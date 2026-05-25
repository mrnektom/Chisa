const std = @import("std");
const Tokenizer = @import("tokens/tokenizer.zig");
const Parser = @import("parser.zig");
const Analyzer = @import("analyzer/analyzer.zig");
const Symbol = @import("analyzer/symbol.zig");
const sts = @import("analyzer/symbol_table_stack.zig");
const Self = @This();
const IRGen = @import("ir/ir_gen.zig");
const ir = @import("ir/zsir.zig");
const llvm = @import("codegen/llvm_codegen.zig");
const llvm_lib = @import("llvm");
const core = llvm_lib.core;
const Args = @import("args/args.zig");
const zsm = @import("ast/zs_module.zig");
const type_notation = @import("ast/zs_type_notation.zig");
const Preprocessor = @import("preprocessor.zig");
const dump_symbols = @import("dump_symbols.zig");
const computeMangledName = @import("ZenScript").MangleHelpers.computeMangledName;

/// Convert an AST type notation to the string name used by codegen's mapType.
fn resolveFieldTypeName(allocator: std.mem.Allocator, t: type_notation.ZSTypeNotation) ![]const u8 {
    return switch (t) {
        .reference => |ref| {
            if (std.mem.eql(u8, ref, "number") or std.mem.eql(u8, ref, "int")) return allocator.dupe(u8, "number");
            if (std.mem.eql(u8, ref, "long")) return allocator.dupe(u8, "long");
            if (std.mem.eql(u8, ref, "short")) return allocator.dupe(u8, "short");
            if (std.mem.eql(u8, ref, "byte")) return allocator.dupe(u8, "byte");
            if (std.mem.eql(u8, ref, "boolean")) return allocator.dupe(u8, "boolean");
            if (std.mem.eql(u8, ref, "char")) return allocator.dupe(u8, "char");
            if (std.mem.eql(u8, ref, "String")) return allocator.dupe(u8, "String");
            if (std.mem.eql(u8, ref, "c_string")) return allocator.dupe(u8, "c_string");
            if (std.mem.eql(u8, ref, "void")) return allocator.dupe(u8, "void");
            return allocator.dupe(u8, ref); // struct/enum name — will be looked up in registry
        },
        .generic => |g| {
            if (std.mem.eql(u8, g.name, "Pointer")) return allocator.dupe(u8, "pointer");

            const typeArgNames = try allocator.alloc([]const u8, g.type_args.len);
            defer {
                for (typeArgNames) |name| allocator.free(name);
                allocator.free(typeArgNames);
            }
            for (g.type_args, 0..) |arg, i| {
                typeArgNames[i] = try resolveFieldTypeName(allocator, arg);
            }
            return computeMangledName(allocator, g.name, typeArgNames);
        },
        .array => allocator.dupe(u8, "pointer"), // arrays as pointers
        .fn_type => allocator.dupe(u8, "function"),
    };
}

/// Build a map of struct name → field type name strings from analyzer struct defs.
fn buildStructFieldTypes(
    allocator: std.mem.Allocator,
    structDefs: *const std.StringHashMap(Analyzer.StructDef),
    depStructDefs: []const *const std.StringHashMap(Analyzer.StructDef),
) !std.StringHashMap([]const []const u8) {
    var result = std.StringHashMap([]const []const u8).init(allocator);
    errdefer {
        var it = result.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        result.deinit();
    }
    // Add from deps
    for (depStructDefs) |defs| {
        var iter = defs.iterator();
        while (iter.next()) |entry| {
            if (!result.contains(entry.key_ptr.*)) {
                const sd = entry.value_ptr.*;
                const fieldTypes = try allocator.alloc([]const u8, sd.fields.len);
                var init_count: usize = 0;
                errdefer {
                    for (fieldTypes[0..init_count]) |fieldType| allocator.free(fieldType);
                    allocator.free(fieldTypes);
                }
                for (sd.fields, 0..) |field, i| {
                    fieldTypes[i] = try resolveFieldTypeName(allocator, field.type);
                    init_count = i + 1;
                }
                try result.put(entry.key_ptr.*, fieldTypes);
            }
        }
    }
    // Add from main module
    var iter = structDefs.iterator();
    while (iter.next()) |entry| {
        if (!result.contains(entry.key_ptr.*)) {
            const sd = entry.value_ptr.*;
            const fieldTypes = try allocator.alloc([]const u8, sd.fields.len);
            var init_count: usize = 0;
            errdefer {
                for (fieldTypes[0..init_count]) |fieldType| allocator.free(fieldType);
                allocator.free(fieldTypes);
            }
            for (sd.fields, 0..) |field, i| {
                fieldTypes[i] = try resolveFieldTypeName(allocator, field.type);
                init_count = i + 1;
            }
            try result.put(entry.key_ptr.*, fieldTypes);
        }
    }
    return result;
}

