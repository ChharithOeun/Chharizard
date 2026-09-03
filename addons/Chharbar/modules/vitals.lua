-- MODULE: vitals — HP / MP / TP bars for the player.
--
-- Reference implementation of the v3 module contract. Every future module
-- follows this exact pattern.
--
-- Layout:
--   HP  100% [██████████] 5361/5361
--   MP   96% [██████████] 1116/1163
--   TP  145% [████░░░░░░]  1450/3000
--
-- HP: green / yellow / red by percent.
-- MP: cyan / lavender / purple by percent.
-- TP: yellow (<100%), orange (100-199%), red (200-299%), bright red (300%).
-- ============================================================================
local Vitals = {}
Vitals.name = 'vitals'
Vitals.default = {
    enabled     = true,
    tick_frames = 12,        -- ~5 Hz
    pos_x       = 20,
    pos_y       = 20,
    font_size   = 8,         -- another 10% smaller (v3.1.1)
    opacity     = 255,       -- solid black bg
    bar_width   = 6,         -- slightly wider to compensate for removed % overlay
    auto_hide   = true,      -- hide on menu / macro palette
    strict_hide = true,      -- v4.0.2: also hides on Ctrl/Alt macro palette
                             -- even if CHB.nohide is on globally. Turn off with
                             -- //cb vitals strict off if JoyToKey trigger bleed
                             -- makes it flicker.
}

-- Color codes used inside FFXI text markup.
local COL = {
    RESET  = '\\cr',
    HP_HI  = '\\cs(120,220,120)',   -- green
    HP_MID = '\\cs(240,220,120)',   -- yellow
    HP_LO  = '\\cs(255,110,110)',   -- red
    MP_HI  = '\\cs(140,190,255)',   -- cyan-blue
    MP_MID = '\\cs(200,180,255)',   -- lavender
    MP_LO  = '\\cs(160,100,220)',   -- purple
    TP_LO  = '\\cs(255,235,120)',   -- yellow (< 100%)
    TP_1   = '\\cs(255,200,120)',   -- warm yellow (100-199%)
    TP_2   = '\\cs(255,150, 80)',   -- orange (200-299%)
    TP_3   = '\\cs(255,100, 90)',   -- red (300%)
    LABEL  = '\\cs(220,220,220)',
}

local function _hp_color(pct)
    if pct <= 25 then return COL.HP_LO end
    if pct <= 50 then return COL.HP_MID end
    return COL.HP_HI
end

local function _mp_color(pct)
    if pct <= 24 then return COL.MP_LO end
    if pct <= 50 then return COL.MP_MID end
    return COL.MP_HI
end

local function _tp_color(tp)
    if tp >= 3000 then return COL.TP_3 end
    if tp >= 2000 then return COL.TP_2 end
    if tp >= 1000 then return COL.TP_1 end
    return COL.TP_LO
end

-- v3.1.1: bar without overlay. Format:
--   HP 100% [██████] 3413/3413
-- Percentage is a plain colored text label before the bar; the bar itself
-- shows clean █/░ fill with no text embedded.
local function _row(label, color, cur, max, pct, bar_w)
    local w = tonumber(bar_w) or 10
    local filled = math.floor(math.max(0, math.min(100, pct)) / 100 * w + 0.5)
    if filled > w then filled = w end
    local bar = string.rep('█', filled) .. string.rep('░', w - filled)
    return string.format('%s%s %s%3d%%%s %s[%s%s]%s %s%d/%d%s',
        COL.LABEL, label,
        color, pct, COL.RESET,
        color, bar, color, COL.RESET,
        COL.LABEL, cur, max, COL.RESET)
end

function Vitals:on_create()
    -- Fresh widget every create. No cache, no carry-over.
    self.widget = CHB.new_text_widget(self.settings)
end

function Vitals:on_destroy()
    if self.widget then
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
    -- Sync any drag before destroy so pos is saved.
    if self.widget then CHB.sync_drag_pos(self.widget, self) end
end

function Vitals:on_tick()
    if not self.widget then return end
    -- Read live drag position back into settings so save picks it up.
    CHB.sync_drag_pos(self.widget, self)

    -- v3.0.1: opt-in auto-hide during non-combat menus / macro palette.
    if self.settings.auto_hide then
        if CHB.should_auto_hide() then
            CHB.hide_widget(self.widget); return
        end
        -- v4.0.2: strict_hide adds a keyboard-only hide check that runs even
        -- if the global nohide flag is on. Lets vitals still hide on macro
        -- palette while other modules stay visible under nohide.
        if self.settings.strict_hide and CHB.strict_kbd_hide() then
            CHB.hide_widget(self.widget); return
        end
    end

    local p = windower.ffxi.get_player()
    if not p or type(p.vitals) ~= 'table' then
        CHB.hide_widget(self.widget)
        return
    end
    local v   = p.vitals
    local hp  = tonumber(v.hp)  or 0
    local mp  = tonumber(v.mp)  or 0
    local tp  = tonumber(v.tp)  or 0
    local hpp = tonumber(v.hpp) or 0
    local mpp = tonumber(v.mpp) or 0
    -- Max HP/MP from ratio (game gives us % + current).
    local max_hp = hpp > 0 and math.floor(hp / hpp * 100 + 0.5) or hp
    local max_mp = mpp > 0 and math.floor(mp / mpp * 100 + 0.5) or mp
    local tp_pct = math.floor(tp / 10)

    local bw = self.settings.bar_width or 10
    local lines = {
        _row('HP ', _hp_color(hpp), hp, max_hp, hpp,   bw),
        _row('MP ', _mp_color(mpp), mp, max_mp, mpp,   bw),
        _row('TP ', _tp_color(tp),  tp, 3000,   tp_pct, bw),
    }
    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Vitals:on_dump()
    local live_alpha, live_vis
    if self.widget then
        pcall(function() live_alpha = self.widget:bg_alpha() end)
        pcall(function() live_vis   = self.widget:visible() end)
    end
    return {
        widget      = tostring(self.widget),
        live_alpha  = tostring(live_alpha),
        live_visible = tostring(live_vis),
        bar_width   = self.settings.bar_width,
    }
end

function Vitals:on_command(sub, rest)
    if sub == 'width' or sub == 'bar' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb vitals width <6..40>'); return end
        if n < 6 then n = 6 end
        if n > 40 then n = 40 end
        self.settings.bar_width = n
        CHB.save_settings('vitals')
        CHB.hard_reset('vitals')
        log_info('vitals: bar_width=' .. n)
        return
    end
    if sub == 'strict' then
        -- v4.0.2: toggle strict-hide (Ctrl/Alt macro palette detection).
        local a = (rest or ''):lower()
        if a == 'on'  then self.settings.strict_hide = true
        elseif a == 'off' then self.settings.strict_hide = false
        else self.settings.strict_hide = not self.settings.strict_hide end
        CHB.save_settings('vitals')
        log_info('vitals: strict_hide=' .. tostring(self.settings.strict_hide))
        return
    end
    log_info('vitals subcommands: width <n> | strict on|off  (generic: on/off/toggle/pos/size/opacity)')
end

CHB.register(Vitals)

-- ============================================================================
