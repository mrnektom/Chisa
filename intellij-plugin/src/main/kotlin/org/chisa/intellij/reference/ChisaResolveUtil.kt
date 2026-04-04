package org.chisa.intellij.reference

import com.intellij.openapi.diagnostic.Logger
import com.intellij.openapi.roots.ProjectRootManager
import com.intellij.openapi.vfs.VfsUtilCore
import com.intellij.openapi.vfs.VirtualFile
import com.intellij.psi.PsiElement
import com.intellij.psi.PsiFile
import com.intellij.psi.PsiManager
import com.intellij.psi.TokenType
import com.intellij.psi.util.PsiTreeUtil
import org.chisa.intellij.ChisaFile
import org.chisa.intellij.psi.ChisaElementTypes
import org.chisa.intellij.psi.*
import org.chisa.intellij.settings.ChisaPreludeService

data class ProjectSymbol(val element: ChisaNamedElement, val relativePath: String)

object ChisaResolveUtil {
    private val LOG = Logger.getInstance(ChisaResolveUtil::class.java)
    fun resolveInScope(from: PsiElement, name: String): PsiElement? {
        var current: PsiElement? = from.parent
        while (current != null) {
            // Search siblings above `from` in the current scope
            for (child in current.children) {
                // Only look at declarations that come before the reference in the same scope,
                // unless we're at file level (forward references allowed)
                if (child === from || PsiTreeUtil.isAncestor(child, from, false)) break
                if (child is ChisaNamedElement && child.name == name) {
                    return child
                }
            }

            // If we're at file level, also search declarations after the reference (forward refs)
            if (current === from.containingFile) {
                for (child in current.children) {
                    if (child is ChisaNamedElement && child.name == name) {
                        return child
                    }
                }
            }

            // Check function parameters (only direct children of PARAMETER_LIST)
            if (current is ChisaFnDeclaration) {
                val paramList = current.node.findChildByType(ChisaElementTypes.PARAMETER_LIST)
                if (paramList != null) {
                    for (paramNode in paramList.getChildren(null)) {
                        val param = paramNode.psi
                        if (param is ChisaParameter && param.name == name) {
                            return param
                        }
                    }
                }
            }

            current = current.parent
        }

        // Fallback: resolve via imports
        val imported = resolveViaImports(from.containingFile, name)
        if (imported != null) return imported

        // Final fallback: resolve via prelude
        return resolveViaPrelude(from.project, name)
    }

    fun collectVariants(from: PsiElement): List<String> {
        val result = LinkedHashSet<String>()
        var current: PsiElement? = from.parent
        while (current != null) {
            for (child in current.children) {
                if (child is ChisaNamedElement) {
                    child.name?.let { result.add(it) }
                }
            }
            // Check function parameters
            if (current is ChisaFnDeclaration) {
                val paramList = current.node.findChildByType(ChisaElementTypes.PARAMETER_LIST)
                if (paramList != null) {
                    for (paramNode in paramList.getChildren(null)) {
                        val param = paramNode.psi
                        if (param is ChisaParameter) {
                            param.name?.let { result.add(it) }
                        }
                    }
                }
            }
            current = current.parent
        }
        // Also collect imported symbol names
        val importedVariants = mutableListOf<String>()
        collectImportedVariants(from.containingFile, importedVariants)
        result.addAll(importedVariants)
        // Also collect prelude symbol names
        collectPreludeVariants(from.project, result)
        return result.toList()
    }

    fun resolveImportPath(context: PsiElement, path: String): ChisaFile? {
        val containingFile = context.containingFile?.virtualFile ?: return null
        val dir = containingFile.parent ?: return null
        val targetVFile = dir.findFileByRelativePath(path) ?: return null
        val psiFile = PsiManager.getInstance(context.project).findFile(targetVFile)
        return psiFile as? ChisaFile
    }

    fun findExportedSymbol(
        file: PsiFile,
        name: String,
        visited: MutableSet<PsiFile> = mutableSetOf()
    ): ChisaNamedElement? {
        if (!visited.add(file)) return null // cycle prevention

        // Search top-level named elements in the file
        for (child in file.children) {
            if (child is ChisaNamedElement && child.name == name) {
                return child
            }
        }

        // Check export-from statements for re-exports (transitive)
        for (child in file.children) {
            if (child is ChisaExportFromStatement) {
                for (symbol in child.getImportSymbols()) {
                    val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                    if (visibleName == name) {
                        val path = child.getPath() ?: continue
                        val originalName = symbol.getOriginalName() ?: continue
                        val targetFile = resolveImportPath(child, path) ?: continue
                        return findExportedSymbol(targetFile, originalName, visited)
                    }
                }
            }
        }

        return null
    }

