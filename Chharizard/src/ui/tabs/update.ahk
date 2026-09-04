; ============================================================================
; ui/tabs/update.ahk  —  GitHub Releases auto-updater UI.
; ============================================================================

class UpdateTab {
    static statusText := ""
    static bodyEdit := ""
    static applyBtn := ""

    static build(gui) {
        ThemeApply.h3(gui)
        gui.Add("Text", "x30 y50", "Chharizard update")

        ThemeApply.small(gui)
        gui.Add("Text", "x30 y+5 w900",
            "Checks the latest release at " . CHZ.repo . "/releases and offers "
            . "a one-click upgrade. Your local data/ folder is preserved.")

        ThemeApply.status_ok(gui)
        ; v5.4.2: auto-check on launch preference
        autoOn := State.get("auto_update_on_launch", true)
        ThemeApply.small(gui)
        cb := gui.Add("Checkbox", "x30 y+15 vUpdateAutoCheck", "Check for updates automatically when Chharizard starts")
        cb.Value := autoOn ? 1 : 0
        cb.OnEvent("Click", (ctrl, *) => (State.set("auto_update_on_launch", ctrl.Value = 1), State.save()))

        ThemeApply.status_ok(gui)
        gui.Add("Button", "x30 y+15 w200", "Check for updates")
            .OnEvent("Click", (*) => UpdateTab._check())
        gui.Add("Button", "x+10 w200 vUpdateApplyBtn", "Download and install")
            .OnEvent("Click", (*) => UpdateTab._apply())
        UpdateTab.applyBtn := gui["UpdateApplyBtn"]
        UpdateTab.applyBtn.Enabled := false

        gui.Add("Button", "x+10 w200", "Open releases page")
            .OnEvent("Click", (*) => Run(CHZ.repo . "/releases"))

        ThemeApply.status_warn(gui)
        UpdateTab.statusText := gui.Add("Text", "x30 y+20 w900 vUpdateStatus", "Not checked yet.")

        ThemeApply.small(gui)
        gui.Add("Text", "x30 y+15", "Changelog:")
        UpdateTab.bodyEdit := gui.Add("Edit", "x30 y+5 w900 h300 +VScroll +ReadOnly Multi vUpdateBody -Wrap")
        UpdateTab.bodyEdit.SetFont("s9 c40e0e8", "Consolas")
    }

    static _check() {
        UpdateTab.statusText.Text := "Checking..."
        result := Commands.run("update.check")
        if (!result.ok) {
            UpdateTab.statusText.Text := "Check failed: " . result.error
            return
        }
        info := result.data
        cmp := Updater.compare(info.tag)
        if (cmp > 0) {
            UpdateTab.statusText.Text := "Update available: " . info.tag . " (you have " . CHZ.version . ")"
            UpdateTab.applyBtn.Enabled := true
        } else if (cmp = 0) {
            UpdateTab.statusText.Text := "You are on the latest version (" . CHZ.version . ")"
            UpdateTab.applyBtn.Enabled := false
        } else {
            UpdateTab.statusText.Text := "You are ahead of latest release (local " . CHZ.version . " > remote " . info.tag . ")"
            UpdateTab.applyBtn.Enabled := false
        }
        UpdateTab.bodyEdit.Value := info.body
    }

    static _apply() {
        ans := MsgBox("Download and install the update now?", "Confirm update", "0x21")  ; OKCancel + ?
        if (ans != "OK") return
        UpdateTab.statusText.Text := "Downloading..."
        result := Commands.run("update.apply")
        if (result.ok) {
            UpdateTab.statusText.Text := "Update applied. Restart Chharizard.exe to load the new version."
            MsgBox("Update installed. Close Chharizard and reopen to load the new version.")
        } else {
            UpdateTab.statusText.Text := "Apply failed: " . result.error
        }
    }
}
