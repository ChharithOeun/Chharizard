-- CHUNK 6: scoreboard — real DPS tracker.
--
-- Sums damage dealt per party PC by parsing incoming action packets. A
-- "fight window" starts on the first damaging hit and auto-clears after
-- 30s with no activity, so between fights the board resets itself.
--
-- Design:
--   * Damage attribution by actor_id -> PC name via get_mob_by_id().
--   * Only party members are counted (self + p1..p5). Mob damage ignored.
--   * Categories that deal damage: 1 melee, 2 ranged finish, 3 WS finish,
--     4 spell finish, 9 pet ability finish, 13 pet WS. Everything else
--     (JAs, items, songs, geo) is skipped in v1 to avoid mis-attributing
--     cures. We'll widen this in v3.5.1 once we have real fight data.
--   * Messages that are NOT damage (cures, resists, misses, absorbs) are
--     filtered out via MSG_NOT_DAMAGE below.
--   * Additional effects (samba, en-spells, spikes, WS add-effects) are
--     summed from action.add_effect and attributed to the SAME actor.
--
-- Default: DISABLED. Turn on with `//cb scoreboard on`.
-- ============================================================================

-- v4.7.9: scoreboard is now keyed BY MOB (same fix hate got in v4.0.1),
-- so switching targets or killing one mob doesn't leave stale numbers
-- from the previous fight glued to your new target. Also cleared on
-- 0x029 death msgs and on zone changes.
CHB.sb = {
    by_mob       = {},    -- [mob_id] = { dmg = {[name]=n}, hits = {[name]=n}, start, last_hit }
    current_mob  = nil,   -- mob_id we're currently displaying stats for
}

local SB_DMG_CATEGORIES = {
    [1]=true,   -- melee
    [2]=true,   -- ranged finish
    [3]=true,   -- WS finish
    [4]=true,   -- spell finish
    [9]=true,   -- pet ability finish
    [13]=true,  -- pet WS
}

-- Messages that must NOT be counted as damage. Covers heals, resists,
-- misses, absorbs, drains-to-self, no-effect. Extend as we notice noise.
-- v4.7.9: expanded to include buff/enhance/wear messages so casting
-- Protect/Shell/Refresh on a party member no longer registers as damage.
local MSG_NOT_DAMAGE = {
    [2]   = true,  -- no effect
    [3]   = true,  -- recovers HP
    [5]   = true,  -- HP recovered (variant)
    [7]   = true,  -- MP recovered
    [8]   = true,  -- cure - Poison
    [12]  = true,  -- HP restored while asleep
    [15]  = true,  -- physical miss
    [16]  = true,  -- physical miss / guarded
    [17]  = true,  -- physical evaded
    [20]  = true,  -- HP recovered / drain to self
    [30]  = true,  -- shadow absorbed
    [31]  = true,  -- shadow absorbed
    [63]  = true,  -- spell resist / has no effect
    [79]  = true,  -- spell fully resisted
    [106] = true,  -- spell reflected
    [108] = true,  -- spell absorbed
    [165] = true,  -- spell casting interrupted
    [166] = true,  -- unable to cast
    [188] = true,  -- add effect - resist
    [204] = true,  -- effect wears off
    [206] = true,  -- absorbed by ...
    [230] = true,  -- gains the effect of (buff cast)
    [231] = true,  -- gains the effect (variant)
    [233] = true,  -- gains buff
    [259] = true,  -- spell cure - recovers HP
    [263] = true,  -- buff gained
    [268] = true,  -- add effect - HP drain (heals actor, not damage to us)
    [271] = true,  -- effect wears (enfeeble land msg — landing != damage)
    [282] = true,  -- shadow absorbed
    [283] = true,  -- shadow absorbed
    [317] = true,  -- ranged miss (some builds)
    [355] = true,  -- resist
    [419] = true,  -- gain protect
    [420] = true,  -- gain shell
    [423] = true,  -- gain barfire etc.
}

local function _sb_actor_name(actor_id)
    if not actor_id or actor_id == 0 then return nil end
    local ok, m = pcall(function() return windower.ffxi.get_mob_by_id(actor_id) end)
    if not ok or not m or not m.name then return nil end
    return m.name
end

