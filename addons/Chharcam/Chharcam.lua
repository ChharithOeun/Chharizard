-- ============================================================================
-- Chharcam — camera distance and pan-speed control for FFXI.
--
-- Adapted from Hokuten's XICamera v0.7.8 (BSD 3-clause) with attribution
-- preserved. Redistributed as part of the Chharizard suite.
--
-- What's different from vanilla XICamera:
--   * Renamed to Chharcam so it lives alongside the Chharizard umbrella
--     without namespace collision.
--   * Command surface exposes both '//cam' and '//chb cam' entry points
--     so users of the Chharizard companion can drive it either way.
--   * Loads the same _XICamera.dll (memory-poke library, C++), copied
--     verbatim from Hokuten's release — see libs/README.md for MD5.
--   * settings.example.xml ships with the same defaults as XICamera.
--
-- Windower 4 only in v5.8.0. Ashita v4 port arrives in v5.8.1 (Ashita
-- uses different memory offsets for camera; needs a separate DLL build).
--
-- Original copyright: (c) 2019 Hokuten, all rights reserved. BSD 3-clause.
-- Adaptation:         (c) 2026 Chharizard, MIT with attribution to Hokuten.
-- ============================================================================

_addon.name     = 'Chharcam'
_addon.author   = 'Chharizard (adapted from Hokuten XICamera)'
_addon.version  = '5.8.0'
_addon.commands = { 'cam', 'chharcam', 'camera' }  -- inherit XICamera aliases

config = require('config')
require('pack')
require('lists')
require('tables')

local addon_path = windower.addon_path:gsub('\\', '/')

defaults = T{
    cameraDistance     = 6,
    battleDistance     = 8.2,
    horizontalPanSpeed = 3.0,
    verticalPanSpeed   = 10.7,
    saveOnIncrement    = false,
    autoCalcVertSpeed  = true,
}

settings = config.load(defaults)
config.save(settings)

package.cpath = package.cpath .. ';' .. addon_path .. '/libs/?.dll'
require('_XICamera')

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------

windower.register_event('load', function()
    _XICamera.disable()
    _XICamera.set_camera_distance(settings.cameraDistance)
    _XICamera.set_battle_distance(settings.battleDistance)
    _XICamera.set_horizontal_pan_speed(settings.horizontalPanSpeed)
    if settings.autoCalcVertSpeed then
        _XICamera.set_vertical_pan_speed(defaults.verticalPanSpeed * settings.cameraDistance / 6)
    else
        _XICamera.set_vertical_pan_speed(settings.verticalPanSpeed)
    end
    _XICamera.enable()
    windower.add_to_chat(207, '[Chharcam] loaded v' .. _addon.version
        .. '  |  distance=' .. settings.cameraDistance
        .. '  battle=' .. settings.battleDistance)
end)

windower.register_event('unload', function()
    _XICamera.disable()
end)

-- ----------------------------------------------------------------------------
-- Command dispatch — same surface as XICamera plus a couple of shortcuts.
-- ----------------------------------------------------------------------------

local function announce(msg)
    windower.add_to_chat(207, '[Chharcam] ' .. tostring(msg))
end

local function set_distance(v)
    v = tonumber(v)
    if not v then announce('bad distance value'); return end
    if _XICamera.set_camera_distance(v) > 0 then
        settings.cameraDistance = v
        config.save(settings)
        if settings.autoCalcVertSpeed then
            _XICamera.set_vertical_pan_speed(defaults.verticalPanSpeed * v / 6)
        end
        announce('camera distance = ' .. v)
    else
        announce('failed to change distance to ' .. tostring(v))
    end
end

local function set_battle(v)
    v = tonumber(v)
    if not v then announce('bad battle value'); return end
    if _XICamera.set_battle_distance(v) > 0 then
        settings.battleDistance = v
        config.save(settings)
        announce('battle distance = ' .. v)
    else
        announce('failed to change battle distance to ' .. tostring(v))
    end
end

local function set_hspeed(v)
    v = tonumber(v)
    if not v then announce('bad hspeed value'); return end
    if _XICamera.set_horizontal_pan_speed(v) > 0 then
        settings.horizontalPanSpeed = v
        config.save(settings)
        announce('horizontal pan speed = ' .. v)
    end
