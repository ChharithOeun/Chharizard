# Chharsai

Mog Garden + Furrow + Monster Rearing automation for FFXI. Part of the Chharizard suite.

**Adapted from [Noirblanc's Bonsai v1.4.1](https://github.com/Noirblanc/Bonsai)** with full attribution preserved. Chharsai is a light adapter over Noirblanc's production-tested state machine — same logic, Chharizard branding + command aliases + extended manifest integration.

> **⚠️ Do NOT contact me in-game about this project.** [GitHub Issues](https://github.com/ChharithOeun/Chharizard/issues) or nothing.

## What it does

- **Garden** — walks to each garden node (Mineral Vein, Pond Dredger, Arboreal Grove, Coastal Fishing Net, Flotsam), pokes, harvests, moves on
- **Furrows** — plants Revival Roots, optionally fertilizes with Miracle Mulch (30-min cycle vs 61-min), harvests when grown, loops
- **Monster Rearing** — pets every breeding monster in the Rearing Grounds
- **Auto-sell** — optional pit-stop at the Green Thumb Moogle to auto-sell junk (requires the external SellNPC addon)
- **Full automation** — `//sai all` runs your customized node order end-to-end

## Install (Windower 4)

Drop this folder into `Windower/addons/Chharsai/`. In-game:

```
//lua load Chharsai
```

Add `lua load Chharsai` to your `Windower/scripts/init.txt` to auto-load per character.

## Install (Ashita v4)

Should work via Chharbar's compat shim (`addons/Chharbar/core/compat_ashita.lua`) as long as Chharbar is loaded first — Chharsai uses the same `windower.*` API surface the shim provides. Direct Ashita testing pending in v5.10.1.

## Commands

All aliases work — pick whichever feels natural: `//chharsai`, `//sai`, `//bon`, `//bonsai`.

### Garden

```
//sai garden        -- run all 4 garden nodes in order
//sai mine          -- Mineral Vein
//sai dredger       -- Pond Dredger
//sai grove         -- Arboreal Grove
//sai net           -- Coastal Fishing Net
//sai flotsam       -- Flotsam
```

### Furrows

```
//sai furrow start [1|2] [fert]   -- begin loop (1 = plant first, 2 = harvest first; fert = use Miracle Mulch)
//sai furrow stop                 -- stop the furrow loop
//sai furrow status               -- how long until ready / current state
//sai fert                        -- toggle Miracle Mulch fertilizing (default OFF)
```

### Monster rearing

```
//sai pet           -- pet every breeding monster (only in the Rearing Grounds!)
```

### Full automation

```
//sai all           -- run your customized node order + optional pet at end
//sai add <node>    -- add a node to the //sai all order (mine/dredger/grove/net/flotsam/pet)
//sai remove <node>
//sai list          -- show current order
//sai cancel        -- abort the current run
```

### Auto-sell (requires external SellNPC addon)

```
//sai autosell on|off             -- toggle Green Thumb Moogle auto-sell
```

## Requirements

- Character must be in Mog Garden for garden / furrow / all commands
- `//sai pet` should be run only in the Rearing Grounds (not the main Mog Garden area)
- `//sai all` starts from the main Mog Garden and warps to Rearing Grounds via Chacharoon at the end
- Furrows need at least 1 Revival Root in inventory
- Auto-sell requires the external [SellNPC addon](https://github.com/Windower/Lua) with a profile named `garden`

## Chharbot integration (v5.11+)

Chharsai is state-machine driven, which means the Chharbot AI plugin can (in a future release) call `//sai all` per character on a schedule + monitor state to know when it's safe to move on. This unlocks fully-autonomous multi-character daily runs — set it and forget it.

For now: Chharsai runs manually, one character at a time. Multi-instance orchestration = v5.11.0.

## Config

Chharsai uses Windower's `config` library. Per-character settings live in `data/settings.xml` (auto-created on first load). Custom `//sai all` order + autosell preference are saved per character automatically.

## Credits

- **Noirblanc** — original Bonsai author. Chharsai is a light rebrand + integration of his 1,326-line state machine.
- **Chharizard suite** — packaging + Chharizard-integration + Ashita compat shim.

## License

Original Bonsai code: license per Noirblanc's repository. See [Bonsai on GitHub](https://github.com/Noirblanc/Bonsai) for the canonical terms.

Chharizard adaptations (this README, the header rebrand, the `//sai` command aliases): **MIT** — see [`LICENSE`](../../LICENSE) at repo root.

## Sibling addons

- [`Chharbar`](../Chharbar/) — HUD suite
- [`Chharcam`](../Chharcam/) — camera distance control
- Chhargear — planned (gearswap builder GUI)
