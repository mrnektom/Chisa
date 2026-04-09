const std = @import("std");
const ir = @import("zsir.zig");
const zsm = @import("../ast/zs_module.zig");
const ast = @import("../ast/ast_node.zig");
const Analyzer = @import("../analyzer/analyzer.zig");
const sig = @import("../analyzer/symbol_signature.zig");
const Symbol = @import("../analyzer/symbol.zig");
const Self = @This();

pub const Error = error{} || std.mem.Allocator.Error || std.fmt.ParseIntError;

/// Represents a single captured variable in a lambda closure.
/// srcName/outerIrName are borrowed (valid for generate() lifetime).
/// paramName is allocPrint-owned and freed in lambdaCaptureMap cleanup.
const CaptureEntry = struct {
    srcName: []const u8, // source identifier (e.g. "acc")
    outerIrName: []const u8, // IR temp in outer scope (e.g. "x3")
    paramName: []const u8, // hidden leading param in lambda fn (e.g. "__cap_0")
};

fn callResolutionKey(startPos: usize, endPos: usize) usize {
    return std.hash.Wyhash.hash(0, std.mem.asBytes(&[_]usize{ startPos, endPos }));
}

instructions: *std.ArrayList(ir.ZSIR),
topLevelInstructions: *std.ArrayList(ir.ZSIR),
allocator: std.mem.Allocator,
nameCount: usize = 0,
varNames: std.StringHashMap([]const u8),
resolutions: *const std.AutoHashMap(usize, []const u8),
overloadedNames: *const std.StringHashMap(void),
fieldIndices: *const std.AutoHashMap(usize, u32),
enumInits: *const std.AutoHashMap(usize, Analyzer.EnumInitInfo),
derefTypes: *const std.AutoHashMap(usize, []const u8),
indexElemTypes: *const std.AutoHashMap(usize, []const u8),
arrayLiteralElemTypes: *const std.AutoHashMap(usize, []const u8),
monomorphizedFunctions: []const ast.stmt.ZSFn,
structInitResolutions: *const std.AutoHashMap(usize, []const u8),
monomorphizedEnums: ?*const std.StringHashMap(Analyzer.MonomorphizedEnumDef),
matchEnumNames: ?*const std.AutoHashMap(usize, []const u8),
extensionCalls: ?*const std.AutoHashMap(usize, void),
lambdaNames: ?*const std.AutoHashMap(usize, []const u8),
lambdaTypes: ?*const std.AutoHashMap(usize, sig.ZSType),
safeNavInfo: ?*const std.AutoHashMap(usize, Analyzer.SafeNavInfo),
// Closure capture state — set only while inside generateLambda body gen
outerVarNamesForCapture: ?*const std.StringHashMap([]const u8) = null,
currentLambdaCaptures: ?*std.ArrayList(CaptureEntry) = null,
// Set of variable names that are captured-by-reference inside the current lambda
// (these hold pointers, so reads need deref_op and writes need store_ptr)
capturedVarNamesSet: ?*std.StringHashMap(void) = null,
// Maps lambda fn name → owned slice of CaptureEntry (for call-site prepending)
lambdaCaptureMap: std.StringHashMap([]CaptureEntry),

pub const IrGenContext = struct {
    module: *const zsm.ZSModule,
    allocator: std.mem.Allocator,
    resolutions: *const std.AutoHashMap(usize, []const u8),
    overloadedNames: *const std.StringHashMap(void),
    fieldIndices: *const std.AutoHashMap(usize, u32),
    enumInits: *const std.AutoHashMap(usize, Analyzer.EnumInitInfo),
    derefTypes: *const std.AutoHashMap(usize, []const u8),
    indexElemTypes: *const std.AutoHashMap(usize, []const u8),
    arrayLiteralElemTypes: *const std.AutoHashMap(usize, []const u8),
    monomorphizedFunctions: []const ast.stmt.ZSFn,
    structInitResolutions: *const std.AutoHashMap(usize, []const u8),
    importedVarNames: ?*const std.StringHashMap([]const u8) = null,
    monomorphizedEnums: ?*const std.StringHashMap(Analyzer.MonomorphizedEnumDef) = null,
    matchEnumNames: ?*const std.AutoHashMap(usize, []const u8) = null,
    extensionCalls: ?*const std.AutoHashMap(usize, void) = null,
    lambdaNames: ?*const std.AutoHashMap(usize, []const u8) = null,
    lambdaTypes: ?*const std.AutoHashMap(usize, sig.ZSType) = null,
    safeNavInfo: ?*const std.AutoHashMap(usize, Analyzer.SafeNavInfo) = null,
};

pub const IrGenResult = struct {
    instructions: ir.ZSIRInstructions,
    varNames: std.StringHashMap([]const u8),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        self.instructions.deinit(allocator);
        self.varNames.deinit();
    }
};

pub fn generate(ctx: IrGenContext) !IrGenResult {
    const allocator = ctx.allocator;
    var instructions = try std.ArrayList(ir.ZSIR).initCapacity(allocator, 5);
    defer instructions.deinit(allocator);

    var varNames = std.StringHashMap([]const u8).init(allocator);
    // Pre-populate with imported variable mappings
    if (ctx.importedVarNames) |imports| {
        var it = imports.iterator();
        while (it.next()) |entry| {
            try varNames.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }

    var irGen = Self{
        .instructions = &instructions,
        .topLevelInstructions = &instructions,
        .allocator = allocator,
        .varNames = varNames,
        .resolutions = ctx.resolutions,
        .overloadedNames = ctx.overloadedNames,
        .fieldIndices = ctx.fieldIndices,
        .enumInits = ctx.enumInits,
        .derefTypes = ctx.derefTypes,
        .indexElemTypes = ctx.indexElemTypes,
        .arrayLiteralElemTypes = ctx.arrayLiteralElemTypes,
        .monomorphizedFunctions = ctx.monomorphizedFunctions,
        .structInitResolutions = ctx.structInitResolutions,
        .monomorphizedEnums = ctx.monomorphizedEnums,
        .matchEnumNames = ctx.matchEnumNames,
        .extensionCalls = ctx.extensionCalls,
        .lambdaNames = ctx.lambdaNames,
        .lambdaTypes = ctx.lambdaTypes,
        .safeNavInfo = ctx.safeNavInfo,
        .lambdaCaptureMap = std.StringHashMap([]CaptureEntry).init(allocator),
    };
    // Cleanup lambdaCaptureMap on both success and error paths
    defer {
        var mapIter = irGen.lambdaCaptureMap.iterator();
        while (mapIter.next()) |entry| {
            // paramName strings are owned by fn_def.argNames; freed by fn_def.deinit
            allocator.free(entry.value_ptr.*);
        }
        irGen.lambdaCaptureMap.deinit();
    }

    // Generate IR for monomorphized generic enums before other nodes
    // so enum_decl instructions are visible to match/init lookups
    if (irGen.monomorphizedEnums) |me| {
        var iter = me.iterator();
        while (iter.next()) |entry| {
            const def = entry.value_ptr.*;
            const variants = try allocator.alloc(ir.ZSIREnumVariantDef, def.variants.len);
            for (def.variants, 0..) |v, i| {
                variants[i] = .{
                    .name = v.name,
                    .tag = @intCast(i),
                    .payloadType = if (v.payload_type) |pt| typeToString(pt) else null,
                };
            }
            try instructions.append(allocator, ir.ZSIR{ .enum_decl = .{
                .name = def.mangledName,
                .variants = variants,
            } });
        }
    }

    for (ctx.module.ast) |node| {
        _ = try irGen.generateNode(node);
    }

    // Generate IR for monomorphized generic functions
    for (irGen.monomorphizedFunctions) |func| {
        _ = try irGen.generateFunction(func);
    }

    return .{
        .instructions = .{ .instructions = try allocator.dupe(ir.ZSIR, instructions.items) },
        .varNames = irGen.varNames,
    };
}

const computeMangledName = @import("ZenScript").MangleHelpers.computeMangledName;

/// Returns an owned (allocated) IR type name string for the given AST type annotation.
/// Generic types like `Either<FsError, String>` produce mangled names like `Either__FsError_String`.
fn typeAnnotationToIrTypeName(allocator: std.mem.Allocator, t: ast.ZSTypeNotation) ![]const u8 {
    return switch (t) {
        .reference => |ref| try allocator.dupe(u8, ref),
        .generic => |g| blk: {
            const typeArgNames = try allocator.alloc([]const u8, g.type_args.len);
            defer allocator.free(typeArgNames);
            for (g.type_args, 0..) |ta, i| {
                typeArgNames[i] = try typeAnnotationToIrTypeName(allocator, ta);
            }
            defer for (typeArgNames) |n| allocator.free(n);
            break :blk try computeMangledName(allocator, g.name, typeArgNames);
        },
        .array => try allocator.dupe(u8, "pointer"),
        .fn_type => try allocator.dupe(u8, "function"),
    };
}

fn generateNode(self: *Self, node: ast.ZSAstNode) ![]const u8 {
    return switch (node) {
        .stmt => try self.generateStmt(node.stmt),
        .expr => self.generateExpr(node.expr),
        .import_decl => |imp| try self.generateImport(imp),
        .export_from => |ef| try self.generateExportFrom(ef),
        .use_decl => "", // use declarations don't generate IR
        .when_decl, .target_decl => "", // consumed by preprocessor
    };
}

fn generateExportFrom(self: *Self, ef: ast.ZSExportFrom) ![]const u8 {
    // export_from acts as an import at the IR level
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{ .module_init = ir.ZSIRModuleInit{ .name = ef.path } },
    );
    return "";
}

