-- CHUNK 4: debuffs — show negative status effects on the player.
--
-- v3.3.0 ships SELF debuffs only, read from windower.ffxi.get_player().buffs.
-- Party/alliance debuffs will follow in v3.3.1 by parsing the incoming
-- 0x076 packet (read-only) using the same pattern XivParty uses.
--
-- Design decisions:
--   * Whitelist-only. We list the buff IDs we know are debuffs and
--     ignore everything else. Safer than a buff exclusion list — if we
--     miss a debuff we just don't show it (annoying), if we accidentally
--     include a buff we show something misleading (worse).
--   * Nuclear-force render every tick: full widget state, no cache.
--   * When the debuff list is empty, hide the widget completely so it
--     doesn't leave a ghost background.
--   * Debuff names use FFXI's short color codes for at-a-glance triage:
--       yellow = magic-inflicted (Poison, Paralyze, Silence, Blind, Slow,
--                                 Dia, Bio, elemental DoTs)
--       red    = disabling      (Sleep, Stun, Petrify, Charm, Amnesia,
--                                 Bind, Weight, Terror, Doom, Curse)
--       purple = songs/JA       (Requiem, Elegy, Threnody, Lullaby, Frazzle)
-- ============================================================================

-- Comprehensive debuff whitelist. Extracted from FFXI buffs resource;
-- expand as we see more in the wild.
local DEBUFF_SET = {
    -- Core status ailments (early IDs)
    [1]=true,   -- Weakness
    [2]=true,   -- Sleep
    [3]=true,   -- Poison
    [4]=true,   -- Paralysis
    [5]=true,   -- Blindness
    [6]=true,   -- Silence
    [7]=true,   -- Petrification
    [8]=true,   -- Disease
    [9]=true,   -- Curse
    [10]=true,  -- Stun
    [11]=true,  -- Bind
    [12]=true,  -- Weight
    [13]=true,  -- Slow
    [14]=true,  -- Charm
    [15]=true,  -- Dia
    [16]=true,  -- Bio
    [17]=true,  -- Sleep II
    [18]=true,  -- Poison II
    [19]=true,  -- Paralysis II
    [20]=true,  -- Blindness II
    [21]=true,  -- Silence II
    [22]=true,  -- Petrification II
    [23]=true,  -- Disease II
    [24]=true,  -- Curse II
    [25]=true,  -- Frost
    [26]=true,  -- Choke
    [27]=true,  -- Rasp
    [28]=true,  -- Shock
    [29]=true,  -- Burn
    [30]=true,  -- Drown
    [31]=true,  -- Dia II
    [32]=true,  -- Bio II
    [33]=true,  -- Stun II
    [34]=true,  -- Requiem
    [35]=true,  -- Lullaby
    [36]=true,  -- Elegy
    [56]=true,  -- Doom
    [128]=true, -- Max HP down
    [129]=true, -- Max MP down
    [130]=true, -- Terror
    [131]=true, -- Muddle
    [193]=true, -- Encumbrance
    [252]=true, -- Amnesia
    [253]=true, -- Charm II
    [254]=true, -- Gradual Petrification
    [255]=true, -- Sleep III
    [256]=true, -- Encumbrance II
    [257]=true, -- Obliviscence
    [258]=true, -- Debilitation
    [259]=true, -- Slow II
    [260]=true, -- Blind II
    [261]=true, -- Bio III
    [262]=true, -- Dia III
    [263]=true, -- Wildfire
    [264]=true, -- Muddle II
    [265]=true, -- Impairment
    [266]=true, -- Addle
    [267]=true, -- Poison III
    [268]=true, -- Frazzle
    [269]=true, -- Distract
    [270]=true, -- Actor Suppression
    [271]=true, -- Silence II
    [272]=true, -- Paralysis III
    [273]=true, -- Voidsong
    [274]=true, -- Bane
    [275]=true, -- Geo (various)
    [276]=true,
    [277]=true,
    [278]=true,
    [279]=true,
    [280]=true,
    [281]=true,
    [282]=true,
    [283]=true,
    [284]=true,
    [285]=true,
    [286]=true,
    [287]=true, -- Geo indi/entrust bubbles use these
    [388]=true, -- Pillage / other newer
    [389]=true,
    [402]=true, -- Various debilitating songs
    [420]=true,
    [421]=true,
    [422]=true, -- Threnody variants
    [423]=true,
    [424]=true,
    [425]=true,
    [426]=true,
    [427]=true,
    [428]=true,
    [453]=true, -- Requiem tiers
    [454]=true,
    [455]=true,
    [456]=true,
    [457]=true,
    [458]=true,
    [459]=true,
    [460]=true,
    [461]=true,
    [462]=true,
    [463]=true, -- Elegy tiers
    [464]=true,
    [465]=true,
    [466]=true,
    [467]=true,
    [468]=true,
    [469]=true,
    [470]=true,
    [471]=true,
    [472]=true,
    [473]=true, -- Threnody tiers
    [474]=true,
    [475]=true,
    [476]=true,
    [477]=true,
    [478]=true,
    [479]=true,
    [480]=true,
}

