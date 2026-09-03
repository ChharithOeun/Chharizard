-- MODULE: targetinfo — ID, hex ID, speed% (Arcon's TargetInfo, ported).
-- Uses read-only get_mob_by_target — never injects.
-- ============================================================================
local TargetInfo = {}
TargetInfo.name = 'targetinfo'
TargetInfo.default = {
    enabled     = true,
    tick_frames = 12,
    pos_x       = 500,
    pos_y       = 100,
    font_size   = 10,
    opacity     = 200,
    auto_hide   = true,
}

function TargetInfo:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function TargetInfo:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function TargetInfo:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end
    local mob
    pcall(function()
        mob = windower.ffxi.get_mob_by_target('st')
           or windower.ffxi.get_mob_by_target('t')
    end)
    if not mob or (tonumber(mob.id) or 0) <= 0 then
        CHB.hide_widget(self.widget); return
    end
    local hex_id  = tonumber(mob.index) or 0
    local full_id = tonumber(mob.id) or 0
    local mv     = tonumber(mob.movement_speed) or 0
    local status = tonumber(mob.status) or 0
    -- Arcon's formula:
    --   walking (status 5) or battle-stance (85):  100 * (mv / 4)
    --   otherwise:                                 100 * (mv / 5 - 1)
    local speed_pct
    if status == 5 or status == 85 then
        speed_pct = 100 * (mv / 4)
    else
        speed_pct = 100 * (mv / 5 - 1)
    end
    speed_pct = math.floor(speed_pct + 0.5)
    local speed_col = NC.DIM
    if speed_pct > 0 then speed_col = NC.ON
    elseif speed_pct < 0 then speed_col = NC.OFF end
    local lines = {
        string.format('%sID:     %s%08d%s',      NC.DIM, NC.HEADER, full_id, NC.RESET),
        string.format('%sHex ID: %s%03X%s',      NC.DIM, NC.HEADER, hex_id,  NC.RESET),
        string.format('%sSpeed:  %s%+d%%%s',     NC.DIM, speed_col, speed_pct, NC.RESET),
    }
    CHB.render_text(self.widget, {
        text      = table.concat(lines, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function TargetInfo:on_dump()
    local mob
    pcall(function()
        mob = windower.ffxi.get_mob_by_target('st') or windower.ffxi.get_mob_by_target('t')
    end)
    return {
        widget = tostring(self.widget),
        mob_id = mob and mob.id or 'nil',
        mob_name = mob and mob.name or 'nil',
    }
end

CHB.register(TargetInfo)

-- ============================================================================
