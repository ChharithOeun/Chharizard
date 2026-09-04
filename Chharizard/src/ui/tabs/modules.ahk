; ============================================================================
; ui/tabs/modules.ahk  —  per-character checkbox matrix.
; Writes to addons/Chharbar/data/enabled_by_char.lua so the loader can
; pick the right module set per character on Windower load.
; ============================================================================

class ModulesTab {
    static ALL_MODULES := [
        "vitals","target","distance","targetinfo","chharpt","debuffs",
        "castbar","scoreboard","debuffed","hate","wsc","chharchat",
        "gsassist","silmaril_bridge","autotarget"
    ]

    static charDD := ""
    static checkboxes := Map()

    static build(gui) {
        ThemeApply.h3(gui)
        gui.Add("Text", "x30 y50", "Character:")

        roster := State.get("roster", [])
        if (roster.Length = 0)
            roster := ["(add characters in Roster tab)"]

        ThemeApply.body(gui)
        ModulesTab.charDD := gui.Add("DropDownList", "x+10 w200 vModulesChar", roster)
        ModulesTab.charDD.Choose(1)
        ModulesTab.charDD.OnEvent("Change", (ctrl, *) => ModulesTab._loadForChar(ctrl.Text))

        ThemeApply.muted(gui)
        gui.Add("Text", "x30 y+20 w900",
            "Toggle which HUD modules load for the selected character. Changes save "
            . "on click and take effect next //lua reload chharbar.")

        ThemeApply.body(gui)
        y := 130
        col := 0
        for m in ModulesTab.ALL_MODULES {
            x := 30 + (col * 220)
            cb := gui.Add("Checkbox", "x" . x . " y" . y . " w200 v_cb_" . m, m)
            cb.Value := 1
            cb.OnEvent("Click", (ctrl, *) => ModulesTab._onToggle())
            ModulesTab.checkboxes[m] := cb
            col++
            if (col >= 4) { col := 0; y += 28 }
        }

        ThemeApply.status_ok(gui)
        gui.Add("Button", "x30 y+30 w200", "Save").OnEvent("Click", (*) => ModulesTab._save())
        gui.Add("Button", "x+10 w200",     "Enable all").OnEvent("Click", (*) => ModulesTab._all(true))
        gui.Add("Button", "x+10 w200",     "Disable all").OnEvent("Click", (*) => ModulesTab._all(false))

        if (roster.Length > 0 && roster[1] != "(add characters in Roster tab)")
            ModulesTab._loadForChar(roster[1])
    }

    static _loadForChar(char) {
        result := Commands.run("modules.list", { char: char })
        enabled := result.ok ? result.data : ModulesTab.ALL_MODULES
        for m in ModulesTab.ALL_MODULES {
            found := false
            for e in enabled
                if (e = m) { found := true; break }
            ModulesTab.checkboxes[m].Value := found ? 1 : 0
        }
    }

    static _onToggle() {
        ; Auto-save on toggle
        ModulesTab._save()
    }

    static _save() {
        char := ModulesTab.charDD.Text
        if (char = "" || char = "(add characters in Roster tab)")
            return
        enabled := []
        for m in ModulesTab.ALL_MODULES
            if (ModulesTab.checkboxes[m].Value)
                enabled.Push(m)
        Commands.run("modules.set", { char: char, enabled: enabled })
        State.save()
        log("[Modules] saved " . enabled.Length . " modules for " . char)
    }

    static _all(on) {
        for m, cb in ModulesTab.checkboxes
            cb.Value := on ? 1 : 0
        ModulesTab._save()
    }
}
