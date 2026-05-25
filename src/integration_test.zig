const std = @import("std");
const testing = std.testing;
const Pipeline = @import("pipeline.zig");
const Args = @import("args/args.zig");

fn compileFile(path: []const u8) !void {
    var p = try Pipeline.init(testing.allocator, testing.io);
    defer p.deinit();
    try p.compile(.{
        .entryPoint = path,
        .dumpIr = false,
        .outputPath = null,
        .run = false,
        .debug = false,
    });
}

fn compileFileToNative(path: []const u8) !void {
    const output_path = "/tmp/chisa_codegen_test_output";

    var p = try Pipeline.init(testing.allocator, testing.io);
    defer p.deinit();
    try p.compile(.{
        .entryPoint = path,
        .dumpIr = false,
        .outputPath = output_path,
        .run = false,
        .debug = false,
    });
}

fn compileRunExpectStdout(path: []const u8, expected_stdout: []const u8) !void {
    const output_path = "/tmp/chisa_codegen_runtime_test_output";

    var p = try Pipeline.init(testing.allocator, testing.io);
    defer p.deinit();
    try p.compile(.{
        .entryPoint = path,
        .dumpIr = false,
        .outputPath = output_path,
        .run = false,
        .debug = false,
    });

    const result = try std.process.run(testing.allocator, testing.io, .{
        .argv = &.{output_path},
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| try testing.expectEqual(@as(u8, 0), code),
        else => return error.UnexpectedRuntimeTermination,
    }
    try testing.expectEqualStrings(expected_stdout, result.stdout);
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

test "match: grouped literal arms" {
    try compileFile("tests/fixtures/match_literal_list.chisa");
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

test "match: literal pattern type must match subject" {
    try expectCompileError("tests/fixtures/errors/match_literal_subject_mismatch.chisa");
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

test "casts: primitive as coercions compile to native" {
    try compileFileToNative("tests/fixtures/primitives_as_cast.chisa");
}

test "casts: integer and pointer coercions compile to native" {
    try compileFileToNative("tests/fixtures/pointer_as_cast.chisa");
}

test "type alias: basic declaration" {
    try compileFile("tests/fixtures/type_alias.chisa");
}

test "imports: import from another file" {
    try compileFile("tests/fixtures/imports_basic.chisa");
}

test "comments: line block and doc comments are ignored" {
    try compileFile("tests/fixtures/comments_basic.chisa");
}

test "imports: alias imported names" {
    try compileFile("tests/fixtures/imports_alias_basic.chisa");
}

test "exports: re-export from another module with alias" {
    try compileFile("tests/fixtures/reexport_chain_consumer.chisa");
}

test "stdlib: net module compiles" {
    try compileFile("tests/fixtures/net_basic.chisa");
}

test "match: payload binding keeps enum payload type" {
    try compileFile("tests/fixtures/either_match_payload_method.chisa");
}

test "match: imported payload enum keeps extension methods" {
    try compileFile("tests/fixtures/either_match_imported_payload_consumer.chisa");
}

test "codegen: Either<String> propagation compiles to native" {
    try compileFileToNative("tests/e2e/either_string_codegen.chisa");
}

test "codegen: Either<pointer> propagation compiles to native" {
    try compileFileToNative("tests/e2e/either_pointer_codegen.chisa");
}

test "codegen: Either<byte pointer> propagation compiles to native" {
    try compileFileToNative("tests/e2e/either_byte_pointer_codegen.chisa");
}

test "codegen: imported match payload keeps enum methods" {
    try compileFileToNative("tests/fixtures/either_match_imported_payload_consumer.chisa");
}

test "codegen: grouped literal arms compile to native" {
    try compileFileToNative("tests/fixtures/match_literal_list.chisa");
}

test "codegen: string literal match runs" {
    try compileRunExpectStdout("tests/e2e/match_string_runtime.chisa", "7\n");
}

test "codegen: struct destructure match runs" {
    try compileRunExpectStdout("tests/e2e/match_struct_runtime.chisa", "5\n");
}

test "codegen: enum payload struct survives runtime match" {
    try compileRunExpectStdout("tests/e2e/enum_struct_payload_runtime.chisa", "16\n");
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

test "function types: generic aliases in parameters" {
    try compileFile("tests/fixtures/function_types_alias_generic.chisa");
}

test "safe navigation: optional chaining with ?." {
    try compileFile("tests/fixtures/safe_navigation.chisa");
}

test "safe navigation: optional chaining with extension calls" {
    try compileFile("tests/fixtures/safe_navigation_extension.chisa");
}

test "error propagation: !! operator on Either" {
    try compileFile("tests/fixtures/error_propagation.chisa");
}

test "error propagation: !! operator via Option.toEither" {
    try compileFile("tests/fixtures/error_propagation_option.chisa");
}

test "when: top-level when block defining platform function" {
    try compileFile("tests/fixtures/when_toplevel.chisa");
}

test "when: top-level when block with multi-declaration arm" {
    try compileFile("tests/fixtures/when_toplevel_multidecl.chisa");
}

test "type alias: exported alias imported in another module" {
    try compileFile("tests/fixtures/type_alias_export_consumer.chisa");
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

test "errors: generic type mismatch" {
    try expectCompileError("tests/fixtures/errors/generic_type_mismatch.chisa");
}

test "errors: pointer type mismatch" {
    try expectCompileError("tests/fixtures/errors/pointer_type_mismatch.chisa");
}

test "errors: function type mismatch" {
    try expectCompileError("tests/fixtures/errors/function_type_mismatch.chisa");
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

test "errors: if expression without else in value position" {
    try expectCompileError("tests/fixtures/errors/if_without_else_value.chisa");
}

test "errors: as cast target must be primitive" {
    try expectCompileError("tests/fixtures/errors/as_cast_non_primitive.chisa");
}
