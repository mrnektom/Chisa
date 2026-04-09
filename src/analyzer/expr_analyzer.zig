const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const sts = @import("symbol_table_stack.zig");
const SymbolTable = sts.SymbolTable;
const type_resolver = @import("type_resolver.zig");

const Error = @import("analyzer.zig").Error;

pub fn analyzeExpr(self: anytype, expr: ast.expr.ZSExpr) Error!Symbol.ZSTypeNotation {
    return switch (expr) {
        .number => Symbol.ZSTypeNotation.number,
        .string => try type_resolver.getStringStructType(self),
        .char => Symbol.ZSTypeNotation.char,
        .boolean => Symbol.ZSTypeNotation.boolean,
        .call => self.analyzeCall(expr.call),
        .reference => analyzeReference(self, expr.reference),
        .if_expr => analyzeIfExpr(self, expr.if_expr),
        .while_expr => analyzeWhileExpr(self, expr.while_expr),
        .for_expr => analyzeForExpr(self, expr.for_expr),
        .binary => analyzeBinary(self, expr.binary),
        .unary => analyzeUnary(self, expr.unary),
        .block => analyzeBlock(self, expr.block),
        .return_expr => analyzeReturn(self, expr.return_expr),
        .break_expr => analyzeBreak(self, expr.break_expr),
        .continue_expr => analyzeContinue(self, expr.continue_expr),
        .struct_init => self.analyzeStructInit(expr.struct_init),
        .field_access => self.analyzeFieldAccess(expr.field_access),
        .array_literal => self.analyzeArrayLiteral(expr.array_literal),
        .index_access => self.analyzeIndexAccess(expr.index_access),
        .enum_init => self.analyzeEnumInit(expr.enum_init),
        .match_expr => self.analyzeMatchExpr(expr.match_expr),
        .lambda => analyzeLambda(self, expr.lambda),
        .safe_nav => analyzeSafeNav(self, expr.safe_nav),
    };
}

pub fn analyzeLambda(self: anytype, lambda: ast.expr.ZSLambda) Error!Symbol.ZSTypeNotation {
    // Generate a name for this lambda
    const lambdaName = try std.fmt.allocPrint(self.allocator, "__lambda_{d}", .{self.lambdaCount});
    self.lambdaCount += 1;
    try self.allocatedStrings.append(self.allocator, lambdaName);
    try self.lambdaNames.put(lambda.startPos, lambdaName);

    // Analyze the lambda body in a new scope with params as symbols
    var scope = SymbolTable.init(self.allocator);
    defer scope.deinit();
    try self.tableStack.enterScope(&scope);

    // Extract expected function arg types from context (e.g., when expectedType is a fn type)
    const expectedFnArgs: ?[]const sig.ZSFnArg = if (self.expectedType) |et|
        if (et == .function) et.function.args else null
    else
        null;

    const synthesizedImplicitIt = lambda.implicit_params_from_context and expectedFnArgs != null and expectedFnArgs.?.len == 1;
    if (lambda.implicit_params_from_context and expectedFnArgs != null and expectedFnArgs.?.len > 1) {
        try self.recordError(lambda, "shorthand lambda requires an expected function type with at most one parameter");
    }

    if (synthesizedImplicitIt) {
        try self.tableStack.put(.{
            .name = "it",
            .assignable = true,
            .signature = expectedFnArgs.?[0].type,
        });
    }

    for (lambda.params, 0..) |param, pi| {
        const paramSig = if (param.type) |pt|
            try type_resolver.resolveTypeAnnotationFull(self, pt)
        else if (expectedFnArgs) |efa|
            if (pi < efa.len) efa[pi].type else Symbol.ZSTypeNotation.unknown
        else blk: {
            const msg = try std.fmt.allocPrint(self.allocator, "cannot infer type of lambda parameter '{s}': add a type annotation", .{param.name});
            try self.allocatedStrings.append(self.allocator, msg);
            try self.recordError(lambda, msg);
            break :blk Symbol.ZSTypeNotation.unknown;
        };
        try self.tableStack.put(.{
            .name = param.name,
            .assignable = true,
            .signature = paramSig,
        });
    }

    const expectedFnRet: ?Symbol.ZSTypeNotation = if (self.expectedType) |et|
        if (et == .function) et.function.ret.* else null
    else
        null;

    const savedExpected = self.expectedType;
    if (expectedFnRet) |ret| {
        self.expectedType = ret;
    }
    const retType = try self.analyzeExpr(lambda.body.*);
    self.expectedType = savedExpected;
    _ = try self.tableStack.exitScope();

    // Build function type
    const retPtr = try self.allocator.create(Symbol.ZSTypeNotation);
    retPtr.* = retType;
    try self.allocatedTypes.append(self.allocator, retPtr);

    const paramCount = lambda.params.len + @as(usize, if (synthesizedImplicitIt) 1 else 0);
    const args = try self.allocator.alloc(sig.ZSFnArg, paramCount);
    try self.allocatedFnArgs.append(self.allocator, args);
    var argIndex: usize = 0;
    if (synthesizedImplicitIt) {
        args[0] = .{ .name = "it", .type = expectedFnArgs.?[0].type };
        argIndex = 1;
    }
    for (lambda.params, 0..) |param, i| {
        const argType = if (param.type) |pt|
            try type_resolver.resolveTypeAnnotationFull(self, pt)
        else if (expectedFnArgs) |efa|
            if (i < efa.len) efa[i].type else Symbol.ZSTypeNotation.unknown
        else
            Symbol.ZSTypeNotation.unknown;
        args[argIndex + i] = .{ .name = param.name, .type = argType };
    }

    const fnType = Symbol.ZSTypeNotation{ .function = .{ .ret = retPtr, .args = args } };
    try self.lambdaTypes.put(lambda.startPos, fnType);
    return fnType;
}

