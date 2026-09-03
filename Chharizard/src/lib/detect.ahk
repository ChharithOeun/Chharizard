; ============================================================================
; lib/detect.ahk  —  detect Windower / Ashita install locations and characters
; ============================================================================

class Detect {
    static _windowerCandidates := [
        "C:\Windower",
        "D:\Windower",
        "C:\Program Files\Windower",
        "C:\Program Files (x86)\Windower",
        A_UserProfile . "\Windower"
    ]

    static _ashitaCandidates := [
        "C:\Ashita",
        "D:\Ashita",
        "C:\Ashita-v4",
        "D:\Ashita-v4",
        A_UserProfile . "\Ashita",
        A_UserProfile . "\Ashita-v4"
    ]

    static framework() {
        hasWindower := Detect._findFirst(Detect._windowerCandidates, "windower.exe") != ""
        hasAshita   := Detect._findFirst(Detect._ashitaCandidates, "Ashita.exe") != ""
        if (hasWindower && hasAshita) return "both"
        if (hasWindower) return "windower"
        if (hasAshita)   return "ashita"
        return "none"
    }

    static frameworkPath() {
        p := Detect._findFirst(Detect._windowerCandidates, "windower.exe")
        if (p != "") return p
        p := Detect._findFirst(Detect._ashitaCandidates, "Ashita.exe")
        if (p != "") return p
        return ""
    }

    static _findFirst(candidates, exeName) {
        for dir in candidates {
            if (FileExist(dir . "\" . exeName))
                return dir
        }
        return ""
    }

    ; List characters by scanning existing enabled_by_char map + Windower's
    ; character-specific data folders if we can find them.
    static characters() {
        roster := State.get("roster", [])
        return roster
    }
}
