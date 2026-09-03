-- ============================================================================
-- Chharbar 5.0.0 — thin loader for the modular HUD suite.
--
-- Reads data/enabled.lua (or falls back to all modules) and loads each enabled
-- module in dependency order. All module files live under modules/ and share
-- the CHB namespace set up in core/framework.lua.
--
-- This file is the ONLY thing you `//lua load chharbar`. It is intentionally
-- tiny — every ounce of feature code lives in a module file that you can
-- edit, disable, or fork without touching the loader.
--
-- Author:   Chharizard
-- Repo:     https://github.com/ChharithOeun/Chharizard
-- Frame:    Windower 4 (Lua 5.1). Ashita v4 support arrives in v5.3.0 via
--           core/compat_ashita.lua.
-- ============================================================================

_addon.name     = 'Chharbar'
_addon.author   = 'Chharizard'
_addon.version  = '5.0.0'
_addon.commands = { 'cb', 'chharbar' }

-- ----------------------------------------------------------------------------
-- Core framework MUST load first. It defines CHB, register handlers, cmd
-- dispatcher, and the widget helpers every module depends on.
-- ----------------------------------------------------------------------------
require('core.framework')

-- Shared helpers used by target / distance / targetinfo. Load before those
-- modules so they can call into it.
require('core.target_helpers')

-- ----------------------------------------------------------------------------
-- Enabled-module list.
--
-- Priority (highest wins):
--   1. data/enabled.lua           (per-install config, gitignored)
--   2. DEFAULT_ENABLED below      (repo default = every module ON)
--
-- To disable a module, either:
--   a) Copy data/enabled.example.lua → data/enabled.lua and edit the list, or
--   b) Use Chharizard.exe → Modules tab (v5.1.0+) which writes the file for you
-- ----------------------------------------------------------------------------
local DEFAULT_ENABLED = {
    'vitals',
    'target',
    'distance',
    'targetinfo',
    'chharpt',
    'debuffs',
    'castbar',
    'scoreboard',
    'debuffed',
    'hate',
    'wsc',
    'chharchat',
    'gsassist',
    'silmaril_bridge',
    'autotarget',
}

local function load_enabled_list()
    local addon_path = windower.addon_path or ''
    local cfg_path   = addon_path .. 'data/enabled.lua'
    local f = io.open(cfg_path, 'r')
    if not f then return DEFAULT_ENABLED end
    f:close()
    local ok, cfg = pcall(dofile, cfg_path)
    if not ok or type(cfg) ~= 'table' or type(cfg.enabled) ~= 'table' then
        if CHB and CHB.log then
            CHB.log('enabled.lua present but invalid, falling back to defaults: ' .. tostring(cfg))
        end
        return DEFAULT_ENABLED
    end
    return cfg.enabled
end

local enabled = load_enabled_list()

for _, mod_name in ipairs(enabled) do
    local ok, err = pcall(require, 'modules.' .. mod_name)
    if not ok then
        if CHB and CHB.log then
            CHB.log(('MODULE FAIL [%s]: %s'):format(mod_name, tostring(err)))
        end
        windower.add_to_chat(123,
            ('[Chharbar] module load failed: %s — %s'):format(mod_name, tostring(err)))
    end
end

if CHB and CHB.log then
    CHB.log(('Chharbar %s loaded — %d modules'):format(_addon.version, #enabled))
end