pub fn analyzeReference(self: anytype, ref: ast.expr.ZSReference) Error!Symbol.ZSTypeNotation {
    if (self.tableStack.get(ref.name)) |sym| {
        return sym.signature;
    }
    // Check use aliases (e.g., `use Color.{ Red }` makes `Red` resolve to `Color.Red`)
    if (self.useAliases.get(ref.name)) |alias| {
        if (self.enumDefs.get(alias.enum_name)) |ed| {
            for (ed.variants, 0..) |v, i| {
                if (std.mem.eql(u8, v.name, alias.variant_name)) {
                    try self.enumInits.put(ref.startPos, .{
                        .enumName = alias.enum_name,
                        .variantTag = @intCast(i),
                    });
                    return try type_resolver.buildEnumType(self, ed);
                }
            }
        }
    }
    try self.recordError(ref, "Reference not found");
    return Symbol.ZSTypeNotation.unknown;
}

pub fn analyzeIfExpr(self: anytype, ifExpr: ast.expr.ZSIfExpr) Error!Symbol.ZSTypeNotation {
    _ = try self.analyzeExpr(ifExpr.condition.*);
    const thenType = try self.analyzeExpr(ifExpr.then_branch.*);
    if (ifExpr.else_branch) |eb| {
        const elseType = try self.analyzeExpr(eb.*);
        if (thenType != .unknown and elseType != .unknown and
            !type_resolver.typesCompatible(thenType, elseType) and !type_resolver.typesCompatible(elseType, thenType))
        {
            try self.recordError(ifExpr, "if/else branches have incompatible types");
        }
    }
    return thenType;
}

pub fn analyzeWhileExpr(self: anytype, whileExpr: ast.expr.ZSWhileExpr) Error!Symbol.ZSTypeNotation {
    _ = try self.analyzeExpr(whileExpr.condition.*);
    const wasInLoop = self.inLoop;
    self.inLoop = true;
    _ = try self.analyzeExpr(whileExpr.body.*);
    self.inLoop = wasInLoop;
    return .unknown;
}

