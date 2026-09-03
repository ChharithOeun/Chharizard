; ============================================================================
; ui/tabs/tune.ahk  —  run FFXI system tuner (embedded). Stub v5.1.0.
; ============================================================================

class TuneTab {
    static build(gui) {
        gui.SetFont("s10 bold cffd732")
        gui.Add("Text", "x30 y50", "Tune — coming in v5.2.0")

        gui.SetFont("s9 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "Runs the tune-ffxi backbone (Defender exclusions, Game Bar off, "
            . "hardware GPU scheduling, MMCSS, Ndu off, etc.) with a checkbox "
            . "list and one-click revert. No separate .bat file needed.")
    }
}
