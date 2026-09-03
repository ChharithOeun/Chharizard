-- CHUNK 7: debuffed — enemy-target debuff tracker in the style of Xathe's
-- original Debuffed addon (thanks to Xathe / DiscipleOfEris — pattern is
-- theirs, ported into our module/framework architecture).
--
-- Why the rewrite from v3.7.0's enemydebuffs:
--   * OLD: hardcoded ~35 spell names → durations. Missed lots of spells
--     and never handled Composure/gear extensions or Shot promotions.
--   * NEW: reads spell metadata from Windower's res.spells[id]:
--       .status      = which status effect the spell inflicts
--       .duration    = base duration in seconds
--       .overwrites  = spell IDs this spell overwrites (Dia III kicks Dia I)
--     Comprehensive by construction — every debuffing spell in the game
--     resource file is covered automatically.
--
-- Data source:
--   * Incoming packet 0x028 (action) parsed via windower.packets.parse_action.
--     - Damaging debuffs (Bio/Dia): action message = 2 or 252  ->  landed.
--     - Non-damaging debuffs (Slow/Para/Blind/etc): action message = 236,
--       237, 268, or 271  ->  landed with effect id in action.param.
--   * Incoming packet 0x029 (action message):
--     - death messages (6, 20, 113, 406, 605, 646)     -> clear that mob.
--     - "wears off" messages (64, 204, 206, 350, 531) -> clear that debuff.
--   * Category 6 param 131 (Shot/Barrage on Dia)      -> promote Dia tier
--     for the extension (Ranger's dia-extension mechanic).
--
-- Display (matches Xathe format):
--     Debuffed [TargetName]
--
--     Dia III: 45
--     Slow II: 220
--     Paralyze II: 90
--
-- Colors: white for debuffs YOU applied, yellow for party members'.
--
-- Commands: //cb debuffed on|off|show|hide|toggle    (via generic)
--           //cb debuffed timers        toggle timer numbers
--           //cb debuffed clear         drop all tracked mobs
--           //cb debuffed test          push sample data on current target
--           //cb dev debuffed           live-state dump
-- ============================================================================

CHB.debuffed_mobs = {}   -- [mob_id] = { [effect_id] = { id=spell_id, timer=os.clock+dur, actor=actor_id } }
CHB.debuffed_player_id = 0

-- Message IDs (from res/action_messages.xml, Xathe's set).
local DBF_MSG_DAMAGING     = { [2]=true, [252]=true }
local DBF_MSG_NONDAMAGING  = { [236]=true, [237]=true, [268]=true, [271]=true }
local DBF_MSG_DEATH        = { [6]=true, [20]=true, [113]=true, [406]=true, [605]=true, [646]=true }
local DBF_MSG_WEARS_OFF    = { [64]=true, [204]=true, [206]=true, [350]=true, [531]=true }

local function _dbf_handle_overwrites(target_id, new_spell_id, this_overwrites)
    local mob = CHB.debuffed_mobs[target_id]
    if not mob then return true end
    -- If any active debuff on this mob lists new_spell_id in its own
    -- .overwrites, it's a higher-priority effect — refuse the new one.
    for effect, spell in pairs(mob) do
        local old = (res.spells[spell.id] and res.spells[spell.id].overwrites) or {}
        for _, ovr in ipairs(old) do
            if new_spell_id == ovr then return false end
        end
        -- Conversely, if our new spell overwrites this one, drop it.
        for _, ovr in ipairs(this_overwrites or {}) do
            if spell.id == ovr then mob[effect] = nil end
        end
    end
    return true
end

local function _dbf_apply(target_id, effect_id, spell_id, actor_id)
    if not res.spells[spell_id] then return end
    if not CHB.debuffed_mobs[target_id] then CHB.debuffed_mobs[target_id] = {} end
    local overwrites = res.spells[spell_id].overwrites or {}
    if not _dbf_handle_overwrites(target_id, spell_id, overwrites) then return end
    local dur = tonumber(res.spells[spell_id].duration) or 0
    CHB.debuffed_mobs[target_id][effect_id] = {
        id    = spell_id,
        timer = os.clock() + dur,
        actor = actor_id,
    }
end

-- Ranger's Shot / Barrage promotes an active Dia to the next tier when
-- landed on the currently Dia'd target. Effect id 134 = Dia. Xathe caps
-- at spell id 26 (Dia III) — we follow the same guard.
local function _dbf_handle_shot(target_id)
    local mob = CHB.debuffed_mobs[target_id]
    if not mob or not mob[134] then return end
    local cur = mob[134].id
    if cur < 26 then
        mob[134].id    = cur + 1
        mob[134].timer = os.clock() + ((res.spells[cur + 1] and res.spells[cur + 1].duration) or 0)
    end
end

local function _dbf_inc_action(a)
    if not a or not a.targets or not a.targets[1] then return end
    if a.category ~= 4 then
        if a.category == 6 and a.param == 131 then
            _dbf_handle_shot(a.targets[1].id)
        end
        return
    end

    local action = a.targets[1].actions and a.targets[1].actions[1]
    if not action then return end
    local msg    = tonumber(action.message) or 0
    local target = a.targets[1].id
    local spell  = a.param
    local sp     = res.spells[spell]
    if not sp then return end

    if DBF_MSG_DAMAGING[msg] then
        local effect = sp.status
        if effect then _dbf_apply(target, effect, spell, a.actor_id) end
    elseif DBF_MSG_NONDAMAGING[msg] then
        local effect = action.param
        if sp.status and sp.status == effect then
            _dbf_apply(target, effect, spell, a.actor_id)
        end
    end
end

local function _dbf_inc_action_message(target_id, param_1, message_id)
    if DBF_MSG_DEATH[message_id] then
        CHB.debuffed_mobs[target_id] = nil
    elseif DBF_MSG_WEARS_OFF[message_id] then
        if CHB.debuffed_mobs[target_id] then
            CHB.debuffed_mobs[target_id][param_1] = nil
        end
    end
end

windower.register_event('incoming chunk', function(id, data)
    if id == 0x028 then
        local ok, parsed = pcall(function()
            return windower.packets.parse_action(data)
        end)
        if ok and parsed then _dbf_inc_action(parsed) end
    elseif id == 0x029 then
        local ok = pcall(function()
            local target_id  = data:unpack('I', 0x09)
            local param_1    = data:unpack('I', 0x0D)
            local message_id = data:unpack('H', 0x19) % 32768
            _dbf_inc_action_message(target_id, param_1, message_id)
        end)
    end
end)

windower.register_event('login', 'load', function()
    local p = windower.ffxi.get_player()
    CHB.debuffed_player_id = (p and p.id) or 0
end)

windower.register_event('logout', 'zone change', function()
    CHB.debuffed_mobs = {}
end)

local COL_DBF_SELF   = '\\cs(255,255,255)'   -- white — YOUR debuffs
local COL_DBF_OTHER  = '\\cs(255,235,120)'   -- yellow — party members'
local COL_DBF_LOW    = '\\cs(255,110,110)'   -- red — <10s remaining
local COL_DBF_HDR    = '\\cs(220,220,220)'
local COL_DBF_RST    = '\\cr'

local Debuffed = {}
Debuffed.name = 'debuffed'
Debuffed.default = {
    enabled          = true,
    tick_frames      = 6,          -- ~10 Hz for smooth countdown
    pos_x            = 500,
    pos_y            = 160,
    font_size        = 12,
    opacity          = 220,
    auto_hide        = true,
    timers           = true,       -- show numeric seconds after each name
    hide_below_zero  = true,       -- drop debuffs whose timer expired
    warn_below       = 10,         -- seconds under which name goes red
}

function Debuffed:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function Debuffed:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function Debuffed:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    local target
    pcall(function() target = windower.ffxi.get_mob_by_target('t') end)
    if not target or not target.valid_target then
        CHB.hide_widget(self.widget); return
    end

    local data = CHB.debuffed_mobs[target.id]
    if not data then
        CHB.hide_widget(self.widget); return
    end

    local lines = {}
    local now   = os.clock()
    for effect, spell in pairs(data) do
        local sp = res.spells[spell.id]
        if sp then
            local name    = sp.name or sp.en or ('spell_' .. spell.id)
            local remains = math.max(0, spell.timer - now)
            local color   = (spell.actor == CHB.debuffed_player_id) and COL_DBF_SELF or COL_DBF_OTHER
            if remains > 0 and remains < (self.settings.warn_below or 10) then
                color = COL_DBF_LOW
            end
            if remains > 0 or not self.settings.hide_below_zero then
                if self.settings.timers and remains > 0 then
                    lines[#lines + 1] = string.format('%s%s: %.0f%s', color, name, remains, COL_DBF_RST)
                else
                    lines[#lines + 1] = string.format('%s%s%s', color, name, COL_DBF_RST)
                end
            else
                data[effect] = nil     -- prune expired
            end
        end
    end

    if #lines == 0 then
        CHB.hide_widget(self.widget); return
    end

    local text = string.format('%sDebuffed [%s]%s\n\n%s',
        COL_DBF_HDR, target.name, COL_DBF_RST,
        table.concat(lines, '\n'))

    CHB.render_text(self.widget, {
        text      = text,
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Debuffed:on_dump()
    local target
    pcall(function() target = windower.ffxi.get_mob_by_target('t') end)
    local names = {}
    if target and target.id and CHB.debuffed_mobs[target.id] then
        for effect, spell in pairs(CHB.debuffed_mobs[target.id]) do
            local sp = res.spells[spell.id]
            local nm = sp and (sp.name or sp.en) or ('spell_' .. spell.id)
            local rem = math.max(0, spell.timer - os.clock())
            names[#names + 1] = string.format('%s(%.0fs)', nm, rem)
        end
    end
    local tracked = 0
    for _ in pairs(CHB.debuffed_mobs) do tracked = tracked + 1 end
    return {
        widget       = tostring(self.widget),
        target_id    = target and target.id or 'nil',
        target_name  = target and target.name or 'nil',
        active       = table.concat(names, ', '),
        tracked_mobs = tracked,
        player_id    = CHB.debuffed_player_id,
    }
end

function Debuffed:on_command(sub, rest)
    if sub == 'clear' then
        CHB.debuffed_mobs = {}
        log_info('debuffed: cleared all tracked mobs.'); return
    end
    if sub == 'timers' then
        self.settings.timers = not self.settings.timers
        CHB.save_settings('debuffed')
        log_info('debuffed: timers=' .. tostring(self.settings.timers)); return
    end
    if sub == 'test' then
        local t; pcall(function() t = windower.ffxi.get_mob_by_target('t') end)
        local id = (t and t.id) or 99999
        -- Spell IDs from res: Dia III=25, Slow II=79, Paralyze=58, Blind=254
        CHB.debuffed_mobs[id] = {
            [134] = { id = 25,  timer = os.clock() + 178, actor = CHB.debuffed_player_id },
            [13]  = { id = 79,  timer = os.clock() + 220, actor = CHB.debuffed_player_id + 1 },
            [4]   = { id = 58,  timer = os.clock() +  90, actor = CHB.debuffed_player_id },
            [5]   = { id = 254, timer = os.clock() +   8, actor = CHB.debuffed_player_id + 1 },
        }
        log_info('debuffed: test data pushed for mob_id=' .. id); return
    end
    log_info('debuffed subcommands: on/off/show/hide/toggle | clear | timers | test | pos <x> <y> | size <n>')
end

CHB.register(Debuffed)

-- ============================================================================
