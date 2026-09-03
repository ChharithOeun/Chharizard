-- CHUNK 14: autotarget — <stnpc>/<stmob> auto-expansion for macros.
--
-- Why:
--   FFXI's <stnpc> subtarget has been unreliable across client patches for
--   years — many macros that used to open an NPC picker now open the wrong
--   cursor or fail silently. Third-party addons like "stnpc" and
--   "AutoSelect" work around this by rewriting the command to target the
--   nearest NPC before firing the original action. This chunk bakes that
--   fix directly into Chharbar so all your macros just work again — no
--   extra addon to install, no macro rewriting.
--
-- Tokens handled:
--   <stnpc>    -> nearest valid NPC (spawn_type 2 or 34 with valid_target)
--   <stmob>    -> nearest valid hostile mob (spawn_type 16)
--   <stnpcf>   -> same as <stnpc> but includes NPCs facing you only (v2)
--
-- Mechanic:
--   1. Register 'outgoing text' event.
--   2. If the outgoing text contains a supported token AND is not something
--      we just injected ourselves, find the appropriate nearest entity.
--   3. Send: input /target "Name"; wait 0.25; input <original with token→<t>>
--   4. Return (original, true) to BLOCK the original send.
--
-- Safety:
--   * Read-only on mob array. Never injects packets. Only issues text
--     commands the user could have typed themselves.
--   * If no valid target found, we fall through and let the original
--     command hit the client — same as no-op today.
--
-- Commands:
--   //cb autotarget on|off|toggle
--   //cb autotarget test              try expanding <stnpc> right now
--   //cb autotarget radius <n>        max scan distance (default 30 yards)
--   //cb dev autotarget               dump last-target info
-- ============================================================================

CHB.autotarget = {
    enabled       = true,
    radius        = 30,
    -- v4.6.1: token substitution mode.
    --   't'   = replace <stnpc>/<stmob> with <t>   (native FFXI, default)
    --   'tid' = replace with <tid>                 (Silmaril's target-id
    --                                              token; Silmaril expands
    --                                              it to numeric ID before
    --                                              sending)
    --   'id'  = replace with the literal numeric mob id
    -- Auto-override: if the outgoing text already contains <tid> anywhere,
    -- we use 'tid' regardless of this setting so mixed macros work.
    token         = 't',
    last_hit      = nil,     -- {token, name, id, dist, ts}
    last_expand_at = 0,
}

-- Spawn type filters. Windower's mob table uses these int codes for the
-- .spawn_type field. Different client patches shift the numbers slightly;
-- we keep the "safe" sets and additionally check .is_npc / .is_pc booleans
-- when they exist.
local AT_SPAWN_NPC = { [2] = true, [34] = true }
local AT_SPAWN_MOB = { [16] = true }

local function _at_player_pos()
    local ok, me = pcall(function() return windower.ffxi.get_player() end)
    if not ok or not me then return nil end
    local mok, mm = pcall(function() return windower.ffxi.get_mob_by_id(me.id) end)
    if not mok or not mm then return nil end
    return mm.x, mm.y, mm.z, me.id
end

local function _at_nearest(entity_type)
    local px, py, pz, my_id = _at_player_pos()
    if not px then return nil end
    local ok, mobs = pcall(function() return windower.ffxi.get_mob_array() end)
    if not ok or type(mobs) ~= 'table' then return nil end
    local best, best_dist = nil, math.huge
    local max = (CHB.autotarget.radius or 30) ^ 2
    for _, m in pairs(mobs) do
        if type(m) == 'table' and m.id and m.id ~= my_id and m.name and m.name ~= ''
                and m.valid_target then
            local matches = false
            if entity_type == 'npc' then
                if m.is_npc == true then matches = true
                elseif m.is_pc ~= true and AT_SPAWN_NPC[m.spawn_type or -1] then matches = true
                end
            elseif entity_type == 'mob' then
                if AT_SPAWN_MOB[m.spawn_type or -1] then matches = true
                elseif m.spawn_type and (m.spawn_type == 16) then matches = true
                end
            end
            if matches then
                local dx = (m.x or 0) - px
                local dy = (m.y or 0) - py
                local dz = (m.z or 0) - pz
                local d2 = dx*dx + dy*dy + dz*dz
                if d2 <= max and d2 < best_dist then
                    best, best_dist = m, d2
                end
            end
        end
    end
    if best then
        CHB.autotarget.last_hit = {
            token = entity_type,
            name  = best.name,
            id    = best.id,
            dist  = math.sqrt(best_dist),
            ts    = os.clock(),
        }
    end
    return best
end

-- v4.6.1: determine which token to substitute <stnpc>/<stmob> with.
-- Silmaril users typically want <tid>. If the outgoing text already uses
-- <tid> anywhere we auto-pick 'tid' so mixed-mode macros work.
local function _at_choose_sub(text, target_id)
    local mode = CHB.autotarget.token or 't'
    if text:find('<tid>') then mode = 'tid' end
    if mode == 'tid' then return '<tid>' end
    if mode == 'id'  then return tostring(target_id or 0) end
    return '<t>'
end

