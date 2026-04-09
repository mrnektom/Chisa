const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const type_resolver = @import("type_resolver.zig");
const computeMangledName = @import("ZenScript").MangleHelpers.computeMangledName;

const OverloadEntry = @import("analyzer.zig").OverloadEntry;
const GenericFnDef = @import("analyzer.zig").GenericFnDef;
const Error = @import("analyzer.zig").Error;

fn callResolutionKey(startPos: usize, endPos: usize) usize {
    return std.hash.Wyhash.hash(0, std.mem.asBytes(&[_]usize{ startPos, endPos }));
}

pub fn analyzeCall(self: anytype, call: ast.expr.ZSCall) Error!Symbol.ZSTypeNotation {
    // Get the function name from the subject
    const subject = call.subject.*;
    const fnName: ?[]const u8 = switch (subject) {
        .reference => subject.reference.name,
        else => null,
    };

    // Handle ptr/deref intrinsics
    if (fnName) |name| {
        if (std.mem.eql(u8, name, "ptr")) {
            if (call.arguments.len != 1) {
                try self.recordError(call, "ptr() expects exactly 1 argument");
                return Symbol.ZSTypeNotation.unknown;
            }
            const argType = try self.analyzeExpr(call.arguments[0]);
            const innerPtr = try self.allocator.create(Symbol.ZSTypeNotation);
            innerPtr.* = argType;
            try self.allocatedTypes.append(self.allocator, innerPtr);
            return Symbol.ZSTypeNotation{ .pointer = innerPtr };
        }
        if (std.mem.eql(u8, name, "deref")) {
            if (call.arguments.len != 1) {
                try self.recordError(call, "deref() expects exactly 1 argument");
                return Symbol.ZSTypeNotation.unknown;
            }
            const argType = try self.analyzeExpr(call.arguments[0]);
            const resultType = switch (argType) {
                .pointer => |inner| inner.*,
                .long, .number => Symbol.ZSTypeNotation.number,
                else => blk: {
                    try self.recordError(call, "deref() argument must be a pointer");
                    break :blk Symbol.ZSTypeNotation.unknown;
                },
            };
            try self.derefTypes.put(call.startPos, type_resolver.typeToString(resultType));
            return resultType;
        }

        if (std.mem.eql(u8, name, "free")) {
            if (call.arguments.len != 2) {
                try self.recordError(call, "free() expects exactly 2 arguments");
                return Symbol.ZSTypeNotation.unknown;
            }
            const ptrType = try self.analyzeExpr(call.arguments[0]);
            _ = try self.analyzeExpr(call.arguments[1]);
            if (ptrType != .pointer) {
                try self.recordError(call, "free() first argument must be a pointer");
            }
            return Symbol.ZSTypeNotation.unknown;
        }
    }

    // Handle extension function calls: expr.method(args)
    if (subject == .field_access) {
        const fa = subject.field_access;
        const savedExpected = self.expectedType;
        defer self.expectedType = savedExpected;
        if (savedExpected) |expectedResultType| {
            if (try inferExpectedReceiverTypeForExtensionCall(self, fa.field, expectedResultType)) |expectedReceiverType| {
                self.expectedType = expectedReceiverType;
            }
        }
        const receiverType = try self.analyzeExpr(fa.subject.*);
        const receiverTypeName = type_resolver.typeToString(receiverType);
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ receiverTypeName, fa.field });
        defer self.allocator.free(key);

        if (self.extensionFns.get(key)) |entries| {
            // Analyze arguments
            const extArgTypes = try self.allocator.alloc([]const u8, call.arguments.len);
            defer self.allocator.free(extArgTypes);
            for (call.arguments, 0..) |arg, i| {
                const argType = try self.analyzeExpr(arg);
                extArgTypes[i] = type_resolver.typeToString(argType);
            }

            // Find matching overload (args don't include receiver)
            var matched: ?OverloadEntry = null;
            for (entries.items) |entry| {
                if (entry.argTypes.len == extArgTypes.len) {
                    if (entry.external) {
                        matched = entry;
                        break;
                    }
                    var allMatch = true;
                    for (entry.argTypes, extArgTypes) |a, b| {
                        if (!std.mem.eql(u8, a, b)) {
                            if (!(type_resolver.isNumericType(a) and type_resolver.isNumericType(b))) {
                                allMatch = false;
                                break;
                            }
                        }
                    }
                    if (allMatch) {
                        matched = entry;
                        break;
                    }
                }
            }

            if (matched) |entry| {
                const keyPos = callResolutionKey(call.startPos, call.endPos);
                try self.resolutions.put(keyPos, entry.mangledName);
                try self.extensionCalls.put(keyPos, {});
                return entry.retType;
            } else {
                try self.recordError(call, "No matching extension function overload");
                return Symbol.ZSTypeNotation.unknown;
            }
        }

        // Fallback: try to monomorphize a generic extension method stored in genericFns
        // under key "ReceiverName.methodName" (e.g. "Option.map").
        if (try tryMonomorphizeExtensionCall(self, key, receiverType, call)) |retType| {
            return retType;
        }
    }

    if (fnName) |name| {
        if (!self.overloadedNames.contains(name)) {
            if (self.tableStack.get(name)) |sym| {
                if (sym.signature == .function) {
                    return try analyzeCallAgainstFunctionType(self, call, sym.signature.function);
                }
            }
        }
        if (try tryInferMonomorphizeCall(self, name, call)) |retType| {
            return retType;
        }
    }

    // Analyze all argument expressions and collect their types
    // These are static string literals from typeToString, no need to track
    const argTypes = try self.allocator.alloc([]const u8, call.arguments.len);
    defer self.allocator.free(argTypes);
    for (call.arguments, 0..) |arg, i| {
        const argType = try self.analyzeExpr(arg);
        argTypes[i] = type_resolver.typeToString(argType);
    }

    if (fnName) |name| {
        // Check if we have overloads for this function
        if (self.overloads.get(name)) |entries| {
            // Find matching overload
            var matched: ?OverloadEntry = null;
            for (entries.items) |entry| {
                if (entry.argTypes.len == argTypes.len) {
                    // External (built-in) functions accept any argument types
                    if (entry.external) {
                        matched = entry;
                        break;
                    }
                    var allMatch = true;
                    for (entry.argTypes, argTypes) |a, b| {
                        if (!std.mem.eql(u8, a, b)) {
                            // Allow numeric type compatibility
                            if (!(type_resolver.isNumericType(a) and type_resolver.isNumericType(b))) {
                                allMatch = false;
                                break;
                            }
                        }
                    }
                    if (allMatch) {
                        matched = entry;
                        break;
                    }
                }
            }

            if (matched) |entry| {
                // Determine the resolved name
                const isOverloaded = self.overloadedNames.contains(name);
                const resolvedName = if (isOverloaded and !entry.external)
                    entry.mangledName
                else
                    name;

                try self.resolutions.put(callResolutionKey(call.startPos, call.endPos), resolvedName);

                return entry.retType;
            } else {
                try self.recordError(call, "No matching overload");
                return Symbol.ZSTypeNotation.unknown;
            }
        }

        // Check if this is a generic function call (mangled name like "list_push$number")
        if (try tryMonomorphizeCall(self, name, argTypes, call.startPos, call.endPos)) |retType| {
            return retType;
        }
    }

    // Fallback: resolve via symbol table (for non-function-reference subjects)
    const subjectType = try self.analyzeExpr(call.subject.*);
    return switch (subjectType) {
        .function => subjectType.function.ret.*,
        .unknown => Symbol.ZSTypeNotation.unknown,
        else => blk: {
            try self.recordError(call, "Subject is not a function");
            break :blk Symbol.ZSTypeNotation.unknown;
        },
    };
}

