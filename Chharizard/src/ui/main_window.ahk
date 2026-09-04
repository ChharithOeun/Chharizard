; ============================================================================
; ui/main_window.ahk  —  themed main window with banner + tabbed content.
;
; v5.9.0: full theme adoption — Chharizard banner across the top, dark title
; bar, cyan/pink/yellow palette everywhere. Each tab file gets a themed base
; via gui.SetFont() applied before UseTab().
; ============================================================================

class MainWindow {
    static gui := ""
    static tabCtrl := ""

    static build() {
        MainWindow.gui := Gui("+Resize -DPIScale", CHZ.name . " " . CHZ.version)
        MainWindow.gui.MarginX := 0
        MainWindow.gui.MarginY := 0
        MainWindow.gui.BackColor := Theme.bg

        ; --- Banner strip at the top --------------------------------------
        bannerPath := A_ScriptDir . "\..\assets\banner.png"
        if (FileExist(bannerPath)) {
            MainWindow.gui.Add("Picture", "x0 y0 w1000 h140", bannerPath)
        } else {
            ; No banner image found — fall back to a text title.
            ThemeApply.title(MainWindow.gui)
            MainWindow.gui.Add("Text", "x20 y40 w960 h60 Center", "Chharizard")
        }

        ; --- Themed base font applied BEFORE tabs are built --------------
        ThemeApply.body(MainWindow.gui)

        ; --- Tab control below the banner ---------------------------------
        MainWindow.tabCtrl := MainWindow.gui.Add("Tab3",
            "x8 y150 w984 h520 vMainTab Background" . Theme.bg,
            ["Dashboard", "Modules", "Roster", "Launcher", "Tune", "Update", "Logs", "Plugins"])

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

        ; --- Status strip at bottom ---------------------------------------
        ThemeApply.muted(MainWindow.gui)
        statusLine := "v" . CHZ.version . "  |  "
            . (Config.framework = "none" ? "no framework detected" : Config.framework . " @ " . Config.frameworkPath)
            . "  |  " . CHZ.repo
        MainWindow.gui.Add("Text", "x8 y+8 w984 Center", statusLine)
    }

    static show() {
        MainWindow.gui.Show("w1000 h720")
        DarkTitleBar(MainWindow.gui)   ; apply dark title bar after HWND exists
        log("Main window shown (themed)")
    }

    static hide() {
        MainWindow.gui.Hide()
    }
}
