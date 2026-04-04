package org.chisa.intellij.settings

import com.intellij.openapi.components.Service
import com.intellij.openapi.project.Project
import com.intellij.openapi.vfs.LocalFileSystem
import com.intellij.openapi.vfs.VirtualFile
import com.intellij.openapi.vfs.VirtualFileManager
import com.intellij.psi.PsiManager
import org.chisa.intellij.ChisaFile

@Service(Service.Level.PROJECT)
class ChisaPreludeService(private val project: Project) {

    fun getPreludeFile(): ChisaFile? {
        val stdlibPath = ChisaSettings.getInstance(project).stdlibPath
        if (stdlibPath.isBlank()) return null
        val stdlibDir = findDirectory(stdlibPath) ?: return null
        val preludeVf = stdlibDir.findChild("prelude.chisa") ?: return null
        return PsiManager.getInstance(project).findFile(preludeVf) as? ChisaFile
    }

    private fun findDirectory(path: String): VirtualFile? {
        // Try as VFS URL first (handles temp:// in tests, file:// etc.)
        VirtualFileManager.getInstance().findFileByUrl(path)?.let { return it }
        // Try as local filesystem path
        return LocalFileSystem.getInstance().findFileByPath(path)
    }
}
