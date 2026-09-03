# Chharizard Plugins

Drop `.ahk` files in this folder. Chharizard scans this directory on startup and lists all found plugins in the **Plugins** tab.

Each plugin should:

1. Subscribe to events via `Events.on(evt, callback)`
2. Register commands via `Commands.register("your.command", handler)`
3. Optionally draw its own UI via a new tab (see `ui/tabs/*.ahk` for the pattern)

## Planned first-party plugins

- **chharbot-ai.ahk** — local AI model (via ollama or llama.cpp CLI) that watches game state and issues suggestions or takes actions autonomously.
- **discord-bridge.ahk** — connects Chharizard to a Discord bot so team members can query state or issue commands from Discord.

Both plugins will use the same `Commands.run()` surface that the UI uses. Adding them requires zero changes to Chharizard core.
