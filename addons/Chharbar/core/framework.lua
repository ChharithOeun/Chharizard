-- ============================================================================
-- Chharbar / core / framework.lua  (Chharizard v5.4.0+)
--
-- Detects which FFXI addon framework is running (Windower 4 or Ashita v4)
-- and installs a common surface so modules can call the same functions on
-- either platform.
--
-- Strategy: COMPAT SHIM. On Ashita, we install a fake `windower.*` global
-- backed by Ashita's ashita.* API. Existing Chharbar modules that call
-- windower.register_event, windower.ffxi.get_player, windower.add_to_chat,
-- etc. keep working without a migration.
--
-- Native Windower: no shim needed — windower.* already exists. framework.lua
-- just records which framework we're on and its version.
--
-- Exposes:
--   FW.name              = 'windower' | 'ashita'
--   FW.version           = detected framework version string
--   FW.lua_version       = '5.1' | '5.4'
--   FW.addon_path        = string, addon install dir (trailing slash)
--   FW.is_windower       = true/false
--   FW.is_ashita         = true/false
--
-- Do NOT `//lua load` this directly — it's a library required by Chharbar.lua.
-- ============================================================================

FW = FW or {}

-- ----------------------------------------------------------------------------
-- Detect which framework is loading us.
-- ----------------------------------------------------------------------------
if type(_G.windower) == 'table' and type(_G.windower.register_event) == 'function' then
    FW.name = 'windower'
    FW.is_windower = true
    FW.is_ashita   = false
    FW.lua_version = _VERSION:match('%d+%.%d+') or '5.1'
    FW.addon_path  = _G.windower.addon_path or ''
    -- Windower version isn't exposed cleanly at runtime; use a static marker.
    FW.version = (_G.windower.ffxi and _G.windower.ffxi.get_info and 'Windower 4.x') or 'Windower 4'
    -- No shim needed — windower.* is native.
    require('core.compat_windower')
    _G.CHR_FW = FW
    return
end

if type(_G.ashita) == 'table' then
    FW.name = 'ashita'
    FW.is_windower = false
    FW.is_ashita   = true
    FW.lua_version = _VERSION:match('%d+%.%d+') or '5.4'
    FW.addon_path  = (_G.addon and _G.addon.path) or ''
    FW.version     = 'Ashita v4'
    -- Install the windower.* shim over ashita.*
    require('core.compat_ashita')
    _G.CHR_FW = FW
    return
end

-- Neither detected — fail loudly. Something is very wrong.
error('[Chharbar/framework] Neither windower.* nor ashita.* globals found. '
      .. 'Are you loading this outside a supported addon framework?')
