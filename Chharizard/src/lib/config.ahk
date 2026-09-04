; ============================================================================
; lib/config.ahk  —  path resolution + framework detection facts.
; ============================================================================

class Config {
    static framework := "none"       ; "windower" | "ashita" | "both" | "none"
    static frameworkPath := ""       ; e.g. "C:\Windower"
    static addonPath := ""           ; e.g. "C:\Windower\addons"

    static detect() {
        Config.framework := Detect.framework()
        Config.frameworkPath := Detect.frameworkPath()
        Config.addonPath := Config.frameworkPath . "\addons"
    }

    ; Repo root (where this exe lives, minus /Chharizard/build/)
    static repoRoot() {
        s := State.get("chharizard_repo", "")
        if (s != "" && DirExist(s))
            return s
        return A_ScriptDir . "\..\.."
    }

    ; Where Chharbar's data/ folder lives
    static chharbarDataPath() {
        return Config.repoRoot() . "\addons\Chharbar\data"
    }
}
