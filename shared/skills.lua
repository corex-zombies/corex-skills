-- =============================================================================
-- COREX Skill Tree — single source of truth for both server and client.
-- =============================================================================
-- Each skill row:
--   id        : string — unique key persisted in player metadata.skills.unlocked
--   name      : string — display name
--   path      : 'combat' | 'survivor' | 'craftsman' | 'core'
--   tier      : 0..5 (0 = root, 5 = capstone)
--   x, y      : SVG coords (must match html/script.js viewBox 1360x620)
--   cost      : skill points required to unlock
--   parents   : array of prerequisite skill ids (all must be unlocked)
--   icon      : icon glyph id understood by html/script.js
--   desc      : tooltip / detail panel text
--   capstone  : optional bool — Tier-5 ceremonial node
--   isRoot    : optional bool — the central nexus
-- =============================================================================

CorexSkills = CorexSkills or {}

local L = Config.Layout
local PATH_X = L.PATH_X
local TIER_Y = L.TIER_Y
local BR = L.BRANCH_OFFSET

CorexSkills.List = {
    -- ROOT --------------------------------------------------------------------
    {
        id = 'root', name = 'Root', path = 'core', tier = 0,
        x = PATH_X.survivor, y = TIER_Y.root,
        cost = 0, parents = {},
        icon = 'root', isRoot = true,
        desc = 'Branch into Combat, Survivor, or Craftsman. Points are limited.'
    },

    -- COMBAT ------------------------------------------------------------------
    {
        id = 'c_steady', name = 'Steady Aim', path = 'combat', tier = 1,
        x = PATH_X.combat, y = TIER_Y[1],
        cost = 1, parents = { 'root' }, icon = 'crosshair',
        desc = 'Reduces weapon sway by 25% and shaves 15% off recoil.'
    },
    {
        id = 'c_reload', name = 'Quick Reload', path = 'combat', tier = 2,
        x = PATH_X.combat - BR, y = TIER_Y[2],
        cost = 2, parents = { 'c_steady' }, icon = 'reload',
        desc = 'Reload speed increased by 20% for all firearms.'
    },
    {
        id = 'c_iron', name = 'Iron Sights', path = 'combat', tier = 2,
        x = PATH_X.combat + BR, y = TIER_Y[2],
        cost = 2, parents = { 'c_steady' }, icon = 'iron',
        desc = 'Aiming down sights is 30% faster.'
    },
    {
        id = 'c_head', name = 'Headshot Pro', path = 'combat', tier = 3,
        x = PATH_X.combat, y = TIER_Y[3],
        cost = 3, parents = { 'c_reload', 'c_iron' }, icon = 'head',
        desc = 'Headshots deal 30% more damage.'
    },
    {
        id = 'c_recoil', name = 'Recoil Master', path = 'combat', tier = 4,
        x = PATH_X.combat - BR, y = TIER_Y[4],
        cost = 4, parents = { 'c_head' }, icon = 'recoil',
        desc = 'Cuts weapon recoil by 50%. Stacks with Steady Aim and Executioner.'
    },
    {
        id = 'c_akimbo', name = 'Akimbo', path = 'combat', tier = 4,
        x = PATH_X.combat + BR, y = TIER_Y[4],
        cost = 4, parents = { 'c_head' }, icon = 'akimbo',
        desc = 'Dual-wield pistols and SMGs at double fire rate.'
    },
    {
        id = 'c_exec', name = 'Executioner', path = 'combat', tier = 5,
        x = PATH_X.combat, y = TIER_Y.cap,
        cost = 6, parents = { 'c_recoil', 'c_akimbo' }, icon = 'exec',
        capstone = true,
        desc = 'LASER MODE: weapon recoil is essentially eliminated. 2x damage to sub-30% HP targets.'
    },

    -- SURVIVOR ----------------------------------------------------------------
    {
        id = 's_tough', name = 'Tough Skin', path = 'survivor', tier = 1,
        x = PATH_X.survivor, y = TIER_Y[1],
        cost = 1, parents = { 'root' }, icon = 'shield',
        desc = 'Maximum HP increased by 20%.'
    },
    {
        id = 's_endurance', name = 'Endurance', path = 'survivor', tier = 2,
        x = PATH_X.survivor, y = TIER_Y[2],
        cost = 2, parents = { 's_tough' }, icon = 'lightning',
        desc = 'Stamina pool +30%, sprint regen +25%.'
    },
    {
        id = 's_iron_body', name = 'Iron Body', path = 'survivor', tier = 3,
        x = PATH_X.survivor - BR, y = TIER_Y[3],
        cost = 3, parents = { 's_endurance' }, icon = 'heart',
        desc = 'Hunger and thirst drain 35% slower.'
    },
    {
        id = 's_cold', name = 'Cold Blood', path = 'survivor', tier = 3,
        x = PATH_X.survivor + BR, y = TIER_Y[3],
        cost = 3, parents = { 's_endurance' }, icon = 'snow',
        desc = 'Take 50% less damage in cold zones (Mt Chiliad, snowy areas).'
    },
    {
        id = 's_bleed', name = 'Bleed Stopper', path = 'survivor', tier = 4,
        x = PATH_X.survivor - BR, y = TIER_Y[4],
        cost = 4, parents = { 's_iron_body' }, icon = 'drop',
        desc = 'Bleeding from heavy hits drains 50% slower; any bandage stops it.'
    },
    {
        id = 's_plague', name = 'Plague Resist', path = 'survivor', tier = 4,
        x = PATH_X.survivor + BR, y = TIER_Y[4],
        cost = 4, parents = { 's_cold' }, icon = 'virus',
        desc = 'Bite infection reduced by 50%.'
    },
    {
        id = 's_immunity', name = 'Plague Immunity', path = 'survivor', tier = 5,
        x = PATH_X.survivor, y = TIER_Y.cap,
        cost = 6, parents = { 's_bleed', 's_plague' }, icon = 'immune',
        capstone = true,
        desc = '75% bite resistance + full airborne plague immunity.'
    },

    -- CRAFTSMAN ---------------------------------------------------------------
    {
        id = 'k_quick', name = 'Quick Hands', path = 'craftsman', tier = 1,
        x = PATH_X.craftsman, y = TIER_Y[1],
        cost = 1, parents = { 'root' }, icon = 'hammer',
        desc = 'Build construction speed +25%.'
    },
    {
        id = 'k_material', name = 'Material Saver', path = 'craftsman', tier = 2,
        x = PATH_X.craftsman - BR, y = TIER_Y[2],
        cost = 2, parents = { 'k_quick' }, icon = 'stack',
        desc = 'Crafting and building consume 20% less raw materials.'
    },
    {
        id = 'k_solid', name = 'Solid Build', path = 'craftsman', tier = 2,
        x = PATH_X.craftsman + BR, y = TIER_Y[2],
        cost = 2, parents = { 'k_quick' }, icon = 'wall',
        desc = 'Items you craft heal/cure 30% more when consumed (quality bonus).'
    },
    {
        id = 'k_master', name = 'Master Crafter', path = 'craftsman', tier = 3,
        x = PATH_X.craftsman, y = TIER_Y[3],
        cost = 3, parents = { 'k_material', 'k_solid' }, icon = 'anvil',
        desc = 'Unlocks rare crafting recipes (Combat PDW etc.) +15% craft quality.'
    },
    {
        id = 'k_lock', name = 'Locksmith', path = 'craftsman', tier = 4,
        x = PATH_X.craftsman - BR, y = TIER_Y[4],
        cost = 4, parents = { 'k_master' }, icon = 'lock',
        desc = 'Widens the lockpick success zone — locked containers open easier.'
    },
    {
        id = 'k_modder', name = 'Weapon Modder', path = 'craftsman', tier = 4,
        x = PATH_X.craftsman + BR, y = TIER_Y[4],
        cost = 4, parents = { 'k_master' }, icon = 'wrench',
        desc = 'Attach weapon mods at any workbench, 20% cheaper.'
    },
    {
        id = 'k_insta', name = 'Insta-Build', path = 'craftsman', tier = 5,
        x = PATH_X.craftsman, y = TIER_Y.cap,
        cost = 6, parents = { 'k_lock', 'k_modder' }, icon = 'spark',
        capstone = true,
        desc = '20% chance to instantly complete any build with no cost.'
    }
}

-- Build O(1) lookup once.
CorexSkills.ById = {}
for _, s in ipairs(CorexSkills.List) do
    CorexSkills.ById[s.id] = s
end

function CorexSkills.Get(id)
    return id and CorexSkills.ById[id] or nil
end

-- Returns true if every parent in `node.parents` is present in the unlocked set.
function CorexSkills.PrereqsMet(node, unlockedSet)
    if not node or type(node.parents) ~= 'table' then return true end
    for _, parent in ipairs(node.parents) do
        if not unlockedSet[parent] then return false end
    end
    return true
end

-- Total cost spent across an unlocked-id list (used by respec refunds).
function CorexSkills.TotalCost(unlockedList)
    local total = 0
    for _, id in ipairs(unlockedList or {}) do
        local node = CorexSkills.ById[id]
        if node and id ~= 'root' then
            total = total + (tonumber(node.cost) or 0)
        end
    end
    return total
end
