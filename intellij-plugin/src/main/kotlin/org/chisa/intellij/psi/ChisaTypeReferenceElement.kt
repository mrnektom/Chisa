package org.chisa.intellij.psi

import com.intellij.extapi.psi.ASTWrapperPsiElement
import com.intellij.lang.ASTNode
import com.intellij.psi.PsiReference
import org.chisa.intellij.reference.ChisaTypeReference

class ChisaTypeReferenceElement(node: ASTNode) : ASTWrapperPsiElement(node) {
    override fun getReference(): PsiReference = ChisaTypeReference(this)

    fun getReferenceName(): String? {
        val identifierNode = node.findChildByType(ChisaTokenTypes.IDENTIFIER)
        return identifierNode?.text
    }
}
