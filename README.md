# corex-skills

> Skill tree + XP system for the **COREX** zombie-survival framework.
> 21 skills across Combat / Survivor / Craftsman, every one wired to a real
> in-game effect via `corex-inventory`, `corex-survival`, and `corex-crafting`.

```
Dependencies : corex-core
Optional     : corex-survival · corex-inventory · corex-crafting · corex-zombies · corex-events · corex-loot
NUI key      : K   (open / close the skill tree)
```

---

## Install

1. Drop into `server-file/resources/[corex]/corex-skills/`.
2. `ensure corex-skills` in `server.cfg` **after** `corex-core`.
3. Restart the server. Player metadata persists automatically through corex-core.

---

## Config reference (`config.lua`)

### General

| Key | Default | What it does |
|---|---|---|
| `Config.Debug` | `false` | Console traces (regen-gate flips, zombie kill XP, etc.). |
| `Config.StartingPoints` | `18` | Skill points granted to a brand-new player on first sync. |
| `Config.MaxPoints` | `999` | Hard ceiling on stored skill points (anti-bug, not balance). |
| `Config.AllowRespec` | `true` | Show the respec button in the NUI. |
| `Config.RespecCost` | `0` | Cash cost per respec. `0` = free. |
| `Config.AutoGrantRoot` | `true` | Auto-unlocks the Root node so the tree is usable from spawn. |
| `Config.OpenCommand` | `'skills'` | Chat command to toggle the tree (`/skills`). |
| `Config.OpenKey` | `'K'` | FiveM key binding for the same toggle. |

### XP economy

| Key | Default | What it does |
|---|---|---|
| `Config.XpPerPoint` | `100` | XP needed to spawn 1 skill point. Spillover carries forward. |
| `Config.MaxXpTotal` | `1 000 000` | Lifetime XP ceiling (statistic only — points keep flowing). |
| `Config.AfkThresholdMs` | `300 000` (5 min) | Player must move at least 1m within this window to earn playtime XP. |
| `Config.RequireAlive` | `true` | Must have HP > 0 to earn any XP source. |
| `Config.ShowXpToasts` | `true` | Show a "+50 XP — Playtime" pop on every XP gain. |
| `Config.ShowPointToasts` | `true` | Show a "+1 PT" celebration when an XP grant tips a full point. |

### XP sources (`Config.Xp`)

Set any value to `0` to disable that source.

| Key | Default | When it fires |
|---|---|---|
| `playtimeIntervalMs` | `1 800 000` (30 min) | Tick cadence for the playtime drip. |
| `playtimeAmount` | `50` | XP per tick (default = ½ point per 30 min = 1 point/hour). |
| `zombieKill` | `5` | Per zombie killed (relayed from corex-zombies). |
| `zombieKillSpecial` | `15` | Bonus for non-walker types (brute, runner, etc.). |
| `eventComplete` | `100` | Per player who was within 120 m when a corex-events event ended. |
| `eventParticipate` | `25` | Consolation for being on the participants list but not the final completion. |
| `redzoneContainer` | `25` | Per fully-emptied dynamic / event container (corex-loot). |
| `infectionCured` | `50` | Antidote / antibiotics used at infection ≥ 50 %. |

### Events (other resources can listen)

```lua
AddEventHandler('corex-skills:server:onUnlocked',      function(src, skillId) … end)
AddEventHandler('corex-skills:server:onPointsGained',  function(src, delta, total) … end)
AddEventHandler('corex-skills:server:onXpAwarded',     function(src, amount, reason, newXp) … end)
AddEventHandler('corex-skills:server:onRespec',        function(src) … end)
AddEventHandler('corex-skills:server:onModifiersDirty',function(src, modifiers) … end)
```

---

## Skill catalog

| Branch | ID | Cost | Effect |
|---|---|---|---|
| Combat | `c_steady` | 1 | -25 % weapon sway, -15 % recoil |
| Combat | `c_reload` | 2 | Reload animation 25 % faster |
| Combat | `c_iron` | 2 | ADS transition snap (subjective) |
| Combat | `c_head` | 3 | +30 % headshot damage (head-bone hit detection) |
| Combat | `c_recoil` | 4 | -50 % recoil |
| Combat | `c_akimbo` | 4 | +40 % fire rate on pistols / SMGs |
| Combat | `c_exec` (capstone) | 6 | LASER MODE: total recoil ≤ 2 %, 2× damage on sub-30 % HP targets |
| Survivor | `s_tough` | 1 | Max HP 200 → 240 |
| Survivor | `s_endurance` | 2 | +30 % stamina regen, -25 % sprint cost |
| Survivor | `s_iron_body` | 3 | Hunger / thirst drain × 0.65 |
| Survivor | `s_cold` | 3 | Cold rise rate × 0.5 + cold damage × 0.5 |
| Survivor | `s_bleed` | 4 | Bleed drain × 0.5 |
| Survivor | `s_plague` | 4 | Bite chance × 0.5 |
| Survivor | `s_immunity` (capstone) | 6 | Bites never infect |
| Craftsman | `k_quick` | 1 | Craft duration ÷ 1.25 |
| Craftsman | `k_material` | 2 | Material cost × 0.80 |
| Craftsman | `k_solid` | 2 | Crafted items get `qualityBonus = 0.30` (heal 30 % more) |
| Craftsman | `k_master` | 3 | Unlocks `unlocksRareRecipes` flag + `qualityBonus = 0.15` |
| Craftsman | `k_lock` | 4 | Lockpick green-zone +60 % |
| Craftsman | `k_modder` | 4 | Unlocks `unlocksWeaponMods` flag |
| Craftsman | `k_insta` (capstone) | 6 | 20 % chance to skip materials AND duration |

