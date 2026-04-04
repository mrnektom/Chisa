package org.chisa.intellij

import com.intellij.openapi.fileTypes.LanguageFileType
import javax.swing.Icon

object ChisaFileType : LanguageFileType(ChisaLanguage) {
    override fun getName(): String = "Chisa"
    override fun getDescription(): String = "Chisa language file"
    override fun getDefaultExtension(): String = "zs"
    override fun getIcon(): Icon = ChisaIcons.FILE
}
