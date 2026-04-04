package org.chisa.intellij.highlighting

import com.intellij.lexer.Lexer
import com.intellij.openapi.editor.DefaultLanguageHighlighterColors
import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.openapi.editor.colors.TextAttributesKey.createTextAttributesKey
import com.intellij.openapi.fileTypes.SyntaxHighlighterBase
import com.intellij.psi.tree.IElementType
import org.chisa.intellij.lexer.ChisaLexer
import org.chisa.intellij.psi.ChisaTokenSets
import org.chisa.intellij.psi.ChisaTokenTypes

class ChisaSyntaxHighlighter : SyntaxHighlighterBase() {
    companion object {
        val KEYWORD = createTextAttributesKey("CHISA_KEYWORD", DefaultLanguageHighlighterColors.KEYWORD)
        val NUMBER = createTextAttributesKey("CHISA_NUMBER", DefaultLanguageHighlighterColors.NUMBER)
        val STRING = createTextAttributesKey("CHISA_STRING", DefaultLanguageHighlighterColors.STRING)
        val LINE_COMMENT = createTextAttributesKey("CHISA_LINE_COMMENT", DefaultLanguageHighlighterColors.LINE_COMMENT)
        val OPERATION_SIGN = createTextAttributesKey("CHISA_OPERATION_SIGN", DefaultLanguageHighlighterColors.OPERATION_SIGN)
        val PARENTHESES = createTextAttributesKey("CHISA_PARENTHESES", DefaultLanguageHighlighterColors.PARENTHESES)
        val BRACES = createTextAttributesKey("CHISA_BRACES", DefaultLanguageHighlighterColors.BRACES)
        val BRACKETS = createTextAttributesKey("CHISA_BRACKETS", DefaultLanguageHighlighterColors.BRACKETS)
        val COMMA = createTextAttributesKey("CHISA_COMMA", DefaultLanguageHighlighterColors.COMMA)
        val SEMICOLON = createTextAttributesKey("CHISA_SEMICOLON", DefaultLanguageHighlighterColors.SEMICOLON)
        val IDENTIFIER = createTextAttributesKey("CHISA_IDENTIFIER", DefaultLanguageHighlighterColors.IDENTIFIER)
        val FUNCTION_NAME = createTextAttributesKey("CHISA_FUNCTION_NAME", DefaultLanguageHighlighterColors.FUNCTION_DECLARATION)
        val FUNCTION_CALL = createTextAttributesKey("CHISA_FUNCTION_CALL", DefaultLanguageHighlighterColors.FUNCTION_CALL)
        val FIELD_NAME = createTextAttributesKey("CHISA_FIELD_NAME", DefaultLanguageHighlighterColors.INSTANCE_FIELD)
        val ENUM_VARIANT_NAME = createTextAttributesKey("CHISA_ENUM_VARIANT_NAME", DefaultLanguageHighlighterColors.STATIC_FIELD)
        val BAD_CHARACTER = createTextAttributesKey("CHISA_BAD_CHARACTER", DefaultLanguageHighlighterColors.INVALID_STRING_ESCAPE)

        private val KEYWORD_KEYS = arrayOf(KEYWORD)
        private val NUMBER_KEYS = arrayOf(NUMBER)
        private val STRING_KEYS = arrayOf(STRING)
        private val COMMENT_KEYS = arrayOf(LINE_COMMENT)
        private val OPERATOR_KEYS = arrayOf(OPERATION_SIGN)
        private val PAREN_KEYS = arrayOf(PARENTHESES)
        private val BRACE_KEYS = arrayOf(BRACES)
        private val BRACKET_KEYS = arrayOf(BRACKETS)
        private val COMMA_KEYS = arrayOf(COMMA)
        private val SEMICOLON_KEYS = arrayOf(SEMICOLON)
        private val IDENTIFIER_KEYS = arrayOf(IDENTIFIER)
        private val BAD_CHAR_KEYS = arrayOf(BAD_CHARACTER)
        private val EMPTY_KEYS = emptyArray<TextAttributesKey>()
    }

    override fun getHighlightingLexer(): Lexer = ChisaLexer()

    override fun getTokenHighlights(tokenType: IElementType): Array<TextAttributesKey> = when {
        ChisaTokenSets.KEYWORDS.contains(tokenType) -> KEYWORD_KEYS
        ChisaTokenSets.OPERATORS.contains(tokenType) -> OPERATOR_KEYS
        tokenType == ChisaTokenTypes.NUMBER_LITERAL -> NUMBER_KEYS
        tokenType == ChisaTokenTypes.STRING_LITERAL || tokenType == ChisaTokenTypes.CHAR_LITERAL -> STRING_KEYS
        tokenType == ChisaTokenTypes.LINE_COMMENT -> COMMENT_KEYS
        tokenType == ChisaTokenTypes.LPAREN || tokenType == ChisaTokenTypes.RPAREN -> PAREN_KEYS
        tokenType == ChisaTokenTypes.LBRACE || tokenType == ChisaTokenTypes.RBRACE -> BRACE_KEYS
        tokenType == ChisaTokenTypes.LBRACKET || tokenType == ChisaTokenTypes.RBRACKET -> BRACKET_KEYS
        tokenType == ChisaTokenTypes.COMMA -> COMMA_KEYS
        tokenType == ChisaTokenTypes.SEMICOLON -> SEMICOLON_KEYS
        tokenType == ChisaTokenTypes.IDENTIFIER -> IDENTIFIER_KEYS
        tokenType == ChisaTokenTypes.BAD_CHARACTER -> BAD_CHAR_KEYS
        else -> EMPTY_KEYS
    }
}