Mappings live in [`shared/modifiers.lua`](shared/modifiers.lua) (`SKILL_EFFECTS` table).
Tree positions / parents in [`shared/skills.lua`](shared/skills.lua).

---

## Public API

### Server exports

```lua
-- Read state
exports['corex-skills']:HasSkill(src, skillId)            -- bool
exports['corex-skills']:GetUnlockedSkills(src)            -- table<string>
exports['corex-skills']:GetSkillPoints(src)               -- number
exports['corex-skills']:GetXp(src)                        -- number (0..XpPerPoint-1)
exports['corex-skills']:GetXpTotal(src)                   -- number (lifetime)
exports['corex-skills']:GetSkillInfo(skillId)             -- {id,name,path,tier,cost,desc} | nil
exports['corex-skills']:GetSkillForFlag(flag)             -- {id,name,path,tier} | nil

-- Modifier broker (always returns a complete neutral table)
exports['corex-skills']:GetModifiers(src)                 -- flat table (see shared/modifiers.lua)
exports['corex-skills']:GetModifier(src, key)             -- single value

-- Mutators
exports['corex-skills']:AwardXp(src, amount, reason)      -- ok, newXp, points, gainedPoints
exports['corex-skills']:AddSkillPoints(src, amount)       -- ok, newTotal
exports['corex-skills']:GiveSkillPoints(src, amount)      -- alias of AddSkillPoints

-- Crafting gate (recipe.requiresSkill / requiresFlag)
exports['corex-skills']:CanCraftRecipe(src, recipe)       -- ok, reason, missingId
```

### Client exports

```lua
exports['corex-skills']:HasSkill(skillId)                 -- own player, bool
exports['corex-skills']:GetLocalModifiers()               -- live snapshot
exports['corex-skills']:GetLocalModifier(key)             -- single value
exports['corex-skills']:GetLocalUnlocked()                -- table<string>

-- Lockpick minigame: synchronous-ish, blocks until result
local ok = exports['corex-skills']:OpenLockpick({
    pins         = 3,
    cursorMs     = 1400,
    zoneFraction = 0.18,
    timeoutMs    = 30000
})
```

---

## Admin commands

| Command | Effect |
|---|---|
| `/skills` (or `K`) | Open / close the skill tree. |
| `/giveskillpoints [id] amount` | Direct point grant. |
| `/giveskillxp [id] amount` | Grant raw XP (spills into points at the threshold). |
| `/skillsmods [id]` | Print the active modifier table to console. |
| `/myskills` | Same as above, client-side (F8). |
| `/resetskills [id]` | Wipe unlocks + XP back to defaults. |
| `/testlockpick` | Run the lockpick minigame standalone. |

---

## Integration recipes

### Award XP from your own resource
```lua
exports['corex-skills']:AwardXp(src, 25, 'fishing_caught_rare')
```
The `reason` shows up on the client toast (`+25 XP — Fishing Caught Rare`).

### Read a modifier safely
```lua
local function GetMod(src, key, default)
    local ok, mods = pcall(function()
        return exports['corex-skills']:GetModifiers(src)
    end)
    if ok and type(mods) == 'table' and mods[key] ~= nil then return mods[key] end
    return default
end

local craftSpeed = GetMod(src, 'craftSpeed', 1.0)
local duration   = math.floor(baseDuration / craftSpeed)
```

### Gate a crafting recipe behind a skill
In `corex-crafting/config.lua`:
```lua
{
    id = 'craft_my_recipe',
    -- materials, duration, etc. as normal
    requiresSkill = 'k_master',           -- single id or array
    requiresFlag  = 'unlocksRareRecipes', -- modifier flag
}
```
The recipe is greyed-out in the UI until both gates pass; the detail panel shows
`Required Skill: Master Crafter [LOCKED]`.

---

## Persistence

Stored under `metadata.skills` via corex-core:

```lua
metadata.skills = {
    unlocked = { 'root', 'c_steady', 's_tough' },
    points   = 14,
    xp       = 73,        -- 0..XpPerPoint-1, accumulator
    xpTotal  = 412        -- lifetime, capped at MaxXpTotal
}
```

Forward-compatible: missing fields are populated with safe defaults on load,
unknown skill ids are dropped silently.

---

## File map

```
corex-skills/
├── fxmanifest.lua
├── config.lua             # all tunables
├── shared/
│   ├── skills.lua         # tree definition (22 nodes)
│   └── modifiers.lua      # skill → modifier mapping + aggregator
├── server/
│   ├── main.lua           # state, exports, unlock/respec, broadcasts
│   └── xp.lua             # XP earning sources (playtime, kills, events…)
├── client/
│   └── main.lua           # NUI bridge + native effect driver + heartbeat + lockpick API
└── html/                  # NUI: SVG tree + XP bar + toast + lockpick minigame
    ├── index.html
    ├── style.css
    └── script.js
```

---

## License

MIT — same as the rest of [COREX](https://github.com/corex-zombies).