    fun resolveViaImports(file: PsiFile?, name: String): PsiElement? {
        if (file == null) return null

        for (child in file.children) {
            when (child) {
                is ChisaImportStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        if (visibleName == name) {
                            val path = child.getPath() ?: continue
                            val originalName = symbol.getOriginalName() ?: continue
                            val targetFile = resolveImportPath(child, path) ?: continue
                            return findExportedSymbol(targetFile, originalName)
                        }
                    }
                }
                is ChisaUseStatement -> {
                    for (symbol in child.getVariantSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        if (visibleName == name) {
                            val enumName = child.getEnumName() ?: continue
                            val originalName = symbol.getOriginalName() ?: continue
                            val enumDecl = resolveInLocalScope(file, enumName)
                                ?: resolveImportOrExportFrom(file, enumName)
                                ?: resolveViaPrelude(file.project, enumName)
                            if (enumDecl is ChisaEnumDeclaration) {
                                val variant = findEnumVariant(enumDecl, originalName)
                                if (variant != null) return variant
                            }
                        }
                    }
                }
                is ChisaExportFromStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        if (visibleName == name) {
                            val path = child.getPath() ?: continue
                            val originalName = symbol.getOriginalName() ?: continue
                            val targetFile = resolveImportPath(child, path) ?: continue
                            return findExportedSymbol(targetFile, originalName)
                        }
                    }
                }
            }
        }
        return null
    }

    fun findEnumVariant(enumDecl: ChisaEnumDeclaration, variantName: String): ChisaEnumVariant? {
        for (child in enumDecl.children) {
            if (child is ChisaEnumVariant && child.name == variantName) {
                return child
            }
        }
        return null
    }

    private fun resolveInLocalScope(file: PsiFile, name: String): PsiElement? {
        for (child in file.children) {
            if (child is ChisaNamedElement && child.name == name) {
                return child
            }
        }
        return null
    }

    private fun resolveImportOrExportFrom(file: PsiFile, name: String): PsiElement? {
        for (child in file.children) {
            when (child) {
                is ChisaImportStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        if (visibleName == name) {
                            val path = child.getPath() ?: continue
                            val originalName = symbol.getOriginalName() ?: continue
                            val targetFile = resolveImportPath(child, path) ?: continue
                            return findExportedSymbol(targetFile, originalName)
                        }
                    }
                }
                is ChisaExportFromStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        if (visibleName == name) {
                            val path = child.getPath() ?: continue
                            val originalName = symbol.getOriginalName() ?: continue
                            val targetFile = resolveImportPath(child, path) ?: continue
                            return findExportedSymbol(targetFile, originalName)
                        }
                    }
                }
            }
        }
        return null
    }

    fun collectVariantElements(from: PsiElement): List<ChisaNamedElement> {
        val seen = LinkedHashSet<String>()
        val result = mutableListOf<ChisaNamedElement>()
        fun addUnique(element: ChisaNamedElement) {
            val name = element.name ?: return
            if (seen.add(name)) result.add(element)
        }

        var current: PsiElement? = from.parent
        while (current != null) {
            for (child in current.children) {
                if (child is ChisaNamedElement) {
                    addUnique(child)
                }
            }
            // Check function parameters
            if (current is ChisaFnDeclaration) {
                val paramList = current.node.findChildByType(ChisaElementTypes.PARAMETER_LIST)
                if (paramList != null) {
                    for (paramNode in paramList.getChildren(null)) {
                        val param = paramNode.psi
                        if (param is ChisaParameter) {
                            addUnique(param)
                        }
                    }
                }
            }
            current = current.parent
        }
        collectImportedVariantElements(from.containingFile, result, seen)
        collectPreludeVariantElements(from.project, result, seen)
        return result
    }

    fun collectImportedVariantElements(file: PsiFile?, result: MutableList<ChisaNamedElement>, seen: MutableSet<String> = mutableSetOf()) {
        if (file == null) return
        for (child in file.children) {
            when (child) {
                is ChisaImportStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val name = symbol.name ?: continue
                        if (seen.add(name)) result.add(symbol)
                    }
                }
                is ChisaUseStatement -> {
                    for (symbol in child.getVariantSymbols()) {
                        val name = symbol.name ?: continue
                        if (seen.add(name)) result.add(symbol)
                    }
                }
                is ChisaExportFromStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val name = symbol.name ?: continue
                        if (seen.add(name)) result.add(symbol)
                    }
                }
            }
        }
    }

    fun findStructField(structDecl: ChisaStructDeclaration, fieldName: String): ChisaStructField? {
        for (child in structDecl.children) {
            if (child is ChisaStructField && child.name == fieldName) {
                return child
            }
        }
        return null
    }

    /**
     * Given a sibling just before a struct literal's LBRACE, finds the REFERENCE_EXPRESSION
     * for the struct name. Handles both plain (`Point { ... }`) and generic (`Pair<T, U> { ... }`)
     * struct literals by skipping backwards over `> TypeName (, TypeName)* <` tokens.
     */
    fun findStructNameBeforeLbrace(lbrace: PsiElement): ChisaReferenceExpression? {
        var node: PsiElement? = lbrace.prevSibling
        while (node != null && node.node.elementType == TokenType.WHITE_SPACE) node = node.prevSibling
        // Skip generic type args: > ... <
        if (node?.node?.elementType == ChisaTokenTypes.GT) {
            node = node.prevSibling
            while (node != null && node.node.elementType != ChisaTokenTypes.LT) node = node.prevSibling
            node = node?.prevSibling
            while (node != null && node.node.elementType == TokenType.WHITE_SPACE) node = node.prevSibling
        }
        return node as? ChisaReferenceExpression
    }

    /**
     * Resolves a field name in a struct literal (e.g. `x` in `Point { x: 3 }`).
     * Returns the [ChisaStructField] declaration, or null if not applicable.
     */
    fun resolveStructLiteralField(element: ChisaReferenceExpression): ChisaStructField? {
        // Check: is this REFERENCE_EXPRESSION followed by COLON?
        var next: PsiElement? = element.nextSibling
        while (next != null && next.node.elementType == TokenType.WHITE_SPACE) next = next.nextSibling
        if (next?.node?.elementType != ChisaTokenTypes.COLON) return null

        // Walk backwards to find the LBRACE
        var prev: PsiElement? = element.prevSibling
        while (prev != null && prev.node.elementType != ChisaTokenTypes.LBRACE) prev = prev.prevSibling
        if (prev == null) return null

        val structNameRef = findStructNameBeforeLbrace(prev) ?: return null
        val structDecl = resolveInScope(structNameRef, structNameRef.getReferenceName() ?: return null)
        if (structDecl !is ChisaStructDeclaration) return null

        val fieldName = element.getReferenceName() ?: return null
        return findStructField(structDecl, fieldName)
    }

    fun collectStructFields(structDecl: ChisaStructDeclaration): List<ChisaStructField> {
        return structDecl.children.filterIsInstance<ChisaStructField>()
    }

    fun collectEnumVariants(enumDecl: ChisaEnumDeclaration): List<ChisaEnumVariant> {
        return enumDecl.children.filterIsInstance<ChisaEnumVariant>()
    }

    private fun resolveViaPrelude(project: com.intellij.openapi.project.Project, name: String): PsiElement? {
        val preludeFile = project.getService(ChisaPreludeService::class.java)
            ?.getPreludeFile() ?: return null
        return findExportedSymbol(preludeFile, name)
    }

    private fun collectPreludeVariants(project: com.intellij.openapi.project.Project, result: MutableSet<String>) {
        val preludeFile = project.getService(ChisaPreludeService::class.java)
            ?.getPreludeFile() ?: return
        for (child in preludeFile.children) {
            if (child is ChisaNamedElement) {
                child.name?.let { result.add(it) }
            }
            if (child is ChisaExportFromStatement) {
                for (symbol in child.getImportSymbols()) {
                    val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                    visibleName?.let { result.add(it) }
                }
            }
        }
    }

    private fun collectPreludeVariantElements(project: com.intellij.openapi.project.Project, result: MutableList<ChisaNamedElement>, seen: MutableSet<String> = mutableSetOf()) {
        val preludeFile = project.getService(ChisaPreludeService::class.java)
            ?.getPreludeFile() ?: return
        for (child in preludeFile.children) {
            if (child is ChisaNamedElement) {
                val name = child.name ?: continue
                if (seen.add(name)) result.add(child)
            }
            if (child is ChisaExportFromStatement) {
                for (symbol in child.getImportSymbols()) {
                    val name = symbol.name ?: continue
                    if (seen.add(name)) result.add(symbol)
                }
            }
        }
    }

    fun collectProjectExportedSymbols(from: PsiFile, alreadySeen: Set<String>): List<ProjectSymbol> {
        val project = from.project
        val currentVFile = from.virtualFile ?: run {
            LOG.warn("Chisa project completion: from.virtualFile is null")
            return emptyList()
        }
        val result = mutableListOf<ProjectSymbol>()
        val psiManager = PsiManager.getInstance(project)

        val roots = ProjectRootManager.getInstance(project).contentRoots
        LOG.warn("Chisa project completion: contentRoots count = ${roots.size}, currentFile = ${currentVFile.path}")

        for (root in roots) {
            LOG.warn("Chisa project completion: scanning root = ${root.path}")
            VfsUtilCore.iterateChildrenRecursively(root, null) { vFile ->
                if (!vFile.isDirectory && vFile.extension == "zs" && vFile != currentVFile) {
                    LOG.warn("Chisa project completion: found .chisa file = ${vFile.path}")
                    val relativePath = computeRelativePath(currentVFile, vFile)
                    if (relativePath != null) {
                        val psiFile = psiManager.findFile(vFile)
                        if (psiFile != null) {
                            for (child in psiFile.children) {
                                if (child is ChisaNamedElement) {
                                    val name = child.name ?: return@iterateChildrenRecursively true
                                    if (!alreadySeen.contains(name)) {
                                        result.add(ProjectSymbol(child, relativePath))
                                    }
                                }
                            }
                        } else {
                            LOG.warn("Chisa project completion: psiManager.findFile returned null for ${vFile.path}")
                        }
                    } else {
                        LOG.warn("Chisa project completion: computeRelativePath returned null for ${vFile.path}")
                    }
                }
                true
            }
        }
        LOG.warn("Chisa project completion: total symbols collected = ${result.size}")
        return result
    }

    fun collectProjectZsFiles(from: VirtualFile, project: com.intellij.openapi.project.Project): List<Pair<VirtualFile, String>> {
        val result = mutableListOf<Pair<VirtualFile, String>>()
        val roots = ProjectRootManager.getInstance(project).contentRoots
        for (root in roots) {
            VfsUtilCore.iterateChildrenRecursively(root, null) { vFile ->
                if (!vFile.isDirectory && vFile.extension == "zs" && vFile != from) {
                    val rel = computeRelativePath(from, vFile)
                    if (rel != null) result.add(vFile to rel)
                }
                true
            }
        }
        return result
    }

    fun computeRelativePath(from: VirtualFile, to: VirtualFile): String? {
        val fromDir = from.parent ?: return null
        // Try direct relative path (to is under fromDir or its subdirectory)
        val direct = VfsUtilCore.getRelativePath(to, fromDir)
        if (direct != null) return "./$direct"
        // Walk up from fromDir to find a common ancestor
        var ancestor = fromDir.parent
        var upCount = 1
        while (ancestor != null) {
            val rel = VfsUtilCore.getRelativePath(to, ancestor)
            if (rel != null) {
                return "../".repeat(upCount) + rel
            }
            ancestor = ancestor.parent
            upCount++
        }
        return null
    }

    private fun collectImportedVariants(file: PsiFile?, result: MutableList<String>) {
        if (file == null) return
        for (child in file.children) {
            when (child) {
                is ChisaImportStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        visibleName?.let { result.add(it) }
                    }
                }
                is ChisaUseStatement -> {
                    for (symbol in child.getVariantSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        visibleName?.let { result.add(it) }
                    }
                }
                is ChisaExportFromStatement -> {
                    for (symbol in child.getImportSymbols()) {
                        val visibleName = symbol.getAlias() ?: symbol.getOriginalName()
                        visibleName?.let { result.add(it) }
                    }
                }
            }
        }
    }
}
