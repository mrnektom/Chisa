const std = @import("std");
const builtin = @import("builtin");
const protocol = @import("protocol.zig");
const handler = @import("handler.zig");

const use_unix_socket = builtin.os.tag != .windows;

const unix_socket_path = "/tmp/zs-daemon.sock";
const default_tcp_port: u16 = 7654;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var stdlib_path: ?[]const u8 = null;
    var tcp_port: u16 = default_tcp_port;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--stdlib") and i + 1 < args.len) {
            i += 1;
            stdlib_path = args[i];
        } else if (std.mem.eql(u8, args[i], "--port") and i + 1 < args.len) {
            i += 1;
            tcp_port = std.fmt.parseInt(u16, args[i], 10) catch default_tcp_port;
        }
    }

    const ctx = handler.Context{ .stdlib_path = stdlib_path };

    if (use_unix_socket) {
        try runServer(allocator, try std.net.Address.initUnix(unix_socket_path), true, ctx);
    } else {
        try runServer(allocator, try std.net.Address.parseIp4("127.0.0.1", tcp_port), false, ctx);
    }
}

fn runServer(allocator: std.mem.Allocator, addr: std.net.Address, is_unix: bool, ctx: handler.Context) !void {
    if (is_unix) {
        std.fs.deleteFileAbsolute(unix_socket_path) catch {};
    }

    var server = try addr.listen(.{ .reuse_address = true });
    defer {
        server.deinit();
        if (is_unix) std.fs.deleteFileAbsolute(unix_socket_path) catch {};
    }

    if (is_unix) {
        std.debug.print("zs-daemon listening on {s}\n", .{unix_socket_path});
    } else {
        std.debug.print("zs-daemon listening on 127.0.0.1:{d}\n", .{default_tcp_port});
    }

    while (true) {
        const conn = server.accept() catch |err| {
            std.debug.print("accept error: {s}\n", .{@errorName(err)});
            continue;
        };
        std.debug.print("client connected\n", .{});
        handleConnection(allocator, conn.stream, ctx) catch |err| {
            std.debug.print("connection error: {s}\n", .{@errorName(err)});
        };
        conn.stream.close();
        std.debug.print("client disconnected\n", .{});
    }
}

// ─── Connection handler ───────────────────────────────────────────────────────

/// Buffer size for reading from the socket. A single JSON request (including
/// base64/escaped file content) must fit in this limit.
const read_buf_size = 4 * 1024 * 1024; // 4 MB

fn handleConnection(allocator: std.mem.Allocator, stream: std.net.Stream, ctx: handler.Context) !void {
    const read_buf = try allocator.alloc(u8, read_buf_size);
    defer allocator.free(read_buf);

    var rb_start: usize = 0;
    var rb_end: usize = 0;

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(allocator);

    while (true) {
        if (rb_start >= rb_end) {
            const n = try stream.read(read_buf);
            if (n == 0) return; // peer closed
            rb_start = 0;
            rb_end = n;
        }

        const chunk = read_buf[rb_start..rb_end];

        if (std.mem.indexOfScalar(u8, chunk, '\n')) |nl| {
            try line_buf.appendSlice(allocator, chunk[0..nl]);
            rb_start += nl + 1;

            const line = std.mem.trim(u8, line_buf.items, " \r\t");
            if (line.len > 0) {
                processLine(allocator, stream, line, ctx) catch |err| {
                    std.debug.print("processLine error: {s}\n", .{@errorName(err)});
                    return;
                };
            }
            line_buf.clearRetainingCapacity();
        } else {
            try line_buf.appendSlice(allocator, chunk);
            rb_start = rb_end;
        }
    }
}

fn processLine(allocator: std.mem.Allocator, stream: std.net.Stream, line: []const u8, ctx: handler.Context) !void {
    const parsed = protocol.parseRequest(allocator, line) catch |err| {
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        const resp = try protocol.buildErrorResponse(allocator, 0, "invalid JSON request");
        defer allocator.free(resp);
        return stream.writeAll(resp);
    };
    defer parsed.deinit();

    const resp = handler.dispatch(allocator, parsed.value, ctx);
    defer allocator.free(resp);

    try stream.writeAll(resp);
}

