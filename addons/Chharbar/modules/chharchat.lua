-- CHUNK 10: chharchat — universal chat window (chatmon + battlemod flavor).
--
-- Motivation: FFXI's built-in chat log is one channel; you can't easily
-- separate party from LS from battle spam from tells. Chatmon splits by
-- channel; battlemod compresses combat spam. Chharchat does both.
--
-- Approach:
--   * windower.register_event('text_added') fires for EVERY line about to
--     hit the game chat log, with the mode code. Classify by mode, filter
--     against per-tab whitelist, colorize, prepend optional timestamp,
--     push into a ring buffer, render newest at bottom.
--   * Multiple named tabs, each with its own mode filter + color palette:
--       'all'    — everything except battle noise
--       'party'  — /p, /a, /t (tells received)
--       'ls'     — linkshell 1 + 2
--       'tells'  — incoming /tell only
--       'battle' — combat messages (hits/miss/spells/WS/actions)
--       'system' — announcements, quest, /yell, /say
--   * Only ONE tab visible at a time (like Discord). //cb chharchat tab <name>.
--   * Ring buffer capped (default 200 lines/tab) — old lines drop off.
--
-- FFXI mode codes (windower text_added mode field):
--   0=say 1=shout 2=tell(recv) 3=tell(sent) 4=party 5=linkshell(1)
--   6=emote 7=battle 8=other 9=system 26=linkshell(2) 27=yell 33=alliance
--   ... (varies by client patch; we handle unknowns as 'other')
--
-- Off by default because it's opinionated. //cb chharchat on to try it.
-- ============================================================================

-- v4.7.12: content-based intake — mode integers vary across FFXI/Windower
-- builds so we ignore them entirely. Instead we parse the line TEXT and
-- match characteristic prefixes for tells and linkshell chat. Everything
-- else (say/shout/yell/party/alliance/system/battle) is dropped.
--
-- Tabs are ROSTER-based: each multibox toon gets its own tab, plus 'all'.
-- Configure the roster via //cb chharchat roster add <Name> / remove /list.
CHB.cht_roster = {
    'Chharzilla', 'Chharith', 'Chharutaru', 'Chharlotte',
    'Chharity', 'Chhardonnay', 'Chharburzt',
}
CHB.cht_last_tell_from = nil   -- for //cb chat r "msg"

local function _cht_is_roster(name)
    if type(name) ~= 'string' or name == '' then return false end
    for _, n in ipairs(CHB.cht_roster) do
        if n:lower() == name:lower() then return true end
    end
    return false
end

-- v4.7.12 old mode table kept only for legacy modedbg helper.
-- Whitelist-only — anything not listed here is treated as noise and dropped
-- so battle spam (mode 207 etc) doesn't drown the log.
--
-- Mode integers vary slightly by FFXI client patch and Windower build:
-- if a tell/ls doesn't show up, run //cb chharchat modedbg on, send a test
-- message, note the mode number, and add it here (or ask me to).
local CHT_MODE_CAT = {
    [0]   = 'say',      [1]  = 'shout',
    [2]   = 'tell',     [3]  = 'tellout',    -- also seen as 'party' on some builds
    [4]   = 'party',    [5]  = 'ls',
    [6]   = 'emote',
    [7]   = 'emote',
    [8]   = 'shout',                          -- shout variant
    [9]   = 'tell',                           -- tell variant on some builds
    [11]  = 'shout',
    [26]  = 'ls',                             -- linkshell2
    [27]  = 'yell',
    [33]  = 'alliance',
    [144] = 'party',
    [145] = 'party',
    [148] = 'ls',                             -- linkshell1 variant
    [149] = 'ls',                             -- linkshell1 variant
    [150] = 'ls',                             -- linkshell2 variant
    [151] = 'ls',
}

