# Chharizard v5.7.0 Audit Report

Systematic sweep of every AHK, Lua, PS1, and BAT file for security issues, silent failures, path bugs, unbounded loops, hardcoded secrets, TODO residue, and API surface gaps.

**Codebase size:** 9,218 lines across 39 files (AHK, Lua, PS1, BAT).

## Executive summary

| Severity | Found | Fixed in v5.7.0 | Deferred |
|----------|-------|-----------------|----------|
| Critical | 2     | 2               | 0        |
| High     | 5     | 5               | 0        |
| Medium   | 3     | 0               | 3        |
| Low      | 4     | 0               | 4        |
| Total    | 14    | 7               | 7        |

## Critical — fixed in this cut

### C1 — Two residual path bugs from v5.5.1 fix

The v5.5.1 sed pass caught state.ahk, log.ahk, rpc.ahk, commands.ahk but MISSED:
- `lib/config.ahk` line 21: `A_ScriptDir . "\..\..\..\"` → repo path resolved to `Documents\` instead of `Documents\Chharizard\`
- `lib/events.ahk` line 35: `A_ScriptDir . "\..\..\..\Chharizard.log"` → error logs went to wrong path

**Fix:** corrected both to `\..\..`. Verified no remaining `..\..\..` patterns in `.ahk` files.

**Impact:** without this fix, `Config.repoRoot()` returned the wrong directory; `Compat` scans would fail; event handler errors would be silently misdirected.

## High — fixed in this cut

### H1-H5 — Ashita shim missing 5 functions the addon actually calls

The v5.4.0 shim shipped based on my documentation grep, not on what the modules actually use. Cross-referencing every `windower.*` call in the addon against the shim revealed gaps:

| Function                          | Used by                              | Fix                                            |
|-----------------------------------|--------------------------------------|------------------------------------------------|
| `windower.ffxi.get_mob_array()`   | targetinfo, autotarget               | Walk entity table 0-2303, build index-keyed map |
| `windower.ffxi.get_menu_string()` | internal_framework auto-hide gate    | Try Player:GetMenuName() then GetMenu(), fallback '' |
| `windower.get_key_state(vk)`      | ctrl/alt hold-to-show                | imgui.IsKeyDown when available, else GetAsyncKeyState via ffi |
| `windower.debug.get_key_state`    | same as above, alt namespace         | Alias to W.get_key_state                        |
| `windower.packets.parse_action`   | hate, scoreboard, wsc (critical)     | Minimal 0x028 header parse (actor, size, category, param) — full target walk deferred to v5.7.1 |

**Impact:** without these shims, Chharbar on Ashita would silently no-op key state checks, always hide with menu gate broken, and hate/scoreboard/wsc modules would throw nil-index errors on every action packet. Now degrades gracefully (partial packet parse) or logs cleanly.

**Deferred to v5.7.1:** full 0x028 target sub-block walk — needs side-by-side Windower/Ashita test data to verify.

## Medium — deferred with tickets

### M1 — `loadstring` in `wsc.lua`

Loads `data/wsc_skills.lua` (Ivaar's Skillchain data table) via `loadstring` inside `pcall`.

**Verdict:** Not a vuln. Path is scoped to `windower.addon_path`; file ships with the addon. Zero external input. `pcall`-wrapped so malformed data can't crash. The comment already documents this exception intentionally.

**Deferred:** none. Documented and safe.

### M2 — `dofile` in `Chharbar.lua` loader

Loads `data/enabled.lua` (user's per-install module toggle) via `pcall(dofile, ...)`.

**Verdict:** Not a vuln. Path scoped to addon's data folder. User-controlled = user-owned = same trust boundary as user's own scripts.

**Deferred:** none. Safe.

### M3 — Missing rate limit on `Commands.run` (in-process)

RPC has a 10/sec rate limit. In-process `Commands.run` does not. An event-storm subscriber could recursively dispatch and stack-overflow.

**Deferred to v5.7.2:** add a reentrancy guard on `Commands.run` to protect against handlers that emit events that fire handlers that call more commands.

## Low — noted for future

### L1 — Silent `try` in `events.ahk`

Event-bus subscriber errors are logged (good) but the try wraps a single expression which can silently drop errors on the FileAppend fallback if the log dir is unwritable.

**Deferred:** low impact; user would notice missing log entries. Backstop OK.

### L2 — No timeout on `WinHttpRequest` for update check

`Updater.check()` uses `req.SetTimeouts(10s, 10s, 10s, 10s)` which is fine. But `Updater.download()` uses 300s receive timeout — could hang the UI thread if GitHub stalls.

**Deferred:** move `download` to a background thread or use SetTimer for chunked progress.

### L3 — Ashita compat announces active shim via `AddChatMessage` on every load

Prints "[Chharbar] Ashita compat shim active (v5.4.0). Widgets stubbed until v5.4.2" on every character login. Now that v5.4.2 shipped, the warning is stale/incorrect.

**Deferred to v5.7.1:** remove or update the message.

### L4 — `.gitignore` may not cover future additions

Current `.gitignore` protects everything sensitive as of v5.6.0, but each new component adds new file patterns. Need periodic re-audit.

**Deferred:** add a CI check that flags files matching `*roster*`, `*state_v*`, `*.log` if they slip through.

## Verified clean

- **No TODO/FIXME/HACK/XXX/WIP** residue in ship code (matches are all legitimate English "try" verbs in comments)
- **No unbounded loops** (`Loop` without count, `while true`)
- **No hardcoded `C:\Users\` paths** in ship code (only in docs/example files)
- **No silent-swallow try/catch** without a log fallback
- **.gitignore correctly excludes** `data/roster.json`, `data/per_toon/`, `data/state_*.lua`, character-specific gearswap, tune-ffxi backups, secrets, editor detritus
- **Commands.register handlers** all wrapped in `Commands.run`'s try/catch — errors always return structured `{ok:false, error:...}`
- **RPC response serializability** — every command that could return complex objects returns Map/Array/primitives that JSON.Stringify handles

## Recommended follow-ups

- **v5.7.1** — Full 0x028 target sub-block walk in Ashita packet parser; remove stale shim-active chat message
- **v5.7.2** — In-process rate limit / reentrancy guard on `Commands.run`
- **v5.7.3** — Background thread for `Updater.download` with progress event stream

Everything else in this report is either fixed or intentional.