fn generateImport(self: *Self, imp: ast.ZSImport) ![]const u8 {
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{ .module_init = ir.ZSIRModuleInit{ .name = imp.path } },
    );
    return "";
}

fn generateStmt(self: *Self, stmt: ast.stmt.ZSStmt) ![]const u8 {
    return switch (stmt) {
        .variable => try self.generateVariable(stmt.variable),
        .function => try self.generateFunction(stmt.function),
        .reassign => try self.generateReassign(stmt.reassign),
        .struct_decl => "", // Struct declarations don't generate IR instructions
        .enum_decl => try self.generateEnumDecl(stmt.enum_decl),
        .scalar_decl => "", // Scalar declarations don't generate IR instructions
        .type_alias => "", // Type aliases don't generate IR
        .asm_block => try self.generateAsmBlock(stmt.asm_block),
    };
}

fn generateExpr(self: *Self, expr: ast.expr.ZSExpr) Error![]const u8 {
    return switch (expr) {
        .number => self.generateNumberAssign(expr.number),
        .string => self.generateStringAssign(expr.string),
        .char => self.generateCharAssign(expr.char),
        .boolean => self.generateBooleanAssign(expr.boolean),
        .call => self.generateCallOrIntrinsic(expr.call),
        .reference => try self.generateReference(expr.reference),
        .if_expr => self.generateIfExpr(expr.if_expr),
        .while_expr => self.generateWhileExpr(expr.while_expr),
        .for_expr => self.generateForExpr(expr.for_expr),
        .binary => self.generateBinary(expr.binary),
        .unary => self.generateUnary(expr.unary),
        .block => self.generateBlock(expr.block),
        .return_expr => self.generateReturn(expr.return_expr),
        .break_expr => self.generateBreak(),
        .continue_expr => self.generateContinue(),
        .struct_init => self.generateStructInit(expr.struct_init),
        .field_access => self.generateFieldAccess(expr.field_access),
        .array_literal => self.generateArrayLiteral(expr.array_literal),
        .index_access => self.generateIndexAccess(expr.index_access),
        .enum_init => self.generateEnumInit(expr.enum_init),
        .match_expr => self.generateMatchExpr(expr.match_expr),
        .lambda => self.generateLambda(expr.lambda),
        .safe_nav => self.generateSafeNav(expr.safe_nav),
    };
}

fn generateCallOrIntrinsic(self: *Self, call: ast.expr.ZSCall) Error![]const u8 {
    // Check for ptr/deref intrinsics
    const subject = call.subject.*;
    if (subject == .reference) {
        const name = subject.reference.name;
        if (std.mem.eql(u8, name, "ptr") and call.arguments.len == 1) {
            const operand = try self.generateExpr(call.arguments[0]);
            const resultName = try self.generateName();
            try self.instructions.append(self.allocator, ir.ZSIR{ .ptr_op = .{
                .resultName = resultName,
                .operand = operand,
            } });
            return resultName;
        }
        if (std.mem.eql(u8, name, "deref") and call.arguments.len == 1) {
            const operand = try self.generateExpr(call.arguments[0]);
            const resultName = try self.generateName();
            const pointeeType = self.derefTypes.get(call.startPos) orelse "number";
            try self.instructions.append(self.allocator, ir.ZSIR{ .deref_op = .{
                .resultName = resultName,
                .operand = operand,
                .pointeeType = pointeeType,
            } });
            return resultName;
        }
    }
    return self.generateCall(call);
}

fn generateCall(self: *Self, call: ast.expr.ZSCall) Error![]const u8 {
    // Check if this is an extension function call
    const isExtCall = if (self.extensionCalls) |ec| ec.contains(callResolutionKey(call.startPos, call.endPos)) else false;

    var callerName: []const u8 = undefined;
    var argNames: [][]const u8 = undefined;

    if (isExtCall and call.subject.* == .field_access) {
        // Generate receiver as first arg
        const fa = call.subject.*.field_access;
        const receiverName = try self.generateExpr(fa.subject.*);
        argNames = try self.allocator.alloc([]const u8, call.arguments.len + 1);
        argNames[0] = receiverName;
        for (call.arguments, 0..) |arg, i| {
            argNames[i + 1] = try self.generateExpr(arg);
        }
        callerName = fa.field; // will be overridden by resolution
    } else {
        callerName = try self.generateExpr(call.subject.*);
        argNames = try self.allocator.alloc([]const u8, call.arguments.len);
        for (call.arguments, 0..) |arg, i| {
            argNames[i] = try self.generateExpr(arg);
        }
    }

    // Only apply a resolved name when it still matches the callee we are lowering.
    // Chained calls can reuse startPos, so blindly trusting the map can assign the
    // outer call's resolved name to an inner call in the same chain.
    if (self.resolutions.get(callResolutionKey(call.startPos, call.endPos))) |resolvedName| {
        const expectedCallee = switch (call.subject.*) {
            .reference => |ref| ref.name,
            .field_access => |fa| fa.field,
            else => null,
        };
        if (expectedCallee) |name| {
            if (resolvedNameMatchesCallee(resolvedName, name)) {
                callerName = resolvedName;
            }
        } else {
            callerName = resolvedName;
        }
    }

    // If callerName is a capturing lambda, prepend pointers to the captured outer
    // variables as hidden leading arguments (capture-by-reference).
    if (self.lambdaCaptureMap.get(callerName)) |captures| {
        if (captures.len > 0) {
            const newArgs = try self.allocator.alloc([]const u8, captures.len + argNames.len);
            for (captures, 0..) |cap, i| {
                // Emit ptr_op to get address of the captured variable's alloca
                const outerIr = self.varNames.get(cap.srcName) orelse cap.outerIrName;
                const ptrName = try self.generateName();
                try self.instructions.append(self.allocator, ir.ZSIR{ .ptr_op = .{
                    .resultName = ptrName,
                    .operand = outerIr,
                } });
                newArgs[i] = ptrName;
            }
            @memcpy(newArgs[captures.len..], argNames);
            self.allocator.free(argNames);
            argNames = newArgs;
        }
    }

    const resultName = try self.generateName();
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .call = ir.ZSIRCall{
                .resultName = resultName,
                .fnName = callerName,
                .argNames = argNames,
                .startPos = call.startPos,
            },
        },
    );
    return resultName;
}

