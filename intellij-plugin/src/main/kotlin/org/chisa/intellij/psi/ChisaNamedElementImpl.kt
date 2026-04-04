package org.chisa.intellij.psi

import com.intellij.extapi.psi.ASTWrapperPsiElement
import com.intellij.lang.ASTNode
import com.intellij.psi.PsiElement

abstract class ChisaNamedElementImpl(node: ASTNode) : ASTWrapperPsiElement(node), ChisaNamedElement {
    override fun getNameIdentifier(): PsiElement? =
        node.findChildByType(ChisaTokenTypes.IDENTIFIER)?.psi

    override fun getName(): String? = nameIdentifier?.text

    override fun setName(name: String): PsiElement {
        val identifier = nameIdentifier ?: return this
        val newIdentifier = ChisaPsiFactory.createIdentifier(project, name)
        if (newIdentifier != null) {
            identifier.replace(newIdentifier)
        }
        return this
    }

    override fun getTextOffset(): Int = nameIdentifier?.textOffset ?: super.getTextOffset()
}

class ChisaVarDeclaration(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaFnDeclaration(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaStructDeclaration(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaEnumDeclaration(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaParameter(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaEnumVariant(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaStructField(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaScalarDeclaration(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaMatchBinding(node: ASTNode) : ChisaNamedElementImpl(node)
class ChisaReturnStatement(node: ASTNode) : ASTWrapperPsiElement(node)
