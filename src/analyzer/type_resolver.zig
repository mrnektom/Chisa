const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const computeMangledName = @import("ZenScript").MangleHelpers.computeMangledName;

const StructDef = @import("analyzer.zig").StructDef;
const EnumDef = @import("analyzer.zig").EnumDef;
const GenericFnDef = @import("analyzer.zig").GenericFnDef;
const Error = @import("analyzer.zig").Error;

pub fn typeToString(zsType: Symbol.ZSTypeNotation) []const u8 {
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

pub fn isNumericType(name: []const u8) bool {
    return std.mem.eql(u8, name, "number") or
        std.mem.eql(u8, name, "long") or
        std.mem.eql(u8, name, "int") or
        std.mem.eql(u8, name, "short") or
        std.mem.eql(u8, name, "byte") or
        std.mem.eql(u8, name, "char");
}

pub fn isArithmeticType(t: Symbol.ZSTypeNotation) bool {
    return switch (t) {
        .number, .long, .short, .byte, .char => true,
        else => false,
    };
}

pub const builtinScalars = .{
    .{ "number", Symbol.ZSTypeNotation.number },
    .{ "int", Symbol.ZSTypeNotation.number },
    .{ "long", Symbol.ZSTypeNotation.long },
    .{ "short", Symbol.ZSTypeNotation.short },
    .{ "byte", Symbol.ZSTypeNotation.byte },
    .{ "boolean", Symbol.ZSTypeNotation.boolean },
    .{ "char", Symbol.ZSTypeNotation.char },
};

pub const ZSTType = sig.ZSTType;

/// Check if two types are compatible for assignment.
/// Returns true if `src` can be assigned to a variable of type `dst`.
pub fn typesCompatible(dst: Symbol.ZSTypeNotation, src: Symbol.ZSTypeNotation) bool {
    // Same tag = compatible (for primitives)
    const dstTag: ZSTType = dst;
    const srcTag: ZSTType = src;
    if (dstTag == srcTag) {
        // For enum types, also check the name matches
        if (dstTag == .enum_type) {
            return std.mem.eql(u8, dst.enum_type.name, src.enum_type.name);
        }
        // For struct types, check name matches
        if (dstTag == .struct_type) {
            return std.mem.eql(u8, dst.struct_type.name, src.struct_type.name);
        }
        return true;
    }
    // number/short/byte/long are all integer-compatible
    const intTypes = [_]ZSTType{ .number, .long, .short, .byte };
    var dstIsInt = false;
    var srcIsInt = false;
    for (intTypes) |t| {
        if (dstTag == t) dstIsInt = true;
        if (srcTag == t) srcIsInt = true;
    }
    if (dstIsInt and srcIsInt) return true;
    return false;
}

pub fn resolveTypeAnnotationFull(self: anytype, astType: ast.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    const maxDepth = 32;
    if (self.typeResolutionDepth >= maxDepth) {
        try self.errors.append(self.allocator, .{
            .message = "type annotation is too deeply nested (limit: 32 levels): break it up using type aliases",
            .severity = .err,
            .phase = .analyze,
            .filename = self.module.filename,
        });
        return .unknown;
    }
    self.typeResolutionDepth += 1;
    defer self.typeResolutionDepth -= 1;

    switch (astType) {
        .reference => |ref| {
            // Check if it's a type parameter with active resolved bindings first so
            // generic types like Option<number> survive contextual inference.
            if (self.typeParamSymbolBindings) |bindings| {
                for (bindings.typeParams, 0..) |tp, i| {
                    if (std.mem.eql(u8, ref, tp)) {
                        return bindings.bindings[i];
                    }
                }
            }
            // Scalar types registered from stdlib scalar declarations
            if (self.scalarDefs.get(ref)) |t| return t;
            if (std.mem.eql(u8, ref, "void")) return .void;
            // Check if it's a known struct type (non-generic)
            if (self.structDefs.get(ref)) |sd| {
                if (sd.type_params.len == 0) {
                    return try instantiateStruct(self, sd, &.{});
                }
            }
            // Check if it's a known enum type (non-generic)
            if (self.enumDefs.get(ref)) |ed| {
                if (ed.type_params.len == 0) {
                    return try buildEnumType(self, ed);
                }
            }
            // Check if it's a type parameter with active bindings
            if (self.typeParamBindings) |bindings| {
                for (bindings.typeParams, 0..) |tp, i| {
                    if (std.mem.eql(u8, ref, tp)) {
                        return try resolveTypeAnnotationFull(self, ast.ZSTypeNotation{ .reference = bindings.bindings[i] });
                    }
                }
            }
            // Check type aliases
            if (self.typeAliases.get(ref)) |alias| {
                if (alias.type_params.len == 0) {
                    return try resolveTypeAnnotationFull(self, alias.aliased_type);
                }
            }
            return .unknown;
        },
        .array => |a| {
            const elemType = try resolveTypeAnnotationFull(self, a.element_type.*);
            const elemPtr = try self.allocator.create(Symbol.ZSTypeNotation);
            elemPtr.* = elemType;
            try self.allocatedTypes.append(self.allocator, elemPtr);
            return Symbol.ZSTypeNotation{ .array_type = .{ .element_type = elemPtr, .size = 0 } };
        },
        .fn_type => |ft| {
            const retType = try resolveTypeAnnotationFull(self, ft.return_type.*);
            const retPtr = try self.allocator.create(Symbol.ZSTypeNotation);
            retPtr.* = retType;
            try self.allocatedTypes.append(self.allocator, retPtr);
            const args = try self.allocator.alloc(sig.ZSFnArg, ft.param_types.len);
            try self.allocatedFnArgs.append(self.allocator, args);
            for (ft.param_types, 0..) |pt, i| {
                args[i] = .{ .name = "", .type = try resolveTypeAnnotationFull(self, pt) };
            }
            return Symbol.ZSTypeNotation{ .function = .{ .ret = retPtr, .args = args } };
        },
        .generic => |g| {
            // Check type aliases for generic types
            if (self.typeAliases.get(g.name)) |alias| {
                if (alias.type_params.len == g.type_args.len) {
                    const bindingStrs = try self.allocator.alloc([]const u8, g.type_args.len);
                    try self.allocatedSliceLists.append(self.allocator, bindingStrs);
                    for (g.type_args, 0..) |typeArg, i| {
                        const resolved = try resolveTypeAnnotationFull(self, typeArg);
                        bindingStrs[i] = typeToString(resolved);
                    }
                    const substituted = try substituteAstType(self, alias.aliased_type, alias.type_params, bindingStrs);
                    return try resolveTypeAnnotationFull(self, substituted);
                }
            }
            // Pointer<T> is represented as ZSTypeNotation.pointer, not as a struct
            if (std.mem.eql(u8, g.name, "Pointer") and g.type_args.len == 1) {
                const innerType = try resolveTypeAnnotationFull(self, g.type_args[0]);
                const innerPtr = try self.allocator.create(Symbol.ZSTypeNotation);
                innerPtr.* = innerType;
                try self.allocatedTypes.append(self.allocator, innerPtr);
                return Symbol.ZSTypeNotation{ .pointer = innerPtr };
            }
            // Check for generic struct
            if (self.structDefs.get(g.name)) |sd| {
                return try instantiateStruct(self, sd, g.type_args);
            }
            // Check for generic enum
            if (self.enumDefs.get(g.name)) |ed| {
                return try instantiateEnum(self, ed, g.type_args);
            }
            return .unknown;
        },
    }
}

pub fn instantiateStruct(self: anytype, sd: StructDef, typeArgs: []const ast.type_notation.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    // Validate type argument count matches type parameter count
    if (typeArgs.len != sd.type_params.len) {
        return .unknown;
    }

    // Build a mapping from type_param names to resolved types
    const resolvedFields = try self.allocator.alloc(sig.ZSStructField, sd.fields.len);
    try self.allocatedStructFields.append(self.allocator, resolvedFields);
    const resolvedTypeArgs = try self.allocator.alloc(Symbol.ZSTypeNotation, typeArgs.len);
    try self.allocatedTypeSlices.append(self.allocator, resolvedTypeArgs);

    for (typeArgs, 0..) |ta, i| {
        resolvedTypeArgs[i] = try resolveTypeAnnotationFull(self, ta);
    }

    for (sd.fields, 0..) |field, i| {
        const fieldType = try resolveFieldType(self, field.type, sd.type_params, resolvedTypeArgs);
        resolvedFields[i] = .{ .name = field.name, .type = fieldType };
    }

    return Symbol.ZSTypeNotation{ .struct_type = .{
        .name = sd.name,
        .fields = resolvedFields,
        .type_args = resolvedTypeArgs,
    } };
}

pub fn resolveFieldType(self: anytype, fieldAstType: ast.type_notation.ZSTypeNotation, typeParams: []const []const u8, resolvedTypeArgs: []const Symbol.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    switch (fieldAstType) {
        .reference => |ref| {
            // Check if it's a type parameter
            for (typeParams, 0..) |param, i| {
                if (std.mem.eql(u8, ref, param)) {
                    if (i < resolvedTypeArgs.len) return resolvedTypeArgs[i];
                    return .unknown;
                }
            }
            // Otherwise resolve normally
            return try resolveTypeAnnotationFull(self, fieldAstType);
        },
        .generic => |g| {
            // Resolve each type arg through resolveFieldType so outer type params are substituted
            // with their actual Symbol.ZSTypeNotation values rather than lossy string names.
            const resolvedArgs = try self.allocator.alloc(Symbol.ZSTypeNotation, g.type_args.len);
            try self.allocatedTypeSlices.append(self.allocator, resolvedArgs);
            for (g.type_args, 0..) |ta, i| {
                resolvedArgs[i] = try resolveFieldType(self, ta, typeParams, resolvedTypeArgs);
            }
            if (std.mem.eql(u8, g.name, "Pointer") and resolvedArgs.len == 1) {
                const innerPtr = try self.allocator.create(Symbol.ZSTypeNotation);
                innerPtr.* = resolvedArgs[0];
                try self.allocatedTypes.append(self.allocator, innerPtr);
                return Symbol.ZSTypeNotation{ .pointer = innerPtr };
            }
            if (self.structDefs.get(g.name)) |sd| {
                return try instantiateStructFromResolved(self, sd, resolvedArgs);
            }
            if (self.enumDefs.get(g.name)) |ed| {
                return try instantiateEnumFromResolved(self, ed, resolvedArgs);
            }
            return .unknown;
        },
        .array => |a| {
            const elemType = try resolveFieldType(self, a.element_type.*, typeParams, resolvedTypeArgs);
            const elemPtr = try self.allocator.create(Symbol.ZSTypeNotation);
            elemPtr.* = elemType;
            try self.allocatedTypes.append(self.allocator, elemPtr);
            return Symbol.ZSTypeNotation{ .array_type = .{ .element_type = elemPtr, .size = 0 } };
        },
        .fn_type => |ft| {
            const retType = try resolveFieldType(self, ft.return_type.*, typeParams, resolvedTypeArgs);
            const retPtr = try self.allocator.create(Symbol.ZSTypeNotation);
            retPtr.* = retType;
            try self.allocatedTypes.append(self.allocator, retPtr);
            const args = try self.allocator.alloc(sig.ZSFnArg, ft.param_types.len);
            try self.allocatedFnArgs.append(self.allocator, args);
            for (ft.param_types, 0..) |pt, i| {
                args[i] = .{ .name = "", .type = try resolveFieldType(self, pt, typeParams, resolvedTypeArgs) };
            }
            return Symbol.ZSTypeNotation{ .function = .{ .ret = retPtr, .args = args } };
        },
    }
}

pub fn getStringStructType(self: anytype) !Symbol.ZSTypeNotation {
    // If String is registered as a struct, build its type from the definition
    if (self.structDefs.get("String")) |sd| {
        const resolvedFields = try self.allocator.alloc(sig.ZSStructField, sd.fields.len);
        try self.allocatedStructFields.append(self.allocator, resolvedFields);
        for (sd.fields, 0..) |field, i| {
            const fieldType = try resolveFieldType(self, field.type, sd.type_params, &.{});
            resolvedFields[i] = .{ .name = field.name, .type = fieldType };
        }
        return Symbol.ZSTypeNotation{ .struct_type = .{
            .name = sd.name,
            .fields = resolvedFields,
            .type_args = &.{},
        } };
    }
    return getStringStructTypeStatic();
}

pub fn getStringStructTypeStatic() Symbol.ZSTypeNotation {
    return Symbol.ZSTypeNotation{ .struct_type = .{
        .name = "String",
        .fields = &.{},
        .type_args = &.{},
    } };
}

pub fn buildEnumType(self: anytype, ed: EnumDef) Error!Symbol.ZSTypeNotation {
    const variants = try self.allocator.alloc(sig.ZSEnumVariant, ed.variants.len);
    try self.allocatedEnumVariants.append(self.allocator, variants);
    for (ed.variants, 0..) |v, i| {
        const payloadType: ?Symbol.ZSTypeNotation = if (v.payload_type) |pt| try resolveTypeAnnotationFull(self, pt) else null;
        variants[i] = .{
            .name = v.name,
            .payload_type = payloadType,
            .tag = @intCast(i),
        };
    }
    return Symbol.ZSTypeNotation{ .enum_type = .{
        .name = ed.name,
        .variants = variants,
        .type_args = &.{},
    } };
}

pub fn instantiateStructFromResolved(self: anytype, sd: StructDef, resolvedTypeArgs: []const Symbol.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    if (resolvedTypeArgs.len != sd.type_params.len) return .unknown;

    const resolvedFields = try self.allocator.alloc(sig.ZSStructField, sd.fields.len);
    try self.allocatedStructFields.append(self.allocator, resolvedFields);

    for (sd.fields, 0..) |field, i| {
        const fieldType = try resolveFieldType(self, field.type, sd.type_params, resolvedTypeArgs);
        resolvedFields[i] = .{ .name = field.name, .type = fieldType };
    }

    return Symbol.ZSTypeNotation{ .struct_type = .{
        .name = sd.name,
        .fields = resolvedFields,
        .type_args = resolvedTypeArgs,
    } };
}

pub fn instantiateEnum(self: anytype, ed: EnumDef, typeArgs: []const ast.type_notation.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    const resolvedTypeArgs = try self.allocator.alloc(Symbol.ZSTypeNotation, typeArgs.len);
    try self.allocatedTypeSlices.append(self.allocator, resolvedTypeArgs);
    for (typeArgs, 0..) |ta, i| {
        resolvedTypeArgs[i] = try resolveTypeAnnotationFull(self, ta);
    }

    return try instantiateEnumFromResolved(self, ed, resolvedTypeArgs);
}

pub fn instantiateEnumFromResolved(self: anytype, ed: EnumDef, resolvedTypeArgs: []const Symbol.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    const variants = try self.allocator.alloc(sig.ZSEnumVariant, ed.variants.len);
    try self.allocatedEnumVariants.append(self.allocator, variants);
    for (ed.variants, 0..) |v, i| {
        const payloadType: ?Symbol.ZSTypeNotation = if (v.payload_type) |pt| blk: {
            const ptName = pt.typeName();
            for (ed.type_params, 0..) |param, pi| {
                if (std.mem.eql(u8, ptName, param)) {
                    if (pi < resolvedTypeArgs.len) break :blk resolvedTypeArgs[pi];
                    break :blk Symbol.ZSTypeNotation.unknown;
                }
            }
            break :blk try resolveTypeAnnotationFull(self, pt);
        } else null;
        variants[i] = .{
            .name = v.name,
            .payload_type = payloadType,
            .tag = @intCast(i),
        };
    }

    // Register monomorphized enum
    const mangledName = try computeEnumMangledName(self, ed.name, resolvedTypeArgs);
    if (!self.monomorphizedEnums.contains(mangledName)) {
        try self.monomorphizedEnums.put(mangledName, .{
            .mangledName = mangledName,
            .variants = variants,
        });
    }

    return Symbol.ZSTypeNotation{ .enum_type = .{
        .name = ed.name,
        .variants = variants,
        .type_args = resolvedTypeArgs,
    } };
}

pub fn computeEnumMangledName(self: anytype, baseName: []const u8, typeArgs: []const Symbol.ZSTypeNotation) ![]const u8 {
    const typeArgNames = try self.allocator.alloc([]const u8, typeArgs.len);
    defer self.allocator.free(typeArgNames);
    for (typeArgs, 0..) |ta, i| {
        typeArgNames[i] = typeToString(ta);
    }
    const mangled = try computeMangledName(self.allocator, baseName, typeArgNames);
    try self.allocatedStrings.append(self.allocator, mangled);
    return mangled;
}

/// Resolve the return type of a generic function with concrete type bindings.
pub fn resolveConcreteRetType(self: anytype, gfn: GenericFnDef, bindings: []const []const u8) Error!Symbol.ZSTypeNotation {
    if (gfn.func.ret) |ret| {
        const substituted = try substituteAstType(self, ret, gfn.type_params, bindings);
        return try resolveTypeAnnotationFull(self, substituted);
    }
    return Symbol.ZSTypeNotation.unknown;
}

pub fn resolveConcreteRetTypeWithSymbolBindings(
    self: anytype,
    gfn: GenericFnDef,
    symbolBindings: []const Symbol.ZSTypeNotation,
) Error!Symbol.ZSTypeNotation {
    if (gfn.func.ret) |ret| {
        const substituted = try substituteAstTypeWithSymbolBindings(self, ret, gfn.type_params, symbolBindings);
        return try resolveTypeAnnotationFull(self, substituted);
    }
    return Symbol.ZSTypeNotation.unknown;
}

/// Substitute type parameter references in an AST type with concrete type names.
pub fn substituteAstType(self: anytype, t: ast.ZSTypeNotation, typeParams: []const []const u8, bindings: []const []const u8) !ast.ZSTypeNotation {
    switch (t) {
        .reference => |ref| {
            for (typeParams, 0..) |tp, i| {
                if (std.mem.eql(u8, ref, tp)) {
                    return ast.ZSTypeNotation{ .reference = bindings[i] };
                }
            }
            return t;
        },
        .generic => |g| {
            // Substitute type args within generic types (e.g., Pointer<T> -> Pointer<number>)
            const newTypeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, g.type_args.len);
            try self.allocatedAstTypeSlices.append(self.allocator, newTypeArgs);
            for (g.type_args, 0..) |ta, i| {
                newTypeArgs[i] = try substituteAstType(self, ta, typeParams, bindings);
            }
            return ast.ZSTypeNotation{ .generic = .{ .name = g.name, .type_args = newTypeArgs } };
        },
        .array => |a| {
            const newElem = try self.allocator.create(ast.type_notation.ZSTypeNotation);
            newElem.* = try substituteAstType(self, a.element_type.*, typeParams, bindings);
            return ast.ZSTypeNotation{ .array = .{ .element_type = newElem } };
        },
        .fn_type => |ft| {
            const newParamTypes = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, ft.param_types.len);
            try self.allocatedAstTypeSlices.append(self.allocator, newParamTypes);
            for (ft.param_types, 0..) |pt, i| {
                newParamTypes[i] = try substituteAstType(self, pt, typeParams, bindings);
            }
            const newRetType = try self.allocator.create(ast.type_notation.ZSTypeNotation);
            newRetType.* = try substituteAstType(self, ft.return_type.*, typeParams, bindings);
            return ast.ZSTypeNotation{ .fn_type = .{ .param_types = newParamTypes, .return_type = newRetType } };
        },
    }
}

