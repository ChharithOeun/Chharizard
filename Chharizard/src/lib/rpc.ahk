; ============================================================================
; lib/rpc.ahk  —  local RPC listener for AI + Discord bridge.
;
; v5.1.0: stub. Sets up the pipe name in state, logs startup, but doesn't
; actually listen yet. Real named-pipe listener lands in v5.2.0 along with
; the command protocol spec.
;
; Future protocol (v5.2.0):
;   Client writes:  {"cmd": "modules.set", "args": {"char": "Chharzilla", "enabled": ["vitals","target"]}}
;   Server replies: {"ok": true, "state": {...}}
;
;   {"cmd": "roster.add",    "args": {"name": "Chharzilla"}}
;   {"cmd": "roster.list"}
;   {"cmd": "launcher.start","args": {"char": "Chharzilla"}}
;   {"cmd": "log.tail",      "args": {"lines": 100}}
;   {"cmd": "state.get",     "args": {"key": "roster"}}
;
; Same commands the UI dispatches through Commands.run() — see lib/commands.ahk.
; ============================================================================

class RPC {
    static _running := false

    static start() {
        pipeName := State.get("rpc_pipe_name", "\\.\pipe\chharizard")
        log("[RPC] listener stubbed (v5.1.0). Pipe target: " . pipeName)
        log("[RPC] real listener + protocol arrives in v5.2.0")
        RPC._running := true
        Events.emit("rpc:started", { pipe: pipeName })
    }

    static stop() {
        if (RPC._running) {
            log("[RPC] stopping")
            RPC._running := false
        }
    }

    static isRunning() {
        return RPC._running
    }
}
