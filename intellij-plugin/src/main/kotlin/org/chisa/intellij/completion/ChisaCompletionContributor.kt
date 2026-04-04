package org.chisa.intellij.completion

import com.intellij.codeInsight.completion.*
import com.intellij.codeInsight.lookup.LookupElementBuilder
import com.intellij.lang.ASTNode
import com.intellij.openapi.command.WriteCommandAction
import com.intellij.openapi.diagnostic.Logger
import com.intellij.patterns.PlatformPatterns
import com.intellij.psi.PsiDocumentManager
import com.intellij.psi.PsiElement
import com.intellij.psi.TokenType
import com.intellij.psi.util.PsiTreeUtil
import com.intellij.util.ProcessingContext
import com.intellij.icons.AllIcons
import org.chisa.intellij.ChisaFile
import org.chisa.intellij.ChisaLanguage
import org.chisa.intellij.daemon.DaemonService
import org.chisa.intellij.psi.*
import org.chisa.intellij.reference.ChisaResolveUtil

class ChisaCompletionContributor : CompletionContributor() {
    init {
        // 4a. Identifier completion in expressions
        extend(
            CompletionType.BASIC,
            PlatformPatterns.psiElement()
                .withLanguage(ChisaLanguage),
            IdentifierCompletionProvider()
        )
    }

    private class IdentifierCompletionProvider : CompletionProvider<CompletionParameters>() {
        companion object {
            private val LOG = Logger.getInstance(IdentifierCompletionProvider::class.java)
            private val KEYWORDS = listOf(
                "let", "const", "fn", "if", "else", "while", "for", "return",
                "enum", "struct", "import", "use", "export", "break", "continue",
                "match", "true", "false", "external", "scalar",
                "when", "asm", "type"
            )
            private val BUILTIN_TYPES = listOf("number", "string", "boolean", "Unit", "char", "long", "short", "byte", "Pointer")
            private val BUILTIN_OPS = listOf(
                Triple("ptr", "(expr)", "Pointer<T>"),
                Triple("deref", "(pointer)", "T"),
                Triple("alloc", "(size)", "Pointer<T>"),
                Triple("free", "(pointer, size)", "void")
            )
        }

        override fun addCompletions(
            parameters: CompletionParameters,
            context: ProcessingContext,
            result: CompletionResultSet
        ) {
            val position = parameters.position
            val parent = position.parent
            val originalFile = parameters.originalFile as? ChisaFile
            LOG.warn("Chisa completion: position=${position::class.simpleName}, parent=${parent::class.simpleName}(${parent.node.elementType})")

            when {
                // 4c. Dot-access completion (member access)
                parent is ChisaReferenceExpression && isDotAccess(parent) -> {
                    addDotCompletions(parent, result)
                }
                // Struct literal field completion
                parent is ChisaReferenceExpression && isStructLiteralContext(parent) -> {
                    addStructLiteralFieldCompletions(parent, result)
                }
                // 4b. Type annotation completion
                parent is ChisaTypeReferenceElement -> {
                    addTypeCompletions(position, result)
                    if (originalFile != null) addProjectSymbolCompletions(originalFile, result, typesOnly = true)
                }
                // Import symbol completion: import { <caret> } from "./file.chisa"
                parent is ChisaImportSymbol && parent.parent is ChisaImportStatement -> {
                    addImportSymbolCompletions(parent.parent as ChisaImportStatement, originalFile, result)
                }
                // 4e. Use statement variant completion
                parent is ChisaImportSymbol && parent.parent is ChisaUseStatement -> {
                    addUseVariantCompletions(parent.parent as ChisaUseStatement, result)
                }
                // 4f. Import path completion
                parent is ChisaImportPath -> {
                    addImportPathCompletions(parent, originalFile, result)
                }
                // 4a. General identifier completion + 4d. Keywords
                parent is ChisaReferenceExpression -> {
                    addIdentifierCompletions(position, result)
                    if (originalFile != null) addProjectSymbolCompletions(originalFile, result)
                    addDaemonCompletions(parameters, result)
                    addKeywordCompletions(result)
                }
                // Top-level keyword completion (when typing outside any expression)
                parent is ChisaFile || isTopLevelContext(position) -> {
                    addKeywordCompletions(result)
                    if (originalFile != null) addProjectSymbolCompletions(originalFile, result)
                }
            }
        }

