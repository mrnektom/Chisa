# ZenScript (chisa) — Project Context

## Project Overview

ZenScript (also referred to as **chisa**) is a custom programming language compiler written in **Zig**, targeting **LLVM** for native code generation. The language features modern syntax including generics, pattern matching, tagged unions, extension functions, lambdas with closures, safe navigation, error propagation, conditional compilation, and inline assembly.

### Key Language Features
- **Variables**: `let` (mutable), `const` (immutable)
- **Functions**: expression/block bodies, overloading, generic type parameters `<T>`, `external` declarations, `export` for cross-module visibility
- **Extension functions**: add methods to any existing type (`fn number.double(): number = this * 2`)
- **Lambdas & closures**: `{ x -> x * 2 }`, trailing lambda syntax, closure capture by reference
- **Functional types**: first-class function types `(T) -> R`, higher-order functions, `type` aliases
- **Safe navigation**: `?.` operator for `Option<T>` chaining
- **Error propagation**: `!!` operator with `Either<L, R>` support
- **Structs & enums**: generic support, tagged unions, pattern matching with `match`
- **Arrays**: fixed-size, stack-allocated, repeat syntax `[value; count]`
- **Pointers**: `ptr()`, `deref()`, `alloc()`, `free()`
- **Inline assembly**: `asm { }` blocks for low-level code
- **Conditional compilation**: `@target` and `when {}` for compile-time selection
- **Imports/exports**: named imports with aliasing, re-exports, circular import detection

### Compilation Pipeline

```
.chisa source → Tokenizer → Parser → Analyzer → IRGen → LLVMCodeGen → native executable
```

CLI modes:
- `-r` — JIT execution via MCJIT
- `-o <path>` — compile to native executable
- `-dump-ir` — dump LLVM IR to stdout

## Building and Running

**Requirements**: Zig >= 0.15.2

```bash
# Build everything (CLI, daemon, Node addon, stdlib)
zig build

# Compile a source file
zig build run -- -i <file.chisa>

# Compile and execute (JIT)
zig build run -- -i <file.chisa> -r

# Dump LLVM IR
zig build run -- -i <file.chisa> -dump-ir

# Compile to native executable
zig build run -- -i <file.chisa> -o <output>

# Run all Zig unit and integration tests
zig build test

# Run end-to-end compiler tests
bash tests/e2e/run_tests.sh

# Build the language server daemon
zig build daemon

# Run IntelliJ plugin tests
cd intellij-plugin && ./gradlew test
```

## Project Structure

```
src/
├── tokens/          — Lexer/tokenizer
├── ast/             — Abstract syntax tree definitions
├── analyzer/        — Semantic analysis & type checking
├── ir/              — Intermediate representation generation
├── codegen/         — LLVM code generation
├── helpers/         — Utility functions
├── daemon/          — Language server / daemon
├── runtime/         — Runtime support
├── args/            — CLI argument parsing
├── main.zig         — CLI entry point
├── root.zig         — Main module root
├── parser.zig       — Parser implementation
├── pipeline.zig     — Compiler pipeline orchestration
├── preprocessor.zig — Source preprocessor
├── daemon_api.zig   — Daemon API definitions
├── nodemodule.zig   — Node.js addon (N-API)
└── integration_test.zig

stdlib/              — Standard library (auto-imported prelude)
├── prelude.chisa    — Built-in scalar types & common declarations
├── Option.chisa     — Option<T> type + extensions
├── Either.chisa     — Either<L, R> type + extensions
├── String.chisa     — String type + extensions
├── Number.chisa     — Number extensions
├── Unit.chisa       — Unit singleton type
├── arraylist.chisa  — Dynamic array list
├── bufio.chisa      — Buffered I/O
├── fs.chisa         — File system utilities
└── mem.chisa        — Memory allocation utilities

tests/
├── fixtures/        — Language fixture tests (*.chisa)
└── e2e/             — End-to-end compiler tests (*.zs)

examples/            — Sample .chisa source files
intellij-plugin/     — IntelliJ IDEA plugin (Kotlin)
```

## Development Conventions

### Zig Code Style
- **4-space indentation**
- `camelCase` for locals and functions
- `PascalCase` for types
- Descriptive module names aligned with pipeline stages (e.g., `expr_analyzer.zig`, `llvm_codegen.zig`)
- Run `zig fmt src build.zig` before committing

### Kotlin (IntelliJ Plugin)
- `PascalCase` class names, `camelCase` methods
- One top-level type per file when practical

### Testing
- Add/update tests with every behavior change
- Focused Zig `test` blocks near affected code for parser/analyzer logic
- Language fixtures in `tests/fixtures/*.chisa`
- Executable scenarios in `tests/e2e/*.zs`
- IntelliJ plugin tests extend `BasePlatformTestCase` (e.g., `testImportResolve`)

### Commits
- Short imperative summaries (e.g., `Delete unnecessary files`, `Some refactor`)
- One change per commit
- For PRs: include affected area, behavior summary, commands run, and screenshots for editor UI changes

## Key References

- **`SPECIFICATION.md`** — Authoritative language specification. **Read before any compiler or plugin work.**
- **`AGENTS.md`** — Repository guidelines and workflow notes.
- **`build.zig`** — Build configuration: defines CLI, daemon, Node addon, test suites, and stdlib installation.
- **`README.md`** — Quick overview and basic syntax examples.

## Dependencies

- **LLVM** — Code generation backend (via Zig dependency)
- **Clang** — LLVM/Clang bindings (via Zig dependency)
- **N-API** — Node.js addon support (for `ZenScriptNode.node`)
- **Standard Library** — Auto-imported from `stdlib/`, provides `Option`, `Either`, `String`, `Unit`, I/O, memory management

## Architecture Notes

The compiler follows a classic multi-stage pipeline:

1. **Tokenizer** (`src/tokens/`) — Lexes source into tokens
2. **Parser** (`src/parser.zig`, `src/ast/`) — Builds AST
3. **Analyzer** (`src/analyzer/`) — Semantic analysis, type checking, scope resolution
4. **IRGen** (`src/ir/`) — Lowers AST to intermediate representation
5. **CodeGen** (`src/codegen/`) — Emits LLVM IR, then native code via MCJIT or object file + linker

The **daemon** (`src/daemon/`) provides language server functionality for the IntelliJ plugin. The **Node addon** (`src/nodemodule.zig`) exposes compilation capabilities to JavaScript via N-API.

The standard library is auto-imported as a prelude (`stdlib/prelude.chisa`) and declares all built-in scalar types (`number`, `long`, `short`, `byte`, `boolean`, `char`), making them available in every module.
