-- CHUNK 5: castbar — self-cast progress bar (text-fill, no image sprite).
--
-- v2's cast bar used an image primitive layered behind the job icon and
-- kept losing z-order fights. v3 renders the bar in the same text widget
-- pipeline as everything else — pure text glyphs (█░), no z-order to lose.
--
-- Data source: Windower's 'action' event (parsed 0x028 packet, read-only).
--   category 8  = begin casting spell        -> start tracker
--   category 4  = finish casting spell       -> clear tracker
--   category 15 = interrupted spell          -> clear tracker
--   Different Windower builds have shifted category numbers over the years,
--   so we ALSO clear the tracker whenever the estimated duration expires
--   (safety net so a stale cast never sticks on screen).
--
-- v3.4.1 will add per-party-member cast overlay inside the chharpt rows
-- (same data source, filtered by actor_id in party). v3.4.0 is self-only.
-- ============================================================================

CHB.cast = nil   -- { spell_name, spell_id, started_at, duration } — self
-- v4.3.0: per-party-member cast tracking for chharpt-row overlays.
--   CHB.cast_by_actor[actor_id] = { spell_name, spell_id, started_at, duration, from_ws=false }
CHB.cast_by_actor = {}

local function _spell_cast_time(spell_id)
    if not spell_id then return nil end
    local ok, sp = pcall(function() return res.spells[spell_id] end)
    if not ok or not sp then return nil end
    -- res.spells cast_time is in 1/4-second frames on older Windower builds
    -- and seconds on newer ones. If the value looks like frames (>60 for a
    -- typical spell), divide. Otherwise trust it as seconds.
    local t = tonumber(sp.cast_time) or 0
    if t > 60 then t = t / 4 end
    if t <= 0 then t = 2 end   -- floor so instant-cast spells still show briefly
    return t, sp.en or sp.name or ('spell_' .. spell_id)
end

-- Categories that mean "start of a spell/ability" vs "end". Erring on the
-- side of clearing more than we start prevents ghost casts.
local CAT_CAST_START = { [8]=true }
local CAT_CAST_END   = { [4]=true, [15]=true, [6]=true, [12]=true }

windower.register_event('action', function(a)
    if not a or type(a) ~= 'table' then return end
    local me
    pcall(function() me = windower.ffxi.get_player() end)
    if not me then return end

    -- v4.3.0: track casts for ANY party member (self + p1..p5).
    -- Same category filters as before.
    local is_self = (a.actor_id == me.id)
    local ok_party = false
    if not is_self then
        local ok, party = pcall(function() return windower.ffxi.get_party() end)
        if ok and type(party) == 'table' then
            for k, mm in pairs(party) do
                if type(mm) == 'table' and mm.mob and mm.mob.id == a.actor_id
                        and (k == 'p1' or k == 'p2' or k == 'p3' or k == 'p4' or k == 'p5') then
                    ok_party = true; break
                end
            end
        end
    end
    if not is_self and not ok_party then return end

    if CAT_CAST_START[a.category] then
        local spell_id = a.param
        local dur, name = _spell_cast_time(spell_id)
        if dur then
            local rec = {
                spell_id   = spell_id,
                spell_name = name,
                started_at = os.clock(),
                duration   = dur,
            }
            if is_self then CHB.cast = rec end
            CHB.cast_by_actor[a.actor_id] = rec
        end
    elseif CAT_CAST_END[a.category] then
        if is_self then CHB.cast = nil end
        CHB.cast_by_actor[a.actor_id] = nil
    end
end)

local CastBar = {}
CastBar.name = 'castbar'
CastBar.default = {
    enabled     = true,
    tick_frames = 3,        -- ~20 Hz for a smooth-scrolling bar
    pos_x       = 500,
    pos_y       = 300,
    font_size   = 12,
    opacity     = 220,
    bar_width   = 24,
    auto_hide   = false,    -- casting should show even if a menu is up
}

local COL_CAST_BAR   = '\\cs(255,220,120)'   -- warm yellow
local COL_CAST_DONE  = '\\cs(140,200,255)'   -- cyan (finishing tail)
local COL_CAST_NAME  = '\\cs(255,255,255)'
local COL_CAST_TIME  = '\\cs(200,200,200)'
local COL_CAST_RESET = '\\cr'

local function _cast_render_bar(pct, width)
    local w = tonumber(width) or 24
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local filled = math.floor(pct * w + 0.5)
    if filled > w then filled = w end
    local col = (pct >= 0.9) and COL_CAST_DONE or COL_CAST_BAR
    return col .. string.rep('█', filled) .. string.rep('░', w - filled) .. COL_CAST_RESET
end

function CastBar:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function CastBar:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function CastBar:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end

    local c = CHB.cast
    if not c then
        CHB.hide_widget(self.widget); return
    end

    local elapsed = os.clock() - c.started_at
    local dur     = c.duration or 2
    -- Safety net: if the duration expired ages ago, clear the cast and
    -- don't render — this protects against missed 'end cast' events on
    -- older Windower builds that fire different action categories.
    if elapsed > dur + 1.0 then
        CHB.cast = nil
        CHB.hide_widget(self.widget); return
    end
    local pct = elapsed / dur
    local remaining = math.max(0, dur - elapsed)

    local line1 = string.format('%s%s%s  %s%.1fs%s',
        COL_CAST_NAME, c.spell_name, COL_CAST_RESET,
        COL_CAST_TIME, remaining, COL_CAST_RESET)
    local line2 = _cast_render_bar(pct, self.settings.bar_width)

    CHB.render_text(self.widget, {
        text      = line1 .. '\n' .. line2,
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function CastBar:on_dump()
    local c = CHB.cast
    return {
        widget      = tostring(self.widget),
        active      = c and 'yes' or 'no',
        spell       = c and c.spell_name or '-',
        spell_id    = c and c.spell_id or '-',
        elapsed     = c and string.format('%.2f', os.clock() - c.started_at) or '-',
        duration    = c and string.format('%.2f', c.duration) or '-',
        bar_width   = self.settings.bar_width,
    }
end

function CastBar:on_command(sub, rest)
    if sub == 'width' or sub == 'bar' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb castbar width <8..40>'); return end
        n = math.max(8, math.min(40, math.floor(n)))
        self.settings.bar_width = n
        CHB.save_settings('castbar'); CHB.hard_reset('castbar')
        log_info('castbar: bar_width=' .. n); return
    end
    if sub == 'test' then
        CHB.cast = {
            spell_id   = 0,
            spell_name = 'Fire IV',
            started_at = os.clock(),
            duration   = 5.0,
        }
        log_info('castbar: test cast pushed (5s Fire IV placeholder).')
        return
    end
    if sub == 'clear' then
        CHB.cast = nil
        log_info('castbar: cleared.'); return
    end
    log_info('castbar subcommands: width <n> | test | clear  (generic: on/off/toggle/pos/size/opacity)')
end

CHB.register(CastBar)

-- ============================================================================
