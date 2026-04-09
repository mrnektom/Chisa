const std = @import("std");
const testing = std.testing;
const Pipeline = @import("pipeline.zig");
const Args = @import("args/args.zig");

fn compileFile(path: []const u8) !void {
    var p = try Pipeline.init(testing.allocator);
    defer p.deinit();
    try p.compile(.{
        .entryPoint = path,
        .dumpIr = false,
        .outputPath = null,
        .run = false,
        .debug = false,
    });
}

fn expectCompileError(path: []const u8) !void {
    compileFile(path) catch return;
    return error.ExpectedCompileFailure;
}

// ── Positive tests ────────────────────────────────────────────────────────────

test "variables: let const and type inference" {
    try compileFile("tests/fixtures/variables_basic.chisa");
}

test "variables: reassignment of let" {
    try compileFile("tests/fixtures/variables_reassignment.chisa");
}

test "functions: basic declaration and call" {
    try compileFile("tests/fixtures/functions_basic.chisa");
}

test "functions: overloading" {
    try compileFile("tests/fixtures/functions_overload.chisa");
}

test "functions: generic" {
    try compileFile("tests/fixtures/functions_generic.chisa");
}

test "functions: external declaration" {
    try compileFile("tests/fixtures/functions_external.chisa");
}

test "functions: export" {
    try compileFile("tests/fixtures/functions_export.chisa");
}

test "structs: basic definition init and field access" {
    try compileFile("tests/fixtures/structs_basic.chisa");
}

test "structs: generic" {
    try compileFile("tests/fixtures/structs_generic.chisa");
}

test "structs: nested field chaining" {
    try compileFile("tests/fixtures/structs_nested.chisa");
}

test "enums: basic variants and match" {
    try compileFile("tests/fixtures/enums_basic.chisa");
}

test "enums: payload variant" {
    try compileFile("tests/fixtures/enums_payload.chisa");
}

test "enums: generic" {
    try compileFile("tests/fixtures/enums_generic.chisa");
}

test "enums: nested generic payload inference" {
    try compileFile("tests/fixtures/enums_generic_nested.chisa");
}

test "extensions: scalar receiver" {
    try compileFile("tests/fixtures/extensions_scalars.chisa");
}

test "extensions: struct receiver" {
    try compileFile("tests/fixtures/extensions_struct.chisa");
}

test "extensions: generic receiver" {
    try compileFile("tests/fixtures/extensions_generic.chisa");
}

test "match: number literal arms" {
    try compileFile("tests/fixtures/match_primitives.chisa");
}

test "match: enum payload binding" {
    try compileFile("tests/fixtures/match_enums.chisa");
}

test "match: struct field patterns" {
    try compileFile("tests/fixtures/match_structs.chisa");
}

test "match: wildcard else arm" {
    try compileFile("tests/fixtures/match_wildcard.chisa");
}

test "control flow: if expression and statement" {
    try compileFile("tests/fixtures/if_expr.chisa");
}

test "control flow: while loop" {
    try compileFile("tests/fixtures/while_loop.chisa");
}

test "control flow: for loop" {
    try compileFile("tests/fixtures/for_loop.chisa");
}

test "control flow: break and continue" {
    try compileFile("tests/fixtures/break_continue.chisa");
}

test "control flow: return statement" {
    try compileFile("tests/fixtures/return_stmt.chisa");
}

test "operators: arithmetic" {
    try compileFile("tests/fixtures/operators_arithmetic.chisa");
}

test "operators: comparison" {
    try compileFile("tests/fixtures/operators_comparison.chisa");
}

test "operators: logical" {
    try compileFile("tests/fixtures/operators_logical.chisa");
}

test "arrays: literal index and write" {
    try compileFile("tests/fixtures/arrays_basic.chisa");
}

test "lambdas: basic declaration" {
    try compileFile("tests/fixtures/lambdas_basic.chisa");
}

test "generics: combined fn struct enum" {
    try compileFile("tests/fixtures/generics_combined.chisa");
}