const CompiledModule = struct {
    analyzeResult: Analyzer.AnalyzeResult,
    irResult: IRGen.IrGenResult,
};

allocator: std.mem.Allocator,
cache: std.StringHashMap(CompiledModule),
inProgress: std.StringHashMap(void),
allSources: std.ArrayList([]const u8),
allModules: std.ArrayList(zsm.ZSModule),
io: std.Io,

pub fn init(allocator: std.mem.Allocator, io: std.Io) !Self {
    return .{
        .allocator = allocator,
        .cache = std.StringHashMap(CompiledModule).init(allocator),
        .inProgress = std.StringHashMap(void).init(allocator),
        .allSources = try std.ArrayList([]const u8).initCapacity(allocator, 4),
        .allModules = try std.ArrayList(zsm.ZSModule).initCapacity(allocator, 4),
        .io = io,
    };
}

pub fn deinit(self: *Self) void {
    var cacheIter = self.cache.iterator();
    while (cacheIter.next()) |entry| {
        entry.value_ptr.analyzeResult.deinit(self.allocator);
        entry.value_ptr.irResult.deinit(self.allocator);
        self.allocator.free(entry.key_ptr.*);
    }
    self.cache.deinit();
    self.inProgress.deinit();
    for (self.allSources.items) |s| self.allocator.free(s);
    self.allSources.deinit(self.allocator);
    for (self.allModules.items) |m| m.deinit(self.allocator);
    self.allModules.deinit(self.allocator);
}

/// Resolve a relative import path against the importing file's directory.
fn resolvePath(allocator: std.mem.Allocator, importerPath: []const u8, relativePath: []const u8) ![]const u8 {
    // Paths starting with "./" or "../" are relative to the importing file.
    // All other paths are relative to CWD (project root).
    if (std.mem.startsWith(u8, relativePath, "./") or std.mem.startsWith(u8, relativePath, "../")) {
        const dir = std.fs.path.dirname(importerPath) orelse ".";
        const raw = try std.mem.concat(allocator, u8, &.{ dir, "/", relativePath });
        defer allocator.free(raw);
        return try std.fs.path.resolve(allocator, &.{raw});
    }
    return try allocator.dupe(u8, relativePath);
}

fn isStdlibPath(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "stdlib/") or
        std.mem.indexOf(u8, path, "/stdlib/") != null;
}