pub fn analyzeBuiltin(self: anytype, builtin: ast.ZSBuiltin) !Symbol.ZSTypeNotation {
    _ = self;
    return switch (builtin) {
        .number => Symbol.ZSTypeNotation.number,
    };
}

fn analyzeCallAgainstFunctionType(
    self: anytype,
    call: ast.expr.ZSCall,
    fnType: sig.ZSFunction,
) Error!Symbol.ZSTypeNotation {
    if (call.arguments.len != fnType.args.len) {
        try self.recordError(call, "Wrong number of arguments");
        return Symbol.ZSTypeNotation.unknown;
    }

    for (call.arguments, 0..) |arg, i| {
        const savedExpected = self.expectedType;
        self.expectedType = fnType.args[i].type;
        const argType = try self.analyzeExpr(arg);
        self.expectedType = savedExpected;

        const expectedArgType = fnType.args[i].type;
        if (argType != .unknown and expectedArgType != .unknown and
            !type_resolver.typesCompatible(expectedArgType, argType))
        {
            try self.recordError(call, "Argument type mismatch");
            return Symbol.ZSTypeNotation.unknown;
        }
    }

    return fnType.ret.*;
}

/// Try to monomorphize a generic function call.
/// The parser mangles `list_push<number>(...)` into a reference named `list_push$number`.
/// This function splits the mangled name, looks up the generic template, monomorphizes it,
/// and registers the concrete function.
pub fn tryMonomorphizeCall(self: anytype, mangledName: []const u8, _: []const []const u8, callStartPos: usize, callEndPos: usize) Error!?Symbol.ZSTypeNotation {
    // Split mangled name on '$' to get base name and explicit type args
    const dollarIdx = std.mem.indexOfScalar(u8, mangledName, '$') orelse return null;
    const baseName = mangledName[0..dollarIdx];

    const gfn = self.genericFns.get(baseName) orelse return null;

    // Parse explicit type args from mangled name (e.g., "number$char" -> ["number", "char"])
    var bindings = try std.ArrayList([]const u8).initCapacity(self.allocator, gfn.type_params.len);
    defer bindings.deinit(self.allocator);
    var rest = mangledName[dollarIdx + 1 ..];
    while (rest.len > 0) {
        if (std.mem.indexOfScalar(u8, rest, '$')) |nextDollar| {
            try bindings.append(self.allocator, rest[0..nextDollar]);
            rest = rest[nextDollar + 1 ..];
        } else {
            try bindings.append(self.allocator, rest);
            break;
        }
    }

    if (bindings.items.len != gfn.type_params.len) return null;

    // Substitute type params in bindings using active bindings context
    // (e.g., when inside list_push$number body, list_grow$T becomes list_grow$number)
    for (bindings.items, 0..) |b, i| {
        bindings.items[i] = type_resolver.substituteTypeParamName(self, b);
    }

    // Compute the resolved mangled name (after substitution)
    var resolvedMangledBuf = try std.ArrayList(u8).initCapacity(self.allocator, mangledName.len + 16);
    defer resolvedMangledBuf.deinit(self.allocator);
    try resolvedMangledBuf.appendSlice(self.allocator, baseName);
    for (bindings.items) |b| {
        try resolvedMangledBuf.append(self.allocator, '$');
        try resolvedMangledBuf.appendSlice(self.allocator, b);
    }
    const resolvedMangledName = try self.allocator.dupe(u8, resolvedMangledBuf.items);
    try self.allocatedStrings.append(self.allocator, resolvedMangledName);

    // Check if already monomorphized
    if (self.monomorphizedFns.contains(resolvedMangledName)) {
        // Already done — just resolve the call and return the type
        try self.resolutions.put(callResolutionKey(callStartPos, callEndPos), resolvedMangledName);
        return try type_resolver.resolveConcreteRetType(self, gfn, bindings.items);
    }

    // Monomorphize the function
    const concreteFn = try monomorphizeFunction(self, gfn, bindings.items, resolvedMangledName);

    // Track it
    try self.monomorphizedFns.put(resolvedMangledName, {});

    // Register as a normal function (it has type_params = &.{} now)
    try self.registerFunction(concreteFn);

    // Analyze the function body with type param bindings in scope
    const savedBindings = self.typeParamBindings;
    self.typeParamBindings = .{
        .typeParams = gfn.type_params,
        .bindings = bindings.items,
    };
    defer self.typeParamBindings = savedBindings;
    _ = try self.analyzeFunction(concreteFn);

    // Add to monomorphized functions list for IR gen
    try self.monomorphizedFunctions.append(self.allocator, concreteFn);

    // Resolve the call to the monomorphized name
    try self.resolutions.put(callResolutionKey(callStartPos, callEndPos), resolvedMangledName);

    // Return the concrete return type
    return try type_resolver.resolveConcreteRetType(self, gfn, bindings.items);
}

