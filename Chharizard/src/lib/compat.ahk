; ============================================================================
; lib/compat.ahk  —  version self-recovery (v5.6.0).
;
; Reads manifest.json at repo root (declares known-good versions of every
; component) + reads local component versions from file headers. Reports
; drift, offers one-click repair via the updater.
;
; A component is "healthy" when:
;   - its version matches the manifest exactly, OR
;   - the manifest's requires_exe range accepts the current CHZ.version
;
; Drift categories:
;   OK       — versions match
;   OUTDATED — local component is older than manifest (repair = update)
;   NEWER    — local is newer than manifest (rare; repair = downgrade or
;              update exe to a manifest that recognizes it)
;   MISSING  — file not present on disk (repair = pull from release)
;   UNKNOWN  — file present but version couldn't be parsed
; ============================================================================

class Compat {
    static _manifest := ""
    static _report := []

    static manifestPath() {
        return Config.repoRoot() . "\manifest.json"
    }

    ; Load manifest.json from repo root. Returns the parsed Map or "" on
    ; failure. Cached in _manifest for subsequent calls.
    static loadManifest() {
        if (Compat._manifest != "")
            return Compat._manifest
        path := Compat.manifestPath()
        if (!FileExist(path)) {
            log("[Compat] manifest.json not found at " . path)
            return ""
        }
        try {
            text := FileRead(path, "UTF-8")
            Compat._manifest := JSON.Parse(text)
            return Compat._manifest
        } catch as e {
            log("[Compat] manifest parse failed: " . e.Message)
            return ""
        }
    }

    ; Parse a version string from a file. Looks for common patterns:
    ;   _addon.version = 'X.Y.Z'    (Lua addon)
    ;   version: "X.Y.Z"            (AHK / JSON)
    ;   Version: X.Y                (PS1 comment)
    ;   # Version: X.Y.Z            (PS1 param block)
    static readComponentVersion(relativePath) {
        fullPath := Config.repoRoot() . "\" . StrReplace(relativePath, "/", "\")
        if (!FileExist(fullPath))
            return { status: "MISSING", version: "" }
        try {
            text := FileRead(fullPath, "UTF-8")
        } catch as e {
            return { status: "UNKNOWN", version: "" }
        }
        ; Try several patterns
        patterns := [
            "_addon\.version\s*=\s*['""]([0-9]+\.[0-9]+\.[0-9]+)['""]",
            "version:\s*['""]([0-9]+\.[0-9]+\.[0-9]+)['""]",
            "Version:\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)",
            "#\s*Version:\s*([0-9]+\.[0-9]+(?:\.[0-9]+)?)"
        ]
        for pat in patterns {
            if (RegExMatch(text, pat, &m)) {
                v := m[1]
                ; Normalize X.Y → X.Y.0
                if (RegExMatch(v, "^\d+\.\d+$"))
                    v := v . ".0"
                return { status: "OK", version: v }
            }
        }
        return { status: "UNKNOWN", version: "" }
    }

    ; Compare two semver-ish strings. Returns 1 (a>b), 0 (=), -1 (a<b).
    static compareVersion(a, b) {
        ap := StrSplit(a, ".")
        bp := StrSplit(b, ".")
        Loop 3 {
            ai := (A_Index <= ap.Length) ? Integer(ap[A_Index]) : 0
            bi := (A_Index <= bp.Length) ? Integer(bp[A_Index]) : 0
            if (ai > bi) return 1
            if (ai < bi) return -1
        }
        return 0
    }

    ; Run a full compat scan. Returns an array of per-component reports:
    ;   { name, expected, local, status: "OK|OUTDATED|NEWER|MISSING|UNKNOWN",
    ;     path, note }
    static scan() {
        m := Compat.loadManifest()
        if (m = "") {
            return [{
                name: "manifest",
                expected: "",
                local: "",
                status: "MISSING",
                path: Compat.manifestPath(),
                note: "manifest.json not found or unreadable"
            }]
        }
        report := []
        ; First: the exe itself
        exeExpected := m.Has("chharizard") ? m["chharizard"] : ""
        exeCmp := Compat.compareVersion(CHZ.version, exeExpected)
        report.Push({
            name: "Chharizard.exe",
            expected: exeExpected,
            local: CHZ.version,
            status: (exeCmp = 0) ? "OK" : (exeCmp < 0) ? "OUTDATED" : "NEWER",
            path: "(this process)",
            note: (exeCmp < 0)
                ? "Update Chharizard via the Update tab to align with manifest."
                : (exeCmp > 0) ? "Local exe is newer than manifest — pull latest release for a fresh manifest." : ""
        })
        ; Then: each component
        if (m.Has("components")) {
            comps := m["components"]
            for name, spec in comps {
                relPath := spec.Has("path") ? spec["path"] : ""
                expected := spec.Has("version") ? spec["version"] : ""
                fileInfo := Compat.readComponentVersion(relPath)
                status := "OK"
                note := ""
                if (fileInfo.status = "MISSING") {
                    status := "MISSING"
                    note := "File not found — pull from latest release."
                } else if (fileInfo.status = "UNKNOWN") {
                    status := "UNKNOWN"
                    note := "Could not parse version from file header."
                } else {
                    cmp := Compat.compareVersion(fileInfo.version, expected)
                    if (cmp < 0) {
                        status := "OUTDATED"
                        note := "Local " . fileInfo.version . " is older than manifest " . expected . " — repair recommended."
                    } else if (cmp > 0) {
                        status := "NEWER"
                        note := "Local " . fileInfo.version . " is newer than manifest — usually fine, but exe may not recognize new features."
                    }
                }
                report.Push({
                    name: name,
                    expected: expected,
                    local: fileInfo.version,
                    status: status,
                    path: relPath,
                    note: note
                })
            }
        }
        Compat._report := report
        Events.emit("compat:scanned", { count: report.Length })
        return report
    }

    ; Attempt self-repair. Currently: any component MISSING or OUTDATED is
    ; fixed by re-running the updater (pulls latest release which contains
    ; correct versions of everything).
    static repair() {
        needsRepair := false
        for r in Compat._report {
            if (r.status = "MISSING" || r.status = "OUTDATED") {
                needsRepair := true
                break
            }
        }
        if (!needsRepair) {
            log("[Compat] no repair needed — all components healthy.")
            return { repaired: false, reason: "no drift detected" }
        }
        log("[Compat] running update.apply to re-sync components...")
        return Commands.run("update.apply")
    }

    ; Health summary: single-line status for the Dashboard.
    static summary() {
        if (Compat._report.Length = 0)
            Compat.scan()
        okCount := 0
        driftCount := 0
        missingCount := 0
        for r in Compat._report {
            if      (r.status = "OK")       okCount++
            else if (r.status = "MISSING")  missingCount++
            else                            driftCount++
        }
        return {
            total:   Compat._report.Length,
            ok:      okCount,
            drift:   driftCount,
            missing: missingCount,
            healthy: (driftCount = 0 && missingCount = 0)
        }
    }
}

; ----------------------------------------------------------------------------
; Register compat commands with the dispatcher.
; ----------------------------------------------------------------------------
Commands.register("compat.scan",    (args) => Compat.scan())
Commands.register("compat.summary", (args) => Compat.summary())
Commands.register("compat.repair",  (args) => Compat.repair())
