const std = @import("std");
const zsm = @import("../ast/zs_module.zig");
const ast = @import("../ast/ast_node.zig");
const sig = @import("symbol_signature.zig");
const sts = @import("symbol_table_stack.zig");
const Symbol = @import("symbol.zig");
const ZSDiagnostic = @import("analyze_error.zig");
const SymbolTable = sts.SymbolTable;
const type_resolver = @import("type_resolver.zig");
const expr_analyzer = @import("expr_analyzer.zig");
const call_analyzer = @import("call_analyzer.zig");
const type_def_analyzer = @import("type_def_analyzer.zig");
const stmt_analyzer = @import("stmt_analyzer.zig");
const registrar = @import("registrar.zig");
const Self = @This();

tableStack: *sts,
errors: *std.ArrayList(ZSDiagnostic),
allocator: std.mem.Allocator,
module: zsm.ZSModule,
deps: *const std.StringHashMap(AnalyzeResult),
exports: SymbolTable,
overloads: std.StringHashMap(std.ArrayList(OverloadEntry)),
resolutions: std.AutoHashMap(usize, []const u8),
overloadedNames: std.StringHashMap(void),
allocatedStrings: std.ArrayList([]const u8),
allocatedTypes: std.ArrayList(*Symbol.ZSTypeNotation),
allocatedSliceLists: std.ArrayList([]const []const u8),
allocatedStructFields: std.ArrayList([]sig.ZSStructField),
allocatedFnArgs: std.ArrayList([]sig.ZSFnArg),
allocatedTypeSlices: std.ArrayList([]const Symbol.ZSTypeNotation),
allocatedAstTypeSlices: std.ArrayList([]const ast.type_notation.ZSTypeNotation),
allocatedAstStructFields: std.ArrayList([]const ast.stmt.ZSStruct.ZSStructField),
scalarDefs: std.StringHashMap(Symbol.ZSTypeNotation),
structDefs: std.StringHashMap(StructDef),
exportedStructDefs: std.StringHashMap(StructDef),
fieldIndices: std.AutoHashMap(usize, u32),
enumDefs: std.StringHashMap(EnumDef),
exportedEnumDefs: std.StringHashMap(EnumDef),
useAliases: std.StringHashMap(UseAlias),
allocatedEnumVariants: std.ArrayList([]sig.ZSEnumVariant),
enumInits: std.AutoHashMap(usize, EnumInitInfo),
derefTypes: std.AutoHashMap(usize, []const u8),
indexElemTypes: std.AutoHashMap(usize, []const u8),
arrayLiteralElemTypes: std.AutoHashMap(usize, []const u8),
genericFns: std.StringHashMap(GenericFnDef),
monomorphizedFns: std.StringHashMap(void),
monomorphizedFunctions: std.ArrayList(ast.stmt.ZSFn),
structInitResolutions: std.AutoHashMap(usize, []const u8),
monomorphizedEnums: std.StringHashMap(MonomorphizedEnumDef),
matchEnumNames: std.AutoHashMap(usize, []const u8),
typeParamBindings: ?TypeParamBindings,
extensionFns: std.StringHashMap(std.ArrayList(OverloadEntry)),
extensionCalls: std.AutoHashMap(usize, void),
lambdaNames: std.AutoHashMap(usize, []const u8),
lambdaCount: usize,
typeResolutionDepth: u32,
inLoop: bool,
typeAliases: std.StringHashMap(TypeAliasDef),
expectedType: ?Symbol.ZSTypeNotation = null,
currentFnReturnType: ?Symbol.ZSTypeNotation = null,

pub const EnumInitInfo = struct {
    enumName: []const u8,
    variantTag: u32,
};

const UseAlias = struct {
    enum_name: []const u8,
    variant_name: []const u8,
};

pub const StructDef = struct {
    name: []const u8,
    type_params: []const []const u8,
    fields: []ast.stmt.ZSStruct.ZSStructField,
};

pub const EnumDef = struct {
    name: []const u8,
    type_params: []const []const u8,
    variants: []ast.stmt.ZSEnum.ZSEnumVariant,
};

pub const MonomorphizedEnumDef = struct {
    mangledName: []const u8,
    variants: []sig.ZSEnumVariant,
};

