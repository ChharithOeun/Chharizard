; ============================================================================
; lib/launcher.ahk  —  spawn Windower / Ashita, optionally per-character.
;
; Windower 4:  windower.exe (shows PlayOnline login)
; Ashita v4:   Ashita.exe   (shows profile picker)
;
; Per-character launch: currently spawns the framework and relies on the
; user selecting the character at PlayOnline login. Future v5.4+ can either
; (a) coordinate with Silmaril, (b) drive PlayOnline login via UIA, or
; (c) hook Windower's launcher profile system directly.
; ============================================================================

class Launcher {
    static launchFramework() {
        if (Config.framework = "none")
            throw Error("No framework detected. Set framework path in Dashboard.")
        exe := Launcher._exePath()
        if (exe = "")
            throw Error("Framework exe not found at " . Config.frameworkPath)
        log("[Launcher] spawning " . exe)
        Run(exe, Config.frameworkPath)
        Events.emit("launcher:started", { framework: Config.framework, exe: exe })
        return exe
    }

    static launchCharacter(char) {
        if (char = "")
            throw Error("Empty character name")
        Launcher.launchFramework()
        Events.emit("launcher:char", { name: char })
        log("[Launcher] launched for character: " . char)
        return char
    }

    static launchAll() {
        roster := State.get("roster", [])
        count := 0
        for name in roster {
            try {
                Launcher.launchCharacter(name)
                count++
                Sleep(3000)  ; stagger to avoid PlayOnline login race
            } catch as e {
                log("[Launcher] launchAll failed on " . name . ": " . e.Message)
            }
        }
        Events.emit("launcher:all", { count: count })
        return count
    }

    static _exePath() {
        if (Config.framework = "windower" || Config.framework = "both")
            return Config.frameworkPath . "\windower.exe"
        if (Config.framework = "ashita")
            return Config.frameworkPath . "\Ashita.exe"
        return ""
    }
}

; ----------------------------------------------------------------------------
; Register launcher commands with the dispatcher.
; ----------------------------------------------------------------------------
Commands.register("launcher.start", (args) => Launcher.launchFramework())

Commands.register("launcher.char", (args) => Launcher.launchCharacter(args.name))

Commands.register("launcher.all", (args) => Launcher.launchAll())
