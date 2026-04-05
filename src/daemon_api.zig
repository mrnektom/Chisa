/// Facade module that re-exports compiler internals needed by zs-daemon.
/// Lives at src/ so it can reach all sibling packages via relative imports.
pub const Tokenizer = @import("tokens/tokenizer.zig");
pub const Parser = @import("parser.zig");
pub const Analyzer = @import("analyzer/analyzer.zig");
pub const Sig = @import("analyzer/symbol_signature.zig");
pub const ZSModule = @import("ast/zs_module.zig").ZSModule;
pub const SymbolTable = @import("analyzer/symbol_table_stack.zig").SymbolTable;
pub const ZSFn = @import("ast/zs_stmt_fn.zig");
pub const ZSAstType = @import("ast/zs_type_notation.zig").ZSTypeNotation;
