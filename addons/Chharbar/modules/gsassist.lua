-- CHUNK 12: gsassist — Gearswap set explorer + simulator.
--
-- READ-ONLY. Never modifies gearswap files or equipped gear. Just parses
-- your gearswap job file text and lets you inspect sets, compare them, or
-- simulate expected damage using the scoreboard's per-hit history.
--
-- Data source:
--   * Windower/addons/GearSwap/data/<PlayerName>/<JOB>.lua
--   * Parsed with a lightweight scanner (regex, no loadstring — the
--     security constraint holds even for gearswap files we don't own).
--   * We look for sets.WS["Name"] = { ... slot="Item", ... } blocks and
--     harvest the slot->item map.
--
-- Sim math (v1, deliberately naive):
--   * Scoreboard tracks each hit's damage per PC. We take the last N
--     hits for the player and compute mean/max. That's the CURRENT set's
--     effective baseline. Comparing sets requires estimating stat
--     deltas from item names, which needs an item DB — out of scope for
--     v1. So sim mode just shows CURRENT baseline + LIST both sets so
--     the user can eyeball differences.
--   * v4.4.1 could bring a proper stat DB and predicted-damage math.
--
-- Commands (all under //cb gs ...):
--   //cb gs list                 list WS sets found in current job file
--   //cb gs show <WS>            print the item list for that WS set
--   //cb gs compare <WS> <A> <B> diff two sets side-by-side
--   //cb gs sim <WS>             baseline damage from scoreboard history
--   //cb gs file                 print the file path we're reading from
--   //cb gs reload               rescan the file
-- ============================================================================

CHB.gs = { file_path = nil, sets = nil, last_load = 0 }

-- Try to locate the current player+job's gearswap file. Multiple standard
-- paths exist across gearswap versions.
local function _gs_find_file()
    local p = pcall(function() return windower.ffxi.get_player() end)
    local ok, player = pcall(function() return windower.ffxi.get_player() end)
    if not ok or not player then return nil end
    local name = player.name
    local job  = player.main_job
    if not name or not job then return nil end
    local candidates = {
        'GearSwap/data/' .. name .. '/' .. job .. '.lua',
        'GearSwap/data/' .. job .. '.lua',
    }
    for _, rel in ipairs(candidates) do
        -- try each as a files.new — if read returns non-empty, it's real
        local f_ok, f = pcall(function() return files.new('../' .. rel, false) end)
        if f_ok and f then
            local rd_ok, src = pcall(function() return f:read() end)
            if rd_ok and type(src) == 'string' and src ~= '' then
                return rel, src
            end
        end
    end
    return nil
end

-- Parse gearswap file text to extract sets.WS["Name"] = { slot="Item" ... }.
-- Returns { [ws_name] = { [slot] = item_string, ... } }.
--
-- This is a REGEX scanner, not a Lua parser. It handles the common gearswap
-- idioms: sets.WS["Name"], sets["WS"]["Name"], sets.WS.Name. Inline augment
-- tables ({ name="X", augments={...} }) are captured as the item's name.
local function _gs_parse_ws_sets(src)
    if type(src) ~= 'string' then return {} end
    local out = {}

    -- Match: sets.WS["Name"] = { ... }  OR  sets.WS.Name = { ... }
    -- We scan block-by-block. Nesting is handled by counting braces manually.
    local i = 1
    local L = #src
    while i <= L do
        local key_s, key_e, ws_name = src:find('sets%.WS%[["\']([^"\']+)["\']%]%s*=%s*{', i)
        local dot_s, dot_e, ws_name_dot
        if not key_s then
            dot_s, dot_e, ws_name_dot = src:find('sets%.WS%.([%w_]+)%s*=%s*{', i)
        end
        local block_start, block_end, ws
        if key_s and (not dot_s or key_s < dot_s) then
            block_start = key_e; ws = ws_name
        elseif dot_s then
            block_start = dot_e; ws = ws_name_dot
        else
            break
        end
        -- Walk from block_start (just after opening '{'), counting braces.
        local depth = 1
        local j = block_start + 1
        while j <= L and depth > 0 do
            local ch = src:sub(j, j)
            if ch == '{' then depth = depth + 1
            elseif ch == '}' then depth = depth - 1
            elseif ch == '"' or ch == "'" then
                -- skip string
                local closer = ch
                j = j + 1
                while j <= L and src:sub(j, j) ~= closer do
                    if src:sub(j, j) == '\\' then j = j + 1 end
                    j = j + 1
                end
            end
            j = j + 1
        end
        local body = src:sub(block_start + 1, j - 2)
        -- Extract slot="Item" and slot={ name="Item", ... }
        local slots = {}
        for slot, item in body:gmatch('(%w+)%s*=%s*"([^"]+)"') do
            slots[slot] = item
        end
        for slot, item in body:gmatch('(%w+)%s*=%s*{[^{}]-name%s*=%s*"([^"]+)"') do
            slots[slot] = item
        end
        out[ws] = slots
        i = j
    end
    return out
end

local function _gs_ensure_loaded(force)
    if not force and CHB.gs.sets and (os.clock() - CHB.gs.last_load) < 30 then
        return CHB.gs.sets
    end
    local path, src = _gs_find_file()
    if not path or not src then return nil end
    CHB.gs.file_path = path
    CHB.gs.sets = _gs_parse_ws_sets(src)
    CHB.gs.last_load = os.clock()
    return CHB.gs.sets
end

-- Recent-hit baseline from scoreboard: pull the last N hit weights for
-- the current player, compute mean + max. Returns nil if not enough data.
local function _gs_baseline_from_scoreboard(min_hits)
    min_hits = min_hits or 5
    local me; pcall(function() me = windower.ffxi.get_player() end)
    if not me then return nil end
    local name = me.name
    -- Scoreboard events are ALL damage, not just WS. Still a useful baseline.
    -- v4.7.9: scoreboard is per-mob now. Aggregate this player's totals
    -- across all tracked mobs for the baseline. Rough, but "recent" enough.
    local total, hits = 0, 0
    if CHB.sb and CHB.sb.by_mob then
        for _, m in pairs(CHB.sb.by_mob) do
            total = total + (m.dmg[name]  or 0)
            hits  = hits  + (m.hits[name] or 0)
        end
    end
    if hits == 0 then total = nil end
    if not total or not hits or hits < min_hits then return nil end
    return { total = total, hits = hits, mean = math.floor(total / hits + 0.5) }
end

local function _gs_cmd_help()
    log_info('gs subcommands:')
    log_info('  //cb gs list                    scan current job file for WS sets')
    log_info('  //cb gs show <WS>               show slot=item map for one set')
    log_info('  //cb gs compare <WS> <A> <B>    diff two sets')
    log_info('  //cb gs sim <WS>                baseline damage from scoreboard')
    log_info('  //cb gs file                    print current gearswap file path')
    log_info('  //cb gs reload                  rescan the file')
end

windower.register_event('addon command', function(cmd, ...)
    if not cmd or cmd:lower() ~= 'gs' then return end
    -- Only handle 'gs' subcommands so we don't clash with per-module commands.
    local args = { ... }
    local sub = (args[1] or ''):lower()

    if sub == '' or sub == 'help' or sub == 'h' then _gs_cmd_help(); return end

    if sub == 'file' then
        local sets = _gs_ensure_loaded()
        log_info('gs file: ' .. tostring(CHB.gs.file_path or 'not found'))
        return
    end
    if sub == 'reload' then
        local sets = _gs_ensure_loaded(true)
        log_info('gs: reloaded. ' ..
            (sets and (tostring((function() local n=0; for _ in pairs(sets) do n=n+1 end; return n end)()) .. ' WS sets found')
                 or 'file not found.'))
        return
    end
    if sub == 'list' then
        local sets = _gs_ensure_loaded()
        if not sets then log_info('gs: no gearswap file loaded; try //cb gs reload'); return end
        local names = {}
        for k in pairs(sets) do names[#names + 1] = k end
        table.sort(names)
        log_info('gs: ' .. #names .. ' WS sets in ' .. tostring(CHB.gs.file_path))
        for _, n in ipairs(names) do
            local slot_count = 0
            for _ in pairs(sets[n]) do slot_count = slot_count + 1 end
            log_info('  ' .. n .. '  [' .. slot_count .. ' slots]')
        end
        return
    end
    if sub == 'show' then
        local sets = _gs_ensure_loaded()
        if not sets then log_info('gs: no gearswap file loaded'); return end
        local wsname = table.concat({select(2, unpack(args))}, ' ')
        if wsname == '' then log_info('usage: //cb gs show <WS name>'); return end
        local set = sets[wsname]
        if not set then log_info('gs: no set named "' .. wsname .. '". Try //cb gs list.'); return end
        log_info('gs show ' .. wsname .. ':')
        for slot, item in pairs(set) do log_info('  ' .. slot .. ' = ' .. item) end
        return
    end
    if sub == 'compare' then
        -- Free-text args: WS name may include spaces; try to split on last two tokens as set names.
        local sets = _gs_ensure_loaded()
        if not sets then log_info('gs: no gearswap file loaded'); return end
        -- Simple form: //cb gs compare <SetA> <SetB> — no WS argument.
        local a, b = args[2], args[3]
        if not a or not b then log_info('usage: //cb gs compare <SetA> <SetB>'); return end
        local sa, sb = sets[a], sets[b]
        if not sa or not sb then log_info('gs: one of ' .. a .. ' / ' .. b .. ' not found. //cb gs list to see names.'); return end
        log_info('gs compare ' .. a .. ' vs ' .. b .. ':')
        local all_slots = {}
        for s in pairs(sa) do all_slots[s] = true end
        for s in pairs(sb) do all_slots[s] = true end
        for s in pairs(all_slots) do
            local ia = sa[s] or '(none)'
            local ib = sb[s] or '(none)'
            if ia ~= ib then log_info(('  %-14s %s  |  %s'):format(s, ia, ib)) end
        end
        return
    end
    if sub == 'sim' then
        local base = _gs_baseline_from_scoreboard()
        if not base then log_info('gs sim: not enough scoreboard data yet. Fight a bit with //cb scoreboard on.'); return end
        log_info(('gs sim baseline (from scoreboard):'))
        log_info(('  hits=%d  total=%d  mean/hit=%d'):format(base.hits, base.total, base.mean))
        log_info(('  (v1 sim only shows current baseline; A/B stat delta needs an item DB — v4.4.1)'))
        return
    end
    _gs_cmd_help()
end)

-- ============================================================================
