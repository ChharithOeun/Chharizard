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

## [5.9.1] — 2026-09-04

### Changed
- **Tab reskin sweep** — mechanical replacement of 39 inline `SetFont(...)` calls across 7 tab files (`modules`, `roster`, `launcher`, `tune`, `update`, `logs`, `plugins`) with the v5.9.0 `ThemeApply.*` helpers. Whole app now consistently uses the palette from `lib/theme.ahk`.
- Remaining inline `SetFont` calls (4 total: 2 in `tune.ahk`, 1 in `update.ahk`, 1 in `logs.ahk`) are Consolas / custom-color cases that don't map cleanly to a single ThemeApply helper — left as-is intentionally.

### Notes
- Sanity-checked brace balance on all edited tabs — no syntax breakage from the sweep.
- If any button colors look slightly off from your expected palette after this cut, ping me the tab + button and I'll add a new ThemeApply variant.

## [5.9.0] — 2026-09-04

### Added
- **`lib/theme.ahk`** — central palette (cyan `#40e0e8` / pink `#ff2e97` / yellow `#ffd732` on brick `#0d0810`) + font families (Georgia italic titles, Segoe UI body, Consolas mono) matching the Chharizard banner. `ThemeApply.*` helpers so tabs don't repeat verbose SetFont calls.
- **Banner strip at top of main window** — `assets/banner.png` loaded via Gui.Add("Picture"), 1000×140 fixed strip. Graceful fallback to a text title if the PNG is missing.
- **Dark title bar** — `DwmSetWindowAttribute(20, 1)` via DllCall to `dwmapi.dll`. Wrapped in try/catch so pre-Win10-1909 systems silently keep the default title bar.
- **Dashboard rewritten** using theme constants as the reference implementation for tab authors.

### Changed
- `main_window.ahk` — banner + themed tab control (Background color, no margins), status strip in `text_muted`
- `Chharizard.ahk` bumped to v5.9.0; `#Include lib\theme.ahk` added
- Tab authors can drop in `ThemeApply.title(gui)`, `ThemeApply.h2(gui)`, `ThemeApply.body(gui)`, `ThemeApply.status_ok(gui)`, etc. for consistent look

### Deferred (per-tab reskin rollout)
- Modules / Roster / Launcher / Tune / Update / Logs / Plugins tabs still use inline color literals. Ships in v5.9.1 (mechanical sed pass over each tab file to replace hardcoded colors with ThemeApply calls).

## [5.8.0] — 2026-09-04

### Added
- **Chharcam** — new sibling addon under `addons/Chharcam/`. Camera distance + pan-speed control ported from Hokuten's XICamera v0.7.8 (BSD 3-clause). Bundles `_XICamera.dll` verbatim (MD5 `99b0d3e58f5efc9a5adb8e53d4bd5230` published for tamper-check).
- Commands under `//cam` / `//chharcam` / `//camera` — distance, battle distance, pan speed, incr/decr, status, help.
- `data/settings.example.xml` template.
- `manifest.json` component entry for Chharcam.

### Known limits (v5.8.0)
- **Windower 4 only.** Ashita v4 port deferred to v5.8.1 — needs either a rebuilt DLL for Ashita's hook path or an imgui-based reimplementation.

## [5.7.0] — 2026-09-04

### Audit — fixed
Full sweep of the codebase (9,218 lines, 39 files). See `docs/AUDIT-v5.7.0.md` for the complete report. Highlights:

#### Critical
- **Two more `A_ScriptDir . "\..\..\.."` path bugs** missed in v5.5.1:
  - `lib/config.ahk` — `Config.repoRoot()` was resolving one level too high
  - `lib/events.ahk` — event-bus error log path was misdirected

#### High — Ashita shim gaps
Cross-referenced every `windower.*` call in the actual Chharbar modules against `compat_ashita.lua`. Added 5 missing functions:
- `windower.ffxi.get_mob_array()` — batch entity table walk
- `windower.ffxi.get_menu_string()` — for auto-hide gate
- `windower.get_key_state(vk)` — via imgui.IsKeyDown, ffi fallback
- `windower.debug.get_key_state` — alias
- `windower.packets.parse_action()` — minimal 0x028 header parse (actor, size, category, param). Full target sub-block walk deferred to v5.7.1.

### Deferred (with tickets)
- v5.7.1: Full 0x028 target walk in Ashita packet parser + remove stale "shim active" chat message
- v5.7.2: In-process reentrancy guard on `Commands.run`
- v5.7.3: Background thread for update download with progress events

### Verified clean
- No TODO/FIXME/HACK/XXX/WIP residue in ship code
- No unbounded loops
- No hardcoded `C:\Users\` paths
- No silent-swallow try/catch without log fallback
- .gitignore covers everything sensitive
- All Commands.register handlers protected by dispatcher's try/catch
- RPC response payloads all JSON-serializable

## [5.6.0] — 2026-09-04

### Added
- **`manifest.json`** at repo root — declares known-good version of every component the current Chharizard.exe ships with. Bundled per release.
- **`lib/compat.ahk`** — version self-recovery. Reads `manifest.json` + parses local component versions from file headers (Lua `_addon.version`, PS1 `# Version:`, AHK `version:`), compares, reports drift.
- **Dashboard "Version health" panel** — grid showing every component with Expected / Local / Status / Note columns. Green when all match, red when drift detected.
- **One-click "Repair drift" button** — invokes `compat.repair` which runs the updater to pull the exact versions declared in the current release's manifest.
- **`# Version: 1.0.0` markers** in `TUNE-FFXI.ps1` and `REVERT-FFXI.ps1` so compat can parse them.

### Command surface additions
- `compat.scan`    → array of per-component reports
- `compat.summary` → `{total, ok, drift, missing, healthy}`
- `compat.repair`  → invokes update.apply when drift found

## [5.5.1] — 2026-09-04

### Fixed
- **RPC path resolution bug** — `A_ScriptDir . "\..\..\..\data"` was resolving one level too high (into `%USERPROFILE%\Documents\` instead of `%USERPROFILE%\Documents\Chharizard\`). Fixed to `\..\..\data`. Affects: state.ahk (state file + repo path), log.ahk (log file), rpc.ahk (inbox/outbox), commands.ahk (log.tail).
- **Result:** RPC folders now correctly create at `data/rpc/inbox/` and `data/rpc/outbox/` inside the Chharizard repo root. External RPC clients now work.

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
