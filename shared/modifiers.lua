-- =============================================================================
-- COREX Skills :: shared/modifiers.lua
-- =============================================================================
-- Translates the unlocked-skill set into a flat, gameplay-ready modifier table
-- consumed by every other resource (corex-survival, corex-inventory,
-- corex-crafting, corex-zombies). One source of truth so balance stays in sync.
--
--   * `mul`  modifiers multiply together (1.0 baseline; lower-is-better keys
--            like `weaponRecoil` use values < 1.0).
--   * `add`  modifiers sum (0.0 baseline; e.g. `plagueResist` 0..1).
--   * `or`   modifiers OR together (boolean flags / gates).
-- =============================================================================

CorexSkills = CorexSkills or {}

CorexSkills.MOD_DEFAULTS = {
    -- Combat ------------------------------------------------------------------
    weaponSway       = { default = 1.0,   kind = 'mul' },  -- lower = steadier
    weaponRecoil     = { default = 1.0,   kind = 'mul' },  -- lower = less kick
    reloadSpeed      = { default = 1.0,   kind = 'mul' },  -- lower = faster reload (multiplies duration)
    aimSpeed         = { default = 1.0,   kind = 'mul' },  -- lower = ADS faster
    headshotDamage   = { default = 1.0,   kind = 'mul' },  -- higher = bigger headshots
    finishingDamage  = { default = 1.0,   kind = 'mul' },  -- damage vs <30% HP targets
    weaponDamage     = { default = 1.0,   kind = 'mul' },  -- general damage modifier (akimbo etc.)
    fireRate         = { default = 1.0,   kind = 'mul' },  -- higher = faster

    -- Survivor ----------------------------------------------------------------
    maxHealth        = { default = 1.0,   kind = 'mul' },  -- higher = more HP
    staminaRegen     = { default = 1.0,   kind = 'mul' },  -- higher = faster regen
    sprintCost       = { default = 1.0,   kind = 'mul' },  -- lower = cheaper sprint
    hungerDrain      = { default = 1.0,   kind = 'mul' },  -- lower = drains slower
    thirstDrain      = { default = 1.0,   kind = 'mul' },  -- lower = drains slower
    coldDamage       = { default = 1.0,   kind = 'mul' },  -- lower = takes less cold dmg
    bleedRate        = { default = 1.0,   kind = 'mul' },  -- lower = stops bleeding faster
    infectionGrowth  = { default = 1.0,   kind = 'mul' },  -- lower = infection grows slower
    biteChance       = { default = 1.0,   kind = 'mul' },  -- lower = harder to get bitten
    plagueResist     = { default = 0.0,   kind = 'add' },  -- additive 0..1, % blocked
    biteImmunity     = { default = false, kind = 'or'  },  -- full bite immunity flag
    bandageHeal      = { default = 1.0,   kind = 'mul' },  -- higher = bigger heal
    antibioticPower  = { default = 1.0,   kind = 'mul' },  -- higher = stronger antibiotics

    -- Craftsman ---------------------------------------------------------------
    craftSpeed       = { default = 1.0,   kind = 'mul' },  -- higher = faster crafting (we DIVIDE duration by this)
    materialCost     = { default = 1.0,   kind = 'mul' },  -- lower = uses less mats
    buildDurability  = { default = 1.0,   kind = 'mul' },  -- higher = stronger builds
    carryWeight      = { default = 1.0,   kind = 'mul' },  -- lower = items feel lighter
    lockpickSpeed    = { default = 1.0,   kind = 'mul' },  -- higher = faster minigame
    weaponModCost    = { default = 1.0,   kind = 'mul' },  -- lower = cheaper attachments
    instaBuildChance = { default = 0.0,   kind = 'add' },  -- additive 0..1, free-craft chance
    unlocksRareRecipes = { default = false, kind = 'or' }, -- gate flag for blueprints
    unlocksWeaponMods  = { default = false, kind = 'or' }  -- gate flag for modder bench
}

