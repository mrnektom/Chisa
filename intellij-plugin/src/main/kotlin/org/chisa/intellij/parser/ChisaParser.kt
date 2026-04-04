package org.chisa.intellij.parser

import com.intellij.lang.ASTNode
import com.intellij.lang.PsiBuilder
import com.intellij.lang.PsiParser
import com.intellij.psi.tree.IElementType
import org.chisa.intellij.psi.ChisaElementTypes
import org.chisa.intellij.psi.ChisaTokenTypes

class ChisaParser : PsiParser {
    override fun parse(root: IElementType, builder: PsiBuilder): ASTNode {
        val rootMarker = builder.mark()
        while (!builder.eof()) {
            val before = builder.currentOffset
            parseTopLevel(builder)
            if (builder.currentOffset == before) {
                builder.error("Unexpected token: ${builder.tokenType}")
                builder.advanceLexer()
            }
        }
        rootMarker.done(root)
        return builder.treeBuilt
    }

    private fun parseTopLevel(b: PsiBuilder) {
        when (b.tokenType) {
            ChisaTokenTypes.LET, ChisaTokenTypes.CONST -> parseVarDeclaration(b)
            ChisaTokenTypes.FN -> parseFnDeclaration(b)
            ChisaTokenTypes.EXTERNAL -> parseFnDeclaration(b)
            ChisaTokenTypes.STRUCT -> parseStructDeclaration(b)
            ChisaTokenTypes.ENUM -> parseEnumDeclaration(b)
            ChisaTokenTypes.SCALAR -> parseScalarDeclaration(b)
            ChisaTokenTypes.EXPORT -> {
                // Peek ahead: if next meaningful token is LBRACE, it's export-from
                if (peekNextToken(b) == ChisaTokenTypes.LBRACE) {
                    parseExportFromStatement(b)
                } else {
                    b.advanceLexer() // skip export
                    if (!b.eof()) parseTopLevel(b)
                }
            }
            ChisaTokenTypes.IF -> parseIfStatement(b)
            ChisaTokenTypes.WHILE -> parseWhileStatement(b)
            ChisaTokenTypes.FOR -> parseForStatement(b)
            ChisaTokenTypes.RETURN -> parseReturnStatement(b)
            ChisaTokenTypes.BREAK, ChisaTokenTypes.CONTINUE -> {
                b.advanceLexer()
                eatOptionalSemicolon(b)
            }
            ChisaTokenTypes.IMPORT -> parseImportStatement(b)
            ChisaTokenTypes.USE -> parseUseStatement(b)
            ChisaTokenTypes.AT -> parseAtTarget(b)
            ChisaTokenTypes.TYPE_KW -> parseTypeAliasDeclaration(b)
            ChisaTokenTypes.WHEN -> parseWhenExpression(b)
            ChisaTokenTypes.ASM -> parseAsmStatement(b)
            ChisaTokenTypes.IDENTIFIER,
            ChisaTokenTypes.THIS_KW -> parseExpressionStatement(b)
            else -> {
                b.error("Unexpected token: ${b.tokenType}")
                b.advanceLexer()
            }
        }
    }

    private fun parseStatement(b: PsiBuilder) {
        when (b.tokenType) {
            ChisaTokenTypes.LET, ChisaTokenTypes.CONST -> parseVarDeclaration(b)
            ChisaTokenTypes.FN -> parseFnDeclaration(b)
            ChisaTokenTypes.IF -> parseIfStatement(b)
            ChisaTokenTypes.WHILE -> parseWhileStatement(b)
            ChisaTokenTypes.FOR -> parseForStatement(b)
            ChisaTokenTypes.RETURN -> parseReturnStatement(b)
            ChisaTokenTypes.BREAK, ChisaTokenTypes.CONTINUE -> {
                b.advanceLexer()
                eatOptionalSemicolon(b)
            }
            ChisaTokenTypes.WHEN -> parseWhenExpression(b)
            ChisaTokenTypes.ASM -> parseAsmStatement(b)
            ChisaTokenTypes.LBRACE -> parseBlock(b)
            else -> parseExpressionStatement(b)
        }
    }

