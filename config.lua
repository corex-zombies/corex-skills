Config = {}

Config.Debug = true

-- Starting points granted to fresh players (one-time on first sync).
Config.StartingPoints = 3

-- Hard cap on stored skill points (anti-bug ceiling, not a balance setting).
Config.MaxPoints = 999

-- Allow respeccing? (refunds all points and clears unlocks except root)
Config.AllowRespec = true
Config.RespecCost = 0       -- in cash; 0 = free for now

-- Auto-grant the root node so the tree is usable from the start.
Config.AutoGrantRoot = true

-- Open key & command (FiveM key bind for client)
Config.OpenCommand = 'skills'
Config.OpenKey     = 'K'

-- =============================================================================
-- XP Economy
-- =============================================================================
-- Internally we accumulate XP, then convert XP -> skill points at this rate.
-- 100 XP = 1 skill point keeps "0.5 point per 30 minutes of play" intuitive.
Config.XpPerPoint = 100

-- Lifetime XP cap (sanity ceiling). Players still earn after the cap, but it
-- stops growing — points keep flowing as long as they can.
Config.MaxXpTotal = 1000000

-- XP sources. Set any value to 0 to disable that source.

Config.Xp = {
    playtimeIntervalMs = 30 * 1000,              -- 30 ثانية بدل 30 دقيقة
    playtimeAmount     = 50,
    zombieKill         = 5,
    zombieKillSpecial  = 15,
    eventComplete      = 100,
    eventParticipate   = 25,
    redzoneContainer   = 25,
    infectionCured     = 50
}
Config.AfkThresholdMs = 60 * 1000  

-- Config.Xp = {
--     -- Playtime drip: players who stay logged in (and not AFK) get a slow drip
--     -- so casual players can still progress, but it should never dominate.
--     playtimeIntervalMs = 30 * 60 * 1000,  -- every 30 minutes
--     playtimeAmount     = 50,              -- = 0.5 point / 30 min = 1 point / hour

--     -- Zombie kills. Many small grants > one big grant: keeps engagement up.
--     zombieKill         = 5,               -- 5 XP per kill (20 kills = 1 point)
--     zombieKillSpecial  = 15,              -- bonus for special types (brute, etc.)

--     -- Events (corex-events): grants on successful completion to participants.
--     eventComplete      = 100,             -- = 1 point per completed event
--     eventParticipate   = 25,              -- consolation if event ends without you

--     -- Loot pickups inside redzones / event containers.
--     redzoneContainer   = 25,              -- 4 containers = 1 point

--     -- Survival milestones (corex-survival).
--     infectionCured     = 50,              -- cured >= 50% infection with antidote
--     bleedSurvived      = 10                -- (reserved for future bleed system)
-- }

-- Anti-AFK: the playtime drip only fires while the player has been "active"
-- (recent input or movement) within this window. Any input resets the timer.
Config.AfkThresholdMs = 5 * 60 * 1000   -- 5 minutes idle = no playtime XP

-- Must the player be alive (HP > 0) to earn ANY XP? Keeps respawn-farming
-- exploits in check.
Config.RequireAlive = true

-- =============================================================================
-- UI / Notifications
-- =============================================================================
-- Show toast on every XP gain? Disable if it gets noisy on big servers.
Config.ShowXpToasts = true

-- Show special toast when a skill point is earned (every XpPerPoint XP).
Config.ShowPointToasts = true

-- Path color tokens (also used by the UI for branding the panel)
Config.Colors = {
    combat    = { primary = '#DC2626', icon = '#FCA5A5' },
    survivor  = { primary = '#10B981', icon = '#6EE7B7' },
    craftsman = { primary = '#F59E0B', icon = '#FCD34D' },
    core      = { primary = '#FFFFFF', icon = '#FFFFFF' }
}

-- Layout constants (must mirror the values used inside the NUI; do not edit
-- without updating html/script.js viewBox + layout helpers).
Config.Layout = {
    VBW = 1360,
    VBH = 620,
    BRANCH_OFFSET = 90,
    PATH_X = { combat = 340, survivor = 680, craftsman = 1020 },
    TIER_Y = { root = 555, [1] = 465, [2] = 375, [3] = 285, [4] = 195, cap = 105 }
}

-- Event names (kept stable so other resources can listen).
Config.Events = {
    Unlocked       = 'corex-skills:server:onUnlocked',     -- (src, skillId)
    PointsGained   = 'corex-skills:server:onPointsGained', -- (src, delta, total)
    Respec         = 'corex-skills:server:onRespec',       -- (src)
    XpAwarded      = 'corex-skills:server:onXpAwarded',    -- (src, amount, reason, newXp)
    ModifiersDirty = 'corex-skills:server:onModifiersDirty'-- (src, modifiers)
}