pub const TypeParamBindings = struct {
    typeParams: []const []const u8,
    bindings: []const []const u8,
};

pub const GenericFnDef = struct {
    func: ast.stmt.ZSFn,
    type_params: []const []const u8,
};

pub const TypeAliasDef = struct {
    type_params: []const []const u8,
    aliased_type: ast.type_notation.ZSTypeNotation,
};

pub const OverloadEntry = struct {
    argTypes: []const []const u8,
    mangledName: []const u8,
    retType: Symbol.ZSTypeNotation,
    external: bool,
};

pub const Error = error{} || std.mem.Allocator.Error || sts.Error;

pub const AnalyzeResult = struct {
    exports: SymbolTable,
    /// All top-level symbols in this module (exported or not). Used by the daemon for hover.
    moduleScope: SymbolTable,
    errors: []ZSDiagnostic,
    resolutions: std.AutoHashMap(usize, []const u8),
    overloadedNames: std.StringHashMap(void),
    overloads: std.StringHashMap(std.ArrayList(OverloadEntry)),
    allocatedStrings: std.ArrayList([]const u8),
    allocatedTypes: std.ArrayList(*Symbol.ZSTypeNotation),
    allocatedSliceLists: std.ArrayList([]const []const u8),
    allocatedStructFields: std.ArrayList([]sig.ZSStructField),
    allocatedFnArgs: std.ArrayList([]sig.ZSFnArg),
    allocatedTypeSlices: std.ArrayList([]const Symbol.ZSTypeNotation),
    allocatedAstTypeSlices: std.ArrayList([]const ast.type_notation.ZSTypeNotation),
    allocatedAstStructFields: std.ArrayList([]const ast.stmt.ZSStruct.ZSStructField),
    scalarDefs: std.StringHashMap(Symbol.ZSTypeNotation),
    structDefs: std.StringHashMap(StructDef),
    exportedStructDefs: std.StringHashMap(StructDef),
    fieldIndices: std.AutoHashMap(usize, u32),
    enumDefs: std.StringHashMap(EnumDef),
    exportedEnumDefs: std.StringHashMap(EnumDef),
    allocatedEnumVariants: std.ArrayList([]sig.ZSEnumVariant),
    enumInits: std.AutoHashMap(usize, EnumInitInfo),
    derefTypes: std.AutoHashMap(usize, []const u8),
    indexElemTypes: std.AutoHashMap(usize, []const u8),
    arrayLiteralElemTypes: std.AutoHashMap(usize, []const u8),
    genericFns: std.StringHashMap(GenericFnDef),
    monomorphizedFunctions: std.ArrayList(ast.stmt.ZSFn),
    structInitResolutions: std.AutoHashMap(usize, []const u8),
    monomorphizedEnums: std.StringHashMap(MonomorphizedEnumDef),
    matchEnumNames: std.AutoHashMap(usize, []const u8),
    extensionFns: std.StringHashMap(std.ArrayList(OverloadEntry)),
    extensionCalls: std.AutoHashMap(usize, void),
    lambdaNames: std.AutoHashMap(usize, []const u8),
    typeAliases: std.StringHashMap(TypeAliasDef),

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
        allocator.free(self.errors);
        self.exports.deinit();
        self.moduleScope.deinit();

        self.resolutions.deinit();

        self.overloadedNames.deinit();

        // Free overloads map and its inner ArrayLists
        var overloadIter = self.overloads.iterator();
        while (overloadIter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.overloads.deinit();

        // Free all tracked heap-allocated strings (mangled names)
        for (self.allocatedStrings.items) |s| {
            allocator.free(s);
        }
        self.allocatedStrings.deinit(allocator);

        // Free all tracked heap-allocated ZSTypeNotation pointers
        for (self.allocatedTypes.items) |t| {
            allocator.destroy(t);
        }
        self.allocatedTypes.deinit(allocator);

        // Free all tracked argTypes slice arrays
        for (self.allocatedSliceLists.items) |s| {
            allocator.free(s);
        }
        self.allocatedSliceLists.deinit(allocator);

        // Free all tracked struct field slices
        for (self.allocatedStructFields.items) |s| {
            allocator.free(s);
        }
        self.allocatedStructFields.deinit(allocator);

        // Free all tracked fn arg slices
        for (self.allocatedFnArgs.items) |s| {
            allocator.free(s);
        }
        self.allocatedFnArgs.deinit(allocator);

        // Free all tracked type slices
        for (self.allocatedTypeSlices.items) |s| {
            allocator.free(s);
        }
        self.allocatedTypeSlices.deinit(allocator);

        // Free all tracked AST type slices
        for (self.allocatedAstTypeSlices.items) |s| {
            allocator.free(s);
        }
        self.allocatedAstTypeSlices.deinit(allocator);

        // Free all tracked AST struct field slices
        for (self.allocatedAstStructFields.items) |s| {
            allocator.free(s);
        }
        self.allocatedAstStructFields.deinit(allocator);

        self.scalarDefs.deinit();
        self.structDefs.deinit();
        self.exportedStructDefs.deinit();
        self.fieldIndices.deinit();
        self.enumDefs.deinit();
        self.exportedEnumDefs.deinit();

        for (self.allocatedEnumVariants.items) |s| {
            allocator.free(s);
        }
        self.allocatedEnumVariants.deinit(allocator);
        self.enumInits.deinit();
        self.derefTypes.deinit();
        self.indexElemTypes.deinit();
        self.arrayLiteralElemTypes.deinit();
        self.genericFns.deinit();
        for (self.monomorphizedFunctions.items) |func| {
            allocator.free(func.args);
        }
        self.monomorphizedFunctions.deinit(allocator);
        self.structInitResolutions.deinit();
        self.monomorphizedEnums.deinit();
        self.matchEnumNames.deinit();
        var extFnIter = self.extensionFns.iterator();
        while (extFnIter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.extensionFns.deinit();
        self.extensionCalls.deinit();
        self.lambdaNames.deinit();
        self.typeAliases.deinit();
    }
};

pub fn analyze(module: zsm.ZSModule, allocator: std.mem.Allocator, deps: *const std.StringHashMap(AnalyzeResult)) !AnalyzeResult {
    return analyzeWithPrelude(module, allocator, deps, null, null, null, null, null, null);
}

pub fn analyzeWithPrelude(module: zsm.ZSModule, allocator: std.mem.Allocator, deps: *const std.StringHashMap(AnalyzeResult), preludeExports: ?*const SymbolTable, preludeOverloads: ?*const std.StringHashMap(std.ArrayList(OverloadEntry)), preludeStructDefs: ?*const std.StringHashMap(StructDef), preludeEnumDefs: ?*const std.StringHashMap(EnumDef), preludeGenericFns: ?*const std.StringHashMap(GenericFnDef), preludeScalarDefs: ?*const std.StringHashMap(Symbol.ZSTypeNotation)) !AnalyzeResult {
    var errors = try std.ArrayList(ZSDiagnostic).initCapacity(allocator, 1);
    defer errors.deinit(allocator);
    var tableStack = try sts.create(allocator);
    defer tableStack.deinit();
    var analyzer = Self{
        .tableStack = &tableStack,
        .errors = &errors,
        .allocator = allocator,
        .module = module,
        .deps = deps,
        .exports = SymbolTable.init(allocator),
        .overloads = std.StringHashMap(std.ArrayList(OverloadEntry)).init(allocator),
        .resolutions = std.AutoHashMap(usize, []const u8).init(allocator),
        .overloadedNames = std.StringHashMap(void).init(allocator),
        .allocatedStrings = try std.ArrayList([]const u8).initCapacity(allocator, 8),
        .allocatedTypes = try std.ArrayList(*Symbol.ZSTypeNotation).initCapacity(allocator, 4),
        .allocatedSliceLists = try std.ArrayList([]const []const u8).initCapacity(allocator, 8),
        .allocatedStructFields = try std.ArrayList([]sig.ZSStructField).initCapacity(allocator, 4),
        .allocatedFnArgs = try std.ArrayList([]sig.ZSFnArg).initCapacity(allocator, 4),
        .allocatedTypeSlices = try std.ArrayList([]const Symbol.ZSTypeNotation).initCapacity(allocator, 4),
        .allocatedAstTypeSlices = try std.ArrayList([]const ast.type_notation.ZSTypeNotation).initCapacity(allocator, 4),
        .allocatedAstStructFields = try std.ArrayList([]const ast.stmt.ZSStruct.ZSStructField).initCapacity(allocator, 4),
        .scalarDefs = std.StringHashMap(Symbol.ZSTypeNotation).init(allocator),
        .structDefs = std.StringHashMap(StructDef).init(allocator),
        .exportedStructDefs = std.StringHashMap(StructDef).init(allocator),
        .fieldIndices = std.AutoHashMap(usize, u32).init(allocator),
        .enumDefs = std.StringHashMap(EnumDef).init(allocator),
        .exportedEnumDefs = std.StringHashMap(EnumDef).init(allocator),
        .useAliases = std.StringHashMap(UseAlias).init(allocator),
        .allocatedEnumVariants = try std.ArrayList([]sig.ZSEnumVariant).initCapacity(allocator, 4),
        .enumInits = std.AutoHashMap(usize, EnumInitInfo).init(allocator),
        .derefTypes = std.AutoHashMap(usize, []const u8).init(allocator),
        .indexElemTypes = std.AutoHashMap(usize, []const u8).init(allocator),
        .arrayLiteralElemTypes = std.AutoHashMap(usize, []const u8).init(allocator),
        .genericFns = std.StringHashMap(GenericFnDef).init(allocator),
        .monomorphizedFns = std.StringHashMap(void).init(allocator),
        .monomorphizedFunctions = try std.ArrayList(ast.stmt.ZSFn).initCapacity(allocator, 4),
        .structInitResolutions = std.AutoHashMap(usize, []const u8).init(allocator),
        .monomorphizedEnums = std.StringHashMap(MonomorphizedEnumDef).init(allocator),
        .matchEnumNames = std.AutoHashMap(usize, []const u8).init(allocator),
        .typeParamBindings = null,
        .extensionFns = std.StringHashMap(std.ArrayList(OverloadEntry)).init(allocator),
        .extensionCalls = std.AutoHashMap(usize, void).init(allocator),
        .lambdaNames = std.AutoHashMap(usize, []const u8).init(allocator),
        .lambdaCount = 0,
        .typeResolutionDepth = 0,
        .inLoop = false,
        .typeAliases = std.StringHashMap(TypeAliasDef).init(allocator),
    };

    // Note: resolutions, overloadedNames, overloads, allocatedStrings, allocatedTypes,
    // structDefs, enumDefs, genericFns, monomorphizedFunctions are moved into the result, not freed here
    defer analyzer.useAliases.deinit();
    defer analyzer.monomorphizedFns.deinit();

    var table = SymbolTable.init(allocator);
    defer table.deinit();
    try tableStack.enterScope(&table);

    // Import dependencies and prelude definitions
    try registrar.importDependencies(&analyzer, allocator, deps, preludeExports, preludeOverloads, preludeStructDefs, preludeEnumDefs, preludeGenericFns, preludeScalarDefs);

    // Pre-pass: register all type aliases
    try analyzer.registerTypeAliases(module);

    // Pre-pass: register all scalar declarations
    try analyzer.registerScalars(module);

    // Pre-pass: register all struct definitions
    try analyzer.registerStructs(module);

    // Pre-pass: register all enum definitions
    try analyzer.registerEnums(module);

    // Pre-pass: register all function overloads
    try analyzer.registerFunctions(module);

    // Determine which names are overloaded
    var overloadIter = analyzer.overloads.iterator();
    while (overloadIter.next()) |entry| {
        if (entry.value_ptr.items.len > 1) {
            try analyzer.overloadedNames.put(entry.key_ptr.*, {});
        }
    }

    try analyzer.analyzeModule(module);
    const globalScope = try tableStack.exitScope();

    // Copy global scope into a stable SymbolTable for hover/lookup after analysis.
    var moduleScope = SymbolTable.init(allocator);
    var scopeIter = globalScope.iterator();
    while (scopeIter.next()) |entry| {
        try moduleScope.put(entry.key_ptr.*, entry.value_ptr.*);
    }

    return .{
        .exports = analyzer.exports,
        .moduleScope = moduleScope,
        .errors = try allocator.dupe(ZSDiagnostic, errors.items),
        .resolutions = analyzer.resolutions,
        .overloadedNames = analyzer.overloadedNames,
        .overloads = analyzer.overloads,
        .allocatedStrings = analyzer.allocatedStrings,
        .allocatedTypes = analyzer.allocatedTypes,
        .allocatedSliceLists = analyzer.allocatedSliceLists,
        .allocatedStructFields = analyzer.allocatedStructFields,
        .allocatedFnArgs = analyzer.allocatedFnArgs,
        .allocatedTypeSlices = analyzer.allocatedTypeSlices,
        .allocatedAstTypeSlices = analyzer.allocatedAstTypeSlices,
        .allocatedAstStructFields = analyzer.allocatedAstStructFields,
        .scalarDefs = analyzer.scalarDefs,
        .structDefs = analyzer.structDefs,
        .exportedStructDefs = analyzer.exportedStructDefs,
        .fieldIndices = analyzer.fieldIndices,
        .enumDefs = analyzer.enumDefs,
        .exportedEnumDefs = analyzer.exportedEnumDefs,
        .allocatedEnumVariants = analyzer.allocatedEnumVariants,
        .enumInits = analyzer.enumInits,
        .derefTypes = analyzer.derefTypes,
        .indexElemTypes = analyzer.indexElemTypes,
        .arrayLiteralElemTypes = analyzer.arrayLiteralElemTypes,
        .genericFns = analyzer.genericFns,
        .monomorphizedFunctions = analyzer.monomorphizedFunctions,
        .structInitResolutions = analyzer.structInitResolutions,
        .monomorphizedEnums = analyzer.monomorphizedEnums,
        .matchEnumNames = analyzer.matchEnumNames,
        .extensionFns = analyzer.extensionFns,
        .extensionCalls = analyzer.extensionCalls,
        .lambdaNames = analyzer.lambdaNames,
        .typeAliases = analyzer.typeAliases,
    };
}

pub fn registerIntrinsic(self: *Self, allocator: std.mem.Allocator, name: []const u8, argTypeNames: []const []const u8, retType: Symbol.ZSTypeNotation) !void {
    return registrar.registerIntrinsic(self, allocator, name, argTypeNames, retType);
}

pub fn registerTypeAliases(self: *Self, module: zsm.ZSModule) !void {
    return registrar.registerTypeAliases(self, module);
}

pub fn registerFunctions(self: *Self, module: zsm.ZSModule) !void {
    return registrar.registerFunctions(self, module);
}

pub fn registerFunction(self: *Self, func: ast.stmt.ZSFn) !void {
    return registrar.registerFunction(self, func);
}

pub fn analyzeModule(self: *Self, module: zsm.ZSModule) !void {
    return stmt_analyzer.analyzeModule(self, module);
}

pub fn analyzeNode(self: *Self, node: ast.ZSAstNode) !?Symbol {
    return stmt_analyzer.analyzeNode(self, node);
}

pub fn analyzeImport(self: *Self, imp: ast.ZSImport) !?Symbol {
    return stmt_analyzer.analyzeImport(self, imp);
}

pub fn analyzeExportFrom(self: *Self, ef: ast.ZSExportFrom) !void {
    return stmt_analyzer.analyzeExportFrom(self, ef);
}

pub fn analyzeStmt(self: *Self, stmt: ast.stmt.ZSStmt) !?Symbol {
    return stmt_analyzer.analyzeStmt(self, stmt);
}

pub fn analyzeExpr(self: *Self, expr: ast.expr.ZSExpr) !Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeExpr(self, expr);
}