test "when: conditional compilation inside function" {
    try compileFile("tests/fixtures/when_compilation.chisa");
}

test "target directive: file-level @target" {
    try compileFile("tests/fixtures/target_directive.chisa");
}

test "assembly: asm block inside function" {
    try compileFile("tests/fixtures/assembly_basic.chisa");
}

test "pointers: ptr and deref" {
    try compileFile("tests/fixtures/pointers_basic.chisa");
}

test "scalars: scalar types as annotations" {
    try compileFile("tests/fixtures/scalars_decl.chisa");
}

test "type alias: basic declaration" {
    try compileFile("tests/fixtures/type_alias.chisa");
}

test "imports: import from another file" {
    try compileFile("tests/fixtures/imports_basic.chisa");
}

// ── Unimplemented feature tests (skipped) ────────────────────────────────────

test "extensions: call chain on scalar (double then addOne)" {
    try compileFile("tests/fixtures/extensions_call_chain.chisa");
}

test "lambdas: block body with local variable" {
    try compileFile("tests/fixtures/lambdas_block_body.chisa");
}

test "lambdas: explicit type annotation on parameter" {
    try compileFile("tests/fixtures/lambdas_typed.chisa");
}

test "lambdas: invoke stored lambda" {
    try compileFile("tests/fixtures/lambdas_invoke.chisa");
}

test "lambdas: implicit single parameter uses it" {
    try compileFile("tests/fixtures/lambdas_implicit_it.chisa");
}

test "lambdas: implicit zero-arg body omits arrow" {
    try compileFile("tests/fixtures/lambdas_implicit_empty.chisa");
}

test "closures: capture and mutate outer variable" {
    try compileFile("tests/fixtures/closures_basic.chisa");
}

test "higher-order functions: pass lambda as argument" {
    try compileFile("tests/fixtures/hof.chisa");
}

test "trailing lambda: call with trailing lambda syntax" {
    try compileFile("tests/fixtures/trailing_lambda.chisa");
}

test "inference: generic function call with lambda" {
    try compileFile("tests/fixtures/infer_generic_lambda_call.chisa");
}

test "inference: generic extension chain with lambda" {
    try compileFile("tests/fixtures/infer_extension_chain.chisa");
}

test "inference: direct generic extension chain preserves downstream context" {
    try compileFile("tests/fixtures/infer_extension_chain_direct.chisa");
}

test "inference: generic lambda return follows expected result type" {
    try compileFile("tests/fixtures/infer_generic_expected_lambda_return.chisa");
}

test "inference: nested generic extension result preserves inner type args" {
    try compileFile("tests/fixtures/infer_nested_generic_extension.chisa");
}

test "inference: expected type drives generic enum construction" {
    try compileFile("tests/fixtures/infer_expected_generic_enum.chisa");
}

test "safe navigation: optional chaining with ?." {
    try compileFile("tests/fixtures/safe_navigation.chisa");
}

test "error propagation: !! operator on Either" {
    try compileFile("tests/fixtures/error_propagation.chisa");
}

test "when: top-level when block defining platform function" {
    try compileFile("tests/fixtures/when_toplevel.chisa");
}

test "comptime: runtime block inside comptime" {
    return error.SkipZigTest; // comptime/runtime blocks not yet implemented
}

// ── Negative tests ────────────────────────────────────────────────────────────

test "errors: undefined variable" {
    try expectCompileError("tests/fixtures/errors/undefined_var.chisa");
}

test "errors: undefined function" {
    try expectCompileError("tests/fixtures/errors/undefined_fn.chisa");
}

test "errors: type mismatch" {
    try expectCompileError("tests/fixtures/errors/type_mismatch.chisa");
}

test "errors: reassign const" {
    try expectCompileError("tests/fixtures/errors/reassign_const.chisa");
}

test "errors: unknown expression type" {
    try expectCompileError("tests/fixtures/errors/unknown_expr_type.chisa");
}

test "errors: block expression syntax is reserved for lambdas" {
    try expectCompileError("tests/fixtures/errors/block_expr_removed.chisa");
}