-- v4.7.11: known battle/system modes we EXPLICITLY DROP so they never
-- reach the tabs. If chharchat feels bare, comment one of these out.
local CHT_DROP_MODES = {
    [149] = false,   -- kept as ls above
    [207] = true, [208] = true, [209] = true, [210] = true, [211] = true,
    [212] = true, [213] = true, [214] = true, [215] = true, [216] = true,
    [217] = true, [218] = true, [219] = true, [220] = true, [221] = true,
    [222] = true, [223] = true, [224] = true, [225] = true, [226] = true,
    [227] = true, [228] = true,       -- battle system range
    [80]  = true, [81] = true, [82] = true, [83] = true, [84] = true,
                                       -- action / experience
    [123] = true, [124] = true,       -- item found / obtained
    [30]  = true, [31] = true,        -- extra system
}

-- Foreground colors per category (RGB triples).
local CHT_COLORS = {
    say      = {200,200,200},
    shout    = {255,140,140},
    tell     = {255,200,255},
    tellout  = {200,180,255},
    party    = {180,255,180},
    alliance = {150,220,150},
    ls       = {170,220,255},
    emote    = {200,160,120},
    battle   = {160,160,160},
    other    = {180,180,180},
    system   = {255,220,120},
    yell     = {255,180, 90},
}

-- v4.7.12: buffers are keyed by tab NAME (roster toon + 'all').
CHB.cht_buffers = {}