pub fn tryInferMonomorphizeCall(self: anytype, name: []const u8, call: ast.expr.ZSCall) Error!?Symbol.ZSTypeNotation {
    if (std.mem.indexOfScalar(u8, name, '$') != null) return null;

    const gfn = self.genericFns.get(name) orelse return null;
    const func = gfn.func;
    if (gfn.type_params.len == 0) return null;

    const localBindings = try self.allocator.alloc([]const u8, gfn.type_params.len);
    defer self.allocator.free(localBindings);
    const localSymbolBindings = try self.allocator.alloc(Symbol.ZSTypeNotation, gfn.type_params.len);
    defer self.allocator.free(localSymbolBindings);
    for (localBindings) |*binding| binding.* = "unknown";
    for (localSymbolBindings) |*binding| binding.* = .unknown;

    const outerCount: usize = if (self.typeParamBindings) |outer| outer.typeParams.len else 0;
    const combinedTypeParams = try self.allocator.alloc([]const u8, outerCount + gfn.type_params.len);
    defer self.allocator.free(combinedTypeParams);
    const combinedBindings = try self.allocator.alloc([]const u8, outerCount + gfn.type_params.len);
    defer self.allocator.free(combinedBindings);
    const combinedSymbolBindings = try self.allocator.alloc(Symbol.ZSTypeNotation, outerCount + gfn.type_params.len);
    defer self.allocator.free(combinedSymbolBindings);

    if (self.typeParamBindings) |outer| {
        for (outer.typeParams, 0..) |tp, i| combinedTypeParams[i] = tp;
        for (outer.bindings, 0..) |binding, i| combinedBindings[i] = binding;
    }
    if (self.typeParamSymbolBindings) |outer| {
        for (outer.bindings, 0..) |binding, i| combinedSymbolBindings[i] = binding;
    } else {
        for (0..outerCount) |i| combinedSymbolBindings[i] = .unknown;
    }
    for (gfn.type_params, 0..) |tp, i| {
        combinedTypeParams[outerCount + i] = tp;
        combinedBindings[outerCount + i] = localBindings[i];
        combinedSymbolBindings[outerCount + i] = localSymbolBindings[i];
    }

    const savedBindingsForInfer = self.typeParamBindings;
    const savedSymbolBindingsForInfer = self.typeParamSymbolBindings;
    self.typeParamBindings = .{
        .typeParams = combinedTypeParams,
        .bindings = combinedBindings,
    };
    self.typeParamSymbolBindings = .{
        .typeParams = combinedTypeParams,
        .bindings = combinedSymbolBindings,
    };
    defer {
        self.typeParamBindings = savedBindingsForInfer;
        self.typeParamSymbolBindings = savedSymbolBindingsForInfer;
    }

    if (self.expectedType) |expected| {
        if (func.ret) |retAnnot| {
            for (gfn.type_params, 0..) |paramName, pi| {
                if (!std.mem.eql(u8, localBindings[pi], "unknown") or !typeAnnotationRefersTo(retAnnot, paramName)) continue;

                localSymbolBindings[pi] = inferTypeParamFromArg(
                    retAnnot,
                    expected,
                    paramName,
                    combinedTypeParams,
                    combinedSymbolBindings,
                );
                if (localSymbolBindings[pi] == .unknown) continue;

                localBindings[pi] = try type_resolver.typeToBindingString(self, localSymbolBindings[pi]);
                try self.allocatedStrings.append(self.allocator, localBindings[pi]);
                combinedBindings[outerCount + pi] = localBindings[pi];
                combinedSymbolBindings[outerCount + pi] = localSymbolBindings[pi];
            }
        }
    }

    for (func.args, 0..) |declArg, ai| {
        if (ai >= call.arguments.len) break;
        const declType = declArg.type orelse continue;

        const savedExpected = self.expectedType;
        self.expectedType = try type_resolver.resolveTypeAnnotationFull(self, declType);
        const actualArgType = try self.analyzeExpr(call.arguments[ai]);
        self.expectedType = savedExpected;

        for (gfn.type_params, 0..) |paramName, pi| {
            if (localSymbolBindings[pi] != .unknown or !typeAnnotationRefersTo(declType, paramName)) continue;

            localSymbolBindings[pi] = inferTypeParamFromArg(
                declType,
                actualArgType,
                paramName,
                combinedTypeParams,
                combinedSymbolBindings,
            );
            if (localSymbolBindings[pi] == .unknown) continue;

            localBindings[pi] = try type_resolver.typeToBindingString(self, localSymbolBindings[pi]);
            try self.allocatedStrings.append(self.allocator, localBindings[pi]);
            combinedBindings[outerCount + pi] = localBindings[pi];
            combinedSymbolBindings[outerCount + pi] = localSymbolBindings[pi];
        }
    }

    for (localBindings) |binding| {
        if (std.mem.eql(u8, binding, "unknown")) return null;
    }

    var mangledBuf = try std.ArrayList(u8).initCapacity(self.allocator, name.len + 16);
    defer mangledBuf.deinit(self.allocator);
    try mangledBuf.appendSlice(self.allocator, name);
    for (localBindings) |binding| {
        try mangledBuf.append(self.allocator, '$');
        try mangledBuf.appendSlice(self.allocator, binding);
    }
    const mangledName = try self.allocator.dupe(u8, mangledBuf.items);
    try self.allocatedStrings.append(self.allocator, mangledName);

    if (self.monomorphizedFns.contains(mangledName)) {
        try self.resolutions.put(callResolutionKey(call.startPos, call.endPos), mangledName);
        return try type_resolver.resolveConcreteRetTypeWithSymbolBindings(self, gfn, localSymbolBindings);
    }

    const concreteFn = try monomorphizeFunctionWithSymbolBindings(self, gfn, gfn.type_params, localSymbolBindings, mangledName);

    try self.monomorphizedFns.put(mangledName, {});
    try self.registerFunction(concreteFn);

    const savedBindings = self.typeParamBindings;
    const savedSymbolBindings = self.typeParamSymbolBindings;
    self.typeParamBindings = .{
        .typeParams = combinedTypeParams,
        .bindings = combinedBindings,
    };
    self.typeParamSymbolBindings = .{
        .typeParams = combinedTypeParams,
        .bindings = combinedSymbolBindings,
    };
    defer {
        self.typeParamBindings = savedBindings;
        self.typeParamSymbolBindings = savedSymbolBindings;
    }
    _ = try self.analyzeFunction(concreteFn);

    try self.monomorphizedFunctions.append(self.allocator, concreteFn);
    try self.resolutions.put(callResolutionKey(call.startPos, call.endPos), mangledName);

    return try type_resolver.resolveConcreteRetTypeWithSymbolBindings(self, gfn, localSymbolBindings);
}

