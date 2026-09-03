-- CHUNK 13: silmaril — Silmaril multibox tool integration hooks.
--
-- Silmaril is the user's multibox controller. From the diag we saw it
-- listening on 127.0.0.1:61981 as an HTTP-like local service. This module
-- lets Chharbar cooperate with it:
--
--   * Detect Silmaril presence (local port open?).
--   * Query the roster of PCs Silmaril knows about.
--   * Send a same-command-to-all broadcast via Silmaril's tell relay.
--
-- SECURITY / SAFETY:
--   * All traffic to Silmaril is over 127.0.0.1 (loopback). No remote.
--   * We DO NOT store or ship any Silmaril key. Anything auth-gated goes
--     through Silmaril's own auth — we just hand it commands.
--   * We use send_command('input //<cmd>') style, not packet injection.
--
-- Implementation is deliberately minimal: a tiny HTTP GET helper using
-- Windower's `socket` lib. On builds where socket isn't loadable, all
-- functions no-op cleanly and //cb sil status reports "unavailable".
-- ============================================================================

CHB.sil = {
    host    = '127.0.0.1',
    port    = 61981,
    last_ok = 0,
    online  = false,
    roster  = {},   -- list of toon names Silmaril knows
}

local function _sil_socket()
    -- Try LuaSocket via Windower's bundled lib. Not all builds ship it.
    local ok, socket = pcall(require, 'socket')
    if not ok then return nil end
    return socket
end

local function _sil_http_get(path, timeout)
    local socket = _sil_socket()
    if not socket then return nil, 'socket lib unavailable' end
    local c, err = socket.tcp()
    if not c then return nil, tostring(err) end
    c:settimeout(timeout or 1.5)
    local ok, cerr = c:connect(CHB.sil.host, CHB.sil.port)
    if not ok then c:close(); return nil, 'connect: ' .. tostring(cerr) end
    local req = ('GET %s HTTP/1.0\r\nHost: %s:%d\r\nUser-Agent: Chharbar/4.5.0\r\n\r\n'):format(
        path, CHB.sil.host, CHB.sil.port)
    c:send(req)
    local buf, part = {}
    while true do
        part, cerr = c:receive('*l')
        if not part then break end
        buf[#buf + 1] = part
    end
    c:close()
    local body = table.concat(buf, '\n')
    return body
end

local function _sil_ping()
    -- Simple availability check. Any HTTP response = "online" for our purpose.
    local body, err = _sil_http_get('/', 0.8)
    CHB.sil.online = (body ~= nil)
    if CHB.sil.online then CHB.sil.last_ok = os.clock() end
    return CHB.sil.online, err
end

local function _sil_roster()
    -- Silmaril's key manager displays roster in Player 1..18. We don't have
    -- documented HTTP endpoints, so best-effort: parse any HTML/JSON at /
    -- for name-like strings. Falls back to windower.ffxi party if empty.
    local body = _sil_http_get('/', 1.0)
    local names = {}
    if body and body ~= '' then
        for n in body:gmatch('[Cc]hhar%w+') do names[#names + 1] = n end
    end
    if #names == 0 then
        -- Fallback: use current party as a proxy roster
        local ok, party = pcall(function() return windower.ffxi.get_party() end)
        if ok and type(party) == 'table' then
            for _, m in pairs(party) do
                if type(m) == 'table' and m.name then names[#names + 1] = m.name end
            end
        end
    end
    -- Dedupe preserving order
    local seen, uniq = {}, {}
    for _, n in ipairs(names) do
        if not seen[n] then seen[n] = true; uniq[#uniq + 1] = n end
    end
    CHB.sil.roster = uniq
    return uniq
end

-- Broadcast a FFXI text command to every roster member via /tell relay.
-- Uses Silmaril's own tell-based command routing (if configured). Also
-- runs the command locally on THIS toon.
local function _sil_broadcast(cmd)
    if not cmd or cmd == '' then return end
    -- Run locally
    windower.send_command('input //' .. cmd)
    -- Ask Silmaril to fan-out. We simply /tell each roster member the
    -- command prefixed with the Silmaril router token — the exact token is
    -- Silmaril-side; we default to '!!' which is common but user can
    -- override via //cb sil prefix <string>.
    local prefix = (CHB.settings.silmaril and CHB.settings.silmaril.prefix) or '!!'
    local roster = CHB.sil.roster
    if #roster == 0 then _sil_roster() end
    local me; pcall(function() me = windower.ffxi.get_player() end)
    for _, name in ipairs(CHB.sil.roster) do
        if not me or name ~= me.name then
            windower.send_command(('input /tell %s %s%s'):format(name, prefix, cmd))
        end
    end
end

windower.register_event('addon command', function(cmd, ...)
    if not cmd or cmd:lower() ~= 'sil' then return end
    local args = { ... }
    local sub = (args[1] or ''):lower()

    if sub == '' or sub == 'help' or sub == 'h' then
        log_info('sil subcommands:')
        log_info('  //cb sil status                 check Silmaril reachability')
        log_info('  //cb sil roster                 refresh + list toons Silmaril knows')
        log_info('  //cb sil bcast <cmd>            broadcast //cmd to every roster toon via /tell')
        log_info('  //cb sil prefix <str>           set the router prefix (default "!!")')
        return
    end
    if sub == 'status' then
        local ok, err = _sil_ping()
        if ok then log_info('sil: online at ' .. CHB.sil.host .. ':' .. CHB.sil.port)
        else log_info('sil: unreachable (' .. tostring(err) .. ')') end
        return
    end
    if sub == 'roster' then
        local r = _sil_roster()
        log_info('sil roster (' .. #r .. '):')
        for _, n in ipairs(r) do log_info('  ' .. n) end
        return
    end
    if sub == 'bcast' or sub == 'broadcast' then
        local rest = table.concat({select(2, unpack(args))}, ' ')
        if rest == '' then log_info('usage: //cb sil bcast <cmd>'); return end
        _sil_broadcast(rest)
        log_info('sil: broadcast //' .. rest .. ' to ' .. #CHB.sil.roster .. ' toons.')
        return
    end
    if sub == 'prefix' then
        local p = args[2]
        if not p then log_info('usage: //cb sil prefix <string>'); return end
        CHB.settings.silmaril = CHB.settings.silmaril or {}
        CHB.settings.silmaril.prefix = p
        log_info('sil: prefix set to "' .. p .. '"')
        return
    end
    log_info('sil: unknown subcommand. //cb sil help')
end)

-- Background ping every 30s (cheap; loopback) to keep online status fresh.
CHB.sil.next_ping = 0
windower.register_event('prerender', function()
    local now = os.clock()
    if now < CHB.sil.next_ping then return end
    CHB.sil.next_ping = now + 30
    pcall(_sil_ping)
end)

-- ============================================================================
