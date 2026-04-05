const std = @import("std");
const ZenScript = @import("ZenScript");
const Args = @import("args/args.zig");
const Tokenizer = @import("tokens/tokenizer.zig");
const Pipline = @import("pipeline.zig");
const llvm = @import("codegen/llvm_codegen.zig");

pub fn main() !void {
    const args = Args.collectArgs() catch |err| {
        switch (err) {
            error.MissingEntryPoint => std.debug.print("Error: no input file specified. Usage: zenscript -i <file.zs>\n", .{}),
        }
        return;
    };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var pipline = try Pipline.init(allocator);
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
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