/// Create a concrete (monomorphized) function by substituting type params with concrete types.
pub fn monomorphizeFunction(self: anytype, gfn: GenericFnDef, bindings: []const []const u8, mangledName: []const u8) !ast.stmt.ZSFn {
    const newArgs = try self.allocator.alloc(ast.stmt.ZSFn.Arg, gfn.func.args.len);
    for (gfn.func.args, 0..) |arg, i| {
        newArgs[i] = .{
            .name = arg.name,
            .type = if (arg.type) |t| try type_resolver.substituteAstType(self, t, gfn.type_params, bindings) else null,
        };
    }

    const newRet: ?ast.ZSTypeNotation = if (gfn.func.ret) |r| try type_resolver.substituteAstType(self, r, gfn.type_params, bindings) else null;

    return ast.stmt.ZSFn{
        .name = mangledName,
        .receiver_type = null,
        .receiver_type_params = &.{},
        .type_params = &.{},
        .args = newArgs,
        .ret = newRet,
        .modifiers = gfn.func.modifiers,
        .body = gfn.func.body, // reuse the same AST body
    };
}

fn monomorphizeFunctionWithSymbolBindings(
    self: anytype,
    gfn: GenericFnDef,
    typeParams: []const []const u8,
    bindings: []const Symbol.ZSTypeNotation,
    mangledName: []const u8,
) !ast.stmt.ZSFn {
    const newArgs = try self.allocator.alloc(ast.stmt.ZSFn.Arg, gfn.func.args.len);
    for (gfn.func.args, 0..) |arg, i| {
        newArgs[i] = .{
            .name = arg.name,
            .type = if (arg.type) |t| try type_resolver.substituteAstTypeWithSymbolBindings(self, t, typeParams, bindings) else null,
        };
    }

    const newRet: ?ast.ZSTypeNotation = if (gfn.func.ret) |r|
        try type_resolver.substituteAstTypeWithSymbolBindings(self, r, typeParams, bindings)
    else
        null;

    return ast.stmt.ZSFn{
        .name = mangledName,
        .receiver_type = null,
        .receiver_type_params = &.{},
        .type_params = &.{},
        .args = newArgs,
        .ret = newRet,
        .modifiers = gfn.func.modifiers,
        .body = gfn.func.body,
    };
}

