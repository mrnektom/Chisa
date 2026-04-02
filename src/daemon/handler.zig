const std = @import("std");
const daemon_api = @import("daemon_api");
const Tokenizer = daemon_api.Tokenizer;
const Parser = daemon_api.Parser;
const Analyzer = daemon_api.Analyzer;
const Sig = daemon_api.Sig;
const SymbolTable = daemon_api.SymbolTable;
const ZSAstType = daemon_api.ZSAstType;
const protocol = @import("protocol.zig");

/// Per-request context passed from server.zig.
pub const Context = struct {
    /// Path to the stdlib directory (containing prelude.zs). Null if not configured.
    stdlib_path: ?[]const u8,
};

/// Dispatch a parsed request and return a heap-allocated JSON response line.
/// Caller must free the returned slice.
pub fn dispatch(allocator: std.mem.Allocator, req: protocol.Request, ctx: Context) []u8 {
    return dispatchInner(allocator, req, ctx) catch |err| {
        const msg = std.fmt.allocPrint(allocator, "internal error: {s}", .{@errorName(err)}) catch
            return allocator.dupe(u8, "{\"id\":0,\"error\":\"out of memory\"}\n") catch "";
        defer allocator.free(msg);
        return protocol.buildErrorResponse(allocator, req.id, msg) catch
            allocator.dupe(u8, "{\"id\":0,\"error\":\"out of memory\"}\n") catch "";
    };
}

fn dispatchInner(allocator: std.mem.Allocator, req: protocol.Request, ctx: Context) ![]u8 {
    if (std.mem.eql(u8, req.method, "check")) {
        return handleCheck(allocator, req, ctx);
    } else if (std.mem.eql(u8, req.method, "complete")) {
        return handleComplete(allocator, req, ctx);
    } else if (std.mem.eql(u8, req.method, "hover")) {
        return handleHover(allocator, req, ctx);
    } else {
        const msg = try std.fmt.allocPrint(allocator, "unknown method: {s}", .{req.method});
        defer allocator.free(msg);
        return protocol.buildErrorResponse(allocator, req.id, msg);
    }
}

// ─── check ────────────────────────────────────────────────────────────────────

fn handleCheck(allocator: std.mem.Allocator, req: protocol.Request, ctx: Context) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var result = try runAnalyzer(a, req.file, req.content, ctx) orelse {
        return protocol.buildDiagnosticsResponse(allocator, req.id, &.{});
    };
    defer result.deinit(a);

    var diags: std.ArrayList(protocol.Diagnostic) = .empty;
    defer diags.deinit(allocator);

    for (result.errors) |err| {
        try diags.append(allocator, .{
            .message = err.message,
            .line = err.lineNumber,
            .col = err.lineCol,
            .start = err.start,
            .end = err.end,
        });
    }

    return protocol.buildDiagnosticsResponse(allocator, req.id, diags.items);
}

// ─── complete ─────────────────────────────────────────────────────────────────

fn handleComplete(allocator: std.mem.Allocator, req: protocol.Request, ctx: Context) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var result = try runAnalyzer(a, req.file, req.content, ctx) orelse {
        return protocol.buildCompletionsResponse(allocator, req.id, &.{});
    };
    defer result.deinit(a);

    var items: std.ArrayList(protocol.CompletionItem) = .empty;
    defer items.deinit(allocator);

    var it = result.exports.iterator();
    while (it.next()) |entry| {
        const sym = entry.value_ptr.*;
        const detail = if (sym.signature == .unknown) blk: {
            if (result.genericFns.get(sym.name)) |gfn| {
                break :blk try genericFnDetail(a, gfn.func.name, gfn.func.type_params, gfn.func.args, gfn.func.ret);
            }
            break :blk try signatureDetail(a, sym.name, sym.signature);
        } else try signatureDetail(a, sym.name, sym.signature);
        try items.append(allocator, .{
            .label = sym.name,
            .kind = kindString(sym.signature),
            .detail = detail,
        });
    }

    // Also include exported generic functions (stored in genericFns, not in exports)
    var gfIt = result.genericFns.iterator();
    while (gfIt.next()) |entry| {
        const gfn = entry.value_ptr.*;
        if (gfn.func.modifiers.exported == null) continue;
        if (result.exports.contains(entry.key_ptr.*)) continue;
        const detail = try genericFnDetail(a, gfn.func.name, gfn.func.type_params, gfn.func.args, gfn.func.ret);
        try items.append(allocator, .{
            .label = gfn.func.name,
            .kind = "function",
            .detail = detail,
        });
    }

    return protocol.buildCompletionsResponse(allocator, req.id, items.items);
}

