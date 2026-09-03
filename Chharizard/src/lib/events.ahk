; ============================================================================
; lib/events.ahk  —  pub/sub bus.
;
; Every user action, state change, and background event fires through here.
; The UI subscribes. The future AI plugin will subscribe. The Discord bridge
; will subscribe. Nothing is coupled to anything else — the bus is the API.
;
; Usage:
;   Events.on("modules:changed", (data) => log("modules now: " . data.count))
;   Events.emit("modules:changed", { count: 15, character: "Chharzilla" })
; ============================================================================

class Events {
    static _subs := Map()

    static on(evt, callback) {
        if (!Events._subs.Has(evt))
            Events._subs[evt] := []
        Events._subs[evt].Push(callback)
    }

    static off(evt) {
        if (Events._subs.Has(evt))
            Events._subs.Delete(evt)
    }

    static emit(evt, data := "") {
        if (!Events._subs.Has(evt))
            return
        for cb in Events._subs[evt] {
            try cb(data)
            catch as e {
                ; Don't let a bad subscriber take down the bus
                try FileAppend("[events] handler for " . evt . " threw: " . e.Message . "`n",
                               A_ScriptDir . "\..\..\..\Chharizard.log", "UTF-8")
            }
        }
    }

    static listEvents() {
        arr := []
        for k in Events._subs
            arr.Push(k)
        return arr
    }
}
