# Changelog

All notable changes to Chharizard will be documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Planned
- v5.0.x — Split Chharbar.lua (5658 lines) into per-module files under `addons/Chharbar/modules/`
- v5.1.0 — Chharizard.exe skeleton (AutoHotkey v2) with Modules / Roster / Launcher / Tune / Update tabs
- v5.2.0 — Auto-updater backed by GitHub Releases API
- v5.3.0 — Ashita v4 compatibility layer (`core/compat_ashita.lua`) so all addons run on private servers too
- v5.4.0 — Chharsai (automation) — port Bonsai state-machine pattern for multibox routines
- v5.5.0 — Chharcam (camera) — port XICamera DLL, wrap in Chharizard commands
- v5.6.0 — Chhargear (gearswap builder) — GUI to generate `gearswap/data/JOB_Char.lua` from item DB

## [5.5.0] — 2026-09-04

### Added
- **RPC listener** — file-based transport at `data/rpc/inbox/` (write requests) ↔ `data/rpc/outbox/` (read responses). Poll interval 250ms, rate limit 10/sec, auto-deletes processed inbox files.
- **JSON protocol** with correlation IDs — see `docs/RPC-PROTOCOL.md` for full spec + Python / PowerShell / Node client examples.
- **`Commands.run()` fully exposed over RPC** — every UI action (roster, modules, launcher, update, tune) callable by any external process.
- **`rpc.ping`** and **`rpc.status`** commands for external liveness checks.
- **Plugins tab now shows RPC status** — running/stopped, inbox/outbox counts, folder paths. "Send test ping" button verifies the dispatcher.

### Command surface additions
- `rpc.ping`   → `"pong"`
- `rpc.status` → `{running, inbox, outbox, inboxPending, outboxUnread, rateWindow}`

### Deferred to v5.5.1
- Named-pipe transport (`\\.\pipe\chharizard`) for sub-100ms latency. Same JSON protocol — clients switch transport without protocol changes.

## [5.4.2] — 2026-09-03

### Added
- **Real widget rendering on Ashita v4** — replaces the v5.4.0 stubs. `compat_ashita.lua` now maintains a central widget registry drawn each frame via a single `d3d_present` handler using imgui. Text widgets support: text content, position, color/alpha, background color/alpha/visibility, font size, stroke, right-justification, destroy. Chharbar HUDs now render on Ashita the same as Windower.
- **Auto-update on launch** — `Chharizard.ahk` startup fires a non-blocking version check 1.5s after the main window shows. If a newer release exists on GitHub, prompts with tag comparison + first 800 chars of changelog. Accept → download → apply → auto-restart the exe on the new version.
- **`auto_update_on_launch` preference** (default: true) — toggle in the Update tab.

### Deferred to v5.4.3
- Ashita image widget rendering (texture upload via primitive manager)
- Any per-event packet parsing gaps discovered during real Ashita testing

## [5.4.0] — 2026-09-03

### Added
- **Ashita v4 support** via compat shim strategy — Chharbar addons run on both frameworks with the same source.
- **`addons/Chharbar/core/framework.lua`** — auto-detects Windower vs Ashita at load, requires the correct adapter, populates `FW.*` metadata.
- **`addons/Chharbar/core/compat_windower.lua`** — no-op stub (Windower is native).
- **`addons/Chharbar/core/compat_ashita.lua`** — installs fake `windower.*` global backed by `ashita.*` API. Full coverage of events, player/party/target data, chat, commands. Widgets stubbed until v5.4.2.
- **`addons/Chharbar/core/internal_framework.lua`** — the CHB namespace previously in framework.lua, renamed for clarity now that framework.lua handles cross-platform detection.
- **Exe-side dual-framework detection** — `lib/detect.ahk` finds both Windower and Ashita installs, reads file version metadata via FileSystemObject, exposes `Detect.all()` returning both.
- **Dashboard tab** shows both frameworks side-by-side with version strings.
- **Per-character framework preference** — Roster tab dropdown lets each char launch under a specific framework (auto / windower / ashita). Mixed sessions work: one toon on Windower, another on Ashita, simultaneously.
- **Launcher** respects per-char framework — picks the right exe automatically.