/// Try to monomorphize a generic extension method call.
/// Called when extensionFns lookup fails but the method may be stored as a generic
/// extension in genericFns under key "ReceiverName.methodName".
///
/// For example, `Option<T>.map<U>` is stored in genericFns["Option.map"] with
/// receiver_type_params=["T"] and type_params=["U"].  When called on Option<number>,
/// we bind T=number from the receiver's type_args, then infer U by analyzing the
/// first function argument against the declared parameter type.
pub fn tryMonomorphizeExtensionCall(
    self: anytype,
    key: []const u8, // e.g. "Option.map"
    receiverType: Symbol.ZSTypeNotation,
    call: ast.expr.ZSCall,
) Error!?Symbol.ZSTypeNotation {
    const gfn = self.genericFns.get(key) orelse return null;
    const func = gfn.func;

    const allTypeParams = gfn.type_params;
    const numRecvParams = func.receiver_type_params.len;
    const numFnParams = func.type_params.len;
    const totalParams = allTypeParams.len;
    if (totalParams == 0) return null;

    const allBindings = try self.allocator.alloc([]const u8, totalParams);
    defer self.allocator.free(allBindings);
    const allSymbolBindings = try self.allocator.alloc(Symbol.ZSTypeNotation, totalParams);
    defer self.allocator.free(allSymbolBindings);

    const receiverTypeArgs: []const Symbol.ZSTypeNotation = switch (receiverType) {
        .enum_type => |et| et.type_args,
        .struct_type => |st| st.type_args,
        else => &.{},
    };
    for (0..totalParams) |i| {
        allSymbolBindings[i] = .unknown;
        allBindings[i] = "unknown";
    }
    for (0..numRecvParams) |i| {
        if (i < receiverTypeArgs.len) {
            allSymbolBindings[i] = receiverTypeArgs[i];
            allBindings[i] = try type_resolver.typeToBindingString(self, receiverTypeArgs[i]);
            try self.allocatedStrings.append(self.allocator, allBindings[i]);
        } else {
            allSymbolBindings[i] = .unknown;
            allBindings[i] = "unknown";
        }
    }

    const savedBindingsForInfer = self.typeParamBindings;
    const savedSymbolBindingsForInfer = self.typeParamSymbolBindings;
    self.typeParamBindings = .{
        .typeParams = allTypeParams,
        .bindings = allBindings,
    };
    self.typeParamSymbolBindings = .{
        .typeParams = allTypeParams,
        .bindings = allSymbolBindings,
    };
    defer {
        self.typeParamBindings = savedBindingsForInfer;
        self.typeParamSymbolBindings = savedSymbolBindingsForInfer;
    }

    if (self.expectedType) |expected| {
        if (func.ret) |retAnnot| {
            for (0..numFnParams) |fi| {
                const paramName = func.type_params[fi];
                if (!std.mem.eql(u8, allBindings[numRecvParams + fi], "unknown") or !typeAnnotationRefersTo(retAnnot, paramName)) continue;

                const inferred = inferTypeParamFromArg(retAnnot, expected, paramName, allTypeParams, allSymbolBindings);
                if (inferred == .unknown) continue;

                allSymbolBindings[numRecvParams + fi] = inferred;
                allBindings[numRecvParams + fi] = try type_resolver.typeToBindingString(self, inferred);
                try self.allocatedStrings.append(self.allocator, allBindings[numRecvParams + fi]);
            }
        }
    }

    for (0..numFnParams) |fi| {
        const paramName = func.type_params[fi];
        var inferred: Symbol.ZSTypeNotation = .unknown;

        for (func.args, 0..) |declArg, ai| {
            if (ai >= call.arguments.len) break;
            if (declArg.type) |declType| {
                if (typeAnnotationRefersTo(declType, paramName)) {
                    const savedExpected = self.expectedType;
                    self.expectedType = try type_resolver.resolveTypeAnnotationFull(self, declType);
                    const actualArgType = try self.analyzeExpr(call.arguments[ai]);
                    self.expectedType = savedExpected;
                    inferred = inferTypeParamFromArg(declType, actualArgType, paramName, allTypeParams, allSymbolBindings);
                    break;
                }
            }
        }

        allSymbolBindings[numRecvParams + fi] = inferred;
        allBindings[numRecvParams + fi] = if (inferred != .unknown)
            try type_resolver.typeToBindingString(self, inferred)
        else
            "unknown";
        if (inferred != .unknown) {
            try self.allocatedStrings.append(self.allocator, allBindings[numRecvParams + fi]);
        }
    }

    for (allBindings[numRecvParams..]) |binding| {
        if (std.mem.eql(u8, binding, "unknown")) return null;
    }

    var mangledBuf = try std.ArrayList(u8).initCapacity(self.allocator, key.len + 32);
    defer mangledBuf.deinit(self.allocator);
    try mangledBuf.appendSlice(self.allocator, key);
    for (allBindings) |b| {
        try mangledBuf.append(self.allocator, '$');
        try mangledBuf.appendSlice(self.allocator, b);
    }
    const mangledName = try self.allocator.dupe(u8, mangledBuf.items);
    try self.allocatedStrings.append(self.allocator, mangledName);

    if (!self.monomorphizedFns.contains(mangledName)) {
        const concreteFn = try monomorphizeGenericExtension(self, gfn, allTypeParams, allSymbolBindings, mangledName);
        try self.monomorphizedFns.put(mangledName, {});
        try self.registerFunction(concreteFn);

        const savedBindings = self.typeParamBindings;
        const savedSymbolBindings = self.typeParamSymbolBindings;
        self.typeParamBindings = .{
            .typeParams = allTypeParams,
            .bindings = allBindings,
        };
        self.typeParamSymbolBindings = .{
            .typeParams = allTypeParams,
            .bindings = allSymbolBindings,
        };
        defer {
            self.typeParamBindings = savedBindings;
            self.typeParamSymbolBindings = savedSymbolBindings;
        }
        _ = try self.analyzeFunction(concreteFn);

        try self.monomorphizedFunctions.append(self.allocator, concreteFn);
    }

    const keyPos = callResolutionKey(call.startPos, call.endPos);
    try self.resolutions.put(keyPos, mangledName);
    try self.extensionCalls.put(keyPos, {});

    return try resolveRetTypeWithBindings(self, func.ret, allTypeParams, allSymbolBindings);
}

