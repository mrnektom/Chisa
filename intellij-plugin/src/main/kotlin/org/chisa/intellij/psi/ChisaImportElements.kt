package org.chisa.intellij.psi

import com.intellij.extapi.psi.ASTWrapperPsiElement
import com.intellij.lang.ASTNode
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiReference
import com.intellij.psi.util.PsiTreeUtil
import org.chisa.intellij.reference.ChisaImportPathReference
import org.chisa.intellij.reference.ChisaImportSymbolReference

class ChisaImportStatement(node: ASTNode) : ASTWrapperPsiElement(node) {
    fun getPath(): String? = getImportPath()?.getPathString()

    fun getImportPath(): ChisaImportPath? =
        PsiTreeUtil.findChildOfType(this, ChisaImportPath::class.java)

    fun getImportSymbols(): List<ChisaImportSymbol> =
        PsiTreeUtil.getChildrenOfTypeAsList(this, ChisaImportSymbol::class.java)
}

class ChisaExportFromStatement(node: ASTNode) : ASTWrapperPsiElement(node) {
    fun getPath(): String? = getImportPath()?.getPathString()

    fun getImportPath(): ChisaImportPath? =
        PsiTreeUtil.findChildOfType(this, ChisaImportPath::class.java)

    fun getImportSymbols(): List<ChisaImportSymbol> =
        PsiTreeUtil.getChildrenOfTypeAsList(this, ChisaImportSymbol::class.java)
}

class ChisaUseStatement(node: ASTNode) : ASTWrapperPsiElement(node) {
    fun getEnumName(): String? {
        val identNode = node.findChildByType(ChisaTokenTypes.IDENTIFIER)
        return identNode?.text
    }

    fun getVariantSymbols(): List<ChisaImportSymbol> =
        PsiTreeUtil.getChildrenOfTypeAsList(this, ChisaImportSymbol::class.java)
}

class ChisaImportSymbol(node: ASTNode) : ChisaNamedElementImpl(node) {
    fun getOriginalName(): String? {
        val identifiers = node.getChildren(null)
            .filter { it.elementType == ChisaTokenTypes.IDENTIFIER }
        return identifiers.firstOrNull()?.text
    }

    fun getAlias(): String? {
        val identifiers = node.getChildren(null)
            .filter { it.elementType == ChisaTokenTypes.IDENTIFIER }
        return if (identifiers.size >= 2) identifiers[1].text else null
    }

    override fun getName(): String? = getAlias() ?: getOriginalName()

    override fun getNameIdentifier(): PsiElement? {
        val identifiers = node.getChildren(null)
            .filter { it.elementType == ChisaTokenTypes.IDENTIFIER }
        // If there's an alias, the name identifier is the alias (second identifier)
        return if (identifiers.size >= 2) identifiers[1].psi else identifiers.firstOrNull()?.psi
    }

    override fun getReference(): PsiReference = ChisaImportSymbolReference(this)
}

class ChisaImportPath(node: ASTNode) : ASTWrapperPsiElement(node) {
    fun getPathString(): String? {
        val stringNode = node.findChildByType(ChisaTokenTypes.STRING_LITERAL)
        val text = stringNode?.text ?: return null
        // Strip surrounding quotes (only if both are present)
        return if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
            text.substring(1, text.length - 1)
        } else if (text.startsWith('"') && text.length > 1) {
            text.substring(1) // Unclosed string — strip only opening quote
        } else {
            null
        }
    }

    override fun getReference(): PsiReference = ChisaImportPathReference(this)
}