    private fun parseVarDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat let/const
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected identifier")
        }
        // Optional type annotation
        if (b.tokenType == ChisaTokenTypes.COLON) {
            b.advanceLexer()
            parseTypeReference(b)
        }
        // = expression
        if (b.tokenType == ChisaTokenTypes.EQ) {
            b.advanceLexer()
            parseExpression(b)
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.VAR_DECLARATION)
    }

    private fun parseFnDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        // optional: external
        if (b.tokenType == ChisaTokenTypes.EXTERNAL) {
            b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.FN) {
            b.advanceLexer() // eat fn
        }
        var isExtension = false
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat receiver type name or function name
            // Receiver may have generic params: fn Option<T>.method(...)
            if (b.tokenType == ChisaTokenTypes.LT) {
                val rollback = b.mark()
                skipGenericParams(b)
                if (b.tokenType == ChisaTokenTypes.DOT) {
                    // confirmed: generic receiver + dot = extension function
                    rollback.drop()
                } else {
                    // not extension — roll back and treat <...> as method generic params later
                    rollback.rollbackTo()
                }
            }
            // Check for extension function: fn TypeName.methodName(...)
            if (b.tokenType == ChisaTokenTypes.DOT) {
                isExtension = true
                b.advanceLexer() // eat .
                if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                    b.advanceLexer() // eat method name
                } else {
                    b.error("Expected method name after '.'")
                }
            }
        } else {
            b.error("Expected function name")
        }
        // Optional generic params <T, U> (method-level generics)
        if (b.tokenType == ChisaTokenTypes.LT) {
            skipGenericParams(b)
        }
        // Parameter list
        if (b.tokenType == ChisaTokenTypes.LPAREN) {
            parseParameterList(b)
        }
        // Optional return type
        if (b.tokenType == ChisaTokenTypes.COLON) {
            b.advanceLexer()
            parseTypeReference(b)
        }
        // Body: = expr or { block }
        if (b.tokenType == ChisaTokenTypes.EQ) {
            b.advanceLexer()
            parseExpression(b)
            eatOptionalSemicolon(b)
        } else if (b.tokenType == ChisaTokenTypes.LBRACE) {
            parseBlock(b)
        }
        if (isExtension) {
            marker.done(ChisaElementTypes.EXTENSION_FN_DECLARATION)
        } else {
            marker.done(ChisaElementTypes.FN_DECLARATION)
        }
    }

    private fun parseStructDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat struct
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected struct name")
        }
        if (b.tokenType == ChisaTokenTypes.LT) {
            skipGenericParams(b)
        }
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            parseStructBody(b)
        }
        marker.done(ChisaElementTypes.STRUCT_DECLARATION)
    }

    private fun parseEnumDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat enum
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected enum name")
        }
        if (b.tokenType == ChisaTokenTypes.LT) {
            skipGenericParams(b)
        }
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            parseEnumBody(b)
        }
        marker.done(ChisaElementTypes.ENUM_DECLARATION)
    }

    private fun parseEnumBody(b: PsiBuilder) {
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                val variantMarker = b.mark()
                b.advanceLexer() // eat variant name
                // Optional payload: (type, type, ...)
                if (b.tokenType == ChisaTokenTypes.LPAREN) {
                    skipParenContent(b)
                }
                variantMarker.done(ChisaElementTypes.ENUM_VARIANT)
            } else if (b.tokenType == ChisaTokenTypes.COMMA) {
                b.advanceLexer() // eat comma
            } else {
                b.error("Expected enum variant name")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun parseStructBody(b: PsiBuilder) {
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                val fieldMarker = b.mark()
                b.advanceLexer() // eat field name
                if (b.tokenType == ChisaTokenTypes.COLON) {
                    b.advanceLexer() // eat :
                    parseTypeReference(b)
                }
                fieldMarker.done(ChisaElementTypes.STRUCT_FIELD)
            } else if (b.tokenType == ChisaTokenTypes.COMMA) {
                b.advanceLexer() // eat comma
            } else {
                b.error("Expected struct field name")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun parseParameterList(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat (
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RPAREN) {
            parseParameter(b)
            if (b.tokenType == ChisaTokenTypes.COMMA) {
                b.advanceLexer()
            } else {
                break
            }
        }
        if (b.tokenType == ChisaTokenTypes.RPAREN) {
            b.advanceLexer()
        }
        marker.done(ChisaElementTypes.PARAMETER_LIST)
    }

    private fun parseParameter(b: PsiBuilder) {
        val marker = b.mark()
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat param name
        } else {
            b.error("Expected parameter name")
            marker.drop()
            return
        }
        if (b.tokenType == ChisaTokenTypes.COLON) {
            b.advanceLexer()
            parseTypeReference(b)
        }
        marker.done(ChisaElementTypes.PARAMETER)
    }

    private fun parseTypeReference(b: PsiBuilder) {
        val marker = b.mark()
        when {
            // Function type: (Type, ...) -> ReturnType
            b.tokenType == ChisaTokenTypes.LPAREN -> {
                b.advanceLexer() // eat (
                while (!b.eof() && b.tokenType != ChisaTokenTypes.RPAREN) {
                    parseTypeReference(b)
                    if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer() else break
                }
                if (b.tokenType == ChisaTokenTypes.RPAREN) b.advanceLexer()
                if (b.tokenType == ChisaTokenTypes.ARROW) {
                    b.advanceLexer() // eat ->
                    parseTypeReference(b) // return type
                } else {
                    b.error("Expected '->' in function type")
                }
            }
            b.tokenType == ChisaTokenTypes.IDENTIFIER || b.tokenType == ChisaTokenTypes.CHAR_KW -> {
                b.advanceLexer()
                // Optional generic args <T, U>
                if (b.tokenType == ChisaTokenTypes.LT) {
                    skipGenericParams(b)
                }
                // Optional array suffix: T[]
                if (b.tokenType == ChisaTokenTypes.LBRACKET) {
                    b.advanceLexer() // eat [
                    if (b.tokenType == ChisaTokenTypes.RBRACKET) {
                        b.advanceLexer() // eat ]
                    } else {
                        b.error("Expected ']'")
                    }
                }
            }
            else -> {
                b.error("Expected type name")
                marker.drop()
                return
            }
        }
        marker.done(ChisaElementTypes.TYPE_REFERENCE)
    }

    private fun parseBlock(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
            val before = b.currentOffset
            parseStatement(b)
            if (b.currentOffset == before) {
                // No progress — skip the unexpected token to avoid infinite loop
                b.error("Unexpected token: ${b.tokenType}")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) {
            b.advanceLexer()
        }
        marker.done(ChisaElementTypes.BLOCK)
    }

    private fun parseIfStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat if
        // condition
        if (b.tokenType == ChisaTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            parseExpression(b)
            if (b.tokenType == ChisaTokenTypes.RPAREN) b.advanceLexer()
        } else {
            parseExpression(b)
        }
        // then branch
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            parseBlock(b)
        } else {
            parseStatement(b)
        }
        // optional else
        if (b.tokenType == ChisaTokenTypes.ELSE) {
            b.advanceLexer()
            if (b.tokenType == ChisaTokenTypes.LBRACE) {
                parseBlock(b)
            } else {
                parseStatement(b)
            }
        }
        marker.done(ChisaElementTypes.IF_STATEMENT)
    }

    private fun parseWhileStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat while
        if (b.tokenType == ChisaTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            parseExpression(b)
            if (b.tokenType == ChisaTokenTypes.RPAREN) b.advanceLexer()
        } else {
            parseExpression(b)
        }
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            parseBlock(b)
        } else {
            parseStatement(b)
        }
        marker.done(ChisaElementTypes.WHILE_STATEMENT)
    }

    private fun parseForStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat for
        // for (init; cond; update) { body }
        if (b.tokenType == ChisaTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            // init: let/const declaration or expression statement
            if (b.tokenType == ChisaTokenTypes.LET || b.tokenType == ChisaTokenTypes.CONST) {
                parseVarDeclaration(b) // creates VAR_DECLARATION with identifier
            } else if (b.tokenType != ChisaTokenTypes.SEMICOLON) {
                parseExpression(b)
                eatOptionalSemicolon(b)
            }
            // condition
            if (b.tokenType != ChisaTokenTypes.SEMICOLON && b.tokenType != ChisaTokenTypes.RPAREN) {
                parseExpression(b)
            }
            eatOptionalSemicolon(b)
            // update
            if (b.tokenType != ChisaTokenTypes.RPAREN) {
                parseExpression(b)
                // Handle reassignment: expr = expr
                if (b.tokenType == ChisaTokenTypes.EQ) {
                    b.advanceLexer()
                    parseExpression(b)
                }
            }
            if (b.tokenType == ChisaTokenTypes.RPAREN) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            parseBlock(b)
        }
        marker.done(ChisaElementTypes.FOR_STATEMENT)
    }

    private fun parseReturnStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat return
        if (b.tokenType != null &&
            b.tokenType != ChisaTokenTypes.RBRACE &&
            b.tokenType != ChisaTokenTypes.SEMICOLON
        ) {
            parseExpression(b)
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.RETURN_STATEMENT)
    }

    private fun parseImportStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat import
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            parseImportSymbolList(b)
            if (b.tokenType == ChisaTokenTypes.RBRACE) {
                b.advanceLexer() // eat }
            } else {
                b.error("Expected '}'")
            }
        } else {
            b.error("Expected '{'")
        }
        if (b.tokenType == ChisaTokenTypes.FROM) {
            b.advanceLexer() // eat from
            parseImportPath(b)
        } else {
            b.error("Expected 'from'")
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.IMPORT_STATEMENT)
    }

    private fun parseExportFromStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat export
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            parseImportSymbolList(b)
            if (b.tokenType == ChisaTokenTypes.RBRACE) {
                b.advanceLexer() // eat }
            } else {
                b.error("Expected '}'")
            }
        } else {
            b.error("Expected '{'")
        }
        if (b.tokenType == ChisaTokenTypes.FROM) {
            b.advanceLexer() // eat from
            parseImportPath(b)
        } else {
            b.error("Expected 'from'")
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.EXPORT_FROM_STATEMENT)
    }

    private fun parseUseStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat use
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat enum name
        } else {
            b.error("Expected identifier")
        }
        if (b.tokenType == ChisaTokenTypes.DOT) {
            b.advanceLexer() // eat .
        } else {
            b.error("Expected '.'")
        }
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            parseImportSymbolList(b)
            if (b.tokenType == ChisaTokenTypes.RBRACE) {
                b.advanceLexer() // eat }
            } else {
                b.error("Expected '}'")
            }
        } else {
            b.error("Expected '{'")
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.USE_STATEMENT)
    }

    private fun parseImportSymbolList(b: PsiBuilder) {
        if (b.tokenType == ChisaTokenTypes.RBRACE) return // empty list
        parseImportSymbol(b)
        while (b.tokenType == ChisaTokenTypes.COMMA) {
            b.advanceLexer() // eat comma
            if (b.tokenType == ChisaTokenTypes.RBRACE) break // trailing comma
            parseImportSymbol(b)
        }
    }

    private fun parseImportSymbol(b: PsiBuilder) {
        val marker = b.mark()
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected identifier")
            marker.drop()
            return
        }
        // Optional alias: as alias_name
        if (b.tokenType == ChisaTokenTypes.AS) {
            b.advanceLexer() // eat as
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                b.advanceLexer() // eat alias
            } else {
                b.error("Expected alias name")
            }
        }
        marker.done(ChisaElementTypes.IMPORT_SYMBOL)
    }

    private fun parseImportPath(b: PsiBuilder) {
        val marker = b.mark()
        if (b.tokenType == ChisaTokenTypes.STRING_LITERAL) {
            b.advanceLexer()
        } else {
            b.error("Expected string literal path")
            marker.drop()
            return
        }
        marker.done(ChisaElementTypes.IMPORT_PATH)
    }

    /**
     * Peek at the next token type without advancing.
     */
    private fun peekNextToken(b: PsiBuilder): IElementType? {
        val marker = b.mark()
        b.advanceLexer() // skip current token
        val next = b.tokenType
        marker.rollbackTo()
        return next
    }

    private fun parseExpressionStatement(b: PsiBuilder) {
        parseExpression(b)
        // Handle reassignment: expr = expr
        if (b.tokenType == ChisaTokenTypes.EQ) {
            b.advanceLexer()
            parseExpression(b)
        }
        eatOptionalSemicolon(b)
    }

    /**
     * Expression parser with precedence climbing.
     * Precedence levels (lowest to highest):
     *   0: ||
     *   1: &&
     *   2: ==, !=
     *   3: <, >, <=, >=
     *   4: +, -
     *   5: *, /, %
     */
    private fun parseExpression(b: PsiBuilder) {
        parseExpressionPrec(b, 0)
    }

    private fun parseExpressionPrec(b: PsiBuilder, minPrec: Int) {
        parseUnaryExpression(b)

        while (!b.eof()) {
            val prec = operatorPrecedence(b.tokenType) ?: break
            if (prec < minPrec) break
            b.advanceLexer() // eat operator
            parseExpressionPrec(b, prec + 1)
        }
    }

    private fun operatorPrecedence(type: IElementType?): Int? = when (type) {
        ChisaTokenTypes.OR_OR -> 0
        ChisaTokenTypes.AND_AND -> 1
        ChisaTokenTypes.EQ_EQ, ChisaTokenTypes.BANG_EQ -> 2
        ChisaTokenTypes.LT, ChisaTokenTypes.GT,
        ChisaTokenTypes.LT_EQ, ChisaTokenTypes.GT_EQ -> 3
        ChisaTokenTypes.PLUS, ChisaTokenTypes.MINUS -> 4
        ChisaTokenTypes.STAR, ChisaTokenTypes.SLASH,
        ChisaTokenTypes.PERCENT -> 5
        else -> null
    }

    private fun parseUnaryExpression(b: PsiBuilder) {
        // Unary prefix: !, -
        if (b.tokenType == ChisaTokenTypes.BANG || b.tokenType == ChisaTokenTypes.MINUS) {
            b.advanceLexer()
        }
        parsePrimaryExpression(b)
    }

    private fun parsePrimaryExpression(b: PsiBuilder) {
        when (b.tokenType) {
            ChisaTokenTypes.IDENTIFIER,
            ChisaTokenTypes.THIS_KW -> {
                val marker = b.mark()
                b.advanceLexer() // eat identifier / this
                marker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                parseSuffix(b)
            }
            ChisaTokenTypes.NUMBER_LITERAL,
            ChisaTokenTypes.STRING_LITERAL,
            ChisaTokenTypes.CHAR_LITERAL,
            ChisaTokenTypes.TRUE,
            ChisaTokenTypes.FALSE -> {
                b.advanceLexer()
            }
            ChisaTokenTypes.LPAREN -> {
                skipParenContent(b)
            }
            ChisaTokenTypes.LBRACKET -> {
                parseArrayLiteral(b)
            }
            ChisaTokenTypes.LBRACE -> {
                if (isLambdaStart(b)) parseLambdaExpression(b) else parseBlock(b)
            }
            ChisaTokenTypes.MATCH -> {
                parseMatchExpression(b)
            }
            ChisaTokenTypes.WHEN -> {
                parseWhenExpression(b)
            }
            ChisaTokenTypes.IF -> {
                // inline if expression — delegate to if statement parsing
                parseIfStatement(b)
            }
            else -> {
                // Don't advance — caller handles this
            }
        }
    }

    private fun parseSuffix(b: PsiBuilder) {
        while (!b.eof()) {
            when (b.tokenType) {
                ChisaTokenTypes.LPAREN -> {
                    // Function call
                    skipParenContent(b)
                }
                ChisaTokenTypes.DOT -> {
                    b.advanceLexer() // eat .
                    if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                        val marker = b.mark()
                        b.advanceLexer()
                        marker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                    }
                }
                ChisaTokenTypes.LBRACKET -> {
                    skipBracketContent(b)
                }
                ChisaTokenTypes.LBRACE -> {
                    // Struct literal: Name { field: value, ... }
                    parseStructLiteralBody(b)
                }
                ChisaTokenTypes.LT -> {
                    // Generic struct literal: Name<T, U> { field: value, ... }
                    // Speculatively skip generic args; if followed by '{' it's a struct literal.
                    val rollback = b.mark()
                    skipGenericParams(b)
                    if (b.tokenType == ChisaTokenTypes.LBRACE) {
                        rollback.drop()
                        parseStructLiteralBody(b)
                    } else {
                        rollback.rollbackTo()
                        break
                    }
                }
                ChisaTokenTypes.QUEST_DOT -> {
                    val safeMarker = b.mark()
                    b.advanceLexer() // eat ?.
                    if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                        val refMarker = b.mark()
                        b.advanceLexer()
                        refMarker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                    }
                    safeMarker.done(ChisaElementTypes.SAFE_NAVIGATION)
                }
                ChisaTokenTypes.BANG_BANG -> {
                    val errMarker = b.mark()
                    b.advanceLexer() // eat !!
                    errMarker.done(ChisaElementTypes.ERROR_PROPAGATION)
                }
                else -> break
            }
        }
    }

    private fun parseStructLiteralBody(b: PsiBuilder) {
        if (b.tokenType != ChisaTokenTypes.LBRACE) return
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                val marker = b.mark()
                b.advanceLexer() // eat field name
                marker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                if (b.tokenType == ChisaTokenTypes.COLON) {
                    b.advanceLexer() // eat :
                    parseExpression(b)
                }
            }
            if (b.tokenType == ChisaTokenTypes.COMMA) {
                b.advanceLexer()
            } else if (b.tokenType != ChisaTokenTypes.RBRACE) {
                b.error("Expected ',' or '}'")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun parseMatchExpression(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat match
        parseExpression(b) // subject
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
                val armMarker = b.mark()
                parseMatchPattern(b)
                if (b.tokenType == ChisaTokenTypes.ARROW) {
                    b.advanceLexer() // eat ->
                    parseExpression(b)
                } else {
                    b.error("Expected '->'")
                }
                if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer()
                armMarker.done(ChisaElementTypes.MATCH_ARM)
            }
            if (b.tokenType == ChisaTokenTypes.RBRACE) b.advanceLexer()
        }
        marker.done(ChisaElementTypes.MATCH_EXPRESSION)
    }

    private fun parseMatchPattern(b: PsiBuilder) {
        when (b.tokenType) {
            ChisaTokenTypes.ELSE -> b.advanceLexer()
            ChisaTokenTypes.NUMBER_LITERAL,
            ChisaTokenTypes.STRING_LITERAL,
            ChisaTokenTypes.CHAR_LITERAL,
            ChisaTokenTypes.TRUE,
            ChisaTokenTypes.FALSE -> b.advanceLexer()
            ChisaTokenTypes.IDENTIFIER -> {
                val nameMarker = b.mark()
                b.advanceLexer() // eat name
                when (b.tokenType) {
                    ChisaTokenTypes.DOT -> {
                        // EnumName.Variant or EnumName.Variant(payload bindings)
                        nameMarker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                        b.advanceLexer() // eat .
                        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                            val varMarker = b.mark()
                            b.advanceLexer()
                            varMarker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                        }
                        if (b.tokenType == ChisaTokenTypes.LPAREN) {
                            parseEnumPayloadPattern(b)
                        }
                    }
                    ChisaTokenTypes.LBRACE -> {
                        // StructName { field: val, field2 }
                        nameMarker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                        parseStructPatternBody(b)
                    }
                    else -> {
                        // Plain binding identifier — binds the matched value to a variable
                        nameMarker.done(ChisaElementTypes.MATCH_BINDING)
                    }
                }
            }
            else -> {
                b.error("Expected match pattern")
                b.advanceLexer()
            }
        }
    }

    /** Parses `(binding1, binding2, ...)` in an enum variant pattern. Each identifier becomes a MATCH_BINDING. */
    private fun parseEnumPayloadPattern(b: PsiBuilder) {
        b.advanceLexer() // eat (
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RPAREN) {
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                val bindMarker = b.mark()
                b.advanceLexer()
                bindMarker.done(ChisaElementTypes.MATCH_BINDING)
            } else {
                b.error("Expected binding name")
                b.advanceLexer()
            }
            if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.RPAREN) b.advanceLexer()
    }

    /** Parses `{ field: value, field2, ... }` in a struct pattern.
     *  `field: value` — valued field (reference + skip expression), `field2` alone — MATCH_BINDING. */
    private fun parseStructPatternBody(b: PsiBuilder) {
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                val fieldMarker = b.mark()
                b.advanceLexer() // eat field name
                if (b.tokenType == ChisaTokenTypes.COLON) {
                    // field: value — reference expression, not a binding
                    fieldMarker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                    b.advanceLexer() // eat :
                    parseExpression(b)
                } else {
                    // bare field name — binds the field value to a variable
                    fieldMarker.done(ChisaElementTypes.MATCH_BINDING)
                }
            } else {
                b.error("Expected field name")
                b.advanceLexer()
            }
            if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) b.advanceLexer()
    }

    private fun parseScalarDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat scalar
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected scalar type name")
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.SCALAR_DECLARATION)
    }

    private fun parseArrayLiteral(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat [
        if (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACKET) {
            parseExpression(b)
            when {
                // [expr; count] — repeat literal
                b.tokenType == ChisaTokenTypes.SEMICOLON -> {
                    b.advanceLexer() // eat ;
                    parseExpression(b) // eat count
                }
                // [expr, expr, ...] — list literal
                b.tokenType == ChisaTokenTypes.COMMA -> {
                    while (b.tokenType == ChisaTokenTypes.COMMA) {
                        b.advanceLexer()
                        if (b.tokenType == ChisaTokenTypes.RBRACKET) break
                        parseExpression(b)
                    }
                }
            }
        }
        if (b.tokenType == ChisaTokenTypes.RBRACKET) {
            b.advanceLexer()
        } else {
            b.error("Expected ']'")
        }
        marker.done(ChisaElementTypes.ARRAY_LITERAL)
    }

    // --- Helpers ---

    private fun skipParenContent(b: PsiBuilder) {
        if (b.tokenType != ChisaTokenTypes.LPAREN) return
        b.advanceLexer() // eat (
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ChisaTokenTypes.LPAREN -> depth++
                ChisaTokenTypes.RPAREN -> depth--
                ChisaTokenTypes.IDENTIFIER -> {
                    val marker = b.mark()
                    b.advanceLexer()
                    marker.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                    continue
                }
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.RPAREN) {
            b.advanceLexer()
        }
    }

    private fun skipBraceContent(b: PsiBuilder) {
        if (b.tokenType != ChisaTokenTypes.LBRACE) return
        b.advanceLexer() // eat {
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ChisaTokenTypes.LBRACE -> depth++
                ChisaTokenTypes.RBRACE -> depth--
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun skipBracketContent(b: PsiBuilder) {
        if (b.tokenType != ChisaTokenTypes.LBRACKET) return
        b.advanceLexer() // eat [
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ChisaTokenTypes.LBRACKET -> depth++
                ChisaTokenTypes.RBRACKET -> depth--
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.RBRACKET) {
            b.advanceLexer()
        }
    }

    private fun skipGenericParams(b: PsiBuilder) {
        if (b.tokenType != ChisaTokenTypes.LT) return
        b.advanceLexer() // eat <
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ChisaTokenTypes.LT -> depth++
                ChisaTokenTypes.GT -> depth--
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ChisaTokenTypes.GT) {
            b.advanceLexer()
        }
    }

    private fun eatOptionalSemicolon(b: PsiBuilder) {
        if (b.tokenType == ChisaTokenTypes.SEMICOLON) {
            b.advanceLexer()
        }
    }

    // --- New constructs ---

    private fun parseAtTarget(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat @
        // expect `target` identifier
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer()
        } else {
            b.error("Expected 'target' after '@'")
        }
        if (b.tokenType == ChisaTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            // condition expression (identifiers, ==, &&, ||, strings, !)
            parseExpression(b)
            if (b.tokenType == ChisaTokenTypes.RPAREN) b.advanceLexer()
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.AT_TARGET)
    }

    private fun parseTypeAliasDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat type
        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat alias name
        } else {
            b.error("Expected type alias name")
        }
        if (b.tokenType == ChisaTokenTypes.LT) {
            skipGenericParams(b)
        }
        if (b.tokenType == ChisaTokenTypes.EQ) {
            b.advanceLexer() // eat =
            parseTypeReference(b)
        } else {
            b.error("Expected '='")
        }
        eatOptionalSemicolon(b)
        marker.done(ChisaElementTypes.TYPE_ALIAS_DECLARATION)
    }

    /**
     * Speculatively checks if the `{` at current position starts a lambda.
     * A lambda has the form: `{` (`->` | params `->`) body `}`
     * where params = `ident (: Type)? (, ident (: Type)?)*`
     */
    private fun isLambdaStart(b: PsiBuilder): Boolean {
        val rollback = b.mark()
        b.advanceLexer() // eat {
        // { -> ... } — zero-param lambda
        val result = if (b.tokenType == ChisaTokenTypes.ARROW) {
            true
        } else {
            // Try to parse: (ident (: Type)? ,)* ident (: Type)? ->
            var found = false
            loop@ while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
                if (b.tokenType != ChisaTokenTypes.IDENTIFIER) break@loop
                b.advanceLexer() // eat param name
                if (b.tokenType == ChisaTokenTypes.COLON) {
                    b.advanceLexer() // eat :
                    // skip type tokens: ident, optional <...>, optional []
                    if (b.tokenType == ChisaTokenTypes.IDENTIFIER || b.tokenType == ChisaTokenTypes.CHAR_KW) {
                        b.advanceLexer()
                        if (b.tokenType == ChisaTokenTypes.LT) skipGenericParams(b)
                        if (b.tokenType == ChisaTokenTypes.LBRACKET) {
                            b.advanceLexer()
                            if (b.tokenType == ChisaTokenTypes.RBRACKET) b.advanceLexer()
                        }
                    }
                }
                when (b.tokenType) {
                    ChisaTokenTypes.ARROW -> { found = true; break@loop }
                    ChisaTokenTypes.COMMA -> b.advanceLexer()
                    else -> break@loop
                }
            }
            found
        }
        rollback.rollbackTo()
        return result
    }

    private fun parseLambdaExpression(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat {
        // Parse params (may be empty) before ->
        while (!b.eof() && b.tokenType != ChisaTokenTypes.ARROW && b.tokenType != ChisaTokenTypes.RBRACE) {
            if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                val paramMarker = b.mark()
                b.advanceLexer() // eat param name
                if (b.tokenType == ChisaTokenTypes.COLON) {
                    b.advanceLexer()
                    parseTypeReference(b)
                }
                paramMarker.done(ChisaElementTypes.LAMBDA_PARAM)
            }
            if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer() else break
        }
        if (b.tokenType == ChisaTokenTypes.ARROW) b.advanceLexer() // eat ->
        // Parse body statements
        while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
            val before = b.currentOffset
            parseStatement(b)
            if (b.currentOffset == before) {
                b.error("Unexpected token: ${b.tokenType}")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ChisaTokenTypes.RBRACE) b.advanceLexer()
        marker.done(ChisaElementTypes.LAMBDA_EXPRESSION)
    }

    private fun parseWhenExpression(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat when
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
                val armMarker = b.mark()
                // condition or else
                if (b.tokenType == ChisaTokenTypes.ELSE) {
                    b.advanceLexer()
                } else {
                    parseExpression(b)
                }
                if (b.tokenType == ChisaTokenTypes.ARROW) {
                    b.advanceLexer() // eat ->
                    // arm body: declaration or expression
                    if (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE &&
                        b.tokenType != ChisaTokenTypes.COMMA) {
                        parseStatement(b)
                    }
                } else {
                    b.error("Expected '->'")
                }
                if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer()
                armMarker.done(ChisaElementTypes.WHEN_ARM)
            }
            if (b.tokenType == ChisaTokenTypes.RBRACE) b.advanceLexer()
        }
        marker.done(ChisaElementTypes.WHEN_EXPRESSION)
    }

    private fun parseAsmStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat asm
        if (b.tokenType == ChisaTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            while (!b.eof() && b.tokenType != ChisaTokenTypes.RBRACE) {
                when (b.tokenType) {
                    ChisaTokenTypes.IN_KW -> {
                        val bm = b.mark()
                        b.advanceLexer() // eat in
                        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) b.advanceLexer() // reg
                        if (b.tokenType == ChisaTokenTypes.EQ) b.advanceLexer()
                        parseExpression(b)
                        bm.done(ChisaElementTypes.ASM_BINDING)
                    }
                    ChisaTokenTypes.OUT_KW -> {
                        val bm = b.mark()
                        b.advanceLexer() // eat out
                        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) b.advanceLexer() // reg
                        if (b.tokenType == ChisaTokenTypes.EQ) b.advanceLexer()
                        if (b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                            val nm = b.mark()
                            b.advanceLexer()
                            nm.done(ChisaElementTypes.REFERENCE_EXPRESSION)
                        }
                        bm.done(ChisaElementTypes.ASM_BINDING)
                    }
                    ChisaTokenTypes.CLOBBER_KW -> {
                        val bm = b.mark()
                        b.advanceLexer() // eat clobber
                        while (!b.eof() && b.tokenType == ChisaTokenTypes.IDENTIFIER) {
                            b.advanceLexer()
                            if (b.tokenType == ChisaTokenTypes.COMMA) b.advanceLexer() else break
                        }
                        bm.done(ChisaElementTypes.ASM_BINDING)
                    }
                    ChisaTokenTypes.STRING_LITERAL -> {
                        b.advanceLexer() // assembly instruction string
                    }
                    else -> {
                        b.error("Unexpected token in asm block")
                        b.advanceLexer()
                    }
                }
            }
            if (b.tokenType == ChisaTokenTypes.RBRACE) b.advanceLexer()
        }
        marker.done(ChisaElementTypes.ASM_STATEMENT)
    }

}