/// Convert a resolved Symbol.ZSTypeNotation back to an AST type annotation, preserving type
/// arguments.  Used to build non-lossy substitution bindings from already-resolved symbols so
/// that parameterised types like Option<number> round-trip correctly through substituteAstType.
pub fn symbolTypeToAstAnnotation(self: anytype, t: Symbol.ZSTypeNotation) !ast.ZSTypeNotation {
    return switch (t) {
        .number => .{ .reference = "number" },
        .boolean => .{ .reference = "boolean" },
        .char => .{ .reference = "char" },
        .long => .{ .reference = "long" },
        .short => .{ .reference = "short" },
        .byte => .{ .reference = "byte" },
        .void => .{ .reference = "void" },
        .unknown => .{ .reference = "unknown" },
        .function => .{ .reference = "function" },
        .pointer => |inner| {
            const typeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, 1);
            try self.allocatedAstTypeSlices.append(self.allocator, typeArgs);
            typeArgs[0] = try symbolTypeToAstAnnotation(self, inner.*);
            return .{ .generic = .{ .name = "Pointer", .type_args = typeArgs } };
        },
        .array_type => |arr| {
            const elemPtr = try self.allocator.create(ast.type_notation.ZSTypeNotation);
            try self.allocatedAstTypes.append(self.allocator, elemPtr);
            elemPtr.* = try symbolTypeToAstAnnotation(self, arr.element_type.*);
            return .{ .array = .{ .element_type = elemPtr } };
        },
        .struct_type => |st| {
            if (st.type_args.len == 0) return .{ .reference = st.name };
            const typeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, st.type_args.len);
            try self.allocatedAstTypeSlices.append(self.allocator, typeArgs);
            for (st.type_args, 0..) |ta, i| {
                typeArgs[i] = try symbolTypeToAstAnnotation(self, ta);
            }
            return .{ .generic = .{ .name = st.name, .type_args = typeArgs } };
        },
        .enum_type => |et| {
            if (et.type_args.len == 0) return .{ .reference = et.name };
            const typeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, et.type_args.len);
            try self.allocatedAstTypeSlices.append(self.allocator, typeArgs);
            for (et.type_args, 0..) |ta, i| {
                typeArgs[i] = try symbolTypeToAstAnnotation(self, ta);
            }
            return .{ .generic = .{ .name = et.name, .type_args = typeArgs } };
        },
    };
}