pub fn analyzeLambda(self: *Self, lambda: ast.expr.ZSLambda) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeLambda(self, lambda);
}

pub fn analyzeVariable(self: *Self, variable: ast.stmt.ZSVar) !Symbol {
    return stmt_analyzer.analyzeVariable(self, variable);
}

pub fn analyzeReassign(self: *Self, reassign: ast.stmt.ZSReassign) !void {
    return stmt_analyzer.analyzeReassign(self, reassign);
}

pub fn analyzeReassignFieldTarget(self: *Self, f: ast.stmt.ZSReassign.FieldTarget) !void {
    return stmt_analyzer.analyzeReassignFieldTarget(self, f);
}

pub fn analyzeFunction(self: *Self, function: ast.stmt.ZSFn) !Symbol {
    return stmt_analyzer.analyzeFunction(self, function);
}


pub fn analyzeBuiltin(self: *Self, builtin: ast.ZSBuiltin) !Symbol.ZSTypeNotation {
    return call_analyzer.analyzeBuiltin(self, builtin);
}

pub fn analyzeFnArgs(self: *Self, args: []ast.stmt.ZSFn.Arg) ![]Symbol.sig.ZSFnArg {
    return stmt_analyzer.analyzeFnArgs(self, args);
}

pub fn analyzeCall(self: *Self, call: ast.expr.ZSCall) Error!Symbol.ZSTypeNotation {
    return call_analyzer.analyzeCall(self, call);
}

