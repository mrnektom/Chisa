const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const sts = @import("symbol_table_stack.zig");
const SymbolTable = sts.SymbolTable;
const type_resolver = @import("type_resolver.zig");

const StructDef = @import("analyzer.zig").StructDef;
const EnumDef = @import("analyzer.zig").EnumDef;
const MonomorphizedEnumDef = @import("analyzer.zig").MonomorphizedEnumDef;
const EnumInitInfo = @import("analyzer.zig").EnumInitInfo;
const Error = @import("analyzer.zig").Error;

pub fn analyzeStructInit(self: anytype, si: ast.expr.ZSStructInit) Error!Symbol.ZSTypeNotation {
    // Try direct lookup first
    var sd = self.structDefs.get(si.name);
    var structName = si.name;
    var typeArgsForInstantiation: ?[]ast.type_notation.ZSTypeNotation = null;

    // If not found, check for mangled generic struct name (e.g., "List$T" or "List$number")
    if (sd == null) {
        if (std.mem.indexOfScalar(u8, si.name, '$')) |dollarIdx| {
            const baseName = si.name[0..dollarIdx];
            if (self.structDefs.get(baseName)) |baseSd| {
                // Parse type args from mangled name
                var typeArgs = try std.ArrayList([]const u8).initCapacity(self.allocator, 2);
                defer typeArgs.deinit(self.allocator);
                var rest = si.name[dollarIdx + 1 ..];
                while (rest.len > 0) {
                    if (std.mem.indexOfScalar(u8, rest, '$')) |nextDollar| {
                        try typeArgs.append(self.allocator, rest[0..nextDollar]);
                        rest = rest[nextDollar + 1 ..];
                    } else {
                        try typeArgs.append(self.allocator, rest);
                        break;
                    }
                }

                // Substitute type params if we have bindings in scope
                var resolvedTypeArgNames = try self.allocator.alloc([]const u8, typeArgs.items.len);
                defer self.allocator.free(resolvedTypeArgNames);
                for (typeArgs.items, 0..) |ta, i| {
                    resolvedTypeArgNames[i] = type_resolver.substituteTypeParamName(self, ta);
                }

                // Build AST type args for instantiation
                const astTypeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, resolvedTypeArgNames.len);
                try self.allocatedAstTypeSlices.append(self.allocator, astTypeArgs);
                for (resolvedTypeArgNames, 0..) |rta, i| {
                    astTypeArgs[i] = ast.ZSTypeNotation{ .reference = rta };
                }
                typeArgsForInstantiation = astTypeArgs;
                sd = baseSd;
                structName = baseName;
            }
        }
    }

    const structDef = sd orelse {
        try self.recordError(si, "Unknown struct type");
        return Symbol.ZSTypeNotation.unknown;
    };

    // Check field count
    if (si.field_values.len != structDef.fields.len) {
        try self.recordError(si, "Wrong number of fields in struct init");
        return Symbol.ZSTypeNotation.unknown;
    }

    // Analyze each field value and build resolved fields
    const resolvedFields = try self.allocator.alloc(sig.ZSStructField, structDef.fields.len);
    try self.allocatedStructFields.append(self.allocator, resolvedFields);
    for (si.field_values, 0..) |fv, i| {
        const valueType = try self.analyzeExpr(fv.value);
        // Find matching field in definition
        var found = false;
        for (structDef.fields) |defField| {
            if (std.mem.eql(u8, defField.name, fv.name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try self.recordError(si, "Unknown field in struct init");
        }
        if (i < resolvedFields.len) {
            resolvedFields[i] = .{ .name = fv.name, .type = valueType };
        }
    }

    // If this is a generic struct, instantiate with resolved type args
    if (typeArgsForInstantiation) |taArgs| {
        // Build the resolved mangled struct name for IR gen
        var mangledBuf = try std.ArrayList(u8).initCapacity(self.allocator, structName.len + 16);
        defer mangledBuf.deinit(self.allocator);
        try mangledBuf.appendSlice(self.allocator, structName);
        for (taArgs) |ta| {
            try mangledBuf.append(self.allocator, '$');
            try mangledBuf.appendSlice(self.allocator, ta.typeName());
        }
        const resolvedStructName = try self.allocator.dupe(u8, mangledBuf.items);
        try self.allocatedStrings.append(self.allocator, resolvedStructName);

        // Register the struct init resolution so IR gen can emit the right name
        try self.structInitResolutions.put(si.startPos, resolvedStructName);

        // Register the monomorphized struct definition so codegen can find its field types
        if (!self.structDefs.contains(resolvedStructName)) {
            // Extract string type arg names from AST types
            const typeArgStrs = try self.allocator.alloc([]const u8, taArgs.len);
            try self.allocatedSliceLists.append(self.allocator, typeArgStrs);
            for (taArgs, 0..) |ta, i| {
                typeArgStrs[i] = ta.typeName();
            }
            // Create a concrete struct def with substituted field types
            const concreteFields = try self.allocator.alloc(ast.stmt.ZSStruct.ZSStructField, structDef.fields.len);
            try self.allocatedAstStructFields.append(self.allocator, concreteFields);
            for (structDef.fields, 0..) |field, i| {
                concreteFields[i] = .{
                    .name = field.name,
                    .type = try type_resolver.substituteAstType(self, field.type, structDef.type_params, typeArgStrs),
                };
            }
            try self.structDefs.put(resolvedStructName, .{
                .name = resolvedStructName,
                .type_params = &.{},
                .fields = concreteFields,
            });
        }

        return try type_resolver.instantiateStruct(self, structDef, taArgs);
    }

    return Symbol.ZSTypeNotation{ .struct_type = .{
        .name = structName,
        .fields = resolvedFields,
        .type_args = &.{},
    } };
}

pub fn analyzeArrayLiteral(self: anytype, al: ast.expr.ZSArrayLiteral) Error!Symbol.ZSTypeNotation {
    var elemType: Symbol.ZSTypeNotation = .unknown;
    for (al.elements) |elem| {
        const t = try self.analyzeExpr(elem);
        if (elemType == .unknown) {
            elemType = t;
        } else if (t != .unknown and !type_resolver.typesCompatible(elemType, t)) {
            try self.recordErrorAt(elem.start(), elem.end(), "Array elements must have a consistent type");
        }
    }
    const elemPtr = try self.allocator.create(Symbol.ZSTypeNotation);
    elemPtr.* = elemType;
    try self.allocatedTypes.append(self.allocator, elemPtr);
    try self.arrayLiteralElemTypes.put(al.startPos, type_resolver.typeToString(elemType));
    return Symbol.ZSTypeNotation{ .array_type = .{ .element_type = elemPtr, .size = al.elements.len } };
}

pub fn analyzeIndexAccess(self: anytype, ia: ast.expr.ZSIndexAccess) Error!Symbol.ZSTypeNotation {
    const subjectType = try self.analyzeExpr(ia.subject.*);
    _ = try self.analyzeExpr(ia.index.*);
    return switch (subjectType) {
        .array_type => |at| at.element_type.*,
        .pointer => |pt| {
            try self.indexElemTypes.put(ia.startPos, type_resolver.typeToString(pt.*));
            return pt.*;
        },
        .struct_type => |st| blk: {
            // Pointer<T> structs support index access, returning T
            if (std.mem.eql(u8, st.name, "Pointer") and st.type_args.len > 0) {
                const elemType = st.type_args[0];
                try self.indexElemTypes.put(ia.startPos, type_resolver.typeToString(elemType));
                break :blk elemType;
            }
            try self.recordError(ia, "Index access on non-array type");
            break :blk Symbol.ZSTypeNotation.unknown;
        },
        .long => .char,
        else => blk: {
            try self.recordError(ia, "Index access on non-array type");
            break :blk Symbol.ZSTypeNotation.unknown;
        },
    };
}

pub fn analyzeFieldAccess(self: anytype, fa: ast.expr.ZSFieldAccess) Error!Symbol.ZSTypeNotation {
    // Check if subject is a reference to an enum name (e.g., Option.None)
    if (fa.subject.* == .reference) {
        const refName = fa.subject.reference.name;
        if (self.enumDefs.get(refName)) |ed| {
            // This is EnumName.Variant (unit variant access)
            for (ed.variants, 0..) |variant, i| {
                if (std.mem.eql(u8, variant.name, fa.field)) {
                    // For generic enums, try to use expected type to instantiate
                    if (ed.type_params.len > 0) {
                        if (self.expectedType) |expected| {
                            if (expected == .enum_type) {
                                const expectedEnum = expected.enum_type;
                                if (std.mem.eql(u8, expectedEnum.name, ed.name) and expectedEnum.type_args.len == ed.type_params.len) {
                                    const result = try type_resolver.instantiateEnumFromResolved(self, ed, expectedEnum.type_args);
                                    const mangledName = try type_resolver.computeEnumMangledName(self, ed.name, expectedEnum.type_args);
                                    try self.enumInits.put(fa.startPos, .{
                                        .enumName = mangledName,
                                        .variantTag = @intCast(i),
                                    });
                                    return result;
                                }
                            }
                        }
                        // No expected type -- cannot instantiate generic enum
                        try self.recordError(fa, "Cannot infer type arguments for generic enum; add a type annotation");
                        return Symbol.ZSTypeNotation.unknown;
                    }

                    // Record this as an enum init for IR gen
                    try self.enumInits.put(fa.startPos, .{
                        .enumName = refName,
                        .variantTag = @intCast(i),
                    });
                    return try type_resolver.buildEnumType(self, ed);
                }
            }
            try self.recordError(fa, "Unknown enum variant");
            return Symbol.ZSTypeNotation.unknown;
        }
    }

    const subjectType = try self.analyzeExpr(fa.subject.*);
    return switch (subjectType) {
        .struct_type => |st| {
            for (st.fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, fa.field)) {
                    try self.fieldIndices.put(fa.startPos, @intCast(i));
                    return field.type;
                }
            }
            try self.recordError(fa, "Field not found in struct");
            return Symbol.ZSTypeNotation.unknown;
        },
        .array_type => {
            if (std.mem.eql(u8, fa.field, "length")) {
                return Symbol.ZSTypeNotation.number;
            }
            try self.recordError(fa, "Unknown array field");
            return Symbol.ZSTypeNotation.unknown;
        },
        else => blk: {
            try self.recordError(fa, "Field access on non-struct type");
            break :blk Symbol.ZSTypeNotation.unknown;
        },
    };
}

