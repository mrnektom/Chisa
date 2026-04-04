package org.chisa.intellij.parser

import com.intellij.extapi.psi.ASTWrapperPsiElement
import com.intellij.lang.ASTNode
import com.intellij.lang.ParserDefinition
import com.intellij.lang.PsiParser
import com.intellij.lexer.Lexer
import com.intellij.openapi.project.Project
import com.intellij.psi.FileViewProvider
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFile
import com.intellij.psi.tree.IFileElementType
import com.intellij.psi.tree.TokenSet
import org.chisa.intellij.ChisaFile
import org.chisa.intellij.ChisaLanguage
import org.chisa.intellij.lexer.ChisaLexer
import org.chisa.intellij.psi.*

class ChisaParserDefinition : ParserDefinition {
    companion object {
        val FILE = IFileElementType(ChisaLanguage)
    }

    override fun createLexer(project: Project?): Lexer = ChisaLexer()
    override fun createParser(project: Project?): PsiParser = ChisaParser()
    override fun getFileNodeType(): IFileElementType = FILE
    override fun getCommentTokens(): TokenSet = ChisaTokenSets.COMMENTS
    override fun getStringLiteralElements(): TokenSet = ChisaTokenSets.STRINGS
    override fun getWhitespaceTokens(): TokenSet = ChisaTokenSets.WHITE_SPACES

    override fun createElement(node: ASTNode): PsiElement = when (node.elementType) {
        ChisaElementTypes.VAR_DECLARATION -> ChisaVarDeclaration(node)
        ChisaElementTypes.FN_DECLARATION -> ChisaFnDeclaration(node)
        ChisaElementTypes.STRUCT_DECLARATION -> ChisaStructDeclaration(node)
        ChisaElementTypes.ENUM_DECLARATION -> ChisaEnumDeclaration(node)
        ChisaElementTypes.ENUM_VARIANT -> ChisaEnumVariant(node)
        ChisaElementTypes.STRUCT_FIELD -> ChisaStructField(node)
        ChisaElementTypes.PARAMETER -> ChisaParameter(node)
        ChisaElementTypes.REFERENCE_EXPRESSION -> ChisaReferenceExpression(node)
        ChisaElementTypes.TYPE_REFERENCE -> ChisaTypeReferenceElement(node)
        ChisaElementTypes.IMPORT_STATEMENT -> ChisaImportStatement(node)
        ChisaElementTypes.EXPORT_FROM_STATEMENT -> ChisaExportFromStatement(node)
        ChisaElementTypes.USE_STATEMENT -> ChisaUseStatement(node)
        ChisaElementTypes.IMPORT_SYMBOL -> ChisaImportSymbol(node)
        ChisaElementTypes.IMPORT_PATH -> ChisaImportPath(node)
        ChisaElementTypes.RETURN_STATEMENT -> ChisaReturnStatement(node)
        ChisaElementTypes.SCALAR_DECLARATION -> ChisaScalarDeclaration(node)
        ChisaElementTypes.MATCH_BINDING -> ChisaMatchBinding(node)
        else -> ASTWrapperPsiElement(node)
    }

    override fun createFile(viewProvider: FileViewProvider): PsiFile = ChisaFile(viewProvider)
}