pub fn analyzeReference(self: *Self, ref: ast.expr.ZSReference) !Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeReference(self, ref);
}

pub fn analyzeIfExpr(self: *Self, ifExpr: ast.expr.ZSIfExpr) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeIfExpr(self, ifExpr);
}

pub fn analyzeWhileExpr(self: *Self, whileExpr: ast.expr.ZSWhileExpr) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeWhileExpr(self, whileExpr);
}

pub fn analyzeForExpr(self: *Self, forExpr: ast.expr.ZSForExpr) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeForExpr(self, forExpr);
}

pub fn analyzeBreak(self: *Self, breakExpr: ast.expr.ZSBreak) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeBreak(self, breakExpr);
}

pub fn analyzeContinue(self: *Self, continueExpr: ast.expr.ZSContinue) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeContinue(self, continueExpr);
}

pub fn analyzeUnary(self: *Self, unary: ast.expr.ZSUnary) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeUnary(self, unary);
}


pub fn analyzeBinary(self: *Self, binary: ast.expr.ZSBinary) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeBinary(self, binary);
}

pub fn analyzeBlock(self: *Self, block: ast.expr.ZSBlock) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeBlock(self, block);
}

pub fn analyzeReturn(self: *Self, ret: ast.expr.ZSReturn) Error!Symbol.ZSTypeNotation {
    return expr_analyzer.analyzeReturn(self, ret);
}

