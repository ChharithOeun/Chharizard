-- ============================================================================
-- Chharbar / core / framework.lua
--
-- Provides the CHB namespace, widget helpers, prerender tick dispatcher,
-- mouse pipeline, command router, auto-hide gate, per-toon state I/O, and
-- perf profiler. Required by Chharbar.lua BEFORE any module.
--
-- Do NOT `//lua load` this directly. It is a library file for the loader.
-- ============================================================================

require('tables')
require('strings')
texts   = require('texts')
res     = require('resources')
files   = require('files')

-- ============================================================================
-- CHB — global namespace. Kept intentionally small and inspectable.
-- ============================================================================
CHB = {
    modules       = {},      -- [name] = module def
    order         = {},      -- registration order for iteration
    settings      = {},      -- [name] = active settings (merged: defaults + per-toon)
    state         = { version = 3, toons = {} },  -- persisted; per-toon slices
    tick_counter  = 0,       -- prerender frame counter (0..59)
    state_file    = nil,     -- files.new handle, set at load
    log_level     = 'info',  -- 'debug' | 'info' | 'quiet'
    disabled      = false,   -- kill-switch for the whole addon
}

-- ---- v4.7.10: persistent debug log --------------------------------------
-- Appends every important event to data/chharbar.log with a timestamp so
-- you can see what fired and when (and go back and check if a bug was
-- patched between two dates). Rotates at ~200 KB into chharbar.log.bak.
CHB.debug_log_file = nil
CHB.debug_log_size = 0
local DEBUG_LOG_MAX = 200 * 1024

function CHB.log(msg)
    if not files then return end
    if not CHB.debug_log_file then
        pcall(function() CHB.debug_log_file = files.new('data/chharbar.log', true) end)
        CHB.debug_log_size = 0
    end
    if not CHB.debug_log_file then return end
    local line = string.format('[%s v%s] %s\n',
        os.date('%Y-%m-%d %H:%M:%S'), _addon.version, tostring(msg))
    pcall(function() CHB.debug_log_file:append(line) end)
    CHB.debug_log_size = CHB.debug_log_size + #line
    -- Rotate when file gets big.
    if CHB.debug_log_size > DEBUG_LOG_MAX then
        pcall(function()
            local bak = files.new('data/chharbar.log.bak', true)
            local cur = CHB.debug_log_file:read() or ''
            bak:write(cur)
            CHB.debug_log_file:write('[rotated ' .. os.date('%Y-%m-%d %H:%M:%S') .. ']\n')
        end)
        CHB.debug_log_size = 0
    end
end

-- ---- v4.7.10: shared caches to slash per-action-packet lookups. Many
-- modules independently call get_mob_by_id(actor_id) and get_party() for
-- the SAME actor within the same packet. With 5 action handlers × 30
-- action packets/sec (6-box combat), that's 300 redundant lookups/sec.
-- Cache with a tight TTL and share across handlers.
CHB.cache_actor_id   = nil
CHB.cache_actor_name = nil
CHB.cache_actor_ts   = 0
CHB.cache_party_data = nil
CHB.cache_party_ts   = 0

function CHB.actor_name(actor_id)
    if not actor_id or actor_id == 0 then return nil end
    local now = os.clock()
    if CHB.cache_actor_id == actor_id and (now - CHB.cache_actor_ts) < 0.05 then
        return CHB.cache_actor_name
    end
    local name
    pcall(function()
        local m = windower.ffxi.get_mob_by_id(actor_id)
        if m and m.name then name = m.name end
    end)
    CHB.cache_actor_id, CHB.cache_actor_name, CHB.cache_actor_ts = actor_id, name, now
    return name
end

function CHB.party()
    local now = os.clock()
    if CHB.cache_party_data and (now - CHB.cache_party_ts) < 0.1 then
        return CHB.cache_party_data
    end
    local ok, p = pcall(function() return windower.ffxi.get_party() end)
    if ok and type(p) == 'table' then
        CHB.cache_party_data, CHB.cache_party_ts = p, now
    end
    return CHB.cache_party_data
end

-- ---- logging ---------------------------------------------------------------
local function log_info(msg)
    if CHB.log_level == 'quiet' then return end
    windower.add_to_chat(207, 'chharbar: ' .. tostring(msg))
end

local function log_debug(msg)
    if CHB.log_level ~= 'debug' then return end
    windower.add_to_chat(207, 'chharbar(dbg): ' .. tostring(msg))
end