fn resolvedNameMatchesCallee(resolvedName: []const u8, expectedCallee: []const u8) bool {
    if (std.mem.eql(u8, resolvedName, expectedCallee)) return true;

    var base = resolvedName;

    if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| {
        base = base[dot + 1 ..];
    }
    if (std.mem.indexOf(u8, base, "__")) |idx| {
        base = base[0..idx];
    }
    if (std.mem.indexOfScalar(u8, base, '$')) |idx| {
        base = base[0..idx];
    }

    return std.mem.eql(u8, base, expectedCallee);
}

fn generateReference(self: *Self, reference: ast.expr.ZSReference) Error![]const u8 {
    if (self.varNames.get(reference.name)) |irName| {
        // If this var is a captured-by-reference pointer, emit deref_op to load through it
        if (self.capturedVarNamesSet) |capSet| {
            if (capSet.get(reference.name) != null) {
                const derefName = try self.generateName();
                try self.instructions.append(self.allocator, ir.ZSIR{ .deref_op = .{
                    .resultName = derefName,
                    .operand = irName,
                    .pointeeType = "number",
                } });
                return derefName;
            }
        }
        return irName;
    }
    // Check outer scope for closure capture
    if (self.outerVarNamesForCapture) |outerVars| {
        if (outerVars.get(reference.name)) |outerIrName| {
            if (self.currentLambdaCaptures) |caps| {
                // Return existing capture param if already recorded
                for (caps.items) |cap| {
                    if (std.mem.eql(u8, cap.srcName, reference.name)) {
                        // Emit deref_op to load current value through the pointer
                        const derefName = try self.generateName();
                        try self.instructions.append(self.allocator, ir.ZSIR{ .deref_op = .{
                            .resultName = derefName,
                            .operand = cap.paramName,
                            .pointeeType = "number",
                        } });
                        return derefName;
                    }
                }
                // Record new capture and allocate a hidden param name
                const paramName = try std.fmt.allocPrint(self.allocator, "__cap_{d}", .{caps.items.len});
                try caps.append(self.allocator, .{ .srcName = reference.name, .outerIrName = outerIrName, .paramName = paramName });
                // Mark this var as captured-by-reference in the lambda scope
                if (self.capturedVarNamesSet) |capSet| {
                    try capSet.put(reference.name, {});
                }
                // Also add the pointer param to innerVarNames so future lookups hit the fast path
                try self.varNames.put(reference.name, paramName);
                // Emit deref_op to load current value through the pointer
                const derefName = try self.generateName();
                try self.instructions.append(self.allocator, ir.ZSIR{ .deref_op = .{
                    .resultName = derefName,
                    .operand = paramName,
                    .pointeeType = "number",
                } });
                return derefName;
            }
        }
    }
    return reference.name;
}

fn generateVariable(self: *Self, variable: ast.stmt.ZSVar) ![]const u8 {
    const irName = try self.generateExpr(variable.expr);
    try self.varNames.put(variable.name, irName);
    return irName;
}

fn generateReassign(self: *Self, reassign: ast.stmt.ZSReassign) ![]const u8 {
    const irName = try self.generateExpr(reassign.expr);
    switch (reassign.target) {
        .name => |name| {
            // If the target is a captured-by-reference var, store through the pointer
            if (self.capturedVarNamesSet) |capSet| {
                if (capSet.get(name) != null) {
                    const ptrName = self.varNames.get(name) orelse name;
                    try self.instructions.append(
                        self.allocator,
                        ir.ZSIR{
                            .store_ptr = ir.ZSIRStorePtr{
                                .pointer = ptrName,
                                .value = irName,
                                .pointeeType = "number",
                            },
                        },
                    );
                    return irName;
                }
            }
            const existingName = self.varNames.get(name) orelse name;
            try self.instructions.append(
                self.allocator,
                ir.ZSIR{
                    .store = ir.ZSIRStore{
                        .target = existingName,
                        .value = irName,
                    },
                },
            );
        },
        .index => |idx| {
            const subjectName = self.varNames.get(idx.subject_name) orelse idx.subject_name;
            const indexName = try self.generateExpr(idx.index);
            const elemType = self.indexElemTypes.get(idx.startPos);
            try self.instructions.append(
                self.allocator,
                ir.ZSIR{
                    .index_store = ir.ZSIRIndexStore{
                        .subject = subjectName,
                        .index = indexName,
                        .value = irName,
                        .elemType = elemType,
                    },
                },
            );
        },
        .field => |f| {
            const subjectName = resolveFieldTargetSubject(&f, self);
            try self.instructions.append(
                self.allocator,
                ir.ZSIR{
                    .field_store = ir.ZSIRFieldStore{
                        .subject = subjectName,
                        .field_name = f.field_name,
                        .fieldIndex = self.fieldIndices.get(f.startPos) orelse unreachable,
                        .value = irName,
                    },
                },
            );
        },
    }
    return irName;
}

fn resolveFieldTargetSubject(f: *const ast.stmt.ZSReassign.FieldTarget, self: *Self) []const u8 {
    switch (f.subject.*) {
        .name => |n| return self.varNames.get(n) orelse n,
        .field => |*inner| return resolveFieldTargetSubject(inner, self),
        .index => |idx| return self.varNames.get(idx.subject_name) orelse idx.subject_name,
    }
}

