package org.chisa.intellij.daemon

import com.intellij.lang.annotation.AnnotationHolder
import com.intellij.lang.annotation.ExternalAnnotator
import com.intellij.lang.annotation.HighlightSeverity
import com.intellij.openapi.editor.Document
import com.intellij.openapi.project.Project
import com.intellij.openapi.util.TextRange
import com.intellij.psi.PsiDocumentManager
import com.intellij.psi.PsiFile
import org.chisa.intellij.ChisaFile

/**
 * ExternalAnnotator that delegates semantic diagnostics to the running zs-daemon.
 *
 * IntelliJ calls this in three phases:
 *   1. [collectInformation] on EDT — extract file path + content
 *   2. [doAnnotate]         on background thread — call daemon
 *   3. [apply]              on EDT — create annotations from results
 */
class DaemonAnnotator : ExternalAnnotator<DaemonAnnotator.FileInfo, List<DaemonDiagnostic>>() {

    data class FileInfo(
        val project: Project,
        val filePath: String,
        val content: String,
        val document: Document,
    )

    override fun collectInformation(file: PsiFile): FileInfo? {
        if (file !is ChisaFile) return null
        val vf = file.virtualFile ?: return null
        val doc = PsiDocumentManager.getInstance(file.project).getDocument(file) ?: return null
        return FileInfo(
            project = file.project,
            filePath = vf.path,
            content = doc.text,
            document = doc,
        )
    }

    override fun doAnnotate(info: FileInfo): List<DaemonDiagnostic> {
        val service = DaemonService.getInstance(info.project)
        val client = service.getClient() ?: return emptyList()
        return client.check(info.filePath, info.content)
    }

    override fun apply(file: PsiFile, diagnostics: List<DaemonDiagnostic>, holder: AnnotationHolder) {
        if (diagnostics.isEmpty()) return
        val doc = PsiDocumentManager.getInstance(file.project).getDocument(file) ?: return
        val docLen = doc.textLength

        for (diag in diagnostics) {
            val range = safeRange(diag.start, diag.end, docLen) ?: continue
            holder.newAnnotation(HighlightSeverity.ERROR, diag.message)
                .range(range)
                .create()
        }
    }

    private fun safeRange(start: Int, end: Int, docLen: Int): TextRange? {
        val s = start.coerceAtLeast(0)
        val e = end.coerceAtMost(docLen)
        if (s >= e || s >= docLen) return null
        return TextRange(s, e)
    }
}
