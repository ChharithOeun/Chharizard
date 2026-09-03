-- CHUNK 8: hate — aggro/hate proxy meter with MT/OT + spike detection.
--
-- FFXI hides real enmity values from the client except via the Enmity
-- Windower plugin (memory reads). Rather than depend on that plugin, we
-- build a PROXY hate model from action-packet observation:
--   * Damage dealt to the current battle target = major hate signal.
--   * Healing done on party members while target is engaged = tank/support
--     hate signal (cures generate real enmity in FFXI).
--   * All events time-stamped; hate = sum of weights inside the rolling
--     window (default 30s). Recent events dominate — this matches how
--     real enmity fades over time (CE decays slowly, VE quickly).
--
-- Ranking:
--   MT = highest current hate (yellow crown ★).
--   OT = second highest (orange ▲).
--   Rest = plain.
--
-- Spike detection:
--   For each PC, sum weights within the last 3s. If that sub-window
--   accounts for > SPIKE_THRESHOLD of the current MT's total hate, we
--   flag with a red '!' — warning that this PC just took a big chunk
--   of hate (likely a WS or nuke). Useful for tanks to re-provoke and
--   for DPS to hold back briefly.
--
-- Default OFF. Turn on with //cb hate on.
-- ============================================================================

-- v4.0.1: Hate tracker is now keyed BY MOB, not just actor. That way when
-- you kill mob A and pull mob B, mob A's hate table isn't still on screen
-- claiming somebody has 100% hate on a dead thing.
--
-- Data model:
--   CHB.hate_events[mob_id][actor_id] = { {ts, w}, ... }
--   CHB.hate_names[actor_id]          = 'PC name'
--   CHB.hate_mob_seen[mob_id]         = os.clock() of last event
--
-- Display filters to current battle target (bt) only. Mob death (0x029
-- death messages, borrowed from Xathe's Debuffed pattern) clears that
-- mob's whole entry immediately. Prune loop drops any mob not touched
-- in >90s.
CHB.hate_events   = {}
CHB.hate_names    = {}
CHB.hate_mob_seen = {}

local HATE_WINDOW           = 30      -- rolling window seconds per fight
local HATE_SPIKE_WINDOW     = 3
local HATE_SPIKE_THRESHOLD  = 0.30    -- 3s spike >30% of MT total = flag
local HATE_MOB_TTL          = 90      -- prune mob if no events for this long

-- v4.7.1: enmity table for spells + job abilities that generate hate WITHOUT
-- damage. Weights are in the same "damage-equivalent" units the rest of the
-- proxy uses — approximate, tuned so Flash > Provoke > Sentinel > cures.
-- Add more as you notice a specific action being under-counted.
local HATE_ENMITY_ACTIONS = {
    -- Job abilities (JAs) — category 6 in action packets
    ['Provoke']         = 1800,
    ['Warcry']          =  600,
    ['Sentinel']        = 1000,
    ['Rampart']         =  800,
    ['Shield Bash']     =  400,
    ['Weapon Bash']     =  200,
    ['Souleater']       =  200,
    ['Berserk']         =  100,
    ['Aggressor']       =  100,
    ['Elemental Seal']  =  100,
    ['Nether Void']     =  300,
    ['Cover']           =  200,
    ['Sengikori']       =  200,
    ['Hasso']           =    0,
    -- Spells — category 4
    ['Flash']           = 2000,   -- 320 CE + 1800 VE, biggest hate move in game
    ['Dia']             =  300,   ['Dia II']  = 400,   ['Dia III']  = 500,
    ['Bio']             =  200,   ['Bio II']  = 300,   ['Bio III']  = 400,
    ['Slow']            =  200,   ['Slow II'] = 250,
    ['Paralyze']        =  200,   ['Paralyze II'] = 250,
    ['Blind']           =  200,   ['Blind II'] = 250,
    ['Silence']         =  200,
    ['Sleep']           =  200,   ['Sleep II'] = 250,
    ['Poison']          =  150,   ['Poison II'] = 200,
    ['Bind']            =  200,
    ['Gravity']         =  200,
    ['Break']           =  200,
    ['Repose']          =  200,
    ['Frazzle']         =  200,   ['Frazzle II'] = 220,   ['Frazzle III'] = 250,
    ['Distract']        =  200,   ['Distract II'] = 220,  ['Distract III'] = 250,
    ['Addle']           =  200,   ['Addle II'] = 220,
    ['Utsusemi: Ichi']  =  100,
    ['Utsusemi: Ni']    =  150,
    -- Cures — tier scaled (targeting party member = hate on bt)
    ['Cure']            =   60,
    ['Cure II']         =  150,
    ['Cure III']        =  300,
    ['Cure IV']         =  500,
    ['Cure V']          =  700,
    ['Cure VI']         =  900,
    ['Curaga']          =  200,
    ['Curaga II']       =  350,
    ['Curaga III']      =  500,
    -- Buffs (small hate, target = party)
    ['Refresh']         =  100,   ['Refresh II'] = 130,   ['Refresh III'] = 160,
    ['Regen']           =   60,   ['Regen II'] =  80,     ['Regen III']  = 100,
    ['Haste']           =  100,   ['Haste II'] = 120,
    ['Protect']         =   50,   ['Protect II'] = 60,    ['Protect III'] = 70,
    ['Shell']           =   50,   ['Shell II'] = 60,      ['Shell III'] = 70,
}

local function _hate_actor_is_party(actor_id)
    if not actor_id or actor_id == 0 then return false, nil end
    local ok, party = pcall(function() return windower.ffxi.get_party() end)
    if not ok or type(party) ~= 'table' then return false, nil end
    for k, m in pairs(party) do
        if type(m) == 'table' and m.mob and m.mob.id == actor_id
                and (k == 'p0' or k == 'p1' or k == 'p2' or k == 'p3' or k == 'p4' or k == 'p5') then
            return true, m.name
        end
    end
    return false, nil
end

local function _hate_record(mob_id, actor_id, name, weight)
    if not mob_id or mob_id == 0 or not actor_id or weight <= 0 then return end
    CHB.hate_events[mob_id]  = CHB.hate_events[mob_id]  or {}
    CHB.hate_events[mob_id][actor_id] = CHB.hate_events[mob_id][actor_id] or {}
    CHB.hate_names[actor_id] = name or CHB.hate_names[actor_id]
    table.insert(CHB.hate_events[mob_id][actor_id], { ts = os.clock(), w = weight })
    CHB.hate_mob_seen[mob_id] = os.clock()
end

windower.register_event('action', function(a)
    if not a or type(a) ~= 'table' then return end
    -- v4.7.1: category 6 = JA finish (Provoke etc). Include it alongside
    -- damage cats + spells so non-damage enmity generators register.
    if not SB_DMG_CATEGORIES[a.category] and a.category ~= 4 and a.category ~= 6 then return end

    local is_party, name = _hate_actor_is_party(a.actor_id)
    if not is_party then return end

    -- Resolve the action name (spell/JA) for the enmity lookup.
    local action_name
    if a.category == 4 then
        local ok, sp = pcall(function() return res.spells[a.param] end)
        if ok and sp then action_name = sp.en end
    elseif a.category == 6 then
        local ok, ja = pcall(function() return res.job_abilities[a.param] end)
        if ok and ja then action_name = ja.en end
    end
    local enmity_weight = action_name and HATE_ENMITY_ACTIONS[action_name] or 0

    -- Bt for attributing "hate on the mob you're fighting" for buffs/heals
    -- whose target is a party member (not a mob).
    local bt_id
    pcall(function()
        local bt = windower.ffxi.get_mob_by_target('bt')
        if bt then bt_id = bt.id end
    end)

    for _, t in pairs(a.targets or {}) do
        local tid = tonumber(t.id) or 0
        if type(t.actions) == 'table' and tid ~= 0 then
            for _, act in pairs(t.actions) do
                local msg   = tonumber(act.message) or 0
                local param = tonumber(act.param)   or 0
                if not MSG_NOT_DAMAGE[msg] and param > 0 then
                    -- Damage attributed to (mob=t.id, actor=a.actor_id).
                    _hate_record(tid, a.actor_id, name, param)
                end
            end
        end
        -- v4.7.1: attach non-damage enmity from this action.
        -- If target is a party member (buff/cure), attribute to bt instead.
        if enmity_weight > 0 then
            local attribute_to = tid
            local is_pc_target = false
            pcall(function()
                local tm = windower.ffxi.get_mob_by_id(tid)
                if tm and tm.is_pc then is_pc_target = true end
            end)
            if is_pc_target or tid == 0 then attribute_to = bt_id or 0 end
            if attribute_to and attribute_to ~= 0 then
                _hate_record(attribute_to, a.actor_id, name, enmity_weight)
            end
        end
    end
end)

-- Clear a mob's hate table when it dies. Uses the same 0x029 death
-- message IDs Xathe's Debuffed uses (6, 20, 113, 406, 605, 646).
local HATE_MSG_DEATH = { [6]=true, [20]=true, [113]=true, [406]=true, [605]=true, [646]=true }
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x029 then return end
    pcall(function()
        local target_id  = data:unpack('I', 0x09)
        local message_id = data:unpack('H', 0x19) % 32768
        if HATE_MSG_DEATH[message_id] then
            CHB.hate_events[target_id]   = nil
            CHB.hate_mob_seen[target_id] = nil
        end
    end)
end)

