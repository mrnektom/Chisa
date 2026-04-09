const std = @import("std");
const Analyzer = @import("analyzer/analyzer.zig");
const Symbol = @import("analyzer/symbol.zig");
const Sig = @import("analyzer/symbol_signature.zig");
const ast = @import("ast/ast_node.zig");

// ─── Type formatters (AST notation → string) ────────────────────────────────

fn formatAstType(arena: std.mem.Allocator, t: ast.type_notation.ZSTypeNotation) []const u8 {
    return switch (t) {
        .reference => |ref| ref,
        .array => |a| formatAstTypeInner(arena, a.element_type.*),
        .generic => |g| formatGeneric(arena, g),
        .fn_type => |f| formatFnType(arena, f),
    };
}

fn formatAstTypeInner(arena: std.mem.Allocator, t: ast.type_notation.ZSTypeNotation) []const u8 {
    return switch (t) {
        .reference => |ref| ref,
        .array => |a| blk: {
            const elem = formatAstTypeInner(arena, a.element_type.*);
            break :blk std.fmt.allocPrint(arena, "{s}[]", .{elem}) catch elem;
        },
        .generic => |g| formatGeneric(arena, g),
        .fn_type => |f| formatFnType(arena, f),
    };
}

fn formatGeneric(arena: std.mem.Allocator, g: ast.type_notation.ZSGenericType) []const u8 {
    if (g.type_args.len == 0) return g.name;
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(arena);
    for (g.type_args) |arg| {
        parts.append(arena, formatAstTypeInner(arena, arg)) catch {};
    }
    const joined = std.mem.join(arena, ", ", parts.items) catch return g.name;
    return std.fmt.allocPrint(arena, "{s}<{s}>", .{ g.name, joined }) catch g.name;
}

fn formatFnType(arena: std.mem.Allocator, f: ast.type_notation.ZSFnType) []const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(arena);
    for (f.param_types) |p| {
        parts.append(arena, formatAstTypeInner(arena, p)) catch {};
    }
    const params = std.mem.join(arena, ", ", parts.items) catch return "function";
    const ret = formatAstTypeInner(arena, f.return_type.*);
    return std.fmt.allocPrint(arena, "({s}) -> {s}", .{ params, ret }) catch "function";
}

fn formatSigType(arena: std.mem.Allocator, t: Sig.ZSType) []const u8 {
    return switch (t) {
        .number => "number",
        .boolean => "boolean",
        .char => "char",
        .long => "long",
        .short => "short",
        .byte => "byte",
        .void => "void",
        .unknown => "unknown",
        .function => "function",
        .struct_type => |st| st.name,
        .enum_type => |et| et.name,
        .pointer => "pointer",
        .array_type => |a| blk: {
            const elem = formatSigType(arena, a.element_type.*);
            break :blk std.fmt.allocPrint(arena, "{s}[]", .{elem}) catch elem;
        },
    };
}

fn extractReceiverType(name: []const u8) []const u8 {
    const underscorePos = std.mem.indexOfScalar(u8, name, '_') orelse return name;
    return name[0..underscorePos];
}

// ─── Pretty JSON writer ─────────────────────────────────────────────────────

const P = struct {
    fn indent(buf: *std.ArrayList(u8), a: std.mem.Allocator, depth: usize) !void {
        var i: usize = 0;
        while (i < depth * 4) : (i += 1) {
            try buf.append(a, ' ');
        }
    }

    fn str(buf: *std.ArrayList(u8), a: std.mem.Allocator, s: []const u8) !void {
        var aw = std.Io.Writer.Allocating.init(a);
        defer aw.deinit();
        try std.json.Stringify.encodeJsonString(s, .{}, &aw.writer);
        try buf.appendSlice(a, try aw.toOwnedSlice());
    }
};

// ─── Detailed type writer ───────────────────────────────────────────────────

