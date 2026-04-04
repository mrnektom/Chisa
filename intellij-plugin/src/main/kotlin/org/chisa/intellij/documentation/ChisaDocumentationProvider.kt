package org.chisa.intellij.documentation

import com.intellij.lang.documentation.AbstractDocumentationProvider
import com.intellij.openapi.util.text.StringUtil
import com.intellij.psi.PsiElement
import org.chisa.intellij.daemon.DaemonService
import org.chisa.intellij.psi.*

class ChisaDocumentationProvider : AbstractDocumentationProvider() {
    override fun generateDoc(element: PsiElement, originalElement: PsiElement?): String? {
        if (element !is ChisaNamedElement) return null
        val signature = getDeclarationSignature(element) ?: return null
        val base = "<pre>${StringUtil.escapeXmlEntities(signature)}</pre>"

        val ref = originalElement ?: element
        val file = ref.containingFile ?: return base
        val path = file.virtualFile?.path ?: return base
        val content = file.text ?: return base
        val offset = ref.textOffset
        val typeStr = DaemonService.getInstance(file.project).getClient()
            ?.hover(path, content, offset)
        return if (typeStr != null) "<b>Type:</b> ${StringUtil.escapeXmlEntities(typeStr)}<br>$base" else base
    }

    override fun getQuickNavigateInfo(element: PsiElement, originalElement: PsiElement?): String? {
        if (element !is ChisaNamedElement) return null
        return getDeclarationSignature(element)
    }

    private fun getDeclarationSignature(element: ChisaNamedElement): String? {
        val node = element.node
        val text = node.text

        return when (element) {
            is ChisaFnDeclaration -> {
                // Show up to the opening brace or = (the signature, not the body)
                val braceIdx = text.indexOf('{')
                val eqIdx = text.indexOf('=')
                val endIdx = when {
                    braceIdx >= 0 && eqIdx >= 0 -> minOf(braceIdx, eqIdx)
                    braceIdx >= 0 -> braceIdx
                    eqIdx >= 0 -> eqIdx
                    else -> text.length
                }
                text.substring(0, endIdx).trim()
            }
            is ChisaVarDeclaration -> {
                // Show "let/const name: Type" without the initializer body (keep short)
                val eqIdx = text.indexOf('=')
                if (eqIdx >= 0) {
                    val afterEq = text.substring(eqIdx + 1).trim()
                    // If initializer is short (< 40 chars), include it
                    if (afterEq.length <= 40) text.trim() else text.substring(0, eqIdx).trim()
                } else {
                    text.trim()
                }
            }
            is ChisaStructDeclaration -> {
                // Show "struct Name { fields }" — full text for short structs
                if (text.length <= 80) text.trim() else {
                    val braceIdx = text.indexOf('{')
                    if (braceIdx >= 0) text.substring(0, braceIdx).trim() + " { ... }" else text.trim()
                }
            }
            is ChisaEnumDeclaration -> {
                if (text.length <= 80) text.trim() else {
                    val braceIdx = text.indexOf('{')
                    if (braceIdx >= 0) text.substring(0, braceIdx).trim() + " { ... }" else text.trim()
                }
            }
            is ChisaParameter -> {
                text.trim()
            }
            is ChisaStructField -> {
                text.trim()
            }
            is ChisaScalarDeclaration -> {
                text.trim()
            }
            else -> null
        }
    }
}
