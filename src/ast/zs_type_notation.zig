const std = @import("std");

pub const ZSTypeType = enum { reference, generic, array, fn_type };

pub const ZSType = union(ZSTypeType) {
    reference: []const u8,
    generic: ZSGenericType,
    array: ZSArrayType,
    fn_type: ZSFnType,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        switch (self.*) {
            .generic => |g| g.deinit(allocator),
            .array => |a| a.deinit(allocator),
            .fn_type => |f| f.deinit(allocator),
            .reference => {},
        }
    }

    /// Returns the base type name (reference name or generic base name).
    pub fn typeName(self: @This()) []const u8 {
        return switch (self) {
            .reference => |ref| ref,
            .generic => |g| g.name,
            .array => |a| a.element_type.typeName(),
            .fn_type => "function",
        };
    }
};

pub const ZSGenericType = struct {
    name: []const u8,
    type_args: []ZSType,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        for (self.type_args) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.type_args);
    }
};

pub const ZSFnType = struct {
    param_types: []ZSType,
    return_type: *ZSType,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        for (self.param_types) |*pt| {
            pt.deinit(allocator);
        }
        allocator.free(self.param_types);
        self.return_type.deinit(allocator);
        allocator.destroy(self.return_type);
    }
};

pub const ZSArrayType = struct {
    element_type: *ZSType,

    pub fn deinit(self: *const @This(), allocator: std.mem.Allocator) void {
        self.element_type.deinit(allocator);
        allocator.destroy(self.element_type);
    }
};

pub const BuiltinType = enum { number };
