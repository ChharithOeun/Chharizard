; ============================================================================
; ui/tabs/update.ahk  —  GitHub releases auto-updater. Stub v5.1.0.
; ============================================================================

class UpdateTab {
    static build(gui) {
        gui.SetFont("s10 bold cffd732")
        gui.Add("Text", "x30 y50", "Update — coming in v5.2.0")

        gui.SetFont("s9 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "Polls " . CHZ.api . " on launch. When a new version is available "
            . "you'll see a prompt with the changelog. One click downloads, "
            . "verifies (SHA-256), extracts to the addons folder, and restarts.")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+30 w200", "Check now (stub)").OnEvent("Click",
            (*) => MsgBox("Not implemented yet — v5.2.0 adds real update flow."))
    }
}
