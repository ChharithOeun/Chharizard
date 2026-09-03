# Chharizard.exe

The Windows companion app for the Chharizard ecosystem. AutoHotkey v2 based.

## Architecture

```
src/
├── Chharizard.ahk         # Entry point
├── lib/
│   ├── json.ahk           # JSON encode/decode (vendored)
│   ├── log.ahk            # File log + subscribable log:line event
│   ├── events.ahk         # Pub/sub bus (on/off/emit)
│   ├── state.ahk          # Central JSON state store
│   ├── config.ahk         # Paths, framework detection facts
│   ├── detect.ahk         # Windower/Ashita location + character discovery
│   ├── rpc.ahk            # Local RPC listener (stub v5.1.0)
│   └── commands.ahk       # Single command dispatcher — UI/RPC/AI all route here
├── ui/
│   ├── main_window.ahk    # Top window + tabs
│   └── tabs/
│       ├── dashboard.ahk  # Framework status + quick actions
│       ├── modules.ahk    # Per-character module toggle matrix (functional)
│       ├── roster.ahk     # Character CRUD (functional)
│       ├── launcher.ahk   # Launch Windower per character (stub v5.2.0)
│       ├── tune.ahk       # Embedded FFXI tuner (stub v5.2.0)
│       ├── update.ahk     # GitHub releases auto-updater (stub v5.2.0)
│       ├── logs.ahk       # Live log tail (functional)
│       └── plugins.ahk    # Plugin discovery (functional)
└── plugins/               # Drop .ahk files here — auto-discovered
build/
├── BUILD.bat              # Compile to Chharizard.exe via Ahk2Exe
└── Chharizard.exe         # Compiled release (built by BUILD.bat)
```

## Development

**Requires AutoHotkey v2.** Install from https://www.autohotkey.com/ (choose the v2 installer).

Run the app without compiling:
```
RUN-DEV.bat
```

Compile to a standalone `.exe`:
```
build\BUILD.bat
```

## AI-ready and Discord-ready

Every user action goes through `Commands.run(name, args)`. Every state change emits an event via `Events.emit(evt, data)`. When Chharbot (AI) and the Discord wiki-bridge arrive:

- They subscribe to the same event bus
- They call the same command dispatcher
- They drop in as `.ahk` files in `plugins/`
- Zero refactor to Chharizard core

The RPC listener (v5.2.0) exposes `Commands.run()` over a named pipe so external processes (Python, Node, other exes) can drive Chharizard the same way.

## Contact

Bug reports: https://github.com/ChharithOeun/Chharizard/issues
**Do NOT contact in-game.**