fn generateFunction(self: *Self, func: ast.stmt.ZSFn) ![]const u8 {
    // Skip generic function templates — only monomorphized copies generate IR.
    // Also skip extension methods on generic receiver types (receiver_type_params non-empty).
    if (func.type_params.len > 0 or func.receiver_type_params.len > 0) return "";

    const isExtension = func.receiver_type != null;

    const argTypes = if (isExtension) blk: {
        const at = try self.allocator.alloc([]const u8, func.args.len + 1);
        at[0] = try self.allocator.dupe(u8, func.receiver_type.?);
        for (func.args, 0..) |arg, i| {
            at[i + 1] = if (arg.type) |t| try typeAnnotationToIrTypeName(self.allocator, t) else try self.allocator.dupe(u8, "unknown");
        }
        break :blk at;
    } else blk: {
        const at = try self.allocator.alloc([]const u8, func.args.len);
        for (func.args, 0..) |arg, i| {
            at[i] = if (arg.type) |t| try typeAnnotationToIrTypeName(self.allocator, t) else try self.allocator.dupe(u8, "unknown");
        }
        break :blk at;
    };

    const retType: []const u8 = if (func.ret) |r| try typeAnnotationToIrTypeName(self.allocator, r) else try self.allocator.dupe(u8, "void");
    const external = func.modifiers.external != null;

    // Determine the function name: mangle if overloaded and not external
    // Always allocate an owned copy so IR can free it uniformly
    const fnName = if (isExtension) blk: {
        if (!external and (std.mem.indexOfScalar(u8, func.name, '$') != null or std.mem.indexOfScalar(u8, func.name, '.') != null)) {
            break :blk try self.allocator.dupe(u8, func.name);
        }
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ func.receiver_type.?, func.name });
        if (external) {
            break :blk key;
        } else {
            const mname = try computeMangledName(self.allocator, key, argTypes[1..]);
            self.allocator.free(key);
            break :blk mname;
        }
    } else if (!external and self.overloadedNames.contains(func.name))
        try computeMangledName(self.allocator, func.name, argTypes)
    else
        try self.allocator.dupe(u8, func.name);

    if (func.body) |body| {
        // User-defined function with body — include 'this' for extension functions
        const argNames = if (isExtension) blk: {
            const an = try self.allocator.alloc([]const u8, func.args.len + 1);
            an[0] = try self.allocator.dupe(u8, "this");
            for (func.args, 0..) |arg, i| {
                an[i + 1] = try self.allocator.dupe(u8, arg.name);
            }
            break :blk an;
        } else blk: {
            const an = try self.allocator.alloc([]const u8, func.args.len);
            for (func.args, 0..) |arg, i| {
                an[i] = try self.allocator.dupe(u8, arg.name);
            }
            break :blk an;
        };

        // Generate body instructions into a separate list
        var bodyInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 8);
        defer bodyInstructions.deinit(self.allocator);

        // Save and swap instruction target
        const outerInstructions = self.instructions;
        self.instructions = &bodyInstructions;

        // Save and create new scope for function args
        var innerVarNames = std.StringHashMap([]const u8).init(self.allocator);
        // Copy outer scope
        var outerIter = self.varNames.iterator();
        while (outerIter.next()) |entry| {
            try innerVarNames.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        // Add function args to scope (they reference themselves by name)
        for (func.args) |arg| {
            try innerVarNames.put(arg.name, arg.name);
        }
        const outerVarNames = self.varNames;
        self.varNames = innerVarNames;
        defer {
            // Restore outer state on both success and error paths
            self.instructions = outerInstructions;
            var modifiedInner = self.varNames;
            self.varNames = outerVarNames;
            modifiedInner.deinit();
        }

        const bodyResult = try self.generateExpr(body);

        // For expression bodies (not blocks), add an implicit return
        if (body != .block) {
            try self.instructions.append(
                self.allocator,
                ir.ZSIR{
                    .ret = ir.ZSIRRet{
                        .value = bodyResult,
                        .startPos = body.start(),
                    },
                },
            );
        }

        // Restore instructions to outer before appending fn_def
        self.instructions = outerInstructions;

        try self.instructions.append(
            self.allocator,
            ir.ZSIR{
                .fn_def = ir.ZSIRFnDef{
                    .name = fnName,
                    .argTypes = argTypes,
                    .argNames = argNames,
                    .retType = retType,
                    .body = try self.allocator.dupe(ir.ZSIR, bodyInstructions.items),
                    .startPos = body.start(),
                },
            },
        );
    } else {
        // External/forward declaration
        try self.instructions.append(
            self.allocator,
            ir.ZSIR{
                .fn_decl = ir.ZSIRFnDecl{
                    .name = fnName,
                    .argTypes = argTypes,
                    .retType = retType,
                    .external = external,
                },
            },
        );
    }
    return "";
}

fn generateIfExpr(self: *Self, ifExpr: ast.expr.ZSIfExpr) Error![]const u8 {
    const condName = try self.generateExpr(ifExpr.condition.*);

    // Generate then body
    var thenInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer thenInstructions.deinit(self.allocator);
    const outerInstructions = self.instructions;
    self.instructions = &thenInstructions;
    errdefer self.instructions = outerInstructions;
    const thenResult = try self.generateExpr(ifExpr.then_branch.*);
    self.instructions = outerInstructions;

    // Generate else body
    var elseInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer elseInstructions.deinit(self.allocator);
    var elseResult: ?[]const u8 = null;
    if (ifExpr.else_branch) |eb| {
        self.instructions = &elseInstructions;
        errdefer self.instructions = outerInstructions;
        elseResult = try self.generateExpr(eb.*);
        self.instructions = outerInstructions;
    }

    // Determine if branches produce values (non-empty result, not a block with returns)
    const thenHasValue = thenResult.len > 0;
    const elseHasValue = if (elseResult) |er| er.len > 0 else false;
    const hasResult = thenHasValue and elseHasValue;

    var resultName: ?[]const u8 = null;
    if (hasResult) {
        resultName = try self.generateName();
    }

    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .branch = ir.ZSIRBranch{
                .condition = condName,
                .thenBody = try self.allocator.dupe(ir.ZSIR, thenInstructions.items),
                .elseBody = try self.allocator.dupe(ir.ZSIR, elseInstructions.items),
                .resultName = resultName,
                .thenResult = if (thenHasValue) thenResult else null,
                .elseResult = elseResult,
                .startPos = ifExpr.startPos,
            },
        },
    );
    return resultName orelse "";
}

fn generateBinary(self: *Self, binary: ast.expr.ZSBinary) Error![]const u8 {
    const op = binary.op;

    // Short-circuit logical operators: desugar to branch
    if (std.mem.eql(u8, op, "&&")) {
        return self.generateLogicalAnd(binary);
    }
    if (std.mem.eql(u8, op, "||")) {
        return self.generateLogicalOr(binary);
    }

    const lhsName = try self.generateExpr(binary.lhs.*);
    const rhsName = try self.generateExpr(binary.rhs.*);
    const resultName = try self.generateName();

    const isCompare = std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
        std.mem.eql(u8, op, ">") or std.mem.eql(u8, op, "<") or
        std.mem.eql(u8, op, ">=") or std.mem.eql(u8, op, "<=");

    if (isCompare) {
        try self.instructions.append(
            self.allocator,
            ir.ZSIR{
                .compare = ir.ZSIRCompare{
                    .resultName = resultName,
                    .lhs = lhsName,
                    .rhs = rhsName,
                    .op = op,
                },
            },
        );
    } else {
        try self.instructions.append(
            self.allocator,
            ir.ZSIR{
                .arith = ir.ZSIRArith{
                    .resultName = resultName,
                    .lhs = lhsName,
                    .rhs = rhsName,
                    .op = op,
                },
            },
        );
    }
    return resultName;
}

// a && b: if a then b else false
fn generateLogicalAnd(self: *Self, binary: ast.expr.ZSBinary) Error![]const u8 {
    const condName = try self.generateExpr(binary.lhs.*);

    // Then body: evaluate rhs
    var thenInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer thenInstructions.deinit(self.allocator);
    const outerInstructions = self.instructions;
    self.instructions = &thenInstructions;
    errdefer self.instructions = outerInstructions;
    const thenResult = try self.generateExpr(binary.rhs.*);
    self.instructions = outerInstructions;

    // Else body: produce false
    var elseInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 1);
    defer elseInstructions.deinit(self.allocator);
    self.instructions = &elseInstructions;
    errdefer self.instructions = outerInstructions;
    const elseResult = try self.generateBooleanAssign(.{ .value = false, .startPos = 0, .endPos = 0 });
    self.instructions = outerInstructions;

    const resultName = try self.generateName();
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .branch = ir.ZSIRBranch{
                .condition = condName,
                .thenBody = try self.allocator.dupe(ir.ZSIR, thenInstructions.items),
                .elseBody = try self.allocator.dupe(ir.ZSIR, elseInstructions.items),
                .resultName = resultName,
                .thenResult = thenResult,
                .elseResult = elseResult,
                .startPos = binary.startPos,
            },
        },
    );
    return resultName;
}

