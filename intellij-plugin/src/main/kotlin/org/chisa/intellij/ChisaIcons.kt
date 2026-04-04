package org.chisa.intellij

import com.intellij.openapi.util.IconLoader
import javax.swing.Icon

object ChisaIcons {
    @JvmField
    val FILE: Icon = IconLoader.getIcon("/icons/chisa.svg", ChisaIcons::class.java)
}