/// Check whether an AST type annotation references a given type param name.
fn typeAnnotationRefersTo(t: ast.ZSTypeNotation, paramName: []const u8) bool {
    return switch (t) {
        .reference => |ref| std.mem.eql(u8, ref, paramName),
        .generic => |g| blk: {
            for (g.type_args) |ta| {
                if (typeAnnotationRefersTo(ta, paramName)) break :blk true;
            }
            break :blk false;
        },
        .fn_type => |ft| blk: {
            for (ft.param_types) |pt| {
                if (typeAnnotationRefersTo(pt, paramName)) break :blk true;
            }
            break :blk typeAnnotationRefersTo(ft.return_type.*, paramName);
        },
        .array => |a| typeAnnotationRefersTo(a.element_type.*, paramName),
    };
}

/// Given a declared arg type (e.g. `(T) -> U`) and the actual arg type (e.g. `function`),
/// infer the binding for `paramName`.
fn inferTypeParamFromArg(
    declType: ast.ZSTypeNotation,
    actualType: Symbol.ZSTypeNotation,
    paramName: []const u8,
    allTypeParams: []const []const u8,
    allBindings: []const Symbol.ZSTypeNotation,
) Symbol.ZSTypeNotation {
    switch (declType) {
        .reference => |ref| {
            if (std.mem.eql(u8, ref, paramName)) {
                return actualType;
            }
        },
        .fn_type => |ft| {
            if (actualType == .function) {
                const actualFn = actualType.function;
                // Recurse into the return type rather than calling typeToString directly.
                // This handles cases where paramName is wrapped inside a generic in the
                // return position (e.g. declared "(T)->Option<U>", actual "(number)->Option<number>"):
                // typeToString would produce "Option" instead of "number".
                if (typeAnnotationRefersTo(ft.return_type.*, paramName)) {
                    const result = inferTypeParamFromArg(ft.return_type.*, actualFn.ret.*, paramName, allTypeParams, allBindings);
                    if (result != .unknown) return result;
                }
                // Recurse into each param type for the same reason.
                for (ft.param_types, 0..) |pt, i| {
                    if (i < actualFn.args.len and typeAnnotationRefersTo(pt, paramName)) {
                        const result = inferTypeParamFromArg(pt, actualFn.args[i].type, paramName, allTypeParams, allBindings);
                        if (result != .unknown) return result;
                    }
                }
            }
        },
        .generic => |g| {
            switch (actualType) {
                .enum_type => |et| {
                    if (std.mem.eql(u8, et.name, g.name)) {
                        for (g.type_args, 0..) |argTypeAnnot, i| {
                            if (i < et.type_args.len) {
                                const result = inferTypeParamFromArg(argTypeAnnot, et.type_args[i], paramName, allTypeParams, allBindings);
                                if (result != .unknown) return result;
                            }
                        }
                    }
                },
                .struct_type => |st| {
                    if (std.mem.eql(u8, st.name, g.name)) {
                        for (g.type_args, 0..) |argTypeAnnot, i| {
                            if (i < st.type_args.len) {
                                const result = inferTypeParamFromArg(argTypeAnnot, st.type_args[i], paramName, allTypeParams, allBindings);
                                if (result != .unknown) return result;
                            }
                        }
                    }
                },
                else => {},
            }
        },
        .array => |elem| {
            switch (actualType) {
                .array_type => |actualElem| {
                    return inferTypeParamFromArg(elem.element_type.*, actualElem.element_type.*, paramName, allTypeParams, allBindings);
                },
                else => {},
            }
        },
    }
    // Fall back to checking existing bindings
    for (allTypeParams, 0..) |tp, i| {
        if (std.mem.eql(u8, tp, paramName)) {
            if (i < allBindings.len) return allBindings[i];
        }
    }
    return .unknown;
}

