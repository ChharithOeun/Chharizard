; ============================================================================
; lib/rpc.ahk  —  file-based RPC listener (v5.5.0).
;
; Transport: JSON files dropped into data/rpc/inbox/ by external processes.
; Chharizard polls every 250ms, dispatches through Commands.run(), writes
; the response as JSON to data/rpc/outbox/. Inbox files auto-deleted after
; processing. Outbox files kept for the client to read; client is expected
; to delete them after read.
;
; Protocol (per file):
;   REQUEST  (inbox):  {"id": "<uuid>", "cmd": "modules.set", "args": {...}}
;   RESPONSE (outbox): {"id": "<uuid>", "ok": true, "data": ...}
;   or:                {"id": "<uuid>", "ok": false, "error": "..."}
;
; The "id" field lets a client correlate requests to responses. Outbox files
; are named "<id>.json".
;
; Rate limit: 10 requests per second (drop oldest if exceeded).
;
; Security: only files in data/rpc/inbox/ are processed. Any process with
; write access to that directory can dispatch commands — no different
; from any process with access to your user's files. Do NOT expose
; data/rpc/ to untrusted users.
;
; Upgrade path: v5.5.1 will add a named-pipe transport for real-time
; latency. Same JSON protocol, no client changes required (they'd just
; open the pipe instead of writing files).
; ============================================================================

class RPC {
    static _running := false
    static _inbox := ""
    static _outbox := ""
    static _rateWindow := []   ; timestamps of processed requests (last second)

    static start() {
        RPC._inbox  := A_ScriptDir . "\..\..\data\rpc\inbox"
        RPC._outbox := A_ScriptDir . "\..\..\data\rpc\outbox"
        try DirCreate(RPC._inbox)
        try DirCreate(RPC._outbox)
        log("[RPC] inbox:  " . RPC._inbox)
        log("[RPC] outbox: " . RPC._outbox)
        SetTimer(() => RPC._poll(), 250)
        RPC._running := true
        Events.emit("rpc:started", { inbox: RPC._inbox, outbox: RPC._outbox })
    }

    static stop() {
        SetTimer(() => RPC._poll(), 0)
        RPC._running := false
        log("[RPC] stopped")
    }

    static isRunning() {
        return RPC._running
    }

    static _poll() {
        if (!RPC._running || !DirExist(RPC._inbox))
            return
        Loop Files, RPC._inbox . "\*.json", "F" {
            try {
                RPC._processFile(A_LoopFileFullPath, A_LoopFileName)
            } catch as e {
                log("[RPC] processFile error: " . e.Message)
                try FileDelete(A_LoopFileFullPath)
            }
        }
    }

    static _processFile(path, filename) {
        ; Rate limit: max 10 in the last 1000ms
        now := A_TickCount
        newWindow := []
        for ts in RPC._rateWindow {
            if (now - ts < 1000)
                newWindow.Push(ts)
        }
        RPC._rateWindow := newWindow
        if (RPC._rateWindow.Length >= 10) {
            log("[RPC] rate limit hit, deferring " . filename)
            return  ; leave the file for next tick
        }
        RPC._rateWindow.Push(now)

        text := FileRead(path, "UTF-8")
        FileDelete(path)   ; delete inbox file immediately after read

        req := ""
        try req := JSON.Parse(text)
        catch as e {
            RPC._writeError(filename, "", "JSON parse: " . e.Message)
            return
        }

        id := (Type(req) = "Map" && req.Has("id")) ? req["id"] : ""
        cmd := (Type(req) = "Map" && req.Has("cmd")) ? req["cmd"] : ""
        args := (Type(req) = "Map" && req.Has("args")) ? req["args"] : Map()

        if (cmd = "") {
            RPC._writeError(filename, id, "missing 'cmd' field")
            return
        }

        log("[RPC] " . id . " -> " . cmd)
        result := Commands.run(cmd, args)

        resp := Map()
        resp["id"] := id
        resp["cmd"] := cmd
        resp["ts"] := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
        if (result.ok) {
            resp["ok"] := true
            resp["data"] := (result.HasProp("data") ? result.data : "")
        } else {
            resp["ok"] := false
            resp["error"] := (result.HasProp("error") ? result.error : "unknown")
        }

        outName := (id != "") ? (id . ".json") : ("resp_" . A_TickCount . ".json")
        outPath := RPC._outbox . "\" . outName
        try FileDelete(outPath)
        FileAppend(JSON.Stringify(resp, "  "), outPath, "UTF-8")
        Events.emit("rpc:handled", { id: id, cmd: cmd, ok: result.ok })
    }

    static _writeError(filename, id, msg) {
        log("[RPC] error on " . filename . ": " . msg)
        resp := Map("id", id, "ok", false, "error", msg,
                    "ts", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"))
        outName := (id != "") ? (id . ".json") : ("err_" . A_TickCount . ".json")
        outPath := RPC._outbox . "\" . outName
        try FileDelete(outPath)
        FileAppend(JSON.Stringify(resp, "  "), outPath, "UTF-8")
    }

    ; Diagnostic helpers exposed as commands
    static status() {
        inboxCount  := 0
        outboxCount := 0
        try Loop Files, RPC._inbox . "\*.json",  "F" { inboxCount++  }
        try Loop Files, RPC._outbox . "\*.json", "F" { outboxCount++ }
        return {
            running:      RPC._running,
            inbox:        RPC._inbox,
            outbox:       RPC._outbox,
            inboxPending: inboxCount,
            outboxUnread: outboxCount,
            rateWindow:   RPC._rateWindow.Length
        }
    }
}

; ----------------------------------------------------------------------------
; Register RPC-side introspection commands.
; ----------------------------------------------------------------------------
Commands.register("rpc.status", (args) => RPC.status())
Commands.register("rpc.ping",   (args) => "pong")