// a || b: if a then true else b
fn generateLogicalOr(self: *Self, binary: ast.expr.ZSBinary) Error![]const u8 {
    const condName = try self.generateExpr(binary.lhs.*);

    // Then body: produce true
    var thenInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 1);
    defer thenInstructions.deinit(self.allocator);
    const outerInstructions = self.instructions;
    self.instructions = &thenInstructions;
    errdefer self.instructions = outerInstructions;
    const thenResult = try self.generateBooleanAssign(.{ .value = true, .startPos = 0, .endPos = 0 });
    self.instructions = outerInstructions;

    // Else body: evaluate rhs
    var elseInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer elseInstructions.deinit(self.allocator);
    self.instructions = &elseInstructions;
    errdefer self.instructions = outerInstructions;
    const elseResult = try self.generateExpr(binary.rhs.*);
    self.instructions = outerInstructions;

    const resultName = try self.generateName();
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .branch = ir.ZSIRBranch{
                .condition = condName,
                .thenBody = try self.allocator.dupe(ir.ZSIR, thenInstructions.items),
                .elseBody = try self.allocator.dupe(ir.ZSIR, elseInstructions.items),
                .resultName = resultName,
                .thenResult = thenResult,
                .elseResult = elseResult,
                .startPos = binary.startPos,
            },
        },
    );
    return resultName;
}

fn generateWhileExpr(self: *Self, whileExpr: ast.expr.ZSWhileExpr) Error![]const u8 {
    // Generate condition instructions into a separate list
    var condInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer condInstructions.deinit(self.allocator);
    const outerInstructions = self.instructions;
    self.instructions = &condInstructions;
    errdefer self.instructions = outerInstructions;
    const condName = try self.generateExpr(whileExpr.condition.*);
    self.instructions = outerInstructions;

    // Generate body instructions
    var bodyInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 8);
    defer bodyInstructions.deinit(self.allocator);
    self.instructions = &bodyInstructions;
    _ = try self.generateExpr(whileExpr.body.*);
    self.instructions = outerInstructions;

    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .loop = ir.ZSIRLoop{
                .condition = try self.allocator.dupe(ir.ZSIR, condInstructions.items),
                .conditionName = condName,
                .body = try self.allocator.dupe(ir.ZSIR, bodyInstructions.items),
            },
        },
    );
    return "";
}

fn generateForExpr(self: *Self, forExpr: ast.expr.ZSForExpr) Error![]const u8 {
    // Generate init statement (e.g. let i = 0) into current instructions
    _ = try self.generateNode(forExpr.init.*);

    // Generate condition instructions into a separate list
    var condInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer condInstructions.deinit(self.allocator);
    const outerInstructions = self.instructions;
    self.instructions = &condInstructions;
    errdefer self.instructions = outerInstructions;
    const condName = try self.generateExpr(forExpr.condition.*);
    self.instructions = outerInstructions;

    // Generate body instructions
    var bodyInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 8);
    defer bodyInstructions.deinit(self.allocator);
    self.instructions = &bodyInstructions;
    _ = try self.generateExpr(forExpr.body.*);
    self.instructions = outerInstructions;

    // Generate step instructions separately (for correct continue behavior)
    var stepInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer stepInstructions.deinit(self.allocator);
    self.instructions = &stepInstructions;
    _ = try self.generateNode(forExpr.step.*);
    self.instructions = outerInstructions;

    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .loop = ir.ZSIRLoop{
                .condition = try self.allocator.dupe(ir.ZSIR, condInstructions.items),
                .conditionName = condName,
                .body = try self.allocator.dupe(ir.ZSIR, bodyInstructions.items),
                .step = try self.allocator.dupe(ir.ZSIR, stepInstructions.items),
            },
        },
    );
    return "";
}

fn generateBreak(self: *Self) Error![]const u8 {
    try self.instructions.append(self.allocator, ir.ZSIR{ .break_stmt = .{} });
    return "";
}

fn generateContinue(self: *Self) Error![]const u8 {
    try self.instructions.append(self.allocator, ir.ZSIR{ .continue_stmt = .{} });
    return "";
}

fn generateUnary(self: *Self, unary: ast.expr.ZSUnary) Error![]const u8 {
    const operandName = try self.generateExpr(unary.operand.*);
    const resultName = try self.generateName();
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .not_op = ir.ZSIRNot{
                .resultName = resultName,
                .operand = operandName,
            },
        },
    );
    return resultName;
}

fn generateBlock(self: *Self, block: ast.expr.ZSBlock) Error![]const u8 {
    var lastResult: []const u8 = "";
    for (block.stmts) |node| {
        lastResult = try self.generateNode(node);
    }
    return lastResult;
}

fn generateReturn(self: *Self, ret: ast.expr.ZSReturn) Error![]const u8 {
    var valueName: ?[]const u8 = null;
    if (ret.value) |v| {
        valueName = try self.generateExpr(v.*);
    }
    try self.instructions.append(
        self.allocator,
        ir.ZSIR{
            .ret = ir.ZSIRRet{
                .value = valueName,
                .startPos = ret.startPos,
            },
        },
    );
    return "";
}

fn generateStructInit(self: *Self, si: ast.expr.ZSStructInit) Error![]const u8 {
    const fields = try self.allocator.alloc(ir.ZSIRFieldValue, si.field_values.len);
    for (si.field_values, 0..) |fv, i| {
        const valueName = try self.generateExpr(fv.value);
        fields[i] = .{ .name = fv.name, .value = valueName };
    }
    const resultName = try self.generateName();
    // Use resolved struct name if available (for generic struct inits like List$number)
    const structName = self.structInitResolutions.get(si.startPos) orelse si.name;
    try self.instructions.append(self.allocator, ir.ZSIR{ .struct_init = .{
        .resultName = resultName,
        .structName = structName,
        .fields = fields,
    } });
    return resultName;
}

fn generateFieldAccess(self: *Self, fa: ast.expr.ZSFieldAccess) Error![]const u8 {
    // Check if this field_access is actually an enum unit variant init
    if (self.enumInits.get(fa.startPos)) |info| {
        const resultName = try self.generateName();
        try self.instructions.append(self.allocator, ir.ZSIR{ .enum_init = .{
            .resultName = resultName,
            .enumName = info.enumName,
            .variantTag = info.variantTag,
            .payload = null,
        } });
        return resultName;
    }

    const subjectName = try self.generateExpr(fa.subject.*);
    const resultName = try self.generateName();
    const fieldIndex = self.fieldIndices.get(fa.startPos) orelse 0;
    try self.instructions.append(self.allocator, ir.ZSIR{ .field_access = .{
        .resultName = resultName,
        .subject = subjectName,
        .field = fa.field,
        .fieldIndex = fieldIndex,
    } });
    return resultName;
}

fn generateNumberAssign(self: *Self, number: ast.expr.ZSNumber) Error![]const u8 {
    return self.generateAssign(ir.ZSIRValue{ .number = try std.fmt.parseInt(i32, number.value, 10) }, number.startPos);
}

fn generateStringAssign(self: *Self, string: ast.expr.ZSString) Error![]const u8 {
    return self.generateAssign(ir.ZSIRValue{ .string = string.value }, string.startPos);
}

fn generateBooleanAssign(self: *Self, boolean: ast.expr.ZSBoolean) Error![]const u8 {
    return self.generateAssign(ir.ZSIRValue{ .boolean = boolean.value }, boolean.startPos);
}

fn generateCharAssign(self: *Self, char: ast.expr.ZSChar) Error![]const u8 {
    return self.generateAssign(ir.ZSIRValue{ .char = char.value }, char.startPos);
}

