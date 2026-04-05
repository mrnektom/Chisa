const std = @import("std");

pub const Severity = enum { err, warning, info };
pub const Phase = enum { parse, analyze, irgen, link };

message: []const u8,
severity: Severity = .err,
phase: Phase = .analyze,
filename: ?[]const u8 = null,
codeLine: ?[]const u8 = null,
lineNumber: ?usize = null,
lineCol: ?usize = null,
start: ?usize = null,
end: ?usize = null,

pub fn format(
    self: @This(),
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    if (self.filename) |fname| {
        const ln = (self.lineNumber orelse 0) + 1;
        const col = (self.lineCol orelse 0) + 1;
        try writer.print("\n{s}\n{s}:{}:{}\n", .{ self.message, fname, ln, col });
    } else {
        try writer.print("\n{s}\n", .{self.message});
    }

    if (self.codeLine) |cl| {
        const ln = (self.lineNumber orelse 0) + 1;
        try writer.print("{} | {s}\n", .{ ln, cl });
        try writer.print("{} | ", .{ln});
        const col = self.lineCol orelse 0;
        for (0..col) |_| {
            try writer.writeByte(' ');
        }
        try writer.print("^\n", .{});
    }
}