end

local function set_vspeed(v)
    v = tonumber(v)
    if not v then announce('bad vspeed value'); return end
    if _XICamera.set_vertical_pan_speed(v) > 0 then
        settings.verticalPanSpeed = v
        config.save(settings)
        announce('vertical pan speed = ' .. v)
    end
end

local function step(is_battle, is_incr)
    local cur = is_battle and settings.battleDistance or settings.cameraDistance
    local new = cur + (is_incr and 1 or -1)
    local fn  = is_battle and _XICamera.set_battle_distance or _XICamera.set_camera_distance
    if fn(new) > 0 then
        if is_battle then settings.battleDistance = new else settings.cameraDistance = new end
        if settings.saveOnIncrement then config.save(settings) end
        announce((is_battle and 'battle ' or '') .. 'distance = ' .. new)
    else
        announce('failed to step ' .. (is_battle and 'battle ' or '') .. 'distance')
    end
end

local function print_status()
    local stats = _XICamera.status()
    windower.add_to_chat(127, '[Chharcam] status')
    windower.add_to_chat(127, '  cameraDistance:     ' .. tostring(stats.cameraDistance))
    windower.add_to_chat(127, '  battleDistance:     ' .. tostring(stats.battleDistance))
    windower.add_to_chat(127, '  horizontalPanSpeed: ' .. tostring(stats.horizontalPanSpeed))
    windower.add_to_chat(127, '  verticalPanSpeed:   ' .. tostring(stats.verticalPanSpeed))
    windower.add_to_chat(127, '  saveOnIncrement:    ' .. tostring(settings.saveOnIncrement))
    windower.add_to_chat(127, '  autoCalcVertSpeed:  ' .. tostring(settings.autoCalcVertSpeed))
end

local function print_help()
    windower.add_to_chat(8, '[Chharcam] v' .. _addon.version)
    windower.add_to_chat(8, '  //cam d|distance <n>   set camera distance')
    windower.add_to_chat(8, '  //cam b|battle <n>     set battle-camera distance')
    windower.add_to_chat(8, '  //cam hs|hspeed <n>    set horizontal pan speed')
    windower.add_to_chat(8, '  //cam vs|vspeed <n>    set vertical pan speed')
    windower.add_to_chat(8, '  //cam in / de          increment / decrement distance')
    windower.add_to_chat(8, '  //cam bin / bde        increment / decrement battle distance')
    windower.add_to_chat(8, '  //cam soi              toggle saveOnIncrement')
    windower.add_to_chat(8, '  //cam acv              toggle autoCalcVertSpeed')
    windower.add_to_chat(8, '  //cam s|status         print current settings')
end

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd and cmd:lower()) or 'help'
    local args = { ... }

    if     cmd == 'help' or cmd == 'h'           then print_help()
    elseif cmd == 'd'   or cmd == 'distance'     then set_distance(args[1])
    elseif cmd == 'b'   or cmd == 'battle'       then set_battle(args[1])
    elseif cmd == 'hs'  or cmd == 'hspeed'       then set_hspeed(args[1])
    elseif cmd == 'vs'  or cmd == 'vspeed'       then set_vspeed(args[1])
    elseif cmd == 'in'  or cmd == 'incr'         then step(false, true)
    elseif cmd == 'de'  or cmd == 'decr'         then step(false, false)
    elseif cmd == 'bin' or cmd == 'bincr'        then step(true,  true)
    elseif cmd == 'bde' or cmd == 'bdecr'        then step(true,  false)
    elseif cmd == 'soi' or cmd == 'saveonincrement' then
        settings.saveOnIncrement = not settings.saveOnIncrement
        config.save(settings)
        announce('saveOnIncrement = ' .. tostring(settings.saveOnIncrement))
    elseif cmd == 'acv' or cmd == 'autocalcvertspeed' then
        settings.autoCalcVertSpeed = not settings.autoCalcVertSpeed
        config.save(settings)
        announce('autoCalcVertSpeed = ' .. tostring(settings.autoCalcVertSpeed))
    elseif cmd == 's'   or cmd == 'status'       then print_status()
    else
        announce('unknown command: ' .. cmd)
        print_help()
    end
end)