/// Monomorphize a generic extension method: substitute all type params (receiver + fn level).
fn monomorphizeGenericExtension(
    self: anytype,
    gfn: GenericFnDef,
    allTypeParams: []const []const u8,
    allBindings: []const Symbol.ZSTypeNotation,
    mangledName: []const u8,
) !ast.stmt.ZSFn {
    const concreteReceiverType: ?[]const u8 = if (gfn.func.receiver_type) |receiver| blk: {
        if (gfn.func.receiver_type_params.len == 0) break :blk receiver;

        const receiverBindings = allBindings[0..gfn.func.receiver_type_params.len];
        if (self.enumDefs.contains(receiver)) {
            break :blk try type_resolver.computeEnumMangledName(self, receiver, receiverBindings);
        }
        if (self.structDefs.contains(receiver)) {
            const bindingNames = try self.allocator.alloc([]const u8, receiverBindings.len);
            defer self.allocator.free(bindingNames);
            for (receiverBindings, 0..) |binding, i| {
                bindingNames[i] = try type_resolver.typeToBindingString(self, binding);
                try self.allocatedStrings.append(self.allocator, bindingNames[i]);
            }
            const concrete = try computeMangledName(self.allocator, receiver, bindingNames);
            try self.allocatedStrings.append(self.allocator, concrete);
            break :blk concrete;
        }
        break :blk receiver;
    } else null;

    const newArgs = try self.allocator.alloc(ast.stmt.ZSFn.Arg, gfn.func.args.len);
    for (gfn.func.args, 0..) |arg, i| {
        newArgs[i] = .{
            .name = arg.name,
            .type = if (arg.type) |t| try type_resolver.substituteAstTypeWithSymbolBindings(self, t, allTypeParams, allBindings) else null,
        };
    }

    const newRet: ?ast.ZSTypeNotation = if (gfn.func.ret) |r|
        try type_resolver.substituteAstTypeWithSymbolBindings(self, r, allTypeParams, allBindings)
    else
        null;

    return ast.stmt.ZSFn{
        .name = mangledName,
        .receiver_type = concreteReceiverType,
        .receiver_type_params = &.{},
        .type_params = &.{},
        .args = newArgs,
        .ret = newRet,
        .modifiers = gfn.func.modifiers,
        .body = gfn.func.body,
    };
}

