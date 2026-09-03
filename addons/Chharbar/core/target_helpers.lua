-- SHARED HELPERS (used by target / distance / targetinfo)
-- ============================================================================

-- Nameplate colors — approximates FFXI's in-game palette.
local NC = {
    NPC       = '\\cs(120,220,120)',   -- green
    PARTY     = '\\cs(120,220,120)',   -- green
    ALLIANCE  = '\\cs(240,200,120)',   -- yellow-orange
    SELF      = '\\cs(255,235,120)',   -- yellow highlight
    PC        = '\\cs(160,220,255)',   -- cyan
    RESET     = '\\cr',
    DIM       = '\\cs(180,180,180)',
    HEADER    = '\\cs(230,230,230)',
    OFF       = '\\cs(255,110,110)',   -- red (low HP)
    MID       = '\\cs(240,220,120)',   -- yellow (mid HP)
    ON        = '\\cs(120,220,120)',   -- green (full HP)
    SUB       = '\\cs(200,180,255)',   -- lavender
}

local function _target_hp_color(pct, is_friend)
    if is_friend then return NC.ON end
    if pct <= 25 then return NC.OFF end
    if pct <= 50 then return NC.MID end
    return NC.ON
end

local function _target_bar(pct, w)
    w = w or 10
    if pct < 0 then pct = 0 end
    if pct > 100 then pct = 100 end
    local filled = math.floor(pct / 100 * w + 0.5)
    return string.rep('█', filled) .. string.rep('░', w - filled)
end

-- Distance from me to any target slot ('t', 'st', 'stpt', 'stal').
-- Returns nil if either side has no position data.
local function _dist_to(slot)
    local ok, mob = pcall(function() return windower.ffxi.get_mob_by_target(slot) end)
    if not ok or not mob then return nil end
    -- Windower gives .distance (already squared) on the mob record — cheap.
    local d = tonumber(mob.distance)
    if d then return math.sqrt(d), mob end
    local ok2, me = pcall(function() return windower.ffxi.get_mob_by_target('me') end)
    if not ok2 or not me or not mob.x or not me.x then return nil, mob end
    local dx = (tonumber(mob.x) or 0) - (tonumber(me.x) or 0)
    local dy = (tonumber(mob.y) or 0) - (tonumber(me.y) or 0)
    return math.sqrt(dx * dx + dy * dy), mob
end

-- Look up job info for a target using every source Windower exposes,
-- preferring the party record (fresh from packet 0xDD) then the mob
-- record fields (populated by /check on some builds).
local function _resolve_target_jobs(t)
    if not t then return nil end
    local out = {
        main_job = t.main_job or (t.mob and t.mob.main_job),
        main_lvl = tonumber(t.main_job_level or (t.mob and t.mob.main_job_level)),
        sub_job  = t.sub_job  or (t.mob and t.mob.sub_job),
        sub_lvl  = tonumber(t.sub_job_level  or (t.mob and t.mob.sub_job_level)),
    }
    -- Self short-circuit — always use get_player() for our own.
    local me
    pcall(function() me = windower.ffxi.get_player() end)
    if me and me.id and t.id == me.id then
        out.main_job = me.main_job
        out.main_lvl = tonumber(me.main_job_level)
        out.sub_job  = me.sub_job
        out.sub_lvl  = tonumber(me.sub_job_level)
        return out
    end
    -- Party lookup by name.
    local ok, party = pcall(function() return windower.ffxi.get_party() end)
    if ok and type(party) == 'table' then
        for _, m in pairs(party) do
            if type(m) == 'table' and m.name == t.name then
                out.main_job = m.main_job or out.main_job
                out.main_lvl = tonumber(m.main_job_level) or out.main_lvl
                out.sub_job  = m.sub_job  or out.sub_job
                out.sub_lvl  = tonumber(m.sub_job_level)  or out.sub_lvl
                return out
            end
        end
    end
    return out
end

-- Classify a target for nameplate color + friendliness.
--   spawn_type 1 = PC, 2 = NPC, 16 = mob.
local function _classify_target(t)
    if not t then return NC.HEADER, false, false end
    local st = tonumber(t.spawn_type) or 0
    if st == 2 then return NC.NPC, true, false end   -- NPC = friendly-ish
    local me
    pcall(function() me = windower.ffxi.get_player() end)
    if me and me.id and t.id == me.id then
        return NC.SELF, true, true
    end
    if t.in_party    then return NC.PARTY,    true,  false end
    if t.in_alliance then return NC.ALLIANCE, true,  false end
    if st == 1 then return NC.PC, false, false end
    return nil, false, false   -- mob: caller uses HP-based color
end

local function _render_one_target(t, bar_w, is_subtarget)
    if not t or not t.name then return '' end
    local hpp = tonumber(t.hpp) or 0
    local st  = tonumber(t.spawn_type) or 0
    local nm  = tostring(t.name):sub(1, 20)
    local prefix = is_subtarget and (NC.DIM .. '  \\-> ' .. NC.RESET) or ''
    local name_color, is_friend, is_self = _classify_target(t)
    local jobs = _resolve_target_jobs(t)
    local job_line = ''
    if jobs and jobs.main_job and jobs.main_lvl and jobs.main_lvl > 0 then
        if jobs.sub_job and jobs.sub_lvl and jobs.sub_lvl > 0 then
            job_line = string.format(' %s%s%d/%s%d%s',
                NC.DIM, jobs.main_job, jobs.main_lvl, jobs.sub_job, jobs.sub_lvl, NC.RESET)
        else
            job_line = string.format(' %s%s%d%s',
                NC.DIM, jobs.main_job, jobs.main_lvl, NC.RESET)
        end
    end
    if st == 2 then
        -- NPC: name + job (if any) — no HP bar.
        return prefix .. (name_color or NC.HEADER) .. nm .. NC.RESET .. job_line
    end
    -- PC / party / self / alliance / mob: name + HP bar + optional MP + optional job.
    local hp_color = _target_hp_color(hpp, is_friend)
    local out = prefix .. (name_color or NC.HEADER) .. nm .. NC.RESET .. job_line
    out = out .. string.format(' %sHP:%3d%%%s [%s%s%s]',
        hp_color, hpp, NC.RESET,
        hp_color, _target_bar(hpp, bar_w), NC.RESET)
    local mpp = tonumber(t.mpp)
    if is_friend and mpp then
        out = out .. string.format(' %sMP:%3d%%%s', NC.SUB, mpp, NC.RESET)
    end
    return out
end

-- ============================================================================
