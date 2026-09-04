# Chharcam

Camera distance + pan-speed control for FFXI, part of the Chharizard suite.

**Adapted from [Hokuten's XICamera v0.7.8](https://github.com/Hokuten/XICamera)** (BSD 3-clause) with full attribution preserved. The bundled `libs/_XICamera.dll` is Hokuten's original compiled C++ binary, unmodified.

> **⚠️ Do NOT contact me in-game about this project.** [GitHub Issues](https://github.com/ChharithOeun/Chharizard/issues) or nothing.

## What it does

- Increase camera distance beyond FFXI's default (default cap = 6.0; Chharcam lets you go further)
- Separate battle-camera distance
- Adjustable horizontal / vertical pan speed
- Auto-calc vertical speed proportional to camera distance (recommended)
- Save preferences per character via Windower's `config` library

## Install (Windower 4)

Drop this folder into `Windower/addons/Chharcam/`, then:

```
//lua load Chharcam
```

Add `lua load Chharcam` to your `Windower/scripts/init.txt` to auto-load per character.

## Install (Ashita v4)

**Not supported in v5.8.0.** XICamera's DLL is Windower-specific (it uses memory offsets and hook points that don't map cleanly to Ashita v4's D3D9 hook path). Ashita port planned for v5.8.1 — either via a rebuilt DLL or via Ashita's built-in `imgui`-based camera settings.

## Commands

Both `//cam` and `//chharcam` work (`//camera` too, for XICamera muscle memory):

```
//cam                          -- show help
//cam d|distance <n>           -- set camera distance (default: 6)
//cam b|battle <n>             -- set battle-camera distance (default: 8.2)
//cam hs|hspeed <n>            -- set horizontal pan speed
//cam vs|vspeed <n>            -- set vertical pan speed
//cam in|incr                  -- increment distance by 1
//cam de|decr                  -- decrement distance by 1
//cam bin|bincr                -- increment battle distance by 1
//cam bde|bdecr                -- decrement battle distance by 1
//cam soi                      -- toggle saveOnIncrement (default: off)
//cam acv                      -- toggle autoCalcVertSpeed (default: on)
//cam s|status                 -- print current settings
```

## Configuration

Settings live in `data/settings.xml` (per-character via Windower's config library). Copy `data/settings.example.xml` if you want a starting template.

```xml
<?xml version="1.1" ?>
<settings>
    <global>
        <cameraDistance>6</cameraDistance>
        <battleDistance>8.2</battleDistance>
        <horizontalPanSpeed>3</horizontalPanSpeed>
        <verticalPanSpeed>10.7</verticalPanSpeed>
        <saveOnIncrement>false</saveOnIncrement>
        <autoCalcVertSpeed>true</autoCalcVertSpeed>
    </global>
</settings>
```

## Trust check for the bundled DLL

The `libs/_XICamera.dll` in this folder is Hokuten's original binary. Verify integrity:

```powershell
Get-FileHash .\libs\_XICamera.dll -Algorithm MD5
# Should match:  99b0d3e58f5efc9a5adb8e53d4bd5230
```

If the MD5 doesn't match, do NOT load the addon — pull the release again.

## Credits

- **Hokuten** — original XICamera author. This addon is a light adaptation of his work.
- **Chharizard suite** — packaging + Chharizard-integration commands.

## License

Original XICamera code and DLL: **BSD 3-clause** — see the header of `Chharcam.lua` for the original notice. Redistribution retains Hokuten's copyright.

Chharizard adaptations (this README, the Chharizard-integration commands, the settings.example.xml template): **MIT** — see [`LICENSE`](../../LICENSE) at repo root.

## Sibling addons

- [`Chharbar`](../Chharbar/) — HUD suite (party, vitals, target, DPS, hate, WSC, chat)
- Chharsai — planned (Mog Garden automation)
- Chhargear — planned (gearswap builder)
