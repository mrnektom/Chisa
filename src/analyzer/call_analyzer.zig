const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const type_resolver = @import("type_resolver.zig");
const computeMangledName = @import("ZenScript").MangleHelpers.computeMangledName;

const OverloadEntry = @import("analyzer.zig").OverloadEntry;
const GenericFnDef = @import("analyzer.zig").GenericFnDef;
const Error = @import("analyzer.zig").Error;

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
                try self.resolutions.put(call.startPos, entry.mangledName);
                try self.extensionCalls.put(call.startPos, {});
                return entry.retType;
            } else {
                try self.recordError(call, "No matching extension function overload");
                return Symbol.ZSTypeNotation.unknown;
            }
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

                try self.resolutions.put(call.startPos, resolvedName);

                return entry.retType;
            } else {
                try self.recordError(call, "No matching overload");
                return Symbol.ZSTypeNotation.unknown;
            }
        }

        // Check if this is a generic function call (mangled name like "list_push$number")
        if (try tryMonomorphizeCall(self, name, argTypes, call.startPos)) |retType| {
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

/// Try to monomorphize a generic function call.
/// The parser mangles `list_push<number>(...)` into a reference named `list_push$number`.
/// This function splits the mangled name, looks up the generic template, monomorphizes it,
/// and registers the concrete function.
pub fn tryMonomorphizeCall(self: anytype, mangledName: []const u8, _: []const []const u8, callStartPos: usize) Error!?Symbol.ZSTypeNotation {
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
        try self.resolutions.put(callStartPos, resolvedMangledName);
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
    try self.resolutions.put(callStartPos, resolvedMangledName);

    // Return the concrete return type
    return try type_resolver.resolveConcreteRetType(self, gfn, bindings.items);
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
