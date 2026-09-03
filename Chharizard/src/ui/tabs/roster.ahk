; ============================================================================
; ui/tabs/roster.ahk  —  CRUD your multibox character list.
; ============================================================================

class RosterTab {
    static listCtrl := ""
    static nameInput := ""

    static build(gui) {
        gui.SetFont("s10 bold c40e0e8")
        gui.Add("Text", "x30 y50", "Roster")

        gui.SetFont("s9 c888888")
        gui.Add("Text", "x30 y+5 w900",
            "Your in-game FFXI character names. Saved locally in "
            . "data/chharizard-state.json — never committed to the repo.")

        RosterTab.listCtrl := gui.Add("ListBox", "x30 y+15 w400 h300 vRosterList")
        RosterTab._refresh()

        gui.SetFont("s10 cCCCCCC")
        gui.Add("Text", "x450 y110", "Add character:")
        RosterTab.nameInput := gui.Add("Edit", "x450 y+5 w300 vRosterNewName")

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x450 y+10 w140", "Add").OnEvent("Click", (*) => RosterTab._add())
        gui.Add("Button", "x+10 w140", "Remove selected").OnEvent("Click", (*) => RosterTab._remove())
    }

    static _refresh() {
        RosterTab.listCtrl.Delete()
        roster := State.get("roster", [])
        for name in roster
            RosterTab.listCtrl.Add([name])
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
        sel := RosterTab.listCtrl.Text
        if (sel = "") return
        Commands.run("roster.remove", { name: sel })
        RosterTab._refresh()
        State.save()
        Events.emit("roster:changed", State.get("roster", []))
    }
}
