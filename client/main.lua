-- =============================================================================
-- corex-skills :: client/main.lua
-- =============================================================================
-- Lightweight bridge between the player and the NUI panel.
-- Server is authoritative — client only relays unlock requests and renders
-- whatever state the server sends back.
-- =============================================================================

local Corex
local isReady = false
local isOpen  = false

local lastState = {
    unlocked  = {},
    points    = 0,
    xp        = 0,
    xpTotal   = 0,
    modifiers = nil   -- populated on first server sync
}

-- Cache of effect-driving values so we only re-apply when something actually
-- changed (avoid spamming SetPedMaxHealth every tick).
local appliedEffects = {
    maxHealthMul = 1.0,
    sprintMul    = 1.0
}

-- ---------------------------------------------------------------------------
-- Core init
-- ---------------------------------------------------------------------------

local function InitCore()
    local ok, core = pcall(function()
        return exports['corex-core']:GetCoreObject()
    end)
    if not ok or not core or not core.Functions then return false end
    Corex = core
    return true
end

local function OnCoreReady()
    isReady = true
    if Config.Debug then print('[COREX-SKILLS] ^2Connected to corex-core^0') end
    -- Pull latest state on resource start / re-spawn.
    TriggerServerEvent('corex-skills:server:requestState')
end

if not InitCore() then
    AddEventHandler('corex:client:coreReady', function(coreObj)
        if coreObj and coreObj.Functions and not Corex then
            Corex = coreObj
            OnCoreReady()
        end
    end)
    CreateThread(function()
        local elapsed = 0
        while not Corex and elapsed < 15000 do
            Wait(250)
            elapsed = elapsed + 250
        end
        if not Corex then
            print('[COREX-SKILLS] ^1Core init timed out^0')
        end
    end)
else
    CreateThread(OnCoreReady)
end

-- ---------------------------------------------------------------------------
-- Build the payload the NUI expects (skills tree + player state).
-- We send the tree once on open (it's static) and live-update unlocked/points.
-- ---------------------------------------------------------------------------

local function BuildSkillTreePayload()
    local skills = {}
    for i, s in ipairs(CorexSkills.List) do
        skills[i] = {
            id       = s.id,
            name     = s.name,
            path     = s.path,
            tier     = s.tier,
            x        = s.x,
            y        = s.y,
            cost     = s.cost,
            parents  = s.parents or {},
            icon     = s.icon,
            desc     = s.desc,
            capstone = s.capstone == true,
            isRoot   = s.isRoot == true
        }
    end
    return skills
end

local function BuildOpenPayload()
    local playerName = (Corex and Corex.Functions and Corex.Functions.GetPlayerName)
        and Corex.Functions.GetPlayerName(GetPlayerServerId(PlayerId()))
        or GetPlayerName(PlayerId())

    return {
        skills    = BuildSkillTreePayload(),
        unlocked  = lastState.unlocked,
        points    = lastState.points,
        xp        = lastState.xp,
        xpTotal   = lastState.xpTotal,
        xpPerPoint = Config.XpPerPoint or 100,
        modifiers = lastState.modifiers,
        layout    = Config.Layout,
        colors    = Config.Colors,
        player    = {
            name  = playerName or 'Survivor',
            level = 1
        },
        config = {
            allowRespec = Config.AllowRespec == true
        }
    }
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

local function OpenSkills()
    if isOpen or not isReady then return end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = BuildOpenPayload() })
end

local function CloseSkills()
    if not isOpen then return end
    isOpen = false
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
end

local function ToggleSkills()
    if isOpen then CloseSkills() else OpenSkills() end
end

-- ---------------------------------------------------------------------------
-- Server -> client state push
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Native effects driver
-- ---------------------------------------------------------------------------
-- Translates the synced modifier table into actual gameplay tweaks via FiveM
-- natives. Only re-applies when a value changed, and re-applies on respawn
-- because a fresh ped resets max HP / sprint multipliers.