local function _sb_is_party_member(name)
    if not name then return false end
    local ok, party = pcall(function() return windower.ffxi.get_party() end)
    if not ok or type(party) ~= 'table' then return false end
    for k, m in pairs(party) do
        if type(m) == 'table' and m.name == name then
            -- Only main party (p0-p5), not alliance1/2. Change to include all
            -- alliance later if the user wants raid-wide DPS.
            if k == 'p0' or k == 'p1' or k == 'p2' or k == 'p3' or k == 'p4' or k == 'p5' then
                return true
            end
        end
    end
    return false
end

-- v4.7.9: per-mob damage tracking. Damage attributed to (mob_id, actor)
-- so switching between mobs, or one dying while another lives, doesn't
-- leave stale totals on your new target's readout.
local function _sb_ensure_mob(mob_id)
    local m = CHB.sb.by_mob[mob_id]
    if not m then
        m = { dmg = {}, hits = {}, start = os.clock(), last_hit = os.clock() }
        CHB.sb.by_mob[mob_id] = m
    end
    return m
end

local function _sb_add_damage(mob_id, name, amount)
    if not mob_id or mob_id == 0 or not name or type(amount) ~= 'number' or amount <= 0 then return end
    local m = _sb_ensure_mob(mob_id)
    m.dmg[name]  = (m.dmg[name]  or 0) + amount
    m.hits[name] = (m.hits[name] or 0) + 1
    m.last_hit   = os.clock()
end

-- Filter out non-hostile targets (party members, self) so buffs and heals
-- don't accidentally register even if they slip past the message filter.
local function _sb_is_hostile(mob_id)
    if not mob_id or mob_id == 0 then return false end
    local ok, tm = pcall(function() return windower.ffxi.get_mob_by_id(mob_id) end)
    if not ok or not tm then return false end
    if tm.is_pc then return false end
    -- spawn_type: 16 typically hostile mob; also accept anything not npc/pc.
    if tm.is_npc then return false end
    return true
end

windower.register_event('action', function(a)
    if not a or type(a) ~= 'table' then return end
    if not SB_DMG_CATEGORIES[a.category] then return end
    local name = _sb_actor_name(a.actor_id)
    if not name or not _sb_is_party_member(name) then return end
    if type(a.targets) ~= 'table' then return end

    for _, t in pairs(a.targets) do
        local tid = tonumber(t.id) or 0
        -- v4.7.9: only count damage against hostile mobs. Filters out
        -- buff/heal/cover spells cast on party members that were
        -- inflating the DPS.
        if tid ~= 0 and _sb_is_hostile(tid) and type(t.actions) == 'table' then
            for _, act in pairs(t.actions) do
                local msg   = tonumber(act.message) or 0
                local param = tonumber(act.param)   or 0
                if not MSG_NOT_DAMAGE[msg] and param > 0 then
                    _sb_add_damage(tid, name, param)
                end
                -- Add effects (samba, spikes, en-spells, WS add-effects)
                if type(act.add_effect) == 'table' then
                    for _, ae in pairs(act.add_effect) do
                        local aemsg   = tonumber(ae.message) or 0
                        local aeparam = tonumber(ae.param)   or 0
                        if not MSG_NOT_DAMAGE[aemsg] and aeparam > 0 then
                            _sb_add_damage(tid, name, aeparam)
                        end
                    end
                end
            end
        end
    end
end)

-- v4.7.9: clear a mob's tally when it dies. Same 0x029 death msg set the
-- hate + debuffed modules use.
local SB_MSG_DEATH = { [6]=true, [20]=true, [113]=true, [406]=true, [605]=true, [646]=true }
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x029 then return end
    pcall(function()
        local target_id  = data:unpack('I', 0x09)
        local message_id = data:unpack('H', 0x19) % 32768
        if SB_MSG_DEATH[message_id] then
            CHB.sb.by_mob[target_id] = nil
            if CHB.sb.current_mob == target_id then CHB.sb.current_mob = nil end
        end
    end)
end)

