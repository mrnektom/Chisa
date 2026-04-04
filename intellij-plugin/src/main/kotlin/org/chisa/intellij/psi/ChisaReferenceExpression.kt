package org.chisa.intellij.psi

import com.intellij.extapi.psi.ASTWrapperPsiElement
import com.intellij.lang.ASTNode
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiReference
import org.chisa.intellij.reference.ChisaReference

class ChisaReferenceExpression(node: ASTNode) : ASTWrapperPsiElement(node) {
    override fun getReference(): PsiReference = ChisaReference(this)

    fun getReferenceName(): String? = node.findChildByType(ChisaTokenTypes.IDENTIFIER)?.text

    fun setName(name: String): PsiElement {
        val newIdentifier = ChisaPsiFactory.createIdentifier(project, name)
        if (newIdentifier != null) {
            val identifierNode = node.findChildByType(ChisaTokenTypes.IDENTIFIER)
            if (identifierNode != null) {
                identifierNode.psi.replace(newIdentifier)
            }
        }
        return this
    }
}
