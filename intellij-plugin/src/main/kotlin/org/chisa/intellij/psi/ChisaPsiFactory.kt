package org.chisa.intellij.psi

import com.intellij.openapi.project.Project
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFileFactory
import org.chisa.intellij.ChisaFileType

object ChisaPsiFactory {
    fun createIdentifier(project: Project, name: String): PsiElement? {
        val file = PsiFileFactory.getInstance(project)
            .createFileFromText("dummy.chisa", ChisaFileType, "let $name = 0")
        // Navigate: file -> VAR_DECLARATION -> IDENTIFIER
        val varDecl = file.firstChild ?: return null
        return varDecl.node.findChildByType(ChisaTokenTypes.IDENTIFIER)?.psi
    }
}
