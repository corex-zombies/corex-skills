-- =============================================================================
-- corex-skills :: server/main.lua
-- =============================================================================
-- Persists per-player skill state inside corex-core's metadata.skills:
--     metadata.skills = {
--         unlocked = { 'root','c_steady',... },
--         points   = 18,
--         xp       = 73,       -- accumulator; xp >= XpPerPoint -> +1 point
--         xpTotal  = 412       -- lifetime XP earned (statistic only)
--     }
-- =============================================================================

local Corex
local META_KEY = 'skills'

-- Exposed to server/xp.lua via the global CorexSkillsServer table.
CorexSkillsServer = CorexSkillsServer or {}

local function Debug(msg)
    if Config.Debug then
        print('^5[COREX-SKILLS] ^7' .. tostring(msg) .. '^0')
    end
end

local function InitCorex()
    if Corex then return true end
    local ok, obj = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    if ok and obj then
        Corex = obj
        return true
    end
    return false
end

CreateThread(function()
    local tries = 0
    while not InitCorex() and tries < 50 do
        tries = tries + 1
        Wait(200)
    end
    if not Corex then
        print('^1[COREX-SKILLS] Failed to bind to corex-core after 10s.^0')
    else
        Debug('Connected to corex-core.')
    end
end)

local function Notify(src, message, ntype)
    if Corex and Corex.Functions and Corex.Functions.Notify then
        Corex.Functions.Notify(src, message, ntype or 'info')
    else
        TriggerClientEvent('corex:notify', src, message, ntype or 'info')
    end
end

-- ---------------------------------------------------------------------------
-- Metadata helpers
-- ---------------------------------------------------------------------------

local function ListToSet(list)
    local set = {}
    if type(list) ~= 'table' then return set end
    for _, id in ipairs(list) do
        if type(id) == 'string' and CorexSkills.ById[id] then
            set[id] = true
        end
    end
    return set
end

