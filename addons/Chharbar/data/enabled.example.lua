-- ============================================================================
-- Chharbar / data / enabled.example.lua
--
-- Copy this file to `enabled.lua` (same folder) to override which modules
-- Chharbar loads. `enabled.lua` is gitignored — your local config never hits
-- the public repo.
--
-- Delete a line to disable that module. Add a comment `--` to disable it
-- temporarily. Order doesn't affect load order (that is fixed in Chharbar.lua)
-- but it controls the display order in `//cb list`.
-- ============================================================================

return {
    enabled = {
        'vitals',           -- HP / MP / TP bars for the player
        'target',           -- target name + HP%
        'distance',         -- yards from player to target
        'targetinfo',       -- target ID / hex / speed% (Arcon's TargetInfo port)
        'chharpt',          -- party + alliance 1 + alliance 2 lists
        'debuffs',          -- self debuffs on the player
        'castbar',          -- self-cast progress bar
        'scoreboard',       -- DPS per mob
        'debuffed',         -- enemy debuff tracker (Xathe's Debuffed port)
        'hate',             -- aggro / hate proxy meter with MT/OT + spikes
        'wsc',              -- Skillchain / Magic Burst predictor
        'chharchat',        -- unified /tell + /ls + /ls2 tabbed chat
        'gsassist',         -- Gearswap set explorer + simulator
        'silmaril_bridge',  -- Silmaril multibox tool integration hooks
        'autotarget',       -- <stnpc> / <stmob> auto-expansion
    },
}