fn generateArrayLiteral(self: *Self, al: ast.expr.ZSArrayLiteral) Error![]const u8 {
    const elements = try self.allocator.alloc([]const u8, al.elements.len);
    for (al.elements, 0..) |elem, i| {
        elements[i] = try self.generateExpr(elem);
    }
    // Determine element type from analyzer-provided type info
    const elemType: []const u8 = self.arrayLiteralElemTypes.get(al.startPos) orelse "number";
    const resultName = try self.generateName();
    try self.instructions.append(self.allocator, ir.ZSIR{ .array_init = .{
        .resultName = resultName,
        .elementType = elemType,
        .elements = elements,
    } });
    return resultName;
}

fn generateIndexAccess(self: *Self, ia: ast.expr.ZSIndexAccess) Error![]const u8 {
    const subjectName = try self.generateExpr(ia.subject.*);
    const indexName = try self.generateExpr(ia.index.*);
    const resultName = try self.generateName();
    const elemType = self.indexElemTypes.get(ia.startPos);
    try self.instructions.append(self.allocator, ir.ZSIR{ .index_access = .{
        .resultName = resultName,
        .subject = subjectName,
        .index = indexName,
        .elemType = elemType,
    } });
    return resultName;
}

fn generateEnumDecl(self: *Self, ed: ast.stmt.ZSEnum) Error![]const u8 {
    // Skip generic template enums — monomorphized copies are emitted separately
    if (ed.type_params.len > 0) return "";

    const variants = try self.allocator.alloc(ir.ZSIREnumVariantDef, ed.variants.len);
    for (ed.variants, 0..) |v, i| {
        variants[i] = .{
            .name = v.name,
            .tag = @intCast(i),
            .payloadType = if (v.payload_type) |pt| pt.typeName() else null,
        };
    }
    try self.instructions.append(self.allocator, ir.ZSIR{ .enum_decl = .{
        .name = ed.name,
        .variants = variants,
    } });
    return "";
}

fn generateEnumInit(self: *Self, ei: ast.expr.ZSEnumInit) Error![]const u8 {
    // When the analyzer reinterpreted this enum_init as a method call on a variable
    // (because enum_name is a variable, not an enum type), generate a call instead.
    const matchingResolvedName = blk: {
        if (self.resolutions.get(callResolutionKey(ei.startPos, ei.endPos))) |resolvedName| {
            if (resolvedNameMatchesCallee(resolvedName, ei.variant_name)) break :blk resolvedName;
        }
        break :blk null;
    };
    const isReinterpretedCall = blk: {
        if (self.extensionCalls) |ec| {
            if (ec.contains(callResolutionKey(ei.startPos, ei.endPos))) break :blk true;
        }
        if (matchingResolvedName != null) break :blk true;
        break :blk false;
    };
    if (isReinterpretedCall) {
        // The analyzer reinterpreted this enum_init as a method call on a variable.
        // Generate: receiver.method(payload) as an extension call.
        // The receiver name is ei.enum_name, method is ei.variant_name.
        const receiverName = self.varNames.get(ei.enum_name) orelse ei.enum_name;
        const resolvedName = matchingResolvedName orelse ei.variant_name;

        var argNames: [][]const u8 = undefined;
        if (ei.payload) |p| {
            const payloadName = try self.generateExpr(p.*);
            argNames = try self.allocator.alloc([]const u8, 2);
            argNames[0] = receiverName;
            argNames[1] = payloadName;
        } else {
            argNames = try self.allocator.alloc([]const u8, 1);
            argNames[0] = receiverName;
        }

        const resultName = try self.generateName();
        try self.instructions.append(self.allocator, ir.ZSIR{ .call = ir.ZSIRCall{
            .resultName = resultName,
            .fnName = resolvedName,
            .argNames = argNames,
            .startPos = ei.startPos,
        } });
        return resultName;
    }

    // Use the analyzer's enum init info which has the correct (possibly mangled) name
    const initInfo = self.enumInits.get(ei.startPos);
    const enumName = if (initInfo) |info| info.enumName else ei.enum_name;

    // Find the variant tag by looking up the enum declaration in top-level instructions
    var variantTag: u32 = if (initInfo) |info| info.variantTag else 0;
    if (initInfo == null) {
        var tagFound = false;
        for (self.topLevelInstructions.items) |inst| {
            if (inst == .enum_decl and std.mem.eql(u8, inst.enum_decl.name, enumName)) {
                for (inst.enum_decl.variants) |v| {
                    if (std.mem.eql(u8, v.name, ei.variant_name)) {
                        variantTag = v.tag;
                        tagFound = true;
                        break;
                    }
                }
                break;
            }
        }
        if (!tagFound) {
            std.debug.print("Warning: enum variant '{s}.{s}' not found in IR\n", .{ ei.enum_name, ei.variant_name });
        }
    }

    var payloadName: ?[]const u8 = null;
    if (ei.payload) |p| {
        payloadName = try self.generateExpr(p.*);
    }

    const resultName = try self.generateName();
    try self.instructions.append(self.allocator, ir.ZSIR{ .enum_init = .{
        .resultName = resultName,
        .enumName = enumName,
        .variantTag = variantTag,
        .payload = payloadName,
    } });
    return resultName;
}

fn zsSymbolTypeToIrName(t: sig.ZSType) []const u8 {
    return switch (t) {
        .number => "number",
        .boolean => "boolean",
        .char => "char",
        .long => "long",
        .short => "short",
        .byte => "byte",
        .void => "void",
        .function => "function",
        .unknown => "unknown",
        .struct_type => |st| st.name,
        .pointer => "pointer",
        .array_type => "array",
        .enum_type => |et| et.name,
    };
}

