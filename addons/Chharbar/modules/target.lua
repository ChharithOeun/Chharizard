-- MODULE: target — main target + subtarget on a second row.
-- ============================================================================
local Target = {}
Target.name = 'target'
Target.default = {
    enabled     = true,
    tick_frames = 12,
    pos_x       = 500,
    pos_y       = 20,
    font_size   = 10,
    opacity     = 200,
    bar_width   = 36,     -- v3.7.0: 3x wider than previous default (12).
    auto_hide   = true,
}

function Target:on_create()
    self.widget = CHB.new_text_widget(self.settings)
end

function Target:on_destroy()
    if self.widget then
        CHB.sync_drag_pos(self.widget, self)
        pcall(function() self.widget:destroy() end)
        self.widget = nil
    end
end

function Target:on_tick()
    if not self.widget then return end
    CHB.sync_drag_pos(self.widget, self)
    if self.settings.auto_hide and CHB.should_auto_hide() then
        CHB.hide_widget(self.widget); return
    end
    -- v3.2.1: subtarget can be in slot 'st', 'stpt' (party), or 'stal'
    -- (alliance) depending on how the user opened the sub. XivParty
    -- checks all three. Also: "last main target" cache — when you
    -- subtarget a party member for a Cure, FFXI keeps your prior
    -- mob as `t` and puts the party member in `st`. But some spell
    -- prompts swap them (party in `t`, mob still visible via `bt`).
    -- So fall back to `bt` (battle target / last hostile) too.
    local t, st, bt
    pcall(function() t  = windower.ffxi.get_mob_by_target('t')   end)
    pcall(function() st = windower.ffxi.get_mob_by_target('st')  end)
    if not st or not st.name then
        pcall(function() st = windower.ffxi.get_mob_by_target('stpt') end)
    end
    if not st or not st.name then
        pcall(function() st = windower.ffxi.get_mob_by_target('stal') end)
    end
    pcall(function() bt = windower.ffxi.get_mob_by_target('bt') end)

    -- Prefer a hostile bt as the "main" line when we have a friendly
    -- st (e.g., casting Cure on a party member): show mob on top, party
    -- member as the sub row.
    if st and st.name and st.spawn_type == 1 and bt and bt.name
            and (not t or t.spawn_type == 1) then
        t = bt
    end

    if (not t or not t.name) and (not st or not st.name) then
        CHB.hide_widget(self.widget); return
    end
    local parts = {}
    if t and t.name then
        parts[#parts + 1] = _render_one_target(t, self.settings.bar_width, false)
    end
    if st and st.name and st.id and (not t or st.id ~= t.id) then
        parts[#parts + 1] = ''  -- blank spacer between main + sub
        parts[#parts + 1] = _render_one_target(st, self.settings.bar_width, true)
    end
    CHB.render_text(self.widget, {
        text      = table.concat(parts, '\n'),
        pos_x     = self.settings.pos_x,
        pos_y     = self.settings.pos_y,
        font_size = self.settings.font_size,
        opacity   = self.settings.opacity,
    })
end

function Target:on_dump()
    local t, st
    pcall(function() t  = windower.ffxi.get_mob_by_target('t')  end)
    pcall(function() st = windower.ffxi.get_mob_by_target('st') end)
    return {
        widget     = tostring(self.widget),
        target     = t and t.name or 'nil',
        subtarget  = st and st.name or 'nil',
        bar_width  = self.settings.bar_width,
    }
end

function Target:on_command(sub, rest)
    if sub == 'width' or sub == 'bar' then
        local n = tonumber(rest)
        if not n then log_info('usage: //cb target width <6..80>'); return end
        n = math.max(6, math.min(80, n))
        self.settings.bar_width = n
        CHB.save_settings('target'); CHB.hard_reset('target')
        log_info('target: bar_width=' .. n); return
    end
    log_info('target subcommands: width <n>  (generic: on/off/toggle/pos/size/opacity)')
end

CHB.register(Target)

-- ============================================================================