        private fun skipWhitespacePrev(node: ASTNode?): ASTNode? {
            var current = node
            while (current != null && (current.elementType == TokenType.WHITE_SPACE ||
                        current.elementType == ChisaTokenTypes.WHITE_SPACE)) {
                current = current.treePrev
            }
            return current
        }

        private fun isDotAccess(refExpr: ChisaReferenceExpression): Boolean {
            val prevNode = skipWhitespacePrev(refExpr.node.treePrev)
            return prevNode != null && prevNode.elementType == ChisaTokenTypes.DOT
        }

        private fun isTopLevelContext(position: PsiElement): Boolean {
            var current = position.parent
            while (current != null) {
                if (current is ChisaFile) return true
                if (current is ChisaNamedElement) return false
                current = current.parent
            }
            return false
        }

        // 4a. Identifier completions
        private fun addIdentifierCompletions(position: PsiElement, result: CompletionResultSet) {
            val variants = ChisaResolveUtil.collectVariantElements(position)
            for (element in variants) {
                val name = element.name ?: continue
                val lookup = when (element) {
                    is ChisaFnDeclaration -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Function)
                        .withTailText("()", true)
                    is ChisaVarDeclaration -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Variable)
                    is ChisaStructDeclaration -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Class)
                    is ChisaEnumDeclaration -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Enum)
                    is ChisaEnumVariant -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Field)
                    is ChisaMatchBinding -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Variable)
                    is ChisaParameter -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Parameter)
                    is ChisaImportSymbol -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Include)
                    else -> LookupElementBuilder.create(name)
                }
                result.addElement(lookup)
            }
            // Built-in pointer operations
            for ((opName, tailText, retType) in BUILTIN_OPS) {
                result.addElement(
                    LookupElementBuilder.create(opName)
                        .withIcon(AllIcons.Nodes.Function)
                        .withTailText(tailText, true)
                        .withTypeText(retType, true)
                )
            }
        }

        // 4b. Type completions
        private fun addTypeCompletions(position: PsiElement, result: CompletionResultSet) {
            // Add builtin types
            for (typeName in BUILTIN_TYPES) {
                val lookup = if (typeName == "Pointer")
                    LookupElementBuilder.create(typeName).bold().withTailText("<T>", true)
                else
                    LookupElementBuilder.create(typeName).bold()
                result.addElement(lookup)
            }
            // Add user-defined types (structs and enums)
            val variants = ChisaResolveUtil.collectVariantElements(position)
            for (element in variants) {
                val name = element.name ?: continue
                val lookup = when (element) {
                    is ChisaStructDeclaration -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Class)
                    is ChisaEnumDeclaration -> LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Enum)
                    else -> continue
                }
                result.addElement(lookup)
            }
        }

        private fun isStructLiteralContext(refExpr: ChisaReferenceExpression): Boolean {
            if (findStructDeclForLiteral(refExpr) == null) return false
            // If the previous non-whitespace token is COLON, we're in value position (e.g. `x: <caret>`)
            var prev: PsiElement? = refExpr.prevSibling
            while (prev != null && prev.node.elementType == TokenType.WHITE_SPACE) {
                prev = prev.prevSibling
            }
            if (prev?.node?.elementType == ChisaTokenTypes.COLON) return false
            return true
        }

        private fun findStructDeclForLiteral(refExpr: ChisaReferenceExpression): ChisaStructDeclaration? {
            // Walk backwards to find the opening LBRACE
            var prev: PsiElement? = refExpr.prevSibling
            while (prev != null && prev.node.elementType != ChisaTokenTypes.LBRACE) {
                prev = prev.prevSibling
            }
            if (prev == null) return null
            val structNameRef = ChisaResolveUtil.findStructNameBeforeLbrace(prev) ?: return null
            return structNameRef.reference.resolve() as? ChisaStructDeclaration
        }

        private fun addStructLiteralFieldCompletions(refExpr: ChisaReferenceExpression, result: CompletionResultSet) {
            val structDecl = findStructDeclForLiteral(refExpr) ?: return
            for (field in ChisaResolveUtil.collectStructFields(structDecl)) {
                val name = field.name ?: continue
                result.addElement(
                    LookupElementBuilder.create(name)
                        .withIcon(AllIcons.Nodes.Field)
                        .withTailText(": ", true)
                        .withInsertHandler { context, _ ->
                            val offset = context.tailOffset
                            context.document.insertString(offset, ": ")
                            context.editor.caretModel.moveToOffset(offset + 2)
                        }
                )
            }
            result.stopHere()
        }

        // 4c. Dot-access completions (member access)
        private fun addDotCompletions(refExpr: ChisaReferenceExpression, result: CompletionResultSet) {
            // Find the expression before the dot, skipping whitespace
            val dot = skipWhitespacePrev(refExpr.node.treePrev) ?: return
            if (dot.elementType != ChisaTokenTypes.DOT) return
            val beforeDot = skipWhitespacePrev(dot.treePrev) ?: return
            val beforeDotPsi = beforeDot.psi

            val resolved = when (beforeDotPsi) {
                is ChisaReferenceExpression -> beforeDotPsi.reference.resolve()
                else -> null
            }

            when (resolved) {
                is ChisaEnumDeclaration -> {
                    for (variant in ChisaResolveUtil.collectEnumVariants(resolved)) {
                        val name = variant.name ?: continue
                        result.addElement(
                            LookupElementBuilder.create(name)
                                .withIcon(AllIcons.Nodes.Field)
                        )
                    }
                }
                is ChisaStructDeclaration -> {
                    for (field in ChisaResolveUtil.collectStructFields(resolved)) {
                        val name = field.name ?: continue
                        result.addElement(
                            LookupElementBuilder.create(name)
                                .withIcon(AllIcons.Nodes.Field)
                        )
                    }
                }
                is ChisaVarDeclaration, is ChisaParameter -> {
                    // Resolve the type via the type reference's own reference
                    val typeRef = PsiTreeUtil.findChildOfType(resolved, ChisaTypeReferenceElement::class.java)
                    val typeDecl = typeRef?.reference?.resolve()
                    if (typeDecl is ChisaStructDeclaration) {
                        for (field in ChisaResolveUtil.collectStructFields(typeDecl)) {
                            val name = field.name ?: continue
                            result.addElement(
                                LookupElementBuilder.create(name)
                                    .withIcon(AllIcons.Nodes.Field)
                            )
                        }
                    }
                }
            }
        }

        // 4g. Project-wide symbol completions with auto-import
        private fun addProjectSymbolCompletions(
            file: ChisaFile,
            result: CompletionResultSet,
            typesOnly: Boolean = false
        ) {
            val inScope = ChisaResolveUtil.collectVariantElements(file)
                .mapNotNullTo(HashSet()) { it.name }

            val projectSymbols = ChisaResolveUtil.collectProjectExportedSymbols(file, inScope)
            LOG.warn("Chisa project completion: projectSymbols count = ${projectSymbols.size}")

            for ((element, path) in projectSymbols) {
                if (typesOnly && element !is ChisaStructDeclaration && element !is ChisaEnumDeclaration) continue
                val name = element.name ?: continue
                val fileName = path.substringAfterLast("/")
                val lookup = when (element) {
                    is ChisaFnDeclaration ->
                        LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Function)
                            .withTailText("()  $fileName", true)
                    is ChisaStructDeclaration ->
                        LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Class)
                            .withTailText("  $fileName", true)
                    is ChisaEnumDeclaration ->
                        LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Enum)
                            .withTailText("  $fileName", true)
                    is ChisaVarDeclaration ->
                        LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Variable)
                            .withTailText("  $fileName", true)
                    else -> LookupElementBuilder.create(name).withTailText("  $fileName", true)
                }.withInsertHandler { context, _ ->
                    addImportIfMissing(
                        context.file as? ChisaFile ?: return@withInsertHandler,
                        name, path
                    )
                }
                result.addElement(lookup)
            }
        }

        private fun addImportIfMissing(file: ChisaFile, symbolName: String, path: String) {
            // Skip if already imported
            for (child in file.children) {
                if (child is ChisaImportStatement) {
                    val stmtPath = child.getPath() ?: continue
                    if (stmtPath == path) {
                        for (sym in child.getImportSymbols()) {
                            if (sym.getOriginalName() == symbolName) return
                        }
                    }
                }
            }

            // Find insertion point: after the last import statement, or at top
            var insertOffset = 0
            var hasImports = false
            for (child in file.children) {
                if (child is ChisaImportStatement) {
                    insertOffset = child.textRange.endOffset
                    hasImports = true
                }
            }

            val importLine = "import { $symbolName } from \"$path\""
            val project = file.project
            WriteCommandAction.runWriteCommandAction(project, "Add import", null, Runnable {
                val document = PsiDocumentManager.getInstance(project).getDocument(file)
                if (document != null) {
                    if (!hasImports) {
                        document.insertString(0, "$importLine\n")
                    } else {
                        document.insertString(insertOffset, "\n$importLine")
                    }
                    PsiDocumentManager.getInstance(project).commitDocument(document)
                }
            }, file)
        }

        private fun addDaemonCompletions(parameters: CompletionParameters, result: CompletionResultSet) {
            val file = parameters.originalFile
            val path = file.virtualFile?.path ?: return
            val content = file.text ?: return
            val offset = parameters.offset
            val project = file.project
            val client = DaemonService.getInstance(project).getClient() ?: return
            val completions = client.complete(path, content, offset)
            for (c in completions) {
                val icon = when (c.kind) {
                    "function" -> AllIcons.Nodes.Function
                    "variable" -> AllIcons.Nodes.Variable
                    "struct" -> AllIcons.Nodes.Class
                    "enum" -> AllIcons.Nodes.Enum
                    else -> AllIcons.Nodes.Unknown
                }
                result.addElement(
                    LookupElementBuilder.create(c.label)
                        .withIcon(icon)
                        .withTypeText(c.detail, true)
                )
            }
        }

        // 4d. Keyword completions
        private fun addKeywordCompletions(result: CompletionResultSet) {
            for (keyword in KEYWORDS) {
                result.addElement(
                    LookupElementBuilder.create(keyword).bold()
                )
            }
        }

        // Import symbol completions: symbols exported from the target file
        private fun addImportSymbolCompletions(
            importStmt: ChisaImportStatement,
            contextFile: ChisaFile?,
            result: CompletionResultSet
        ) {
            val path = importStmt.getPath() ?: return
            // Use originalFile as context so resolveImportPath can find the directory via virtualFile
            val context: PsiElement = contextFile ?: importStmt
            val targetFile = ChisaResolveUtil.resolveImportPath(context, path) ?: return
            val alreadyImported = importStmt.getImportSymbols().mapNotNullTo(HashSet()) { it.getOriginalName() }
            for (child in targetFile.children) {
                if (child is ChisaNamedElement) {
                    val name = child.name ?: continue
                    if (name in alreadyImported) continue
                    val lookup = when (child) {
                        is ChisaFnDeclaration -> LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Function).withTailText("()", true)
                        is ChisaStructDeclaration -> LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Class)
                        is ChisaEnumDeclaration -> LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Enum)
                        is ChisaVarDeclaration -> LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Variable)
                        else -> LookupElementBuilder.create(name)
                    }
                    result.addElement(lookup)
                }
            }
        }

        // 4e. Use statement variant completions
        private fun addUseVariantCompletions(useStmt: ChisaUseStatement, result: CompletionResultSet) {
            val enumName = useStmt.getEnumName() ?: return
            val enumDecl = ChisaResolveUtil.resolveInScope(useStmt, enumName)
            if (enumDecl is ChisaEnumDeclaration) {
                for (variant in ChisaResolveUtil.collectEnumVariants(enumDecl)) {
                    val name = variant.name ?: continue
                    result.addElement(
                        LookupElementBuilder.create(name)
                            .withIcon(AllIcons.Nodes.Field)
                    )
                }
            }
        }

        // 4f. Import path completions
        private fun addImportPathCompletions(
            importPath: ChisaImportPath,
            originalFile: ChisaFile?,
            result: CompletionResultSet
        ) {
            val currentVFile = originalFile?.virtualFile ?: return
            val zsFiles = ChisaResolveUtil.collectProjectZsFiles(currentVFile, importPath.project)
            for ((_, relativePath) in zsFiles) {
                result.addElement(
                    LookupElementBuilder.create(relativePath)
                        .withIcon(AllIcons.FileTypes.Any_type)
                        .withInsertHandler { ctx, _ ->
                            // Replace the entire content between the quotes
                            val docText = ctx.document.charsSequence
                            var openQuote = ctx.startOffset - 1
                            while (openQuote >= 0 && docText[openQuote] != '"') openQuote--
                            var closeQuote = ctx.tailOffset
                            while (closeQuote < docText.length && docText[closeQuote] != '"') closeQuote++
                            if (openQuote >= 0 && closeQuote < docText.length) {
                                ctx.document.replaceString(openQuote + 1, closeQuote, relativePath)
                                ctx.editor.caretModel.moveToOffset(openQuote + 1 + relativePath.length)
                            }
                        }
                )
            }
        }
    }
}