fn generateMatchExpr(self: *Self, me: ast.expr.ZSMatchExpr) Error![]const u8 {
    const subjectName = try self.generateExpr(me.subject.*);

    // Use the resolved enum name from the analyzer (handles monomorphized generic enums)
    const enumName: []const u8 = if (self.matchEnumNames) |men|
        (men.get(me.startPos) orelse (if (me.arms.len > 0 and me.arms[0].pattern == .enum_variant) me.arms[0].pattern.enum_variant.enum_name else ""))
    else
        (if (me.arms.len > 0 and me.arms[0].pattern == .enum_variant) me.arms[0].pattern.enum_variant.enum_name else "");

    var irArms = try self.allocator.alloc(ir.ZSIRMatchArm, me.arms.len);

    for (me.arms, 0..) |arm, i| {
        // Resolve variant tag and payload type for enum patterns
        var variantTag: u32 = 0;
        var variantPayloadType: ?[]const u8 = null;
        switch (arm.pattern) {
            .enum_variant => |ev| {
                // First look up in top-level (entry module) enum_decl instructions
                var found = false;
                for (self.topLevelInstructions.items) |inst| {
                    if (inst == .enum_decl and std.mem.eql(u8, inst.enum_decl.name, enumName)) {
                        for (inst.enum_decl.variants) |v| {
                            if (std.mem.eql(u8, v.name, ev.variant_name)) {
                                variantTag = v.tag;
                                variantPayloadType = v.payloadType;
                                found = true;
                                break;
                            }
                        }
                        break;
                    }
                }
                // Fallback: look up from monomorphizedEnums (covers cross-module generic enums)
                if (!found) {
                    if (self.monomorphizedEnums) |monoEnums| {
                        if (monoEnums.get(enumName)) |enumDef| {
                            for (enumDef.variants) |v| {
                                if (std.mem.eql(u8, v.name, ev.variant_name)) {
                                    variantTag = v.tag;
                                    if (v.payload_type) |pt| {
                                        variantPayloadType = zsSymbolTypeToIrName(pt);
                                    }
                                    break;
                                }
                            }
                        }
                    }
                }
            },
            else => {},
        }

        // Generate body instructions into a separate list
        var bodyInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
        defer bodyInstructions.deinit(self.allocator);

        const outerInstructions = self.instructions;
        self.instructions = &bodyInstructions;

        // Create an isolated scope for this arm so bindings/variables don't leak
        const outerVarNames = self.varNames;
        var armVarNames = std.StringHashMap([]const u8).init(self.allocator);
        var outerIter = outerVarNames.iterator();
        while (outerIter.next()) |entry| {
            try armVarNames.put(entry.key_ptr.*, entry.value_ptr.*);
        }
        self.varNames = armVarNames;
        errdefer {
            self.instructions = outerInstructions;
            self.varNames.deinit();
            self.varNames = outerVarNames;
        }

        // If there's a binding (enum variant), add it to varNames
        var bindingIrName: ?[]const u8 = null;
        if (arm.pattern == .enum_variant) {
            if (arm.pattern.enum_variant.binding) |binding| {
                bindingIrName = try self.generateName();
                try self.varNames.put(binding, bindingIrName.?);
            }
        }

        const armResult = try self.generateExpr(arm.body.*);
        self.instructions = outerInstructions;
        self.varNames.deinit();
        self.varNames = outerVarNames;

        const patternKind: ir.ZSIRMatchPatternKind = switch (arm.pattern) {
            .enum_variant => .variant_tag,
            .number_literal => .number_literal,
            .boolean_literal => .boolean_literal,
            .char_literal => .char_literal,
            .string_literal => .string_literal,
            .struct_destructure => .struct_destructure,
        };
        const literalValue: []const u8 = switch (arm.pattern) {
            .number_literal => |v| v,
            .string_literal => |v| v,
            .boolean_literal => |v| if (v) "true" else "false",
            .char_literal => |v| try std.fmt.allocPrint(self.allocator, "{c}", .{v}),
            else => "",
        };

        irArms[i] = .{
            .patternKind = patternKind,
            .variantTag = variantTag,
            .literalValue = literalValue,
            .binding = bindingIrName,
            .bindingType = variantPayloadType,
            .body = try self.allocator.dupe(ir.ZSIR, bodyInstructions.items),
            .resultName = if (armResult.len > 0) armResult else null,
        };
    }

    var elseBody: ?[]ir.ZSIR = null;
    var elseResultName: ?[]const u8 = null;
    if (me.has_else) {
        if (me.else_body) |eb| {
            var elseInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
            defer elseInstructions.deinit(self.allocator);
            const outerInstructions = self.instructions;
            self.instructions = &elseInstructions;
            const elseResult = try self.generateExpr(eb.*);
            self.instructions = outerInstructions;
            elseBody = try self.allocator.dupe(ir.ZSIR, elseInstructions.items);
            elseResultName = if (elseResult.len > 0) elseResult else null;
        }
    }

    const resultName = try self.generateName();
    try self.instructions.append(self.allocator, ir.ZSIR{ .match_expr = .{
        .resultName = resultName,
        .subject = subjectName,
        .enumName = enumName,
        .arms = irArms,
        .has_else = me.has_else,
        .else_body = elseBody,
        .else_result_name = elseResultName,
    } });
    return resultName;
}

fn generateSafeNav(self: *Self, sn: ast.expr.ZSSafeNav) Error![]const u8 {
    const info = if (self.safeNavInfo) |m| m.get(sn.startPos) else null;
    if (info == null) return "";

    const snInfo = info.?;
    const receiverName = try self.generateExpr(sn.receiver.*);

    // Look up Some and None variant tags and payload type for the receiver enum
    var someTag: u32 = 0;
    var noneTag: u32 = 1;
    var someResultTag: u32 = 0;
    var noneResultTag: u32 = 1;
    var somePayloadType: ?[]const u8 = null;

    // Search topLevelInstructions for enum_decl matching receiver enum
    for (self.topLevelInstructions.items) |inst| {
        if (inst == .enum_decl and std.mem.eql(u8, inst.enum_decl.name, snInfo.receiverEnumName)) {
            for (inst.enum_decl.variants) |v| {
                if (std.mem.eql(u8, v.name, "Some")) {
                    someTag = v.tag;
                    somePayloadType = v.payloadType;
                }
                if (std.mem.eql(u8, v.name, "None")) {
                    noneTag = v.tag;
                }
            }
            break;
        }
    }
    // Fallback: monomorphizedEnums
    if (self.monomorphizedEnums) |monoEnums| {
        if (monoEnums.get(snInfo.receiverEnumName)) |ed| {
            for (ed.variants) |v| {
                if (std.mem.eql(u8, v.name, "Some")) {
                    someTag = v.tag;
                    if (v.payload_type) |pt| somePayloadType = zsSymbolTypeToIrName(pt);
                }
                if (std.mem.eql(u8, v.name, "None")) noneTag = v.tag;
            }
        }
        // Look up result enum tags too
        if (monoEnums.get(snInfo.resultEnumName)) |ed| {
            for (ed.variants) |v| {
                if (std.mem.eql(u8, v.name, "Some")) someResultTag = v.tag;
                if (std.mem.eql(u8, v.name, "None")) noneResultTag = v.tag;
            }
        }
    }

    // Build Some arm body: field_access on the payload, optionally wrap in Some
    var someBody = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer someBody.deinit(self.allocator);

    const bindingName = try self.generateName();
    const fieldResultName = try self.generateName();
    try someBody.append(self.allocator, ir.ZSIR{ .field_access = .{
        .resultName = fieldResultName,
        .subject = bindingName,
        .field = sn.field,
        .fieldIndex = snInfo.fieldIndex,
    } });

    const someArmResult: []const u8 = if (snInfo.isFlatMap)
        fieldResultName
    else blk: {
        const wrappedName = try self.generateName();
        try someBody.append(self.allocator, ir.ZSIR{ .enum_init = .{
            .resultName = wrappedName,
            .enumName = snInfo.resultEnumName,
            .variantTag = someResultTag,
            .payload = fieldResultName,
        } });
        break :blk wrappedName;
    };

    // Build None arm body: emit Option.None for the result enum
    var noneBody = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 2);
    defer noneBody.deinit(self.allocator);

    const noneArmResult = try self.generateName();
    try noneBody.append(self.allocator, ir.ZSIR{ .enum_init = .{
        .resultName = noneArmResult,
        .enumName = snInfo.resultEnumName,
        .variantTag = noneResultTag,
        .payload = null,
    } });

    const arms = try self.allocator.alloc(ir.ZSIRMatchArm, 2);
    arms[0] = .{
        .patternKind = .variant_tag,
        .variantTag = someTag,
        .binding = bindingName,
        .bindingType = somePayloadType,
        .body = try self.allocator.dupe(ir.ZSIR, someBody.items),
        .resultName = someArmResult,
    };
    arms[1] = .{
        .patternKind = .variant_tag,
        .variantTag = noneTag,
        .binding = null,
        .bindingType = null,
        .body = try self.allocator.dupe(ir.ZSIR, noneBody.items),
        .resultName = noneArmResult,
    };

    const resultName = try self.generateName();
    try self.instructions.append(self.allocator, ir.ZSIR{ .match_expr = .{
        .resultName = resultName,
        .subject = receiverName,
        .enumName = snInfo.receiverEnumName,
        .arms = arms,
        .has_else = false,
        .else_body = null,
        .else_result_name = null,
    } });
    return resultName;
}