fn writeDetailedType(buf: *std.ArrayList(u8), a: std.mem.Allocator, t: Sig.ZSType, depth: usize) !void {
    switch (t) {
        .number => try buf.appendSlice(a, "\"number\""),
        .boolean => try buf.appendSlice(a, "\"boolean\""),
        .char => try buf.appendSlice(a, "\"char\""),
        .long => try buf.appendSlice(a, "\"long\""),
        .short => try buf.appendSlice(a, "\"short\""),
        .byte => try buf.appendSlice(a, "\"byte\""),
        .void => try buf.appendSlice(a, "\"void\""),
        .unknown => try buf.appendSlice(a, "\"unknown\""),
        .function => |f| {
            try buf.appendSlice(a, "{");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"kind\": \"function\"");
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"return_type\": ");
            try writeDetailedType(buf, a, f.ret.*, depth + 1);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"params\": [");
            for (f.args, 0..) |arg, i| {
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 2);
                try buf.appendSlice(a, "{");
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 3);
                try buf.appendSlice(a, "\"name\": ");
                try P.str(buf, a, arg.name);
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 3);
                try buf.appendSlice(a, "\"type\": ");
                try writeDetailedType(buf, a, arg.type, depth + 3);
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 2);
                try buf.append(a, '}');
                if (i < f.args.len - 1) try buf.append(a, ',');
            }
            if (f.args.len > 0) {
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 1);
            }
            try buf.appendSlice(a, "]");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth);
            try buf.append(a, '}');
        },
        .struct_type => |st| {
            try buf.appendSlice(a, "{");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"kind\": \"struct\"");
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"name\": ");
            try P.str(buf, a, st.name);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"fields\": [");
            for (st.fields, 0..) |field, i| {
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 2);
                try buf.appendSlice(a, "{");
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 3);
                try buf.appendSlice(a, "\"name\": ");
                try P.str(buf, a, field.name);
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 3);
                try buf.appendSlice(a, "\"type\": ");
                try writeDetailedType(buf, a, field.type, depth + 3);
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 2);
                try buf.append(a, '}');
                if (i < st.fields.len - 1) try buf.append(a, ',');
            }
            if (st.fields.len > 0) {
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 1);
            }
            try buf.appendSlice(a, "]");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth);
            try buf.append(a, '}');
        },
        .enum_type => |et| {
            try buf.appendSlice(a, "{");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"kind\": \"enum\"");
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"name\": ");
            try P.str(buf, a, et.name);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"variants\": [");
            for (et.variants, 0..) |v, i| {
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 2);
                try buf.appendSlice(a, "{");
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 3);
                try buf.appendSlice(a, "\"name\": ");
                try P.str(buf, a, v.name);
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 3);
                try buf.appendSlice(a, "\"payload_type\": ");
                if (v.payload_type) |pt| {
                    try writeDetailedType(buf, a, pt, depth + 3);
                } else {
                    try buf.appendSlice(a, "null");
                }
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 2);
                try buf.append(a, '}');
                if (i < et.variants.len - 1) try buf.append(a, ',');
            }
            if (et.variants.len > 0) {
                try buf.append(a, '\n');
                try P.indent(buf, a, depth + 1);
            }
            try buf.appendSlice(a, "]");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth);
            try buf.append(a, '}');
        },
        .pointer => |ptr| {
            try buf.appendSlice(a, "{");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"kind\": \"pointer\"");
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"target\": ");
            try writeDetailedType(buf, a, ptr.*, depth + 1);
            try buf.append(a, '\n');
            try P.indent(buf, a, depth);
            try buf.append(a, '}');
        },
        .array_type => |arr| {
            try buf.appendSlice(a, "{");
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"kind\": \"array\"");
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"element\": ");
            try writeDetailedType(buf, a, arr.element_type.*, depth + 1);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try P.indent(buf, a, depth + 1);
            try buf.appendSlice(a, "\"size\": ");
            var n = arr.size;
            if (n == 0) {
                try buf.append(a, '0');
            } else {
                var digits: [20]u8 = undefined;
                var i: usize = 0;
                while (n > 0) : ({
                    n /= 10;
                    i += 1;
                }) {
                    digits[i] = @as(u8, @intCast(n % 10)) + '0';
                }
                var j: usize = i;
                while (j > 0) : (j -= 1) {
                    try buf.append(a, digits[j - 1]);
                }
            }
            try buf.append(a, '\n');
            try P.indent(buf, a, depth);
            try buf.append(a, '}');
        },
    }
}

// ─── Main dump function ─────────────────────────────────────────────────────

