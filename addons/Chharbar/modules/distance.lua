-- MODULE: distance — yards from player to target (and subtarget when present).
-- ============================================================================
local Distance = {}
Distance.name = 'distance'
Distance.default = {
    enabled     = true,
    tick_frames = 12,
    pos_x       = 500,
    pos_y       = 60,
    font_size   = 10,
    opacity     = 200,
    auto_hide   = true,
}

local function _dist_color(d)
    if not d then return NC.DIM end
    if d < 3   then return NC.ON  end
    if d <= 10 then return NC.MID end
    return NC.OFF
end

function Distance:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function Distance:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function Distance:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end
    local d_t,  t  = _dist_to('t')
    local d_st, st = _dist_to('st')
    if (not t or not t.name) and (not st or not st.name) then
        CHB.hide_widget(self.widget); return
    end
    local parts = {}
    if t and t.name and d_t then
        parts[#parts + 1] = string.format('%sDist: %.1fy%s',
            _dist_color(d_t), d_t, NC.RESET)
    end
    if st and st.name and st.id and (not t or st.id ~= t.id) and d_st then
        parts[#parts + 1] = string.format('%s\\-> %.1fy%s',
            _dist_color(d_st), d_st, NC.RESET)
    end
    if #parts == 0 then CHB.hide_widget(self.widget); return end
    CHB.render_text(self.widget, {
        text      = table.concat(parts, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Distance:on_dump()
    local d_t = _dist_to('t')
    local d_st = _dist_to('st')
    return {
        widget      = tostring(self.widget),
        dist_target = d_t and string.format('%.2f', d_t) or 'nil',
        dist_subt   = d_st and string.format('%.2f', d_st) or 'nil',
    }
end

CHB.register(Distance)

-- ============================================================================
