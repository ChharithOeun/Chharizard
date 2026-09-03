# Chharizard Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Chharizard.exe    (Windows companion, AutoHotkey v2)         │
│  - Module toggle UI      - Roster manager                     │
│  - Character launcher    - Auto-updater (GitHub Releases)     │
│  - Gearswap builder GUI  - Tune-FFXI runner (embedded)        │
│  - Framework detector    - Deploys correct adapter            │
└──────────────────┬───────────────────────────────────────────┘
                   │  writes JSON configs, deploys files
                   ▼
┌──────────────────────────────────────────────────────────────┐
│  addons/{Chharbar,Chharsai,Chharcam,Chhargear}/               │
│  ├── core/framework.lua       (abstract API)                  │
│  ├── core/compat_windower.lua (loaded on Windower installs)   │
│  ├── core/compat_ashita.lua   (loaded on Ashita installs)     │
│  └── modules/*.lua            (framework-agnostic)            │
└──────────────────┬───────────────────────────────────────────┘
                   │  framework-specific Lua API
                   ▼
┌──────────────────────────┐   ┌──────────────────────────────┐
│  Windower 4 (retail)     │   │  Ashita v4 (private servers) │
│  windower.*, Lua 5.1     │   │  ashita.*, Lua 5.4           │
└──────────────┬───────────┘   └──────────────┬───────────────┘
               ▼                              ▼
┌──────────────────────────────────────────────────────────────┐
│  FFXI client (pol.exe / retail or private-server variant)     │
└──────────────────────────────────────────────────────────────┘
```

## Framework abstraction

The core problem: **Windower and Ashita have similar Lua APIs but they are not compatible.** Both expose events like `load`, `unload`, `prerender`, `incoming chunk`, `incoming text`, but with different function signatures, different data shapes, and different modules for text/image drawing, packet access, and command registration.

Solution: `core/framework.lua` defines an abstract API. Every module uses only that API. Two adapters implement it:

- `core/compat_windower.lua` — Windower 4 (Lua 5.1) — production-ready in v5.0.x
- `core/compat_ashita.lua` — Ashita v4 (Lua 5.4) — planned v5.3.0

Chharizard.exe detects which framework is installed and drops the correct adapter alongside the modules at install time. Modules never import `windower.*` or `ashita.*` directly.

### Abstract API surface (v1)

```lua
-- Player / target
FW.get_player()          -- {name, id, hp, mp, tp, main_job, sub_job, ...}
FW.get_target()          -- {name, id, hp_pct, distance, ...} or nil
FW.get_party()           -- array of {name, id, hp_pct, ...}

-- Events (registered handlers called with framework-normalized args)
FW.on_load(fn)
FW.on_unload(fn)
FW.on_prerender(fn)
FW.on_incoming_chunk(id, fn)
FW.on_incoming_text(fn)      -- fn(text, mode) returning modified text
FW.on_action(fn)             -- fn(actor_id, targets[], category, param)

-- Drawing
local w = FW.text.new({pos={x,y}, text='', font='Arial', size=10, color={255,255,255}})
w:show() / w:hide() / w:text(str) / w:pos(x,y) / w:destroy()

local i = FW.image.new({pos={x,y}, path='...', size={w,h}})

-- Commands
FW.chat.send('/p Hello')     -- inject party chat
FW.chat.add(color, text)     -- add message to local chat log
FW.register_command('cb', fn)

-- Utilities
FW.log(msg)                  -- write to addon log
FW.zone_id()                 -- current zone
FW.is_in_menu()              -- system menu open?
```

## Boundary rules

- **Chharizard.exe never injects** into FFXI. All game interaction routes through Windower addons.
- **Configs are the bridge**: exe writes JSON; addons watch the JSON and hot-reload.
- **Nothing character-specific in the repo**: rosters, per-toon UI positions, and character gearswap files live only on the user's machine.
- **Addons run READ-ONLY on incoming packets** (no packet injection, no outgoing-chunk registration). Chat commands go through `send_command('input /p ...')`.

## Chharbar module structure (v5.0.0 target)

```
addons/Chharbar/
├── Chharbar.lua               # Thin loader (~200 lines)
│                              # Reads data/enabled.json, requires only enabled modules
├── modules/
│   ├── vitals.lua             # HP/MP/TP bars for self
│   ├── target.lua             # Target name + HP%
│   ├── targetinfo.lua         # Target distance, checkparam
│   ├── chharpt.lua            # Party list (self + party + alliance)
│   ├── scoreboard.lua         # DPS per mob
│   ├── debuffs.lua            # Xathe-style debuff tracking
│   ├── castbar.lua            # Cast progress
│   ├── hate.lua               # Aggro meter + enmity proxy
│   ├── wsc.lua                # Skillchain / Magic Burst predictor
│   ├── chharchat.lua          # Tell / LS / LS2 tabbed chat
│   ├── autotarget.lua         # <stnpc>/<stmob> auto-expansion
│   └── silmaril_bridge.lua    # Silmaril integration hooks
├── data/                      # (gitignored)
│   ├── roster.json
│   ├── enabled.json
│   └── per_toon/*.lua
└── assets/
    ├── skills.lua             # Ivaar's Skillchain data
    └── icons/                 # (empty by default; user may add)
```

## Auto-updater flow

```
Chharizard.exe startup
  ├── Read local version from Chharizard/version.txt
  ├── GET https://api.github.com/repos/ChharithOeun/Chharizard/releases/latest
  ├── Compare tag_name to local version
  ├── If newer:
  │     ├── Show "New version vX.Y.Z — Update now? [Yes] [Later] [Skip]"
  │     ├── If Yes:
  │     │     ├── Download release .zip to %TEMP%
  │     │     ├── SHA256 verify against release notes
  │     │     ├── Extract to Windower/addons/ (backing up old versions)
  │     │     ├── Update Chharizard/version.txt
  │     │     └── Restart Chharizard.exe
  └── Continue to main UI
```

## Chharizard.exe tabs (v5.1.0 target)

1. **Dashboard** — status of each character (loaded / not loaded, active job, zone)
2. **Modules** — matrix: character × module → checkbox
3. **Roster** — add/edit/remove characters, main tank / off tank / healer tags
4. **Launcher** — pick which characters to launch, "Launch All" button
5. **Gearswap** — builder GUI (v5.5.0)
6. **Tune** — run FFXI system tuner (embedded, no separate .bat)
7. **Update** — check for updates, view changelog, one-click upgrade
8. **Logs** — tail addon logs live

## Why AutoHotkey v2 for the .exe

- Single-file .exe compile (`Ahk2Exe`), ~500KB, no runtime dependency
- Native Windows GUI (Windows Common Controls)
- Fast startup (<100ms)
- File I/O, JSON handling, HTTP requests, process management all built-in
- Perfect for a companion tool that needs to launch Windower, edit configs, and poll an API

Alternatives considered:
- C# WPF: prettier UI but needs .NET runtime (not always present on target machines)
- Python: heavy packaging (~40MB via PyInstaller)
- Rust + egui: modern but overkill for this use case
- Electron: absurdly large for a config editor

## Repository conventions

- **Public** by default. Nothing character-specific ever enters the repo.
- **Author** on every file: `Chharizard`. Never a real name.
- **Commit signature**: `git config user.name "Chharbot"` and `user.email ChharithOeun@users.noreply.github.com` locally.
- **Semver**: `v<major>.<minor>.<patch>`. Major = umbrella-wide breaking change. Minor = new module or major feature. Patch = bugfix / tuning.
- **Releases**: tagged `vX.Y.Z`, GitHub release contains one .zip per component + a bundle .zip containing everything.