// ─── hover ────────────────────────────────────────────────────────────────────

fn handleHover(allocator: std.mem.Allocator, req: protocol.Request, ctx: Context) ![]u8 {
    const offset = req.offset orelse return protocol.buildHoverResponse(allocator, req.id, null);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ident = findIdentAt(req.content, offset) orelse
        return protocol.buildHoverResponse(allocator, req.id, null);

    var result = try runAnalyzer(a, req.file, req.content, ctx) orelse
        return protocol.buildHoverResponse(allocator, req.id, null);
    defer result.deinit(a);

    // Look up in moduleScope first (all top-level symbols), then exports
    const sym = result.moduleScope.get(ident) orelse result.exports.get(ident);
    if (sym) |s| {
        // If the symbol's signature is unknown, check genericFns for a better representation
        if (s.signature == .unknown) {
            if (result.genericFns.get(ident)) |gfn| {
                const type_str = try genericFnDetail(allocator, gfn.func.name, gfn.func.type_params, gfn.func.args, gfn.func.ret);
                defer allocator.free(type_str);
                return protocol.buildHoverResponse(allocator, req.id, type_str);
            }
        }
        const type_str = try signatureDetail(allocator, s.name, s.signature);
        defer allocator.free(type_str);
        return protocol.buildHoverResponse(allocator, req.id, type_str);
    }

    // Not in scope — check genericFns directly (e.g. exported generic fn)
    if (result.genericFns.get(ident)) |gfn| {
        const type_str = try genericFnDetail(allocator, gfn.func.name, gfn.func.type_params, gfn.func.args, gfn.func.ret);
        defer allocator.free(type_str);
        return protocol.buildHoverResponse(allocator, req.id, type_str);
    }

    return protocol.buildHoverResponse(allocator, req.id, null);
}

// ─── helpers ──────────────────────────────────────────────────────────────────

/// Analyze a dependency file from disk. Returns null on any error.
/// `depResults` is populated with the AnalyzeResult keyed by dep path string.
fn analyzeDep(
    allocator: std.mem.Allocator,
    depPath: []const u8,
    cache: *std.StringHashMap(Analyzer.AnalyzeResult),
    inProgress: *std.StringHashMap(void),
    prelude: *const PreludeInfo,
) void {
    if (cache.contains(depPath)) return;
    if (inProgress.contains(depPath)) return; // cycle
    inProgress.put(depPath, {}) catch return;
    defer _ = inProgress.remove(depPath);

    const file = std.fs.cwd().openFile(depPath, .{}) catch return;
    defer file.close();
    const content = file.readToEndAlloc(allocator, 16 * 1024 * 1024) catch return;
    // content is freed when arena is deinited

    const tokenizer = Tokenizer.create(content);
    var parser = Parser.create(allocator, tokenizer, depPath, content) catch return;
    const module = parser.parse(allocator) catch return;

    // Recursively resolve this dep's own deps
    var subDeps = std.StringHashMap(Analyzer.AnalyzeResult).init(allocator);
    defer subDeps.deinit();

    for (module.deps) |dep| {
        const dir = std.fs.path.dirname(depPath) orelse ".";
        const resolved = std.fs.path.join(allocator, &.{ dir, dep.path }) catch continue;
        analyzeDep(allocator, resolved, cache, inProgress, prelude);
        if (cache.get(resolved)) |r| {
            subDeps.put(dep.path, r) catch {};
        }
    }

    const result = Analyzer.analyzeWithPrelude(
        module,
        allocator,
        &subDeps,
        prelude.exports,
        prelude.overloads,
        prelude.structDefs,
        prelude.enumDefs,
        prelude.genericFns,
        prelude.scalarDefs,
    ) catch return;
    cache.put(depPath, result) catch {};
}