pub fn dump(allocator: std.mem.Allocator, result: Analyzer.AnalyzeResult) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(a);

    try buf.appendSlice(a, "{");
    try buf.append(a, '\n');
    try buf.appendSlice(a, "    \"symbols\": [");

    var first = true;

    var genericFnNames = std.StringHashMap(void).init(a);
    {
        var it = result.genericFns.iterator();
        while (it.next()) |entry| {
            try genericFnNames.put(entry.key_ptr.*, {});
        }
    }

    // ─── Struct definitions ───
    var structDefIter = result.structDefs.iterator();
    while (structDefIter.next()) |entry| {
        const sd = entry.value_ptr.*;
        if (!first) {
            try buf.append(a, ',');
        }
        first = false;
        try buf.append(a, '\n');
        try buf.appendSlice(a, "        {");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"kind\": \"struct\",");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"name\": ");
        try P.str(&buf, a, sd.name);
        try buf.append(a, ',');
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"type_params\": [");
        for (sd.type_params, 0..) |tp, i| {
            if (i > 0) try buf.append(a, ',');
            try P.str(&buf, a, tp);
        }
        try buf.append(a, ']');
        try buf.append(a, ',');
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"fields\": [");
        for (sd.fields, 0..) |field, i| {
            if (i > 0) try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                {");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                    \"name\": ");
            try P.str(&buf, a, field.name);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                    \"type\": ");
            try P.str(&buf, a, formatAstType(a, field.type));
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                }");
        }
        if (sd.fields.len > 0) {
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            ");
        }
        try buf.appendSlice(a, "]");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "        }");
    }

    // ─── Enum definitions ───
    var enumDefIter = result.enumDefs.iterator();
    while (enumDefIter.next()) |entry| {
        const ed = entry.value_ptr.*;
        if (!first) {
            try buf.append(a, ',');
        }
        first = false;
        try buf.append(a, '\n');
        try buf.appendSlice(a, "        {");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"kind\": \"enum\",");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"name\": ");
        try P.str(&buf, a, ed.name);
        try buf.append(a, ',');
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"type_params\": [");
        for (ed.type_params, 0..) |tp, i| {
            if (i > 0) try buf.append(a, ',');
            try P.str(&buf, a, tp);
        }
        try buf.append(a, ']');
        try buf.append(a, ',');
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"variants\": [");
        for (ed.variants, 0..) |v, i| {
            if (i > 0) try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                {");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                    \"name\": ");
            try P.str(&buf, a, v.name);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                    \"payload_type\": ");
            if (v.payload_type) |pt| {
                try P.str(&buf, a, formatAstType(a, pt));
            } else {
                try buf.appendSlice(a, "null");
            }
            try buf.append(a, '\n');
            try buf.appendSlice(a, "                }");
        }
        if (ed.variants.len > 0) {
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            ");
        }
        try buf.appendSlice(a, "]");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "        }");
    }

    // ─── moduleScope symbols ───
    var scopeIter = result.moduleScope.iterator();
    while (scopeIter.next()) |entry| {
        const sym = entry.value_ptr.*;

        if (genericFnNames.contains(sym.name)) {
            if (result.genericFns.get(sym.name)) |gfn| {
                if (!first) try buf.append(a, ',');
                first = false;
                try buf.append(a, '\n');
                try buf.appendSlice(a, "        {");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"kind\": \"function\",");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"name\": ");
                try P.str(&buf, a, gfn.func.name);
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"type_params\": [");
                for (gfn.func.type_params, 0..) |tp, i| {
                    if (i > 0) try buf.append(a, ',');
                    try P.str(&buf, a, tp);
                }
                try buf.appendSlice(a, "],");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"params\": [");
                for (gfn.func.args, 0..) |arg, j| {
                    if (j > 0) try buf.append(a, ',');
                    try buf.append(a, '\n');
                    try buf.appendSlice(a, "                {");
                    try buf.append(a, '\n');
                    try buf.appendSlice(a, "                    \"name\": ");
                    try P.str(&buf, a, arg.name);
                    try buf.append(a, ',');
                    try buf.append(a, '\n');
                    try buf.appendSlice(a, "                    \"type\": ");
                    try P.str(&buf, a, if (arg.type) |t| formatAstType(a, t) else "unknown");
                    try buf.append(a, '\n');
                    try buf.appendSlice(a, "                }");
                }
                if (gfn.func.args.len > 0) {
                    try buf.append(a, '\n');
                    try buf.appendSlice(a, "            ");
                }
                try buf.appendSlice(a, "],");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"return_type\": ");
                try P.str(&buf, a, if (gfn.func.ret) |r| formatAstType(a, r) else "void");
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"external\": ");
                if (gfn.func.modifiers.external != null) {
                    try buf.appendSlice(a, "true");
                } else {
                    try buf.appendSlice(a, "false");
                }
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            \"exported\": ");
                if (gfn.func.modifiers.exported != null) {
                    try buf.appendSlice(a, "true");
                } else {
                    try buf.appendSlice(a, "false");
                }
                try buf.append(a, '\n');
                try buf.appendSlice(a, "        }");
            }
        } else if (sym.signature == .function) {
            const fnInfo = sym.signature.function;
            if (!first) try buf.append(a, ',');
            first = false;
            try buf.append(a, '\n');
            try buf.appendSlice(a, "        {");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"kind\": \"function\",");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"name\": ");
            try P.str(&buf, a, sym.name);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"type_params\": [],");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"params\": [");
            for (fnInfo.args, 0..) |arg, i| {
                if (i > 0) try buf.append(a, ',');
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                {");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                    \"name\": ");
                try P.str(&buf, a, arg.name);
                try buf.append(a, ',');
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                    \"type\": ");
                try P.str(&buf, a, formatSigType(a, arg.type));
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                }");
            }
            if (fnInfo.args.len > 0) {
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            ");
            }
            try buf.appendSlice(a, "],");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"return_type\": ");
            try P.str(&buf, a, formatSigType(a, fnInfo.ret.*));
            const isExternal = blk: {
                if (result.overloads.get(sym.name)) |overloads| {
                    if (overloads.items.len > 0) break :blk overloads.items[0].external;
                }
                break :blk false;
            };
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"external\": ");
            if (isExternal) {
                try buf.appendSlice(a, "true");
            } else {
                try buf.appendSlice(a, "false");
            }
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"exported\": ");
            if (result.exports.contains(sym.name)) {
                try buf.appendSlice(a, "true");
            } else {
                try buf.appendSlice(a, "false");
            }
            try buf.append(a, '\n');
            try buf.appendSlice(a, "        }");
        } else {
            if (!first) try buf.append(a, ',');
            first = false;
            try buf.append(a, '\n');
            try buf.appendSlice(a, "        {");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"kind\": \"variable\",");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"name\": ");
            try P.str(&buf, a, sym.name);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"type\": ");
            try writeDetailedType(&buf, a, sym.signature, 3);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"assignable\": ");
            if (sym.assignable) {
                try buf.appendSlice(a, "true");
            } else {
                try buf.appendSlice(a, "false");
            }
            try buf.append(a, '\n');
            try buf.appendSlice(a, "        }");
        }
    }

    // ─── Type aliases ───
    var aliasIter = result.typeAliases.iterator();
    while (aliasIter.next()) |entry| {
        const aliasName = entry.key_ptr.*;
        const aliasDef = entry.value_ptr.*;
        if (!first) try buf.append(a, ',');
        first = false;
        try buf.append(a, '\n');
        try buf.appendSlice(a, "        {");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"kind\": \"type_alias\",");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"name\": ");
        try P.str(&buf, a, aliasName);
        try buf.append(a, ',');
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"type_params\": [");
        for (aliasDef.type_params, 0..) |tp, i| {
            if (i > 0) try buf.append(a, ',');
            try P.str(&buf, a, tp);
        }
        try buf.appendSlice(a, "],");
        try buf.append(a, '\n');
        try buf.appendSlice(a, "            \"aliased_type\": ");
        try P.str(&buf, a, formatAstType(a, aliasDef.aliased_type));
        try buf.append(a, '\n');
        try buf.appendSlice(a, "        }");
    }

    // ─── Extension functions ───
    var extFnIter = result.extensionFns.iterator();
    while (extFnIter.next()) |entry| {
        const mangledName = entry.key_ptr.*;
        const overloads = entry.value_ptr.*;
        if (overloads.items.len > 0) {
            const ov = overloads.items[0];
            if (!first) try buf.append(a, ',');
            first = false;
            const receiverType = extractReceiverType(mangledName);
            var methodDisplayName = mangledName;
            if (std.mem.indexOfScalar(u8, mangledName, '_')) |pos| {
                methodDisplayName = mangledName[pos + 1 ..];
            }
            try buf.append(a, '\n');
            try buf.appendSlice(a, "        {");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"kind\": \"extension_fn\",");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"receiver_type\": ");
            try P.str(&buf, a, receiverType);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"name\": ");
            try P.str(&buf, a, methodDisplayName);
            try buf.append(a, ',');
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"params\": [");
            for (ov.argTypes, 0..) |argType, i| {
                if (i > 0) try buf.append(a, ',');
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                {");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                    \"name\": \"this\",");
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                    \"type\": ");
                try P.str(&buf, a, argType);
                try buf.append(a, '\n');
                try buf.appendSlice(a, "                }");
            }
            if (ov.argTypes.len > 0) {
                try buf.append(a, '\n');
                try buf.appendSlice(a, "            ");
            }
            try buf.appendSlice(a, "],");
            try buf.append(a, '\n');
            try buf.appendSlice(a, "            \"return_type\": ");
            try P.str(&buf, a, formatSigType(a, ov.retType));
            try buf.append(a, '\n');
            try buf.appendSlice(a, "        }");
        }
    }

    try buf.append(a, '\n');
    try buf.appendSlice(a, "    ]");
    try buf.append(a, '\n');
    try buf.appendSlice(a, "}\n");

    const stdout = std.fs.File.stdout();
    try stdout.writeAll(buf.items);
}