local function ApplyNativeEffects(mods)
    if type(mods) ~= 'table' then return end
    local ped = PlayerPedId()
    if not ped or ped == 0 then return end

    -- Max health: vanilla GTA caps at 200; we scale that.
    local mhMul = tonumber(mods.maxHealth) or 1.0
    local desiredMax = math.floor(200 * mhMul)
    if mhMul ~= appliedEffects.maxHealthMul or GetPedMaxHealth(ped) ~= desiredMax then
        SetPedMaxHealth(ped, desiredMax)
        -- Bring current HP up only if we boosted; never auto-heal during play.
        if mhMul > appliedEffects.maxHealthMul then
            local current = GetEntityHealth(ped)
            if current > 0 and current < desiredMax then
                local boost = math.floor(200 * (mhMul - appliedEffects.maxHealthMul))
                SetEntityHealth(ped, math.min(desiredMax, current + boost))
            end
        end
        appliedEffects.maxHealthMul = mhMul
    end

    -- Sprint multiplier: combines staminaRegen (positive) and sprintCost
    -- (negative) into a single 1.0..1.49 boost. Native is hard-capped at 1.49.
    local stamMul = tonumber(mods.staminaRegen) or 1.0
    local costMul = tonumber(mods.sprintCost)   or 1.0
    local boost = 1.0
    if stamMul > 1.0 then boost = boost + (stamMul - 1.0) * 0.5 end
    if costMul < 1.0 then boost = boost + (1.0 - costMul) * 0.5 end
    boost = math.min(1.49, math.max(1.0, boost))
    if math.abs(boost - appliedEffects.sprintMul) > 0.001 then
        SetRunSprintMultiplierForPlayer(PlayerId(), boost)
        appliedEffects.sprintMul = boost
    end

    -- Stamina pool: when endurance is unlocked, top up the stat so sprinting
    -- doesn't drain to zero quickly. Stat hash for MP slot 0.
    if stamMul > 1.0 then
        StatSetInt(`MP0_STAMINA`, 100, true)
    end
end

-- Public client export — other resources read live skill modifiers without
-- going through a server callback. Returns a neutral table if not synced yet
-- so consumers can multiply blindly.
exports('GetLocalModifiers', function()
    if type(lastState.modifiers) == 'table' then
        return lastState.modifiers
    end
    return CorexSkills.NeutralModifiers()
end)

exports('GetLocalModifier', function(key)
    return CorexSkills.GetModifierValue(lastState.modifiers, key)
end)

exports('GetLocalUnlocked', function()
    return lastState.unlocked or {}
end)

-- Quick check on the local player. Returns false until the first server sync.
exports('HasSkill', function(skillId)
    if type(skillId) ~= 'string' or skillId == '' then return false end
    if type(lastState.unlocked) ~= 'table' then return false end
    for _, id in ipairs(lastState.unlocked) do
        if id == skillId then return true end
    end
    return false
end)

-- ---------------------------------------------------------------------------
-- Lockpick minigame
-- ---------------------------------------------------------------------------
-- Synchronous-ish helper: pops the lockpick NUI, blocks the calling thread
-- until the player either succeeds, fails, or is killed/disconnected, then
-- returns success (bool). The k_lock skill widens the green zone by up to
-- 50% (lockpickSpeed = 1.5 → ~24% wider). Other resources call:
--
--   local ok = exports['corex-skills']:OpenLockpick({ pins = 3, cursorMs = 1400 })
--   if ok then ... end
--
local lockpickResolver = nil
local lockpickActive   = false

exports('OpenLockpick', function(opts)
    opts = opts or {}
    if lockpickActive then return false end

    -- Skill widens the green zone (easier) — never narrows it.
    local zoneFrac = tonumber(opts.zoneFraction) or 0.18
    local lockSpeed = 1.0
    if type(lastState.modifiers) == 'table' and tonumber(lastState.modifiers.lockpickSpeed) then
        lockSpeed = math.max(1.0, tonumber(lastState.modifiers.lockpickSpeed))
    end
    -- Map a 1.0..1.5 lockpickSpeed range to a 1.0..1.30x zone widening.
    zoneFrac = math.min(0.45, zoneFrac * (1.0 + (lockSpeed - 1.0) * 0.6))

    lockpickActive = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'lockpickStart',
        data = {
            pins         = tonumber(opts.pins) or 3,
            cursorMs     = tonumber(opts.cursorMs) or 1400,
            zoneFraction = zoneFrac
        }
    })

    -- Block this thread until the NUI calls back with the result.
    local result = nil
    lockpickResolver = function(success) result = success end
    local timeout = GetGameTimer() + (tonumber(opts.timeoutMs) or 30000)
    while result == nil and GetGameTimer() < timeout do
        Wait(50)
    end

    -- Cleanup either way (timeout or resolved)
    if result == nil then
        SendNUIMessage({ action = 'lockpickStop' })
        result = false
    end
    lockpickActive = false
    lockpickResolver = nil
    SetNuiFocus(false, false)
    return result == true
end)

RegisterNUICallback('lockpickResult', function(data, cb)
    if lockpickResolver then
        lockpickResolver(data and data.success == true)
    end
    cb('ok')
end)

-- /testlockpick — quick in-game verification. With k_lock unlocked, the
-- green zone is noticeably wider (easier).
RegisterCommand('testlockpick', function()
    local ok = exports['corex-skills']:OpenLockpick({ pins = 3, cursorMs = 1400 })
    print('^5[COREX-SKILLS]^7 lockpick test result: ' .. tostring(ok))
end, false)