pub fn analyzeForExpr(self: anytype, forExpr: ast.expr.ZSForExpr) Error!Symbol.ZSTypeNotation {
    // Enter scope for the loop variable
    var forScope = SymbolTable.init(self.allocator);
    defer forScope.deinit();
    try self.tableStack.enterScope(&forScope);
    // Analyze init and register the variable
    if (try self.analyzeNode(forExpr.init.*)) |symbol| {
        try self.tableStack.put(symbol);
    }
    _ = try self.analyzeExpr(forExpr.condition.*);
    const wasInLoop = self.inLoop;
    self.inLoop = true;
    _ = try self.analyzeExpr(forExpr.body.*);
    self.inLoop = wasInLoop;
    _ = try self.analyzeNode(forExpr.step.*);
    _ = try self.tableStack.exitScope();
    return .unknown;
}

pub fn analyzeBreak(self: anytype, breakExpr: ast.expr.ZSBreak) Error!Symbol.ZSTypeNotation {
    if (!self.inLoop) {
        try self.recordError(breakExpr, "break can only be used inside a loop");
    }
    return .unknown;
}

pub fn analyzeContinue(self: anytype, continueExpr: ast.expr.ZSContinue) Error!Symbol.ZSTypeNotation {
    if (!self.inLoop) {
        try self.recordError(continueExpr, "continue can only be used inside a loop");
    }
    return .unknown;
}

pub fn analyzeUnary(self: anytype, unary: ast.expr.ZSUnary) Error!Symbol.ZSTypeNotation {
    _ = try self.analyzeExpr(unary.operand.*);
    return Symbol.ZSTypeNotation.boolean;
}

pub fn analyzeBinary(self: anytype, binary: ast.expr.ZSBinary) Error!Symbol.ZSTypeNotation {
    const lhsType = try self.analyzeExpr(binary.lhs.*);
    const rhsType = try self.analyzeExpr(binary.rhs.*);
    const op = binary.op;

    const isArith = std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-") or
        std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or
        std.mem.eql(u8, op, "%");
    const isLogical = std.mem.eql(u8, op, "&&") or std.mem.eql(u8, op, "||");
    const isOrdered = std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">") or
        std.mem.eql(u8, op, "<=") or std.mem.eql(u8, op, ">=");
    const isEquality = std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=");

    // Arithmetic: both operands must be numeric (pointer arithmetic is exempt)
    if (isArith and lhsType != .pointer and
        !(lhsType == .struct_type and std.mem.eql(u8, lhsType.struct_type.name, "Pointer")))
    {
        if (lhsType != .unknown and !type_resolver.isArithmeticType(lhsType))
            try self.recordError(binary, "left operand of arithmetic operator must be numeric");
        if (rhsType != .unknown and !type_resolver.isArithmeticType(rhsType))
            try self.recordError(binary, "right operand of arithmetic operator must be numeric");
    }

    // Logical: both must be boolean
    if (isLogical) {
        if (lhsType != .unknown and lhsType != .boolean)
            try self.recordError(binary, "left operand of logical operator must be boolean");
        if (rhsType != .unknown and rhsType != .boolean)
            try self.recordError(binary, "right operand of logical operator must be boolean");
        return Symbol.ZSTypeNotation.boolean;
    }

    // Ordered comparison: both must be numeric
    if (isOrdered) {
        if (lhsType != .unknown and !type_resolver.isArithmeticType(lhsType))
            try self.recordError(binary, "left operand of comparison must be numeric");
        if (rhsType != .unknown and !type_resolver.isArithmeticType(rhsType))
            try self.recordError(binary, "right operand of comparison must be numeric");
        return Symbol.ZSTypeNotation.boolean;
    }

    // Equality: operands must be type-compatible
    if (isEquality) {
        if (lhsType != .unknown and rhsType != .unknown and
            !type_resolver.typesCompatible(lhsType, rhsType) and !type_resolver.typesCompatible(rhsType, lhsType))
        {
            try self.recordError(binary, "equality operands have incompatible types");
        }
        return Symbol.ZSTypeNotation.boolean;
    }

    // Pointer arithmetic: Pointer<T> + number -> Pointer<T>
    if (lhsType == .pointer) {
        return lhsType;
    }
    if (lhsType == .struct_type and std.mem.eql(u8, lhsType.struct_type.name, "Pointer")) {
        return lhsType;
    }
    // Arithmetic operators return number
    return Symbol.ZSTypeNotation.number;
}

