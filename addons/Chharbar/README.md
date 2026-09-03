# Chharbar

HUD suite for Chharizard. Vitals, party, target, debuffs, cast bar, hate meter, skillchain / magic burst predictor, per-toon tabbed chat, gearswap assistant, and more — all as independent modules you can toggle per character.

> **⚠️ Do NOT contact me in-game about this project.** Bugs → [GitHub Issues](https://github.com/ChharithOeun/Chharizard/issues). Feature ideas → Discussions. In-game tells will be ignored.

## Install (Windower 4)

Drop this folder into `Windower/addons/Chharbar/`. In-game:

```
//lua load chharbar
```

Add `lua load chharbar` to your `Windower/scripts/init.txt` to auto-load per character.

## Install (Ashita v4)

Planned for Chharizard v5.3.0 via `core/compat_ashita.lua`. Windower is the primary target for v5.0.x.

## Layout

```
Chharbar/
├── Chharbar.lua                    # Thin loader (~90 lines) — this is what //lua load calls
├── core/
│   ├── framework.lua               # CHB namespace, widget helpers, prerender, cmd router
│   └── target_helpers.lua          # Shared target/distance/targetinfo helpers
├── modules/
│   ├── vitals.lua                  # HP / MP / TP
│   ├── target.lua                  # target name + HP%
│   ├── distance.lua                # yards to target
│   ├── targetinfo.lua              # target ID / hex / speed%
│   ├── chharpt.lua                 # party + alliance lists
│   ├── debuffs.lua                 # self debuffs
│   ├── castbar.lua                 # self cast progress
│   ├── scoreboard.lua              # DPS per mob
│   ├── debuffed.lua                # enemy debuff tracker
│   ├── hate.lua                    # aggro meter + spikes
│   ├── wsc.lua                     # skillchain / magic burst
│   ├── chharchat.lua               # tell / ls / ls2 tabbed chat
│   ├── gsassist.lua                # gearswap set explorer
│   ├── silmaril_bridge.lua         # Silmaril hooks
│   └── autotarget.lua              # <stnpc>/<stmob> expansion
├── data/                           # gitignored (except .example files)
│   ├── enabled.example.lua         # copy to enabled.lua to override which modules load
│   ├── enabled.lua                 # your local module list (optional)
│   ├── roster.json                 # your character roster (private)
│   ├── state_v3.lua                # saved UI positions (auto-generated)
│   └── chharbar.log                # debug log (rotates at 200 KB)
└── assets/
    └── skills.lua                  # Ivaar's skillchain data
```

## Toggling modules

Two paths:

**A. Manually.** Copy `data/enabled.example.lua` to `data/enabled.lua`. Delete or comment out any module you don't want. Reload the addon.

**B. Via Chharizard.exe.** Coming in v5.1.0 — the companion app writes `enabled.lua` for you with per-character override support.

## Chat commands

Every `//cb` and `//chharbar` command from v4.7.x still works. Full reference:

```
//cb                       -- show help
//cb showall               -- force all HUDs visible
//cb hideall               -- hide all HUDs
//cb resetpos              -- reset HUD positions to defaults
//cb resetall              -- nuclear reset (positions + settings)
//cb save                  -- save current UI layout for this character
//cb border on|off         -- toggle gold widget borders
//cb perf on|off|report    -- performance profiler
//cb log [N]               -- tail last N lines of debug log
//cb chat r "message"      -- reply to last incoming /tell
//cb chharchat roster ...  -- manage chat-window tab roster
//cb debuffed              -- toggle debuff widget
//cb wsc                   -- toggle skillchain predictor
//cb hate                  -- toggle aggro meter
//cb scoreboard            -- toggle DPS scoreboard
//cb dev <module>          -- dump module state (debugging)
```

## Migrating from v4.7.13

Your `data/` folder (per-toon settings, roster, saved positions) transfers as-is. The loader reads the exact same files. First launch of v5.0.0 auto-loads every module by default — identical behavior to v4.7.13.

If you want the pre-v5.0.0 monolith for reference, it's saved as `Chharbar.lua.v4713-monolith-backup` in this folder.

## Author

Chharizard — [GitHub](https://github.com/ChharithOeun/Chharizard)

## License

MIT — see [`LICENSE`](../../LICENSE) at repo root.