-- Colour classification.
local DEBUFF_CLASS_DISABLE = {   -- red — can't act / stops movement
    [2]=1, [4]=1, [7]=1, [10]=1, [11]=1, [12]=1, [14]=1, [17]=1, [22]=1,
    [24]=1, [33]=1, [35]=1, [56]=1, [130]=1, [252]=1, [253]=1, [254]=1,
    [255]=1, [193]=1, [256]=1,
}
local DEBUFF_CLASS_SONG = {      -- purple — bard songs / bardic debuffs
    [34]=1, [35]=1, [36]=1,
}
for id = 402, 480 do DEBUFF_CLASS_SONG[id] = 1 end

local COL_DBF_MAGIC   = '\\cs(255,220,120)'   -- yellow
local COL_DBF_DISABLE = '\\cs(255,110,110)'   -- red
local COL_DBF_SONG    = '\\cs(220,140,255)'   -- purple
local COL_DBF_RESET   = '\\cr'

local function _debuff_color(id)
    if DEBUFF_CLASS_DISABLE[id] then return COL_DBF_DISABLE end
    if DEBUFF_CLASS_SONG[id]    then return COL_DBF_SONG    end
    return COL_DBF_MAGIC
end

-- Look up a buff's short display name. res.buffs[id].enl (english label)
-- is the short form; fall back to .en, then to the numeric id.
local function _buff_name(id)
    if not id then return '?' end
    local ok, r = pcall(function() return res.buffs[id] end)
    if ok and r then
        return r.enl or r.en or ('id' .. tostring(id))
    end
    return 'id' .. tostring(id)
end

local Debuffs = {}
Debuffs.name = 'debuffs'
Debuffs.default = {
    enabled     = true,
    tick_frames = 15,      -- ~4 Hz — debuffs don't move fast
    pos_x       = 20,
    pos_y       = 140,
    font_size   = 11,
    opacity     = 220,     -- near-solid so red/yellow text has contrast
    auto_hide   = true,
    max_show    = 10,      -- cap the render list so it can't overflow
}

function Debuffs:on_create()
    self.widget = CHB.new_text_widget(self.settings)
    self.last_ids = {}
end

function Debuffs:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

-- Extract active debuff IDs from player.buffs (which is a dense array of
-- buff IDs, 0 meaning empty slot). Filters through DEBUFF_SET so only
-- known debuffs come through.
local function _player_debuffs()
    local buffs
    local ok = pcall(function()
        local p = windower.ffxi.get_player()
        buffs = p and p.buffs or nil
    end)
    if not ok or type(buffs) ~= 'table' then return {} end
    local out = {}
    for _, id in ipairs(buffs) do
        if id and id ~= 0 and DEBUFF_SET[id] then
            out[#out + 1] = id
        end
    end
    return out
end

function Debuffs:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    local ids = _player_debuffs()
    if #ids == 0 then
        CHB.hide_widget(self.widget); return
    end

    -- Cap and de-duplicate (some effects report twice from stacked application).
    local seen, uniq = {}, {}
    for _, id in ipairs(ids) do
        if not seen[id] then
            seen[id] = true
            uniq[#uniq + 1] = id
            if #uniq >= (self.settings.max_show or 10) then break end
        end
    end

    -- Layout: one debuff per line, coloured by class.
    local lines = {}
    for _, id in ipairs(uniq) do
        lines[#lines + 1] = string.format('%s%s%s',
            _debuff_color(id), _buff_name(id), COL_DBF_RESET)
    end

    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
    self.last_ids = uniq
end

function Debuffs:on_dump()
    local ids = _player_debuffs()
    local names = {}
    for i, id in ipairs(ids) do names[i] = _buff_name(id) .. '(' .. id .. ')' end
    return {
        widget       = tostring(self.widget),
        active_count = #ids,
        active       = table.concat(names, ', '),
        max_show     = self.settings.max_show,
    }
end

function Debuffs:on_command(sub, rest)
    if sub == 'max' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb debuffs max <n>'); return end
        self.settings.max_show = math.max(1, math.min(20, math.floor(n)))
        CHB.save_settings('debuffs'); CHB.hard_reset('debuffs')
        log_info('debuffs: max_show=' .. self.settings.max_show); return
    end
    if sub == 'test' then
        -- Force a visible render even if no debuffs are active.
        pcall(function()
            CHB.render_text(self.widget, {
                text = COL_DBF_MAGIC .. 'Poison' .. COL_DBF_RESET .. '\n' ..
                       COL_DBF_DISABLE .. 'Sleep'  .. COL_DBF_RESET .. '\n' ..
                       COL_DBF_SONG    .. 'Elegy'  .. COL_DBF_RESET,
                pos_x = self.settings.pos_x, pos_y = self.settings.pos_y,
                font_size = self.settings.font_size, opacity = self.settings.opacity,
            })
        end)
        log_info('debuffs: test render pushed. //cb reload debuffs to clear.')
        return
    end
    log_info('debuffs subcommands: max <n> | test  (generic: on/off/toggle/pos/size/opacity)')
end

CHB.register(Debuffs)

-- ============================================================================
