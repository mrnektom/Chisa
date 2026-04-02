package org.zenscript.intellij.parser

import com.intellij.lang.ASTNode
import com.intellij.lang.PsiBuilder
import com.intellij.lang.PsiParser
import com.intellij.psi.tree.IElementType
import org.zenscript.intellij.psi.ZenScriptElementTypes
import org.zenscript.intellij.psi.ZenScriptTokenTypes

class ZenScriptParser : PsiParser {
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
            ZenScriptTokenTypes.LET, ZenScriptTokenTypes.CONST -> parseVarDeclaration(b)
            ZenScriptTokenTypes.FN -> parseFnDeclaration(b)
            ZenScriptTokenTypes.EXTERNAL -> parseFnDeclaration(b)
            ZenScriptTokenTypes.STRUCT -> parseStructDeclaration(b)
            ZenScriptTokenTypes.ENUM -> parseEnumDeclaration(b)
            ZenScriptTokenTypes.SCALAR -> parseScalarDeclaration(b)
            ZenScriptTokenTypes.EXPORT -> {
                // Peek ahead: if next meaningful token is LBRACE, it's export-from
                if (peekNextToken(b) == ZenScriptTokenTypes.LBRACE) {
                    parseExportFromStatement(b)
                } else {
                    b.advanceLexer() // skip export
                    if (!b.eof()) parseTopLevel(b)
                }
            }
            ZenScriptTokenTypes.IF -> parseIfStatement(b)
            ZenScriptTokenTypes.WHILE -> parseWhileStatement(b)
            ZenScriptTokenTypes.FOR -> parseForStatement(b)
            ZenScriptTokenTypes.RETURN -> parseReturnStatement(b)
            ZenScriptTokenTypes.BREAK, ZenScriptTokenTypes.CONTINUE -> {
                b.advanceLexer()
                eatOptionalSemicolon(b)
            }
            ZenScriptTokenTypes.IMPORT -> parseImportStatement(b)
            ZenScriptTokenTypes.USE -> parseUseStatement(b)
            ZenScriptTokenTypes.AT -> parseAtTarget(b)
            ZenScriptTokenTypes.TYPE_KW -> parseTypeAliasDeclaration(b)
            ZenScriptTokenTypes.WHEN -> parseWhenExpression(b)
            ZenScriptTokenTypes.ASM -> parseAsmStatement(b)
            ZenScriptTokenTypes.IDENTIFIER,
            ZenScriptTokenTypes.THIS_KW -> parseExpressionStatement(b)
            else -> {
                b.error("Unexpected token: ${b.tokenType}")
                b.advanceLexer()
            }
        }
    }

    private fun parseStatement(b: PsiBuilder) {
        when (b.tokenType) {
            ZenScriptTokenTypes.LET, ZenScriptTokenTypes.CONST -> parseVarDeclaration(b)
            ZenScriptTokenTypes.FN -> parseFnDeclaration(b)
            ZenScriptTokenTypes.IF -> parseIfStatement(b)
            ZenScriptTokenTypes.WHILE -> parseWhileStatement(b)
            ZenScriptTokenTypes.FOR -> parseForStatement(b)
            ZenScriptTokenTypes.RETURN -> parseReturnStatement(b)
            ZenScriptTokenTypes.BREAK, ZenScriptTokenTypes.CONTINUE -> {
                b.advanceLexer()
                eatOptionalSemicolon(b)
            }
            ZenScriptTokenTypes.WHEN -> parseWhenExpression(b)
            ZenScriptTokenTypes.ASM -> parseAsmStatement(b)
            ZenScriptTokenTypes.LBRACE -> parseBlock(b)
            else -> parseExpressionStatement(b)
        }
    }

    private fun parseVarDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat let/const
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected identifier")
        }
        // Optional type annotation
        if (b.tokenType == ZenScriptTokenTypes.COLON) {
            b.advanceLexer()
            parseTypeReference(b)
        }
        // = expression
        if (b.tokenType == ZenScriptTokenTypes.EQ) {
            b.advanceLexer()
            parseExpression(b)
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.VAR_DECLARATION)
    }

    private fun parseFnDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        // optional: external
        if (b.tokenType == ZenScriptTokenTypes.EXTERNAL) {
            b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.FN) {
            b.advanceLexer() // eat fn
        }
        var isExtension = false
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat receiver type name or function name
            // Receiver may have generic params: fn Option<T>.method(...)
            if (b.tokenType == ZenScriptTokenTypes.LT) {
                val rollback = b.mark()
                skipGenericParams(b)
                if (b.tokenType == ZenScriptTokenTypes.DOT) {
                    // confirmed: generic receiver + dot = extension function
                    rollback.drop()
                } else {
                    // not extension — roll back and treat <...> as method generic params later
                    rollback.rollbackTo()
                }
            }
            // Check for extension function: fn TypeName.methodName(...)
            if (b.tokenType == ZenScriptTokenTypes.DOT) {
                isExtension = true
                b.advanceLexer() // eat .
                if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                    b.advanceLexer() // eat method name
                } else {
                    b.error("Expected method name after '.'")
                }
            }
        } else {
            b.error("Expected function name")
        }
        // Optional generic params <T, U> (method-level generics)
        if (b.tokenType == ZenScriptTokenTypes.LT) {
            skipGenericParams(b)
        }
        // Parameter list
        if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
            parseParameterList(b)
        }
        // Optional return type
        if (b.tokenType == ZenScriptTokenTypes.COLON) {
            b.advanceLexer()
            parseTypeReference(b)
        }
        // Body: = expr or { block }
        if (b.tokenType == ZenScriptTokenTypes.EQ) {
            b.advanceLexer()
            parseExpression(b)
            eatOptionalSemicolon(b)
        } else if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            parseBlock(b)
        }
        if (isExtension) {
            marker.done(ZenScriptElementTypes.EXTENSION_FN_DECLARATION)
        } else {
            marker.done(ZenScriptElementTypes.FN_DECLARATION)
        }
    }

    private fun parseStructDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat struct
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected struct name")
        }
        if (b.tokenType == ZenScriptTokenTypes.LT) {
            skipGenericParams(b)
        }
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            parseStructBody(b)
        }
        marker.done(ZenScriptElementTypes.STRUCT_DECLARATION)
    }

    private fun parseEnumDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat enum
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected enum name")
        }
        if (b.tokenType == ZenScriptTokenTypes.LT) {
            skipGenericParams(b)
        }
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            parseEnumBody(b)
        }
        marker.done(ZenScriptElementTypes.ENUM_DECLARATION)
    }

    private fun parseEnumBody(b: PsiBuilder) {
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                val variantMarker = b.mark()
                b.advanceLexer() // eat variant name
                // Optional payload: (type, type, ...)
                if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
                    skipParenContent(b)
                }
                variantMarker.done(ZenScriptElementTypes.ENUM_VARIANT)
            } else if (b.tokenType == ZenScriptTokenTypes.COMMA) {
                b.advanceLexer() // eat comma
            } else {
                b.error("Expected enum variant name")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun parseStructBody(b: PsiBuilder) {
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                val fieldMarker = b.mark()
                b.advanceLexer() // eat field name
                if (b.tokenType == ZenScriptTokenTypes.COLON) {
                    b.advanceLexer() // eat :
                    parseTypeReference(b)
                }
                fieldMarker.done(ZenScriptElementTypes.STRUCT_FIELD)
            } else if (b.tokenType == ZenScriptTokenTypes.COMMA) {
                b.advanceLexer() // eat comma
            } else {
                b.error("Expected struct field name")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun parseParameterList(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat (
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RPAREN) {
            parseParameter(b)
            if (b.tokenType == ZenScriptTokenTypes.COMMA) {
                b.advanceLexer()
            } else {
                break
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RPAREN) {
            b.advanceLexer()
        }
        marker.done(ZenScriptElementTypes.PARAMETER_LIST)
    }

    private fun parseParameter(b: PsiBuilder) {
        val marker = b.mark()
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat param name
        } else {
            b.error("Expected parameter name")
            marker.drop()
            return
        }
        if (b.tokenType == ZenScriptTokenTypes.COLON) {
            b.advanceLexer()
            parseTypeReference(b)
        }
        marker.done(ZenScriptElementTypes.PARAMETER)
    }

    private fun parseTypeReference(b: PsiBuilder) {
        val marker = b.mark()
        when {
            // Function type: (Type, ...) -> ReturnType
            b.tokenType == ZenScriptTokenTypes.LPAREN -> {
                b.advanceLexer() // eat (
                while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RPAREN) {
                    parseTypeReference(b)
                    if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer() else break
                }
                if (b.tokenType == ZenScriptTokenTypes.RPAREN) b.advanceLexer()
                if (b.tokenType == ZenScriptTokenTypes.ARROW) {
                    b.advanceLexer() // eat ->
                    parseTypeReference(b) // return type
                } else {
                    b.error("Expected '->' in function type")
                }
            }
            b.tokenType == ZenScriptTokenTypes.IDENTIFIER || b.tokenType == ZenScriptTokenTypes.CHAR_KW -> {
                b.advanceLexer()
                // Optional generic args <T, U>
                if (b.tokenType == ZenScriptTokenTypes.LT) {
                    skipGenericParams(b)
                }
                // Optional array suffix: T[]
                if (b.tokenType == ZenScriptTokenTypes.LBRACKET) {
                    b.advanceLexer() // eat [
                    if (b.tokenType == ZenScriptTokenTypes.RBRACKET) {
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
        marker.done(ZenScriptElementTypes.TYPE_REFERENCE)
    }

    private fun parseBlock(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            val before = b.currentOffset
            parseStatement(b)
            if (b.currentOffset == before) {
                // No progress — skip the unexpected token to avoid infinite loop
                b.error("Unexpected token: ${b.tokenType}")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
            b.advanceLexer()
        }
        marker.done(ZenScriptElementTypes.BLOCK)
    }

    private fun parseIfStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat if
        // condition
        if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            parseExpression(b)
            if (b.tokenType == ZenScriptTokenTypes.RPAREN) b.advanceLexer()
        } else {
            parseExpression(b)
        }
        // then branch
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            parseBlock(b)
        } else {
            parseStatement(b)
        }
        // optional else
        if (b.tokenType == ZenScriptTokenTypes.ELSE) {
            b.advanceLexer()
            if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
                parseBlock(b)
            } else {
                parseStatement(b)
            }
        }
        marker.done(ZenScriptElementTypes.IF_STATEMENT)
    }

    private fun parseWhileStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat while
        if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            parseExpression(b)
            if (b.tokenType == ZenScriptTokenTypes.RPAREN) b.advanceLexer()
        } else {
            parseExpression(b)
        }
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            parseBlock(b)
        } else {
            parseStatement(b)
        }
        marker.done(ZenScriptElementTypes.WHILE_STATEMENT)
    }

    private fun parseForStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat for
        // for (init; cond; update) { body }
        if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            // init: let/const declaration or expression statement
            if (b.tokenType == ZenScriptTokenTypes.LET || b.tokenType == ZenScriptTokenTypes.CONST) {
                parseVarDeclaration(b) // creates VAR_DECLARATION with identifier
            } else if (b.tokenType != ZenScriptTokenTypes.SEMICOLON) {
                parseExpression(b)
                eatOptionalSemicolon(b)
            }
            // condition
            if (b.tokenType != ZenScriptTokenTypes.SEMICOLON && b.tokenType != ZenScriptTokenTypes.RPAREN) {
                parseExpression(b)
            }
            eatOptionalSemicolon(b)
            // update
            if (b.tokenType != ZenScriptTokenTypes.RPAREN) {
                parseExpression(b)
                // Handle reassignment: expr = expr
                if (b.tokenType == ZenScriptTokenTypes.EQ) {
                    b.advanceLexer()
                    parseExpression(b)
                }
            }
            if (b.tokenType == ZenScriptTokenTypes.RPAREN) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            parseBlock(b)
        }
        marker.done(ZenScriptElementTypes.FOR_STATEMENT)
    }

    private fun parseReturnStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat return
        if (b.tokenType != null &&
            b.tokenType != ZenScriptTokenTypes.RBRACE &&
            b.tokenType != ZenScriptTokenTypes.SEMICOLON
        ) {
            parseExpression(b)
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.RETURN_STATEMENT)
    }

    private fun parseImportStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat import
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            parseImportSymbolList(b)
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
                b.advanceLexer() // eat }
            } else {
                b.error("Expected '}'")
            }
        } else {
            b.error("Expected '{'")
        }
        if (b.tokenType == ZenScriptTokenTypes.FROM) {
            b.advanceLexer() // eat from
            parseImportPath(b)
        } else {
            b.error("Expected 'from'")
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.IMPORT_STATEMENT)
    }

    private fun parseExportFromStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat export
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            parseImportSymbolList(b)
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
                b.advanceLexer() // eat }
            } else {
                b.error("Expected '}'")
            }
        } else {
            b.error("Expected '{'")
        }
        if (b.tokenType == ZenScriptTokenTypes.FROM) {
            b.advanceLexer() // eat from
            parseImportPath(b)
        } else {
            b.error("Expected 'from'")
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.EXPORT_FROM_STATEMENT)
    }

    private fun parseUseStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat use
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat enum name
        } else {
            b.error("Expected identifier")
        }
        if (b.tokenType == ZenScriptTokenTypes.DOT) {
            b.advanceLexer() // eat .
        } else {
            b.error("Expected '.'")
        }
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            parseImportSymbolList(b)
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
                b.advanceLexer() // eat }
            } else {
                b.error("Expected '}'")
            }
        } else {
            b.error("Expected '{'")
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.USE_STATEMENT)
    }

    private fun parseImportSymbolList(b: PsiBuilder) {
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) return // empty list
        parseImportSymbol(b)
        while (b.tokenType == ZenScriptTokenTypes.COMMA) {
            b.advanceLexer() // eat comma
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) break // trailing comma
            parseImportSymbol(b)
        }
    }

    private fun parseImportSymbol(b: PsiBuilder) {
        val marker = b.mark()
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected identifier")
            marker.drop()
            return
        }
        // Optional alias: as alias_name
        if (b.tokenType == ZenScriptTokenTypes.AS) {
            b.advanceLexer() // eat as
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                b.advanceLexer() // eat alias
            } else {
                b.error("Expected alias name")
            }
        }
        marker.done(ZenScriptElementTypes.IMPORT_SYMBOL)
    }

    private fun parseImportPath(b: PsiBuilder) {
        val marker = b.mark()
        if (b.tokenType == ZenScriptTokenTypes.STRING_LITERAL) {
            b.advanceLexer()
        } else {
            b.error("Expected string literal path")
            marker.drop()
            return
        }
        marker.done(ZenScriptElementTypes.IMPORT_PATH)
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
        if (b.tokenType == ZenScriptTokenTypes.EQ) {
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
        ZenScriptTokenTypes.OR_OR -> 0
        ZenScriptTokenTypes.AND_AND -> 1
        ZenScriptTokenTypes.EQ_EQ, ZenScriptTokenTypes.BANG_EQ -> 2
        ZenScriptTokenTypes.LT, ZenScriptTokenTypes.GT,
        ZenScriptTokenTypes.LT_EQ, ZenScriptTokenTypes.GT_EQ -> 3
        ZenScriptTokenTypes.PLUS, ZenScriptTokenTypes.MINUS -> 4
        ZenScriptTokenTypes.STAR, ZenScriptTokenTypes.SLASH,
        ZenScriptTokenTypes.PERCENT -> 5
        else -> null
    }

    private fun parseUnaryExpression(b: PsiBuilder) {
        // Unary prefix: !, -
        if (b.tokenType == ZenScriptTokenTypes.BANG || b.tokenType == ZenScriptTokenTypes.MINUS) {
            b.advanceLexer()
        }
        parsePrimaryExpression(b)
    }

    private fun parsePrimaryExpression(b: PsiBuilder) {
        when (b.tokenType) {
            ZenScriptTokenTypes.IDENTIFIER,
            ZenScriptTokenTypes.THIS_KW -> {
                val marker = b.mark()
                b.advanceLexer() // eat identifier / this
                marker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                parseSuffix(b)
            }
            ZenScriptTokenTypes.NUMBER_LITERAL,
            ZenScriptTokenTypes.STRING_LITERAL,
            ZenScriptTokenTypes.CHAR_LITERAL,
            ZenScriptTokenTypes.TRUE,
            ZenScriptTokenTypes.FALSE -> {
                b.advanceLexer()
            }
            ZenScriptTokenTypes.LPAREN -> {
                skipParenContent(b)
            }
            ZenScriptTokenTypes.LBRACKET -> {
                parseArrayLiteral(b)
            }
            ZenScriptTokenTypes.LBRACE -> {
                if (isLambdaStart(b)) parseLambdaExpression(b) else parseBlock(b)
            }
            ZenScriptTokenTypes.MATCH -> {
                parseMatchExpression(b)
            }
            ZenScriptTokenTypes.WHEN -> {
                parseWhenExpression(b)
            }
            ZenScriptTokenTypes.IF -> {
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
                ZenScriptTokenTypes.LPAREN -> {
                    // Function call
                    skipParenContent(b)
                }
                ZenScriptTokenTypes.DOT -> {
                    b.advanceLexer() // eat .
                    if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                        val marker = b.mark()
                        b.advanceLexer()
                        marker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                    }
                }
                ZenScriptTokenTypes.LBRACKET -> {
                    skipBracketContent(b)
                }
                ZenScriptTokenTypes.LBRACE -> {
                    // Struct literal: Name { field: value, ... }
                    parseStructLiteralBody(b)
                }
                ZenScriptTokenTypes.LT -> {
                    // Generic struct literal: Name<T, U> { field: value, ... }
                    // Speculatively skip generic args; if followed by '{' it's a struct literal.
                    val rollback = b.mark()
                    skipGenericParams(b)
                    if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
                        rollback.drop()
                        parseStructLiteralBody(b)
                    } else {
                        rollback.rollbackTo()
                        break
                    }
                }
                ZenScriptTokenTypes.QUEST_DOT -> {
                    val safeMarker = b.mark()
                    b.advanceLexer() // eat ?.
                    if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                        val refMarker = b.mark()
                        b.advanceLexer()
                        refMarker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                    }
                    safeMarker.done(ZenScriptElementTypes.SAFE_NAVIGATION)
                }
                ZenScriptTokenTypes.BANG_BANG -> {
                    val errMarker = b.mark()
                    b.advanceLexer() // eat !!
                    errMarker.done(ZenScriptElementTypes.ERROR_PROPAGATION)
                }
                else -> break
            }
        }
    }

    private fun parseStructLiteralBody(b: PsiBuilder) {
        if (b.tokenType != ZenScriptTokenTypes.LBRACE) return
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                val marker = b.mark()
                b.advanceLexer() // eat field name
                marker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                if (b.tokenType == ZenScriptTokenTypes.COLON) {
                    b.advanceLexer() // eat :
                    parseExpression(b)
                }
            }
            if (b.tokenType == ZenScriptTokenTypes.COMMA) {
                b.advanceLexer()
            } else if (b.tokenType != ZenScriptTokenTypes.RBRACE) {
                b.error("Expected ',' or '}'")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun parseMatchExpression(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat match
        parseExpression(b) // subject
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
                val armMarker = b.mark()
                parseMatchPattern(b)
                if (b.tokenType == ZenScriptTokenTypes.ARROW) {
                    b.advanceLexer() // eat ->
                    parseExpression(b)
                } else {
                    b.error("Expected '->'")
                }
                if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer()
                armMarker.done(ZenScriptElementTypes.MATCH_ARM)
            }
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) b.advanceLexer()
        }
        marker.done(ZenScriptElementTypes.MATCH_EXPRESSION)
    }

    private fun parseMatchPattern(b: PsiBuilder) {
        when (b.tokenType) {
            ZenScriptTokenTypes.ELSE -> b.advanceLexer()
            ZenScriptTokenTypes.NUMBER_LITERAL,
            ZenScriptTokenTypes.STRING_LITERAL,
            ZenScriptTokenTypes.CHAR_LITERAL,
            ZenScriptTokenTypes.TRUE,
            ZenScriptTokenTypes.FALSE -> b.advanceLexer()
            ZenScriptTokenTypes.IDENTIFIER -> {
                val nameMarker = b.mark()
                b.advanceLexer() // eat name
                when (b.tokenType) {
                    ZenScriptTokenTypes.DOT -> {
                        // EnumName.Variant or EnumName.Variant(payload bindings)
                        nameMarker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                        b.advanceLexer() // eat .
                        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                            val varMarker = b.mark()
                            b.advanceLexer()
                            varMarker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                        }
                        if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
                            parseEnumPayloadPattern(b)
                        }
                    }
                    ZenScriptTokenTypes.LBRACE -> {
                        // StructName { field: val, field2 }
                        nameMarker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                        parseStructPatternBody(b)
                    }
                    else -> {
                        // Plain binding identifier — binds the matched value to a variable
                        nameMarker.done(ZenScriptElementTypes.MATCH_BINDING)
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
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RPAREN) {
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                val bindMarker = b.mark()
                b.advanceLexer()
                bindMarker.done(ZenScriptElementTypes.MATCH_BINDING)
            } else {
                b.error("Expected binding name")
                b.advanceLexer()
            }
            if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.RPAREN) b.advanceLexer()
    }

    /** Parses `{ field: value, field2, ... }` in a struct pattern.
     *  `field: value` — valued field (reference + skip expression), `field2` alone — MATCH_BINDING. */
    private fun parseStructPatternBody(b: PsiBuilder) {
        b.advanceLexer() // eat {
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                val fieldMarker = b.mark()
                b.advanceLexer() // eat field name
                if (b.tokenType == ZenScriptTokenTypes.COLON) {
                    // field: value — reference expression, not a binding
                    fieldMarker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                    b.advanceLexer() // eat :
                    parseExpression(b)
                } else {
                    // bare field name — binds the field value to a variable
                    fieldMarker.done(ZenScriptElementTypes.MATCH_BINDING)
                }
            } else {
                b.error("Expected field name")
                b.advanceLexer()
            }
            if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) b.advanceLexer()
    }

    private fun parseScalarDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat scalar
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat name
        } else {
            b.error("Expected scalar type name")
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.SCALAR_DECLARATION)
    }

    private fun parseArrayLiteral(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat [
        if (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACKET) {
            parseExpression(b)
            when {
                // [expr; count] — repeat literal
                b.tokenType == ZenScriptTokenTypes.SEMICOLON -> {
                    b.advanceLexer() // eat ;
                    parseExpression(b) // eat count
                }
                // [expr, expr, ...] — list literal
                b.tokenType == ZenScriptTokenTypes.COMMA -> {
                    while (b.tokenType == ZenScriptTokenTypes.COMMA) {
                        b.advanceLexer()
                        if (b.tokenType == ZenScriptTokenTypes.RBRACKET) break
                        parseExpression(b)
                    }
                }
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACKET) {
            b.advanceLexer()
        } else {
            b.error("Expected ']'")
        }
        marker.done(ZenScriptElementTypes.ARRAY_LITERAL)
    }

    // --- Helpers ---

    private fun skipParenContent(b: PsiBuilder) {
        if (b.tokenType != ZenScriptTokenTypes.LPAREN) return
        b.advanceLexer() // eat (
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ZenScriptTokenTypes.LPAREN -> depth++
                ZenScriptTokenTypes.RPAREN -> depth--
                ZenScriptTokenTypes.IDENTIFIER -> {
                    val marker = b.mark()
                    b.advanceLexer()
                    marker.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                    continue
                }
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.RPAREN) {
            b.advanceLexer()
        }
    }

    private fun skipBraceContent(b: PsiBuilder) {
        if (b.tokenType != ZenScriptTokenTypes.LBRACE) return
        b.advanceLexer() // eat {
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ZenScriptTokenTypes.LBRACE -> depth++
                ZenScriptTokenTypes.RBRACE -> depth--
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) {
            b.advanceLexer()
        }
    }

    private fun skipBracketContent(b: PsiBuilder) {
        if (b.tokenType != ZenScriptTokenTypes.LBRACKET) return
        b.advanceLexer() // eat [
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ZenScriptTokenTypes.LBRACKET -> depth++
                ZenScriptTokenTypes.RBRACKET -> depth--
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACKET) {
            b.advanceLexer()
        }
    }

    private fun skipGenericParams(b: PsiBuilder) {
        if (b.tokenType != ZenScriptTokenTypes.LT) return
        b.advanceLexer() // eat <
        var depth = 1
        while (!b.eof() && depth > 0) {
            when (b.tokenType) {
                ZenScriptTokenTypes.LT -> depth++
                ZenScriptTokenTypes.GT -> depth--
            }
            if (depth > 0) b.advanceLexer()
        }
        if (b.tokenType == ZenScriptTokenTypes.GT) {
            b.advanceLexer()
        }
    }

    private fun eatOptionalSemicolon(b: PsiBuilder) {
        if (b.tokenType == ZenScriptTokenTypes.SEMICOLON) {
            b.advanceLexer()
        }
    }

    // --- New constructs ---

    private fun parseAtTarget(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat @
        // expect `target` identifier
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer()
        } else {
            b.error("Expected 'target' after '@'")
        }
        if (b.tokenType == ZenScriptTokenTypes.LPAREN) {
            b.advanceLexer() // eat (
            // condition expression (identifiers, ==, &&, ||, strings, !)
            parseExpression(b)
            if (b.tokenType == ZenScriptTokenTypes.RPAREN) b.advanceLexer()
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.AT_TARGET)
    }

    private fun parseTypeAliasDeclaration(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat type
        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
            b.advanceLexer() // eat alias name
        } else {
            b.error("Expected type alias name")
        }
        if (b.tokenType == ZenScriptTokenTypes.LT) {
            skipGenericParams(b)
        }
        if (b.tokenType == ZenScriptTokenTypes.EQ) {
            b.advanceLexer() // eat =
            parseTypeReference(b)
        } else {
            b.error("Expected '='")
        }
        eatOptionalSemicolon(b)
        marker.done(ZenScriptElementTypes.TYPE_ALIAS_DECLARATION)
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
        val result = if (b.tokenType == ZenScriptTokenTypes.ARROW) {
            true
        } else {
            // Try to parse: (ident (: Type)? ,)* ident (: Type)? ->
            var found = false
            loop@ while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
                if (b.tokenType != ZenScriptTokenTypes.IDENTIFIER) break@loop
                b.advanceLexer() // eat param name
                if (b.tokenType == ZenScriptTokenTypes.COLON) {
                    b.advanceLexer() // eat :
                    // skip type tokens: ident, optional <...>, optional []
                    if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER || b.tokenType == ZenScriptTokenTypes.CHAR_KW) {
                        b.advanceLexer()
                        if (b.tokenType == ZenScriptTokenTypes.LT) skipGenericParams(b)
                        if (b.tokenType == ZenScriptTokenTypes.LBRACKET) {
                            b.advanceLexer()
                            if (b.tokenType == ZenScriptTokenTypes.RBRACKET) b.advanceLexer()
                        }
                    }
                }
                when (b.tokenType) {
                    ZenScriptTokenTypes.ARROW -> { found = true; break@loop }
                    ZenScriptTokenTypes.COMMA -> b.advanceLexer()
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
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.ARROW && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                val paramMarker = b.mark()
                b.advanceLexer() // eat param name
                if (b.tokenType == ZenScriptTokenTypes.COLON) {
                    b.advanceLexer()
                    parseTypeReference(b)
                }
                paramMarker.done(ZenScriptElementTypes.LAMBDA_PARAM)
            }
            if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer() else break
        }
        if (b.tokenType == ZenScriptTokenTypes.ARROW) b.advanceLexer() // eat ->
        // Parse body statements
        while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
            val before = b.currentOffset
            parseStatement(b)
            if (b.currentOffset == before) {
                b.error("Unexpected token: ${b.tokenType}")
                b.advanceLexer()
            }
        }
        if (b.tokenType == ZenScriptTokenTypes.RBRACE) b.advanceLexer()
        marker.done(ZenScriptElementTypes.LAMBDA_EXPRESSION)
    }

    private fun parseWhenExpression(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat when
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
                val armMarker = b.mark()
                // condition or else
                if (b.tokenType == ZenScriptTokenTypes.ELSE) {
                    b.advanceLexer()
                } else {
                    parseExpression(b)
                }
                if (b.tokenType == ZenScriptTokenTypes.ARROW) {
                    b.advanceLexer() // eat ->
                    // arm body: declaration or expression
                    if (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE &&
                        b.tokenType != ZenScriptTokenTypes.COMMA) {
                        parseStatement(b)
                    }
                } else {
                    b.error("Expected '->'")
                }
                if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer()
                armMarker.done(ZenScriptElementTypes.WHEN_ARM)
            }
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) b.advanceLexer()
        }
        marker.done(ZenScriptElementTypes.WHEN_EXPRESSION)
    }

    private fun parseAsmStatement(b: PsiBuilder) {
        val marker = b.mark()
        b.advanceLexer() // eat asm
        if (b.tokenType == ZenScriptTokenTypes.LBRACE) {
            b.advanceLexer() // eat {
            while (!b.eof() && b.tokenType != ZenScriptTokenTypes.RBRACE) {
                when (b.tokenType) {
                    ZenScriptTokenTypes.IN_KW -> {
                        val bm = b.mark()
                        b.advanceLexer() // eat in
                        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) b.advanceLexer() // reg
                        if (b.tokenType == ZenScriptTokenTypes.EQ) b.advanceLexer()
                        parseExpression(b)
                        bm.done(ZenScriptElementTypes.ASM_BINDING)
                    }
                    ZenScriptTokenTypes.OUT_KW -> {
                        val bm = b.mark()
                        b.advanceLexer() // eat out
                        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) b.advanceLexer() // reg
                        if (b.tokenType == ZenScriptTokenTypes.EQ) b.advanceLexer()
                        if (b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                            val nm = b.mark()
                            b.advanceLexer()
                            nm.done(ZenScriptElementTypes.REFERENCE_EXPRESSION)
                        }
                        bm.done(ZenScriptElementTypes.ASM_BINDING)
                    }
                    ZenScriptTokenTypes.CLOBBER_KW -> {
                        val bm = b.mark()
                        b.advanceLexer() // eat clobber
                        while (!b.eof() && b.tokenType == ZenScriptTokenTypes.IDENTIFIER) {
                            b.advanceLexer()
                            if (b.tokenType == ZenScriptTokenTypes.COMMA) b.advanceLexer() else break
                        }
                        bm.done(ZenScriptElementTypes.ASM_BINDING)
                    }
                    ZenScriptTokenTypes.STRING_LITERAL -> {
                        b.advanceLexer() // assembly instruction string
                    }
                    else -> {
                        b.error("Unexpected token in asm block")
                        b.advanceLexer()
                    }
                }
            }
            if (b.tokenType == ZenScriptTokenTypes.RBRACE) b.advanceLexer()
        }
        marker.done(ZenScriptElementTypes.ASM_STATEMENT)
    }

}
