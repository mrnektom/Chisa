const std = @import("std");
const ZenScript = @import("ZenScript");
const Args = @import("args/args.zig");
const Tokenizer = @import("tokens/tokenizer.zig");
const Pipline = @import("pipeline.zig");
const llvm = @import("codegen/llvm_codegen.zig");

pub fn main(init: std.process.Init) !void {
    const argv = try init.minimal.args.toSlice(init.arena.allocator());
    const args = Args.collectArgs(argv) catch |err| {
        switch (err) {
            error.MissingEntryPoint => std.debug.print("Error: no input file specified. Usage: zenscript -i <file.zs>\n", .{}),
        }
        return;
    };

    var pipline = try Pipline.init(init.gpa, init.io);
    defer pipline.deinit();
    try pipline.compile(args);
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    try std.testing.fuzz({}, testOne, .{});
}

fn testOne(context: void, smith: *std.testing.Smith) !void {
    _ = context;
    var buf: [32]u8 = undefined;
    const len = smith.valueRangeAtMost(u8, 0, buf.len);
    smith.bytes(buf[0..len]);
    try std.testing.expect(!std.mem.eql(u8, "canyoufindme", buf[0..len]));
}