-- Per-skill effect table. Key = skill id from shared/skills.lua.
-- Each entry sets one or more modifier keys; the aggregator combines them
-- according to the kind in MOD_DEFAULTS above.
CorexSkills.SKILL_EFFECTS = {
    -- COMBAT ------------------------------------------------------------------
    -- Recoil reduction stacks aggressively across the branch so the capstone
    -- feels FUNDAMENTALLY different, not just "a bit better":
    --   c_steady  alone           : weaponRecoil 0.85   = -15%   (subtle)
    --   c_recoil  alone           : weaponRecoil 0.50   = -50%   (clearly steadier)
    --   c_recoil + c_exec (capstone) : 0.50 * 0.05      = 0.025  = -97.5% — laser-flat
    --   all three (full path)        : 0.85 * 0.50 * 0.05 = 0.021 = -98%
    --
    -- The corex-inventory recoil dampener also enters "laser mode" whenever
    -- weaponRecoil <= 0.30 (i.e. anyone who unlocked c_exec): it zeroes the
    -- additive recoil offset every frame and stops gameplay-cam shake. Net
    -- effect: the master sight basically doesn't move on full-auto fire.
    c_steady  = { weaponSway = 0.75, weaponRecoil = 0.85 },
    c_reload  = { reloadSpeed = 0.80 },
    c_iron    = { aimSpeed = 0.70 },
    c_head    = { headshotDamage = 1.30 },
    c_recoil  = { weaponRecoil = 0.50 },
    c_akimbo  = { fireRate = 1.40, weaponDamage = 0.85 },
    c_exec    = { finishingDamage = 2.0, weaponRecoil = 0.05 },

    -- SURVIVOR ----------------------------------------------------------------
    s_tough       = { maxHealth = 1.20 },                  -- +20% HP
    s_endurance   = { staminaRegen = 1.30, sprintCost = 0.75 },
    s_iron_body   = { hungerDrain = 0.65, thirstDrain = 0.65 },
    s_cold        = { coldDamage = 0.50 },
    s_bleed       = { bleedRate = 0.50 },
    s_plague      = { biteChance = 0.50, plagueResist = 0.50 },
    s_immunity    = { biteChance = 0.25, plagueResist = 0.75, biteImmunity = true },

    -- CRAFTSMAN ---------------------------------------------------------------
    k_quick    = { craftSpeed = 1.25 },                    -- +25% craft speed
    k_material = { materialCost = 0.80 },                  -- -20% materials
    k_solid    = { buildDurability = 1.30 },               -- +30% durability
    k_master   = { unlocksRareRecipes = true, buildDurability = 1.15 },
    k_lock     = { lockpickSpeed = 1.50 },                 -- +50% minigame speed
    k_modder   = { unlocksWeaponMods = true, weaponModCost = 0.80 },
    k_insta    = { instaBuildChance = 0.20 }               -- 20% free-craft
}

-- Returns a fresh, neutral modifier table (used by consumers when corex-skills
-- is missing / player still loading — keeps gameplay running unchanged).
function CorexSkills.NeutralModifiers()
    local mods = {}
    for key, def in pairs(CorexSkills.MOD_DEFAULTS) do
        mods[key] = def.default
    end
    return mods
end

-- Aggregate every unlocked skill's effect into one flat modifier table.
-- `unlockedList` is the array of skill ids stored on the player.
function CorexSkills.ComputeModifiers(unlockedList)
    local mods = CorexSkills.NeutralModifiers()
    if type(unlockedList) ~= 'table' then return mods end

    for _, id in ipairs(unlockedList) do
        local effects = CorexSkills.SKILL_EFFECTS[id]
        if effects then
            for key, val in pairs(effects) do
                local def = CorexSkills.MOD_DEFAULTS[key]
                if def then
                    if def.kind == 'mul' then
                        mods[key] = (mods[key] or 1.0) * val
                    elseif def.kind == 'add' then
                        mods[key] = (mods[key] or 0.0) + val
                    elseif def.kind == 'or' then
                        mods[key] = mods[key] or val
                    end
                end
            end
        end
    end
    return mods
end

-- Convenience: returns a single modifier value, falling back to the neutral
-- default if the key is unknown. Consumers can write:
--     local mult = CorexSkills.GetModifierValue(mods, 'craftSpeed') or 1.0
function CorexSkills.GetModifierValue(mods, key)
    if type(mods) ~= 'table' then
        local def = CorexSkills.MOD_DEFAULTS[key]
        return def and def.default or nil
    end
    if mods[key] == nil then
        local def = CorexSkills.MOD_DEFAULTS[key]
        return def and def.default or nil
    end
    return mods[key]
end
