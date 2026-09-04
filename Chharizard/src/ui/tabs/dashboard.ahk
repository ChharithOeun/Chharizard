; ============================================================================
; ui/tabs/dashboard.ahk  —  status overview + version health.
; ============================================================================

class DashboardTab {
    static wStatus := ""
    static aStatus := ""
    static healthStatus := ""
    static healthList := ""

    static build(gui) {
        gui.SetFont("s14 bold c40e0e8")
        gui.Add("Text", "x30 y50", "Welcome, Chharizard.")

        gui.SetFont("s10 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "Manage every character in your multibox from one window. "
            . "Supports Windower 4 (retail) and Ashita v4 (private servers), "
            . "including mixed-framework sessions.")

        gui.SetFont("s10 bold cffd732")
        gui.Add("Text", "x30 y+20", "Frameworks detected")

        gui.SetFont("s10 c40e0e8")
        DashboardTab.wStatus := gui.Add("Text", "x30 y+8 w900 vDashWindower", "")
        DashboardTab.aStatus := gui.Add("Text", "x30 y+5 w900 vDashAshita", "")

        gui.SetFont("s10 bold cffd732")
        gui.Add("Text", "x30 y+20", "Version health")

        gui.SetFont("s10 c40e0e8")
        DashboardTab.healthStatus := gui.Add("Text", "x30 y+8 w900 vDashHealth", "Scanning...")

        gui.SetFont("s9 cCCCCCC")
        DashboardTab.healthList := gui.Add("ListView",
            "x30 y+5 w900 h180 vDashHealthList Grid -Multi",
            ["Component", "Expected", "Local", "Status", "Note"])
        DashboardTab.healthList.ModifyCol(1, 160)
        DashboardTab.healthList.ModifyCol(2, 80)
        DashboardTab.healthList.ModifyCol(3, 80)
        DashboardTab.healthList.ModifyCol(4, 90)
        DashboardTab.healthList.ModifyCol(5, 460)

        DashboardTab._refresh()

        gui.SetFont("s9 c888888")
        gui.Add("Text", "x30 y+10", "Repo:    " . Config.repoRoot())
        gui.Add("Text", "x30 y+5",  "Version: " . CHZ.version)

        gui.SetFont("s9 cFFD732")
        gui.Add("Text", "x30 y+15", "Actions:")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+8 w180", "Re-detect frameworks")
            .OnEvent("Click", (*) => (Config.detect(), DashboardTab._refresh()))

        gui.Add("Button", "x+8 w180", "Re-scan versions")
            .OnEvent("Click", (*) => DashboardTab._refresh())

        gui.Add("Button", "x+8 w180", "Repair drift")
            .OnEvent("Click", (*) => DashboardTab._repair())

        gui.Add("Button", "x+8 w180", "Open repo folder")
            .OnEvent("Click", (*) => Run("explorer.exe " . Config.repoRoot()))

        gui.Add("Button", "x+8 w130", "Open GitHub")
            .OnEvent("Click", (*) => Run(CHZ.repo))
    }

    static _refresh() {
        ; Frameworks
        info := Detect.all()
        wLine := info.windower.installed
            ? ("[+] Windower " . info.windower.version . "  at  " . info.windower.path)
            : ("[ ] Windower not detected")
        aLine := info.ashita.installed
            ? ("[+] Ashita " . info.ashita.version . "  at  " . info.ashita.path)
            : ("[ ] Ashita not detected (private-server support)")
        DashboardTab.wStatus.Text := wLine
        DashboardTab.aStatus.Text := aLine

        ; Version health
        report := Commands.run("compat.scan")
        summary := Commands.run("compat.summary")
        DashboardTab.healthList.Delete()
        if (report.ok) {
            for r in report.data
                DashboardTab.healthList.Add(, r.name, r.expected, r.local, r.status, r.note)
        }
        if (summary.ok) {
            s := summary.data
            healthLine := s.healthy
                ? "[+] All " . s.total . " components healthy."
                : "[!] " . s.drift . " drift, " . s.missing . " missing out of " . s.total . " components. Click 'Repair drift' to fix."
            DashboardTab.healthStatus.Text := healthLine
        }
    }

    static _repair() {
        ans := MsgBox("Run auto-repair? This will pull the latest release from GitHub and re-sync any drifted or missing components.",
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