pub fn registerScalars(self: *Self, module: zsm.ZSModule) !void {
    return registrar.registerScalars(self, module);
}

pub fn registerStructs(self: *Self, module: zsm.ZSModule) !void {
    return registrar.registerStructs(self, module);
}

pub fn resolveTypeAnnotationFull(self: *Self, astType: ast.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    return type_resolver.resolveTypeAnnotationFull(self, astType);
}

pub fn instantiateStruct(self: *Self, sd: StructDef, typeArgs: []const ast.type_notation.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    return type_resolver.instantiateStruct(self, sd, typeArgs);
}

pub fn resolveFieldType(self: *Self, fieldAstType: ast.type_notation.ZSTypeNotation, typeParams: []const []const u8, resolvedTypeArgs: []const Symbol.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    return type_resolver.resolveFieldType(self, fieldAstType, typeParams, resolvedTypeArgs);
}

pub fn getStringStructType(self: *Self) !Symbol.ZSTypeNotation {
    return type_resolver.getStringStructType(self);
}

pub fn analyzeStructInit(self: *Self, si: ast.expr.ZSStructInit) Error!Symbol.ZSTypeNotation {
    return type_def_analyzer.analyzeStructInit(self, si);
}

pub fn analyzeArrayLiteral(self: *Self, al: ast.expr.ZSArrayLiteral) Error!Symbol.ZSTypeNotation {
    return type_def_analyzer.analyzeArrayLiteral(self, al);
}

