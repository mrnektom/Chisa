const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const zsm = @import("../ast/zs_module.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const sts = @import("symbol_table_stack.zig");
const SymbolTable = sts.SymbolTable;
const type_resolver = @import("type_resolver.zig");
const AnalyzeResult = @import("analyzer.zig").AnalyzeResult;

const OverloadEntry = @import("analyzer.zig").OverloadEntry;
const StructDef = @import("analyzer.zig").StructDef;
const EnumDef = @import("analyzer.zig").EnumDef;
const Error = @import("analyzer.zig").Error;

pub fn analyzeVariable(self: anytype, variable: ast.stmt.ZSVar) Error!Symbol {
    // Resolve type annotation if present and set as expected type
    var annotationType: ?Symbol.ZSTypeNotation = null;
    if (variable.type_annotation) |ta| {
        annotationType = try self.resolveTypeAnnotationFull(ta);
    }

    const savedExpected = self.expectedType;
    if (annotationType) |at| {
        self.expectedType = at;
    }
    const stype = try self.analyzeExpr(variable.expr);
    self.expectedType = savedExpected;

    // Validate type annotation against inferred type
    if (annotationType) |at| {
        if (stype != .unknown and !type_resolver.typesCompatible(at, stype)) {
            const nameStart = self.safeSourceOffset(variable.name.ptr);
            const nameEnd = nameStart + variable.name.len;
            try self.recordErrorAt(nameStart, nameEnd, "Type mismatch: expression type does not match annotation");
        }
    }

    // Use annotation type if present, otherwise inferred type
    const finalType = annotationType orelse stype;

    const sym = Symbol{ .name = variable.name, .assignable = variable.type == .Let, .signature = finalType };
    if (variable.modifiers.exported != null) {
        try self.exports.put(sym.name, sym);
    }
    return sym;
}

pub fn analyzeReassign(self: anytype, reassign: ast.stmt.ZSReassign) Error!void {
    _ = try self.analyzeExpr(reassign.expr);
    switch (reassign.target) {
        .name => |name| {
            const nameStart = self.safeSourceOffset(name.ptr);
            const nameEnd = nameStart + name.len;
            if (self.tableStack.get(name)) |sym| {
                if (!sym.assignable) {
                    try self.recordErrorAt(nameStart, nameEnd, "Cannot reassign const variable");
                }
            } else {
                try self.recordErrorAt(nameStart, nameEnd, "Reference not found");
            }
        },
        .index => |idx| {
            const nameStart = self.safeSourceOffset(idx.subject_name.ptr);
            const nameEnd = nameStart + idx.subject_name.len;
            if (self.tableStack.get(idx.subject_name)) |sym| {
                if (!sym.assignable) {
                    try self.recordErrorAt(nameStart, nameEnd, "Cannot reassign const variable");
                }
                switch (sym.signature) {
                    .pointer => |pt| {
                        try self.indexElemTypes.put(idx.startPos, type_resolver.typeToString(pt.*));
                    },
                    .struct_type => |st| {
                        if (std.mem.eql(u8, st.name, "Pointer") and st.type_args.len > 0) {
                            try self.indexElemTypes.put(idx.startPos, type_resolver.typeToString(st.type_args[0]));
                        }
                    },
                    else => {},
                }
            } else {
                try self.recordErrorAt(nameStart, nameEnd, "Reference not found");
            }
            _ = try self.analyzeExpr(idx.index);
        },
        .field => |f| {
            try analyzeReassignFieldTarget(self, f);
        },
    }
}

pub fn analyzeReassignFieldTarget(self: anytype, f: ast.stmt.ZSReassign.FieldTarget) Error!void {
    switch (f.subject.*) {
        .name => |subjectName| {
            if (self.tableStack.get(subjectName)) |sym| {
                switch (sym.signature) {
                    .struct_type => |st| {
                        var found = false;
                        for (st.fields, 0..) |field, i| {
                            if (std.mem.eql(u8, field.name, f.field_name)) {
                                found = true;
                                try self.fieldIndices.put(f.startPos, @intCast(i));
                                break;
                            }
                        }
                        if (!found) {
                            try self.recordErrorAt(f.startPos, f.startPos + f.field_name.len, "Unknown struct field");
                        }
                    },
                    else => {
                        try self.recordErrorAt(f.startPos, f.startPos + f.field_name.len, "Field access on non-struct type");
                    },
                }
            } else {
                try self.recordErrorAt(f.startPos, f.startPos + f.field_name.len, "Reference not found");
            }
        },
        .field => |inner| try analyzeReassignFieldTarget(self, inner),
        .index => {},
    }
}

pub fn analyzeFunction(self: anytype, function: ast.stmt.ZSFn) Error!Symbol {
    // Skip generic templates — including generic extensions — until they are monomorphized.
    if ((function.type_params.len > 0 or function.receiver_type_params.len > 0) and self.typeParamBindings == null) {
        return Symbol{
            .name = function.name,
            .assignable = false,
            .signature = .unknown,
        };
    }

    const retType = if (function.ret) |r| try self.resolveTypeAnnotationFull(r) else Symbol.ZSTypeNotation.unknown;
    const args = try analyzeFnArgs(self, function.args);

    // Heap-allocate the return type to avoid dangling pointer
    const retPtr = try self.allocator.create(Symbol.ZSTypeNotation);
    retPtr.* = retType;
    try self.allocatedTypes.append(self.allocator, retPtr);

    if (function.body) |body| {
        var scope = SymbolTable.init(self.allocator);
        defer scope.deinit();
        try self.tableStack.enterScope(&scope);
        const savedFnReturnType = self.currentFnReturnType;
        self.currentFnReturnType = retType;
        defer self.currentFnReturnType = savedFnReturnType;
        // Inject 'this' for extension functions
        if (function.receiver_type) |_| {
            const thisType: Symbol.ZSTypeNotation = if (self.structDefs.get(function.receiver_type.?)) |sd| blk: {
                const fields = try self.allocator.alloc(sig.ZSStructField, sd.fields.len);
                try self.allocatedStructFields.append(self.allocator, fields);
                for (sd.fields, 0..) |f, i| {
                    const ft = try self.resolveTypeAnnotationFull(f.type);
                    fields[i] = .{ .name = f.name, .type = ft };
                }
                break :blk Symbol.ZSTypeNotation{ .struct_type = .{ .name = sd.name, .fields = fields, .type_args = &.{} } };
            } else if (self.scalarDefs.get(function.receiver_type.?)) |scalarType| blk: {
                break :blk scalarType;
            } else if (self.enumDefs.get(function.receiver_type.?)) |ed| blk: {
                // For generic enums, instantiate with type args from active bindings.
                if (ed.type_params.len > 0) {
                    if (self.typeParamBindings) |bindings| {
                        const resolvedArgs = try self.allocator.alloc(Symbol.ZSTypeNotation, ed.type_params.len);
                        try self.allocatedTypeSlices.append(self.allocator, resolvedArgs);
                        var allFound = true;
                        for (ed.type_params, 0..) |tp, i| {
                            var found = false;
                            for (bindings.typeParams, 0..) |bp, j| {
                                if (std.mem.eql(u8, bp, tp)) {
                                    resolvedArgs[i] = try type_resolver.resolveTypeAnnotationFull(self, .{ .reference = bindings.bindings[j] });
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) {
                                allFound = false;
                                break;
                            }
                        }
                        if (allFound) {
                            break :blk try type_resolver.instantiateEnumFromResolved(self, ed, resolvedArgs);
                        }
                    }
                }
                break :blk try self.buildEnumType(ed);
            } else if (self.monomorphizedEnums.get(function.receiver_type.?)) |med| blk: {
                break :blk Symbol.ZSTypeNotation{ .enum_type = .{
                    .name = med.mangledName,
                    .variants = med.variants,
                    .type_args = &.{},
                } };
            } else Symbol.ZSTypeNotation.unknown;
            try self.tableStack.put(.{
                .name = "this",
                .assignable = false,
                .signature = thisType,
            });
        }
        // Add args as symbols in the function scope
        for (function.args) |arg| {
            const argType = if (arg.type) |t| try self.resolveTypeAnnotationFull(t) else Symbol.ZSTypeNotation.unknown;
            try self.tableStack.put(.{
                .name = arg.name,
                .assignable = true,
                .signature = argType,
            });
        }
        const savedExpected = self.expectedType;
        if (retType != .unknown) {
            self.expectedType = retType;
        }
        _ = try self.analyzeExpr(body);
        self.expectedType = savedExpected;
        _ = try self.tableStack.exitScope();
    }

    const sym = Symbol{
        .name = function.name,
        .assignable = false,
        .signature = Symbol.ZSTypeNotation{
            .function = .{
                .ret = retPtr,
                .args = args,
            },
        },
    };
    if (function.modifiers.exported != null) {
        try self.exports.put(sym.name, sym);
    }
    return sym;
}

pub fn analyzeFnArgs(self: anytype, args: []ast.stmt.ZSFn.Arg) Error![]sig.ZSFnArg {
    const result = try self.allocator.alloc(sig.ZSFnArg, args.len);
    try self.allocatedFnArgs.append(self.allocator, result);
    for (args, 0..) |arg, i| {
        const argType = if (arg.type) |t| try self.resolveTypeAnnotationFull(t) else Symbol.ZSTypeNotation.unknown;
        result[i] = .{ .name = arg.name, .type = argType };
    }
    return result;
}

pub fn analyzeModule(self: anytype, module: zsm.ZSModule) Error!void {
    for (module.ast) |node| {
        if (try analyzeNode(self, node)) |symbol| {
            try self.tableStack.put(symbol);
        }
    }
}

pub fn analyzeNode(self: anytype, node: ast.ZSAstNode) Error!?Symbol {
    return switch (node) {
        .stmt => try analyzeStmt(self, node.stmt),
        .expr => b: {
            _ = try self.analyzeExpr(node.expr);
            break :b null;
        },
        .import_decl => try analyzeImport(self, node.import_decl),
        .export_from => b: {
            try analyzeExportFrom(self, node.export_from);
            break :b null;
        },
        .use_decl => b: {
            try self.analyzeUse(node.use_decl);
            break :b null;
        },
        .when_decl, .target_decl => null, // consumed by preprocessor
    };
}

pub fn analyzeImport(self: anytype, imp: ast.ZSImport) Error!?Symbol {
    // Look up dependency analysis results
    if (self.deps.get(imp.path)) |depResult| {
        for (imp.symbols) |sym| {
            const localName = sym.alias orelse sym.name;
            if (depResult.exports.get(sym.name)) |exportedSym| {
                try self.tableStack.put(.{
                    .name = localName,
                    .assignable = exportedSym.assignable,
                    .signature = exportedSym.signature,
                });
            } else if (depResult.exportedEnumDefs.get(sym.name)) |ed| {
                // Import an exported enum definition
                if (!self.enumDefs.contains(localName)) {
                    try self.enumDefs.put(localName, ed);
                }
            } else if (depResult.exportedStructDefs.get(sym.name)) |sd| {
                // Import an exported struct definition
                if (!self.structDefs.contains(localName)) {
                    try self.structDefs.put(localName, sd);
                }
            } else if (depResult.genericFns.get(sym.name)) |gfn| {
                // Import a generic function definition
                if (!self.genericFns.contains(localName)) {
                    try self.genericFns.put(localName, gfn);
                }
                // Also put a placeholder in scope so references resolve
                try self.tableStack.put(.{ .name = localName, .assignable = false, .signature = .unknown });
            } else if (depResult.overloads.get(sym.name)) |entries| {
                // Import overloaded function
                const gop = try self.overloads.getOrPut(localName);
                if (!gop.found_existing) {
                    gop.value_ptr.* = try std.ArrayList(OverloadEntry).initCapacity(self.allocator, 2);
                }
                for (entries.items) |ov| {
                    try gop.value_ptr.append(self.allocator, ov);
                }
            } else {
                try self.recordErrorAt(imp.startPos, imp.endPos, "Imported symbol not found in module");
            }
        }
    } else {
        try self.recordErrorAt(imp.startPos, imp.endPos, "Module not found");
    }
    return null;
}

pub fn analyzeExportFrom(self: anytype, ef: ast.ZSExportFrom) Error!void {
    if (self.deps.get(ef.path)) |depResult| {
        for (ef.symbols) |sym| {
            const localName = sym.alias orelse sym.name;
            // Re-export functions/variables
            if (depResult.exports.get(sym.name)) |exportedSym| {
                // Add to current scope so this module can use it
                try self.tableStack.put(.{
                    .name = localName,
                    .assignable = exportedSym.assignable,
                    .signature = exportedSym.signature,
                });
                // Re-export under local name
                try self.exports.put(localName, .{
                    .name = localName,
                    .assignable = exportedSym.assignable,
                    .signature = exportedSym.signature,
                });
            }
            // Re-export struct definitions
            if (depResult.exportedStructDefs.get(sym.name)) |sd| {
                try self.structDefs.put(localName, sd);
                try self.exportedStructDefs.put(localName, sd);
            }
            // Re-export enum definitions
            if (depResult.exportedEnumDefs.get(sym.name)) |ed| {
                try self.enumDefs.put(localName, ed);
                try self.exportedEnumDefs.put(localName, ed);
            }
            // Re-export overloads
            if (depResult.overloads.get(sym.name)) |entries| {
                const gop = try self.overloads.getOrPut(localName);
                if (!gop.found_existing) {
                    gop.value_ptr.* = try std.ArrayList(OverloadEntry).initCapacity(self.allocator, 2);
                }
                for (entries.items) |ov| {
                    try gop.value_ptr.append(self.allocator, ov);
                }
            }
            // Re-export generic function definitions
            if (depResult.genericFns.get(sym.name)) |gfn| {
                try self.genericFns.put(localName, gfn);
            }
        }
    } else {
        try self.recordErrorAt(ef.startPos, ef.endPos, "Module not found");
    }
}

pub fn analyzeStmt(self: anytype, stmt: ast.stmt.ZSStmt) Error!?Symbol {
    return switch (stmt) {
        .variable => try analyzeVariable(self, stmt.variable),
        .function => try analyzeFunction(self, stmt.function),
        .reassign => {
            try analyzeReassign(self, stmt.reassign);
            return null;
        },
        .struct_decl => {
            // Struct definitions are handled in the pre-pass (registerStructs)
            return null;
        },
        .enum_decl => {
            // Enum definitions are handled in the pre-pass (registerEnums)
            return null;
        },
        .scalar_decl => {
            // Scalar declarations are handled in the pre-pass (registerScalars)
            return null;
        },
        .type_alias => {
            // Type aliases are handled in the pre-pass (registerTypeAliases)
            return null;
        },
        .asm_block => |ab| {
            // Analyze input expressions
            for (ab.inputs) |inp| {
                _ = try self.analyzeExpr(inp.expr);
            }
            // Declare output variables in enclosing scope
            for (ab.outputs) |out| {
                try self.tableStack.put(.{
                    .name = out.name,
                    .assignable = true,
                    .signature = Symbol.ZSTypeNotation.number,
                });
            }
            return null;
        },
    };
}