/// Recursively compile a module and all its dependencies.
/// Returns the CompiledModule for the given path.
fn compileModule(self: *Self, path: []const u8, injectPreludeIntoStdlib: bool) !CompiledModule {
    const allocator = self.allocator;

    // Check cache
    if (self.cache.get(path)) |result| return result;

    // Cycle detection
    if (self.inProgress.contains(path)) {
        std.debug.print("Error: Circular import detected for '{s}'\n", .{path});
        return error.CircularImport;
    }
    try self.inProgress.put(path, {});
    errdefer _ = self.inProgress.remove(path);

    // Read file
    const buffer = std.Io.Dir.cwd().readFileAlloc(self.io, path, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: imported module not found: '{s}'\n", .{path});
        }
        return err;
    };
    try self.allSources.append(allocator, buffer);

    // Tokenize & parse
    const tokenizer = Tokenizer.create(buffer);
    var parser = try Parser.create(allocator, tokenizer, path, buffer);
    const rawModule = try parser.parse(allocator);
    // preprocessModule shares .deps/.allocatedStrings from rawModule, but copies .ast —
    // so only free the original ast slice, not deinit (would double-free shared fields).
    defer allocator.free(rawModule.ast);

    // Preprocess conditional compilation
    var ppCtx = Preprocessor.CompileTimeContext.init(allocator);
    defer ppCtx.deinit();
    const module = try Preprocessor.preprocessModule(allocator, rawModule, &ppCtx);
    try self.allModules.append(allocator, module);

    // Recursively compile dependencies
    var depAnalyzeResults = std.StringHashMap(Analyzer.AnalyzeResult).init(allocator);
    defer depAnalyzeResults.deinit();

    // Build imported var names from deps for this module's IRGen
    var importedVarNames = std.StringHashMap([]const u8).init(allocator);
    defer importedVarNames.deinit();

    var preludeExports: ?*const sts.SymbolTable = null;
    var preludeOverloads: ?*const std.StringHashMap(std.ArrayList(Analyzer.OverloadEntry)) = null;
    var preludeStructDefs: ?*const std.StringHashMap(Analyzer.StructDef) = null;
    var preludeEnumDefs: ?*const std.StringHashMap(Analyzer.EnumDef) = null;
    var preludeGenericFns: ?*const std.StringHashMap(Analyzer.GenericFnDef) = null;
    var preludeScalarDefs: ?*const std.StringHashMap(Symbol.ZSTypeNotation) = null;

    for (module.deps) |dep| {
        const resolvedPath = try resolvePath(allocator, path, dep.path);
        defer allocator.free(resolvedPath);

        const depPath = try allocator.dupe(u8, resolvedPath);
        defer allocator.free(depPath);
        const depCompiled = try self.compileModule(depPath, injectPreludeIntoStdlib);
        try depAnalyzeResults.put(dep.path, depCompiled.analyzeResult);

        // Map imported symbol names (using alias if present) to their IR names from the dep
        for (dep.symbols) |sym| {
            const localName = sym.alias orelse sym.name;
            if (depCompiled.irResult.varNames.get(sym.name)) |irName| {
                try importedVarNames.put(localName, irName);
            } else if (depCompiled.analyzeResult.exports.get(sym.name)) |exportedSym| {
                if (exportedSym.signature == .function) {
                    try importedVarNames.put(localName, sym.name);
                }
            }
        }
    }

    if (injectPreludeIntoStdlib or !isStdlibPath(path)) {
        if (try findPreludePath(self, allocator)) |pPath| {
            defer allocator.free(pPath);
            if (!injectPreludeIntoStdlib and self.cache.get(pPath) == null) {
                _ = try self.compileModule(pPath, false);
            }
            if (self.cache.getPtr(pPath)) |cachedPrelude| {
                preludeScalarDefs = &cachedPrelude.analyzeResult.scalarDefs;
                if (!injectPreludeIntoStdlib or !isStdlibPath(path)) {
                    preludeExports = &cachedPrelude.analyzeResult.exports;
                    preludeOverloads = &cachedPrelude.analyzeResult.overloads;
                    preludeStructDefs = &cachedPrelude.analyzeResult.structDefs;
                    preludeEnumDefs = &cachedPrelude.analyzeResult.enumDefs;
                    preludeGenericFns = &cachedPrelude.analyzeResult.genericFns;
                }

                if (!injectPreludeIntoStdlib or !isStdlibPath(path)) {
                    var exportIter = cachedPrelude.analyzeResult.exports.iterator();
                    while (exportIter.next()) |entry| {
                        if (cachedPrelude.irResult.varNames.get(entry.key_ptr.*)) |irName| {
                            try importedVarNames.put(entry.key_ptr.*, irName);
                        }
                    }
                }
            }
        }
    }

    // Analyze
    var analyzeResult = try Analyzer.analyzeWithPrelude(
        module,
        allocator,
        &depAnalyzeResults,
        preludeExports,
        preludeOverloads,
        preludeStructDefs,
        preludeEnumDefs,
        preludeGenericFns,
        preludeScalarDefs,
    );
    errdefer analyzeResult.deinit(allocator);

    if (analyzeResult.errors.len != 0) {
        for (analyzeResult.errors) |e| {
            std.debug.print("{f}\n", .{e});
        }
        return error.AnalysisFailed;
    }

    // Generate IR
    const irResult = try IRGen.generate(.{
        .module = &module,
        .allocator = allocator,
        .resolutions = &analyzeResult.resolutions,
        .overloadedNames = &analyzeResult.overloadedNames,
        .fieldIndices = &analyzeResult.fieldIndices,
        .matchStructFieldIndices = &analyzeResult.matchStructFieldIndices,
        .enumInits = &analyzeResult.enumInits,
        .derefTypes = &analyzeResult.derefTypes,
        .indexElemTypes = &analyzeResult.indexElemTypes,
        .arrayLiteralElemTypes = &analyzeResult.arrayLiteralElemTypes,
        .monomorphizedFunctions = analyzeResult.monomorphizedFunctions.items,
        .structInitResolutions = &analyzeResult.structInitResolutions,
        .importedVarNames = &importedVarNames,
        .monomorphizedEnums = &analyzeResult.monomorphizedEnums,
        .matchEnumNames = &analyzeResult.matchEnumNames,
        .extensionCalls = &analyzeResult.extensionCalls,
        .lambdaNames = &analyzeResult.lambdaNames,
        .lambdaTypes = &analyzeResult.lambdaTypes,
        .safeNavInfo = &analyzeResult.safeNavInfo,
        .returnWrapInfo = &analyzeResult.returnWrapInfo,
        .primitiveCastInfo = &analyzeResult.primitiveCastInfo,
    });

    const compiled = CompiledModule{
        .analyzeResult = analyzeResult,
        .irResult = irResult,
    };

    // Cache result and unmark in-progress
    const cacheKey = try allocator.dupe(u8, path);
    errdefer allocator.free(cacheKey);
    try self.cache.put(cacheKey, compiled);
    _ = self.inProgress.remove(path);

    return self.cache.get(path).?;
}