-- Rewrite a single text command that contains one or more of our tokens.
-- Returns the composite Windower command string to send (or nil if we
-- can't resolve any target).
local function _at_build_expansion(text)
    -- Which tokens are present?
    local wants = {}
    if text:find('<stnpc>') then wants.npc = true end
    if text:find('<stmob>') then wants.mob = true end
    if not next(wants) then return nil end

    -- Resolve each requested token to a target.
    local npc = wants.npc and _at_nearest('npc') or nil
    local mob = wants.mob and _at_nearest('mob') or nil
    if wants.npc and not npc then
        log_info('autotarget: no NPC within ' .. CHB.autotarget.radius .. 'y')
        return nil
    end
    if wants.mob and not mob then
        log_info('autotarget: no hostile mob within ' .. CHB.autotarget.radius .. 'y')
        return nil
    end

    -- If both tokens are present, we resolve NPC first (most common) then
    -- retarget for mob token — order matters. For the common case (one
    -- token per macro line) this is a single retarget.
    local pieces = {}
    local final_text = text
    if npc then
        pieces[#pieces + 1] = 'input /target "' .. npc.name .. '"'
        final_text = final_text:gsub('<stnpc>', _at_choose_sub(final_text, npc.id))
    end
    if mob then
        pieces[#pieces + 1] = 'input /target "' .. mob.name .. '"'
        final_text = final_text:gsub('<stmob>', _at_choose_sub(final_text, mob.id))
    end
    pieces[#pieces + 1] = 'wait 0.25'
    pieces[#pieces + 1] = 'input ' .. final_text
    return table.concat(pieces, '; ')
end

windower.register_event('outgoing text', function(original, modified, injected, blocked)
    if not CHB.autotarget.enabled then return end
    if blocked then return end
    if injected then return end          -- don't re-expand our own send_command
    local text = modified or original or ''
    if type(text) ~= 'string' or text == '' then return end
    if not (text:find('<stnpc>') or text:find('<stmob>')) then return end

    -- Debounce: prevent double-expansion within 200 ms.
    local now = os.clock()
    if (now - CHB.autotarget.last_expand_at) < 0.2 then return end

    local composite = _at_build_expansion(text)
    if not composite then return end   -- no target; let original pass through

    CHB.autotarget.last_expand_at = now
    windower.send_command(composite)
    return original, true               -- block the original send
end)

windower.register_event('addon command', function(cmd, ...)
    if not cmd or cmd:lower() ~= 'autotarget' then return end
    local args = { ... }
    local sub = (args[1] or ''):lower()
    if sub == '' or sub == 'help' then
        log_info('autotarget subcommands:')
        log_info('  //cb autotarget on|off|toggle')
        log_info('  //cb autotarget test              expand <stnpc> right now')
        log_info('  //cb autotarget radius <n>        scan distance in yards (default 30)')
        log_info('  //cb autotarget token t|tid|id    output token (t=FFXI native, tid=Silmaril)')
        log_info('  //cb autotarget status            show current token mode')
        return
    end
    if sub == 'on' then CHB.autotarget.enabled = true
    elseif sub == 'off' then CHB.autotarget.enabled = false
    elseif sub == 'toggle' then CHB.autotarget.enabled = not CHB.autotarget.enabled end
    if sub == 'on' or sub == 'off' or sub == 'toggle' then
        log_info('autotarget: ' .. (CHB.autotarget.enabled and 'ON' or 'OFF'))
        return
    end
    if sub == 'radius' then
        local n = tonumber(args[2])
        if not n then log_info('usage: //cb autotarget radius <yards>'); return end
        n = math.max(3, math.min(50, math.floor(n)))
        CHB.autotarget.radius = n
        log_info('autotarget: radius=' .. n .. 'y'); return
    end
    if sub == 'token' then
        local m = (args[2] or ''):lower()
        if m ~= 't' and m ~= 'tid' and m ~= 'id' then
            log_info('usage: //cb autotarget token t|tid|id')
            log_info('  t   = <t>   native FFXI target token (default)')
            log_info('  tid = <tid> Silmaril target-id token')
            log_info('  id  = raw numeric mob id')
            return
        end
        CHB.autotarget.token = m
        log_info('autotarget: token=' .. m)
        return
    end
    if sub == 'status' then
        log_info(('autotarget: enabled=%s  token=%s  radius=%dy'):format(
            tostring(CHB.autotarget.enabled), CHB.autotarget.token, CHB.autotarget.radius))
        log_info('  (auto-uses <tid> when input text contains <tid> regardless of token setting)')
        return
    end
    if sub == 'test' then
        local npc = _at_nearest('npc')
        if not npc then log_info('autotarget test: no NPC in range'); return end
        log_info(('autotarget test: nearest NPC = %s (id %d, %.1fy)'):format(
            npc.name, npc.id, math.sqrt(((npc.x - (select(1,_at_player_pos()) or 0))^2))))
        return
    end
    if sub == 'dev' then
        local h = CHB.autotarget.last_hit
        if not h then log_info('autotarget: no expansion yet.'); return end
        log_info(('autotarget last: token=%s name=%s id=%d dist=%.1fy age=%.1fs'):format(
            h.token, h.name, h.id, h.dist, os.clock() - h.ts))
        return
    end
    log_info('autotarget: unknown subcommand. //cb autotarget help')
end)

-- ============================================================================
-- END OF CHUNK 14.
-- ============================================================================
