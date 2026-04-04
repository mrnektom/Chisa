package org.chisa.intellij.settings

import com.intellij.openapi.fileChooser.FileChooserDescriptorFactory
import com.intellij.openapi.options.Configurable
import com.intellij.openapi.project.Project
import com.intellij.openapi.ui.TextFieldWithBrowseButton
import com.intellij.util.ui.FormBuilder
import javax.swing.JComponent
import javax.swing.JPanel
import javax.swing.JTextField

class ChisaSettingsConfigurable(private val project: Project) : Configurable {

    private var stdlibPathField: TextFieldWithBrowseButton? = null
    private var daemonPathField: TextFieldWithBrowseButton? = null
    private var daemonPortField: JTextField? = null
    private var mainPanel: JPanel? = null

    override fun getDisplayName(): String = "Chisa"

    override fun createComponent(): JComponent {
        stdlibPathField = TextFieldWithBrowseButton().apply {
            addBrowseFolderListener(
                "Select Chisa Stdlib Directory",
                "Path to the Chisa standard library (containing prelude.chisa)",
                project,
                FileChooserDescriptorFactory.createSingleFolderDescriptor()
            )
        }
        daemonPathField = TextFieldWithBrowseButton().apply {
            addBrowseFolderListener(
                "Select zs-daemon Executable",
                "Path to the zs-daemon binary built with `zig build`",
                project,
                FileChooserDescriptorFactory.createSingleFileDescriptor()
            )
        }
        daemonPortField = JTextField(6)

        mainPanel = FormBuilder.createFormBuilder()
            .addLabeledComponent("Stdlib path:", stdlibPathField!!)
            .addLabeledComponent("Daemon path:", daemonPathField!!)
            .addLabeledComponent("Daemon TCP port (Windows):", daemonPortField!!)
            .addComponentFillVertically(JPanel(), 0)
            .panel
        return mainPanel!!
    }

    override fun isModified(): Boolean {
        val settings = ChisaSettings.getInstance(project)
        return stdlibPathField?.text != settings.stdlibPath
            || daemonPathField?.text != settings.daemonPath
            || daemonPortField?.text?.toIntOrNull() != settings.daemonPort
    }

    override fun apply() {
        val settings = ChisaSettings.getInstance(project)
        settings.stdlibPath = stdlibPathField?.text ?: ""
        settings.daemonPath = daemonPathField?.text ?: ""
        settings.daemonPort = daemonPortField?.text?.toIntOrNull() ?: 7654
    }

    override fun reset() {
        val settings = ChisaSettings.getInstance(project)
        stdlibPathField?.text = settings.stdlibPath
        daemonPathField?.text = settings.daemonPath
        daemonPortField?.text = settings.daemonPort.toString()
    }

    override fun disposeUIResources() {
        stdlibPathField = null
        daemonPathField = null
        daemonPortField = null
        mainPanel = null
    }
}