-- Return sorted list [{ actor_id, name, total, spike }] for ONE mob within
-- the rolling window. Also prunes expired events + expired mobs.
local function _hate_ranked_for_mob(mob_id)
    local now = os.clock()

    -- Prune mobs entirely dormant beyond TTL.
    for mid, last in pairs(CHB.hate_mob_seen) do
        if (now - last) > HATE_MOB_TTL then
            CHB.hate_events[mid]   = nil
            CHB.hate_mob_seen[mid] = nil
        end
    end

    if not mob_id or not CHB.hate_events[mob_id] then return {} end
    local by_actor = CHB.hate_events[mob_id]
    local rows = {}
    for actor_id, events in pairs(by_actor) do
        local total, spike = 0, 0
        local kept = {}
        for _, e in ipairs(events) do
            local age = now - e.ts
            if age <= HATE_WINDOW then
                kept[#kept + 1] = e
                total = total + e.w
                if age <= HATE_SPIKE_WINDOW then spike = spike + e.w end
            end
        end
        by_actor[actor_id] = kept
        if total > 0 then
            rows[#rows + 1] = {
                actor_id = actor_id,
                name     = CHB.hate_names[actor_id] or ('id' .. actor_id),
                total    = total,
                spike    = spike,
            }
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)
    return rows
