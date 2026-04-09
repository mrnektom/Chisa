const std = @import("std");
const Tokenizer = @import("tokens/tokenizer.zig");
const Parser = @import("parser.zig");
const Analyzer = @import("analyzer/analyzer.zig");
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

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .cache = std.StringHashMap(CompiledModule).init(allocator),
        .inProgress = std.StringHashMap(void).init(allocator),
        .allSources = try std.ArrayList([]const u8).initCapacity(allocator, 4),
        .allModules = try std.ArrayList(zsm.ZSModule).initCapacity(allocator, 4),
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

/// Recursively compile a module and all its dependencies.
/// Returns the CompiledModule for the given path.
fn compileModule(self: *Self, path: []const u8) !CompiledModule {
    const allocator = self.allocator;

    // Check cache
    if (self.cache.get(path)) |result| return result;

    // Cycle detection
    if (self.inProgress.contains(path)) {
        std.debug.print("Error: Circular import detected for '{s}'\n", .{path});
        return error.CircularImport;
    }
    try self.inProgress.put(path, {});

    // Read file
    const file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: imported module not found: '{s}'\n", .{path});
        }
        return err;
    };
    defer file.close();
    const fileSize: usize = @intCast((try file.stat()).size);
    const buffer = try file.readToEndAlloc(allocator, fileSize);
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

    for (module.deps) |dep| {
        const resolvedPath = try resolvePath(allocator, path, dep.path);
        defer allocator.free(resolvedPath);

        const depPath = try allocator.dupe(u8, resolvedPath);
        defer allocator.free(depPath);
        const depCompiled = try self.compileModule(depPath);
        try depAnalyzeResults.put(dep.path, depCompiled.analyzeResult);

        // Map imported symbol names (using alias if present) to their IR names from the dep
        for (dep.symbols) |sym| {
            const localName = sym.alias orelse sym.name;
            if (depCompiled.irResult.varNames.get(sym.name)) |irName| {
                try importedVarNames.put(localName, irName);
            }
        }
    }

    // Analyze
    const analyzeResult = try Analyzer.analyze(module, allocator, &depAnalyzeResults);

    // Generate IR
    const irResult = try IRGen.generate(.{
        .module = &module,
        .allocator = allocator,
        .resolutions = &analyzeResult.resolutions,
        .overloadedNames = &analyzeResult.overloadedNames,
        .fieldIndices = &analyzeResult.fieldIndices,
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
fn findPreludePath(allocator: std.mem.Allocator) !?[]const u8 {
    // Try CWD first so workspace builds use the source stdlib rather than zig-out copies.
    const cwdCandidates = [_][]const u8{ "stdlib/prelude.chisa", "stdlib/prelude.zs" };
    for (cwdCandidates) |candidatePath| {
        const cwdCandidate = try allocator.dupe(u8, candidatePath);
        if (std.fs.cwd().access(cwdCandidate, .{})) |_| {
            return cwdCandidate;
        } else |_| {
            allocator.free(cwdCandidate);
        }
    }

    // Try relative to executable
    var buf: [4096]u8 = undefined;
    if (std.fs.selfExePath(&buf)) |ep| {
        const exeDir = std.fs.path.dirname(ep) orelse ".";
        const exeCandidates = [_][]const u8{ "prelude.chisa", "prelude.zs" };
        for (exeCandidates) |preludeName| {
            const candidate = try std.fs.path.join(allocator, &.{ exeDir, "stdlib", preludeName });
            if (std.fs.cwd().access(candidate, .{})) |_| {
                return candidate;
            } else |_| {
                allocator.free(candidate);
            }
        }
        // Try one level up (zig-out/bin/../stdlib)
        const parentDir = std.fs.path.dirname(exeDir) orelse ".";
        for (exeCandidates) |preludeName| {
            const candidate = try std.fs.path.join(allocator, &.{ parentDir, "stdlib", preludeName });
            if (std.fs.cwd().access(candidate, .{})) |_| {
                return candidate;
            } else |_| {
                allocator.free(candidate);
            }
        }
    } else |_| {}

    return null;
}

pub fn compile(self: *Self, args: Args.ExecutionArgs) !void {
    const allocator = self.allocator;

    const file = std.fs.cwd().openFile(args.entryPoint, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("Error: file not found: '{s}'\n", .{args.entryPoint});
            return;
        }
        return err;
    };
    defer file.close();
    const fileSize: usize = @intCast((try file.stat()).size);
    const buffer = try file.readToEndAlloc(allocator, fileSize);
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

    for (module.deps) |dep| {
        const resolvedPath = try resolvePath(allocator, args.entryPoint, dep.path);
        defer allocator.free(resolvedPath);

        const depPath = try allocator.dupe(u8, resolvedPath);
        defer allocator.free(depPath);
        const depResult = self.compileModule(depPath) catch |err| switch (err) {
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
    if (try findPreludePath(allocator)) |pPath| {
        defer allocator.free(pPath);
        if (self.compileModule(pPath)) |preludeCompiled| {
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
            preludeExports = &cachedPrelude.analyzeResult.exports;
            preludeOverloads = &cachedPrelude.analyzeResult.overloads;
            preludeStructDefs = &cachedPrelude.analyzeResult.exportedStructDefs;
            preludeEnumDefs = &cachedPrelude.analyzeResult.enumDefs;
            preludeGenericFns = &cachedPrelude.analyzeResult.genericFns;
            preludeScalarDefs = &cachedPrelude.analyzeResult.scalarDefs;

            // Map all exported symbols from prelude to IR names
            var exportIter = cachedPrelude.analyzeResult.exports.iterator();
            while (exportIter.next()) |entry| {
                if (cachedPrelude.irResult.varNames.get(entry.key_ptr.*)) |irName| {
                    try importedVarNames.put(entry.key_ptr.*, irName);
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
        try dump_symbols.dump(allocator, analyzeResult);
    }

    if (analyzeResult.errors.len == 0) {
        if (args.verbose) std.debug.print("Generating ir\n", .{});
        var entryIrResult = try IRGen.generate(.{
            .module = &module,
            .allocator = allocator,
            .resolutions = &analyzeResult.resolutions,
            .overloadedNames = &analyzeResult.overloadedNames,
            .fieldIndices = &analyzeResult.fieldIndices,
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
                    const irFile = try std.fs.cwd().createFile(irPath, .{});
                    defer irFile.close();
                    try irFile.writeAll(irSlice);
                    try irFile.writeAll("\n");
                } else {
                    const stdout = std.fs.File.stdout();
                    try stdout.writeAll(irSlice);
                    try stdout.writeAll("\n");
                }
            }

            if (args.outputPath) |outputPath| {
                // Compilation mode: emit object file and link
                llvm.generateMain(llvmModule);

                const tmpObjPath = "/tmp/zs_output.o";
                try llvm.emitObjectFile(llvmModule, tmpObjPath);
                core.LLVMDisposeModule(llvmModule);

                // Link with cc
                const ccResult = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &.{ "zig", "cc", "-o", outputPath, tmpObjPath, "-ldl" },
                });
                defer allocator.free(ccResult.stdout);
                defer allocator.free(ccResult.stderr);

                const linkFailed = switch (ccResult.term) {
                    .Exited => |code| code != 0,
                    else => true,
                };
                if (linkFailed) {
                    std.debug.print("Linker error:\n{s}\n", .{ccResult.stderr});
                    return;
                }

                // Clean up temp file
                std.fs.cwd().deleteFile(tmpObjPath) catch {};

                std.debug.print("Compiled to {s}\n", .{outputPath});
            } else if (args.run) {
                if (args.verbose) std.debug.print("Running\n", .{});
                llvm.generateMain(llvmModule);

                const tmpObjPath = "/tmp/zs_run_output.o";
                const tmpExePath = "/tmp/zs_run_output";
                try llvm.emitObjectFile(llvmModule, tmpObjPath);
                core.LLVMDisposeModule(llvmModule);
                defer std.fs.cwd().deleteFile(tmpObjPath) catch {};
                defer std.fs.cwd().deleteFile(tmpExePath) catch {};

                const ccResult = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &.{ "zig", "cc", "-o", tmpExePath, tmpObjPath, "-ldl" },
                });
                defer allocator.free(ccResult.stdout);
                defer allocator.free(ccResult.stderr);

                const linkFailed = switch (ccResult.term) {
                    .Exited => |code| code != 0,
                    else => true,
                };
                if (linkFailed) {
                    std.debug.print("Linker error:\n{s}\n", .{ccResult.stderr});
                    return;
                }

                const entryDirPath = std.fs.path.dirname(args.entryPoint) orelse ".";
                const runResult = try std.process.Child.run(.{
                    .allocator = allocator,
                    .argv = &.{ tmpExePath },
                    .cwd = entryDirPath,
                });
                defer allocator.free(runResult.stdout);
                defer allocator.free(runResult.stderr);

                const stdout = std.fs.File.stdout();
                const stderr = std.fs.File.stderr();
                if (runResult.stdout.len > 0) try stdout.writeAll(runResult.stdout);
                if (runResult.stderr.len > 0) try stderr.writeAll(runResult.stderr);

                const runFailed = switch (runResult.term) {
                    .Exited => |code| code != 0,
                    else => true,
                };
                if (runFailed) return;
            } else {
                core.LLVMDisposeModule(llvmModule);
            }
        }
    }
}