pub fn analyzeIndexAccess(self: *Self, ia: ast.expr.ZSIndexAccess) Error!Symbol.ZSTypeNotation {
    return type_def_analyzer.analyzeIndexAccess(self, ia);
}

pub fn analyzeFieldAccess(self: *Self, fa: ast.expr.ZSFieldAccess) Error!Symbol.ZSTypeNotation {
    return type_def_analyzer.analyzeFieldAccess(self, fa);
}

pub fn registerEnums(self: *Self, module: zsm.ZSModule) !void {
    return registrar.registerEnums(self, module);
}

pub fn buildEnumType(self: *Self, ed: EnumDef) Error!Symbol.ZSTypeNotation {
    return type_resolver.buildEnumType(self, ed);
}

pub fn instantiateEnum(self: *Self, ed: EnumDef, typeArgs: []const ast.type_notation.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    return type_resolver.instantiateEnum(self, ed, typeArgs);
}

pub fn analyzeEnumInit(self: *Self, ei: ast.expr.ZSEnumInit) Error!Symbol.ZSTypeNotation {
    return type_def_analyzer.analyzeEnumInit(self, ei);
}

pub fn findVariantTag(_: *Self, ed: EnumDef, variantName: []const u8) usize {
    return type_def_analyzer.findVariantTag(ed, variantName);
}

