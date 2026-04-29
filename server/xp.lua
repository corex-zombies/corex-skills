-- =============================================================================
-- corex-skills :: server/xp.lua
-- =============================================================================
-- XP earning sources. Each source calls into CorexSkillsServer.AwardXp(...) so
-- xp.lua never touches metadata directly. Sources are toggleable via Config.Xp.
--
--   * Playtime drip — slow accumulator for casual players (AFK-guarded).
--   * Zombie kill   — listens to a relay event from corex-zombies.
--   * Event done    — listens to corex-events completion.
--   * Redzone loot  — listens to corex-loot container-emptied event.
--   * Survival      — bonus XP on infection cure (corex-survival).
--
-- Anti-AFK: the client posts a heartbeat on input. The server only awards
-- playtime XP if the player heartbeated within Config.AfkThresholdMs.
-- =============================================================================

local AwardXp = function(...)
    return CorexSkillsServer and CorexSkillsServer.AwardXp(...)
end

-- ---------------------------------------------------------------------------
-- Activity tracker (AFK guard)
-- ---------------------------------------------------------------------------

local lastActivityAt = {}   -- [src] = epoch ms of last input/movement heartbeat
local lastZombieKillAt = {} -- [src] = ms of last credited zombie kill (rate limit)

local function NowMs()
    return GetGameTimer()
end

local function IsActive(src)
    if not Config.AfkThresholdMs or Config.AfkThresholdMs <= 0 then return true end
    local last = lastActivityAt[src]
    if not last then return false end
    return (NowMs() - last) <= Config.AfkThresholdMs
end

local function IsAlive(src)
    if not Config.RequireAlive then return true end
    -- Try the framework first, fall back to native ped health.
    local ok, hp = pcall(function()
        return exports['corex-core']:GetPlayerHealth(src)
    end)
    if ok and tonumber(hp) then
        return tonumber(hp) > 0
    end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return GetEntityHealth(ped) > 0
end

-- Client posts this every ~30s when the player has had any input.
RegisterNetEvent('corex-skills:server:heartbeat', function()
    local src = source
    if not src or src == 0 then return end
    lastActivityAt[src] = NowMs()
end)

AddEventHandler('playerDropped', function()
    local src = source
    if not src then return end
    lastActivityAt[src] = nil
    lastZombieKillAt[src] = nil
end)

-- ---------------------------------------------------------------------------
-- Playtime drip
-- ---------------------------------------------------------------------------

CreateThread(function()
    while true do
        local interval = tonumber(Config.Xp and Config.Xp.playtimeIntervalMs) or 0
        local amount   = tonumber(Config.Xp and Config.Xp.playtimeAmount) or 0

        if interval <= 0 or amount <= 0 then
            -- Source disabled — sleep a minute and recheck (config could reload).
            Wait(60000)
        else
            Wait(interval)
            for _, idStr in ipairs(GetPlayers()) do
                local src = tonumber(idStr)
                if src and IsActive(src) and IsAlive(src) then
                    AwardXp(src, amount, 'playtime')
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Zombie kills (relayed from corex-zombies)
-- ---------------------------------------------------------------------------
-- corex-zombies fires its kill event client-side. We add a thin relay there
-- (see corex-zombies/client patch) that calls this server event with the
-- zombie's typeId so we can give a bonus for tougher targets.

local KILL_COOLDOWN_MS = 250  -- server-side rate limit; sanity, not balance

RegisterNetEvent('corex-skills:server:reportZombieKill', function(typeId)
    local src = source
    if not src or src == 0 then return end
    if not Config.Xp then return end

    local now = NowMs()
    if lastZombieKillAt[src] and (now - lastZombieKillAt[src]) < KILL_COOLDOWN_MS then
        return
    end
    lastZombieKillAt[src] = now

    if not IsAlive(src) then return end

    local base    = tonumber(Config.Xp.zombieKill) or 0
    local special = tonumber(Config.Xp.zombieKillSpecial) or 0

    if base <= 0 and special <= 0 then return end

    -- Default to walker-tier reward; bump to special for non-walker types.
    local reward = base
    if typeId and typeId ~= 'walker' and special > 0 then
        reward = math.max(base, special)
    end

    if reward > 0 then
        AwardXp(src, reward, 'zombie_kill')
    end
end)

-- ---------------------------------------------------------------------------
-- Event completion (corex-events)
-- ---------------------------------------------------------------------------
-- corex-events broadcasts `corex-events:client:eventEnd` on every event end.
-- We added a server-side companion event (`corex-events:server:eventCompleted`)
-- that fires only when the event ended successfully and carries the
-- participant list.
AddEventHandler('corex-events:server:eventCompleted', function(eventId, participants)
    if not Config.Xp or not participants then return end
    local amount = tonumber(Config.Xp.eventComplete) or 0
    if amount <= 0 then return end

    for _, src in ipairs(participants) do
        src = tonumber(src)
        if src and IsAlive(src) then
            AwardXp(src, amount, 'event_complete:' .. tostring(eventId or '?'))
        end
    end
end)

-- Consolation prize: someone helped but wasn't on the final completion list.
AddEventHandler('corex-events:server:eventParticipated', function(src, eventId)
    if not Config.Xp then return end
    local amount = tonumber(Config.Xp.eventParticipate) or 0
    if amount > 0 and src and IsAlive(src) then
        AwardXp(src, amount, 'event_participate:' .. tostring(eventId or '?'))
    end
end)

-- ---------------------------------------------------------------------------
-- Redzone / dynamic container loot (corex-loot)
-- ---------------------------------------------------------------------------
-- Fired from corex-loot the moment a container is fully emptied. Only counts
-- dynamic / event-driven containers so static loot farming doesn't dominate.
AddEventHandler('corex-loot:server:onContainerLooted', function(src, containerId, isDynamic)
    if not Config.Xp then return end
    if not isDynamic then return end
    local amount = tonumber(Config.Xp.redzoneContainer) or 0
    if amount > 0 and src and IsAlive(src) then
        AwardXp(src, amount, 'redzone_loot:' .. tostring(containerId or '?'))
    end
end)

-- ---------------------------------------------------------------------------
-- Survival milestones (corex-survival)
-- ---------------------------------------------------------------------------
-- Reward "earned" recoveries: curing yourself when really infected is harder
-- than topping up at 5%, so we gate by a minimum infection level.
AddEventHandler('corex-survival:server:onInfectionCured', function(src, fromValue)
    if not Config.Xp or not src then return end
    if (tonumber(fromValue) or 0) < 50 then return end
    local amount = tonumber(Config.Xp.infectionCured) or 0
    if amount > 0 then
        AwardXp(src, amount, 'infection_cured')
    end
end)
