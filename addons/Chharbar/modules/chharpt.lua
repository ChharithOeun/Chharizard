-- CHUNK 3: Party / Alliance 1 / Alliance 2 as three independent modules.
--
-- Each owns its own widget, its own position, its own on/off. Drag them
-- independently. Same helper renders each member row.
-- ============================================================================

local PT_MEMBER_NAME_W = 12   -- fixed-width name column for alignment

local function _pad_name(nm, w)
    w = w or PT_MEMBER_NAME_W
    local s = tostring(nm or ''):sub(1, w)
    if #s < w then s = s .. string.rep(' ', w - #s) end
    return s
end

local function _mp_color_ally(pct)
    if pct <= 24 then return '\\cs(160,100,220)'  end   -- purple
    if pct <= 50 then return '\\cs(200,180,255)'  end   -- lavender
    return NC.SUB                                       -- lavender (default MP)
end

local function _tp_color_ally(tp)
    if tp >= 3000 then return '\\cs(255,100, 90)' end
    if tp >= 2000 then return '\\cs(255,150, 80)' end
    if tp >= 1000 then return '\\cs(255,200,120)' end
    return '\\cs(255,235,120)'
end

-- Zone-different = zoning; row rendered dim.
local function _member_zoning(m)
    if not m then return false end
    local mz = tonumber(m.zone)
    if not mz or mz == 0 then return false end
    local ok, info = pcall(function() return windower.ffxi.get_info() end)
    if not ok or type(info) ~= 'table' then return false end
    return mz ~= (tonumber(info.zone) or 0)
end

-- v4.3.0: build a text cast-bar segment for a party member currently casting.
-- Returns nil when member isn't casting. Auto-clears stale entries too.
local function _pt_cast_segment_for(actor_id)
    local rec = CHB.cast_by_actor[actor_id]
    if not rec then return nil end
    local now = os.clock()
    local elapsed = now - rec.started_at
    local dur = rec.duration or 2
    if elapsed > dur + 1.0 then
        CHB.cast_by_actor[actor_id] = nil
        return nil
    end
    local pct = math.max(0, math.min(1, elapsed / dur))
    local remain = math.max(0, dur - elapsed)
    local w = 8
    local filled = math.floor(pct * w + 0.5)
    if filled > w then filled = w end
    local bar_color = (pct >= 0.9) and '\\cs(140,200,255)' or '\\cs(255,220,120)'
    return string.format(' %s%s%s %s%.1fs%s %s[%s%s]%s',
        '\\cs(255,255,255)', rec.spell_name or '?', NC.RESET,
        '\\cs(200,200,200)', remain, NC.RESET,
        bar_color, string.rep('█', filled) .. string.rep('░', w - filled), bar_color, NC.RESET)
end

