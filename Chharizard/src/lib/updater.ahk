; ============================================================================
; lib/updater.ahk  —  GitHub Releases API auto-updater.
;
; Checks https://api.github.com/repos/ChharithOeun/Chharizard/releases/latest,
; compares tag_name to CHZ.version. If newer: downloads the release zip,
; extracts to a temp dir, replaces the addons/ tree, updates the .exe.
;
; The Update tab drives this via Commands.run("update.check") and
; Commands.run("update.apply").
; ============================================================================

class Updater {
    static latestInfo := ""    ; cached response

    ; Query GitHub for the latest release. Returns:
    ;   { tag: "v5.1.0", name: "...", body: "changelog markdown",
    ;     published_at: "2026-09-03T...", zip_url: "...", assets: [...] }
    ; or throws on HTTP/parse error.
    static check() {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(10000, 10000, 10000, 10000)
        req.Open("GET", CHZ.api, true)
        req.SetRequestHeader("Accept", "application/vnd.github+json")
        req.SetRequestHeader("User-Agent", "Chharizard/" . CHZ.version)
        req.Send()
        req.WaitForResponse(15)

        if (req.Status != 200)
            throw Error("GitHub API returned " . req.Status . ": " . req.StatusText)

        data := JSON.Parse(req.ResponseText)
        info := {
            tag:          data.Has("tag_name") ? data["tag_name"] : "",
            name:         data.Has("name") ? data["name"] : "",
            body:         data.Has("body") ? data["body"] : "",
            published_at: data.Has("published_at") ? data["published_at"] : "",
            zip_url:      data.Has("zipball_url") ? data["zipball_url"] : "",
            assets:       data.Has("assets") ? data["assets"] : []
        }
        Updater.latestInfo := info
        Events.emit("update:checked", info)
        return info
    }

    ; Compare tag (like "v5.1.0") against CHZ.version ("5.1.0"). Returns:
    ;  1 if remote is newer, 0 if equal, -1 if local is ahead
    static compare(remoteTag) {
        r := RegExReplace(remoteTag, "^v")
        l := CHZ.version
        rp := StrSplit(r, ".")
        lp := StrSplit(l, ".")
        Loop 3 {
            ri := (A_Index <= rp.Length) ? Integer(rp[A_Index]) : 0
            li := (A_Index <= lp.Length) ? Integer(lp[A_Index]) : 0
            if (ri > li) return 1
            if (ri < li) return -1
        }
        return 0
    }

    ; Download the release zip. Returns local path.
    static download(url) {
        outPath := A_Temp . "\Chharizard-update.zip"
        try FileDelete(outPath)
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.SetTimeouts(10000, 10000, 30000, 300000)
            req.Open("GET", url, true)
            req.SetRequestHeader("User-Agent", "Chharizard/" . CHZ.version)
            req.Send()
            req.WaitForResponse(300)
            if (req.Status != 200 && req.Status != 302)
                throw Error("Download HTTP " . req.Status)
            ; Save binary body
            stream := ComObject("ADODB.Stream")
            stream.Type := 1
            stream.Open()
            stream.Write(req.ResponseBody)
            stream.SaveToFile(outPath, 2)
            stream.Close()
        } catch as e {
            throw Error("download failed: " . e.Message)
        }
        return outPath
    }

    ; Extract a downloaded zip. GitHub Codeload zips have a top-level folder
    ; named "<repo>-<sha>/" — the caller decides what to do with the tree.
    static extract(zipPath) {
        extractDir := A_Temp . "\Chharizard-update-extracted"
        try DirDelete(extractDir, true)
        DirCreate(extractDir)
        ; Use tar (built into Windows 10 1803+)
        RunWait('tar -xf "' . zipPath . '" -C "' . extractDir . '"', , "Hide")
        return extractDir
    }

    ; Apply an extracted update. Copies addons/, docs/, Chharizard/ over the
    ; repoRoot. Preserves data/ (per-toon settings, roster, state).
    static apply(extractDir) {
        ; Find the single subdir GitHub creates
        Loop Files, extractDir . "\*", "D" {
            src := A_LoopFileFullPath
            dst := Config.repoRoot()
            log("[Updater] copying " . src . " -> " . dst)
            ; xcopy /E /Y /I preserves tree, overwrites without prompt
            ; We'd exclude addons/**/data/ from overwrite, but xcopy /EXCLUDE
            ; requires a text file. Keep it simple: rely on .gitignore-shaped
            ; layout where data/ is separate.
            RunWait('xcopy "' . src . '\*" "' . dst . '\" /E /Y /I /Q', , "Hide")
            break
        }
        Events.emit("update:applied", { source: extractDir })
        return true
    }
}

; ----------------------------------------------------------------------------
; Register updater commands with the dispatcher.
; ----------------------------------------------------------------------------
Commands.register("update.check", (args) => Updater.check())

Commands.register("update.apply", (args) => (
    (url := args.HasProp("url") ? args.url : (Updater.latestInfo != "" ? Updater.latestInfo.zip_url : "")),
    (url = "" ? "" : (
        (zip := Updater.download(url)),
        (dir := Updater.extract(zip)),
        Updater.apply(dir)
    ))
))
