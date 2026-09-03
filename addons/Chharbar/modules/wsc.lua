-- CHUNK 9: wsc — Skillchain / Magic Burst tracker.
--
-- Watches WS actions from party. When two consecutive WSs on the same mob
-- have matching skillchain properties, computes the resulting SC and shows
-- it with a Magic Burst window countdown + burstable elements.
--
-- Skillchain math is Ivaar's Skillchains addon pattern (thanks Ivaar/Nsane
-- — sc_info shape and check_props logic ported into our framework).
--
-- Data:
--   * data/wsc_skills.lua — WS id -> {en, skillchain=[props], weapon=?}
--     Same file the Skillchains addon ships. Preserved from v2.0.11.
--
-- v1 features:
--   * 2-WS chain detection + chain-of-3/4 via SC prop resonance.
--   * Display: "Fragmentation Lv2  MB: Wind/Thunder  4.2s  Chharizard -> Chharzilla"
--   * Per-mob tracking; auto-clear on mob death (0x029 death msgs).
--
-- v4.1.1 backlog:
--   * WS predictor: given current SC prop, show what MY WSs would extend it.
--   * Magic burst spell suggestion by element / job.
-- ============================================================================

-- Load WS skillchain properties from data/wsc_skills.lua (shipped as an
-- asset since v2.0.11). Table shape: skills.weapon_skills[id] = {en, skillchain}.
CHB.wsc_skills = nil
do
    local ok, err = pcall(function()
        local f = files.new('data/wsc_skills.lua', true)
        local src = f:read()
        if src and src ~= '' then
            local chunk, cerr = loadstring(src)
            if not chunk then error(cerr) end
            local tbl = chunk()
            if type(tbl) == 'table' and type(tbl.weapon_skills) == 'table' then
                CHB.wsc_skills = tbl
            end
        end
    end)
    if not ok then
        -- Just log; module will degrade gracefully (report no SC).
        log_info('wsc: failed to load data/wsc_skills.lua: ' .. tostring(err))
    end
end