/// Like substituteAstType but bindings are pre-resolved Symbol.ZSTypeNotation values.
/// Preserves parameterised types (e.g. Option<number>) instead of reducing them to bare
/// reference names via typeToString.
pub fn substituteAstTypeWithSymbolBindings(
    self: anytype,
    t: ast.ZSTypeNotation,
    typeParams: []const []const u8,
    symbolBindings: []const Symbol.ZSTypeNotation,
) !ast.ZSTypeNotation {
    switch (t) {
        .reference => |ref| {
            for (typeParams, 0..) |tp, i| {
                if (std.mem.eql(u8, ref, tp)) {
                    return try symbolTypeToAstAnnotation(self, symbolBindings[i]);
                }
            }
            return t;
        },
        .generic => |g| {
            const newTypeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, g.type_args.len);
            try self.allocatedAstTypeSlices.append(self.allocator, newTypeArgs);
            for (g.type_args, 0..) |ta, i| {
                newTypeArgs[i] = try substituteAstTypeWithSymbolBindings(self, ta, typeParams, symbolBindings);
            }
            return ast.ZSTypeNotation{ .generic = .{ .name = g.name, .type_args = newTypeArgs } };
        },
        .array => |a| {
            const newElem = try self.allocator.create(ast.type_notation.ZSTypeNotation);
            try self.allocatedAstTypes.append(self.allocator, newElem);
            newElem.* = try substituteAstTypeWithSymbolBindings(self, a.element_type.*, typeParams, symbolBindings);
            return ast.ZSTypeNotation{ .array = .{ .element_type = newElem } };
        },
        .fn_type => |ft| {
            const newParamTypes = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, ft.param_types.len);
            try self.allocatedAstTypeSlices.append(self.allocator, newParamTypes);
            for (ft.param_types, 0..) |pt, i| {
                newParamTypes[i] = try substituteAstTypeWithSymbolBindings(self, pt, typeParams, symbolBindings);
            }
            const newRetType = try self.allocator.create(ast.type_notation.ZSTypeNotation);
            try self.allocatedAstTypes.append(self.allocator, newRetType);
            newRetType.* = try substituteAstTypeWithSymbolBindings(self, ft.return_type.*, typeParams, symbolBindings);
            return ast.ZSTypeNotation{ .fn_type = .{ .param_types = newParamTypes, .return_type = newRetType } };
        },
    }
}

