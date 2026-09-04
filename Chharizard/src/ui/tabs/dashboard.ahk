; ============================================================================
; ui/tabs/dashboard.ahk  —  themed status overview (v5.9.0)
;
; Reference implementation for the new theme system. Other tabs can use
; the same ThemeApply.* helpers to stay consistent.
; ============================================================================

class DashboardTab {
    static wStatus := ""
    static aStatus := ""
    static healthStatus := ""
    static healthList := ""

    static build(gui) {
        ThemeApply.title(gui)
        gui.Add("Text", "x30 y40", "Welcome, Chharizard.")

        ThemeApply.body(gui)
        gui.Add("Text", "x30 y+8 w900",
            "Manage every character in your multibox from one window. "
            . "Supports Windower 4 and Ashita v4, including mixed sessions.")

        ThemeApply.h2(gui)
        gui.Add("Text", "x30 y+20", "Frameworks detected")

        ThemeApply.status_ok(gui)
        DashboardTab.wStatus := gui.Add("Text", "x30 y+8 w900 vDashWindower", "")
        DashboardTab.aStatus := gui.Add("Text", "x30 y+5 w900 vDashAshita",   "")

        ThemeApply.h2(gui)
        gui.Add("Text", "x30 y+20", "Version health")

        ThemeApply.status_ok(gui)
        DashboardTab.healthStatus := gui.Add("Text", "x30 y+8 w900 vDashHealth", "Scanning...")

        ThemeApply.small(gui)
        DashboardTab.healthList := gui.Add("ListView",
            "x30 y+5 w900 h160 vDashHealthList Grid -Multi Background" . Theme.panel_dim,
            ["Component", "Expected", "Local", "Status", "Note"])
        DashboardTab.healthList.ModifyCol(1, 150)
        DashboardTab.healthList.ModifyCol(2, 80)
        DashboardTab.healthList.ModifyCol(3, 80)
        DashboardTab.healthList.ModifyCol(4, 90)
        DashboardTab.healthList.ModifyCol(5, 480)

        DashboardTab._refresh()

        ThemeApply.muted(gui)
        gui.Add("Text", "x30 y+8", "Repo:    " . Config.repoRoot())
        gui.Add("Text", "x30 y+3", "Version: " . CHZ.version)

        ThemeApply.accent_pink(gui)
        gui.Add("Text", "x30 y+15", "Actions")

        ThemeApply.h3(gui)
        gui.Add("Button", "x30 y+5 w180 Background" . Theme.panel, "Re-detect frameworks")
            .OnEvent("Click", (*) => (Config.detect(), DashboardTab._refresh()))
        gui.Add("Button", "x+8 w180 Background" . Theme.panel, "Re-scan versions")
            .OnEvent("Click", (*) => DashboardTab._refresh())
        gui.Add("Button", "x+8 w180 Background" . Theme.panel, "Repair drift")
            .OnEvent("Click", (*) => DashboardTab._repair())
        gui.Add("Button", "x+8 w180 Background" . Theme.panel, "Open repo folder")
            .OnEvent("Click", (*) => Run("explorer.exe " . Config.repoRoot()))
        gui.Add("Button", "x+8 w130 Background" . Theme.panel, "Open GitHub")
            .OnEvent("Click", (*) => Run(CHZ.repo))
    }

    static _refresh() {
        info := Detect.all()
        w := info.windower, a := info.ashita
        DashboardTab.wStatus.Text := w.installed
            ? ("[+] Windower " . w.version . "  at  " . w.path)
            : "[ ] Windower not detected"
        DashboardTab.aStatus.Text := a.installed
            ? ("[+] Ashita " . a.version . "  at  " . a.path)
            : "[ ] Ashita not detected (private-server support)"

        report := Commands.run("compat.scan")
        summary := Commands.run("compat.summary")
        DashboardTab.healthList.Delete()
        if (report.ok) {
            for r in report.data
                DashboardTab.healthList.Add(, r.name, r.expected, r.local, r.status, r.note)
        }
        if (summary.ok) {
            s := summary.data
            DashboardTab.healthStatus.Text := s.healthy
                ? ("[+] All " . s.total . " components healthy.")
                : ("[!] " . s.drift . " drift, " . s.missing . " missing out of " . s.total . " components. Click 'Repair drift' to fix.")
        }
    }

    static _repair() {
        ans := MsgBox("Run auto-repair? Pulls the latest release from GitHub and re-syncs any drifted or missing components.",
            "Repair components", "0x21")
        if (ans != "OK") return
        result := Commands.run("compat.repair")
        if (result.ok) {
            MsgBox("Repair complete. Restart Chharizard to load repaired components.")
        } else {
            MsgBox("Repair failed: " . (result.HasProp("error") ? result.error : "unknown"))
        }
        DashboardTab._refresh()
    }
}
