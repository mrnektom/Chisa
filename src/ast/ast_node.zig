const std = @import("std");
pub const expr = @import("zs_expr.zig");
pub const stmt = @import("zs_stmt.zig");
pub const type_notation = @import("zs_type_notation.zig");
pub const zs_import = @import("zs_import.zig");
pub const zs_export_from = @import("zs_export_from.zig");
pub const zs_use = @import("zs_use.zig");

pub const VarType = stmt.VarType;

pub const ZSTypeNotation = type_notation.ZSTypeNotation;
pub const ZSBuiltin = type_notation.BuiltinType;
pub const ZSImport = zs_import;
pub const ZSExportFrom = zs_export_from;
pub const ZSUse = zs_use;

/// Compile-time condition expression for `when` / `@target`.
pub const ZSWhenCond = union(enum) {
    eq: struct { name: []const u8, value: []const u8 },
    neq: struct { name: []const u8, value: []const u8 },
    flag: []const u8,
    not: *ZSWhenCond,
    and_: struct { lhs: *ZSWhenCond, rhs: *ZSWhenCond },
    or_: struct { lhs: *ZSWhenCond, rhs: *ZSWhenCond },
};

pub const ZSWhenArm = struct {
    cond: ?*ZSWhenCond, // null = else arm
    nodes: []ZSAstNode,
};

pub const ZSWhenDecl = struct {
    arms: []ZSWhenArm,
    startPos: usize,
    endPos: usize,
};

pub const ZSTargetDecl = struct {
    cond: *ZSWhenCond,
    startPos: usize,
    endPos: usize,
};

const ZSAstType = enum {
    stmt,
    expr,
    import_decl,
    export_from,
    use_decl,
    when_decl,
    target_decl,
};

pub const ZSAstNode = union(ZSAstType) {
    stmt: stmt.ZSStmt,
    expr: expr.ZSExpr,
    import_decl: ZSImport,
    export_from: ZSExportFrom,
    use_decl: ZSUse,
    when_decl: ZSWhenDecl,
    target_decl: ZSTargetDecl,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .expr => self.expr.deinit(allocator),
            .stmt => self.stmt.deinit(allocator),
            .import_decl => self.import_decl.deinit(allocator),
            .export_from => self.export_from.deinit(allocator),
            .use_decl => self.use_decl.deinit(allocator),
            .when_decl, .target_decl => {}, // consumed by preprocessor
        }
    }
};
