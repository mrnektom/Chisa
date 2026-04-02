const std = @import("std");

// ─── Incoming request ────────────────────────────────────────────────────────

pub const Request = struct {
    id: u64,
    method: []const u8,
    file: []const u8,
    content: []const u8,
    offset: ?u64 = null,
};

/// Parse a single JSON line into a Request.
/// Caller owns the returned Parsed value and must call .deinit() on it.
pub fn parseRequest(allocator: std.mem.Allocator, line: []const u8) !std.json.Parsed(Request) {
    return std.json.parseFromSlice(Request, allocator, line, .{
        .ignore_unknown_fields = true,
    });
}

// ─── Outgoing response pieces ─────────────────────────────────────────────────

pub const Diagnostic = struct {
    message: []const u8,
    line: usize,
    col: usize,
    start: usize,
    end: usize,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: []const u8,
    detail: []const u8,
};

// ─── Response builders ────────────────────────────────────────────────────────

/// Serialize a diagnostics response to a heap-allocated JSON line (with trailing \n).
/// Caller must free the returned slice.
pub fn buildDiagnosticsResponse(
    allocator: std.mem.Allocator,
    id: u64,
    diagnostics: []const Diagnostic,
) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.print("{{\"id\":{d},\"diagnostics\":[", .{id});
    for (diagnostics, 0..) |d, i| {
        if (i > 0) try w.writeAll(",");
        try w.print("{{\"message\":", .{});
        try std.json.Stringify.encodeJsonString(d.message, .{}, w);
        try w.print(",\"line\":{d},\"col\":{d},\"start\":{d},\"end\":{d}}}", .{
            d.line, d.col, d.start, d.end,
        });
    }
    try w.writeAll("]}\n");
    return aw.toOwnedSlice();
}

/// Serialize a completions response to a heap-allocated JSON line (with trailing \n).
/// Caller must free the returned slice.
pub fn buildCompletionsResponse(
    allocator: std.mem.Allocator,
    id: u64,
    completions: []const CompletionItem,
) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.print("{{\"id\":{d},\"completions\":[", .{id});
    for (completions, 0..) |c, i| {
        if (i > 0) try w.writeAll(",");
        try w.writeAll("{\"label\":");
        try std.json.Stringify.encodeJsonString(c.label, .{}, w);
        try w.writeAll(",\"kind\":");
        try std.json.Stringify.encodeJsonString(c.kind, .{}, w);
        try w.writeAll(",\"detail\":");
        try std.json.Stringify.encodeJsonString(c.detail, .{}, w);
        try w.writeAll("}");
    }
    try w.writeAll("]}\n");
    return aw.toOwnedSlice();
}

/// Serialize a hover response to a heap-allocated JSON line (with trailing \n).
/// Caller must free the returned slice.
pub fn buildHoverResponse(
    allocator: std.mem.Allocator,
    id: u64,
    type_str: ?[]const u8,
) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.print("{{\"id\":{d},\"type\":", .{id});
    if (type_str) |t| {
        try std.json.Stringify.encodeJsonString(t, .{}, w);
    } else {
        try w.writeAll("null");
    }
    try w.writeAll("}\n");
    return aw.toOwnedSlice();
}

/// Serialize an error response to a heap-allocated JSON line (with trailing \n).
/// Caller must free the returned slice.
pub fn buildErrorResponse(
    allocator: std.mem.Allocator,
    id: u64,
    message: []const u8,
) ![]u8 {
    var aw = std.Io.Writer.Allocating.init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;

    try w.print("{{\"id\":{d},\"error\":", .{id});
    try std.json.Stringify.encodeJsonString(message, .{}, w);
    try w.writeAll("}\n");
    return aw.toOwnedSlice();
}
