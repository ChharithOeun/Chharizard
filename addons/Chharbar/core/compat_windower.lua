-- ============================================================================
-- Chharbar / core / compat_windower.lua  (Chharizard v5.4.0+)
--
-- No-op adapter. Windower is Chharbar's native platform — everything already
-- lives at windower.*. This file exists so framework.lua can require an
-- adapter unconditionally on either framework, keeping the load pattern
-- symmetrical.
--
-- Future additions to FW.* that need explicit Windower implementations
-- (e.g. richer packet helpers, unified widget factory) will live here.
-- ============================================================================

-- Sanity check.
assert(type(_G.windower) == 'table',
    '[compat_windower] windower global missing — cannot be on Windower.')

-- Nothing to do. All modules call windower.* directly and it Just Works.
