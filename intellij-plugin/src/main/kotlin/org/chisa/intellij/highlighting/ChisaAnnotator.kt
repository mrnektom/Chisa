package org.chisa.intellij.highlighting

import com.intellij.lang.ASTNode
import com.intellij.lang.annotation.AnnotationHolder
import com.intellij.lang.annotation.Annotator
import com.intellij.lang.annotation.HighlightSeverity
import com.intellij.lang.injection.InjectedLanguageManager
import com.intellij.openapi.editor.colors.TextAttributesKey
import com.intellij.psi.PsiElement
import org.chisa.intellij.psi.ChisaElementTypes
import org.chisa.intellij.psi.ChisaEnumVariant
import org.chisa.intellij.psi.ChisaFnDeclaration
import org.chisa.intellij.psi.ChisaReferenceExpression
import org.chisa.intellij.psi.ChisaStructField
import org.chisa.intellij.psi.ChisaTokenTypes

class ChisaAnnotator : Annotator {
    override fun annotate(element: PsiElement, holder: AnnotationHolder) {
        if (InjectedLanguageManager.getInstance(element.project).isInjectedFragment(element.containingFile)) return
        if (element.node.elementType == ChisaElementTypes.EXTENSION_FN_DECLARATION) {
            highlightExtensionFunctionName(element, holder)
            return
        }

        when (element) {
            is ChisaFnDeclaration -> highlightNameIdentifier(element, holder, ChisaSyntaxHighlighter.FUNCTION_NAME)
            is ChisaStructField -> highlightNameIdentifier(element, holder, ChisaSyntaxHighlighter.FIELD_NAME)
            is ChisaEnumVariant -> highlightNameIdentifier(element, holder, ChisaSyntaxHighlighter.ENUM_VARIANT_NAME)
            is ChisaReferenceExpression -> annotateReference(element, holder)
        }
    }

    private fun highlightNameIdentifier(element: PsiElement, holder: AnnotationHolder, key: TextAttributesKey) {
        val nameNode = element.node.findChildByType(ChisaTokenTypes.IDENTIFIER) ?: return
        holder.newSilentAnnotation(HighlightSeverity.INFORMATION)
            .range(nameNode.psi)
            .textAttributes(key)
            .create()
    }

    private fun highlightExtensionFunctionName(element: PsiElement, holder: AnnotationHolder) {
        val nameNode = findExtensionFunctionNameNode(element.node) ?: return
        holder.newSilentAnnotation(HighlightSeverity.INFORMATION)
            .range(nameNode.psi)
            .textAttributes(ChisaSyntaxHighlighter.FUNCTION_NAME)
            .create()
    }

    private fun findExtensionFunctionNameNode(node: ASTNode): ASTNode? {
        var current = node.firstChildNode
        var sawDot = false

        while (current != null && current.elementType != ChisaTokenTypes.LPAREN) {
            when (current.elementType) {
                ChisaTokenTypes.DOT -> sawDot = true
                ChisaTokenTypes.IDENTIFIER -> if (sawDot) return current
            }
            current = current.treeNext
        }

        return null
    }

    private fun annotateReference(element: ChisaReferenceExpression, holder: AnnotationHolder) {
        val resolved = element.reference.resolve() ?: return
        val identifierNode = element.node.findChildByType(ChisaTokenTypes.IDENTIFIER) ?: return

        val key = when (resolved) {
            is ChisaFnDeclaration -> ChisaSyntaxHighlighter.FUNCTION_CALL
            is ChisaStructField -> ChisaSyntaxHighlighter.FIELD_NAME
            is ChisaEnumVariant -> ChisaSyntaxHighlighter.ENUM_VARIANT_NAME
            else -> return
        }

        holder.newSilentAnnotation(HighlightSeverity.INFORMATION)
            .range(identifierNode.psi)
            .textAttributes(key)
            .create()
    }
}
