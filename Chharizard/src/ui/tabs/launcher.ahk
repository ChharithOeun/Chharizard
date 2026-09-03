; ============================================================================
; ui/tabs/launcher.ahk  —  launch Windower/Ashita, per-character or all.
; ============================================================================

class LauncherTab {
    static frameworkText := ""
    static rosterList := ""

    static build(gui) {
        gui.SetFont("s10 bold c40e0e8")
        gui.Add("Text", "x30 y50", "Framework:")

        gui.SetFont("s10 cffd732")
        LauncherTab.frameworkText := gui.Add("Text", "x+10 w600 vLauncherFramework",
            LauncherTab._formatFramework())

        gui.SetFont("s9 cCCCCCC")
        gui.Add("Text", "x30 y+20 w900",
            "Launch Windower (retail) or Ashita (private servers). Per-character "
            . "buttons launch the framework — after the PlayOnline login screen "
            . "opens, pick that character. Future v5.4 will hook Silmaril for "
            . "one-click all-at-once launches.")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+15 w200", "Launch framework")
            .OnEvent("Click", (*) => LauncherTab._launchFramework())
        gui.Add("Button", "x+10 w200", "Re-detect")
            .OnEvent("Click", (*) => (
                Config.detect(),
                LauncherTab.frameworkText.Text := LauncherTab._formatFramework(),
                LauncherTab._refreshRoster()
            ))
        gui.Add("Button", "x+10 w200", "Launch ALL characters")
            .OnEvent("Click", (*) => LauncherTab._launchAll())

        gui.SetFont("s10 bold c40e0e8")
        gui.Add("Text", "x30 y+25", "Per-character launch:")

        LauncherTab.rosterList := gui.Add("ListBox", "x30 y+10 w400 h240 vLauncherRosterList")
        LauncherTab._refreshRoster()

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x450 y+-240 w200", "Launch selected")
            .OnEvent("Click", (*) => LauncherTab._launchSelected())

        gui.Add("Button", "x450 y+10 w200", "Refresh roster")
            .OnEvent("Click", (*) => LauncherTab._refreshRoster())

        ; React to roster changes from the Roster tab
        Events.on("roster:changed", (data) => LauncherTab._refreshRoster())
    }

    static _formatFramework() {
        if (Config.framework = "none")
            return "(none detected — install Windower or Ashita)"
        return Config.framework . " @ " . Config.frameworkPath
    }

    static _refreshRoster() {
        if (LauncherTab.rosterList = "") return
        LauncherTab.rosterList.Delete()
        roster := State.get("roster", [])
        if (roster.Length = 0) {
            LauncherTab.rosterList.Add(["(no characters — add some in Roster tab)"])
            return
        }
        for name in roster
            LauncherTab.rosterList.Add([name])
    }

    static _launchFramework() {
        result := Commands.run("launcher.start")
        if (!result.ok)
            MsgBox("Launch failed: " . result.error)
    }

    static _launchSelected() {
        sel := LauncherTab.rosterList.Text
        if (sel = "" || InStr(sel, "no characters")) return
        result := Commands.run("launcher.char", { name: sel })
        if (!result.ok)
            MsgBox("Launch failed: " . result.error)
    }

    static _launchAll() {
        roster := State.get("roster", [])
        if (roster.Length = 0) {
            MsgBox("No characters in roster. Add some in the Roster tab first.")
            return
        }
        ans := MsgBox("Launch all " . roster.Length . " characters?`n`nThey'll launch 3 seconds apart to avoid login-server race.",
            "Confirm launch all", "0x21")
        if (ans != "OK") return
        result := Commands.run("launcher.all")
        if (!result.ok)
            MsgBox("Launch all failed: " . result.error)
    }
}
