package org.chisa.intellij.psi

import com.intellij.psi.tree.TokenSet

object ChisaTokenSets {
    @JvmField val KEYWORDS = TokenSet.create(
        ChisaTokenTypes.LET, ChisaTokenTypes.CONST, ChisaTokenTypes.FN,
        ChisaTokenTypes.IF, ChisaTokenTypes.ELSE, ChisaTokenTypes.WHILE,
        ChisaTokenTypes.FOR, ChisaTokenTypes.BREAK, ChisaTokenTypes.CONTINUE,
        ChisaTokenTypes.RETURN, ChisaTokenTypes.MATCH, ChisaTokenTypes.STRUCT,
        ChisaTokenTypes.ENUM, ChisaTokenTypes.EXTERNAL, ChisaTokenTypes.IMPORT,
        ChisaTokenTypes.EXPORT, ChisaTokenTypes.FROM, ChisaTokenTypes.AS,
        ChisaTokenTypes.USE, ChisaTokenTypes.TRUE, ChisaTokenTypes.FALSE,
        ChisaTokenTypes.SCALAR,
        ChisaTokenTypes.WHEN, ChisaTokenTypes.ASM, ChisaTokenTypes.TYPE_KW,
        ChisaTokenTypes.IN_KW, ChisaTokenTypes.OUT_KW, ChisaTokenTypes.CLOBBER_KW,
        ChisaTokenTypes.THIS_KW
    )

    @JvmField val OPERATORS = TokenSet.create(
        ChisaTokenTypes.PLUS, ChisaTokenTypes.MINUS, ChisaTokenTypes.STAR,
        ChisaTokenTypes.SLASH, ChisaTokenTypes.PERCENT,
        ChisaTokenTypes.EQ_EQ, ChisaTokenTypes.BANG_EQ,
        ChisaTokenTypes.LT_EQ, ChisaTokenTypes.GT_EQ,
        ChisaTokenTypes.LT, ChisaTokenTypes.GT,
        ChisaTokenTypes.EQ, ChisaTokenTypes.AND_AND, ChisaTokenTypes.OR_OR,
        ChisaTokenTypes.BANG, ChisaTokenTypes.ARROW, ChisaTokenTypes.DOT,
        ChisaTokenTypes.QUEST_DOT, ChisaTokenTypes.BANG_BANG
    )

    @JvmField val STRINGS = TokenSet.create(ChisaTokenTypes.STRING_LITERAL)
    @JvmField val COMMENTS = TokenSet.create(ChisaTokenTypes.LINE_COMMENT)
    @JvmField val WHITE_SPACES = TokenSet.create(ChisaTokenTypes.WHITE_SPACE)
}

object ChisaTokenTypes {
    // Keywords
    @JvmField val LET = ChisaTokenType("LET")
    @JvmField val CONST = ChisaTokenType("CONST")
    @JvmField val FN = ChisaTokenType("FN")
    @JvmField val IF = ChisaTokenType("IF")
    @JvmField val ELSE = ChisaTokenType("ELSE")
    @JvmField val WHILE = ChisaTokenType("WHILE")
    @JvmField val FOR = ChisaTokenType("FOR")
    @JvmField val BREAK = ChisaTokenType("BREAK")
    @JvmField val CONTINUE = ChisaTokenType("CONTINUE")
    @JvmField val RETURN = ChisaTokenType("RETURN")
    @JvmField val MATCH = ChisaTokenType("MATCH")
    @JvmField val STRUCT = ChisaTokenType("STRUCT")
    @JvmField val ENUM = ChisaTokenType("ENUM")
    @JvmField val EXTERNAL = ChisaTokenType("EXTERNAL")
    @JvmField val IMPORT = ChisaTokenType("IMPORT")
    @JvmField val EXPORT = ChisaTokenType("EXPORT")
    @JvmField val FROM = ChisaTokenType("FROM")
    @JvmField val AS = ChisaTokenType("AS")
    @JvmField val USE = ChisaTokenType("USE")
    @JvmField val TRUE = ChisaTokenType("TRUE")
    @JvmField val FALSE = ChisaTokenType("FALSE")
    @JvmField val SCALAR = ChisaTokenType("SCALAR")
    @JvmField val WHEN = ChisaTokenType("WHEN")
    @JvmField val ASM = ChisaTokenType("ASM")
    @JvmField val TYPE_KW = ChisaTokenType("TYPE_KW")
    @JvmField val IN_KW = ChisaTokenType("IN_KW")
    @JvmField val OUT_KW = ChisaTokenType("OUT_KW")
    @JvmField val CLOBBER_KW = ChisaTokenType("CLOBBER_KW")
    @JvmField val THIS_KW = ChisaTokenType("THIS_KW")

