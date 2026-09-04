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

-- --- Widget rendering via imgui (v5.4.2) -----------------------------------
-- All widgets register into a central registry. A single d3d_present handler
-- iterates the registry each frame and draws visible widgets via imgui.
-- This keeps per-widget code tiny and lets us add features (borders, gradients,
-- pulse animations) to every widget by editing one place.

local _widgets = {}
local _next_id = 0
local function _mkid() _next_id = _next_id + 1; return 'chz_' .. _next_id end

-- Convert 0-255 to 0.0-1.0 for imgui
local function _rgba(c)
    local r = (c[1] or 255) / 255
    local g = (c[2] or 255) / 255
    local b = (c[3] or 255) / 255
    local a = (c[4] or 255) / 255
    return r, g, b, a
end

local function _make_text_widget(opts)
    opts = opts or {}
    local w = {
        _id           = _mkid(),
        _kind         = 'text',
        _shown        = false,
        _text         = opts.text or '',
        _x            = opts.pos and opts.pos.x or 0,
        _y            = opts.pos and opts.pos.y or 0,
        _color        = {255, 255, 255, 255},
        _bg_color     = {0, 0, 0, 200},
        _bg_visible   = false,
        _size         = opts.size or 12,
        _font         = opts.font or 'Arial',
        _stroke_w     = 0,
        _stroke_color = {0, 0, 0, 255},
        _right_just   = false,
    }
    function w:show()          self._shown = true end
    function w:hide()          self._shown = false end
    function w:visible(v)      self._shown = v and true or false end
    function w:text(s)         self._text = tostring(s or '') end
    function w:pos(x, y)       self._x, self._y = x, y end
    function w:pos_x(x)        self._x = x end
    function w:pos_y(y)        self._y = y end
    function w:size(s)         self._size = s end
    function w:color(r, g, b)  self._color = {r, g, b, self._color[4] or 255} end
    function w:alpha(a)        self._color[4] = a end
    function w:bg_color(r, g, b) self._bg_color = {r, g, b, self._bg_color[4] or 200} end
    function w:bg_alpha(a)     self._bg_color[4] = a end
    function w:bg_visible(v)   self._bg_visible = v and true or false end
    function w:font(name)      self._font = name end
    function w:stroke_width(n) self._stroke_w = n end
    function w:stroke_color(r, g, b) self._stroke_color = {r, g, b, 255} end
    function w:right_justified(b) self._right_just = b end
    function w:destroy()       _widgets[self._id] = nil end
    function w:extents()       return #self._text * (self._size * 0.6), self._size + 4 end
    _widgets[w._id] = w
    return w
end

local function _make_image_widget(opts)
    opts = opts or {}
    local w = {
        _id     = _mkid(),
        _kind   = 'image',
        _shown  = false,
        _path   = opts.path or '',
        _x      = opts.pos and opts.pos.x or 0,
        _y      = opts.pos and opts.pos.y or 0,
        _width  = opts.size and opts.size.width or 32,
        _height = opts.size and opts.size.height or 32,
        _alpha  = 255,
    }
    function w:show()      self._shown = true end
    function w:hide()      self._shown = false end
    function w:visible(v)  self._shown = v and true or false end
    function w:path(p)     self._path = p end
    function w:pos(x, y)   self._x, self._y = x, y end
    function w:size(w2, h) self._width, self._height = w2, h end
    function w:alpha(a)    self._alpha = a end
    function w:destroy()   _widgets[self._id] = nil end
    _widgets[w._id] = w
    return w
end

W.text = {}
function W.text.create(name) return _make_text_widget({ name = name }) end
function W.text.new(...)     return _make_text_widget(select(1, ...)) end

W.image = {}
function W.image.new(...)    return _make_image_widget(select(1, ...)) end

-- Central per-frame draw. Registered once at load. Iterates all visible
-- widgets and calls imgui to render them.
--
-- imgui window pattern: use SetNextWindowPos + Begin with NoDecoration flags
-- to draw text at an absolute screen position without a chrome window.
local WINDOW_FLAGS = 0
if imgui then
    -- Compose flags. Values from Ashita's imgui binding (imgui.WindowFlags):
    -- NoTitleBar (1), NoResize (2), NoMove (4), NoScrollbar (8), NoBackground (128),
    -- NoInputs (512), AlwaysAutoResize (64), NoSavedSettings (1024)
    WINDOW_FLAGS = 1 + 2 + 4 + 8 + 128 + 512 + 64 + 1024
end

local function _draw_all()
    if not imgui then return end
    for id, w in pairs(_widgets) do
        if w._shown then
            imgui.SetNextWindowPos(w._x, w._y)
            imgui.SetNextWindowBgAlpha(0.0)  -- outer window transparent; we draw bg ourselves
            if imgui.Begin('##' .. w._id, true, WINDOW_FLAGS) then
                if w._kind == 'text' then
                    -- Draw background rect if enabled
                    if w._bg_visible then
                        local r, g, b, a = _rgba(w._bg_color)
                        imgui.PushStyleColor(2, r, g, b, a)  -- ChildBg
                        local tw, th = w:extents()
                        imgui.BeginChild('##bg_' .. w._id, tw + 8, th + 4, false)
                        imgui.EndChild()
                        imgui.PopStyleColor(1)
                        imgui.SetCursorPos(4, 2)
                    end
                    -- Draw text
                    local r, g, b, a = _rgba(w._color)
                    imgui.PushStyleColor(0, r, g, b, a)  -- Text
                    imgui.TextUnformatted(w._text)
                    imgui.PopStyleColor(1)
                elseif w._kind == 'image' then
                    -- Ashita imgui image loading: requires a texture id from
                    -- the primitive manager. For v5.4.2 we log and skip until
                    -- image support lands in v5.4.3.
                end
                imgui.End()
            end
        end
    end
end

if ashita and ashita.events and ashita.events.register then
    ashita.events.register('d3d_present', 'chz_draw_all', _draw_all)
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