pub fn analyzeEnumInit(self: anytype, ei: ast.expr.ZSEnumInit) Error!Symbol.ZSTypeNotation {
    const ed = self.enumDefs.get(ei.enum_name) orelse {
        try self.recordError(ei, "Unknown enum type");
        return Symbol.ZSTypeNotation.unknown;
    };

    // Find the variant
    var foundVariant: ?ast.stmt.ZSEnum.ZSEnumVariant = null;
    for (ed.variants) |v| {
        if (std.mem.eql(u8, v.name, ei.variant_name)) {
            foundVariant = v;
            break;
        }
    }

    if (foundVariant == null) {
        try self.recordError(ei, "Unknown enum variant");
        return Symbol.ZSTypeNotation.unknown;
    }

    const variant = foundVariant.?;

    // Check payload
    if (ei.payload != null and variant.payload_type == null) {
        try self.recordError(ei, "Variant does not accept a payload");
    } else if (ei.payload == null and variant.payload_type != null) {
        try self.recordError(ei, "Variant requires a payload");
    }

    // Analyze payload and infer type args for generic enums
    var payloadType: Symbol.ZSTypeNotation = .unknown;
    if (ei.payload) |p| {
        payloadType = try self.analyzeExpr(p.*);
    }

    if (ed.type_params.len > 0) {
        // Try to infer type args from payload
        var inferredTypeArgs = try self.allocator.alloc(Symbol.ZSTypeNotation, ed.type_params.len);
        try self.allocatedTypeSlices.append(self.allocator, inferredTypeArgs);
        for (0..ed.type_params.len) |i| {
            inferredTypeArgs[i] = .unknown;
        }

        if (variant.payload_type != null and ei.payload != null) {
            const ptName = variant.payload_type.?.typeName();
            for (ed.type_params, 0..) |param, pi| {
                if (std.mem.eql(u8, ptName, param)) {
                    inferredTypeArgs[pi] = payloadType;
                    break;
                }
            }
        }

        // Check if all type args were inferred
        var allInferred = true;
        for (inferredTypeArgs) |ta| {
            if (ta == .unknown) {
                allInferred = false;
                break;
            }
        }

        if (!allInferred) {
            // Try expected type propagation
            if (self.expectedType) |expected| {
                if (expected == .enum_type) {
                    const expectedEnum = expected.enum_type;
                    if (std.mem.eql(u8, expectedEnum.name, ed.name) and expectedEnum.type_args.len == ed.type_params.len) {
                        for (0..ed.type_params.len) |i| {
                            if (inferredTypeArgs[i] == .unknown) {
                                inferredTypeArgs[i] = expectedEnum.type_args[i];
                            }
                        }
                        allInferred = true;
                        for (inferredTypeArgs) |ta| {
                            if (ta == .unknown) {
                                allInferred = false;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (allInferred) {
            const result = try type_resolver.instantiateEnumFromResolved(self, ed, inferredTypeArgs);
            // Record enum init info with mangled name
            const mangledName = try type_resolver.computeEnumMangledName(self, ed.name, inferredTypeArgs);
            try self.enumInits.put(ei.startPos, .{
                .enumName = mangledName,
                .variantTag = @intCast(findVariantTag(ed, ei.variant_name)),
            });
            return result;
        }
    }

    // For generic enums where inference failed, emit an error
    if (ed.type_params.len > 0) {
        try self.recordError(ei, "Cannot infer type arguments for generic enum; add a type annotation");
        return Symbol.ZSTypeNotation.unknown;
    }

    // Non-generic: use base enum name
    try self.enumInits.put(ei.startPos, .{
        .enumName = ed.name,
        .variantTag = @intCast(findVariantTag(ed, ei.variant_name)),
    });
    return try type_resolver.buildEnumType(self, ed);
}

pub fn findVariantTag(ed: EnumDef, variantName: []const u8) usize {
    for (ed.variants, 0..) |v, i| {
        if (std.mem.eql(u8, v.name, variantName)) return i;
    }
    return 0;
}

pub fn analyzeMatchExpr(self: anytype, me: ast.expr.ZSMatchExpr) Error!Symbol.ZSTypeNotation {
    const subjectType = try self.analyzeExpr(me.subject.*);

    // For enum patterns, subject must be an enum type
    var hasEnumArm = false;
    for (me.arms) |arm| {
        if (arm.pattern == .enum_variant) { hasEnumArm = true; break; }
    }
    if (hasEnumArm and subjectType != .enum_type) {
        try self.recordError(me, "Match subject must be an enum type for enum patterns");
        return Symbol.ZSTypeNotation.unknown;
    }

    const enumTypeOpt: ?sig.ZSEnumType = if (subjectType == .enum_type) subjectType.enum_type else null;
    const enumType = enumTypeOpt orelse sig.ZSEnumType{ .name = "", .variants = @as([]sig.ZSEnumVariant, &.{}), .type_args = @as([]const Symbol.ZSTypeNotation, &.{}) };
    var resultType: Symbol.ZSTypeNotation = .unknown;

    // Record the resolved enum name for IR gen (uses mangled name for generic enums)
    if (enumType.type_args.len > 0) {
        const mangledName = try type_resolver.computeEnumMangledName(self, enumType.name, enumType.type_args);
        try self.matchEnumNames.put(me.startPos, mangledName);
        // Ensure the monomorphized enum is registered in this module's context.
        // It may have been instantiated in an imported module and not carried over.
        if (!self.monomorphizedEnums.contains(mangledName)) {
            if (self.enumDefs.get(enumType.name)) |ed| {
                _ = try type_resolver.instantiateEnumFromResolved(self, ed, enumType.type_args);
            } else if (enumTypeOpt) |et| {
                // Cross-module generic enum: enumDefs doesn't have it, but the resolved
                // type already carries the concrete variants with correct tags.
                const monoMangledName = try self.allocator.dupe(u8, mangledName);
                try self.allocatedStrings.append(self.allocator, monoMangledName);
                try self.monomorphizedEnums.put(monoMangledName, .{
                    .mangledName = monoMangledName,
                    .variants = et.variants,
                });
            }
        }
    } else {
        try self.matchEnumNames.put(me.startPos, enumType.name);
    }

    // Track covered variants for exhaustiveness check
    var coveredVariants = std.StringHashMap(void).init(self.allocator);
    defer coveredVariants.deinit();

    for (me.arms) |arm| {
        var armScope = SymbolTable.init(self.allocator);
        defer armScope.deinit();
        try self.tableStack.enterScope(&armScope);

        switch (arm.pattern) {
            .enum_variant => |ev| {
                // Verify the variant belongs to the enum
                var foundVariant: ?sig.ZSEnumVariant = null;
                for (enumType.variants) |v| {
                    if (std.mem.eql(u8, v.name, ev.variant_name)) {
                        foundVariant = v;
                        break;
                    }
                }
                if (foundVariant == null) {
                    try self.recordError(me, "Unknown variant in match arm");
                    _ = try self.tableStack.exitScope();
                    continue;
                }
                const variant = foundVariant.?;
                try coveredVariants.put(ev.variant_name, {});
                if (ev.binding) |binding| {
                    const bindingType = variant.payload_type orelse Symbol.ZSTypeNotation.unknown;
                    try self.tableStack.put(.{
                        .name = binding,
                        .assignable = false,
                        .signature = bindingType,
                    });
                }
            },
            .number_literal => {},
            .boolean_literal => {},
            .char_literal => {},
            .string_literal => {},
            .struct_destructure => |sd| {
                if (subjectType == .struct_type) {
                    const st = subjectType.struct_type;
                    for (sd.fields) |fp| {
                        var fieldType: Symbol.ZSTypeNotation = .unknown;
                        for (st.fields) |sf| {
                            if (std.mem.eql(u8, sf.name, fp.name)) {
                                fieldType = sf.type;
                                break;
                            }
                        }
                        if (fp.binding_name) |bn| {
                            try self.tableStack.put(.{
                                .name = bn,
                                .assignable = false,
                                .signature = fieldType,
                            });
                        }
                    }
                }
            },
        }

        const armType = try self.analyzeExpr(arm.body.*);
        _ = try self.tableStack.exitScope();

        if (resultType == .unknown) {
            resultType = armType;
        } else if (armType != .unknown and
                   !type_resolver.typesCompatible(resultType, armType) and
                   !type_resolver.typesCompatible(armType, resultType))
        {
            try self.recordError(me, "match arms have incompatible return types");
        }
    }

    // Analyze else body if present
    if (me.has_else) {
        if (me.else_body) |eb| {
            const elseType = try self.analyzeExpr(eb.*);
            if (resultType == .unknown) {
                resultType = elseType;
            } else if (elseType != .unknown and
                       !type_resolver.typesCompatible(resultType, elseType) and
                       !type_resolver.typesCompatible(elseType, resultType))
            {
                try self.recordError(me, "else branch type is incompatible with match arms");
            }
        }
    } else {
        // Exhaustiveness check: all variants must be covered (only when no else)
        for (enumType.variants) |v| {
            if (!coveredVariants.contains(v.name)) {
                const msg = try std.fmt.allocPrint(self.allocator, "Match is not exhaustive: missing variant '{s}'", .{v.name});
                try self.allocatedStrings.append(self.allocator, msg);
                try self.recordError(me, msg);
            }
        }
    }

    return resultType;
}

pub fn analyzeUse(self: anytype, u: ast.ZSUse) Error!void {
    const ed = self.enumDefs.get(u.enum_name) orelse {
        try self.recordErrorAt(u.startPos, u.endPos, "Unknown enum type in use declaration");
        return;
    };

    for (u.variants) |variantName| {
        // Verify the variant exists
        var found = false;
        for (ed.variants) |v| {
            if (std.mem.eql(u8, v.name, variantName)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try self.recordErrorAt(u.startPos, u.endPos, "Unknown variant in use declaration");
            continue;
        }
        try self.useAliases.put(variantName, .{
            .enum_name = u.enum_name,
            .variant_name = variantName,
        });
    }
}
