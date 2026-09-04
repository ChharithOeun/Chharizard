; ============================================================================
; Chharizard.ahk  —  entry point for the Chharizard companion app.
;
; Architecture: event bus + state store + tabbed GUI + RPC listener + plugin
; folder. Designed so a future AI (Chharbot autonomous mode) and Discord
; wiki-bot can subscribe to the same events and emit the same commands as
; the human UI, without a single line of refactor here.
;
; Author: Chharizard
; Repo:   https://github.com/ChharithOeun/Chharizard
; ============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

; ----------------------------------------------------------------------------
; App metadata (single source of truth — the .exe reads this for version
; comparison in the auto-updater, and the GUI title bar renders it).
; ----------------------------------------------------------------------------
global CHZ := {
    name:    "Chharizard",
    version: "5.3.0",
    author:  "Chharizard",
    repo:    "https://github.com/ChharithOeun/Chharizard",
    api:     "https://api.github.com/repos/ChharithOeun/Chharizard/releases/latest"
}

; ----------------------------------------------------------------------------
; Load libraries in dependency order.
; ----------------------------------------------------------------------------
#Include lib\json.ahk         ; JSON encode/decode (JXON, small vendored)
#Include lib\log.ahk          ; log() — file + UI subscribable
#Include lib\events.ahk       ; on(evt, fn), emit(evt, data) — pub/sub bus
#Include lib\state.ahk        ; State.get/set/save/load, publishes state:changed
#Include lib\config.ahk       ; Config.paths — Windower/Ashita/repo dirs
#Include lib\detect.ahk       ; Detect.framework(), Detect.characters()
#Include lib\rpc.ahk          ; RPC.start() — named pipe listener (stub v5.1.0)
#Include lib\commands.ahk     ; Every UI action + AI action + RPC call routes here
#Include lib\updater.ahk      ; GitHub Releases auto-updater (v5.2.0)
#Include lib\launcher.ahk     ; Windower/Ashita launcher (v5.2.0)
#Include lib\tune.ahk         ; Embedded FFXI system tuner (v5.3.0)

; ----------------------------------------------------------------------------
; Load UI (main window + all tab modules).
; ----------------------------------------------------------------------------
#Include ui\main_window.ahk
#Include ui\tabs\dashboard.ahk
#Include ui\tabs\modules.ahk
#Include ui\tabs\roster.ahk
#Include ui\tabs\launcher.ahk
#Include ui\tabs\tune.ahk
#Include ui\tabs\update.ahk
#Include ui\tabs\logs.ahk
#Include ui\tabs\plugins.ahk

; ----------------------------------------------------------------------------
; Boot sequence.
; ----------------------------------------------------------------------------
log("=== Chharizard " . CHZ.version . " starting ===")
log("Working dir: " . A_ScriptDir)

; Load persisted state (paths, per-character enabled modules, roster).
State.load()
log("State loaded: " . State.get("last_launch", "never"))

; Detect Windower / Ashita installation.
Config.detect()
if (Config.framework = "none") {
    log("[WARN] No Windower or Ashita install detected. First-run wizard.")
} else {
    log("Framework: " . Config.framework . " at " . Config.frameworkPath)
}

; Discover plugins (future AI plugin, Discord bridge, etc.).
PluginsTab.discover()
log("Plugins discovered: " . PluginsTab.count())

; Start local RPC listener (named pipe) so external tools (Discord bot, AI)
; can send commands. Stub in v5.1.0 — real handler in v5.2.0.
RPC.start()

; Build and show the main window.
MainWindow.build()
MainWindow.show()

; Autoclose event handler wires state.save() on window close.
OnExit(ShutdownHandler)

ShutdownHandler(reason, code) {
    log("Shutting down (" . reason . ")")
    State.set("last_launch", A_Now)
    State.save()
    RPC.stop()
}
