const std = @import("std");

const Error = error{MissingEntryPoint};

pub const ExecutionArgs = struct { entryPoint: []const u8, dumpIr: bool = false, dumpSymbols: bool = false, verbose: bool = false, outputPath: ?[]const u8 = null, run: bool = false, debug: bool = false };

pub fn collectArgs(args: []const [:0]const u8) Error!ExecutionArgs {
    var execArgs = ExecutionArgs{ .entryPoint = "" };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-i")) {
            if (i + 1 < args.len) {
                i += 1;
                execArgs.entryPoint = args[i];
            } else {
                return Error.MissingEntryPoint;
            }
        } else if (std.mem.eql(u8, arg, "-dump-ir")) {
            execArgs.dumpIr = true;
        } else if (std.mem.eql(u8, arg, "-r")) {
            execArgs.run = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            if (i + 1 < args.len) {
                i += 1;
                execArgs.outputPath = args[i];
            }
        } else if (std.mem.eql(u8, arg, "-g")) {
            execArgs.debug = true;
        } else if (std.mem.eql(u8, arg, "-dump-symbols")) {
            execArgs.dumpSymbols = true;
        } else if (std.mem.eql(u8, arg, "-v")) {
            execArgs.verbose = true;
        }
    }

    if (execArgs.entryPoint.len == 0) {
        return Error.MissingEntryPoint;
    }

    return execArgs;
}