local function _cht_tab_order()
    local out = { 'all' }
    for _, n in ipairs(CHB.cht_roster) do out[#out + 1] = n end
    return out
end

local function _cht_ensure_buffers()
    for _, tab in ipairs(_cht_tab_order()) do
        if not CHB.cht_buffers[tab] then CHB.cht_buffers[tab] = {} end
    end
end
_cht_ensure_buffers()

local function _cht_cat_for_mode(mode)
    local m = tonumber(mode) or -1
    if CHT_DROP_MODES[m] then return nil end     -- v4.7.11: filter noise
    return CHT_MODE_CAT[m] or nil                -- unknown -> also drop (whitelist-only)
end

-- Strip FFXI control codes and normalize whitespace for our own rendering.
local function _cht_clean(text)
    if type(text) ~= 'string' then return '' end
    -- FFXI text may carry auto-translate + inline color codes; drop the
    -- non-printable range aggressively for consistent formatting.
    text = text:gsub('[%z\1-\8\11-\31\127]', '')
    return text
end

-- v4.7.13: content-based line classifier. Broader patterns to handle
-- FFXI text variants (with/without space before colon, mixed punctuation).
local function _cht_classify(text)
    if type(text) ~= 'string' or text == '' then return nil end
    -- Incoming tell:
    --   ">>Sender: body"      (no space)
    --   ">>Sender : body"     (space before colon)
    --   ">> Sender: body"     (space after arrows)
    local sender, body = text:match('^%s*>>%s*([%w%.%-_]+)%s*:%s*(.*)$')
    if sender then return 't_in', sender, body end
    -- Outgoing tell: "SenderName>>Recipient : body"
    local from, to
    from, to, body = text:match('^%s*([%w%.%-_]+)%s*>>%s*([%w%.%-_]+)%s*:%s*(.*)$')
    if from and to then
        local me = (me_name() or ''):lower()
        if from:lower() == me then return 't_out', to, body end
        if to:lower()   == me then return 't_in',  from, body end
    end
    -- LS1 formats:
    --   "<Sender> body"
    --   "[LSName]Sender : body"
    --   "[LSName] Sender : body"
    sender, body = text:match('^%s*<([%w%.%-_]+)>%s*(.*)$')
    if sender then return 'ls', sender, body end
    sender, body = text:match('^%s*%[([^%]]+)%]%s*([%w%.%-_]+)%s*:%s*(.*)$')
    if sender then
        -- return the SENDER, not the LS name — user wants to see who spoke.
        return 'ls', body:match('^(%S+)') or sender, body
    end
    -- LS2 — most builds share the LS pattern; distinguishing is hard without
    -- mode. If a chat line matches "«Name»" (UTF-8 guillemets), tag as ls2.
    sender, body = text:match('^%s*\194\171([%w%.%-_]+)\194\187%s*(.*)$')
    if sender then return 'ls2', sender, body end
    return nil
end

local function _cht_push(text)
    if type(text) ~= 'string' or text == '' then return end
    text = _cht_clean(text)
    if text == '' then return end
    local kind, other, body = _cht_classify(text)
    if not kind then return end
    -- Roster filter: only show comms involving our multibox toons.
    -- (LS is included even from non-roster senders — user wants LS chat.)
    if (kind == 't_in' or kind == 't_out') and not _cht_is_roster(other) then
        -- Non-roster tell — still show but under 'all' tab only.
    end
    if kind == 't_in' then CHB.cht_last_tell_from = other end
    local entry = {
        ts    = os.clock(),
        kind  = kind,
        other = other or '?',
        body  = body or '',
    }
    _cht_ensure_buffers()
    -- Always append to 'all'
    local cap = (CHB.settings.chharchat and CHB.settings.chharchat.capacity) or 200
    local function _append(tab)
        local buf = CHB.cht_buffers[tab]
        if not buf then return end
        buf[#buf + 1] = entry
        if #buf > cap then table.remove(buf, 1) end
    end
    _append('all')
    -- Also append to per-toon tab if it's a roster member
    if _cht_is_roster(other) then _append(other) end
end

CHB.cht_mode_dbg      = false  -- v4.7.3: //cb chharchat modedbg logs every mode
CHB.cht_raw_dbg       = false  -- v4.7.13: //cb chharchat raw logs full text + hex prefix
CHB.cht_events_seen   = 0      -- v4.7.10: heartbeat counter
CHB.cht_last_event    = ''     -- last event name that fired (for diagnostic)

local function _cht_hex_prefix(s, n)
    n = n or 16
    if type(s) ~= 'string' then return '' end
    local out = {}
    for i = 1, math.min(#s, n) do
        out[#out + 1] = string.format('%02x', string.byte(s, i))
    end
    return table.concat(out, ' ')
end

local function _cht_intake(event_name, original, modified, mode, blocked, ...)
    if blocked then return end
    CHB.cht_events_seen = CHB.cht_events_seen + 1
    CHB.cht_last_event  = event_name
    local raw = modified or original or ''
    if CHB.cht_mode_dbg then
        local sample = tostring(raw):sub(1, 60)
        log_info(('chat[%s] mode=%s : %s'):format(event_name, tostring(mode), sample))
    end
    -- v4.7.13: raw dump — writes full text + hex prefix to debug log so we
    -- can see FFXI's chat channel bytes and pinpoint why tell/ls patterns
    -- don't match. Turn on before sending a /tell, then `//cb log 30`.
    if CHB.cht_raw_dbg then
        pcall(function()
            CHB.log(('CHT-RAW event=%s mode=%s hex=[%s] text=%q'):format(
                event_name, tostring(mode), _cht_hex_prefix(raw, 20), tostring(raw)))
        end)
    end
    local mod = CHB.modules and CHB.modules.chharchat
    if not mod or not mod.settings or mod.settings.enabled == false then return end
    -- v4.7.12: content-based classifier — ignore mode entirely.
    _cht_push(raw)
end

-- v4.7.10: register on BOTH text_added and incoming text. Different
-- Windower builds fire different events for chat lines. Whichever runs
-- gets logged; whichever runs first pushes to the buffer.
windower.register_event('text_added', function(original, modified, mode, blocked)
    _cht_intake('text_added', original, modified, mode, blocked)
end)
pcall(function()
    windower.register_event('incoming text', function(original, modified, original_mode, modified_mode, blocked)
        _cht_intake('incoming text', original, modified, modified_mode or original_mode, blocked)
    end)
end)

local Chharchat = {}
Chharchat.name = 'chharchat'
Chharchat.default = {
    enabled     = true,         -- v4.7.7: on by default; user hides + saves
    tick_frames = 6,            -- ~10 Hz
    pos_x       = 20,
    pos_y       = 700,
    font_size   = 10,
    opacity     = 200,
    auto_hide   = false,
    tab         = 'all',        -- current visible tab
    lines_shown = 12,           -- how many recent lines to render
    show_time   = true,         -- prefix HH:MM
    capacity    = 200,          -- ring buffer size per tab
}

local function _cht_fmt_time(ts_unused)
    -- os.date has HH:MM:SS
    return os.date('%H:%M')
end

local function _cht_color_prefix(cat)
    local c = CHT_COLORS[cat] or CHT_COLORS.other
    return string.format('\\cs(%d,%d,%d)', c[1], c[2], c[3])
end

function Chharchat:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function Chharchat:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function Chharchat:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    _cht_ensure_buffers()
    local order = _cht_tab_order()
    local tab = self.settings.tab or 'all'
    if not CHB.cht_buffers[tab] then tab = 'all' end
    local buf = CHB.cht_buffers[tab] or {}
    local n = math.min(self.settings.lines_shown or 12, #buf)

    -- v4.7.12: header is roster-toon list (not category names).
    local header_parts = {}
    for _, t in ipairs(order) do
        if t == tab then
            header_parts[#header_parts + 1] = '\\cs(255,220,120)[' .. t .. ']\\cr'
        else
            header_parts[#header_parts + 1] = '\\cs(140,140,140)' .. t .. '\\cr'
        end
    end
    local lines = { table.concat(header_parts, ' | ') }

    -- v4.7.12: render format is [time] [>>/<<] [t/ls/ls2] Name : body
    local KIND_TAG   = { t_in = '>>', t_out = '<<', ls = '--', ls2 = '--' }
    local KIND_CHAN  = { t_in = 't',  t_out = 't',  ls = 'ls', ls2 = 'ls2' }
    local KIND_COLOR = {
        t_in  = '\\cs(255,200,255)',
        t_out = '\\cs(200,180,255)',
        ls    = '\\cs(170,220,255)',
        ls2   = '\\cs(140,255,180)',
    }

    for i = #buf - n + 1, #buf do
        if i >= 1 then
            local e = buf[i]
            local timestr = ''
            if self.settings.show_time then
                timestr = '\\cs(120,120,120)[' .. _cht_fmt_time() .. ']\\cr '
            end
            local tag  = KIND_TAG[e.kind]  or '--'
            local chan = KIND_CHAN[e.kind] or '?'
            local col  = KIND_COLOR[e.kind] or '\\cs(200,200,200)'
            lines[#lines + 1] = string.format(
                '%s\\cs(200,180,60)[%s]\\cr \\cs(200,180,60)[%s]\\cr \\cs(255,255,180)%-10s\\cr : %s%s\\cr',
                timestr, tag, chan, e.other or '?', col, e.body or '')
        end
    end

    if #lines == 1 then
        -- header only; append hint line so widget isn't empty
        lines[#lines + 1] = '\\cs(120,120,120)(no messages)\\cr'
    end

    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Chharchat:on_dump()
    _cht_ensure_buffers()
    local pieces = {}
    for _, tab in ipairs(_cht_tab_order()) do
        pieces[#pieces + 1] = tab .. '=' .. tostring(#(CHB.cht_buffers[tab] or {}))
    end
    return {
        widget         = tostring(self.widget),
        tab            = self.settings.tab,
        lines          = self.settings.lines_shown,
        capacity       = self.settings.capacity,
        roster         = table.concat(CHB.cht_roster, ', '),
        last_tell_from = tostring(CHB.cht_last_tell_from),
        buffer_by_tab  = table.concat(pieces, ' '),
    }
end

function Chharchat:on_command(sub, rest)
    if sub == 'tab' then
        local a = rest or ''
        -- Case-insensitive match against roster + 'all'
        local pick
        if a:lower() == 'all' then pick = 'all' end
        if not pick then
            for _, n in ipairs(CHB.cht_roster) do
                if n:lower() == a:lower() then pick = n; break end
            end
        end
        if not pick then
            log_info('chharchat: tab must be "all" or a roster toon: ' .. table.concat(CHB.cht_roster, ', '))
            return
        end
        self.settings.tab = pick
        CHB.save_settings('chharchat')
        log_info('chharchat: tab=' .. pick); return
    end
    if sub == 'roster' then
        local action, name = rest:match('^(%S+)%s*(.*)$')
        action = (action or ''):lower()
        if action == 'list' or action == '' then
            log_info('chharchat roster: ' .. table.concat(CHB.cht_roster, ', ')); return
        end
        if action == 'add' and name and name ~= '' then
            for _, n in ipairs(CHB.cht_roster) do if n:lower() == name:lower() then log_info('roster: already has ' .. n); return end end
            CHB.cht_roster[#CHB.cht_roster + 1] = name
            _cht_ensure_buffers()
            log_info('roster: added ' .. name); return
        end
        if action == 'remove' or action == 'rm' and name and name ~= '' then
            for i, n in ipairs(CHB.cht_roster) do
                if n:lower() == name:lower() then
                    table.remove(CHB.cht_roster, i)
                    CHB.cht_buffers[n] = nil
                    log_info('roster: removed ' .. n); return
                end
            end
            log_info('roster: no such name ' .. name); return
        end
        log_info('usage: //cb chharchat roster [list|add <Name>|remove <Name>]'); return
    end
    if sub == 'lines' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb chharchat lines <4..40>'); return end
        n = math.max(4, math.min(40, math.floor(n)))
        self.settings.lines_shown = n
        CHB.save_settings('chharchat'); CHB.hard_reset('chharchat')
        log_info('chharchat: lines_shown=' .. n); return
    end
    if sub == 'cap' or sub == 'capacity' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb chharchat cap <50..1000>'); return end
        n = math.max(50, math.min(1000, math.floor(n)))
        self.settings.capacity = n
        CHB.save_settings('chharchat')
        log_info('chharchat: capacity=' .. n); return
    end
    if sub == 'time' then
        self.settings.show_time = not self.settings.show_time
        CHB.save_settings('chharchat')
        log_info('chharchat: show_time=' .. tostring(self.settings.show_time)); return
    end
    if sub == 'clear' then
        for _, tab in ipairs(_cht_tab_order()) do CHB.cht_buffers[tab] = {} end
        log_info('chharchat: all buffers cleared.'); return
    end
    if sub == 'modedbg' then
        local a = (rest or ''):lower()
        if a == 'on' then CHB.cht_mode_dbg = true
        elseif a == 'off' then CHB.cht_mode_dbg = false
        else CHB.cht_mode_dbg = not CHB.cht_mode_dbg end
        log_info('chharchat mode-debug -> ' .. (CHB.cht_mode_dbg and 'ON (each chat line logs its mode code)' or 'OFF'))
        return
    end
    if sub == 'raw' then
        local a = (rest or ''):lower()
        if a == 'on' then CHB.cht_raw_dbg = true
        elseif a == 'off' then CHB.cht_raw_dbg = false
        else CHB.cht_raw_dbg = not CHB.cht_raw_dbg end
        log_info('chharchat raw dump -> ' .. (CHB.cht_raw_dbg and 'ON (every chat line written to data/chharbar.log with hex+text)' or 'OFF'))
        return
    end
    if sub == 'stats' then
        log_info(('chharchat: text_added/incoming-text events seen so far = %d'):format(CHB.cht_events_seen))
        log_info(('chharchat: last event was "%s"'):format(CHB.cht_last_event or '(none)'))
        if CHB.cht_events_seen == 0 then
            log_info('chharchat: NEITHER event has fired since load — this Windower build may not expose chat text events at all. Talk to yourself in /say to test.')
        end
        return
    end
    if sub == 'test' then
        _cht_push('>>Chharlotte: heals inc')
        _cht_push('Chharzilla>>Chharlotte: thanks')  -- outgoing tell
        _cht_push('<Chharutaru> anyone up for Ambu?')
        _cht_push('<Chhardonnay> ready when you are')
        _cht_push('yell',     'Vagrant: LFG bcnm anyone?')
        _cht_push('shout',    'Somebody: WTS a chunk of ore')
        log_info('chharchat: 7 test lines pushed across tabs.'); return
    end
    log_info('chharchat subcommands: tab <name> | lines <n> | cap <n> | time | clear | test | modedbg on|off')
    log_info('  tabs: ' .. table.concat(CHT_TAB_ORDER, ', '))
end

CHB.register(Chharchat)

-- ============================================================================