-- v4.7.9: wipe scoreboard on zone change so cross-zone stragglers don't
-- linger. Also nuke hate + wsc + debuffed state (they all key on mob ids
-- that no longer exist after zone).
windower.register_event('zone change', function()
    CHB.sb.by_mob = {}
    CHB.sb.current_mob = nil
    if CHB.hate_events then CHB.hate_events = {}; CHB.hate_mob_seen = {} end
    if CHB.debuffed_mobs then CHB.debuffed_mobs = {} end
    if CHB.wsc_state then CHB.wsc_state.last_by_mob = {}; CHB.wsc_state.active = {} end
    if CHB.mob_dbf then CHB.mob_dbf = {} end
end)

local Scoreboard = {}
Scoreboard.name = 'scoreboard'
Scoreboard.default = {
    enabled     = true,      -- v4.7.7: everything on by default; user hides + saves what they don't want
    tick_frames = 30,        -- ~2 Hz — DPS numbers don't need to fly
    pos_x       = 1200,
    pos_y       = 620,
    font_size   = 10,
    opacity     = 220,
    bar_width   = 14,
    max_rows    = 6,
    reset_after = 30,        -- seconds of no damage before auto-reset
    auto_hide   = false,
}

local COL_SB_HEAD = '\\cs(240,240,240)'
local COL_SB_TOP  = '\\cs(255,220,120)'   -- top damage — warm yellow
local COL_SB_MID  = '\\cs(220,220,220)'   -- middle rank — off-white
local COL_SB_LOW  = '\\cs(160,160,160)'   -- lower rank — grey
local COL_SB_BAR  = '\\cs(255,180, 90)'
local COL_SB_RST  = '\\cr'

local function _sb_rank_color(idx)
    if idx == 1 then return COL_SB_TOP end
    if idx <= 3 then return COL_SB_MID end
    return COL_SB_LOW
end

local function _sb_bar(pct, width)
    local w = tonumber(width) or 14
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local filled = math.floor(pct * w + 0.5)
    if filled > w then filled = w end
    return COL_SB_BAR .. string.rep('█', filled) .. string.rep('░', w - filled) .. COL_SB_RST
end

