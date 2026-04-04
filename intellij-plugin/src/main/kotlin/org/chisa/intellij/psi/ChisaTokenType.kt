package org.chisa.intellij.psi

import com.intellij.psi.tree.IElementType
import org.chisa.intellij.ChisaLanguage

class ChisaTokenType(debugName: String) : IElementType(debugName, ChisaLanguage) {
    override fun toString(): String = "ChisaTokenType.${super.toString()}"
}
