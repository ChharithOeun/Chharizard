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
        ThemeApply.h3(gui)
        gui.Add("Text", "x30 y50", "Plugins")

        ThemeApply.small(gui)
        gui.Add("Text", "x30 y+10 w900",
            "Optional .ahk plugins in the plugins/ folder. Drop a plugin file "
            . "there, restart Chharizard, and it registers itself. Future "
            . "Chharbot AI and Discord wiki-bridge will ship as plugins.")

        ; --- RPC status (v5.5.0) -------------------------------------------
        ThemeApply.h2(gui)
        gui.Add("Text", "x30 y+15", "External RPC (v5.5.0)")

        ThemeApply.small(gui)
        rpcStatus := RPC.status()
        gui.Add("Text", "x30 y+5 w900",
            "Status: " . (rpcStatus.running ? "listening" : "stopped")
            . "  |  inbox pending: " . rpcStatus.inboxPending
            . "  |  outbox unread: " . rpcStatus.outboxUnread)
        gui.Add("Text", "x30 y+3 w900", "Inbox:  " . rpcStatus.inbox)
        gui.Add("Text", "x30 y+3 w900", "Outbox: " . rpcStatus.outbox)
        gui.Add("Text", "x30 y+3 w900",
            "Any external process (Discord bot, AI, Python) can drop JSON "
            . "requests in inbox/ and read responses from outbox/. See "
            . "docs/RPC-PROTOCOL.md for full protocol + client examples.")

        ThemeApply.status_ok(gui)
        gui.Add("Button", "x30 y+10 w200", "Open RPC folder")
            .OnEvent("Click", (*) => Run("explorer.exe " . RPC._inbox . "\.."))
        gui.Add("Button", "x+10 w200", "Send test ping")
            .OnEvent("Click", (*) => PluginsTab._testPing())

        ; --- Plugins section ------------------------------------------------
        ThemeApply.h2(gui)
        gui.Add("Text", "x30 y+20", "Plugins")

        PluginsTab.listCtrl := gui.Add("ListBox", "x30 y+10 w900 h240 vPluginsList")
        PluginsTab._render()

        ThemeApply.status_ok(gui)
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

    static _testPing() {
        result := Commands.run("rpc.ping")
        MsgBox("RPC dispatcher result:`n`nok=" . (result.ok ? "true" : "false")
            . "`ndata=" . (result.HasProp("data") ? result.data : "(none)"))
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