fn generateLambda(self: *Self, lambda: ast.expr.ZSLambda) Error![]const u8 {
    const lambdaName = if (self.lambdaNames) |ln|
        ln.get(lambda.startPos) orelse "__lambda_unknown"
    else
        "__lambda_unknown";
    return self.generateLambdaBody(lambdaName, lambda.startPos, lambda.params, lambda.body.*, lambda.implicit_params_from_context);
}

fn generateLambdaBody(
    self: *Self,
    lambdaName: []const u8,
    startPos: usize,
    params: []const ast.expr.ZSLambdaParam,
    body: ast.expr.ZSExpr,
    implicitParamsFromContext: bool,
) Error![]const u8 {

    // Generate body instructions into a separate list
    var lambdaInstructions = try std.ArrayList(ir.ZSIR).initCapacity(self.allocator, 4);
    defer lambdaInstructions.deinit(self.allocator);

    const outerInstructions = self.instructions;
    self.instructions = &lambdaInstructions;

    // Inner scope contains ONLY explicit params (not outer vars).
    // Outer vars are accessible via outerVarNamesForCapture — references that
    // fall through to the outer scope are recorded as CaptureEntry values.
    const resolvedFnType: ?sig.ZSFunction = if (self.lambdaTypes) |lt|
        if (lt.get(startPos)) |t| (if (t == .function) t.function else null) else null
    else
        null;

    var innerVarNames = std.StringHashMap([]const u8).init(self.allocator);
    const synthesizedImplicitIt = implicitParamsFromContext and resolvedFnType != null and resolvedFnType.?.args.len == 1;
    if (synthesizedImplicitIt) {
        try innerVarNames.put("it", "it");
    }
    for (params) |param| {
        try innerVarNames.put(param.name, param.name);
    }
    const outerVarNames = self.varNames;
    self.varNames = innerVarNames;

    // Set up capture tracking
    var captureList = try std.ArrayList(CaptureEntry).initCapacity(self.allocator, 4);
    defer captureList.deinit(self.allocator);
    var capturedSet = std.StringHashMap(void).init(self.allocator);
    defer capturedSet.deinit();
    const outerCapturedSet = self.capturedVarNamesSet;
    self.outerVarNamesForCapture = &outerVarNames;
    self.currentLambdaCaptures = &captureList;
    self.capturedVarNamesSet = &capturedSet;

    const bodyResult = try self.generateExpr(body);

    // Add implicit return for expression body
    if (body != .block) {
        try self.instructions.append(self.allocator, ir.ZSIR{ .ret = .{ .value = bodyResult } });
    }

    // Restore state
    self.instructions = outerInstructions;
    self.outerVarNamesForCapture = null;
    self.currentLambdaCaptures = null;
    self.capturedVarNamesSet = outerCapturedSet;
    var modifiedInner = self.varNames;
    self.varNames = outerVarNames;
    modifiedInner.deinit();

    // Build arg names/types: [__cap_0, __cap_1, ..., param0, param1, ...]
    // Capture params are pointers (i64-encoded) for capture-by-reference semantics.
    const captureLen = captureList.items.len;
    const totalArgs = captureLen + params.len + @as(usize, if (synthesizedImplicitIt) 1 else 0);
    const argNames = try self.allocator.alloc([]const u8, totalArgs);
    const argTypes = try self.allocator.alloc([]const u8, totalArgs);
    for (captureList.items, 0..) |cap, i| {
        argNames[i] = cap.paramName; // ownership transferred to fn_def; NOT duped so ZSIRArith.rhs stays valid
        argTypes[i] = try self.allocator.dupe(u8, "long"); // i64 for pointer-encoded captures
    }
    var paramOffset = captureLen;
    if (synthesizedImplicitIt) {
        argNames[paramOffset] = try self.allocator.dupe(u8, "it");
        const implicitType: []const u8 = if (resolvedFnType) |ft| blk: {
            const t = zsSymbolTypeToIrName(ft.args[0].type);
            break :blk if (std.mem.eql(u8, t, "unknown")) "number" else t;
        } else "number";
        argTypes[paramOffset] = try self.allocator.dupe(u8, implicitType);
        paramOffset += 1;
    }
    for (params, 0..) |param, i| {
        argNames[paramOffset + i] = try self.allocator.dupe(u8, param.name);
        // Use resolved param type; fall back to "number" for unknown (codegen compat)
        const resolvedArgType: []const u8 = if (resolvedFnType) |ft|
            if (i < ft.args.len) blk: {
                const t = zsSymbolTypeToIrName(ft.args[i].type);
                break :blk if (std.mem.eql(u8, t, "unknown")) "number" else t;
            } else "number"
        else
            "number";
        argTypes[paramOffset + i] = try self.allocator.dupe(u8, resolvedArgType);
    }

    // Resolve return type; fall back to "number" for unknown
    const resolvedRetType: []const u8 = if (resolvedFnType) |ft| blk: {
        const t = zsSymbolTypeToIrName(ft.ret.*);
        break :blk if (std.mem.eql(u8, t, "unknown")) "number" else t;
    } else "number";

    // Store captures for call-site prepending (owned slice; paramName strings owned by map)
    if (captureLen > 0) {
        const storedCaptures = try self.allocator.dupe(CaptureEntry, captureList.items);
        try self.lambdaCaptureMap.put(lambdaName, storedCaptures);
    }

    // Emit fn_def at top level
    try self.topLevelInstructions.append(self.allocator, ir.ZSIR{ .fn_def = .{
        .name = try self.allocator.dupe(u8, lambdaName),
        .argNames = argNames,
        .argTypes = argTypes,
        .retType = try self.allocator.dupe(u8, resolvedRetType),
        .body = try self.allocator.dupe(ir.ZSIR, lambdaInstructions.items),
    } });

    // Return the lambda name as a reference
    return lambdaName;
}

fn generateAsmBlock(self: *Self, ab: ast.stmt.ZSAsmBlock) Error![]const u8 {
    const inputs = try self.allocator.alloc(ir.ZSIRAsmInput, ab.inputs.len);
    for (ab.inputs, 0..) |inp, i| {
        const val = try self.generateExpr(inp.expr);
        inputs[i] = .{ .reg = inp.reg, .value = val };
    }

    const outputs = try self.allocator.alloc(ir.ZSIRAsmOutput, ab.outputs.len);
    for (ab.outputs, 0..) |out, i| {
        outputs[i] = .{ .reg = out.reg, .name = out.name };
        try self.varNames.put(out.name, out.name);
    }

    try self.instructions.append(self.allocator, ir.ZSIR{ .asm_block = .{
        .inputs = inputs,
        .outputs = outputs,
        .clobbers = try self.allocator.dupe([]const u8, ab.clobbers),
        .instructions = try self.allocator.dupe([]const u8, ab.instructions),
    } });

    return "";
}

fn generateAssign(self: *Self, value: ir.ZSIRValue, startPos: usize) Error![]const u8 {
    const name = try self.generateName();
    try self.instructions.append(self.allocator, ir.ZSIR{ .assign = ir.ZSIRAssign{ .value = value, .varName = name, .startPos = startPos } });
    return name;
}

fn generateName(self: *Self) Error![]const u8 {
    const name = try std.fmt.allocPrint(self.allocator, "x{}", .{self.nameCount});
    self.nameCount += 1;
    return name;
}

fn typeToString(zsType: Symbol.ZSType) []const u8 {
    return switch (zsType) {
        .number => "number",
        .boolean => "boolean",
        .char => "char",
        .long => "long",
        .short => "short",
        .byte => "byte",
        .void => "void",
        .function => "function",
        .unknown => "unknown",
        .struct_type => |st| st.name,
        .pointer => "pointer",
        .array_type => "array",
        .enum_type => |et| et.name,
    };
}
