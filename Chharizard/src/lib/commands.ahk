; ============================================================================
; lib/commands.ahk  —  single-source command dispatcher.
;
; UI clicks route here. Future RPC calls route here. Future AI decisions
; route here. If it can be done in Chharizard, it goes through this file.
;
; Commands.run("modules.set", { char: "Chharzilla", enabled: ["vitals","target"] })
;
; Returns { ok: true/false, data: ..., error: "..." }
; Emits    cmd:done with the same payload for subscribers.
; ============================================================================

class Commands {
    static _handlers := Map()

    static register(name, fn) {
        Commands._handlers[name] := fn
    }

    static run(name, args := "") {
        if (!Commands._handlers.Has(name)) {
            log("[Commands] unknown command: " . name)
            return { ok: false, error: "unknown command: " . name }
        }
        try {
            data := Commands._handlers[name](args)
            result := { ok: true, data: data }
            Events.emit("cmd:done", { name: name, args: args, result: result })
            return result
        } catch as e {
            log("[Commands] " . name . " threw: " . e.Message)
            result := { ok: false, error: e.Message }
            Events.emit("cmd:done", { name: name, args: args, result: result })
            return result
        }
    }

    static list() {
        arr := []
        for k in Commands._handlers
            arr.Push(k)
        return arr
    }
}

; ----------------------------------------------------------------------------
; Register the v5.1.0 command surface.
; Every one of these will be callable via RPC in v5.2.0 with zero changes.
; ----------------------------------------------------------------------------

; --- Roster --------------------------------------------------------------
Commands.register("roster.list", (args) => State.get("roster", []))

Commands.register("roster.add", (args) => (
    (name := args.name),
    r := State.get("roster", []),
    (r.Push(name)),
    State.set("roster", r),
    (name)
))

Commands.register("roster.remove", (args) => (
    (name := args.name),
    r := State.get("roster", []),
    (newR := []),
    (_removeLoop(r, newR, name)),
    State.set("roster", newR),
    (name)
))

_removeLoop(source, dest, exclude) {
    for x in source
        if (x != exclude)
            dest.Push(x)
}

; --- Modules -------------------------------------------------------------
Commands.register("modules.list", (args) => (
    char := args.HasProp("char") ? args.char : "",
    (char = "" ? State.get("enabled_by_char", Map()) :
        (State.get("enabled_by_char", Map()).Has(char)
            ? State.get("enabled_by_char", Map())[char]
            : []))
))

Commands.register("modules.set", (args) => (
    (char := args.char),
    (list := args.enabled),
    m := State.get("enabled_by_char", Map()),
    (m[char] := list),
    State.set("enabled_by_char", m),
    Events.emit("modules:changed", { char: char, enabled: list }),
    list
))

; --- State / config ------------------------------------------------------
Commands.register("state.get", (args) => State.get(args.key, ""))
Commands.register("state.all", (args) => State.all())

; --- Log -----------------------------------------------------------------
Commands.register("log.tail", (args) => (
    n := args.HasProp("lines") ? args.lines : 50,
    _logTail(n)
))

_logTail(n) {
    path := A_ScriptDir . "\..\..\..\Chharizard.log"
    if (!FileExist(path)) return ""
    text := FileRead(path, "UTF-8")
    lines := StrSplit(text, "`n")
    start := Max(1, lines.Length - n)
    result := ""
    Loop lines.Length - start + 1 {
        idx := start + A_Index - 1
        if (idx <= lines.Length)
            result .= lines[idx] . "`n"
    }
    return result
}
