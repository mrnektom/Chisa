const std = @import("std");
const zsm = @import("ast/zs_module.zig");
const ast = @import("ast/ast_node.zig");

pub const CompileTimeContext = struct {
    os: []const u8,
    arch: []const u8,
    flags: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) CompileTimeContext {
        return .{
            .os = detectOs(),
            .arch = detectArch(),
            .flags = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *CompileTimeContext) void {
        self.flags.deinit();
    }

    fn detectOs() []const u8 {
        return @tagName(@import("builtin").os.tag);
    }

    fn detectArch() []const u8 {
        return @tagName(@import("builtin").cpu.arch);
    }

    pub fn evalCond(self: *const CompileTimeContext, cond: *const ast.ZSWhenCond) bool {
        return switch (cond.*) {
            .eq => |eq| blk: {
                if (self.flags.get(eq.name)) |v| {
                    break :blk std.mem.eql(u8, v, eq.value);
                } else if (std.mem.eql(u8, eq.name, "os")) {
                    break :blk std.mem.eql(u8, self.os, eq.value);
                } else if (std.mem.eql(u8, eq.name, "arch")) {
                    break :blk std.mem.eql(u8, self.arch, eq.value);
                } else {
                    break :blk false;
                }
            },
            .neq => |neq| blk: {
                if (self.flags.get(neq.name)) |v| {
                    break :blk !std.mem.eql(u8, v, neq.value);
                } else if (std.mem.eql(u8, neq.name, "os")) {
                    break :blk !std.mem.eql(u8, self.os, neq.value);
                } else if (std.mem.eql(u8, neq.name, "arch")) {
                    break :blk !std.mem.eql(u8, self.arch, neq.value);
                } else {
                    break :blk true;
                }
            },
            .flag => |name| self.flags.contains(name),
            .not => |inner| !self.evalCond(inner),
            .and_ => |a| self.evalCond(a.lhs) and self.evalCond(a.rhs),
            .or_ => |a| self.evalCond(a.lhs) or self.evalCond(a.rhs),
        };
    }
};

/// Preprocess a module by evaluating @target and when declarations.
/// Returns a new module with conditional nodes expanded.
/// If @target condition is false, returns a module with empty AST.
pub fn preprocessModule(
    allocator: std.mem.Allocator,
    module: zsm.ZSModule,
    ctx: *const CompileTimeContext,
) !zsm.ZSModule {
    var result = try std.ArrayList(ast.ZSAstNode).initCapacity(allocator, module.ast.len);
    defer result.deinit(allocator);

    for (module.ast) |node| {
        switch (node) {
            .target_decl => |td| {
                // If condition is false, exclude the entire file
                if (!ctx.evalCond(td.cond)) {
                    return .{
                        .ast = try allocator.alloc(ast.ZSAstNode, 0),
                        .deps = module.deps,
                        .filename = module.filename,
                        .source = module.source,
                        .allocatedStrings = module.allocatedStrings,
                    };
                }
                // If true, just skip the @target node itself
            },
            .when_decl => |wd| {
                // Find first matching arm
                for (wd.arms) |arm| {
                    const matches = if (arm.cond) |c|
                        ctx.evalCond(c)
                    else
                        true; // else arm
                    if (matches) {
                        for (arm.nodes) |armNode| {
                            try result.append(allocator, armNode);
                        }
                        break;
                    }
                }
            },
            else => {
                try result.append(allocator, node);
            },
        }
    }

    return .{
        .ast = try allocator.dupe(ast.ZSAstNode, result.items),
        .deps = module.deps,
        .filename = module.filename,
        .source = module.source,
        .allocatedStrings = module.allocatedStrings,
    };
}