### Command surface additions
- Detection surface: `Detect.all()` → `{windower: {installed, path, exe, version, addonsDir}, ashita: {...}}`
- `Detect.frameworkForChar(name)` / `Detect.setFrameworkForChar(name, fw)`

### Known limitations (v5.4.0)
- Ashita widgets stubbed (log-only). Actual HUD rendering on Ashita arrives in v5.4.2 via imgui.
- Chharbar modules that heavily rely on Windower-specific packet parsing may need per-event review. Basic events + data confirmed working.

## [5.3.0] — 2026-09-03

### Added
- **`Chharizard/tune/`** — vendored `TUNE-FFXI.ps1` and `REVERT-FFXI.ps1` from the standalone tuner. Ship inside the companion so users don't need a separate .bat.
- **`Chharizard/src/lib/tune.ahk`** — launches the tune / revert scripts with UAC elevation via `*RunAs` prefix. Bubbles up the `.ps1` log for in-app viewing.
- **Tune tab** — functional. Apply / Revert buttons, live log tail from the .ps1's own log file, per-tweak backup managed by the underlying PowerShell.

### Command surface additions
- `tune.apply`   → runs TUNE-FFXI.ps1 elevated
- `tune.revert`  → runs REVERT-FFXI.ps1 elevated (restores every change from backup.json)
- `tune.status`  → `{applied, backup, log}` — for AI / RPC callers to check state
- `tune.log`     → tail last N lines of the tuner log

### Changed
- `Chharizard.ahk` bumped to v5.3.0

## [5.2.0] — 2026-09-03

### Added
- **`Chharizard/src/lib/updater.ahk`** — GitHub Releases API client. Query, compare tags, download release zip, extract via `tar`, apply over repo root preserving `data/`.
- **`Chharizard/src/lib/launcher.ahk`** — spawn Windower/Ashita, per-character or all-at-once with staggered timing to avoid PlayOnline login-server race.
- **Update tab** — functional. Check for updates, view changelog, one-click download+install.
- **Launcher tab** — functional. Detects framework, lists roster, launch selected or launch-all.

### Changed
- `Chharizard.ahk` bumped to v5.2.0
- Roster changes now emit `roster:changed` — Launcher tab auto-refreshes its list

### Command surface additions (all routable through future RPC)
- `update.check`  → returns `{tag, name, body, published_at, zip_url}`
- `update.apply`  → downloads + extracts + copies
- `launcher.start` → spawn framework
- `launcher.char`  → framework + tag for character
- `launcher.all`   → sequential launch with 3s stagger


## [5.0.0] — TBD

Umbrella rebrand from **Chharbar** to **Chharizard**. Chharbar becomes one addon under the Chharizard umbrella; the companion `.exe` orchestrates everything.

### Added
- Monorepo layout: `Chharizard/` (exe) + `addons/{Chharbar,Chharsai,Chharcam,Chhargear}/`
- `.gitignore` protecting local rosters, per-character configs, character-specific gearswap files
- Author attribution moved to `Chharizard` across all Lua headers
- Framework abstraction plan: `core/framework.lua` with `compat_windower.lua` and (v5.3.0) `compat_ashita.lua` adapters — same modules run on both frameworks
- Credits section in README naming every original author whose work inspired or was ported into Chharizard
- Explicit "do not contact in-game" policy in all READMEs — support routes through GitHub only

### Changed
- `Chharbar/Chharbar.lua` split into module files (details in v5.0.0 release notes)
- All `--Chharith` author comments in gearswap files → `--Chharizard`
- `_addon.author = 'Chharith'` in empymerc and legacy files → `'Chharizard'`

### Retained (local, gitignored)
- Character roster (`data/roster.json`)
- Per-character settings (`data/per_toon/*.lua`)
- Character-specific gearswap files (`gearswap/data/*_<CharName>.lua`)

## Pre-v5.0.0 (Chharbar-era)

See prior git history. Chharbar reached v4.7.13 as a single-file addon with 14 chunks of functionality (Vitals, Target, ChharPT, Scoreboard, Debuffs, CastBar, Hate, WSC, Chharchat, Gearswap bridge, Silmaril, Autotarget, WSC animations, per-toon UI). Rebrand to Chharizard preserves all functionality while modularizing for maintainability and companion .exe integration.
