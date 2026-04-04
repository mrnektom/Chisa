package org.chisa.intellij.settings

import com.intellij.openapi.components.*
import com.intellij.openapi.project.Project

@Service(Service.Level.PROJECT)
@State(
    name = "ChisaSettings",
    storages = [Storage("chisa.xml")]
)
class ChisaSettings : PersistentStateComponent<ChisaSettings.State> {

    data class State(
        var stdlibPath: String = "",
        var daemonPath: String = "",
        var daemonPort: Int = 7654,
    )

    private var myState = State()

    override fun getState(): State = myState

    override fun loadState(state: State) {
        myState = state
    }

    var stdlibPath: String
        get() = myState.stdlibPath
        set(value) { myState.stdlibPath = value }

    var daemonPath: String
        get() = myState.daemonPath
        set(value) { myState.daemonPath = value }

    var daemonPort: Int
        get() = myState.daemonPort
        set(value) { myState.daemonPort = value }

    companion object {
        fun getInstance(project: Project): ChisaSettings =
            project.getService(ChisaSettings::class.java)
    }
}
