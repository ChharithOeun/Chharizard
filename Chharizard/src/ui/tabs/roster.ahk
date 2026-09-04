; ============================================================================
; ui/tabs/roster.ahk  —  CRUD your multibox character list + per-char
; framework preference (Windower or Ashita).
; ============================================================================

class RosterTab {
    static listCtrl := ""
    static nameInput := ""
    static fwDropdown := ""
    static charLabel := ""

    static build(gui) {
        ThemeApply.h3(gui)
        gui.Add("Text", "x30 y50", "Roster")

        ThemeApply.muted(gui)
        gui.Add("Text", "x30 y+5 w900",
            "Your in-game FFXI character names + which framework each launches "
            . "with. Saved locally in data/chharizard-state.json — never committed.")

        RosterTab.listCtrl := gui.Add("ListBox", "x30 y+15 w400 h280 vRosterList")
        RosterTab.listCtrl.OnEvent("Change", (ctrl, *) => RosterTab._onSelect())
        RosterTab._refresh()

        ThemeApply.body(gui)
        gui.Add("Text", "x450 y110", "Add character:")
        RosterTab.nameInput := gui.Add("Edit", "x450 y+5 w300 vRosterNewName")

        ThemeApply.status_ok(gui)
        gui.Add("Button", "x450 y+10 w140", "Add")
            .OnEvent("Click", (*) => RosterTab._add())
        gui.Add("Button", "x+10 w140", "Remove selected")
            .OnEvent("Click", (*) => RosterTab._remove())

        ThemeApply.h2(gui)
        RosterTab.charLabel := gui.Add("Text", "x450 y+25 w300 vRosterCharLabel",
            "Select a character to set framework")

        ThemeApply.body(gui)
        gui.Add("Text", "x450 y+10", "Framework:")
        RosterTab.fwDropdown := gui.Add("DropDownList", "x450 y+5 w300 vRosterFw",
            ["auto (use primary detected)", "windower", "ashita"])
        RosterTab.fwDropdown.Choose(1)
        RosterTab.fwDropdown.OnEvent("Change", (ctrl, *) => RosterTab._setFramework())
    }

    static _refresh() {
        RosterTab.listCtrl.Delete()
        roster := State.get("roster", [])
        prefs := State.get("char_framework", Map())
        for name in roster {
            fw := prefs.Has(name) ? prefs[name] : "auto"
            RosterTab.listCtrl.Add([name . "  [" . fw . "]"])
        }
    }

    static _onSelect() {
        raw := RosterTab.listCtrl.Text
        if (raw = "") return
        ; Strip trailing "  [fw]" tag
        name := raw
        if (i := InStr(raw, "  ["))
            name := SubStr(raw, 1, i - 1)
        prefs := State.get("char_framework", Map())
        fw := prefs.Has(name) ? prefs[name] : "auto"
        RosterTab.charLabel.Text := "Framework for " . name . ":"
        idx := (fw = "windower") ? 2 : (fw = "ashita") ? 3 : 1
        RosterTab.fwDropdown.Choose(idx)
    }

    static _setFramework() {
        raw := RosterTab.listCtrl.Text
        if (raw = "") return
        name := raw
        if (i := InStr(raw, "  ["))
            name := SubStr(raw, 1, i - 1)
        choice := RosterTab.fwDropdown.Text
        fw := (InStr(choice, "windower")) ? "windower"
            : (InStr(choice, "ashita"))   ? "ashita"
            : "auto"
        Detect.setFrameworkForChar(name, fw)
        State.save()
        RosterTab._refresh()
        log("[Roster] " . name . " -> framework=" . fw)
    }

    static _add() {
        name := Trim(RosterTab.nameInput.Value)
        if (name = "") return
        Commands.run("roster.add", { name: name })
        RosterTab.nameInput.Value := ""
        RosterTab._refresh()
        State.save()
        Events.emit("roster:changed", State.get("roster", []))
    }

    static _remove() {
        raw := RosterTab.listCtrl.Text
        if (raw = "") return
        name := raw
        if (i := InStr(raw, "  ["))
            name := SubStr(raw, 1, i - 1)
        Commands.run("roster.remove", { name: name })
        RosterTab._refresh()
        State.save()
        Events.emit("roster:changed", State.get("roster", []))
    }
}
