package org.chisa.intellij

import com.intellij.extapi.psi.PsiFileBase
import com.intellij.openapi.fileTypes.FileType
import com.intellij.psi.FileViewProvider

class ChisaFile(viewProvider: FileViewProvider) : PsiFileBase(viewProvider, ChisaLanguage) {
    override fun getFileType(): FileType = ChisaFileType
    override fun toString(): String = "Chisa File"
}
