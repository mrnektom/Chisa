# Repository Guidelines

## Workflow Note
Read `SPECIFICATION.md` before starting any compiler or IntelliJ plugin work. Treat it as the source of truth for language behavior, then implement changes in `src/`, `stdlib/`, tests, or `intellij-plugin/` to match the spec.
Explore the relevant code before making non-trivial changes, and do not guess at intended behavior around language semantics, type-system rules, or error handling when the requirement is ambiguous. Ask the user to clarify any non-obvious or ambiguous requirements before implementing them.
If you hit a compiler bug that blocks code which should work according to `SPECIFICATION.md`, fix the compiler bug first, then continue the original implementation from the point where it was blocked.

## Project Overview
ZenScript is a compiler for a custom programming language, written in Zig. It compiles source files through a multi-stage pipeline targeting LLVM. The project also includes Node.js bindings via napi.

## Project Structure & Module Organization
The compiler lives in `src/` and is split by stage: `tokens/`, `ast/`, `analyzer/`, `ir/`, `codegen/`, `daemon/`, and `helpers/`. Entry points are `src/main.zig` for the CLI, `src/root.zig` for the main module, and `src/nodemodule.zig` for the Node addon. Standard library sources are in `stdlib/`. Language examples live in `examples/`. Regression coverage is split between Zig tests in `src/` and language fixtures under `tests/fixtures/` and `tests/e2e/`. The IntelliJ plugin is isolated in `intellij-plugin/` with Kotlin sources in `src/main/kotlin` and plugin tests in `src/test/kotlin`.

## Compiler Architecture
The main compilation pipeline is orchestrated by `src/pipeline.zig` and flows through tokenizer, parser, analyzer, IR generation, and LLVM code generation.

- Tokenizer: `src/tokens/tokenizer.zig` lexes source into `ZSToken`s from `src/tokens/zs_token.zig`.
- Parser: `src/parser.zig` performs recursive-descent parsing and produces the AST.
- Analyzer: `src/analyzer/analyzer.zig` builds scoped symbols, infers types, and reports semantic errors.
- IR generator: `src/ir/ir_gen.zig` lowers AST nodes into `ZSIR`.
- LLVM codegen: `src/codegen/llvm_codegen.zig` handles backend generation.

Key supporting modules:

- AST definitions live in `src/ast/`.
- Symbol table logic lives in `src/analyzer/symbol_table_stack.zig`.
- Symbol signatures live in `src/analyzer/symbol_signature.zig`.
- Error reporting lives in `src/analyzer/analyze_error.zig` and `src/helpers/source_helpers.zig`.
- CLI argument parsing lives in `src/args/args.zig`.

## Build, Test, and Development Commands
Use Zig 0.15.2 or newer.

- `zig build`: build the CLI, daemon, Node addon, and install `stdlib/`.
- `zig build run -- -i examples/string_test.chisa`: compile a sample source file.
- `zig build run -- -i examples/string_test.chisa -r`: compile and execute the result.
- `zig build test`: run Zig unit and integration tests declared in the build graph.
- `npm run build`: build the Node.js addon.
- `npm test`: test the Node.js addon.
- `bash tests/e2e/run_tests.sh`: run end-to-end `.zs` compiler checks.
- `cd intellij-plugin && ./gradlew test`: run IntelliJ plugin tests.

## Coding Style & Naming Conventions
Follow Zig defaults: 4-space indentation, `camelCase` for locals/functions, and `PascalCase` for types. Keep module names descriptive and aligned with the existing pipeline split, for example `expr_analyzer.zig` or `llvm_codegen.zig`. Run `zig fmt src build.zig` before submitting Zig changes. In the plugin, follow Kotlin conventions already in use: `PascalCase` class names, `camelCase` methods, and one top-level type per file when practical.
Public compiler types generally use a `ZS` prefix, for example `ZSModule`, `ZSAstNode`, `ZSToken`, and `ZSIR`. File names should remain in snake_case, and modules should keep clear ownership within the pipeline.

## Testing Guidelines
Add or update tests with every behavior change. Prefer focused Zig `test` blocks near the affected code for parser/analyzer logic. Put language-level fixture coverage in `tests/fixtures/*.chisa` and executable scenarios in `tests/e2e/*.zs`. IntelliJ plugin tests should extend `BasePlatformTestCase` and use names like `testImportResolve`.

## Current State
Tokenizer, parser, analyzer, and IR generation are functional. LLVM codegen exists but may be incomplete in some areas, so verify backend behavior against the current implementation before depending on it.

## Commit & Pull Request Guidelines
Recent history uses short imperative summaries such as `Delete unnecessary files` and `Some refactor`; keep commits brief, imperative, and scoped to one change. For pull requests, include the affected area (`compiler`, `daemon`, `stdlib`, or `intellij-plugin`), a short behavior summary, commands you ran, and screenshots only for editor UI changes.