local function SetToList(set)
    local list = {}
    for id, on in pairs(set) do
        if on and CorexSkills.ById[id] then
            list[#list + 1] = id
        end
    end
    table.sort(list)
    return list
end

local function GetRawMeta(src)
    local data
    if Corex and Corex.Player and Corex.Player.GetMetaData then
        data = Corex.Player.GetMetaData(src, META_KEY)
    else
        local ok, raw = pcall(function()
            return exports['corex-core']:GetMetaData(src, META_KEY)
        end)
        if ok then data = raw end
    end
    if type(data) ~= 'table' then data = nil end
    return data
end

local function SaveRawMeta(src, value)
    if Corex and Corex.Player and Corex.Player.SetMetaData then
        Corex.Player.SetMetaData(src, META_KEY, value)
    else
        pcall(function()
            return exports['corex-core']:SetMetaData(src, META_KEY, value)
        end)
    end
end

-- Returns a fully-populated state struct for the player, migrating older
-- metadata shapes on the fly. Fields:
--   points       (int, spend currency)
--   xp           (int 0..XpPerPoint-1, accumulator; spills into points at threshold)
--   xpTotal      (int, lifetime XP earned, capped at MaxXpTotal)
--   unlockedList (array of skill ids)
--   unlockedSet  (lookup table {id=true})
local function GetState(src)
    local raw = GetRawMeta(src)
    local needsInit = false

    if not raw then
        raw = {
            unlocked = {},
            points   = Config.StartingPoints or 0,
            xp       = 0,
            xpTotal  = 0
        }
        needsInit = true
    end

    if type(raw.unlocked) ~= 'table' then raw.unlocked = {} end

    if type(raw.points) ~= 'number' or raw.points ~= raw.points then
        raw.points = Config.StartingPoints or 0
        needsInit = true
    end

    if type(raw.xp) ~= 'number' or raw.xp ~= raw.xp then
        raw.xp = 0
        needsInit = true
    end

    if type(raw.xpTotal) ~= 'number' or raw.xpTotal ~= raw.xpTotal then
        raw.xpTotal = 0
        needsInit = true
    end

    raw.points  = math.max(0, math.min(Config.MaxPoints or 999, math.floor(raw.points)))
    raw.xp      = math.max(0, math.floor(raw.xp))
    raw.xpTotal = math.max(0, math.min(Config.MaxXpTotal or 1000000, math.floor(raw.xpTotal)))

    local set = ListToSet(raw.unlocked)
    if Config.AutoGrantRoot and not set['root'] then
        set['root'] = true
        needsInit = true
    end

    -- Drop any orphan IDs (skills removed in updates) so we never desync.
    local cleanedList = SetToList(set)
    if #cleanedList ~= #raw.unlocked then
        needsInit = true
    end

    raw.unlocked = cleanedList

    if needsInit then
        SaveRawMeta(src, raw)
    end

    return {
        points       = raw.points,
        xp           = raw.xp,
        xpTotal      = raw.xpTotal,
        unlockedList = raw.unlocked,
        unlockedSet  = set
    }
end

local function PersistState(src, state)
    SaveRawMeta(src, {
        unlocked = SetToList(state.unlockedSet),
        points   = math.max(0, math.min(Config.MaxPoints or 999, math.floor(state.points or 0))),
        xp       = math.max(0, math.floor(state.xp or 0)),
        xpTotal  = math.max(0, math.min(Config.MaxXpTotal or 1000000, math.floor(state.xpTotal or 0)))
    })
end

local function ComputeMods(state)
    return CorexSkills.ComputeModifiers(SetToList(state.unlockedSet))
end

local function BroadcastState(src, state)
    state = state or GetState(src)
    local mods = ComputeMods(state)
    TriggerClientEvent('corex-skills:client:syncState', src, {
        unlocked  = SetToList(state.unlockedSet),
        points    = state.points,
        xp        = state.xp,
        xpTotal   = state.xpTotal,
        modifiers = mods
    })
    TriggerEvent(Config.Events.ModifiersDirty, src, mods)
end

-- ---------------------------------------------------------------------------
-- Public Lua API + exports
-- ---------------------------------------------------------------------------

local function HasSkill(src, skillId)
    if not src or not skillId then return false end
    local state = GetState(src)
    return state.unlockedSet[skillId] == true
end

local function GetUnlockedSkills(src)
    local state = GetState(src)
    local copy = {}
    for i, id in ipairs(state.unlockedList) do copy[i] = id end
    return copy
end

local function GetSkillPoints(src)
    local state = GetState(src)
    return state.points
end

local function AddSkillPoints(src, amount)
    amount = tonumber(amount)
    if not amount or amount ~= amount then return false end

    local state = GetState(src)
    local before = state.points
    state.points = math.max(0, math.min(Config.MaxPoints or 999, math.floor(before + amount)))

    PersistState(src, state)
    BroadcastState(src, state)

    if amount > 0 then
        TriggerEvent(Config.Events.PointsGained, src, amount, state.points)
    end

    return true, state.points
end

-- ---------------------------------------------------------------------------
-- XP API
-- ---------------------------------------------------------------------------
-- AwardXp credits XP to a player and converts every full XpPerPoint chunk into
-- a skill point. Always pass a `reason` (e.g. "zombie_kill", "playtime") so we
-- can tag the toast on the client and audit-log later.
local function AwardXp(src, amount, reason)
    amount = tonumber(amount)
    if not src or src == 0 then return false end
    if not amount or amount ~= amount or amount <= 0 then return false end

    local state = GetState(src)
    local perPoint = math.max(1, math.floor(Config.XpPerPoint or 100))

    state.xp = math.floor(state.xp + amount)
    state.xpTotal = math.min(
        Config.MaxXpTotal or 1000000,
        math.floor(state.xpTotal + amount)
    )

    -- Spill XP into points at the threshold. Multiple thresholds in one award
    -- (e.g. a fat 250 XP grant) all flow through cleanly.
    local pointsGained = 0
    while state.xp >= perPoint and state.points < (Config.MaxPoints or 999) do
        state.xp = state.xp - perPoint
        state.points = state.points + 1
        pointsGained = pointsGained + 1
    end

    -- If they're capped on points, drop the remaining XP so it doesn't dangle.
    if state.points >= (Config.MaxPoints or 999) then
        state.xp = 0
    end

    PersistState(src, state)
    BroadcastState(src, state)

    TriggerEvent(Config.Events.XpAwarded, src, amount, reason or 'unknown', state.xp)
    if pointsGained > 0 then
        TriggerEvent(Config.Events.PointsGained, src, pointsGained, state.points)
    end

    -- Toasts are forwarded to the client by the broadcast so the NUI can show
    -- a "+50 XP — Zombie kill" overlay.
    TriggerClientEvent('corex-skills:client:xpToast', src, {
        amount = amount,
        reason = reason or 'unknown',
        gainedPoint = pointsGained > 0
    })

    return true, state.xp, state.points, pointsGained
end

-- ---------------------------------------------------------------------------
-- Modifier API
-- ---------------------------------------------------------------------------
-- GetModifiers always returns a complete neutral table even when the player is
-- still loading. Consumers can multiply blindly without nil-checks.
local function GetModifiers(src)
    if not src or src == 0 then
        return CorexSkills.NeutralModifiers()
    end
    local state = GetState(src)
    return ComputeMods(state)
end

local function GetModifier(src, key)
    return CorexSkills.GetModifierValue(GetModifiers(src), key)
end

-- Crafting gate. `recipe` is the recipe table from corex-crafting; we look at
-- a `requiresSkill` field (single id or list) and an optional `requiresFlag`
-- (a modifier flag like 'unlocksRareRecipes').
-- Returns: ok (bool), reason (string|nil), missingSkill (string|nil)
local function CanCraftRecipe(src, recipe)
    if type(recipe) ~= 'table' then return true end
    local state = GetState(src)
    local mods  = ComputeMods(state)

    if recipe.requiresFlag then
        if not mods[recipe.requiresFlag] then
            return false, 'skill_flag', recipe.requiresFlag
        end
    end

    local req = recipe.requiresSkill
    if req then
        local list = type(req) == 'table' and req or { req }
        for _, id in ipairs(list) do
            if not state.unlockedSet[id] then
                return false, 'skill', id
            end
        end
    end

    return true
end

-- Expose to xp.lua / commands.lua via the namespace table.
CorexSkillsServer.AwardXp          = AwardXp
CorexSkillsServer.AddSkillPoints   = AddSkillPoints
CorexSkillsServer.GetState         = GetState
CorexSkillsServer.GetModifiers     = GetModifiers
CorexSkillsServer.HasSkill         = HasSkill
CorexSkillsServer.BroadcastState   = BroadcastState

exports('HasSkill',          function(src, id)   return HasSkill(src, id) end)
exports('GetUnlockedSkills', function(src)       return GetUnlockedSkills(src) end)
exports('GetSkillPoints',    function(src)       return GetSkillPoints(src) end)
exports('AddSkillPoints',    function(src, n)    return AddSkillPoints(src, n) end)
exports('GiveSkillPoints',   function(src, n)    return AddSkillPoints(src, n) end)
exports('AwardXp',           function(src, n, r) return AwardXp(src, n, r) end)
exports('GetModifiers',      function(src)       return GetModifiers(src) end)
exports('GetModifier',       function(src, key)  return GetModifier(src, key) end)
exports('CanCraftRecipe',    function(src, rec)  return CanCraftRecipe(src, rec) end)
exports('GetXp',             function(src)       return GetState(src).xp end)
exports('GetXpTotal',        function(src)       return GetState(src).xpTotal end)

-- Skill catalog lookups — used by external resources (corex-crafting) to
-- render friendly names for skill requirements / gate failures.
exports('GetSkillInfo', function(skillId)
    local node = CorexSkills.Get(skillId)
    if not node then return nil end
    return {
        id    = node.id,
        name  = node.name,
        path  = node.path,
        tier  = node.tier,
        cost  = node.cost,
        desc  = node.desc
    }
end)

-- Returns the FIRST skill that grants the given modifier flag (e.g. the
-- skill that unlocks 'unlocksRareRecipes' is k_master). Useful for showing
-- "Requires: Master Crafter" instead of the raw flag string in UIs.
exports('GetSkillForFlag', function(flag)
    if type(flag) ~= 'string' then return nil end
    local effects = CorexSkills.SKILL_EFFECTS or {}
    for skillId, effs in pairs(effects) do
        if effs[flag] then
            local node = CorexSkills.Get(skillId)
            if node then
                return { id = node.id, name = node.name, path = node.path, tier = node.tier }
            end
        end
    end
    return nil
end)

-- ---------------------------------------------------------------------------
-- Net events (client -> server)
-- ---------------------------------------------------------------------------

RegisterNetEvent('corex-skills:server:requestState', function()
    local src = source
    if not src or src == 0 then return end
    BroadcastState(src)
end)

RegisterNetEvent('corex-skills:server:unlock', function(skillId)
    local src = source
    if not src or src == 0 then return end
    if type(skillId) ~= 'string' then return end

    local node = CorexSkills.Get(skillId)
    if not node then
        Notify(src, 'Unknown skill.', 'error')
        return
    end

    if skillId == 'root' then
        return
    end

    local state = GetState(src)
    if state.unlockedSet[skillId] then
        Notify(src, 'Already unlocked.', 'info')
        BroadcastState(src, state)
        return
    end

    if not CorexSkills.PrereqsMet(node, state.unlockedSet) then
        Notify(src, 'Prerequisites not met.', 'error')
        return
    end

    local cost = tonumber(node.cost) or 0
    if state.points < cost then
        Notify(src, 'Not enough skill points.', 'error')
        return
    end

    state.points = state.points - cost
    state.unlockedSet[skillId] = true

    PersistState(src, state)
    BroadcastState(src, state)

    TriggerEvent(Config.Events.Unlocked, src, skillId)
    Notify(src, ('Unlocked: %s'):format(node.name), 'success')
end)

RegisterNetEvent('corex-skills:server:respec', function()
    local src = source
    if not src or src == 0 then return end
    if not Config.AllowRespec then
        Notify(src, 'Respec is disabled.', 'error')
        return
    end

    local state = GetState(src)
    local refundList = {}
    for id in pairs(state.unlockedSet) do refundList[#refundList + 1] = id end
    local refund = CorexSkills.TotalCost(refundList)

    -- Charge respec cost in cash if configured
    local cost = tonumber(Config.RespecCost) or 0
    if cost > 0 then
        local hasMoney
        if Corex and Corex.Player and Corex.Player.HasMoney then
            hasMoney = Corex.Player.HasMoney(src, 'cash', cost)
        else
            local ok, result = pcall(function()
                return exports['corex-core']:HasMoney(src, 'cash', cost)
            end)
            hasMoney = ok and result == true
        end

        if not hasMoney then
            Notify(src, ('Respec costs $%d cash.'):format(cost), 'error')
            return
        end

        if Corex and Corex.Player and Corex.Player.RemoveMoney then
            Corex.Player.RemoveMoney(src, 'cash', cost)
        else
            pcall(function() exports['corex-core']:RemoveMoney(src, 'cash', cost) end)
        end
    end

    state.unlockedSet = {}
    if Config.AutoGrantRoot then state.unlockedSet['root'] = true end
    state.points = math.min(Config.MaxPoints or 999, state.points + refund)

    PersistState(src, state)
    BroadcastState(src, state)

    TriggerEvent(Config.Events.Respec, src)
    Notify(src, ('Respec complete — +%d points refunded.'):format(refund), 'success')
end)

-- Hook playerReady from corex-core so the client always has fresh state when
-- the player finishes loading.
AddEventHandler('corex:server:playerReady', function(src, _player)
    if not src or src == 0 then return end
    SetTimeout(500, function()
        BroadcastState(src)
    end)
end)

-- ---------------------------------------------------------------------------
-- Admin commands (sandbox / testing helpers)
-- ---------------------------------------------------------------------------

local function ResolveTarget(src, args, idx)
    local target = tonumber(args[idx])
    if not target and src > 0 then return src, idx end
    return target, idx + 1
end

RegisterCommand('giveskillpoints', function(src, args)
    args = args or {}
    local target, nextIdx = ResolveTarget(src, args, 1)
    local amount = tonumber(args[nextIdx])
    if not target or not amount then
        if src > 0 then Notify(src, 'Usage: /giveskillpoints [id] amount', 'error') end
        return
    end
    AddSkillPoints(target, amount)
    if src > 0 then Notify(src, ('Gave %d skill points to %d'):format(amount, target), 'success') end
end, true)

RegisterCommand('resetskills', function(src, args)
    local target = tonumber((args or {})[1]) or src
    if not target or target == 0 then return end

    SaveRawMeta(target, {
        unlocked = Config.AutoGrantRoot and { 'root' } or {},
        points   = Config.StartingPoints or 0,
        xp       = 0,
        xpTotal  = 0
    })
    BroadcastState(target)
    if src > 0 then Notify(src, ('Reset skills for player %d'):format(target), 'success') end
end, true)

-- Grant raw XP to a player (testing). XP spills into points at Config.XpPerPoint.
--   /giveskillxp [id] amount
RegisterCommand('giveskillxp', function(src, args)
    args = args or {}
    local target, nextIdx = ResolveTarget(src, args, 1)
    local amount = tonumber(args[nextIdx])
    if not target or not amount then
        if src > 0 then Notify(src, 'Usage: /giveskillxp [id] amount', 'error') end
        return
    end
    local ok = AwardXp(target, amount, 'admin')
    if src > 0 and ok then
        Notify(src, ('Awarded %d XP to %d'):format(amount, target), 'success')
    end
end, true)

-- Dump active modifiers for a player to console (admin debug).
--   /skillsmods [id]
RegisterCommand('skillsmods', function(src, args)
    local target = tonumber((args or {})[1]) or src
    if not target or target == 0 then
        if src > 0 then Notify(src, 'Usage: /skillsmods [id]', 'error') end
        return
    end
    local mods = GetModifiers(target)
    print(('^5[COREX-SKILLS]^7 Modifiers for player %d:'):format(target))
    -- Sorted output for readability
    local keys = {}
    for k in pairs(mods) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        print(('  %-20s = %s'):format(k, tostring(mods[k])))
    end
    if src > 0 then Notify(src, 'Modifiers printed to console.', 'info') end
end, true)
