# Chharbar → Chharizard Migration Guide

For users upgrading from the pre-v5.0.0 Chharbar single-file addon.

## What changes for you

| Before                                           | After                                                                |
| ------------------------------------------------ | -------------------------------------------------------------------- |
| One giant `Chharbar/Chharbar.lua` (5658 lines)   | `Chharbar.lua` (~200 lines) + `modules/*.lua` (one per feature)      |
| Edit config with `//cb <cmd>`                    | Same commands still work; Chharizard.exe adds a GUI on top           |
| Update by manually downloading .lua              | `Chharizard.exe` prompts and one-click updates from GitHub           |
| Author `Chharith` in file headers                | Author `Chharizard`                                                  |
| Roster hardcoded in `Chharbar.lua` line 4541     | Roster in local `data/roster.json` (gitignored, not shipped in repo) |

## Your data survives

Everything in `Chharbar/data/` (per-toon UI positions, saved states, roster, backups) migrates as-is. The v5.0.0 loader reads the same files.

## Chat commands unchanged

Every `//cb <subcommand>` from v4.x still works in v5.x. The modularization is internal only.

## Migration steps

1. Back up your entire `Windower/addons/Chharbar/` folder.
2. Download the v5.0.0 release from https://github.com/ChharithOeun/Chharizard/releases (or install Chharizard.exe and let it do this).
3. Replace `Windower/addons/Chharbar/Chharbar.lua` with the new thin loader.
4. Copy `Windower/addons/Chharbar/modules/` from the release into your addon directory.
5. Copy `data/roster.example.json` to `data/roster.json` and fill in your character names.
6. In-game: `//lua reload chharbar`.

## Rolling back

Your backup of the v4.x `Chharbar.lua` is a drop-in replacement. Delete `modules/`, put the old `Chharbar.lua` back, `//lua reload chharbar`. All data files are backward compatible.

## Reporting migration issues

- Bug reports: https://github.com/ChharithOeun/Chharizard/issues
- Include `data/chharbar.log` (last 100 lines) and output of `//cb version`