-- ---- module registration --------------------------------------------------
--
-- A module is a table with:
--   .name           string, unique
--   .default        table of user-tunable settings (enabled, pos, size, etc.)
--   .on_create()    spawn widgets, called after settings are loaded
--   .on_tick()      called every N frames per default.tick_frames
--   .on_destroy()   cleanup widgets
--   .on_command()   optional: (subcmd, rest) -> handle //cb <name> <sub>
--   .on_dump()      optional: return {k=v, ...} for //cb dev <name>
--
-- No module ever touches another module's state, texts objects, or settings.
function CHB.register(mod)
    if not mod or type(mod.name) ~= 'string' then
        log_info('register: bad module (missing .name)')
        return
    end
    if CHB.modules[mod.name] then
        log_info('register: overriding existing module ' .. mod.name)
    end
    CHB.modules[mod.name] = mod
    if not table.contains(CHB.order, mod.name) then
        CHB.order[#CHB.order + 1] = mod.name
    end
end

-- Look up a module by name; returns nil if not registered.
function CHB.get(name)
    return CHB.modules[name]
end

-- ---- settings merge -------------------------------------------------------
--
-- Priority (highest wins):
--   1. per-toon persisted   (CHB.state.toons[me].modules[name])
--   2. module defaults      (mod.default)
--
-- Called once per module during on_create. Result is stored in
-- CHB.settings[name] and passed to the module via mod.settings.
local function _shallow_merge(dst, src)
    if type(src) ~= 'table' then return dst end
    for k, v in pairs(src) do
        if type(v) == 'table' and type(dst[k]) == 'table' then
            _shallow_merge(dst[k], v)
        else
            dst[k] = v
        end
    end
    return dst
end

local function me_name()
    local ok, p = pcall(function() return windower.ffxi.get_player() end)
    if ok and p and p.name then return p.name end
    return nil
end

function CHB.load_settings(name)
    local mod = CHB.modules[name]
    if not mod then return {} end
    local merged = {}
    _shallow_merge(merged, mod.default or {})
    local toon = me_name()
    if toon and CHB.state.toons[toon]
            and CHB.state.toons[toon].modules
            and CHB.state.toons[toon].modules[name] then
        _shallow_merge(merged, CHB.state.toons[toon].modules[name])
    end
    CHB.settings[name] = merged
    mod.settings = merged
    return merged
end

function CHB.save_settings(name)
    local toon = me_name()
    if not toon then return end
    CHB.state.toons[toon] = CHB.state.toons[toon] or { modules = {} }
    CHB.state.toons[toon].modules = CHB.state.toons[toon].modules or {}
    CHB.state.toons[toon].modules[name] = CHB.settings[name]
    CHB.save_state()
end

-- ---- state file (data/state_v3.lua) ---------------------------------------
--
-- Format: a plain Lua return-table.
--   return {
--     version = 3,
--     toons = {
--       ['Chharzilla'] = {
--         modules = { vitals = { pos_x=20, pos_y=20, font_size=12, ... } }
--       }
--     }
--   }
local function _serialize_value(v, indent)
    indent = indent or ''
    local t = type(v)
    if t == 'number' then return tostring(v) end
    if t == 'boolean' then return tostring(v) end
    if t == 'string' then return string.format('%q', v) end
    if t == 'table' then
        local buf = { '{\n' }
        for k, vv in pairs(v) do
            local key
            if type(k) == 'string' and k:match('^[%a_][%w_]*$') then
                key = k
            else
                key = '[' .. _serialize_value(k, indent) .. ']'
            end
            buf[#buf + 1] = string.format('%s  %s = %s,\n',
                indent, key, _serialize_value(vv, indent .. '  '))
        end
        buf[#buf + 1] = indent .. '}'
        return table.concat(buf)
    end
    return 'nil'
end

function CHB.save_state()
    if not CHB.state_file then return end
    local ok, err = pcall(function()
        CHB.state_file:write('return ' .. _serialize_value(CHB.state))
    end)
    if not ok then log_info('save_state failed: ' .. tostring(err)) end
end

function CHB.load_state()
    if not CHB.state_file then return end
    local ok, data
    pcall(function()
        ok, data = pcall(function()
            local src = CHB.state_file:read()
            if not src or src == '' then return nil end
            local chunk, err = loadstring(src)
            if not chunk then error(err) end
            return chunk()
        end)
    end)
    if ok and type(data) == 'table' then
        CHB.state = data
        if type(CHB.state.toons) ~= 'table' then CHB.state.toons = {} end
        CHB.state.version = 3
    end
end

-- ============================================================================
-- WIDGET HELPERS — nuclear-force render pattern
--
-- Every module uses CHB.render_text(widget, opts) instead of the old
-- bg_visible/visible toggle dance. Sets the full widget state atomically each
-- call. If the widget was left in a bad state by anything else, the next
-- render corrects it — no cache to drift, no state machine to get stuck.
-- ============================================================================

-- v4.7.3: companion "border" widget per module. Slightly larger + gold bg
-- rendered BEHIND the content widget → thin gold ring around every UI.
-- Border color/alpha can be pulsed per-frame from module tick code by
-- calling CHB.set_border_pulse(widget, r, g, b, alpha).
--
-- v4.7.9: borders are now OFF by default. Doubling every widget was the
-- most likely cause of the stutter you were seeing. Enable with
-- //cb border on (all widgets get gold trim); disable via //cb border off.
CHB.border_enabled  = false
CHB.border_by_widget = {}

function CHB.new_text_widget(opts)
    opts = opts or {}
    local base_pad = opts.padding or 4
    local settings = {
        pos = { x = opts.pos_x or 0, y = opts.pos_y or 0 },
        padding = base_pad,
        bg = {
            alpha   = opts.opacity or 200,
            red     = opts.bg_r or 0,
            green   = opts.bg_g or 0,
            blue    = opts.bg_b or 0,
            visible = true,
        },
        text = {
            font  = opts.font  or 'Consolas',
            size  = opts.font_size or 12,
            alpha = 255,
            red = 255, green = 255, blue = 255,
            stroke = {
                width = opts.stroke_width or 3,
                alpha = 220, red = 0, green = 0, blue = 0,
            },
        },
        flags = {
            -- v3.6.1: native texts:draggable intercepts left-click before our
            -- mouse handler can see it, which stole corner-resize clicks and
            -- turned them into drag-moves. We disable native drag and
            -- implement BOTH drag-move and corner-resize in our own mouse
            -- pipeline (see the 'mouse' event handler below).
            draggable = false,
            bold = false, italic = false, right = false,
        },
    }
    -- v4.7.4: create the gold-border companion FIRST so it renders BEHIND
    -- the content widget. Windower draws text objects in creation order —
    -- if border came second it would sit ON TOP of the content, painting
    -- everything gold (v4.7.3 bug). Same-shape invisible text auto-sizes
    -- it to match the content, +2 padding and (-2,-2) offset produces a
    -- 2px gold ring around the content's black background.
    local border_settings = {
        pos     = { x = (opts.pos_x or 0) - 2, y = (opts.pos_y or 0) - 2 },
        padding = base_pad + 2,
        bg      = {
            alpha   = 220,
            red     = 200, green = 160, blue = 60,   -- gold
            visible = true,
        },
        text    = {
            font  = opts.font or 'Consolas',
            size  = opts.font_size or 12,
            alpha = 0,           -- invisible text
            red   = 0, green = 0, blue = 0,
            stroke = { width = 0, alpha = 0, red = 0, green = 0, blue = 0 },
        },
        flags   = { draggable = false, bold = false, italic = false, right = false },
    }
    local border = texts.new('', border_settings)

    -- Content widget created SECOND so it draws ON TOP of the border,
    -- covering the interior with its own black background — the only
    -- gold visible is the 2px ring around the outside.
    local widget = texts.new('', settings)
    -- v4.7.9: only wire the border companion if the feature is enabled at
    -- widget-creation time. Users who leave borders off pay ZERO cost per
    -- widget for border rendering. Toggle //cb border on then //lua reload
    -- chharbar to make border widgets appear.
    if CHB.border_enabled then
        CHB.border_by_widget[widget] = border
    else
        pcall(function() border:hide() end)
        pcall(function() border:destroy() end)
    end
    return widget
end

-- v4.7.3: per-tick border color/alpha driver, callable from module ticks.
-- Called with (widget, r, g, b, alpha) — nil alpha reverts to static gold.
function CHB.set_border_pulse(widget, r, g, b, alpha)
    local border = CHB.border_by_widget[widget]
    if not border then return end
    local bst = CHB.render_state[border] or {}
    if not alpha then
        -- v4.7.6: reverting to static gold — release pulse control back
        -- to the user's opacity setting.
        r, g, b, alpha = 200, 160, 60, 220
        bst.pulse_active = false
    else
        bst.pulse_active = true
    end
    pcall(function() border:bg_color(r, g, b) end)
    pcall(function() border:bg_alpha(alpha) end)
    bst.bg_r, bst.bg_g, bst.bg_b = r, g, b
    bst.alpha = alpha
    CHB.render_state[border] = bst
end

-- v4.7.5: cache last-pushed state per widget so we can diff and skip
-- redundant Windower calls. Big perf win — render was pushing text/pos/
-- size/visibility every tick for BOTH content and border widget even when
-- values hadn't changed. With 12+ modules × 2 widgets × ~5 pcalls × up
-- to 20 Hz, that's thousands of no-op writes per second.
CHB.render_state = {}   -- [widget] = { text, px, py, size, bg_r, bg_g, bg_b, alpha, shown }

-- The one render function every module calls. Nuclear-force ONLY when
-- values change (previously "nuclear-force everything every tick").
function CHB.render_text(widget, opts)
    if not widget then return end
    opts = opts or {}
    local text = opts.text or ''
    if CHB.edit_mode then
        text = text .. '\n\\cs(255,180, 60)[= drag to resize =]\\cr'
    end
    local st = CHB.render_state[widget] or {}
    local px, py = opts.pos_x, opts.pos_y
    local fs = opts.font_size
    local bg_r, bg_g, bg_b = opts.bg_r or 0, opts.bg_g or 0, opts.bg_b or 0
    -- v4.7.6: content bg alpha is FORCED to 255 so it fully covers the
    -- gold border widget behind it. Only the 2px ring around the outside
    -- shows gold. The user's opacity setting is redirected to the BORDER
    -- widget below so it still controls overall softness of the gold trim.
    local a = 255
    local border_alpha = opts.opacity or 200

    if st.text ~= text then
        pcall(function() widget:text(text) end); st.text = text
    end
    if px and py and (st.px ~= px or st.py ~= py) then
        pcall(function() widget:pos(px, py) end); st.px, st.py = px, py
    end
    if fs and st.size ~= fs then
        pcall(function() widget:size(fs) end); st.size = fs
    end
    if st.bg_r ~= bg_r or st.bg_g ~= bg_g or st.bg_b ~= bg_b then
        pcall(function() widget:bg_color(bg_r, bg_g, bg_b) end)
        st.bg_r, st.bg_g, st.bg_b = bg_r, bg_g, bg_b
    end
    if st.alpha ~= a then
        pcall(function() widget:bg_alpha(a) end); st.alpha = a
    end
    if not st.shown then
        pcall(function() widget:bg_visible(true) end)
        pcall(function() widget:visible(true) end)
        pcall(function() widget:show() end)
        st.shown = true
    end
    CHB.render_state[widget] = st

    -- Border companion — same diff pattern.
    local border = CHB.border_by_widget[widget]
    if border then
        local bst = CHB.render_state[border] or {}
        if bst.text ~= text then
            pcall(function() border:text(text) end); bst.text = text
        end
        if px and py and (bst.px ~= px or bst.py ~= py) then
            pcall(function() border:pos(px - 2, py - 2) end)
            bst.px, bst.py = px, py
        end
        if fs and bst.size ~= fs then
            pcall(function() border:size(fs) end); bst.size = fs
        end
        -- v4.7.6: user's opacity setting drives border alpha (unless a
        -- module has explicitly set a pulse color/alpha via
        -- CHB.set_border_pulse, in which case that stays authoritative).
        if bst.alpha ~= border_alpha and not bst.pulse_active then
            pcall(function() border:bg_alpha(border_alpha) end)
            bst.alpha = border_alpha
        end
        if not bst.shown then
            pcall(function() border:bg_visible(true) end)
            pcall(function() border:visible(true) end)
            pcall(function() border:show() end)
            bst.shown = true
        end
        CHB.render_state[border] = bst
    end
end

function CHB.hide_widget(widget)
    if not widget then return end
    -- v4.7.5: cache state — skip re-hide when already hidden. Also flip
    -- the render_state.shown flag so a subsequent render_text re-shows.
    local st = CHB.render_state[widget] or {}
    if st.shown ~= false or st.alpha ~= 0 or (st.text or '') ~= '' then
        pcall(function() widget:text('') end)
        pcall(function() widget:bg_alpha(0) end)
        pcall(function() widget:bg_visible(false) end)
        pcall(function() widget:visible(false) end)
        pcall(function() widget:hide() end)
        st.text = ''; st.alpha = 0; st.shown = false
        CHB.render_state[widget] = st
    end
    local border = CHB.border_by_widget[widget]
    if border then
        local bst = CHB.render_state[border] or {}
        if bst.shown ~= false then
            pcall(function() border:text('') end)
            pcall(function() border:bg_alpha(0) end)
            pcall(function() border:bg_visible(false) end)
            pcall(function() border:visible(false) end)
            pcall(function() border:hide() end)
            bst.text = ''; bst.shown = false; bst.alpha = 0
            CHB.render_state[border] = bst
        end
    end
end

-- Drag-position sync: read widget's current position back into settings so
-- the next save persists the dragged location. Also flags the module as
-- dirty so the autosave timer knows to write it out.
function CHB.sync_drag_pos(widget, mod)
    if not widget or not mod or not mod.settings then return end
    local ok, x, y = pcall(function() return widget:pos() end)
    if ok and type(x) == 'number' and type(y) == 'number' then
        local nx = math.floor(x)
        local ny = math.floor(y)
        if nx ~= mod.settings.pos_x or ny ~= mod.settings.pos_y then
            mod.settings.pos_x = nx
            mod.settings.pos_y = ny
            CHB.dirty = true
        end
    end
end

-- Approximate widget bounding box: (x, y, w, h). Uses :extents() when the
-- Windower build supports it; falls back to a font-size-based estimate.
function CHB.widget_bbox(widget, settings)
    if not widget then return nil end
    local ok_p, px, py = pcall(function() return widget:pos() end)
    if not ok_p or type(px) ~= 'number' then return nil end
    local w, h
    local ok_e, ew, eh = pcall(function() return widget:extents() end)
    if ok_e and type(ew) == 'number' and type(eh) == 'number' and ew > 0 then
        w, h = ew, eh
    else
        -- Fallback: rough estimate from font_size + text length.
        local fs = (settings and settings.font_size) or 12
        w = math.max(120, fs * 12)
        h = math.max(fs * 1.4, 20)
    end
    return { x = math.floor(px), y = math.floor(py),
             w = math.floor(w),  h = math.floor(h) }
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================
function CHB.start_all()
    for _, name in ipairs(CHB.order) do
        local mod = CHB.modules[name]
        CHB.load_settings(name)
        if mod.on_create then
            local ok, err = pcall(function() mod:on_create() end)
            if not ok then log_info('create ' .. name .. ' failed: ' .. tostring(err)) end
        end
    end
end

function CHB.stop_all()
    for _, name in ipairs(CHB.order) do
        local mod = CHB.modules[name]
        if mod.on_destroy then pcall(function() mod:on_destroy() end) end
    end
end

-- Hard reset: destroy + recreate a module cleanly. Same pattern that made
-- //cb debuffed test work in v2 — bakes it in as a first-class primitive.
function CHB.hard_reset(name)
    local mod = CHB.modules[name]
    if not mod then return false end
    if mod.on_destroy then pcall(function() mod:on_destroy() end) end
    CHB.load_settings(name)
    if mod.on_create then pcall(function() mod:on_create() end) end
    return true
end

-- ============================================================================
-- PRERENDER — the only place ticks are fired.
--
-- Each module's on_tick runs every settings.tick_frames frames. Modules
-- that don't want to tick (or want event-driven updates only) set
-- tick_frames = 0.
-- ============================================================================
-- v4.7.5: perf profiler state. Enabled by //cb perf on.
CHB.perf = { on = false, samples = {}, ticks = 0, start_at = 0 }

windower.register_event('prerender', function()
    if CHB.disabled then return end
    CHB.tick_counter = CHB.tick_counter + 1
    if CHB.tick_counter >= 60 then CHB.tick_counter = 0 end
    local prof = CHB.perf.on
    if prof then CHB.perf.ticks = CHB.perf.ticks + 1 end
    for _, name in ipairs(CHB.order) do
        local mod = CHB.modules[name]
        local s   = mod and mod.settings
        if mod and s and s.enabled ~= false and mod.on_tick then
            local n = tonumber(s.tick_frames) or 12
            if n > 0 and (CHB.tick_counter % n) == 0 then
                if prof then
                    local t0 = os.clock()
                    pcall(function() mod:on_tick() end)
                    local dt = os.clock() - t0
                    local samp = CHB.perf.samples[name] or { calls = 0, total = 0, max = 0 }
                    samp.calls = samp.calls + 1
                    samp.total = samp.total + dt
                    if dt > samp.max then samp.max = dt end
                    CHB.perf.samples[name] = samp
                else
                    pcall(function() mod:on_tick() end)
                end
            end
        end
    end
    -- v3.6.0: autosave dirty settings every 10s so dragged positions and
    -- corner-resize font_size changes survive a game crash.
    if CHB.dirty then
        local now = os.clock()
        if now >= CHB.autosave_at then
            for _, name in ipairs(CHB.order) do
                local mod = CHB.modules[name]
                local toon = me_name()
                if toon and mod and mod.settings then
                    CHB.state.toons[toon] = CHB.state.toons[toon] or { modules = {} }
                    CHB.state.toons[toon].modules[name] = mod.settings
                end
            end
            pcall(CHB.save_state)
            CHB.dirty = false
            CHB.autosave_at = now + 10
        end
    end
end)

-- ============================================================================
-- v3.6.0: click-drag corner resize.
--
-- Left-click inside the bottom-right ~18x18 corner of any widget starts a
-- resize gesture. Drag DOWN grows font size, drag UP shrinks it. Release
-- (mouse-up) saves settings.
--
-- We consume the mouse-down event (return true) so the click doesn't ALSO
-- start a drag-move on the widget. If you want to move the widget instead,
-- click anywhere OTHER than the bottom-right corner.
--
-- Turn `//cb edit on` to make the corner handle visible as a small ◢
-- glyph appended to each widget. Corner clickability is always on.
-- ============================================================================
-- v3.6.2: resize hit area is the ENTIRE BOTTOM STRIP of the widget bbox.
-- This matches where the [= drag to resize =] glyph line actually renders
-- (bottom of the widget, spanning the whole width). Height picked large
-- enough to hit reliably at any font size.
local RESIZE_HANDLE_PX = 26

local function _pt_in_handle(bbox, mx, my)
    if not bbox then return false end
    return mx >= bbox.x and mx <= bbox.x + bbox.w
       and my >= bbox.y + bbox.h - RESIZE_HANDLE_PX and my <= bbox.y + bbox.h
end

local function _pt_in_bbox(bbox, mx, my)
    if not bbox then return false end
    return mx >= bbox.x and mx <= bbox.x + bbox.w
       and my >= bbox.y and my <= bbox.y + bbox.h
end

windower.register_event('mouse', function(mtype, x, y, delta, blocked)
    if blocked or CHB.disabled then return end
    -- mtype: 0=move, 1=lmb down, 2=lmb up, 3=rmb down, 4=rmb up, 5=wheel

    if mtype == 1 then
        if CHB.mouse_dbg then
            log_info(string.format('mouse DOWN @(%d,%d) edit=%s', x, y, tostring(CHB.edit_mode)))
        end
        -- v3.7.0: resize hit area is GATED behind edit mode. Without this
        -- gate, every drag ends up resizing because the bottom strip of the
        -- widget catches every downward drag.
        if CHB.edit_mode then
            for _, name in ipairs(CHB.order) do
                local mod = CHB.modules[name]
                if mod and mod.widget and mod.settings and mod.settings.enabled ~= false then
                    local bbox = CHB.widget_bbox(mod.widget, mod.settings)
                    if CHB.mouse_dbg and bbox then
                        log_info(string.format('  %s bbox=(%d,%d %dx%d)', name, bbox.x, bbox.y, bbox.w, bbox.h))
                    end
                    if bbox and _pt_in_handle(bbox, x, y) then
                        CHB.mouse.resize_mod        = name
                        CHB.mouse.resize_start_size = tonumber(mod.settings.font_size) or 12
                        CHB.mouse.resize_start_y    = y
                        CHB.mouse.resize_start_x    = x
                        if CHB.mouse_dbg then log_info('  -> RESIZE ' .. name) end
                        return true
                    end
                end
            end
        end
        -- Not in a bottom-strip. Widget-body click = drag-move.
        for _, name in ipairs(CHB.order) do
            local mod = CHB.modules[name]
            if mod and mod.widget and mod.settings and mod.settings.enabled ~= false then
                local bbox = CHB.widget_bbox(mod.widget, mod.settings)
                if bbox and _pt_in_bbox(bbox, x, y) then
                    CHB.mouse.drag_mod          = name
                    CHB.mouse.drag_start_x      = x
                    CHB.mouse.drag_start_y      = y
                    CHB.mouse.drag_start_pos_x  = tonumber(mod.settings.pos_x) or bbox.x
                    CHB.mouse.drag_start_pos_y  = tonumber(mod.settings.pos_y) or bbox.y
                    if CHB.mouse_dbg then log_info('  -> MOVE ' .. name) end
                    return true
                end
            end
        end
        if CHB.mouse_dbg then log_info('  -> no widget hit; click passes to game.') end

    elseif mtype == 0 then
        if CHB.mouse.resize_mod then
            local name = CHB.mouse.resize_mod
            local mod = CHB.modules[name]
            if mod and mod.settings then
                local dy = y - CHB.mouse.resize_start_y
                local new_size = math.floor(CHB.mouse.resize_start_size + dy / 4 + 0.5)
                if new_size <  6 then new_size =  6 end
                if new_size > 40 then new_size = 40 end
                if new_size ~= mod.settings.font_size then
                    mod.settings.font_size = new_size
                    pcall(function() mod.widget:size(new_size) end)
                    CHB.dirty = true
                end
            end
            return true
        end
        if CHB.mouse.drag_mod then
            local name = CHB.mouse.drag_mod
            local mod = CHB.modules[name]
            if mod and mod.settings and mod.widget then
                local new_x = CHB.mouse.drag_start_pos_x + (x - CHB.mouse.drag_start_x)
                local new_y = CHB.mouse.drag_start_pos_y + (y - CHB.mouse.drag_start_y)
                mod.settings.pos_x = math.floor(new_x)
                mod.settings.pos_y = math.floor(new_y)
                pcall(function() mod.widget:pos(mod.settings.pos_x, mod.settings.pos_y) end)
                CHB.dirty = true
            end
            return true
        end

    elseif mtype == 2 then
        if CHB.mouse.resize_mod then
            local name = CHB.mouse.resize_mod
            local mod = CHB.modules[name]
            if mod and mod.settings then
                CHB.save_settings(name)
                log_info(name .. ': font_size=' .. tostring(mod.settings.font_size))
            end
            CHB.mouse.resize_mod = nil
            return true
        end
        if CHB.mouse.drag_mod then
            local name = CHB.mouse.drag_mod
            local mod = CHB.modules[name]
            if mod and mod.settings then
                CHB.save_settings(name)
                log_info(name .. ': pos=('
                    .. tostring(mod.settings.pos_x) .. ','
                    .. tostring(mod.settings.pos_y) .. ')')
            end
            CHB.mouse.drag_mod = nil
            return true
        end
    end
end)

windower.register_event('load', function()
    CHB.state_file = files.new('data/state_v3.lua', true)
    CHB.load_state()
    CHB.start_all()
    log_info('v' .. _addon.version .. ' loaded. //cb help')
    pcall(function() CHB.log('loaded — ' .. #CHB.order .. ' modules registered') end)
end)

windower.register_event('unload', function()
    CHB.stop_all()
    CHB.save_state()
    pcall(function() CHB.log('unloaded — state saved') end)
end)

windower.register_event('login', function()
    -- Re-load settings AND rebuild widgets on character switch so the
    -- per-toon UI preset (positions, sizes, enabled/disabled state) from
    -- the state file actually takes effect instead of carrying over the
    -- previous toon's live widgets. v4.7.6.
    for _, name in ipairs(CHB.order) do
        CHB.load_settings(name)
        pcall(function() CHB.hard_reset(name) end)
    end
end)

-- ============================================================================
-- COMMAND DISPATCH
--
--   //cb help                     command index
--   //cb dev <name>               dump module state
--   //cb reload <name>            hard-reset module (destroy + recreate)
--   //cb <name> on|off|toggle     enable/disable a module
--   //cb <name> pos <x> <y>       move a module
--   //cb <name> <subcmd> [args]   module-specific commands
-- ============================================================================
local function _split_words(s)
    local out = {}
    for w in tostring(s or ''):gmatch('%S+') do out[#out + 1] = w end
    return out
end

local function _cmd_help()
    log_info('commands:')
    log_info('  //cb dev <module>          dump live state')
    log_info('  //cb reload <module>       destroy + recreate widget')
    log_info('  //cb modules               list registered modules')
    log_info('  //cb <module> on|off|toggle')
    log_info('  //cb <module> pos <x> <y>  move')
    log_info('  //cb <module> size <n>     font size')
    log_info('  //cb <module> opacity <n>  bg alpha 0..255')
end

local function _cmd_modules()
    log_info('registered modules:')
    for _, name in ipairs(CHB.order) do
        local s = CHB.settings[name] or {}
        log_info(string.format('  %-14s enabled=%s tick=%s',
            name, tostring(s.enabled ~= false), tostring(s.tick_frames or '?')))
    end
end

local function _cmd_dev(name)
    local mod = CHB.modules[name]
    if not mod then log_info('dev: no module: ' .. tostring(name)) return end
    local s = mod.settings or {}
    log_info('dev ' .. name .. ':')
    log_info(string.format('  enabled=%s pos=(%s,%s) size=%s opacity=%s tick=%s',
        tostring(s.enabled ~= false), tostring(s.pos_x), tostring(s.pos_y),
        tostring(s.font_size), tostring(s.opacity), tostring(s.tick_frames)))
    if mod.on_dump then
        local ok, data = pcall(function() return mod:on_dump() end)
        if ok and type(data) == 'table' then
            for k, v in pairs(data) do
                log_info(string.format('  %s = %s', tostring(k), tostring(v)))
            end
        end
    end
end

local function _module_generic(name, sub, rest)
    local mod = CHB.modules[name]
    if not mod then return false end
    local s = mod.settings
    if not s then return false end
    if sub == 'on' or sub == 'show' then
        s.enabled = true; CHB.save_settings(name); CHB.hard_reset(name)
        log_info(name .. ' -> on'); return true
    elseif sub == 'off' or sub == 'hide' then
        s.enabled = false; CHB.save_settings(name)
        if mod.on_destroy then pcall(function() mod:on_destroy() end) end
        log_info(name .. ' -> off'); return true
    elseif sub == 'toggle' or sub == 'tog' then
        s.enabled = not (s.enabled ~= false)
        CHB.save_settings(name)
        if s.enabled then CHB.hard_reset(name)
        elseif mod.on_destroy then pcall(function() mod:on_destroy() end) end
        log_info(name .. ' -> ' .. (s.enabled and 'on' or 'off')); return true
    elseif sub == 'pos' then
        local x, y = rest:match('(%-?%d+)%s+(%-?%d+)')
        if not x then log_info('usage: //cb ' .. name .. ' pos <x> <y>'); return true end
        s.pos_x = tonumber(x); s.pos_y = tonumber(y)
        CHB.save_settings(name); CHB.hard_reset(name)
        log_info(name .. ' -> pos=(' .. s.pos_x .. ',' .. s.pos_y .. ')'); return true
    elseif sub == 'size' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb ' .. name .. ' size <n>'); return true end
        if n < 6 then n = 6 end
        if n > 32 then n = 32 end
        s.font_size = n; CHB.save_settings(name); CHB.hard_reset(name)
        log_info(name .. ' -> size=' .. n); return true
    elseif sub == 'opacity' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb ' .. name .. ' opacity <0..255>'); return true end
        if n < 0 then n = 0 end
        if n > 255 then n = 255 end
        s.opacity = n; CHB.save_settings(name); CHB.hard_reset(name)
        log_info(name .. ' -> opacity=' .. n); return true
    end
    return false
end

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd or ''):lower()
    local args = { ... }
    local rest = table.concat(args, ' ')
    if cmd == '' or cmd == 'help' or cmd == 'h' then _cmd_help() return end
    if cmd == 'modules' or cmd == 'mods' then _cmd_modules() return end
    if cmd == 'dev' or cmd == 'diag' then _cmd_dev(args[1]) return end
    if cmd == 'forcehide' or cmd == 'fh' then
        -- v3.2.2: manual hide toggle for controller users. Bind this to
        -- a gamepad button via FFXI's macro system:
        --   /console cb forcehide on     (macro line 1 — L2 press)
        --   /console cb forcehide off    (macro line 2 — release)
        -- Or via Windower: //bind ^r input //cb forcehide toggle
        local a = (args[1] or ''):lower()
        if a == 'on' then CHB.manual_hide = true
        elseif a == 'off' then CHB.manual_hide = false
        else CHB.manual_hide = not CHB.manual_hide end
        log_info('forcehide -> ' .. (CHB.manual_hide and 'ON' or 'OFF'))
        return
    end
    if cmd == 'perf' then
        -- v4.7.5: per-module on_tick timing profiler.
        local a = (args[1] or ''):lower()
        if a == 'on' then
            CHB.perf.on = true; CHB.perf.samples = {}; CHB.perf.ticks = 0
            CHB.perf.start_at = os.clock()
            log_info('perf: ON — do 15-30s of normal play then //cb perf report'); return
        end
        if a == 'off' then
            CHB.perf.on = false
            log_info('perf: OFF'); return
        end
        if a == 'reset' then
            CHB.perf.samples = {}; CHB.perf.ticks = 0
            CHB.perf.start_at = os.clock()
            log_info('perf: samples cleared'); return
        end
        if a == 'report' then
            local elapsed = math.max(0.001, os.clock() - CHB.perf.start_at)
            log_info(string.format('perf report over %.1fs (%d prerender ticks):', elapsed, CHB.perf.ticks))
            local rows = {}
            for name, s in pairs(CHB.perf.samples) do
                rows[#rows + 1] = {
                    name  = name,
                    calls = s.calls,
                    total = s.total,
                    avg   = s.total / math.max(1, s.calls),
                    max   = s.max,
                    pct   = s.total / elapsed * 100,
                }
            end
            table.sort(rows, function(a, b) return a.total > b.total end)
            for _, r in ipairs(rows) do
                log_info(string.format('  %-14s calls=%-5d total=%.3fs  avg=%.2fms  max=%.2fms  cpu=%.1f%%',
                    r.name, r.calls, r.total, r.avg * 1000, r.max * 1000, r.pct))
            end
            log_info('  --- turn OFF the top-cpu module(s) to test: //cb <name> off')
            return
        end
        log_info('perf: usage: on | off | reset | report')
        return
    end
    if cmd == 'mousedbg' or cmd == 'mdbg' then
        local a = (args[1] or ''):lower()
        if a == 'on' then CHB.mouse_dbg = true
        elseif a == 'off' then CHB.mouse_dbg = false
        else CHB.mouse_dbg = not CHB.mouse_dbg end
        log_info('mouse debug -> ' .. (CHB.mouse_dbg and 'ON' or 'OFF'))
        return
    end
    if cmd == 'bbox' then
        -- v3.6.2: dump the computed bbox for every visible widget so we can
        -- verify hit areas line up with where the widgets actually render.
        for _, name in ipairs(CHB.order) do
            local mod = CHB.modules[name]
            if mod and mod.widget and mod.settings and mod.settings.enabled ~= false then
                local bbox = CHB.widget_bbox(mod.widget, mod.settings)
                if bbox then
                    log_info(string.format('%s: pos=(%d,%d) size=%dx%d handle-strip=y%d..y%d',
                        name, bbox.x, bbox.y, bbox.w, bbox.h,
                        bbox.y + bbox.h - 26, bbox.y + bbox.h))
                else
                    log_info(name .. ': bbox=nil')
                end
            end
        end
        return
    end
    if cmd == 'edit' then
        -- v3.6.0: edit mode adds visible ◢ handles to every widget so users
        -- can see where to click to resize. Corner is clickable either way;
        -- this just makes it discoverable.
        local a = (args[1] or ''):lower()
        if a == 'on'  then CHB.edit_mode = true
        elseif a == 'off' then CHB.edit_mode = false
        else CHB.edit_mode = not CHB.edit_mode end
        log_info('edit mode -> ' .. (CHB.edit_mode and 'ON (drag ◢ corners to resize)' or 'OFF'))
        return
    end
    if cmd == 'save' then
        -- v3.6.0: force-save all current settings to disk right now.
        for _, name in ipairs(CHB.order) do
            local mod = CHB.modules[name]
            if mod and mod.settings then CHB.save_settings(name) end
        end
        log_info('saved.'); return
    end
    if cmd == 'resetpos' then
        -- v4.7.8: restore every module's position back to its default. Use
        -- this when widgets have been dragged off-screen and you can't
        -- find them.
        local n = 0
        for _, name in ipairs(CHB.order) do
            local mod = CHB.modules[name]
            if mod and mod.settings and mod.default then
                if mod.default.pos_x then mod.settings.pos_x = mod.default.pos_x end
                if mod.default.pos_y then mod.settings.pos_y = mod.default.pos_y end
                CHB.save_settings(name)
                pcall(function() CHB.hard_reset(name) end)
                n = n + 1
            end
        end
        log_info('resetpos: ' .. n .. ' module positions restored to defaults + saved.')
        return
    end
    if cmd == 'resetall' then
        -- v4.7.8: nuke this toon's saved overrides entirely and rebuild
        -- from defaults. Fresh-start button. Followed by //cb save is optional.
        local toon = me_name()
        if toon and CHB.state.toons[toon] then
            CHB.state.toons[toon] = { modules = {} }
            CHB.save_state()
        end
        for _, name in ipairs(CHB.order) do
            CHB.load_settings(name)
            pcall(function() CHB.hard_reset(name) end)
        end
        log_info('resetall: wiped saved overrides for ' .. tostring(toon) .. ' — all modules at defaults now.')
        return
    end
    if cmd == 'chat' then
        -- v4.7.12: chat subcommand — currently only `r` (reply).
        --   //cb chat r "message"   -> /tell to the last toon that /tell'd YOU
        local sub2 = (args[1] or ''):lower()
        if sub2 == 'r' or sub2 == 'reply' then
            local target = CHB.cht_last_tell_from
            if not target then
                log_info('chat r: no incoming tell to reply to yet.'); return
            end
            local rest_msg = table.concat({ select(2, unpack(args)) }, ' ')
            -- strip surrounding quotes if the user wrapped the message
            rest_msg = rest_msg:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
            if rest_msg == '' then
                log_info('usage: //cb chat r "your message here"'); return
            end
            windower.send_command('input /tell ' .. target .. ' ' .. rest_msg)
            log_info(('chat r: replied to %s'):format(target))
            return
        end
        log_info('chat subcommands: r "message"   (reply to last incoming tell)')
        return
    end
    if cmd == 'log' then
        -- v4.7.10: read tail of the debug log so you can see recent events
        -- without leaving the game.
        local n = tonumber(args[1]) or 15
        if not CHB.debug_log_file then
            pcall(function() CHB.debug_log_file = files.new('data/chharbar.log', true) end)
        end
        if not CHB.debug_log_file then log_info('log: no debug log file yet.'); return end
        local content
        pcall(function() content = CHB.debug_log_file:read() end)
        if not content or content == '' then log_info('log: (empty)'); return end
        local lines = {}
        for line in content:gmatch('[^\n]+') do lines[#lines + 1] = line end
        local start_i = math.max(1, #lines - n + 1)
        log_info(('log: showing last %d of %d lines from data/chharbar.log:'):format(#lines - start_i + 1, #lines))
        for i = start_i, #lines do log_info('  ' .. lines[i]) end
        return
    end
    if cmd == 'border' then
        -- v4.7.9: toggle the gold border companion widgets globally. OFF
        -- by default for perf (each border is a second text widget that
        -- doubles the render pipeline). Reload chharbar after toggling
        -- to rebuild widgets with the new setting.
        local a = (args[1] or ''):lower()
        if a == 'on' then CHB.border_enabled = true
        elseif a == 'off' then CHB.border_enabled = false
        else CHB.border_enabled = not CHB.border_enabled end
        log_info('border -> ' .. (CHB.border_enabled and 'ON' or 'OFF') .. '  (reload chharbar for it to take effect)')
        return
    end
    if cmd == 'showall' then
        -- v4.7.7: force-enable every registered module for the current toon,
        -- ignoring any saved enabled=false state. Use this to start fresh
        -- from full-visible, then //cb <mod> off + //cb save to lock your layout.
        local n = 0
        for _, name in ipairs(CHB.order) do
            local mod = CHB.modules[name]
            if mod and mod.settings then
                mod.settings.enabled = true
                CHB.save_settings(name)
                pcall(function() CHB.hard_reset(name) end)
                n = n + 1
            end
        end
        log_info('showall: ' .. n .. ' modules forced ON and saved. Hide the ones you dont want + //cb save.')
        return
    end
    if cmd == 'hideall' then
        -- v4.7.7: complement — turn everything off in one shot. Useful for
        -- a clean slate before manually enabling what you want.
        local n = 0
        for _, name in ipairs(CHB.order) do
            local mod = CHB.modules[name]
            if mod and mod.settings then
                mod.settings.enabled = false
                CHB.save_settings(name)
                if mod.on_destroy then pcall(function() mod:on_destroy() end) end
                n = n + 1
            end
        end
        log_info('hideall: ' .. n .. ' modules forced OFF and saved.')
        return
    end
    if cmd == 'nohide' or cmd == 'nh' then
        -- v3.3.0: bypass all auto-hide logic. Use when the keyboard poll
        -- returns stuck Ctrl/Alt (e.g. JoyToKey trigger threshold too low).
        local a = (args[1] or ''):lower()
        if a == 'on' then CHB.nohide = true
        elseif a == 'off' then CHB.nohide = false
        else CHB.nohide = not CHB.nohide end
        log_info('nohide -> ' .. (CHB.nohide and 'ON (auto-hide disabled)' or 'OFF'))
        return
    end
    if cmd == 'hidedump' or cmd == 'hd' then
        -- v3.2.1: show every branch of the hide check + live keyboard poll.
        local hide, reason = CHB.hide_reason()
        local pc, pa = _poll_ctrl_alt()
        local info; pcall(function() info = windower.ffxi.get_info() end)
        local menu_str = ''; pcall(function() menu_str = windower.ffxi.get_menu_string() or '' end)
        local p; pcall(function() p = windower.ffxi.get_player() end)
        log_info(string.format('hidedump: hide=%s reason=%s', tostring(hide), reason))
        log_info(string.format('  ctrl_held=%s alt_held=%s (poll: ctrl=%s alt=%s)',
            tostring(CHB.ctrl_held), tostring(CHB.alt_held),
            tostring(pc), tostring(pa)))
        log_info(string.format('  chat_open=%s mog=%s moghouse=%s menu_id=%s',
            tostring(info and info.chat_open),
            tostring(info and info.mog_menu),
            tostring(info and info.mog_house_menu),
            tostring(info and info.menu_id)))
        log_info(string.format('  menu_str=%q player.status=%s',
            menu_str, tostring(p and p.status)))
        return
    end
    if cmd == 'reload' or cmd == 'reset' then
        local n = args[1]
        if n and CHB.modules[n] then CHB.hard_reset(n); log_info('reloaded ' .. n)
        else log_info('reload: no such module: ' .. tostring(n)) end
        return
    end
    -- Otherwise treat cmd as a module name.
    if CHB.modules[cmd] then
        local sub = (args[1] or ''):lower()
        local mod_rest = table.concat({ select(2, unpack(args)) }, ' ')
        if _module_generic(cmd, sub, mod_rest) then return end
        -- Module-specific handler as fallback.
        local mod = CHB.modules[cmd]
        if mod.on_command then
            pcall(function() mod:on_command(sub, mod_rest) end)
            return
        end
        log_info(cmd .. ': unknown subcommand: ' .. sub)
        return
    end
    -- v4.6.2: a handful of commands are handled by separate 'addon command'
    -- event handlers (autotarget/sil/gs). Windower fires every registered
    -- handler in turn, so the OTHER handler will service the command. Skip
    -- the "unknown command" log for those, otherwise the user sees:
    --   chharbar: unknown command: autotarget
    --   chharbar: autotarget: token=tid       <-- worked anyway
    if CHB.external_cmds and CHB.external_cmds[cmd] then return end
    log_info('unknown command: ' .. cmd .. ' (try //cb help)')
end)

-- v4.6.2: commands handled by separate handlers. Extend as we add more.
CHB.external_cmds = {
    autotarget = true,
    sil        = true,
    gs         = true,
    chat       = true,   -- v4.7.12
    log        = true,   -- v4.7.10
}

-- ============================================================================
-- AUTO-HIDE — opt-in per module.
--
-- Returns true when a non-combat menu is up (chat / Escape / mog house /
-- NPC dialog / macro palette). Returns false during combat menus (Attack,
-- Magic, Ability, Ranged, WS, Trigger, Pet, Jobability) — those let combat
-- HUDs stay visible.
--
-- Modules opt in by checking CHB.should_auto_hide() in their on_tick and
-- calling CHB.hide_widget() when true. This is a pure query — no shared
-- state to get stuck.
-- ============================================================================
CHB.ctrl_held    = false
CHB.alt_held     = false
CHB.ctrl_ts      = 0
CHB.alt_ts       = 0
CHB.manual_hide  = false   -- //cb forcehide on/off/toggle sets this
-- v4.0.1: nohide DEFAULTS to true because JoyToKey trigger bleed emits
-- Ctrl/Alt continuously for gamepad users, making auto-hide fire nonstop.
-- nohide=true still hides on MENUS/ZONING/CUTSCENE/MOG — it only skips
-- the keyboard-held detection. `//cb nohide off` re-enables strict hide.
CHB.nohide       = true
CHB.edit_mode    = false   -- v3.6.0: //cb edit on shows ◢ resize handles
CHB.mouse_dbg    = false   -- v3.6.2: //cb mousedbg toggles per-click console log
CHB.dirty        = false   -- v3.6.0: settings changed since last state file write
CHB.autosave_at  = 0       -- os.clock() of next scheduled autosave
CHB.mouse        = {       -- v3.6.0/3.6.1: drag-move + corner-resize state
    -- resize state
    resize_mod        = nil,
    resize_start_size = 0,
    resize_start_y    = 0,
    resize_start_x    = 0,
    -- drag-move state (v3.6.1)
    drag_mod          = nil,
    drag_start_x      = 0,
    drag_start_y      = 0,
    drag_start_pos_x  = 0,
    drag_start_pos_y  = 0,
}

local COMBAT_PREFIXES = {
    'attack', 'magic', 'ability', 'ranged', 'weapon',
    'trigger', 'pet', 'jobability', 'weaponskill',
}
local function _menu_is_combat(s)
    if not s or s == '' then return false end
    local low = tostring(s):lower():gsub('^%s+', ''):gsub('%s+$', '')
    for _, p in ipairs(COMBAT_PREFIXES) do
        if low:sub(1, #p) == p then return true end
    end
    return false
end

-- Poll windower.get_key_state as a fallback for missed keyboard events
-- (some builds don't fire keyboard events reliably; also alt-tab focus loss).
-- Returns nil if the API isn't available on this Windower build.
local function _poll_ctrl_alt()
    local getkey = nil
    if type(windower.get_key_state) == 'function' then
        getkey = windower.get_key_state
    elseif windower.debug and type(windower.debug.get_key_state) == 'function' then
        getkey = windower.debug.get_key_state
    end
    if not getkey then return nil, nil end
    local ok_c1, c1 = pcall(getkey, 0x1D)
    local ok_c2, c2 = pcall(getkey, 0x9D)
    local ok_a1, a1 = pcall(getkey, 0x38)
    local ok_a2, a2 = pcall(getkey, 0xB8)
    local ctrl = (ok_c1 and c1) or (ok_c2 and c2) or false
    local alt  = (ok_a1 and a1) or (ok_a2 and a2) or false
    return ctrl and true or false, alt and true or false
end

-- Returns (hide_bool, reason_string). Reason lets diagnostics show WHY.
function CHB.hide_reason()
    -- v4.0.1: manual_hide always wins (this is the //cb forcehide toggle).
    if CHB.manual_hide then return true, 'manual_hide' end

    -- Keyboard-triggered hide (Ctrl/Alt = macro palette). ONLY consulted
    -- when nohide is OFF. This split lets a gamepad user with JoyToKey
    -- trigger bleed still get menu/zoning hide while ignoring the phantom
    -- Ctrl/Alt held state.
    if not CHB.nohide then
        local pc, pa = _poll_ctrl_alt()
        if pc ~= nil then CHB.ctrl_held = pc end
        if pa ~= nil then CHB.alt_held  = pa end
        local now = os.clock()
        if CHB.ctrl_held and pc == nil and (now - CHB.ctrl_ts) > 1.5 then CHB.ctrl_held = false end
        if CHB.alt_held  and pa == nil and (now - CHB.alt_ts)  > 1.5 then CHB.alt_held  = false end
        if CHB.ctrl_held then return true, 'ctrl_held' end
        if CHB.alt_held  then return true, 'alt_held'  end
    end

    local info
    pcall(function() info = windower.ffxi.get_info() end)
    if info then
        if info.chat_open      then return true, 'chat_open' end
        if info.mog_menu       then return true, 'mog_menu'  end
        if info.mog_house_menu then return true, 'mog_house_menu' end
    end

    -- Cutscene
    local ok_p, p = pcall(function() return windower.ffxi.get_player() end)
    if ok_p and p then
        local ps = tonumber(p.status) or 0
        if ps == 4 or ps == 44 then return true, 'cutscene_status=' .. ps end
    end

    -- Menu-string dispatch — non-combat menus hide.
    local menu_str = ''
    pcall(function()
        if windower.ffxi.get_menu_string then
            menu_str = windower.ffxi.get_menu_string() or ''
        end
    end)
    if menu_str ~= '' and not _menu_is_combat(menu_str) then
        return true, 'menu_str=' .. menu_str
    end

    -- v4.0.2: menu_id fallback for menus that don't set menu_str (Escape,
    -- Item, Equip, Status, etc.). To keep combat sub-menus visible, we
    -- only trip this when player status != 1 (i.e., NOT engaged). Combat
    -- sub-menus only appear while engaged, so status is a clean split.
    if info and info.menu_id and tonumber(info.menu_id) and info.menu_id ~= 0 then
        local pstat = ok_p and p and tonumber(p.status) or 0
        if pstat ~= 1 then
            return true, 'menu_id=' .. tostring(info.menu_id) .. ' (idle)'
        end
    end

    return false, 'none'
end

-- v4.0.2: per-module strict-hide poll. Returns true if the KEYBOARD
-- macro-palette state should be considered (Ctrl/Alt held). Bypasses
-- CHB.nohide so a specific module can opt back into macro-palette hide
-- even when nohide is on globally. Vitals uses this by default.
function CHB.strict_kbd_hide()
    local pc, pa = _poll_ctrl_alt()
    if pc then return true, 'ctrl_held_strict' end
    if pa then return true, 'alt_held_strict'  end
    return false, nil
end

-- Legacy alias — modules still call should_auto_hide().
function CHB.should_auto_hide()
    return (CHB.hide_reason())
end

-- Keyboard event: track ctrl / alt held for macro-palette hide.
--   dik codes: 0x1D LCtrl, 0x9D RCtrl, 0x38 LAlt, 0xB8 RAlt
windower.register_event('keyboard', function(dik, pressed, flags, blocked)
    local down = pressed and pressed ~= 0 and true or false
    local now  = os.clock()
    if dik == 0x1D or dik == 0x9D then
        CHB.ctrl_held = down
        if down then CHB.ctrl_ts = now end
    elseif dik == 0x38 or dik == 0xB8 then
        CHB.alt_held = down
        if down then CHB.alt_ts = now end
    end
end)

-- ============================================================================