/// Merge dependency IR instructions before entry module IR.
/// Dependencies' fn_def and fn_decl go first, then entry module's instructions.
fn mergeIr(
    allocator: std.mem.Allocator,
    depModules: []const CompiledModule,
    entryIr: *const ir.ZSIRInstructions,
) !ir.ZSIRInstructions {
    var merged = try std.ArrayList(ir.ZSIR).initCapacity(allocator, 32);
    defer merged.deinit(allocator);

    // Add all dependency instructions first (skip module_init — deps are already inlined)
    for (depModules) |dep| {
        for (dep.irResult.instructions.instructions) |inst| {
            if (inst == .module_init) continue;
            try merged.append(allocator, inst);
        }
    }

    // Add entry module instructions (skip module_init — deps are already inlined)
    for (entryIr.instructions) |inst| {
        if (inst == .module_init) continue;
        try merged.append(allocator, inst);
    }

    return .{ .instructions = try allocator.dupe(ir.ZSIR, merged.items) };
}

/// Find the prelude.zs path relative to the compiler executable.
fn findPreludePath(self: *Self, allocator: std.mem.Allocator) !?[]const u8 {
    // Try CWD first so workspace builds use the source stdlib rather than zig-out copies.
    const cwdCandidates = [_][]const u8{ "stdlib/prelude.chisa", "stdlib/prelude.zs" };
    for (cwdCandidates) |candidatePath| {
        if (std.Io.Dir.cwd().access(self.io, candidatePath, .{})) |_| {
            return try allocator.dupe(u8, candidatePath);
        } else |_| {}
    }

    return null;
}

