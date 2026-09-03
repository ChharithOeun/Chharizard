; ============================================================================
; lib/state.ahk  —  central JSON state store.
;
; Every persistent setting lives here. UI reads/writes State; state:changed
; events fire so subscribers refresh. Writing to disk is debounced.
;
; Store schema (data/chharizard-state.json):
; {
;   "last_launch":      "2026-09-03 01:00:00",
;   "framework":        "windower",
;   "framework_path":   "C:\\Windower",
;   "roster":           ["Chharzilla", "..."],
;   "enabled_by_char":  { "Chharzilla": ["vitals","target",...] },
;   "gearswap_prefs":   { ... },
;   "ui_prefs":         { "theme": "dark", ... }
; }
; ============================================================================

class State {
    static _data := Map()
    static _path := A_ScriptDir . "\..\..\..\data\chharizard-state.json"
    static _dirty := false

    static load() {
        try {
            if (!FileExist(State._path)) {
                State._data := State._defaults()
                State.save()
                return
            }
            text := FileRead(State._path, "UTF-8")
            State._data := JSON.Parse(text)
        } catch as e {
            log("[State] load failed: " . e.Message . " — using defaults")
            State._data := State._defaults()
        }
    }

    static save() {
        try {
            DirCreate(A_ScriptDir . "\..\..\..\data")
            text := JSON.Stringify(State._data, "  ")
            FileDelete(State._path)
            FileAppend(text, State._path, "UTF-8")
            State._dirty := false
        } catch as e {
            log("[State] save failed: " . e.Message)
        }
    }

    static get(key, default := "") {
        if (State._data.Has(key))
            return State._data[key]
        return default
    }

    static set(key, value) {
        oldValue := State._data.Has(key) ? State._data[key] : ""
        State._data[key] := value
        State._dirty := true
        Events.emit("state:changed", { key: key, oldValue: oldValue, newValue: value })
    }

    static all() {
        return State._data
    }

    static _defaults() {
        d := Map()
        d["last_launch"] := ""
        d["framework"] := "none"
        d["framework_path"] := ""
        d["chharizard_repo"] := A_ScriptDir . "\..\..\.."  ; parent of Chharizard/
        d["roster"] := []
        d["enabled_by_char"] := Map()
        d["ui_prefs"] := Map("theme", "dark", "startup_tab", "dashboard")
        d["ai_enabled"] := false
        d["discord_bridge_enabled"] := false
        d["rpc_pipe_name"] := "\\.\pipe\chharizard"
        return d
    }
}
