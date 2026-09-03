; ============================================================================
; ui/tabs/plugins.ahk  —  scan plugins/ folder, list installed plugins.
;
; Plugins are .ahk files that get #Included by main.ahk on load. Each plugin
; subscribes to events, registers commands, or draws its own UI panel. The
; future AI (Chharbot) and Discord bridge will each ship as a plugin — drop
; the .ahk in plugins/, restart Chharizard, and it's live.
; ============================================================================

class PluginsTab {
    static _plugins := []
    static listCtrl := ""

    static build(gui) {
        gui.SetFont("s10 bold c40e0e8")
        gui.Add("Text", "x30 y50", "Plugins")

        gui.SetFont("s9 cCCCCCC")
        gui.Add("Text", "x30 y+10 w900",
            "Optional .ahk plugins in the plugins/ folder. Drop a plugin file "
            . "there, restart Chharizard, and it registers itself. Future "
            . "Chharbot AI and Discord wiki-bridge will ship as plugins.")

        PluginsTab.listCtrl := gui.Add("ListBox", "x30 y+15 w900 h300 vPluginsList")
        PluginsTab._render()

        gui.SetFont("s10 c40e0e8")
        gui.Add("Button", "x30 y+10 w200", "Rescan plugins/").OnEvent("Click",
            (*) => (PluginsTab.discover(), PluginsTab._render()))
        gui.Add("Button", "x+10 w200", "Open plugins folder").OnEvent("Click",
            (*) => Run("explorer.exe " . A_ScriptDir . "\..\plugins"))
    }

    static discover() {
        PluginsTab._plugins := []
        pluginDir := A_ScriptDir . "\..\plugins"
        if (!DirExist(pluginDir)) return
        Loop Files, pluginDir . "\*.ahk", "F" {
            PluginsTab._plugins.Push({ name: A_LoopFileName, path: A_LoopFilePath })
        }
    }

    static count() {
        return PluginsTab._plugins.Length
    }

    static _render() {
        if (PluginsTab.listCtrl = "") return
        PluginsTab.listCtrl.Delete()
        if (PluginsTab._plugins.Length = 0) {
            PluginsTab.listCtrl.Add(["(no plugins installed — drop .ahk files in plugins/)"])
            return
        }
        for p in PluginsTab._plugins
            PluginsTab.listCtrl.Add([p.name])
    }
}
