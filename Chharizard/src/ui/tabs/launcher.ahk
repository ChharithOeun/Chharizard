; ============================================================================
; ui/tabs/launcher.ahk  —  launch Windower/Ashita per character. Stub v5.1.0.
; ============================================================================

class LauncherTab {
    static build(gui) {
        gui.SetFont("s10 bold cffd732")
        gui.Add("Text", "x30 y50", "Launcher — coming in v5.2.0")

        gui.SetFont("s9 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "This tab will let you launch " . Config.framework
            . " with a specific character profile in one click, and 'Launch All' "
            . "to spin up every character in your roster sequentially. "
            . "Wired through the same Commands.run(launcher.start, {char: X}) surface "
            . "that RPC and the future AI use.")
    }
}
