; ============================================================================
; lib/tune.ahk  —  embedded FFXI system tuner.
;
; Wraps the vendored PowerShell scripts at Chharizard/tune/ (TUNE-FFXI.ps1 and
; REVERT-FFXI.ps1). ShellExecute with "*RunAs" prefix triggers the UAC prompt
; so we don't need to run the whole exe as administrator.
;
; The .ps1 scripts handle their own backup and reversible per-tweak state.
; This lib just launches them and returns the log path for review.
; ============================================================================

class Tune {
    static tuneDir() {
        return A_ScriptDir . "\..\tune"
    }

    static tunePs1() {
        return Tune.tuneDir() . "\TUNE-FFXI.ps1"
    }

    static revertPs1() {
        return Tune.tuneDir() . "\REVERT-FFXI.ps1"
    }

    static logPath() {
        return Tune.tuneDir() . "\TUNE-FFXI.log"
    }

    static backupPath() {
        return Tune.tuneDir() . "\Revert\backup.json"
    }

    ; Launch the tuner as admin. Returns true on launch success (not tune
    ; success — the .ps1 owns that).
    static apply() {
        script := Tune.tunePs1()
        if (!FileExist(script))
            throw Error("TUNE-FFXI.ps1 not found at " . script)
        cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' . script . '"'
        try {
            Run('*RunAs ' . cmd, Tune.tuneDir())
        } catch as e {
            throw Error("Failed to launch tuner: " . e.Message)
        }
        Events.emit("tune:apply-launched", { script: script })
        log("[Tune] launched " . script)
        return true
    }

    static revert() {
        script := Tune.revertPs1()
        if (!FileExist(script))
            throw Error("REVERT-FFXI.ps1 not found at " . script)
        cmd := 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' . script . '"'
        try {
            Run('*RunAs ' . cmd, Tune.tuneDir())
        } catch as e {
            throw Error("Failed to launch revert: " . e.Message)
        }
        Events.emit("tune:revert-launched", { script: script })
        log("[Tune] launched " . script)
        return true
    }

    static isApplied() {
        return FileExist(Tune.backupPath()) ? true : false
    }

    static readLog(lines := 200) {
        path := Tune.logPath()
        if (!FileExist(path))
            return ""
        text := FileRead(path, "UTF-8")
        lineArr := StrSplit(text, "`n")
        start := Max(1, lineArr.Length - lines)
        result := ""
        Loop lineArr.Length - start + 1 {
            idx := start + A_Index - 1
            if (idx <= lineArr.Length)
                result .= lineArr[idx] . "`n"
        }
        return result
    }
}

; ----------------------------------------------------------------------------
; Register tune commands.
; ----------------------------------------------------------------------------
Commands.register("tune.apply",  (args) => Tune.apply())
Commands.register("tune.revert", (args) => Tune.revert())
Commands.register("tune.status", (args) => (
    { applied: Tune.isApplied(), backup: Tune.backupPath(), log: Tune.logPath() }
))
Commands.register("tune.log",    (args) => Tune.readLog(args.HasProp("lines") ? args.lines : 200))