/// Substitute a type param name using the current bindings context.
/// E.g., if bindings map T -> number, returns "number" for input "T".
pub fn substituteTypeParamName(self: anytype, name: []const u8) []const u8 {
    if (self.typeParamBindings) |bindings| {
        for (bindings.typeParams, 0..) |tp, i| {
            if (std.mem.eql(u8, name, tp)) {
                return bindings.bindings[i];
            }
        }
    }
    return name;
}

pub fn typeToBindingString(self: anytype, t: Symbol.ZSTypeNotation) ![]const u8 {
    var buf = try std.ArrayList(u8).initCapacity(self.allocator, 16);
    defer buf.deinit(self.allocator);
    try appendTypeBindingString(self, &buf, t);
    return try self.allocator.dupe(u8, buf.items);
}

fn appendTypeBindingString(self: anytype, buf: *std.ArrayList(u8), t: Symbol.ZSTypeNotation) !void {
    switch (t) {
        .number => try buf.appendSlice(self.allocator, "number"),
        .boolean => try buf.appendSlice(self.allocator, "boolean"),
        .char => try buf.appendSlice(self.allocator, "char"),
        .long => try buf.appendSlice(self.allocator, "long"),
        .short => try buf.appendSlice(self.allocator, "short"),
        .byte => try buf.appendSlice(self.allocator, "byte"),
        .void => try buf.appendSlice(self.allocator, "void"),
        .unknown => try buf.appendSlice(self.allocator, "unknown"),
        .function => try buf.appendSlice(self.allocator, "function"),
        .pointer => |inner| {
            try buf.appendSlice(self.allocator, "Pointer$");
            try appendTypeBindingString(self, buf, inner.*);
        },
        .array_type => |arr| {
            try buf.appendSlice(self.allocator, "Array$");
            try appendTypeBindingString(self, buf, arr.element_type.*);
        },
        .struct_type => |st| {
            try buf.appendSlice(self.allocator, st.name);
            for (st.type_args) |ta| {
                try buf.append(self.allocator, '$');
                try appendTypeBindingString(self, buf, ta);
            }
        },
        .enum_type => |et| {
            try buf.appendSlice(self.allocator, et.name);
            for (et.type_args) |ta| {
                try buf.append(self.allocator, '$');
                try appendTypeBindingString(self, buf, ta);
            }
        },
    }
}