const PreludeInfo = struct {
    exports: ?*const SymbolTable,
    overloads: ?*const std.StringHashMap(std.ArrayList(Analyzer.OverloadEntry)),
    structDefs: ?*const std.StringHashMap(Analyzer.StructDef),
    enumDefs: ?*const std.StringHashMap(Analyzer.EnumDef),
    genericFns: ?*const std.StringHashMap(Analyzer.GenericFnDef),
    scalarDefs: ?*const std.StringHashMap(Sig.ZSType),
    result: ?*Analyzer.AnalyzeResult,

    const empty = PreludeInfo{
        .exports = null, .overloads = null, .structDefs = null,
        .enumDefs = null, .genericFns = null, .scalarDefs = null, .result = null,
    };
};

/// Load and analyze prelude.zs from `stdlib_path/prelude.zs`.
/// Returns PreludeInfo with pointers into the heap-allocated AnalyzeResult.
fn loadPrelude(allocator: std.mem.Allocator, stdlib_path: []const u8) PreludeInfo {
    const prelude_path = std.fs.path.join(allocator, &.{ stdlib_path, "prelude.zs" }) catch return PreludeInfo.empty;
    // prelude_path is arena-allocated, no need to free

    const file = std.fs.cwd().openFile(prelude_path, .{}) catch return PreludeInfo.empty;
    defer file.close();
    const content = file.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return PreludeInfo.empty;

    const tokenizer = Tokenizer.create(content);
    var parser = Parser.create(allocator, tokenizer, prelude_path, content) catch return PreludeInfo.empty;
    const module = parser.parse(allocator) catch return PreludeInfo.empty;

    var empty_deps = std.StringHashMap(Analyzer.AnalyzeResult).init(allocator);
    defer empty_deps.deinit();

    const result_ptr = allocator.create(Analyzer.AnalyzeResult) catch return PreludeInfo.empty;
    result_ptr.* = Analyzer.analyze(module, allocator, &empty_deps) catch return PreludeInfo.empty;

    return PreludeInfo{
        .exports = &result_ptr.exports,
        .overloads = &result_ptr.overloads,
        .structDefs = &result_ptr.exportedStructDefs,
        .enumDefs = &result_ptr.exportedEnumDefs,
        .genericFns = &result_ptr.genericFns,
        .scalarDefs = &result_ptr.scalarDefs,
        .result = result_ptr,
    };
}

/// Run tokenizer → parser → analyzer on in-memory content.
/// Loads prelude and resolves imports from disk. Returns null on parse/analyze error.
fn runAnalyzer(
    allocator: std.mem.Allocator,
    filename: []const u8,
    content: []const u8,
    ctx: Context,
) !?Analyzer.AnalyzeResult {
    // Load prelude if stdlib path is configured, but not when analyzing the prelude itself.
    const is_prelude = if (ctx.stdlib_path) |sp| blk: {
        const prelude_path = std.fs.path.join(allocator, &.{ sp, "prelude.zs" }) catch break :blk false;
        break :blk std.mem.eql(u8, filename, prelude_path);
    } else false;

    var prelude = if (!is_prelude) blk: {
        break :blk if (ctx.stdlib_path) |sp| loadPrelude(allocator, sp) else PreludeInfo.empty;
    } else PreludeInfo.empty;
    defer if (prelude.result) |r| {
        r.deinit(allocator);
        allocator.destroy(r);
    };

    // Parse the main file (using in-memory content)
    const tokenizer = Tokenizer.create(content);
    var parser = Parser.create(allocator, tokenizer, filename, content) catch return null;
    const module = parser.parse(allocator) catch return null;

    // Analyze dependencies from disk
    var depCache = std.StringHashMap(Analyzer.AnalyzeResult).init(allocator);
    defer {
        var it = depCache.iterator();
        while (it.next()) |entry| entry.value_ptr.deinit(allocator);
        depCache.deinit();
    }
    var inProgress = std.StringHashMap(void).init(allocator);
    defer inProgress.deinit();

    var depResults = std.StringHashMap(Analyzer.AnalyzeResult).init(allocator);
    defer depResults.deinit();

    for (module.deps) |dep| {
        const dir = std.fs.path.dirname(filename) orelse ".";
        const resolved = try std.fs.path.join(allocator, &.{ dir, dep.path });
        analyzeDep(allocator, resolved, &depCache, &inProgress, &prelude);
        if (depCache.get(resolved)) |r| {
            try depResults.put(dep.path, r);
        }
    }

    return Analyzer.analyzeWithPrelude(
        module,
        allocator,
        &depResults,
        prelude.exports,
        prelude.overloads,
        prelude.structDefs,
        prelude.enumDefs,
        prelude.genericFns,
        prelude.scalarDefs,
    ) catch null;
}

