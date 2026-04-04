package org.chisa.intellij.structure

import com.intellij.ide.structureView.*
import com.intellij.ide.structureView.impl.common.PsiTreeElementBase
import com.intellij.ide.util.treeView.smartTree.Sorter
import com.intellij.lang.PsiStructureViewFactory
import com.intellij.openapi.editor.Editor
import com.intellij.psi.PsiFile
import org.chisa.intellij.ChisaFile
import org.chisa.intellij.ChisaIcons
import org.chisa.intellij.psi.*
import javax.swing.Icon

class ChisaStructureViewFactory : PsiStructureViewFactory {
    override fun getStructureViewBuilder(psiFile: PsiFile): StructureViewBuilder? {
        if (psiFile !is ChisaFile) return null
        return object : TreeBasedStructureViewBuilder() {
            override fun createStructureViewModel(editor: Editor?): StructureViewModel {
                return ChisaStructureViewModel(psiFile)
            }
        }
    }
}

private class ChisaStructureViewModel(file: ChisaFile) :
    StructureViewModelBase(file, ChisaFileStructureViewElement(file)),
    StructureViewModel.ElementInfoProvider {

    override fun getSorters(): Array<Sorter> = arrayOf(Sorter.ALPHA_SORTER)
    override fun isAlwaysShowsPlus(element: StructureViewTreeElement): Boolean = false
    override fun isAlwaysLeaf(element: StructureViewTreeElement): Boolean {
        val value = (element as? PsiTreeElementBase<*>)?.value
        return value !is ChisaStructDeclaration && value !is ChisaEnumDeclaration
    }
}

private class ChisaFileStructureViewElement(private val file: ChisaFile) :
    PsiTreeElementBase<ChisaFile>(file) {

    override fun getPresentableText(): String? = file.name

    override fun getChildrenBase(): Collection<StructureViewTreeElement> {
        val result = mutableListOf<StructureViewTreeElement>()
        for (child in file.children) {
            if (child is ChisaNamedElement) {
                result.add(ChisaDeclarationStructureViewElement(child))
            }
        }
        return result
    }
}

private class ChisaDeclarationStructureViewElement(
    private val element: ChisaNamedElement
) : PsiTreeElementBase<ChisaNamedElement>(element) {

    override fun getPresentableText(): String {
        val kind = when (element) {
            is ChisaFnDeclaration -> "fn"
            is ChisaStructDeclaration -> "struct"
            is ChisaEnumDeclaration -> "enum"
            is ChisaVarDeclaration -> "let"
            else -> ""
        }
        return "$kind ${element.name ?: "?"}"
    }

    override fun getIcon(open: Boolean): Icon = ChisaIcons.FILE

    override fun getChildrenBase(): Collection<StructureViewTreeElement> {
        val result = mutableListOf<StructureViewTreeElement>()
        for (child in element.children) {
            if (child is ChisaNamedElement) {
                result.add(ChisaDeclarationStructureViewElement(child))
            }
        }
        return result
    }
}
