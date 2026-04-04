package org.chisa.intellij.reference

import com.intellij.openapi.util.TextRange
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiReferenceBase
import org.chisa.intellij.psi.ChisaTypeReferenceElement

class ChisaTypeReference(element: ChisaTypeReferenceElement) :
    PsiReferenceBase<ChisaTypeReferenceElement>(element, calculateRange(element)) {

    companion object {
        private fun calculateRange(element: ChisaTypeReferenceElement): TextRange {
            val name = element.getReferenceName() ?: return TextRange(0, element.textLength)
            val text = element.text
            val start = text.indexOf(name)
            return if (start >= 0) TextRange(start, start + name.length) else TextRange(0, element.textLength)
        }
    }

    override fun resolve(): PsiElement? {
        val name = element.getReferenceName() ?: return null
        return ChisaResolveUtil.resolveInScope(element, name)
    }

    override fun getVariants(): Array<Any> {
        return ChisaResolveUtil.collectVariants(element).toTypedArray()
    }
}