/// Find the identifier token that spans the given byte offset.
fn findIdentAt(content: []const u8, offset: u64) ?[]const u8 {
    var tok = Tokenizer.create(content);
    while (true) {
        const token = tok.next() catch break orelse break;
        if (token.type != .ident) continue;
        if (token.startPos <= offset and offset < token.endPos) {
            return token.value;
        }
        if (token.startPos > offset) break;
    }
    return null;
}

/// Format a generic function signature from AST, e.g. `fn process<T>(value: T): T`.
fn genericFnDetail(
    allocator: std.mem.Allocator,
    name: []const u8,
    type_params: []const []const u8,
    args: []const daemon_api.ZSFn.Arg,
    ret: ?ZSAstType,
) ![]const u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.print("fn {s}", .{name});

    if (type_params.len > 0) {
        try w.writeAll("<");
        for (type_params, 0..) |tp, i| {
            if (i > 0) try w.writeAll(", ");
            try w.writeAll(tp);
        }
        try w.writeAll(">");
    }

    try w.writeAll("(");
    for (args, 0..) |arg, i| {
        if (i > 0) try w.writeAll(", ");
        try w.print("{s}: {s}", .{ arg.name, if (arg.type) |t| astTypeToString(t) else "unknown" });
    }
    try w.writeAll(")");

    if (ret) |r| {
        try w.print(": {s}", .{astTypeToString(r)});
    }

    return aw.toOwnedSlice();
}

fn astTypeToString(t: ZSAstType) []const u8 {
    return switch (t) {
        .reference => |ref| ref,
        .generic => |g| g.name,
        .array => |a| a.element_type.typeName(),
        .fn_type => "function",
    };
}

fn kindString(sig: Sig.ZSType) []const u8 {
    return switch (sig) {
        .function => "function",
        .struct_type => "struct",
        .enum_type => "enum",
        else => "variable",
    };
}

/// Format a type signature as a human-readable detail string.
/// Returned slice is allocated from `allocator`.
fn signatureDetail(allocator: std.mem.Allocator, name: []const u8, sig: Sig.ZSType) ![]const u8 {
    switch (sig) {
        .function => |f| {
            var aw = std.Io.Writer.Allocating.init(allocator);
            errdefer aw.deinit();
            const w = &aw.writer;
            try w.print("fn {s}(", .{name});
            for (f.args, 0..) |arg, i| {
                if (i > 0) try w.writeAll(", ");
                try w.print("{s}: {s}", .{ arg.name, typeToString(arg.type) });
            }
            try w.print("): {s}", .{typeToString(f.ret.*)});
            return aw.toOwnedSlice();
        },
        .struct_type => |st| return std.fmt.allocPrint(allocator, "struct {s}", .{st.name}),
        .enum_type => |et| return std.fmt.allocPrint(allocator, "enum {s}", .{et.name}),
        else => return std.fmt.allocPrint(allocator, "{s}", .{typeToString(sig)}),
    }
}

fn typeToString(t: Sig.ZSType) []const u8 {
    return switch (t) {
        .number => "number",
        .boolean => "boolean",
        .char => "char",
        .long => "long",
        .short => "short",
        .byte => "byte",
        .unknown => "unknown",
        .function => "function",
        .struct_type => |st| st.name,
        .enum_type => |et| et.name,
        .pointer => "pointer",
        .array_type => "array",
    };
}