pub fn analyzeBlock(self: anytype, block: ast.expr.ZSBlock) Error!Symbol.ZSTypeNotation {
    var blockScope = SymbolTable.init(self.allocator);
    defer blockScope.deinit();
    try self.tableStack.enterScope(&blockScope);

    var lastType: Symbol.ZSTypeNotation = .unknown;
    for (block.stmts) |node| {
        switch (node) {
            .stmt => {
                if (try self.analyzeStmt(node.stmt)) |symbol| {
                    try self.tableStack.put(symbol);
                }
                lastType = .unknown;
            },
            .expr => {
                lastType = try self.analyzeExpr(node.expr);
            },
            .import_decl => {
                lastType = .unknown;
            },
            .export_from => {
                lastType = .unknown;
            },
            .use_decl => {
                try self.analyzeUse(node.use_decl);
                lastType = .unknown;
            },
            .when_decl, .target_decl => {
                lastType = .unknown;
            },
        }
    }

    _ = try self.tableStack.exitScope();
    return lastType;
}

pub fn analyzeReturn(self: anytype, ret: ast.expr.ZSReturn) Error!Symbol.ZSTypeNotation {
    if (ret.value) |v| {
        const savedExpected = self.expectedType;
        if (self.currentFnReturnType) |rt| {
            self.expectedType = rt;
        }
        const result = try self.analyzeExpr(v.*);
        self.expectedType = savedExpected;
        return result;
    }
    return .unknown;
}

pub fn analyzeSafeNav(self: anytype, sn: ast.expr.ZSSafeNav) Error!Symbol.ZSTypeNotation {
    const receiverType = try self.analyzeExpr(sn.receiver.*);

    // Receiver must be Option<T>
    const innerType: Symbol.ZSTypeNotation = switch (receiverType) {
        .enum_type => |et| blk: {
            if (!std.mem.eql(u8, et.name, "Option") or et.type_args.len != 1) {
                try self.recordError(sn, "?. receiver must be Option<T>");
                return .unknown;
            }
            break :blk et.type_args[0];
        },
        else => {
            try self.recordError(sn, "?. receiver must be Option<T>");
            return .unknown;
        },
    };

    // Resolve field type on the inner type (field access only for now)
    const fieldType: Symbol.ZSTypeNotation = switch (innerType) {
        .struct_type => |st| blk: {
            for (st.fields, 0..) |field, i| {
                if (std.mem.eql(u8, field.name, sn.field)) {
                    try self.fieldIndices.put(sn.startPos, @intCast(i));
                    break :blk field.type;
                }
            }
            try self.recordError(sn, "Field not found in struct");
            return .unknown;
        },
        else => {
            try self.recordError(sn, "Cannot access field on non-struct type via ?.");
            return .unknown;
        },
    };

    // flatMap mode: field is itself Option<U> → result is Option<U>
    // map mode:     field is plain T          → result is Option<T>
    const isFlatMap = switch (fieldType) {
        .enum_type => |et| std.mem.eql(u8, et.name, "Option"),
        else => false,
    };

    // Compute mangled Option enum names for IR gen
    const receiverEnumName = try type_resolver.computeEnumMangledName(self, "Option", receiverType.enum_type.type_args);

    const resultEnumName = if (isFlatMap)
        try type_resolver.computeEnumMangledName(self, "Option", fieldType.enum_type.type_args)
    else
        try type_resolver.computeEnumMangledName(self, "Option", &.{fieldType});

    try self.safeNavInfo.put(sn.startPos, .{
        .isFlatMap = isFlatMap,
        .receiverEnumName = receiverEnumName,
        .resultEnumName = resultEnumName,
        .fieldIndex = self.fieldIndices.get(sn.startPos) orelse 0,
    });

    // Return type
    if (isFlatMap) {
        return fieldType;
    } else {
        // Build Option<fieldType> using the Option enum def
        const optionEd = self.enumDefs.get("Option") orelse {
            try self.recordError(sn, "Option type not found in scope");
            return .unknown;
        };
        return try type_resolver.instantiateEnumFromResolved(self, optionEd, &.{fieldType});
    }
}