pub fn computeEnumMangledName(self: *Self, baseName: []const u8, typeArgs: []const Symbol.ZSTypeNotation) ![]const u8 {
    return type_resolver.computeEnumMangledName(self, baseName, typeArgs);
}

pub fn instantiateEnumFromResolved(self: *Self, ed: EnumDef, resolvedTypeArgs: []const Symbol.ZSTypeNotation) Error!Symbol.ZSTypeNotation {
    return type_resolver.instantiateEnumFromResolved(self, ed, resolvedTypeArgs);
}

pub fn analyzeMatchExpr(self: *Self, me: ast.expr.ZSMatchExpr) Error!Symbol.ZSTypeNotation {
    return type_def_analyzer.analyzeMatchExpr(self, me);
}

pub fn analyzeUse(self: *Self, u: ast.ZSUse) Error!void {
    return type_def_analyzer.analyzeUse(self, u);
}

pub fn tryMonomorphizeCall(self: *Self, mangledName: []const u8, argTypes: []const []const u8, callStartPos: usize) Error!?Symbol.ZSTypeNotation {
    return call_analyzer.tryMonomorphizeCall(self, mangledName, argTypes, callStartPos);
}

pub fn resolveConcreteRetType(self: *Self, gfn: GenericFnDef, bindings: []const []const u8) Error!Symbol.ZSTypeNotation {
    return type_resolver.resolveConcreteRetType(self, gfn, bindings);
}

pub fn monomorphizeFunction(self: *Self, gfn: GenericFnDef, bindings: []const []const u8, mangledName: []const u8) !ast.stmt.ZSFn {
    return call_analyzer.monomorphizeFunction(self, gfn, bindings, mangledName);
}

pub fn substituteAstType(self: *Self, t: ast.ZSTypeNotation, typeParams: []const []const u8, bindings: []const []const u8) !ast.ZSTypeNotation {
    return type_resolver.substituteAstType(self, t, typeParams, bindings);
}

pub fn typesCompatible(dst: Symbol.ZSTypeNotation, src: Symbol.ZSTypeNotation) bool {
    return type_resolver.typesCompatible(dst, src);
}

/// Safely compute a source position offset. Returns 0 if the pointer is outside the module source range.
pub fn safeSourceOffset(self: *Self, ptr: [*]const u8) usize {
    const sourceStart = @intFromPtr(self.module.source.ptr);
    const sourceEnd = sourceStart + self.module.source.len;
    const ptrAddr = @intFromPtr(ptr);
    if (ptrAddr >= sourceStart and ptrAddr < sourceEnd) {
        return ptrAddr - sourceStart;
    }
    return 0;
}

pub fn substituteTypeParamName(self: *Self, name: []const u8) []const u8 {
    return type_resolver.substituteTypeParamName(self, name);
}

pub fn recordError(
    self: *Self,
    expr: anytype,
    message: []const u8,
) Error!void {
    try self.recordErrorAt(expr.startPos, expr.endPos, message);
}

pub fn recordErrorAt(
    self: *Self,
    start: usize,
    end: usize,
    message: []const u8,
) Error!void {
    const root = @import("ZenScript");
    try self.errors.append(self.allocator, .{
        .message = message,
        .severity = .err,
        .phase = .analyze,
        .filename = self.module.filename,
        .start = start,
        .end = end,
        .codeLine = root.SourceHelpers.computeSourceLine(self.module.source, start),
        .lineNumber = root.SourceHelpers.computeLineNumber(self.module.source, start),
        .lineCol = root.SourceHelpers.computeLineOffset(self.module.source, start),
    });
}
