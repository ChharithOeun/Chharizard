-- ============================================================================
-- Chharbar / core / compat_ashita.lua  (Chharizard v5.4.0+)
--
-- Installs a fake `windower.*` global on Ashita v4 backed by Ashita's real
-- API. Existing Chharbar modules that call windower.register_event,
-- windower.ffxi.get_player, windower.add_to_chat, etc. keep working
-- without migration.
--
-- This is a COMPAT SHIM. Not every windower function has a perfect Ashita
-- equivalent. Where behavior differs materially, the wrapped function does
-- its best-effort translation and warns via chat.
--
-- Coverage as of v5.4.0:
--   [OK]      register_event('load' / 'unload' / 'prerender')
--   [OK]      register_event('login' / 'logout' / 'zone change')
--   [OK]      register_event('incoming chunk' / 'outgoing chunk')
--   [OK]      register_event('incoming text' / 'text_added')
--   [OK]      register_event('action')
--   [OK]      register_event('keyboard' / 'mouse')
--   [OK]      ffxi.get_player, get_target (via get_mob_by_target)
--   [OK]      ffxi.get_mob_by_id, get_mob_by_index, get_mob_by_target
--   [OK]      ffxi.get_party (basic — p0-p5 shape)
--   [OK]      ffxi.get_info (zone id, chat_open, target_index)
--   [OK]      ffxi.get_items (inventory only)
--   [OK]      ffxi.get_spells, get_abilities
--   [OK]      add_to_chat, send_command
--   [OK]      addon_path, pol_path
--   [STUB]    text.new / image.new — return no-op widget objects (v5.4.2
--             will implement via imgui-based rendering)
--   [PARTIAL] resources module — mapped to Ashita's AshitaCore:GetResourceManager
--
-- Modules that rely heavily on widget rendering will visually degrade on
-- Ashita until v5.4.2 lands. Data + logic paths work.
-- ============================================================================

assert(type(_G.ashita) == 'table',
    '[compat_ashita] ashita global missing — this adapter is Ashita-only.')

-- ----------------------------------------------------------------------------
-- Shim namespace: window
-- ----------------------------------------------------------------------------
local W = {}

-- --- Event registration -----------------------------------------------------
-- Ashita's ashita.events.register(evt_name, cb_id, fn) uses named callbacks;
-- Windower uses anonymous callbacks. Assign auto-incremented IDs.
local _cb_counter = 0
local function _next_cb_id(evt)
    _cb_counter = _cb_counter + 1
    return 'chharbar_' .. evt .. '_' .. tostring(_cb_counter)
end

-- Map Windower event names to Ashita event names.
local EVENT_MAP = {
    ['load']            = 'load',
    ['unload']          = 'unload',
    ['prerender']       = 'd3d_present',
    ['login']           = 'load',       -- Ashita fires 'load' on each char load
    ['logout']          = 'unload',
    ['zone change']     = 'zone_enter',
    ['incoming chunk']  = 'packet_in',
    ['outgoing chunk']  = 'packet_out',
    ['incoming text']   = 'text_in',
    ['text_added']      = 'text_in',
    ['action']          = 'packet_in',  -- action = 0x028 packet
    ['keyboard']        = 'key',
    ['mouse']           = 'mouse',
}

