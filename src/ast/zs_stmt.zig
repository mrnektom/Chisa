const std = @import("std");
pub const ZSVar = @import("zs_stmt_var.zig");
pub const ZSFn = @import("zs_stmt_fn.zig");
pub const ZSReassign = @import("zs_stmt_reassign.zig");
pub const ZSStruct = @import("zs_stmt_struct.zig");
pub const ZSEnum = @import("zs_stmt_enum.zig");

pub const VarType = ZSVar.VariableType;
const ZSExpr = @import("zs_expr.zig").ZSExpr;

pub const ZSScalarDecl = struct { name: []const u8, startPos: usize };

pub const ZSAsmInput = struct {
    reg: []const u8,
    expr: ZSExpr,
};

pub const ZSAsmOut = struct {
    reg: []const u8,
    name: []const u8,
};

pub const ZSAsmBlock = struct {
    inputs: []ZSAsmInput,
    outputs: []ZSAsmOut,
    clobbers: [][]const u8,
    instructions: [][]const u8,
    startPos: usize,
    endPos: usize,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        for (self.inputs) |inp| {
            var e = inp.expr;
            e.deinit(allocator);
        }
        allocator.free(self.inputs);
        allocator.free(self.outputs);
        allocator.free(self.clobbers);
        allocator.free(self.instructions);
    }
};

pub const ZSTypeAlias = struct {
    name: []const u8,
    type_params: []const []const u8,
    aliased_type: @import("zs_type_notation.zig").ZSType,
    modifiers: Modifiers,
    startPos: usize,
};

pub const ZSStmtType = enum {
    variable,
    function,
    reassign,
    struct_decl,
    enum_decl,
    scalar_decl,
    type_alias,
    asm_block,
};

pub const ZSStmt = union(ZSStmtType) {
    variable: ZSVar,
    function: ZSFn,
    reassign: ZSReassign,
    struct_decl: ZSStruct,
    enum_decl: ZSEnum,
    scalar_decl: ZSScalarDecl,
    type_alias: ZSTypeAlias,
    asm_block: ZSAsmBlock,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .variable => self.variable.deinit(allocator),
            .function => {
                if (self.function.body) |*b| {
                    b.deinit(allocator);
                }
                for (self.function.args) |*arg| {
                    if (arg.type) |*t| {
                        t.deinit(allocator);
                    }
                }
                if (self.function.ret) |*r| {
                    r.deinit(allocator);
                }
                allocator.free(self.function.args);
                allocator.free(self.function.type_params);
                allocator.free(self.function.receiver_type_params);
            },
            .reassign => self.reassign.deinit(allocator),
            .struct_decl => self.struct_decl.deinit(allocator),
            .enum_decl => self.enum_decl.deinit(allocator),
            .scalar_decl => {},
            .type_alias => |ta| {
                allocator.free(ta.type_params);
                var aliased = ta.aliased_type;
                aliased.deinit(allocator);
            },
            .asm_block => self.asm_block.deinit(allocator),
        }
    }
};

pub const Modifiers = struct {
    external: ?Modifier,
    exported: ?Modifier,
};

pub const Modifier = struct { start: usize, end: usize };
