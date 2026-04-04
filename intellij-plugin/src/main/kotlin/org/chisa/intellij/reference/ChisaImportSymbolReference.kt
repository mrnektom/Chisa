package org.chisa.intellij.reference

import com.intellij.openapi.util.TextRange
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiReferenceBase
import org.chisa.intellij.psi.ChisaExportFromStatement
import org.chisa.intellij.psi.ChisaImportStatement
import org.chisa.intellij.psi.ChisaEnumDeclaration
import org.chisa.intellij.psi.ChisaImportSymbol
import org.chisa.intellij.psi.ChisaUseStatement

class ChisaImportSymbolReference(element: ChisaImportSymbol) :
    PsiReferenceBase<ChisaImportSymbol>(element, calculateRange(element)) {

    companion object {
        private fun calculateRange(element: ChisaImportSymbol): TextRange {
            // Range covers the original name (first identifier)
            val originalName = element.getOriginalName() ?: return TextRange(0, element.textLength)
            val text = element.text
            val start = text.indexOf(originalName)
            return if (start >= 0) TextRange(start, start + originalName.length) else TextRange(0, element.textLength)
        }
    }

    override fun resolve(): PsiElement? {
        val parent = element.parent
        val originalName = element.getOriginalName() ?: return null

        return when (parent) {
            is ChisaImportStatement -> {
                val path = parent.getPath() ?: return null
                val targetFile = ChisaResolveUtil.resolveImportPath(element, path) ?: return null
                ChisaResolveUtil.findExportedSymbol(targetFile, originalName)
            }
            is ChisaExportFromStatement -> {
                val path = parent.getPath() ?: return null
                val targetFile = ChisaResolveUtil.resolveImportPath(element, path) ?: return null
                ChisaResolveUtil.findExportedSymbol(targetFile, originalName)
            }
            is ChisaUseStatement -> {
                val enumName = parent.getEnumName() ?: return null
                val enumDecl = ChisaResolveUtil.resolveInScope(element, enumName) ?: return null
                if (enumDecl is ChisaEnumDeclaration) {
                    ChisaResolveUtil.findEnumVariant(enumDecl, originalName)
                } else {
                    null
                }
            }
            else -> null
        }
    }

    override fun getVariants(): Array<Any> = emptyArray()
}
