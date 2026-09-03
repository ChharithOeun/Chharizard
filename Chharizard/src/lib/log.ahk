; ============================================================================
; lib/log.ahk  —  logs to file (rotating at 500 KB) + emits log:line event
; so the Logs tab, external RPC clients, and future AI can tail live.
; ============================================================================

global LogState := {
    path: A_ScriptDir . "\..\..\..\Chharizard.log",
    maxBytes: 500 * 1024
}

log(msg) {
    ts := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    line := "[" . ts . "] " . msg
    ; Rotate log if too large
    try {
        if (FileExist(LogState.path)) {
            info := FileGetSize(LogState.path)
            if (info > LogState.maxBytes) {
                FileMove(LogState.path, LogState.path . ".old", true)
            }
        }
    }
    try {
        FileAppend(line . "`n", LogState.path, "UTF-8")
    }
    ; Emit event so subscribers (Logs tab, RPC, AI) see live log
    try Events.emit("log:line", line)
}
