; ============================================================================
; ui/tabs/tune.ahk  —  embedded FFXI tuner UI.
;
; Runs the vendored TUNE-FFXI.ps1 / REVERT-FFXI.ps1 with UAC elevation.
; Displays the .ps1's log inline so you don't have to hunt for it.
; ============================================================================

class TuneTab {
    static statusText := ""
    static logEdit := ""

    static build(gui) {
        ThemeApply.h3(gui)
        gui.Add("Text", "x30 y50", "FFXI system tuner")

        ThemeApply.small(gui)
        gui.Add("Text", "x30 y+5 w900",
            "Applies well-documented Windows tweaks that reduce stutter and improve "
            . "input latency for FFXI + Windower. Each change is backed up per-tweak "
            . "and fully reversible.")

        gui.SetFont("s9 cffd732")
        gui.Add("Text", "x30 y+15 w900",
            "The tuner runs as Administrator (UAC prompt will appear). "
            . "Reboot recommended after applying for hardware GPU scheduling / "
            . "Ndu service / MMCSS changes to take full effect.")

        ThemeApply.small(gui)
        gui.Add("Text", "x30 y+15 w900", "What gets tuned:")
        gui.Add("Text", "x30 y+5 w900",
            "  1. Windows Defender exclusions on pol.exe + Windower folder`n"
            . "  2. Fullscreen Opt OFF + High DPI System for pol.exe`n"
            . "  3. Xbox Game Bar / Game DVR OFF`n"
            . "  4. Hardware-Accelerated GPU Scheduling ON`n"
            . "  5. Ultimate Performance power plan + set active`n"
            . "  6. Hibernation + Fast Startup OFF`n"
            . "  7. USB selective suspend OFF (AC)`n"
            . "  8. Nagle's algorithm OFF on primary adapter`n"
            . "  9. MMCSS Games priority raised`n"
            . " 10. Ndu (Network Data Usage) service OFF`n"
            . " 11. Verify SSD TRIM enabled")

        ThemeApply.status_ok(gui)
        gui.Add("Button", "x30 y+20 w200", "Apply tuning")
            .OnEvent("Click", (*) => TuneTab._apply())
        gui.Add("Button", "x+10 w200", "Revert tuning")
            .OnEvent("Click", (*) => TuneTab._revert())
        gui.Add("Button", "x+10 w200", "View log")
            .OnEvent("Click", (*) => TuneTab._refreshLog())
        gui.Add("Button", "x+10 w200", "Open log in Notepad")
            .OnEvent("Click", (*) => Run('notepad.exe "' . Tune.logPath() . '"'))

        ThemeApply.status_warn(gui)
        TuneTab.statusText := gui.Add("Text", "x30 y+20 w900 vTuneStatus",
            TuneTab._statusLine())

        ThemeApply.small(gui)
        gui.Add("Text", "x30 y+15", "Log (last 100 lines):")
        TuneTab.logEdit := gui.Add("Edit", "x30 y+5 w900 h180 +VScroll +ReadOnly Multi vTuneLog -Wrap")
        TuneTab.logEdit.SetFont("s9 c40e0e8", "Consolas")
        TuneTab._refreshLog()
    }

    static _statusLine() {
        applied := Tune.isApplied()
        return applied
            ? "Status: TUNED  |  backup at " . Tune.backupPath()
            : "Status: not tuned"
    }

    static _apply() {
        ans := MsgBox("Launch the tuner? A UAC prompt will appear, then a PowerShell window will run and show progress.",
            "Confirm apply", "0x21")
        if (ans != "OK") return
        try {
            Commands.run("tune.apply")
            TuneTab.statusText.Text := "Tuner launched — see the elevated PowerShell window."
        } catch as e {
            MsgBox("Failed: " . e.Message)
        }
    }

    static _revert() {
        if (!Tune.isApplied()) {
            MsgBox("No backup file found — nothing to revert. If you know the tuner was run, check " . Tune.backupPath())
            return
        }
        ans := MsgBox("Revert all tuning changes? Reads backup.json and restores every registry key, service, and power setting to its pre-tune state.",
            "Confirm revert", "0x21")
        if (ans != "OK") return
        try {
            Commands.run("tune.revert")
            TuneTab.statusText.Text := "Revert launched — see the elevated PowerShell window."
        } catch as e {
            MsgBox("Failed: " . e.Message)
        }
    }

    static _refreshLog() {
        result := Commands.run("tune.log", { lines: 100 })
        if (result.ok)
            TuneTab.logEdit.Value := result.data
        TuneTab.statusText.Text := TuneTab._statusLine()
    }
}
