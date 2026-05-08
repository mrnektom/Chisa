const std = @import("std");
const builtin = @import("builtin");
const protocol = @import("protocol.zig");
const handler = @import("handler.zig");

const use_unix_socket = builtin.os.tag != .windows;

const unix_socket_path = "/tmp/zs-daemon.sock";
const default_tcp_port: u16 = 7654;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var stdlib_path: ?[]const u8 = null;
    var tcp_port: u16 = default_tcp_port;
    var check_file: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--stdlib") and i + 1 < args.len) {
            i += 1;
            stdlib_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            i += 1;
            tcp_port = std.fmt.parseInt(u16, args[i], 10) catch default_tcp_port;
        } else if (std.mem.eql(u8, args[i], "--check-file") and i + 1 < args.len) {
            i += 1;
            check_file = args[i];
        }
    }

    const ctx = handler.Context{ .stdlib_path = stdlib_path };

    if (check_file) |path| {
        try runOneShotCheck(allocator, io, path, ctx);
        return;
    }

    if (use_unix_socket) {
        const addr = try std.Io.net.UnixAddress.init(unix_socket_path);
        try runServer(allocator, io, addr, true, ctx);
    } else {
        const addr = try std.Io.net.IpAddress.parseIp4("127.0.0.1", tcp_port);
        try runServer(allocator, io, addr, false, ctx);
    }
}

fn runOneShotCheck(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    ctx: handler.Context,
) !void {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(16 * 1024 * 1024));
    defer allocator.free(content);

    const req = protocol.Request{
        .id = 1,
        .method = "check",
        .file = path,
        .content = content,
        .offset = null,
    };

    const resp = handler.dispatch(allocator, req, ctx);
    defer allocator.free(resp);

    try std.Io.File.stdout().writeStreamingAll(io, resp);
}

fn runServer(
    allocator: std.mem.Allocator,
    io: std.Io,
    addr: anytype,
    is_unix: bool,
    ctx: handler.Context,
) !void {
    if (is_unix) {
        std.Io.Dir.deleteFileAbsolute(io, unix_socket_path) catch {};
    }

    var server = try addr.listen(io, .{});
    defer {
        server.deinit(io);
        if (is_unix) std.Io.Dir.deleteFileAbsolute(io, unix_socket_path) catch {};
    }

    if (is_unix) {
        std.debug.print("zs-daemon listening on {s}\n", .{unix_socket_path});
    } else {
        std.debug.print("zs-daemon listening on 127.0.0.1:{d}\n", .{default_tcp_port});
    }

    while (true) {
        var conn = server.accept(io) catch |err| {
            std.debug.print("accept error: {s}\n", .{@errorName(err)});
            continue;
        };
        std.debug.print("client connected\n", .{});
        handleConnection(allocator, io, conn, ctx) catch |err| {
            std.debug.print("connection error: {s}\n", .{@errorName(err)});
        };
        conn.close(io);
        std.debug.print("client disconnected\n", .{});
    }
}

// ─── Connection handler ───────────────────────────────────────────────────────

fn handleConnection(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, ctx: handler.Context) !void {
    const reader_buf = try allocator.alloc(u8, 4 * 1024 * 1024);
    defer allocator.free(reader_buf);
    var reader = stream.reader(io, reader_buf);
    while (true) {
        const line = reader.interface.takeDelimiter('\n') catch |err| switch (err) {
            error.ReadFailed, error.StreamTooLong => return err,
        } orelse return;
        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;
        processLine(allocator, io, stream, trimmed, ctx) catch |err| {
            std.debug.print("processLine error: {s}\n", .{@errorName(err)});
            return;
        };
    }
}

fn processLine(allocator: std.mem.Allocator, io: std.Io, stream: std.Io.net.Stream, line: []const u8, ctx: handler.Context) !void {
    const parsed = protocol.parseRequest(allocator, line) catch |err| {
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        const resp = try protocol.buildErrorResponse(allocator, 0, "invalid JSON request");
        defer allocator.free(resp);
        var buffer: [4096]u8 = undefined;
        var writer = stream.writer(io, &buffer);
        try writer.interface.writeAll(resp);
        try writer.interface.flush();
        return;
    };
    defer parsed.deinit();

    const resp = handler.dispatch(allocator, parsed.value, ctx);
    defer allocator.free(resp);

    var buffer: [4096]u8 = undefined;
    var writer = stream.writer(io, &buffer);
    try writer.interface.writeAll(resp);
    try writer.interface.flush();
}
