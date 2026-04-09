const std = @import("std");
const ast = @import("../ast/ast_node.zig");
const zsm = @import("../ast/zs_module.zig");
const sig = @import("symbol_signature.zig");
const Symbol = @import("symbol.zig");
const type_resolver = @import("type_resolver.zig");
const computeMangledName = @import("ZenScript").MangleHelpers.computeMangledName;

const OverloadEntry = @import("analyzer.zig").OverloadEntry;
const StructDef = @import("analyzer.zig").StructDef;
const EnumDef = @import("analyzer.zig").EnumDef;
const Error = @import("analyzer.zig").Error;

const AnalyzeResult = @import("analyzer.zig").AnalyzeResult;
const GenericFnDef = @import("analyzer.zig").GenericFnDef;

pub fn importDependencies(
    self: anytype,
    allocator: std.mem.Allocator,
    deps: *const std.StringHashMap(AnalyzeResult),
    preludeExports: ?*const std.StringHashMap(Symbol),
    preludeOverloads: ?*const std.StringHashMap(std.ArrayList(OverloadEntry)),
    preludeStructDefs: ?*const std.StringHashMap(StructDef),
    preludeEnumDefs: ?*const std.StringHashMap(EnumDef),
    preludeGenericFns: ?*const std.StringHashMap(GenericFnDef),
    preludeScalarDefs: ?*const std.StringHashMap(Symbol.ZSTypeNotation),
) Error!void {
    // Inject prelude exports into scope
    if (preludeExports) |exports| {
        var iter = exports.iterator();
        while (iter.next()) |entry| {
            try self.tableStack.put(entry.value_ptr.*);
        }
    }

    // Import prelude function overloads so entry module can resolve them
    if (preludeOverloads) |overloads| {
        var iter2 = overloads.iterator();
        while (iter2.next()) |entry| {
            const gop = try self.overloads.getOrPut(entry.key_ptr.*);
            if (!gop.found_existing) {
                gop.value_ptr.* = try std.ArrayList(OverloadEntry).initCapacity(allocator, 2);
            }
            for (entry.value_ptr.items) |ov| {
                try gop.value_ptr.append(allocator, ov);
            }
        }
    }

    // Import exported struct definitions from dependencies
    {
        var depIter = deps.iterator();
        while (depIter.next()) |dep| {
            var sdIter = dep.value_ptr.exportedStructDefs.iterator();
            while (sdIter.next()) |entry| {
                if (!self.structDefs.contains(entry.key_ptr.*)) {
                    try self.structDefs.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
    }

    // Import prelude exported struct definitions so entry module can resolve them
    if (preludeStructDefs) |psd| {
        var iter3 = psd.iterator();
        while (iter3.next()) |entry| {
            if (!self.structDefs.contains(entry.key_ptr.*)) {
                try self.structDefs.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    // Import exported enum definitions from dependencies
    {
        var depIter2 = deps.iterator();
        while (depIter2.next()) |dep| {
            var edIter = dep.value_ptr.exportedEnumDefs.iterator();
            while (edIter.next()) |entry| {
                if (!self.enumDefs.contains(entry.key_ptr.*)) {
                    try self.enumDefs.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
    }

    // Import prelude exported enum definitions
    if (preludeEnumDefs) |ped| {
        var iter4 = ped.iterator();
        while (iter4.next()) |entry| {
            if (!self.enumDefs.contains(entry.key_ptr.*)) {
                try self.enumDefs.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    // Import generic function definitions from dependencies
    {
        var depIter3 = deps.iterator();
        while (depIter3.next()) |dep| {
            var gfIter = dep.value_ptr.genericFns.iterator();
            while (gfIter.next()) |entry| {
                if (!self.genericFns.contains(entry.key_ptr.*)) {
                    try self.genericFns.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
    }

    // Import prelude generic function definitions
    if (preludeGenericFns) |pgf| {
        var iter5 = pgf.iterator();
        while (iter5.next()) |entry| {
            if (!self.genericFns.contains(entry.key_ptr.*)) {
                try self.genericFns.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }

    // Import scalar definitions from dependencies
    {
        var depIter4 = deps.iterator();
        while (depIter4.next()) |dep| {
            var scIter = dep.value_ptr.scalarDefs.iterator();
            while (scIter.next()) |entry| {
                if (!self.scalarDefs.contains(entry.key_ptr.*)) {
                    try self.scalarDefs.put(entry.key_ptr.*, entry.value_ptr.*);
                }
            }
        }
    }

    // Import prelude scalar definitions
    if (preludeScalarDefs) |psc| {
        var scIter = psc.iterator();
        while (scIter.next()) |entry| {
            if (!self.scalarDefs.contains(entry.key_ptr.*)) {
                try self.scalarDefs.put(entry.key_ptr.*, entry.value_ptr.*);
            }
        }
    }
}

pub fn registerIntrinsic(self: anytype, allocator: std.mem.Allocator, name: []const u8, argTypeNames: []const []const u8, retType: Symbol.ZSTypeNotation) Error!void {
    const argTypes = try allocator.alloc([]const u8, argTypeNames.len);
    try self.allocatedSliceLists.append(allocator, argTypes);
    for (argTypeNames, 0..) |t, i| {
        argTypes[i] = t;
    }
    var entries = try std.ArrayList(OverloadEntry).initCapacity(allocator, 1);
    try entries.append(allocator, .{
        .argTypes = argTypes,
        .mangledName = name,
        .retType = retType,
        .external = true,
    });
    try self.overloads.put(name, entries);
}

pub fn registerTypeAliases(self: anytype, module: zsm.ZSModule) Error!void {
    for (module.ast) |node| {
        switch (node) {
            .stmt => {
                switch (node.stmt) {
                    .type_alias => |ta| {
                        try self.typeAliases.put(ta.name, .{
                            .type_params = ta.type_params,
                            .aliased_type = ta.aliased_type,
                        });
                    },
                    else => {},
                }
            },
            .import_decl, .export_from, .expr, .use_decl, .when_decl, .target_decl => {},
        }
    }
}

pub fn registerFunctions(self: anytype, module: zsm.ZSModule) Error!void {
    for (module.ast) |node| {
        switch (node) {
            .stmt => {
                switch (node.stmt) {
                    .function => |func| {
                        try registerFunction(self, func);
                    },
                    else => {},
                }
            },
            .import_decl, .export_from, .expr, .use_decl, .when_decl, .target_decl => {},
        }
    }
}

pub fn registerFunction(self: anytype, func: ast.stmt.ZSFn) Error!void {
    // If the function has type parameters OR is an extension on a generic receiver type,
    // store as a generic template so the call analyzer can monomorphize it.
    // Generic extension methods (receiver_type_params non-empty) are stored under
    // "ReceiverName.methodName" so lookup by receiver works.
    if (func.type_params.len > 0 or func.receiver_type_params.len > 0) {
        if (func.receiver_type) |receiver| {
            const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ receiver, func.name });
            try self.allocatedStrings.append(self.allocator, key);
            // Store with all type params (receiver + function level combined)
            const allTypeParams = try self.allocator.alloc([]const u8, func.receiver_type_params.len + func.type_params.len);
            try self.allocatedSliceLists.append(self.allocator, allTypeParams);
            for (func.receiver_type_params, 0..) |p, i| allTypeParams[i] = p;
            for (func.type_params, 0..) |p, i| allTypeParams[func.receiver_type_params.len + i] = p;
            try self.genericFns.put(key, .{
                .func = func,
                .type_params = allTypeParams,
            });
        } else {
            try self.genericFns.put(func.name, .{
                .func = func,
                .type_params = func.type_params,
            });
        }
        return;
    }

    // If this function has a receiver type, register as extension function
    if (func.receiver_type) |receiver| {
        const key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ receiver, func.name });
        try self.allocatedStrings.append(self.allocator, key);

        // Build argTypes including receiver as first argument
        const argTypes = try self.allocator.alloc([]const u8, func.args.len + 1);
        try self.allocatedSliceLists.append(self.allocator, argTypes);
        argTypes[0] = receiver; // receiver type as first arg
        for (func.args, 0..) |arg, i| {
            argTypes[i + 1] = if (arg.type) |t| t.typeName() else "unknown";
        }

        const external = func.modifiers.external != null;
        const mangledName = if (external)
            func.name
        else blk: {
            const mname = try computeMangledName(self.allocator, key, argTypes[1..]);
            try self.allocatedStrings.append(self.allocator, mname);
            break :blk mname;
        };

        const retType = if (func.ret) |r| try self.resolveTypeAnnotationFull(r) else Symbol.ZSTypeNotation.unknown;

        const gop = try self.extensionFns.getOrPut(key);
        if (!gop.found_existing) {
            gop.value_ptr.* = try std.ArrayList(OverloadEntry).initCapacity(self.allocator, 2);
        }
        try gop.value_ptr.append(self.allocator, .{
            .argTypes = argTypes[1..],
            .mangledName = mangledName,
            .retType = retType,
            .external = external,
        });
        return;
    }

    const argTypes = try self.allocator.alloc([]const u8, func.args.len);
    try self.allocatedSliceLists.append(self.allocator, argTypes);
    for (func.args, 0..) |arg, i| {
        argTypes[i] = if (arg.type) |t| t.typeName() else "unknown";
    }

    const external = func.modifiers.external != null;
    const mangledName = if (external)
        func.name
    else blk: {
        const name = try computeMangledName(self.allocator, func.name, argTypes);
        try self.allocatedStrings.append(self.allocator, name);
        break :blk name;
    };

    const retType = if (func.ret) |r| try self.resolveTypeAnnotationFull(r) else Symbol.ZSTypeNotation.unknown;

    // Check for duplicate signatures
    if (self.overloads.getPtr(func.name)) |entries| {
        for (entries.items) |entry| {
            if (entry.argTypes.len == argTypes.len) {
                var allMatch = true;
                for (entry.argTypes, argTypes) |a, b| {
                    if (!std.mem.eql(u8, a, b)) {
                        allMatch = false;
                        break;
                    }
                }
                if (allMatch) {
                    const nameStart = self.safeSourceOffset(func.name.ptr);
                    try self.recordErrorAt(nameStart, nameStart + func.name.len, "Duplicate function signature");
                    return;
                }
            }
        }
        try entries.append(self.allocator, .{
            .argTypes = argTypes,
            .mangledName = mangledName,
            .retType = retType,
            .external = external,
        });
    } else {
        var entries = try std.ArrayList(OverloadEntry).initCapacity(self.allocator, 2);
        try entries.append(self.allocator, .{
            .argTypes = argTypes,
            .mangledName = mangledName,
            .retType = retType,
            .external = external,
        });
        try self.overloads.put(func.name, entries);
    }
}

pub fn registerScalars(self: anytype, module: zsm.ZSModule) Error!void {
    for (module.ast) |node| {
        switch (node) {
            .stmt => {
                switch (node.stmt) {
                    .scalar_decl => |sd| {
                        var found = false;
                        inline for (type_resolver.builtinScalars) |entry| {
                            if (std.mem.eql(u8, sd.name, entry[0])) {
                                try self.scalarDefs.put(sd.name, entry[1]);
                                found = true;
                            }
                        }
                        if (!found) {
                            try self.recordErrorAt(sd.startPos, sd.startPos + sd.name.len, "Unknown scalar type");
                        }
                    },
                    else => {},
                }
            },
            else => {},
        }
    }
}

pub fn registerStructs(self: anytype, module: zsm.ZSModule) Error!void {
    for (module.ast) |node| {
        switch (node) {
            .stmt => {
                switch (node.stmt) {
                    .struct_decl => |sd| {
                        const def = StructDef{
                            .name = sd.name,
                            .type_params = sd.type_params,
                            .fields = sd.fields,
                        };
                        try self.structDefs.put(sd.name, def);
                        if (sd.modifiers.exported != null) {
                            try self.exportedStructDefs.put(sd.name, def);
                        }
                    },
                    else => {},
                }
            },
            .import_decl, .export_from, .expr, .use_decl, .when_decl, .target_decl => {},
        }
    }
}

pub fn registerEnums(self: anytype, module: zsm.ZSModule) Error!void {
    for (module.ast) |node| {
        switch (node) {
            .stmt => {
                switch (node.stmt) {
                    .enum_decl => |ed| {
                        const def = EnumDef{
                            .name = ed.name,
                            .type_params = ed.type_params,
                            .variants = ed.variants,
                        };
                        try self.enumDefs.put(ed.name, def);
                        if (ed.modifiers.exported != null) {
                            try self.exportedEnumDefs.put(ed.name, def);
                        }
                    },
                    else => {},
                }
            },
            .import_decl, .export_from, .expr, .use_decl, .when_decl, .target_decl => {},
        }
    }
}
