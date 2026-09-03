; ============================================================================
; ui/main_window.ahk  —  the single top-level window with tabs.
; ============================================================================

class MainWindow {
    static gui := ""
    static tabCtrl := ""

    static build() {
        MainWindow.gui := Gui("+Resize", CHZ.name . " " . CHZ.version)
        MainWindow.gui.MarginX := 8
        MainWindow.gui.MarginY := 8
        MainWindow.gui.BackColor := "1a1018"

        MainWindow.gui.SetFont("s10 c0abde3", "Segoe UI")

        MainWindow.tabCtrl := MainWindow.gui.Add("Tab3", "w960 h600 vMainTab",
            ["Dashboard", "Modules", "Roster", "Launcher", "Tune", "Update", "Logs", "Plugins"])

        ; Delegate each tab to its own build function
        MainWindow.tabCtrl.UseTab("Dashboard")
        DashboardTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Modules")
        ModulesTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Roster")
        RosterTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Launcher")
        LauncherTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Tune")
        TuneTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Update")
        UpdateTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Logs")
        LogsTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab("Plugins")
        PluginsTab.build(MainWindow.gui)

        MainWindow.tabCtrl.UseTab()

        ; Status bar at the bottom
        MainWindow.gui.SetFont("s8 c888888")
        MainWindow.gui.Add("Text", "xm y+8 w960", "v" . CHZ.version . "  |  "
            . (Config.framework = "none" ? "no framework detected" : Config.framework . " @ " . Config.frameworkPath)
            . "  |  " . CHZ.repo)
    }

    static show() {
        MainWindow.gui.Show("w980 h680")
        log("Main window shown")
    }

    static hide() {
        MainWindow.gui.Hide()
    }
}