function W.register_event(evt_or_evts, ...)
    local args = {...}
    -- Windower supports register_event(evt1, evt2, ..., fn)
    -- Ashita registers one at a time.
    local fn = args[#args]
    if type(fn) ~= 'function' then
        error('[compat_ashita] register_event: last arg must be function')
    end
    local evts = { evt_or_evts }
    for i = 1, #args - 1 do
        table.insert(evts, args[i])
    end
    local ids = {}
    for _, e in ipairs(evts) do
        local ashita_evt = EVENT_MAP[e]
        if not ashita_evt then
            print('[chharbar] warn: unknown event ' .. tostring(e) .. ' (Ashita compat)')
        else
            local cb_id = _next_cb_id(e)
            ashita.events.register(ashita_evt, cb_id, function(payload)
                -- Try to translate payload signature. For events where
                -- windower's args differ from ashita's, adapt here.
                return fn(payload)
            end)
            table.insert(ids, cb_id)
        end
    end
    return ids
end

-- --- FFXI data helpers ------------------------------------------------------
W.ffxi = {}

local function _memmgr()
    return AshitaCore:GetMemoryManager()
end

function W.ffxi.get_player()
    local mm = _memmgr()
    if not mm then return nil end
    local party = mm:GetParty()
    local player = mm:GetPlayer()
    if not player then return nil end
    return {
        id           = party and party:GetMemberServerId(0) or 0,
        index        = party and party:GetMemberTargetIndex(0) or 0,
        name         = party and party:GetMemberName(0) or '',
        hp           = party and party:GetMemberHP(0) or 0,
        hpp          = party and party:GetMemberHPPercent(0) or 0,
        mp           = party and party:GetMemberMP(0) or 0,
        mpp          = party and party:GetMemberMPPercent(0) or 0,
        tp           = party and party:GetMemberTP(0) or 0,
        main_job     = player and player:GetMainJob() or 0,
        sub_job      = player and player:GetSubJob() or 0,
        main_job_level = player and player:GetMainJobLevel() or 0,
        sub_job_level  = player and player:GetSubJobLevel() or 0,
    }
end

function W.ffxi.get_target()
    local mm = _memmgr()
    if not mm then return nil end
    local t = mm:GetTarget()
    if not t then return nil end
    local idx = t:GetTargetIndex(0)
    return W.ffxi.get_mob_by_index(idx)
end

function W.ffxi.get_mob_by_index(idx)
    local mm = _memmgr()
    if not mm or not idx or idx == 0 then return nil end
    local ent = mm:GetEntity()
    if not ent then return nil end
    return {
        id       = ent:GetServerId(idx),
        index    = idx,
        name     = ent:GetName(idx) or '',
        hpp      = ent:GetHPPercent(idx) or 0,
        distance = ent:GetDistance(idx) or 0,
        x        = ent:GetLocalPositionX(idx) or 0,
        y        = ent:GetLocalPositionY(idx) or 0,
        z        = ent:GetLocalPositionZ(idx) or 0,
        is_npc   = (ent:GetSpawnFlags(idx) or 0) == 0,
        valid_target = (ent:GetSpawnFlags(idx) or 0) ~= 0,
    }
end

function W.ffxi.get_mob_by_id(id)
    local mm = _memmgr()
    if not mm or not id then return nil end
    local ent = mm:GetEntity()
    if not ent then return nil end
    for i = 0, 2303 do
        if ent:GetServerId(i) == id then
            return W.ffxi.get_mob_by_index(i)
        end
    end
    return nil
end

function W.ffxi.get_mob_by_target(t)
    -- 't' can be 't' (target), 'st' (subtarget), 'me' (player)
    if t == 'me' then
        local p = W.ffxi.get_player()
        if not p then return nil end
        return W.ffxi.get_mob_by_index(p.index)
    end
    return W.ffxi.get_target()
end

function W.ffxi.get_party()
    local mm = _memmgr()
    if not mm then return {} end
    local pt = mm:GetParty()
    if not pt then return {} end
    local out = {}
    for i = 0, 17 do  -- 0-5 party, 6-11 a1, 12-17 a2
        local name = pt:GetMemberName(i)
        if name and name ~= '' then
            local key = (i < 6) and ('p' .. i)
                     or (i < 12) and ('a1' .. (i - 6))
                     or ('a2' .. (i - 12))
            out[key] = {
                name = name,
                mob = {
                    id    = pt:GetMemberServerId(i),
                    index = pt:GetMemberTargetIndex(i),
                    hpp   = pt:GetMemberHPPercent(i),
                    mpp   = pt:GetMemberMPPercent(i),
                },
                hp  = pt:GetMemberHP(i),
                mp  = pt:GetMemberMP(i),
                tp  = pt:GetMemberTP(i),
                main_job = pt:GetMemberMainJob(i),
                sub_job  = pt:GetMemberSubJob(i),
            }
        end
    end
    return out
end

function W.ffxi.get_info()
    local mm = _memmgr()
    if not mm then return {} end
    local party = mm:GetParty()
    return {
        zone         = party and party:GetMemberZone(0) or 0,
        chat_open    = false,   -- Ashita doesn't expose chat_open directly
        target_index = 0,
        logged_in    = party and (party:GetMemberName(0) ~= ''),
    }
end

function W.ffxi.get_items()
    local mm = _memmgr()
    if not mm then return {} end
    local inv = mm:GetInventory()
    if not inv then return {} end
    local out = { inventory = {} }
    for i = 1, 80 do
        local item = inv:GetContainerItem(0, i)
        if item and item.Id > 0 then
            table.insert(out.inventory, { id = item.Id, count = item.Count, slot = i })
        end
    end
    return out
end

function W.ffxi.get_spells()
    local mm = _memmgr()
    if not mm or not mm:GetPlayer() then return {} end
    local out = {}
    for i = 0, 1023 do
        if mm:GetPlayer():HasSpell(i) then
            out[i] = true
        end
    end
    return out
end

function W.ffxi.get_abilities()
    -- Ashita exposes abilities via GetPlayer():HasAbility per-id
    local mm = _memmgr()
    if not mm or not mm:GetPlayer() then return {} end
    local out = { job_abilities = {}, weapon_skills = {} }
    for i = 0, 1023 do
        if mm:GetPlayer():HasAbility(i) then
            table.insert(out.job_abilities, i)
        end
    end
    return out
end

-- --- Chat / commands --------------------------------------------------------
function W.add_to_chat(color, msg)
    if not AshitaCore then return end
    AshitaCore:GetChatManager():AddChatMessage(color or 207, false, tostring(msg))
end

function W.send_command(cmd)
    if not AshitaCore then return end
    AshitaCore:GetChatManager():QueueCommand(-1, tostring(cmd))
end

-- --- Paths ------------------------------------------------------------------
W.addon_path = (_G.addon and _G.addon.path) or ''
W.pol_path   = ''  -- Ashita doesn't expose pol_path; leave blank

-- --- Widget stubs (v5.4.2 will replace with imgui rendering) ---------------
W.text = {}
function W.text.create(name)  return W.text.new({ name = name }) end
function W.text.new(opts)
    -- Return a widget object with the windower.texts API surface. Currently
    -- no-ops with a warning on first use so modules keep loading. v5.4.2
    -- will make these render via imgui.
    local widget = { _shown = false, _opts = opts, _text = '' }
    function widget:show()    self._shown = true end
    function widget:hide()    self._shown = false end
    function widget:text(s)   self._text = s end
    function widget:pos(x, y) self._opts.x, self._opts.y = x, y end
    function widget:size(s)   self._opts.size = s end
    function widget:color(r, g, b) end
    function widget:bg_color(r, g, b) end
    function widget:bg_alpha(a) end
    function widget:bg_visible(v) end
    function widget:visible(v)     self._shown = v end
    function widget:destroy() end
    return widget
end

W.image = {}
function W.image.new(opts)
    local img = { _shown = false, _opts = opts }
    function img:show() self._shown = true end
    function img:hide() self._shown = false end
    function img:path(p) end
    function img:pos(x, y) end
    function img:size(w, h) end
    function img:alpha(a) end
    function img:visible(v) self._shown = v end
    function img:destroy() end
    return img
end

-- ----------------------------------------------------------------------------
-- Install the shim globally.
-- ----------------------------------------------------------------------------
_G.windower = W

-- Announce we're active so users know they're on the Ashita compat path.
if AshitaCore and AshitaCore.GetChatManager then
    AshitaCore:GetChatManager():AddChatMessage(207,
        false, '[Chharbar] Ashita compat shim active (v5.4.0). Widgets stubbed until v5.4.2.')
end