pub fn compile(self: *Self, args: Args.ExecutionArgs) !void {
    const allocator = self.allocator;

    const buffer = std.Io.Dir.cwd().readFileAlloc(self.io, args.entryPoint, allocator, .limited(16 * 1024 * 1024)) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: file not found: '{s}'\n", .{args.entryPoint});
            return;
        }
        return err;
    };
    defer allocator.free(buffer);

    const tokenizer = Tokenizer.create(buffer);

    if (args.verbose) std.debug.print("Parsing\n", .{});
    var parser = try Parser.create(
        allocator,
        tokenizer,
        args.entryPoint,
        buffer,
    );

    const rawModule = try parser.parse(allocator);
    // preprocessModule shares .deps/.allocatedStrings from rawModule, but copies .ast into a
    // new slice — so we only free the original ast slice here, not deinit (which would double-free).
    defer allocator.free(rawModule.ast);

    // Preprocess conditional compilation
    var ppCtx = Preprocessor.CompileTimeContext.init(allocator);
    defer ppCtx.deinit();
    const module = try Preprocessor.preprocessModule(allocator, rawModule, &ppCtx);
    defer module.deinit(allocator);

    var depAnalyzeResults = std.StringHashMap(Analyzer.AnalyzeResult).init(allocator);
    defer depAnalyzeResults.deinit();

    // Build imported var names for the entry module
    var importedVarNames = std.StringHashMap([]const u8).init(allocator);
    defer importedVarNames.deinit();

    // Collect compiled dep modules in order
    var depCompiled = try std.ArrayList(CompiledModule).initCapacity(allocator, 4);
    defer depCompiled.deinit(allocator);

    // Precompile and cache the prelude before compiling entry dependencies.
    // Stdlib dependencies rely on its scalar declarations even when full prelude
    // symbol injection is intentionally disabled for stdlib modules.
    if (try findPreludePath(self, allocator)) |pPath| {
        defer allocator.free(pPath);
        if (self.cache.get(pPath) == null) {
            _ = self.compileModule(pPath, false) catch |err| {
                std.debug.print("Warning: could not compile prelude: {}\n", .{err});
                return;
            };
        }
    }

    for (module.deps) |dep| {
        const resolvedPath = try resolvePath(allocator, args.entryPoint, dep.path);
        defer allocator.free(resolvedPath);

        const depPath = try allocator.dupe(u8, resolvedPath);
        defer allocator.free(depPath);
        const depResult = self.compileModule(depPath, true) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        try depAnalyzeResults.put(dep.path, depResult.analyzeResult);
        try depCompiled.append(allocator, depResult);

        // Map imported symbol names to their IR names from the dep
        for (dep.symbols) |sym| {
            const localName = sym.alias orelse sym.name;
            if (depResult.irResult.varNames.get(sym.name)) |irName| {
                try importedVarNames.put(localName, irName);
            } else if (depResult.analyzeResult.exports.get(sym.name)) |exportedSym| {
                if (exportedSym.signature == .function) {
                    try importedVarNames.put(localName, sym.name);
                }
            }
        }
    }

    // Auto-import stdlib prelude
    var preludeExports: ?*const @import("analyzer/symbol_table_stack.zig").SymbolTable = null;
    var preludeOverloads: ?*const std.StringHashMap(std.ArrayList(Analyzer.OverloadEntry)) = null;
    var preludeStructDefs: ?*const std.StringHashMap(Analyzer.StructDef) = null;
    var preludeEnumDefs: ?*const std.StringHashMap(Analyzer.EnumDef) = null;
    var preludeGenericFns: ?*const std.StringHashMap(Analyzer.GenericFnDef) = null;
    var preludeScalarDefs: ?*const std.StringHashMap(@import("analyzer/symbol_signature.zig").ZSType) = null;
    const entryIsStdlib = isStdlibPath(args.entryPoint);
    if (try findPreludePath(self, allocator)) |pPath| {
        defer allocator.free(pPath);
        if (self.cache.get(pPath) == null) {
            _ = self.compileModule(pPath, false) catch |err| {
                std.debug.print("Warning: could not compile prelude: {}\n", .{err});
                return;
            };
        }
        if (self.compileModule(pPath, false)) |preludeCompiled| {
            // Add prelude first so its functions (alloc, free, etc.) are available
            try depCompiled.append(allocator, preludeCompiled);
            // Add prelude's transitive deps (like arraylist.zs) after
            var cacheIter2 = self.cache.iterator();
            while (cacheIter2.next()) |cEntry| {
                // Check if already in depCompiled (avoid duplicates)
                var found = false;
                for (depCompiled.items) |existing| {
                    if (existing.irResult.instructions.instructions.ptr == cEntry.value_ptr.irResult.instructions.instructions.ptr) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try depCompiled.append(allocator, cEntry.value_ptr.*);
                }
            }
            // Get a stable pointer from the cache (not the local copy which goes out of scope)
            const cachedPrelude = self.cache.getPtr(pPath) orelse return error.PreludeCacheInconsistency;
            preludeScalarDefs = &cachedPrelude.analyzeResult.scalarDefs;
            if (!entryIsStdlib) {
                preludeExports = &cachedPrelude.analyzeResult.exports;
                preludeOverloads = &cachedPrelude.analyzeResult.overloads;
                preludeStructDefs = &cachedPrelude.analyzeResult.structDefs;
                preludeEnumDefs = &cachedPrelude.analyzeResult.enumDefs;
                preludeGenericFns = &cachedPrelude.analyzeResult.genericFns;
            }

            // Map all exported symbols from prelude to IR names
            if (!entryIsStdlib) {
                var exportIter = cachedPrelude.analyzeResult.exports.iterator();
                while (exportIter.next()) |entry| {
                    if (cachedPrelude.irResult.varNames.get(entry.key_ptr.*)) |irName| {
                        try importedVarNames.put(entry.key_ptr.*, irName);
                    }
                }
            }
        } else |err| {
            std.debug.print("Warning: could not compile prelude: {}\n", .{err});
        }
    }

    if (args.verbose) std.debug.print("Analyzing\n", .{});

    var analyzeResult = try Analyzer.analyzeWithPrelude(module, allocator, &depAnalyzeResults, preludeExports, preludeOverloads, preludeStructDefs, preludeEnumDefs, preludeGenericFns, preludeScalarDefs);
    defer analyzeResult.deinit(allocator);

    for (analyzeResult.errors) |e| {
        std.debug.print("{f}\n", .{e});
    }

    // Dump symbols as JSON if requested
    if (args.dumpSymbols) {
        try dump_symbols.dump(allocator, self.io, analyzeResult);
    }

    if (analyzeResult.errors.len != 0) {
        return error.AnalysisFailed;
    }

    if (args.verbose) std.debug.print("Generating ir\n", .{});
    var entryIrResult = try IRGen.generate(.{
        .module = &module,
        .allocator = allocator,
        .resolutions = &analyzeResult.resolutions,
        .overloadedNames = &analyzeResult.overloadedNames,
        .fieldIndices = &analyzeResult.fieldIndices,
        .matchStructFieldIndices = &analyzeResult.matchStructFieldIndices,
        .enumInits = &analyzeResult.enumInits,
        .derefTypes = &analyzeResult.derefTypes,
        .indexElemTypes = &analyzeResult.indexElemTypes,
        .arrayLiteralElemTypes = &analyzeResult.arrayLiteralElemTypes,
        .monomorphizedFunctions = analyzeResult.monomorphizedFunctions.items,
        .structInitResolutions = &analyzeResult.structInitResolutions,
        .importedVarNames = &importedVarNames,
        .monomorphizedEnums = &analyzeResult.monomorphizedEnums,
        .matchEnumNames = &analyzeResult.matchEnumNames,
        .extensionCalls = &analyzeResult.extensionCalls,
        .lambdaNames = &analyzeResult.lambdaNames,
        .lambdaTypes = &analyzeResult.lambdaTypes,
        .safeNavInfo = &analyzeResult.safeNavInfo,
        .returnWrapInfo = &analyzeResult.returnWrapInfo,
        .primitiveCastInfo = &analyzeResult.primitiveCastInfo,
    });
    defer entryIrResult.deinit(allocator);

    // Merge dependency IR with entry module IR
    const mergedIr = try mergeIr(allocator, depCompiled.items, &entryIrResult.instructions);
    // Only free the merged instructions array, not individual instructions (owned by deps/entry)
    defer allocator.free(mergedIr.instructions);

    if (args.dumpIr or args.run or args.outputPath != null) {
        if (args.verbose) std.debug.print("Generating llvm\n", .{});

        // Build struct field types map from all struct defs
        var depStructDefPtrs = try std.ArrayList(*const std.StringHashMap(Analyzer.StructDef)).initCapacity(allocator, depCompiled.items.len);
        defer depStructDefPtrs.deinit(allocator);
        for (depCompiled.items) |dep| {
            try depStructDefPtrs.append(allocator, &dep.analyzeResult.structDefs);
            try depStructDefPtrs.append(allocator, &dep.analyzeResult.exportedStructDefs);
        }
        var structFieldTypes = try buildStructFieldTypes(allocator, &analyzeResult.structDefs, depStructDefPtrs.items);
        defer {
            var sfIter = structFieldTypes.iterator();
            while (sfIter.next()) |entry| {
                for (entry.value_ptr.*) |fieldType| allocator.free(fieldType);
                allocator.free(entry.value_ptr.*);
            }
            structFieldTypes.deinit();
        }

        const llvmModule = try llvm.generateLLVMModule(&mergedIr, allocator, &structFieldTypes, module.source, module.filename, args.debug);

        if (args.dumpIr) {
            const irStr = core.LLVMPrintModuleToString(llvmModule);
            defer core.LLVMDisposeMessage(irStr);
            const irSlice = std.mem.span(irStr);
            if (args.outputPath) |outputPath| {
                const irPath = try std.fmt.allocPrint(allocator, "{s}.ll", .{outputPath});
                defer allocator.free(irPath);
                const ll_with_newline = try std.mem.concat(allocator, u8, &.{ irSlice, "\n" });
                defer allocator.free(ll_with_newline);
                try std.Io.Dir.cwd().writeFile(self.io, .{
                    .sub_path = irPath,
                    .data = ll_with_newline,
                });
            } else {
                try std.Io.File.stdout().writeStreamingAll(self.io, irSlice);
                try std.Io.File.stdout().writeStreamingAll(self.io, "\n");
            }
        }

        if (args.outputPath) |outputPath| {
            // Compilation mode: emit object file and link
            llvm.generateMain(llvmModule);

            const tmpObjPathSlice = try std.fmt.allocPrint(allocator, "/tmp/zs_output_{x}.o", .{
                std.hash.Wyhash.hash(0, outputPath),
            });
            defer allocator.free(tmpObjPathSlice);
            const tmpObjPath = try allocator.dupeZ(u8, tmpObjPathSlice);
            defer allocator.free(tmpObjPath);
            try llvm.emitObjectFile(llvmModule, tmpObjPath);
            core.LLVMDisposeModule(llvmModule);

            // Link with cc
            const ccResult = try std.process.run(allocator, self.io, .{
                .argv = &.{ "zig", "cc", "-o", outputPath, tmpObjPath, "-ldl" },
            });
            defer allocator.free(ccResult.stdout);
            defer allocator.free(ccResult.stderr);

            const linkFailed = switch (ccResult.term) {
                .exited => |code| code != 0,
                else => true,
            };
            if (linkFailed) {
                std.debug.print("Linker error:\n{s}\n", .{ccResult.stderr});
                return;
            }

            // Clean up temp file
            std.Io.Dir.cwd().deleteFile(self.io, tmpObjPathSlice) catch {};

            std.debug.print("Compiled to {s}\n", .{outputPath});
        } else if (args.run) {
            if (args.verbose) std.debug.print("Running\n", .{});
            llvm.generateMain(llvmModule);

            const tmpObjPathSlice = try std.fmt.allocPrint(allocator, "/tmp/zs_run_output_{x}.o", .{
                std.hash.Wyhash.hash(0, args.entryPoint),
            });
            defer allocator.free(tmpObjPathSlice);
            const tmpExePathSlice = try std.fmt.allocPrint(allocator, "/tmp/zs_run_output_{x}", .{
                std.hash.Wyhash.hash(0, args.entryPoint),
            });
            defer allocator.free(tmpExePathSlice);
            const tmpObjPath = try allocator.dupeZ(u8, tmpObjPathSlice);
            defer allocator.free(tmpObjPath);
            const tmpExePath = try allocator.dupeZ(u8, tmpExePathSlice);
            defer allocator.free(tmpExePath);
            try llvm.emitObjectFile(llvmModule, tmpObjPath);
            core.LLVMDisposeModule(llvmModule);
            defer std.Io.Dir.cwd().deleteFile(self.io, tmpObjPathSlice) catch {};
            defer std.Io.Dir.cwd().deleteFile(self.io, tmpExePathSlice) catch {};

            const ccResult = try std.process.run(allocator, self.io, .{
                .argv = &.{ "zig", "cc", "-o", tmpExePath, tmpObjPath, "-ldl" },
            });
            defer allocator.free(ccResult.stdout);
            defer allocator.free(ccResult.stderr);

            const linkFailed = switch (ccResult.term) {
                .exited => |code| code != 0,
                else => true,
            };
            if (linkFailed) {
                std.debug.print("Linker error:\n{s}\n", .{ccResult.stderr});
                return;
            }

            const entryDirPath = std.fs.path.dirname(args.entryPoint) orelse ".";
            const runResult = try std.process.run(allocator, self.io, .{
                .argv = &.{tmpExePath},
                .cwd = .{ .path = entryDirPath },
            });
            defer allocator.free(runResult.stdout);
            defer allocator.free(runResult.stderr);

            if (runResult.stdout.len > 0) try std.Io.File.stdout().writeStreamingAll(self.io, runResult.stdout);
            if (runResult.stderr.len > 0) try std.Io.File.stderr().writeStreamingAll(self.io, runResult.stderr);

            const runFailed = switch (runResult.term) {
                .exited => |code| code != 0,
                else => true,
            };
            if (runFailed) return;
        } else {
            core.LLVMDisposeModule(llvmModule);
        }
    }
}