RegisterNetEvent('corex-skills:client:syncState', function(state)
    if type(state) ~= 'table' then return end
    lastState.unlocked  = type(state.unlocked)  == 'table' and state.unlocked  or {}
    lastState.points    = tonumber(state.points)  or 0
    lastState.xp        = tonumber(state.xp)      or 0
    lastState.xpTotal   = tonumber(state.xpTotal) or 0
    lastState.modifiers = type(state.modifiers) == 'table' and state.modifiers or nil

    ApplyNativeEffects(lastState.modifiers)

    if isOpen then
        SendNUIMessage({
            action = 'updateState',
            data = {
                unlocked  = lastState.unlocked,
                points    = lastState.points,
                xp        = lastState.xp,
                xpTotal   = lastState.xpTotal,
                modifiers = lastState.modifiers
            }
        })
    end
end)

-- Forward XP gain toasts from the server to the NUI overlay.
RegisterNetEvent('corex-skills:client:xpToast', function(payload)
    if type(payload) ~= 'table' then return end
    if Config.ShowXpToasts == false then return end
    SendNUIMessage({ action = 'xpToast', data = payload })
end)

-- /myskills — fast in-game verification for the player. Prints the live
-- modifier table the client is currently applying, so you can confirm a
-- skill you just unlocked is actually flowing through to gameplay (e.g.
-- after buying c_recoil, weaponRecoil should read 0.6 here).
RegisterCommand('myskills', function()
    print('^5[COREX-SKILLS] ^7live modifiers (client):^0')
    if type(lastState.modifiers) ~= 'table' then
        print('  (no modifiers synced yet)')
        return
    end
    local keys = {}
    for k in pairs(lastState.modifiers) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local v = lastState.modifiers[k]
        local def = (CorexSkills.MOD_DEFAULTS or {})[k]
        local neutral = def and def.default
        local marker = ''
        if neutral ~= nil and v ~= neutral then marker = '  <-- ACTIVE' end
        print(('  %-22s = %s%s'):format(k, tostring(v), marker))
    end
    print(('^5[COREX-SKILLS]^7 unlocked: %s · points: %d · xp: %d/%d^0'):format(
        table.concat(lastState.unlocked or {}, ', '),
        lastState.points or 0,
        lastState.xp or 0,
        Config.XpPerPoint or 100
    ))
end, false)

-- Re-apply max HP / sprint after respawn (fresh ped wipes them).
AddEventHandler('playerSpawned', function()
    appliedEffects.maxHealthMul = -1   -- force re-apply
    appliedEffects.sprintMul    = -1
    SetTimeout(500, function()
        if lastState.modifiers then
            ApplyNativeEffects(lastState.modifiers)
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks (panel -> client -> server)
-- ---------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    CloseSkills()
    cb('ok')
end)

RegisterNUICallback('unlock', function(data, cb)
    local id = data and data.skillId
    if type(id) == 'string' and #id > 0 and #id <= 64 then
        TriggerServerEvent('corex-skills:server:unlock', id)
    end
    cb('ok')
end)

RegisterNUICallback('respec', function(_, cb)
    TriggerServerEvent('corex-skills:server:respec')
    cb('ok')
end)

RegisterNUICallback('refresh', function(_, cb)
    TriggerServerEvent('corex-skills:server:requestState')
    cb('ok')
end)

-- ---------------------------------------------------------------------------
-- Key bind & command
-- ---------------------------------------------------------------------------

RegisterCommand(Config.OpenCommand, function()
    if not isReady then return end
    ToggleSkills()
end, false)

RegisterKeyMapping(Config.OpenCommand, 'Open Skill Tree', 'keyboard', Config.OpenKey)

-- ESC closes the panel even if NUI focus is somehow lost.
CreateThread(function()
    while true do
        if isOpen then
            Wait(0)
            DisableControlAction(0, 200, true) -- M_PAUSE
            DisableControlAction(0, 199, true) -- P_PAUSE
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199) then
                CloseSkills()
            end
        else
            Wait(250)
        end
    end
end)

-- ---------------------------------------------------------------------------
-- AFK heartbeat — server only credits playtime XP if we recently moved.
-- ---------------------------------------------------------------------------

CreateThread(function()
    local lastCoords = vector3(0, 0, 0)
    local HEARTBEAT_MS = 30000          -- 30s cadence
    local MIN_MOVE     = 1.0            -- meters since last beat (~ standing still loses XP)

    while true do
        Wait(HEARTBEAT_MS)
        if isReady then
            local ped = PlayerPedId()
            if ped and ped ~= 0 and not IsEntityDead(ped) then
                local coords = GetEntityCoords(ped)
                if #(coords - lastCoords) >= MIN_MOVE then
                    lastCoords = coords
                    TriggerServerEvent('corex-skills:server:heartbeat')
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    if isOpen then
        SendNUIMessage({ action = 'close' })
        SetNuiFocus(false, false)
        isOpen = false
    end
end)