end

local Hate = {}
Hate.name = 'hate'
Hate.default = {
    enabled     = true,      -- v4.7.7: on by default; user hides + saves
    tick_frames = 15,        -- ~4 Hz — hate changes fast enough
    pos_x       = 20,
    pos_y       = 400,
    font_size   = 11,
    opacity     = 220,
    bar_width   = 16,
    max_rows    = 6,
    auto_hide   = false,
}

local COL_HATE_MT     = '\\cs(255,220, 90)'   -- yellow — MT crown
local COL_HATE_OT     = '\\cs(255,160, 90)'   -- orange — OT
local COL_HATE_REST   = '\\cs(220,220,220)'   -- off-white
local COL_HATE_SPIKE  = '\\cs(255,110,110)'   -- red — spike marker
local COL_HATE_BAR    = '\\cs(255,180, 90)'
local COL_HATE_HDR    = '\\cs(240,240,240)'
local COL_HATE_RST    = '\\cr'

local function _hate_bar(pct, width)
    local w = tonumber(width) or 16
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local filled = math.floor(pct * w + 0.5)
    if filled > w then filled = w end
    return COL_HATE_BAR .. string.rep('█', filled) .. string.rep('░', w - filled) .. COL_HATE_RST
end

function Hate:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function Hate:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function Hate:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    -- v4.0.1: rank hate ONLY for the current battle target. Kills the
    -- old stale-hate-on-dead-mob problem.
    local bt
    pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
    if not bt or not bt.id then
        CHB.hide_widget(self.widget); return
    end
    local rows = _hate_ranked_for_mob(bt.id)
    if #rows == 0 then
        CHB.hide_widget(self.widget); return
    end

    local top = rows[1].total
    local max_rows = self.settings.max_rows or 6
    local lines = { COL_HATE_HDR .. 'Hate: ' .. (bt.name or '?') .. COL_HATE_RST }

    for i, r in ipairs(rows) do
        if i > max_rows then break end
        local pct = (top > 0) and (r.total / top) or 0
        local rank_color = COL_HATE_REST
        local rank_mark  = '  '
        if i == 1 then rank_color = COL_HATE_MT; rank_mark = ('%s%s%s'):format(COL_HATE_MT, '\226\152\133 ', COL_HATE_RST)  -- ★
        elseif i == 2 then rank_color = COL_HATE_OT; rank_mark = ('%s%s%s'):format(COL_HATE_OT, '\226\150\178 ', COL_HATE_RST) -- ▲
        end
        local spike_pct = (top > 0) and (r.spike / top) or 0
        local spike_mark = ''
        if spike_pct > HATE_SPIKE_THRESHOLD then
            spike_mark = ' ' .. COL_HATE_SPIKE .. '!' .. COL_HATE_RST
        end
        lines[#lines + 1] = string.format('%s%s%-10s%s  %s %3d%%%s',
            rank_mark, rank_color, r.name:sub(1, 10), COL_HATE_RST,
            _hate_bar(pct, self.settings.bar_width),
            math.floor(pct * 100 + 0.5), spike_mark)
    end

    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Hate:on_dump()
    local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
    local rows = bt and bt.id and _hate_ranked_for_mob(bt.id) or {}
    local pieces = {}
    for i, r in ipairs(rows) do
        pieces[i] = string.format('%s=%d(spk %d)', r.name, r.total, r.spike)
        if i >= 8 then break end
    end
    local tracked_mobs = 0
    for _ in pairs(CHB.hate_events) do tracked_mobs = tracked_mobs + 1 end
    return {
        widget       = tostring(self.widget),
        bt_id        = bt and bt.id or 'nil',
        bt_name      = bt and bt.name or 'nil',
        actors       = #rows,
        top          = table.concat(pieces, ', '),
        tracked_mobs = tracked_mobs,
        window_s     = HATE_WINDOW,
        spike_s      = HATE_SPIKE_WINDOW,
    }