/// Resolve the return type of a function with a custom set of type param bindings.
fn resolveRetTypeWithBindings(
    self: anytype,
    retAnnotation: ?ast.ZSTypeNotation,
    allTypeParams: []const []const u8,
    allBindings: []const Symbol.ZSTypeNotation,
) Error!Symbol.ZSTypeNotation {
    const ret = retAnnotation orelse return Symbol.ZSTypeNotation.unknown;
    const substituted = try type_resolver.substituteAstTypeWithSymbolBindings(self, ret, allTypeParams, allBindings);
    return try type_resolver.resolveTypeAnnotationFull(self, substituted);
}

fn inferExpectedReceiverTypeForExtensionCall(
    self: anytype,
    methodName: []const u8,
    expectedResultType: Symbol.ZSTypeNotation,
) Error!?Symbol.ZSTypeNotation {
    var iter = self.genericFns.iterator();
    var resolved: ?Symbol.ZSTypeNotation = null;

    while (iter.next()) |entry| {
        const key = entry.key_ptr.*;
        const dotIdx = std.mem.lastIndexOfScalar(u8, key, '.') orelse continue;
        if (!std.mem.eql(u8, key[dotIdx + 1 ..], methodName)) continue;

        const candidate = try inferExpectedReceiverTypeFromGenericExtension(self, entry.value_ptr.*, expectedResultType);
        if (candidate == null or candidate.? == .unknown) continue;

        if (resolved) |existing| {
            if (!type_resolver.typesCompatible(existing, candidate.?) or !type_resolver.typesCompatible(candidate.?, existing)) {
                return null;
            }
        } else {
            resolved = candidate.?;
        }
    }

    return resolved;
}

fn inferExpectedReceiverTypeFromGenericExtension(
    self: anytype,
    gfn: GenericFnDef,
    expectedResultType: Symbol.ZSTypeNotation,
) Error!?Symbol.ZSTypeNotation {
    const receiverName = gfn.func.receiver_type orelse return null;
    const receiverParamCount = gfn.func.receiver_type_params.len;
    const totalParams = gfn.type_params.len;
    if (totalParams == 0) return null;

    const symbolBindings = try self.allocator.alloc(Symbol.ZSTypeNotation, totalParams);
    defer self.allocator.free(symbolBindings);
    for (symbolBindings) |*binding| binding.* = .unknown;

    if (gfn.func.ret) |retAnnot| {
        for (gfn.func.type_params, 0..) |paramName, fi| {
            const bindingIndex = receiverParamCount + fi;
            if (!typeAnnotationRefersTo(retAnnot, paramName)) continue;

            const inferred = inferTypeParamFromArg(retAnnot, expectedResultType, paramName, gfn.type_params, symbolBindings);
            if (inferred != .unknown) {
                symbolBindings[bindingIndex] = inferred;
            }
        }
    }

    const receiverTypeAst = if (receiverParamCount == 0)
        ast.ZSTypeNotation{ .reference = receiverName }
    else blk: {
        const typeArgs = try self.allocator.alloc(ast.type_notation.ZSTypeNotation, receiverParamCount);
        try self.allocatedAstTypeSlices.append(self.allocator, typeArgs);
        for (gfn.func.receiver_type_params, 0..) |paramName, i| {
            typeArgs[i] = if (symbolBindings[i] == .unknown)
                ast.ZSTypeNotation{ .reference = paramName }
            else
                try type_resolver.symbolTypeToAstAnnotation(self, symbolBindings[i]);
        }
        break :blk ast.ZSTypeNotation{ .generic = .{ .name = receiverName, .type_args = typeArgs } };
    };

    return try type_resolver.resolveTypeAnnotationFull(self, receiverTypeAst);
}
