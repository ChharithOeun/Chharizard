; ============================================================================
; ui/tabs/dashboard.ahk  —  status overview, both frameworks visible.
; ============================================================================

class DashboardTab {
    static wStatus := ""
    static aStatus := ""

    static build(gui) {
        gui.SetFont("s14 bold c40e0e8")
        gui.Add("Text", "x30 y50", "Welcome, Chharizard.")

        gui.SetFont("s10 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "Manage every character in your multibox from one window. Enable modules, "
            . "generate gearswap files, launch profiles, tune the game — all without "
            . "touching Lua or init.txt. Supports Windower 4 (retail) and Ashita v4 "
            . "(private servers), including mixed-framework sessions.")

        gui.SetFont("s10 bold cffd732")
        gui.Add("Text", "x30 y+25", "Frameworks detected")

        gui.SetFont("s10 c40e0e8")
        DashboardTab.wStatus := gui.Add("Text", "x30 y+10 w900 vDashWindower", "")
        DashboardTab.aStatus := gui.Add("Text", "x30 y+5 w900 vDashAshita", "")
        DashboardTab._refresh()

        gui.SetFont("s9 c888888")
        gui.Add("Text", "x30 y+15", "Repo:    " . Config.repoRoot())
        gui.Add("Text", "x30 y+5",  "Version: " . CHZ.version)

        gui.SetFont("s9 cFFD732")
        gui.Add("Text", "x30 y+25", "Quick actions:")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+10 w200", "Re-detect frameworks")
            .OnEvent("Click", (*) => (Config.detect(), DashboardTab._refresh()))

        gui.Add("Button", "x+10 w200", "Open repo folder")
            .OnEvent("Click", (*) => Run("explorer.exe " . Config.repoRoot()))

        gui.Add("Button", "x+10 w200", "Open GitHub")
            .OnEvent("Click", (*) => Run(CHZ.repo))

        gui.Add("Button", "x+10 w200", "Open Releases")
            .OnEvent("Click", (*) => Run(CHZ.repo . "/releases"))
    }

    static _refresh() {
        info := Detect.all()
        w := info.windower
        a := info.ashita
        wLine := w.installed
            ? ("[+] Windower " . w.version . "  at  " . w.path)
            : ("[ ] Windower not detected")
        aLine := a.installed
            ? ("[+] Ashita " . a.version . "  at  " . a.path)
            : ("[ ] Ashita not detected (private-server support)")
        DashboardTab.wStatus.Text := wLine
        DashboardTab.aStatus.Text := aLine
    }
}
