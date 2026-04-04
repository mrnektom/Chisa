package org.chisa.intellij

import com.intellij.lang.Language

object ChisaLanguage : Language("Chisa") {
    private fun readResolve(): Any = ChisaLanguage
}