-- Render one party member row. Compact single-line format:
--   Chharzilla    PLD99/BLU58   HP 100% MP 100% TP  0%   (0.0y)
local function _pt_render_member(m, is_self, bar_w)
    if not m or not m.name then return nil end
    local nm  = _pad_name(m.name, PT_MEMBER_NAME_W)
    local jobs = _resolve_target_jobs(m)
    -- v3.7.0: pad the JOB column to a fixed 12-char width (plain text
    -- length, not including colour codes) so HP always starts at the same
    -- column across members whether or not their job info is available.
    local job_plain
    if jobs and jobs.main_job and jobs.main_lvl and jobs.main_lvl > 0 then
        if jobs.sub_job and jobs.sub_lvl and jobs.sub_lvl > 0 then
            job_plain = string.format('%s%d/%s%d',
                jobs.main_job, jobs.main_lvl, jobs.sub_job, jobs.sub_lvl)
        else
            job_plain = string.format('%s%d', jobs.main_job, jobs.main_lvl)
        end
    else
        job_plain = ''
    end
    if #job_plain > 12 then job_plain = job_plain:sub(1, 12) end
    job_plain = job_plain .. string.rep(' ', 12 - #job_plain)
    local job_str = NC.DIM .. job_plain .. NC.RESET
    local hpp = tonumber(m.hpp) or 0
    local mpp = tonumber(m.mpp) or 0
    local tp  = tonumber(m.tp)  or 0
    local tp_pct = math.floor(tp / 10)
    local hp_c = _target_hp_color(hpp, true)
    local mp_c = _mp_color_ally(mpp)
    local tp_c = _tp_color_ally(tp)
    local w = tonumber(bar_w) or 5

    local function tinybar(pct, color)
        local f = math.floor(math.max(0, math.min(100, pct)) / 100 * w + 0.5)
        return color .. string.rep('█', f) .. string.rep('░', w - f) .. NC.RESET
    end

    local name_color = is_self and NC.SELF or NC.PARTY
    local marker = is_self and (NC.HEADER .. '>' .. NC.RESET .. ' ') or '  '

    -- Distance (only if member has a mob record)
    local dist = ''
    if m.mob and (m.mob.distance or m.mob.x) then
        local d, _ = _dist_to('me')  -- placeholder path
        if m.mob.distance then
            d = math.sqrt(tonumber(m.mob.distance) or 0)
            dist = string.format(' %s(%.1fy)%s', NC.DIM, d, NC.RESET)
        end
    end

    local row = string.format('%s%s%s%s  %s  %sHP%3d%%%s [%s] %sMP%3d%%%s [%s] %sTP%3d%%%s [%s]%s',
        marker,
        name_color, nm, NC.RESET,
        job_str,
        hp_c, hpp, NC.RESET, tinybar(hpp, hp_c),
        mp_c, mpp, NC.RESET, tinybar(mpp, mp_c),
        tp_c, tp_pct, NC.RESET, tinybar(math.min(100, tp / 30), tp_c),
        dist)

    -- v4.3.0: append per-member cast bar overlay if this member is currently
    -- casting. Uses their mob.id to look up cast tracking.
    if m.mob and m.mob.id then
        local seg = _pt_cast_segment_for(m.mob.id)
        if seg then row = row .. seg end
    end

    -- Dim entire row while member is out of zone.
    if _member_zoning(m) then
        row = '\\cs(80,80,80)' .. row:gsub('\\cs%b()', ''):gsub('\\cr', '') .. NC.RESET
    end
    return row
end

-- Factory for a party-list module. Each of Party/Alliance1/Alliance2 is
-- an instance made by this. They only differ in `keys` (which party
-- slots to iterate) and default position.
local function _make_pt_module(name, keys, default_pos)
    local M = {}
    M.name = name
    M.default = {
        enabled     = true,
        tick_frames = 15,     -- ~4 Hz
        pos_x       = default_pos.x,
        pos_y       = default_pos.y,
        font_size   = 10,
        opacity     = 240,    -- near-solid to cover default FFXI HUD
        bar_width   = 5,
        auto_hide   = true,
    }
    function M:on_create()
        self.widget = CHB.new_text_widget(self.settings)
    end
    function M:on_destroy()
        if self.widget then
            CHB.sync_drag_pos(self.widget, self)
            pcall(function() self.widget:destroy() end)
            self.widget = nil
        end
    end
    function M:on_tick()
        if not self.widget then return end
        CHB.sync_drag_pos(self.widget, self)
        if self.settings.auto_hide and CHB.should_auto_hide() then
            CHB.hide_widget(self.widget); return
        end
        local ok, party = pcall(function() return windower.ffxi.get_party() end)
        if not ok or type(party) ~= 'table' then
            CHB.hide_widget(self.widget); return
        end
        local me = windower.ffxi.get_player()
        local my_name = me and me.name or ''
        local lines = {}
        for _, k in ipairs(keys) do
            local m = party[k]
            if type(m) == 'table' and m.name then
                local row = _pt_render_member(m, m.name == my_name, self.settings.bar_width)
                if row then lines[#lines + 1] = row end
            end
        end
        if #lines == 0 then CHB.hide_widget(self.widget); return end
        CHB.render_text(self.widget, {
            text      = table.concat(lines, '\n'),
            pos_x     = self.settings.pos_x,
            pos_y     = self.settings.pos_y,
            font_size = self.settings.font_size,
            opacity   = self.settings.opacity,
        })
    end
    function M:on_dump()
        local ok, party = pcall(function() return windower.ffxi.get_party() end)
        local count = 0
        if ok and type(party) == 'table' then
            for _, k in ipairs(keys) do
                if type(party[k]) == 'table' and party[k].name then count = count + 1 end
            end
        end
        return {
            widget    = tostring(self.widget),
            members   = count,
            slots     = table.concat(keys, ','),
        }
    end
    function M:on_command(sub, rest)
        if sub == 'width' or sub == 'bar' then
            local n = tonumber(rest)
            if not n then log_info('usage: //cb ' .. name .. ' width <2..10>'); return end
            n = math.max(2, math.min(10, n))
            self.settings.bar_width = n
            CHB.save_settings(name); CHB.hard_reset(name)
            log_info(name .. ': bar_width=' .. n); return
        end
        log_info(name .. ' subcommands: width <n>  (generic: on/off/toggle/pos/size/opacity)')
    end
    return M
end

CHB.register(_make_pt_module('party',      { 'p0', 'p1', 'p2', 'p3', 'p4', 'p5' },     { x = 1200, y =  40 }))
CHB.register(_make_pt_module('alliance1',  { 'a10', 'a11', 'a12', 'a13', 'a14', 'a15' }, { x = 1200, y = 220 }))
CHB.register(_make_pt_module('alliance2',  { 'a20', 'a21', 'a22', 'a23', 'a24', 'a25' }, { x = 1200, y = 400 }))

-- ============================================================================