    // Literals
    @JvmField val NUMBER_LITERAL = ChisaTokenType("NUMBER_LITERAL")
    @JvmField val STRING_LITERAL = ChisaTokenType("STRING_LITERAL")
    @JvmField val CHAR_LITERAL = ChisaTokenType("CHAR_LITERAL")
    @JvmField val IDENTIFIER = ChisaTokenType("IDENTIFIER")

    // Operators
    @JvmField val PLUS = ChisaTokenType("PLUS")
    @JvmField val MINUS = ChisaTokenType("MINUS")
    @JvmField val STAR = ChisaTokenType("STAR")
    @JvmField val SLASH = ChisaTokenType("SLASH")
    @JvmField val PERCENT = ChisaTokenType("PERCENT")
    @JvmField val EQ = ChisaTokenType("EQ")
    @JvmField val EQ_EQ = ChisaTokenType("EQ_EQ")
    @JvmField val BANG = ChisaTokenType("BANG")
    @JvmField val BANG_EQ = ChisaTokenType("BANG_EQ")
    @JvmField val LT = ChisaTokenType("LT")
    @JvmField val GT = ChisaTokenType("GT")
    @JvmField val LT_EQ = ChisaTokenType("LT_EQ")
    @JvmField val GT_EQ = ChisaTokenType("GT_EQ")
    @JvmField val AND_AND = ChisaTokenType("AND_AND")
    @JvmField val OR_OR = ChisaTokenType("OR_OR")
    @JvmField val ARROW = ChisaTokenType("ARROW")
    @JvmField val DOT = ChisaTokenType("DOT")
    @JvmField val QUEST_DOT = ChisaTokenType("QUEST_DOT")
    @JvmField val BANG_BANG = ChisaTokenType("BANG_BANG")
    @JvmField val AT = ChisaTokenType("AT")

    // Delimiters
    @JvmField val LPAREN = ChisaTokenType("LPAREN")
    @JvmField val RPAREN = ChisaTokenType("RPAREN")
    @JvmField val LBRACE = ChisaTokenType("LBRACE")
    @JvmField val RBRACE = ChisaTokenType("RBRACE")
    @JvmField val LBRACKET = ChisaTokenType("LBRACKET")
    @JvmField val RBRACKET = ChisaTokenType("RBRACKET")
    @JvmField val COMMA = ChisaTokenType("COMMA")
    @JvmField val COLON = ChisaTokenType("COLON")
    @JvmField val SEMICOLON = ChisaTokenType("SEMICOLON")

    // Special
    @JvmField val WHITE_SPACE = ChisaTokenType("WHITE_SPACE")
    @JvmField val LINE_COMMENT = ChisaTokenType("LINE_COMMENT")
    @JvmField val BAD_CHARACTER = ChisaTokenType("BAD_CHARACTER")

    val KEYWORD_MAP: Map<String, ChisaTokenType> = mapOf(
        "let" to LET, "const" to CONST, "fn" to FN,
        "if" to IF, "else" to ELSE, "while" to WHILE,
        "for" to FOR, "break" to BREAK, "continue" to CONTINUE,
        "return" to RETURN, "match" to MATCH, "struct" to STRUCT,
        "enum" to ENUM, "external" to EXTERNAL, "import" to IMPORT,
        "export" to EXPORT, "from" to FROM, "as" to AS,
        "use" to USE, "true" to TRUE, "false" to FALSE,
        "scalar" to SCALAR,
        "when" to WHEN, "asm" to ASM, "type" to TYPE_KW,
        "in" to IN_KW, "out" to OUT_KW, "clobber" to CLOBBER_KW,
        "this" to THIS_KW
    )
}
