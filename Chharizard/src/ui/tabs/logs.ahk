; ============================================================================
; ui/tabs/logs.ahk  —  live log tail. Subscribes to log:line events.
; ============================================================================

class LogsTab {
    static editCtrl := ""

    static build(gui) {
        gui.SetFont("s9 cCCCCCC")
        gui.Add("Text", "x30 y50", "Live log (last 200 lines). Auto-refreshes on new entries.")

        LogsTab.editCtrl := gui.Add("Edit", "x30 y+10 w900 h480 +VScroll +ReadOnly Multi vLogsEdit -Wrap")
        LogsTab.editCtrl.SetFont("s9 c40e0e8", "Consolas")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+10 w200", "Refresh").OnEvent("Click", (*) => LogsTab._refresh())
        gui.Add("Button", "x+10 w200", "Clear view").OnEvent("Click", (*) => LogsTab.editCtrl.Value := "")
        gui.Add("Button", "x+10 w200", "Open log file").OnEvent("Click",
            (*) => Run("notepad.exe " . LogState.path))

        ; Live-tail via event bus
        Events.on("log:line", (line) => LogsTab.editCtrl.Value := LogsTab.editCtrl.Value . line . "`r`n")

        LogsTab._refresh()
    }

    static _refresh() {
        result := Commands.run("log.tail", { lines: 200 })
        if (result.ok)
            LogsTab.editCtrl.Value := result.data
    }
}
