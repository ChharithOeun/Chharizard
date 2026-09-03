; ============================================================================
; ui/tabs/dashboard.ahk  —  at-a-glance status per character.
; ============================================================================

class DashboardTab {
    static build(gui) {
        gui.SetFont("s14 bold c40e0e8")
        gui.Add("Text", "x30 y50", "Welcome, Chharizard.")

        gui.SetFont("s10 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "Manage every character in your multibox from one window. Enable modules, "
            . "generate gearswap files, launch profiles, tune the game — all without "
            . "touching Lua or init.txt.")

        gui.SetFont("s9 c888888")
        gui.Add("Text", "x30 y+30", "Framework: " . Config.framework)
        gui.Add("Text", "x30 y+5",  "Path:      " . Config.frameworkPath)
        gui.Add("Text", "x30 y+5",  "Repo:      " . Config.repoRoot())
        gui.Add("Text", "x30 y+5",  "Version:   " . CHZ.version)

        gui.SetFont("s9 cFFD732")
        gui.Add("Text", "x30 y+30", "Quick actions:")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+10 w200", "Detect framework").OnEvent("Click",
            (*) => (Config.detect(), log("Re-detected framework: " . Config.framework),
                    MsgBox("Framework: " . Config.framework . "`nPath: " . Config.frameworkPath)))

        gui.Add("Button", "x+10 w200", "Open repo folder").OnEvent("Click",
            (*) => Run("explorer.exe " . Config.repoRoot()))

        gui.Add("Button", "x+10 w200", "Open GitHub").OnEvent("Click",
            (*) => Run(CHZ.repo))
    }
}
