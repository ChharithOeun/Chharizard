; ============================================================================
; lib/detect.ahk  —  detect Windower / Ashita installs, versions, and per-
; character framework preference. Both frameworks can be installed side by
; side; Chharizard deploys addons to whichever is preferred per character.
; ============================================================================

class Detect {
    static _windowerCandidates := [
        "C:\Windower",
        "D:\Windower",
        "C:\Program Files\Windower",
        "C:\Program Files (x86)\Windower",
        A_UserProfile . "\Windower",
        A_UserProfile . "\Desktop\Windower"
    ]

    static _ashitaCandidates := [
        "C:\Ashita",         "D:\Ashita",
        "C:\Ashita-v4",      "D:\Ashita-v4",
        "C:\Program Files\Ashita",
        "C:\Program Files (x86)\Ashita",
        A_UserProfile . "\Ashita",
        A_UserProfile . "\Ashita-v4",
        A_UserProfile . "\Desktop\Ashita",
        A_UserProfile . "\Desktop\Ashita-v4"
    ]

    ; Returns the "primary" framework name for the Config.framework legacy
    ; field. Prefers Windower if both are installed unless per-char pref
    ; says otherwise.
    static framework() {
        results := Detect.all()
        if (results.windower.installed && results.ashita.installed) return "both"
        if (results.windower.installed) return "windower"
        if (results.ashita.installed)   return "ashita"
        return "none"
    }

    static frameworkPath() {
        results := Detect.all()
        if (results.windower.installed) return results.windower.path
        if (results.ashita.installed)   return results.ashita.path
        return ""
    }

    ; Full detection report. Chharizard.exe uses this for the Dashboard tab
    ; and to route each character's launch to the right framework.
    static all() {
        w := Detect._detectOne(Detect._windowerCandidates, "windower.exe")
        a := Detect._detectOne(Detect._ashitaCandidates, "Ashita.exe")
        return {
            windower: {
                installed: w.path != "",
                path:      w.path,
                exe:       w.exe,
                version:   w.version,
                addonsDir: (w.path != "") ? w.path . "\addons" : ""
            },
            ashita: {
                installed: a.path != "",
                path:      a.path,
                exe:       a.exe,
                version:   a.version,
                addonsDir: (a.path != "") ? a.path . "\addons" : ""
            }
        }
    }

    static _detectOne(candidates, exeName) {
        result := { path: "", exe: "", version: "" }
        for dir in candidates {
            exePath := dir . "\" . exeName
            if (FileExist(exePath)) {
                result.path := dir
                result.exe  := exePath
                result.version := Detect._exeVersion(exePath)
                return result
            }
        }
        return result
    }

    ; Read file version metadata via COM. Returns "" if no version resource.
    static _exeVersion(path) {
        try {
            fso := ComObject("Scripting.FileSystemObject")
            v := fso.GetFileVersion(path)
            return v != "" ? v : "unknown"
        } catch as e {
            return "unknown"
        }
    }

    ; Per-character framework preference. Reads from State; defaults to
    ; whatever the primary detected framework is.
    static frameworkForChar(charName) {
        prefs := State.get("char_framework", Map())
        if (prefs.Has(charName))
            return prefs[charName]
        ; Default: primary detected framework
        return Detect.framework()
    }

    static setFrameworkForChar(charName, framework) {
        prefs := State.get("char_framework", Map())
        prefs[charName] := framework
        State.set("char_framework", prefs)
    }

    static characters() {
        return State.get("roster", [])
    }
}