-- v4.7.9: sorted rows for a specific mob's per-actor damage.
local function _sb_sorted_rows_for(mob_id)
    local rows = {}
    local m = mob_id and CHB.sb.by_mob[mob_id]
    if not m then return rows end
    for name, dmg in pairs(m.dmg) do
        rows[#rows + 1] = { name = name, dmg = dmg, hits = m.hits[name] or 0 }
    end
    table.sort(rows, function(a, b) return a.dmg > b.dmg end)
    return rows
end

-- Return (mob_id, mob) for the mob we should show — current battle target
-- if we have data on it, else the most-recently-hit mob still tracked.
local function _sb_current_mob_id()
    local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
    if bt and bt.id and CHB.sb.by_mob[bt.id] then return bt.id end
    -- fallback: latest tracked mob
    local best, best_ts = nil, 0
    for mid, m in pairs(CHB.sb.by_mob) do
        if m.last_hit > best_ts then best, best_ts = mid, m.last_hit end
    end
    return best
end

local function _sb_reset()
    CHB.sb.by_mob = {}
    CHB.sb.current_mob = nil
end

function Scoreboard:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function Scoreboard:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function Scoreboard:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    -- v4.7.9: pick which mob to show. Also prune mobs untouched for >90s
    -- so long-idle entries don't accumulate.
    local now = os.clock()
    for mid, m in pairs(CHB.sb.by_mob) do
        if (now - m.last_hit) > 90 then CHB.sb.by_mob[mid] = nil end
    end
    local mob_id = _sb_current_mob_id()
    if not mob_id then
        CHB.hide_widget(self.widget); return
    end
    local mob_stats = CHB.sb.by_mob[mob_id]
    local rows = _sb_sorted_rows_for(mob_id)
    if #rows == 0 then
        CHB.hide_widget(self.widget); return
    end

    local top_dmg = rows[1].dmg
    local elapsed = math.max(1, (mob_stats.last_hit - mob_stats.start))
    local max_rows = self.settings.max_rows or 6
    local mob_name = 'mob'
    pcall(function()
        local mm = windower.ffxi.get_mob_by_id(mob_id)
        if mm and mm.name then mob_name = mm.name end
    end)

    local lines = { COL_SB_HEAD .. string.format('DPS: %s (%.0fs)', mob_name, elapsed) .. COL_SB_RST }
    for i, r in ipairs(rows) do
        if i > max_rows then break end
        local pct = (top_dmg > 0) and (r.dmg / top_dmg) or 0
        local dps = elapsed > 0 and (r.dmg / elapsed) or 0
        local color = _sb_rank_color(i)
        lines[#lines + 1] = string.format('%s%d. %-10s %6d  %5.0f%s %s',
            color, i, r.name:sub(1, 10), r.dmg, dps, COL_SB_RST,
            _sb_bar(pct, self.settings.bar_width))
    end

    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Scoreboard:on_dump()
    local mob_id = _sb_current_mob_id()
    local rows = _sb_sorted_rows_for(mob_id)
    local pieces = {}
    for i, r in ipairs(rows) do
        pieces[i] = string.format('%s=%d(%d)', r.name, r.dmg, r.hits)
        if i >= 8 then break end
    end
    local tracked = 0
    for _ in pairs(CHB.sb.by_mob) do tracked = tracked + 1 end
    return {
        widget       = tostring(self.widget),
        showing_mob  = tostring(mob_id),
        actors       = #rows,
        tracked_mobs = tracked,
        top          = table.concat(pieces, ', '),
    }
end

function Scoreboard:on_command(sub, rest)
    if sub == 'reset' or sub == 'clear' then
        _sb_reset()
        CHB.hard_reset('scoreboard')
        log_info('scoreboard: reset.'); return
    end
    if sub == 'print' or sub == 'p' then
        -- Send top-N for current-target mob to party chat.
        local mob_id = _sb_current_mob_id()
        if not mob_id then log_info('scoreboard: nothing to print.'); return end
        local rows = _sb_sorted_rows_for(mob_id)
        local m = CHB.sb.by_mob[mob_id]
        if #rows == 0 or not m then log_info('scoreboard: nothing to print.'); return end
        local elapsed = math.max(1, (m.last_hit - m.start))
        local n = math.min(#rows, self.settings.max_rows or 6)
        local mob_name = 'mob'
        pcall(function()
            local mm = windower.ffxi.get_mob_by_id(mob_id)
            if mm and mm.name then mob_name = mm.name end
        end)
        windower.send_command(string.format('input /p [Chharbar] DPS on %s (%.0fs):', mob_name, elapsed))
        for i = 1, n do
            local r = rows[i]
            local dps = elapsed > 0 and (r.dmg / elapsed) or 0
            windower.send_command(string.format('input /p %d. %s %d (%.0f dps)',
                i, r.name, r.dmg, dps))
        end
        log_info('scoreboard: printed ' .. n .. ' rows to /p.'); return
    end
    if sub == 'width' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb scoreboard width <6..30>'); return end
        n = math.max(6, math.min(30, math.floor(n)))
        self.settings.bar_width = n
        CHB.save_settings('scoreboard'); CHB.hard_reset('scoreboard')
        log_info('scoreboard: bar_width=' .. n); return
    end
    if sub == 'rows' or sub == 'max' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb scoreboard rows <1..12>'); return end
        n = math.max(1, math.min(12, math.floor(n)))
        self.settings.max_rows = n
        CHB.save_settings('scoreboard'); CHB.hard_reset('scoreboard')
        log_info('scoreboard: max_rows=' .. n); return
    end
    if sub == 'test' then
        _sb_reset()
        local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
        local mob_id = (bt and bt.id) or 99999
        local m = _sb_ensure_mob(mob_id)
        m.dmg.Chharizard  = 45230
        m.dmg.Chharlotte  = 28901
        m.dmg.Chharutaru  = 21344
        m.dmg.Chharzilla  = 17812
        m.dmg.Chhardonnay = 12055
        m.dmg.Chharity    =  9902
        for k,_ in pairs(m.dmg) do m.hits[k] = math.random(20, 60) end
        m.start    = os.clock() - 60
        m.last_hit = os.clock()
        log_info('scoreboard: test data pushed onto mob_id=' .. mob_id); return
    end
    log_info('scoreboard subcommands: on/off/toggle | reset | print | width <n> | rows <n> | test')
end

CHB.register(Scoreboard)

-- ============================================================================