-- Skillchain composition table (Ivaar's sc_info, ported).
-- For each SC name, list its resonating properties, and how it combines
-- with other properties. Format: prop = {result_level, result_sc_name}.
local WSC_SC_INFO = {
    Radiance      = {'Fire','Wind','Lightning','Light', lvl=4},
    Umbra         = {'Earth','Ice','Water','Dark', lvl=4},
    Light         = {'Fire','Wind','Lightning','Light',
                     Light={4,'Radiance'}, lvl=3},
    Darkness      = {'Earth','Ice','Water','Dark',
                     Darkness={4,'Umbra'}, lvl=3},
    Gravitation   = {'Earth','Dark',
                     Distortion={3,'Darkness'}, Fragmentation={2,'Fragmentation'}, lvl=2},
    Fragmentation = {'Wind','Lightning',
                     Fusion={3,'Light'}, Distortion={2,'Distortion'}, lvl=2},
    Distortion    = {'Ice','Water',
                     Gravitation={3,'Darkness'}, Fusion={2,'Fusion'}, lvl=2},
    Fusion        = {'Fire','Light',
                     Fragmentation={3,'Light'}, Gravitation={2,'Gravitation'}, lvl=2},
    Compression   = {'Dark',
                     Transfixion={1,'Transfixion'}, Detonation={1,'Detonation'}, lvl=1},
    Liquefaction  = {'Fire',
                     Impaction={2,'Fusion'}, Scission={1,'Scission'}, lvl=1},
    Induration    = {'Ice',
                     Reverberation={2,'Fragmentation'}, Compression={1,'Compression'}, Impaction={1,'Impaction'}, lvl=1},
    Reverberation = {'Water',
                     Induration={1,'Induration'}, Impaction={1,'Impaction'}, lvl=1},
    Transfixion   = {'Light',
                     Scission={2,'Distortion'}, Reverberation={1,'Reverberation'}, Compression={1,'Compression'}, lvl=1},
    Scission      = {'Earth',
                     Liquefaction={1,'Liquefaction'}, Reverberation={1,'Reverberation'}, Detonation={1,'Detonation'}, lvl=1},
    Detonation    = {'Wind',
                     Compression={2,'Gravitation'}, Scission={1,'Scission'}, lvl=1},
    Impaction     = {'Lightning',
                     Liquefaction={1,'Liquefaction'}, Detonation={1,'Detonation'}, lvl=1},
}

-- Elements each SC opens for Magic Burst.
local WSC_MB_ELEMENTS = {
    Radiance      = 'Fire/Wind/Thunder/Light',
    Umbra         = 'Earth/Ice/Water/Dark',
    Light         = 'Fire/Wind/Thunder/Light',
    Darkness      = 'Earth/Ice/Water/Dark',
    Fusion        = 'Fire/Light',
    Fragmentation = 'Wind/Thunder',
    Distortion    = 'Water/Ice',
    Gravitation   = 'Earth/Dark',
    Compression   = 'Dark',
    Liquefaction  = 'Fire',
    Induration    = 'Ice',
    Reverberation = 'Water',
    Transfixion   = 'Light',
    Scission      = 'Earth',
    Detonation    = 'Wind',
    Impaction     = 'Thunder',
}

-- v4.7.0: per-element color pips. Colored ▓ block glyphs — no PNG assets
-- needed. Colors picked to match FFXI's own elemental palette closely.
local WSC_ELEM_COLORS = {
    Fire    = {255, 100,  70},
    Ice     = {150, 220, 255},
    Wind    = {150, 240, 170},
    Earth   = {200, 170, 100},
    Thunder = {230, 190,  80},
    Water   = {110, 170, 255},
    Light   = {255, 245, 200},
    Dark    = {200, 140, 220},
}

local function _wsc_pip(elem)
    local c = WSC_ELEM_COLORS[elem]
    if not c then return elem end
    return string.format('\\cs(%d,%d,%d)\226\150\147\\cr', c[1], c[2], c[3])   -- ▓
end

-- Render "🟥 Fire / 🟨 Thunder" style strip from a "Wind/Thunder" spec.
local function _wsc_mb_visual(mb_str)
    if not mb_str or mb_str == '' then return '' end
    local pieces = {}
    for elem in mb_str:gmatch('[^/]+') do
        pieces[#pieces + 1] = _wsc_pip(elem) .. ' ' .. elem
    end
    return table.concat(pieces, ' ')
end

-- Skillchain magic-burst window duration in seconds (approximate FFXI values).
local WSC_WINDOW_BY_LVL = { [1]=4, [2]=6, [3]=8, [4]=10 }
-- Skillchain PAIRING window — how long the first WS's props are valid to
-- close a chain with a second WS. Longer than MB window.
local WSC_CHAIN_WINDOW  = 9

-- Given two prop arrays, return (level, sc_name) if they close a chain,
-- else nil. Ports Ivaar's check_props verbatim.
local function _wsc_check_props(old_props, new_props)
    if type(old_props) ~= 'table' or type(new_props) ~= 'table' then return nil end
    for _, first in ipairs(old_props) do
        local combo = WSC_SC_INFO[first]
        if combo then
            for _, second in ipairs(new_props) do
                local result = combo[second]
                if result then
                    return result[1], result[2]
                end
            end
        end
    end
    return nil, nil
end

-- Per-mob state:
--   last_by_mob[mob_id] = { props=[strings], actor_name, ts, from_ws_name }
--   active[mob_id]      = { sc_name, sc_lvl, opened_at, closes_at, chain_line }
CHB.wsc_state = { last_by_mob = {}, active = {} }

local function _wsc_actor_name(actor_id)
    if not actor_id or actor_id == 0 then return '?' end
    local ok, m = pcall(function() return windower.ffxi.get_mob_by_id(actor_id) end)
    if ok and m and m.name then return m.name end
    return 'id' .. actor_id
end

local function _wsc_is_party(actor_id)
    if not actor_id then return false end
    local ok, party = pcall(function() return windower.ffxi.get_party() end)
    if not ok or type(party) ~= 'table' then return false end
    for _, m in pairs(party) do
        if type(m) == 'table' and m.mob and m.mob.id == actor_id then return true end
    end
    return false
end

windower.register_event('action', function(a)
    if not a or a.category ~= 3 then return end   -- WS finish
    if not CHB.wsc_skills then return end
    if not _wsc_is_party(a.actor_id) then return end

    local ws_id = tonumber(a.param)
    if not ws_id then return end
    local ws = CHB.wsc_skills.weapon_skills[ws_id]
    if not ws or type(ws.skillchain) ~= 'table' or #ws.skillchain == 0 then return end

    local actor = _wsc_actor_name(a.actor_id)
    local now   = os.clock()

    for _, t in pairs(a.targets or {}) do
        local mob_id = tonumber(t.id)
        if mob_id and mob_id ~= 0 then
            local last = CHB.wsc_state.last_by_mob[mob_id]
            local closed = false
            if last and (now - last.ts) <= WSC_CHAIN_WINDOW then
                local lvl, sc_name = _wsc_check_props(last.props, ws.skillchain)
                if lvl and sc_name then
                    -- Chain closed! Store as active SC + roll last.props to
                    -- the SC's own props so a chain-of-3/4 can extend.
                    local window = WSC_WINDOW_BY_LVL[lvl] or 5
                    local chain_line = string.format('%s > %s > %s',
                        last.actor_name, last.from_ws_name, ws.en)
                    CHB.wsc_state.active[mob_id] = {
                        sc_name    = sc_name,
                        sc_lvl     = lvl,
                        opened_at  = now,
                        closes_at  = now + window,
                        chain_line = chain_line,
                        closer     = actor,
                        -- v4.7.0: flash pulse for ~800ms after SC opens.
                        flash_until = now + 0.8,
                    }
                    CHB.wsc_state.last_by_mob[mob_id] = {
                        props        = { sc_name },
                        actor_name   = actor,
                        from_ws_name = ws.en,
                        ts           = now,
                    }
                    closed = true
                end
            end
            if not closed then
                CHB.wsc_state.last_by_mob[mob_id] = {
                    props        = ws.skillchain,
                    actor_name   = actor,
                    from_ws_name = ws.en,
                    ts           = now,
                }
            end
        end
    end
end)

-- Clear a mob's WSC state on death (same 0x029 death msg set as debuffed/hate).
local WSC_MSG_DEATH = { [6]=true, [20]=true, [113]=true, [406]=true, [605]=true, [646]=true }
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x029 then return end
    pcall(function()
        local target_id  = data:unpack('I', 0x09)
        local message_id = data:unpack('H', 0x19) % 32768
        if WSC_MSG_DEATH[message_id] then
            CHB.wsc_state.last_by_mob[target_id] = nil
            CHB.wsc_state.active[target_id]      = nil
        end
    end)
end)

-- v4.1.1: player-known WSs / spells helpers for the predictor + MB spell hints.
local function _wsc_known_ws_ids()
    local ok, ab = pcall(function() return windower.ffxi.get_abilities() end)
    if not ok or type(ab) ~= 'table' or type(ab.weapon_skills) ~= 'table' then return {} end
    return ab.weapon_skills
end

local function _wsc_known_spell_ids()
    local ok, sp = pcall(function() return windower.ffxi.get_spells() end)
    if not ok or type(sp) ~= 'table' then return {} end
    local out = {}
    for id, has in pairs(sp) do
        if has then out[#out + 1] = tonumber(id) end
    end
    return out
end

-- Given a prop (or prop array) of an "opener" state — either the current SC's
-- single prop, or a WS's multi-prop skillchain array — return the top-ranked
-- weapon skills that WOULD extend/close it. Sorted by resulting SC level desc.
local function _wsc_extend_suggestions(opener)
    if not CHB.wsc_skills or not opener then return {} end
    local props = type(opener) == 'table' and opener or { opener }
    local out = {}
    local seen = {}   -- dedupe by ws name (WS ids repeat across weapon variants)
    for _, ws_id in ipairs(_wsc_known_ws_ids()) do
        local ws = CHB.wsc_skills.weapon_skills[ws_id]
        if ws and type(ws.skillchain) == 'table' then
            local lvl, sc_name = _wsc_check_props(props, ws.skillchain)
            if lvl and sc_name and not seen[ws.en] then
                seen[ws.en] = true
                out[#out + 1] = { name = ws.en, result_lvl = lvl, result_sc = sc_name }
            end
        end
    end
    table.sort(out, function(a, b) return a.result_lvl > b.result_lvl end)
    return out
end

-- Element name (as it appears in WSC_MB_ELEMENTS string, e.g. "Fire") ->
-- Windower element ID. Windower uses "Lightning" internally; SC labels use
-- "Thunder" — we alias.
local WSC_ELEMENT_ID = {
    Fire = 0, Ice = 1, Wind = 2, Earth = 3,
    Thunder = 4, Lightning = 4, Water = 5, Light = 6, Dark = 7,
}

-- Given SC name, return known elemental spells that could magic-burst it.
-- Filters to spell types that DO damage (BlackMagic / BlueMagic / Ninjutsu /
-- Geomancy). Sorted by MP cost desc so higher-tier nukes appear first.
local function _wsc_burst_suggestions(sc_name)
    local mb_str = WSC_MB_ELEMENTS[sc_name] or ''
    if mb_str == '' then return {} end
    local target = {}
    for elem_name in mb_str:gmatch('[^/]+') do
        local eid = WSC_ELEMENT_ID[elem_name]
        if eid then target[eid] = true end
    end
    if next(target) == nil then return {} end

    local out = {}
    local seen = {}
    for _, sid in ipairs(_wsc_known_spell_ids()) do
        local sp = res.spells[sid]
        if sp and sp.element and target[sp.element] then
            local sptype = sp.type or ''
            if sptype == 'BlackMagic' or sptype == 'BlueMagic'
               or sptype == 'Ninjutsu' or sptype == 'Geomancy' then
                if not seen[sp.en] then
                    seen[sp.en] = true
                    out[#out + 1] = { name = sp.en, mp = tonumber(sp.mp_cost) or 0 }
                end
            end
        end
    end
    table.sort(out, function(a, b) return (a.mp or 0) > (b.mp or 0) end)
    return out
end

local WSC = {}
WSC.name = 'wsc'
WSC.default = {
    enabled     = true,
    tick_frames = 3,           -- ~20 Hz for smooth countdown
    pos_x       = 500,
    pos_y       = 200,
    font_size   = 12,
    opacity     = 220,
    auto_hide   = false,       -- keep visible even in menus so you don't miss MB
    predictor   = true,        -- v4.1.1: show WSs that would extend current SC
    mb_spells   = true,        -- v4.1.1: show elemental spells that could burst
    max_suggest = 4,           -- how many WSs / spells to list per line
    hang_after  = 2.0,         -- v4.7.2: keep widget visible this many seconds
                               -- after MB window closes so you can read the numbers
    opener_predict = true,     -- v4.7.2: show possibilities after a lone opener WS
}

local COL_WSC_NAME  = '\\cs(255,200,120)'   -- warm yellow — SC name
local COL_WSC_LVL   = '\\cs(255,160, 90)'
local COL_WSC_MB    = '\\cs(140,200,255)'   -- cyan — burst elements
local COL_WSC_TIME  = '\\cs(255,235,120)'
local COL_WSC_LOW   = '\\cs(255,110,110)'   -- red — <2s
local COL_WSC_CHAIN = '\\cs(200,200,200)'
local COL_WSC_PRED  = '\\cs(180,255,180)'   -- pale green — extend WS suggestions
local COL_WSC_BURST = '\\cs(180,180,255)'   -- pale blue — burst spell suggestions
local COL_WSC_RST   = '\\cr'

function WSC:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function WSC:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function WSC:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    -- Prefer active SC on current battle target; fall back to any active SC.
    local now = os.clock()
    local hang_after = tonumber(self.settings.hang_after) or 2.0
    local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
    local mob_id = bt and bt.id or nil
    local sc = mob_id and CHB.wsc_state.active[mob_id] or nil

    -- v4.7.2: consider a "hanging" SC as still displayable up to hang_after
    -- seconds past closes_at, so the user has time to read the final numbers.
    local function _sc_visible(s)
        if not s then return false end
        return (s.closes_at + hang_after) > now
    end

    if not _sc_visible(sc) then sc = nil end

    -- If no SC on current bt, find the most recently opened visible SC on any mob.
    if not sc then
        local best, best_ts = nil, 0
        for mid, s in pairs(CHB.wsc_state.active) do
            if _sc_visible(s) and s.opened_at > best_ts then
                best, best_ts = s, s.opened_at
            end
            if not _sc_visible(s) then
                CHB.wsc_state.active[mid] = nil
            end
        end
        sc = best
    end

    -- v4.7.2: if still no SC, try opener-prediction mode. A recent lone WS
    -- opener on the current bt lets us preview which of YOUR WSs would
    -- close a chain against it, ranked by resulting SC level.
    if not sc and self.settings.opener_predict and mob_id then
        local opener = CHB.wsc_state.last_by_mob[mob_id]
        if opener and opener.props and (now - opener.ts) <= WSC_CHAIN_WINDOW then
            local remain_open = math.max(0, WSC_CHAIN_WINDOW - (now - opener.ts))
            local preds = _wsc_extend_suggestions(opener.props)
            local cap = self.settings.max_suggest or 4
            local pieces = {}
            for i = 1, math.min(cap, #preds) do
                local p = preds[i]
                pieces[i] = string.format('%s -> %s Lv%d', p.name, p.result_sc, p.result_lvl)
            end
            if #pieces == 0 then
                pieces = { '(none of your WSs chain this opener)' }
            end
            local lines = {}
            lines[#lines + 1] = string.format('%s[Opener]%s %s%s%s by %s%s%s   %s%.1fs%s',
                COL_WSC_LVL, COL_WSC_RST,
                COL_WSC_NAME, opener.from_ws_name or '?', COL_WSC_RST,
                COL_WSC_CHAIN, opener.actor_name or '?', COL_WSC_RST,
                COL_WSC_TIME, remain_open, COL_WSC_RST)
            lines[#lines + 1] = COL_WSC_PRED .. 'chain: ' .. table.concat(pieces, ' | ') .. COL_WSC_RST
            CHB.render_text(self.widget, {
                text      = table.concat(lines, '\n'),
                pos_x     = self.settings.pos_x,
                pos_y     = self.settings.pos_y,
                font_size = self.settings.font_size,
                opacity   = self.settings.opacity,
            })
            -- v4.7.3: orange pulse during opener/chain-building phase.
            -- Frequency scales with remain_open (1Hz -> 4Hz).
            local ofrac = remain_open / WSC_CHAIN_WINDOW
            local ofreq = 1 + (1 - ofrac) * 3
            local ophase = os.clock() * ofreq * 2 * math.pi
            local opulse = (math.sin(ophase) + 1) * 0.5
            local oalpha = math.floor(120 + opulse * 135)
            CHB.set_border_pulse(self.widget, 255, 160, 60, oalpha)   -- orange
            return
        end
    end

    if not sc then
        CHB.hide_widget(self.widget); return
    end

    local remaining = math.max(0, sc.closes_at - now)
    local total_dur = math.max(1, sc.closes_at - sc.opened_at)
    local frac      = remaining / total_dur   -- 1.0 -> 0.0
    local is_hanging = (sc.closes_at <= now)   -- v4.7.2: past MB, in hang period

    -- v4.7.0: smooth countdown gradient green -> yellow -> orange -> red.
    -- Linear interpolate between color stops at frac 1.0 / 0.6 / 0.3 / 0.1.
    local function _lerp(a, b, t) return math.floor(a + (b - a) * t + 0.5) end
    local r, g, b
    if frac > 0.6 then
        local t = (frac - 0.6) / 0.4
        r = _lerp(240, 180, t); g = _lerp(240, 255, t); b = _lerp(120,  90, t)
    elseif frac > 0.3 then
        local t = (frac - 0.3) / 0.3
        r = _lerp(255, 240, t); g = _lerp(180, 240, t); b = _lerp( 90, 120, t)
    elseif frac > 0.1 then
        local t = (frac - 0.1) / 0.2
        r = _lerp(255, 255, t); g = _lerp(110, 180, t); b = _lerp( 90,  90, t)
    else
        local t = math.max(0, frac / 0.1)
        r = _lerp(255, 255, t); g = _lerp( 60, 110, t); b = _lerp( 60,  90, t)
    end
    local time_c = string.format('\\cs(%d,%d,%d)', r, g, b)

    local mb_visual = _wsc_mb_visual(WSC_MB_ELEMENTS[sc.sc_name] or '')
    local sc_name_str = sc.sc_name
    -- v4.7.0: Lv4 (Radiance/Umbra) gets a ✦✦✦ prefix for emphasis.
    if sc.sc_lvl >= 4 then
        sc_name_str = '\226\156\166\226\156\166\226\156\166 ' .. sc_name_str   -- ✦✦✦
    elseif sc.sc_lvl == 3 then
        sc_name_str = '\226\156\166\226\156\166 ' .. sc_name_str               -- ✦✦
    end

    local lines = {}
    if is_hanging then
        -- v4.7.2: past-close hang — grey out time display, note "closed"
        lines[#lines+1] = string.format('%s%s%s %sLv%d%s   %sMB: %s   \\cs(140,140,140)closed\\cr',
            COL_WSC_NAME, sc_name_str, COL_WSC_RST,
            COL_WSC_LVL,  sc.sc_lvl, COL_WSC_RST,
            COL_WSC_MB,   mb_visual)
    else
        lines[#lines+1] = string.format('%s%s%s %sLv%d%s   %sMB: %s   %s%.1fs%s',
            COL_WSC_NAME, sc_name_str, COL_WSC_RST,
            COL_WSC_LVL,  sc.sc_lvl, COL_WSC_RST,
            COL_WSC_MB,   mb_visual,
            time_c,       remaining, COL_WSC_RST)
    end
    lines[#lines+1] = COL_WSC_CHAIN .. (sc.chain_line or '') .. COL_WSC_RST

    -- v4.1.1: WS predictor — my WSs that would extend the current SC.
    if self.settings.predictor then
        local extensions = _wsc_extend_suggestions(sc.sc_name)
        if #extensions > 0 then
            local parts = {}
            local cap = self.settings.max_suggest or 4
            for i = 1, math.min(cap, #extensions) do
                local e = extensions[i]
                parts[i] = string.format('%s -> %s Lv%d', e.name, e.result_sc, e.result_lvl)
            end
            lines[#lines+1] = COL_WSC_PRED .. 'extend: ' .. table.concat(parts, ' | ') .. COL_WSC_RST
        end
    end

    -- v4.1.1: MB spell suggestions — my elemental spells matching the SC's
    -- burst elements. Only shows if we have any burst-capable spell known.
    if self.settings.mb_spells then
        local bursts = _wsc_burst_suggestions(sc.sc_name)
        if #bursts > 0 then
            local parts = {}
            local cap = self.settings.max_suggest or 4
            for i = 1, math.min(cap, #bursts) do
                parts[i] = string.format('%s(%d)', bursts[i].name, bursts[i].mp)
            end
            lines[#lines+1] = COL_WSC_BURST .. 'burst: ' .. table.concat(parts, ', ') .. COL_WSC_RST
        end
    end

    -- v4.7.0: bg-alpha flash pulse on SC open. Sine wave over the 800ms
    -- flash window, mapping 3 half-cycles between opacity ±60. Font-size
    -- pulse for Lv4 SCs: bump size +2 during the first 300ms.
    local rendered_opacity = self.settings.opacity or 220
    local rendered_size    = self.settings.font_size or 12
    if sc.flash_until and now < sc.flash_until then
        local flash_frac = (sc.flash_until - now) / 0.8  -- 1.0 -> 0.0
        local phase = flash_frac * math.pi * 3           -- 3 half-waves
        local swing = math.abs(math.sin(phase)) * 80     -- 0..80
        rendered_opacity = math.min(255, math.floor((rendered_opacity or 220) + swing - 40))
        if sc.sc_lvl >= 4 and (sc.flash_until - now) > 0.5 then
            rendered_size = rendered_size + 2
        end
    end

    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = rendered_size,
        opacity   = rendered_opacity,
    })

    -- v4.7.3: pulse the border. Lavender during active MB (chain closed,
    -- window ticking). Static gold once we're in the hang period. Speed
    -- ramps 1 Hz -> 4 Hz as the timer approaches zero.
    if is_hanging then
        CHB.set_border_pulse(self.widget)   -- static gold
    else
        local freq  = 1 + (1 - frac) * 3
        local phase = os.clock() * freq * 2 * math.pi
        local pulse = (math.sin(phase) + 1) * 0.5   -- 0..1
        local alpha = math.floor(120 + pulse * 135) -- 120..255
        CHB.set_border_pulse(self.widget, 200, 170, 255, alpha)  -- lavender
    end
end

function WSC:on_dump()
    local mob_count = 0
    local active_count = 0
    for _ in pairs(CHB.wsc_state.last_by_mob) do mob_count = mob_count + 1 end
    for _ in pairs(CHB.wsc_state.active) do active_count = active_count + 1 end
    return {
        widget          = tostring(self.widget),
        skills_loaded   = CHB.wsc_skills and 'yes' or 'no',
        mobs_tracked    = mob_count,
        active_chains   = active_count,
        chain_window_s  = WSC_CHAIN_WINDOW,
    }
end

function WSC:on_command(sub, rest)
    if sub == 'clear' then
        CHB.wsc_state.last_by_mob = {}
        CHB.wsc_state.active = {}
        log_info('wsc: cleared.'); return
    end
    if sub == 'predictor' or sub == 'pred' then
        local a = (rest or ''):lower()
        if a == 'on' then self.settings.predictor = true
        elseif a == 'off' then self.settings.predictor = false
        else self.settings.predictor = not self.settings.predictor end
        CHB.save_settings('wsc')
        log_info('wsc: predictor=' .. tostring(self.settings.predictor)); return
    end
    if sub == 'mb' or sub == 'mbspells' then
        local a = (rest or ''):lower()
        if a == 'on' then self.settings.mb_spells = true
        elseif a == 'off' then self.settings.mb_spells = false
        else self.settings.mb_spells = not self.settings.mb_spells end
        CHB.save_settings('wsc')
        log_info('wsc: mb_spells=' .. tostring(self.settings.mb_spells)); return
    end
    if sub == 'max' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb wsc max <1..8>'); return end
        n = math.max(1, math.min(8, math.floor(n)))
        self.settings.max_suggest = n
        CHB.save_settings('wsc'); CHB.hard_reset('wsc')
        log_info('wsc: max_suggest=' .. n); return
    end
    if sub == 'hang' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb wsc hang <seconds>'); return end
        n = math.max(0, math.min(10, n))
        self.settings.hang_after = n
        CHB.save_settings('wsc')
        log_info('wsc: hang_after=' .. n .. 's'); return
    end
    if sub == 'opener' then
        local a = (rest or ''):lower()
        if a == 'on' then self.settings.opener_predict = true
        elseif a == 'off' then self.settings.opener_predict = false
        else self.settings.opener_predict = not self.settings.opener_predict end
        CHB.save_settings('wsc')
        log_info('wsc: opener_predict=' .. tostring(self.settings.opener_predict)); return
    end
    if sub == 'testopen' then
        -- v4.7.2: push a lone opener (no chain closed yet) to preview
        -- opener-prediction mode with your current job's WSs.
        local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
        local mob_id = (bt and bt.id) or 99999
        CHB.wsc_state.last_by_mob[mob_id] = {
            props        = { 'Gravitation', 'Transfixion' },   -- Evisceration
            actor_name   = 'Chharizard',
            from_ws_name = 'Evisceration',
            ts           = os.clock(),
        }
        CHB.wsc_state.active[mob_id] = nil
        log_info('wsc: opener test pushed on mob_id=' .. mob_id .. ' — predictions active for ' .. WSC_CHAIN_WINDOW .. 's'); return
    end
    if sub == 'test' then
        -- Push a fake Fragmentation Lv2 with 6s window.
        local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
        local mob_id = (bt and bt.id) or 99999
        local now = os.clock()
        CHB.wsc_state.active[mob_id] = {
            sc_name    = 'Fragmentation',
            sc_lvl     = 2,
            opened_at  = now,
            closes_at  = now + 6,
            chain_line = 'Chharizard > Evisceration > Chharzilla > Blade: Ku',
            closer     = 'Chharzilla',
            flash_until = now + 0.8,
        }
        log_info('wsc: test SC pushed onto mob_id=' .. mob_id); return
    end
    if sub == 'test4' or sub == 'testlv4' then
        -- Push a Lv4 Radiance to preview the emphasis effect.
        local bt; pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)
        local mob_id = (bt and bt.id) or 99999
        local now = os.clock()
        CHB.wsc_state.active[mob_id] = {
            sc_name    = 'Radiance',
            sc_lvl     = 4,
            opened_at  = now,
            closes_at  = now + 10,
            chain_line = 'Chharizard > SavageBlade > Chharzilla > ChantduCygne > Chharlotte > Savage',
            closer     = 'Chharlotte',
            flash_until = now + 0.8,
        }
        log_info('wsc: test Lv4 Radiance pushed onto mob_id=' .. mob_id); return
    end
    log_info('wsc subcommands: clear | test | test4 | testopen | predictor on|off | mb on|off | opener on|off | max <n> | hang <s>  (generic: on/off/toggle/pos/size/opacity)')
end

CHB.register(WSC)

-- ============================================================================