end

function Hate:on_command(sub, rest)
    if sub == 'reset' or sub == 'clear' then
        CHB.hate_events   = {}
        CHB.hate_mob_seen = {}
        log_info('hate: cleared all mobs.'); return
    end
    if sub == 'width' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb hate width <6..30>'); return end
        n = math.max(6, math.min(30, math.floor(n)))
        self.settings.bar_width = n
        CHB.save_settings('hate'); CHB.hard_reset('hate')
        log_info('hate: bar_width=' .. n); return
    end
    if sub == 'rows' or sub == 'max' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb hate rows <1..12>'); return end
        n = math.max(1, math.min(12, math.floor(n)))
        self.settings.max_rows = n
        CHB.save_settings('hate'); CHB.hard_reset('hate')
        log_info('hate: max_rows=' .. n); return
    end
    if sub == 'test' then
        -- v4.0.1: attach test hate to CURRENT battle target so the widget
        -- lights up right away. Without a bt, use a fake mob id so at
        -- least dev/dump shows something.
        local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
        local mob_id = (bt and bt.id) or 99999
        local now = os.clock()
        local function push(actor_id, name, ...)
            CHB.hate_names[actor_id] = name
            CHB.hate_events[mob_id]  = CHB.hate_events[mob_id] or {}
            CHB.hate_events[mob_id][actor_id] = {}
            for _, w in ipairs({...}) do
                table.insert(CHB.hate_events[mob_id][actor_id],
                    { ts = now - math.random(0, 25), w = w })
            end
        end
        push(101, 'Chharzilla',  500,  800, 1200,  900,  650)     -- MT
        push(102, 'Chharizard',    400,  350,  600,  450,  380)     -- OT
        push(103, 'Chharlotte',  200,  180,  240)                  -- healer
        push(104, 'Chharutaru',   80,   90,  110,   70,   85)
        -- Fake a spike on Chharizard in the last 2s
        table.insert(CHB.hate_events[mob_id][102], { ts = now - 1.5, w = 1400 })
        CHB.hate_mob_seen[mob_id] = now
        log_info('hate: test data pushed onto mob_id=' .. mob_id); return
    end
    log_info('hate subcommands: on/off/toggle | reset | width <n> | rows <n> | test')
end

CHB.register(Hate)

-- ============================================================================
