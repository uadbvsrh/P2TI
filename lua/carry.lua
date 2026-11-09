-- Carry weight and movement speed.
--
-- Your speed is the product of three parts:
--
--   * the armour: exactly the game's own armour slowdown (the game's version
--     of it is taken out of its speed calculation, so it is not counted twice);
--   * the load: the kilograms in the rig, the pockets and the backpack plus
--     your weapons and throwables. Up to FREE_WEIGHT is free, at FULL_WEIGHT
--     you are at MIN_FACTOR;
--   * the loot: every bag you carry, in your hands or in the inventory.
--     A bag of a class the game lets you carry at full speed (light, medium)
--     costs LIGHT_BAG_PENALTY for every such bag after the first. Every other
--     bag costs the game's own penalty of its class, again for every bag:
--     a heavy bag 25% (75% speed), two of them 50%. The class penalty is
--     computed like the game does it (the carry speed bonus every player has
--     and the skills that change it count), and the game's slowdown for the
--     bag in your hands is replaced by this, so it is not counted twice.
--
-- The rig and the backpack change it too (gear.lua): a speed bonus (general
-- rig, small backpack) and a smaller load and loot slowdown (large backpack).
--
-- The factor is applied through PlayerManager:movement_speed_multiplier,
-- the multiplier the game itself uses for the walk speed, so it reaches
-- every movement state and is synced like the game's own speed.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Carry = PDTI.Carry or {}
PDTI.Carry = Carry

-- Kilograms you can carry without slowing down.
Carry.FREE_WEIGHT = 15
-- Kilograms at which the load is at its slowest.
Carry.FULL_WEIGHT = 60
-- The slowest the load can make you: 0.6 is 40% slower.
Carry.MIN_FACTOR = 0.6
-- A light or medium bag after the first.
Carry.LIGHT_BAG_PENALTY = 0.15
-- You never get slower than this.
Carry.FLOOR = 0.1
if Carry.enabled == nil then Carry.enabled = true end

local hooks = {}

local function log(message)
    local line = "[PDTI CARRY] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

------------------------------------------------------------------ the parts

-- The kilograms that count in the load: the grids without the loot bags
-- (the loot has its own rule) plus the weapons and throwables.
function Carry.LoadWeight()
    local weight = 0
    for _, entry in ipairs(PDTI.FindItems(function() return true end)) do
        local item = entry.item
        if item.item_id ~= "loot_bag" then
            weight = weight + PDTI.ItemWeight(item)
        end
    end
    if PDTI.Loadout and PDTI.Loadout.LoadWeight then
        local ok, extra = pcall(PDTI.Loadout.LoadWeight)
        if ok and type(extra) == "number" then weight = weight + extra end
    end
    return weight
end

function Carry.LoadFactor(weight)
    weight = weight or Carry.LoadWeight()
    if weight <= Carry.FREE_WEIGHT then return 1 end
    local span = Carry.FULL_WEIGHT - Carry.FREE_WEIGHT
    if span <= 0 then return Carry.MIN_FACTOR end
    local t = math.min(1, (weight - Carry.FREE_WEIGHT) / span)
    return 1 - t * (1 - Carry.MIN_FACTOR)
end

function Carry.ArmourFactor()
    if not PDTI.Loadout or not PDTI.Loadout.ArmourPenalty then return 1 end
    local ok, penalty = pcall(PDTI.Loadout.ArmourPenalty)
    if not ok or type(penalty) ~= "number" then return 1 end
    return 1 - math.max(0, math.min(1, penalty))
end

local function upgrade(category, name, default)
    local ok, value = pcall(function() return managers.player:upgrade_value(category, name, default) end)
    if ok and value ~= nil then return value end
    return default
end

local function has_upgrade(category, name)
    local ok, value = pcall(function() return managers.player:has_category_upgrade(category, name) end)
    return ok and value and true or false
end

-- The speed the game gives while carrying one bag of this class: its
-- modifier times the carry speed bonus, at most 100%.
function Carry.BagSpeed(carry_id)
    local carry = tweak_data and tweak_data.carry
    local bag = carry and carry_id and carry[carry_id]
    local class = bag and bag.type and carry.types and carry.types[bag.type]
    local modifier = class and tonumber(class.move_speed_modifier) or 1
    local bonus = tonumber(upgrade("carry", "movement_speed_multiplier", 1)) or 1
    return math.max(0, math.min(1, modifier * bonus))
end

function Carry.LootFactor()
    if has_upgrade("carry", "movement_penalty_nullifier") then return 1 end
    local light, penalty = 0, 0
    for _, entry in ipairs(PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end)) do
        local data = type(entry.item.data) == "table" and entry.item.data or {}
        local amount = tonumber(entry.item.amount) or 1
        local speed = Carry.BagSpeed(data.carry_id)
        if speed >= 1 then
            light = light + amount
        else
            penalty = penalty + (1 - speed) * amount
        end
    end
    penalty = penalty + Carry.LIGHT_BAG_PENALTY * math.max(0, light - 1)
    return math.max(0, 1 - penalty)
end

-- Every part of the speed, for the screen.
local function gear(fn, default)
    local g = PDTI.Gear
    if not g or not g[fn] then return default end
    local ok, value = pcall(g[fn])
    if ok and type(value) == "number" then return value end
    return default
end

function Carry.GetBreakdown()
    local weight = Carry.LoadWeight()
    local scale = gear("PenaltyScale", 1)
    local parts = {
        load_weight = weight,
        load = 1 - (1 - Carry.LoadFactor(weight)) * scale,
        armour = Carry.ArmourFactor(),
        loot = 1 - (1 - Carry.LootFactor()) * scale,
        gear = 1 + gear("SpeedBonus", 0),
        legs = 1
    }
    local body = PDTI.Body
    if body and body.SpeedFactor then
        local ok, value = pcall(body.SpeedFactor)
        if ok and type(value) == "number" then parts.legs = value end
    end
    parts.total = Carry.enabled
        and math.max(Carry.FLOOR, parts.load * parts.armour * parts.loot * parts.gear * parts.legs) or 1
    return parts
end

-- The game asks for the speed several times a frame; the weapons'
-- concealment is not cheap to compute. The factor is recomputed when the
-- inventory changes, and at least every CACHE_TIME seconds (throwables
-- used, armour changed).
Carry.CACHE_TIME = 0.5
local cache = { value = nil, revision = nil, t = nil }

local function clock()
    local ok, t = pcall(function() return Application:time() end)
    if ok and type(t) == "number" then return t end
    return os.clock()
end

function Carry.InvalidateCache()
    cache.value = nil
end

-- 1.0 = no penalty, lower is slower.
function Carry.GetSpeedFactor()
    if not Carry.enabled then return 1 end
    local now = clock()
    local revision = PDTI.inventory_revision or 0
    if cache.value and cache.revision == revision and cache.t and now - cache.t < Carry.CACHE_TIME then
        return cache.value
    end
    cache.value = Carry.GetBreakdown().total
    cache.revision = revision
    cache.t = now
    return cache.value
end

------------------------------------------------------------------ the hooks

local function wrap(class_name, fn_name, make)
    local cls = rawget(_G, class_name)
    local current = cls and cls[fn_name]
    if type(current) ~= "function" then return false end
    local key = class_name .. "." .. fn_name
    if hooks[key] == current then return true end
    if PDTI.HookHas(current, "carry") then return true end
    local hook = make(current)
    PDTI.HookMark(hook, current, "carry")
    hooks[key] = hook
    cls[fn_name] = hook
    return true
end

local function in_heist(pm)
    local ok, unit = pcall(function() return pm:player_unit() end)
    return ok and unit ~= nil
end

function Carry.InstallHooks()
    local speed = wrap("PlayerManager", "movement_speed_multiplier", function(orig)
        return function(self, speed_state, bonus_multiplier, upgrade_level, health_ratio)
            local result = orig(self, speed_state, bonus_multiplier, upgrade_level, health_ratio)
            -- The menu's armour preview passes a level: it stays the game's.
            if not Carry.enabled or upgrade_level ~= nil or not in_heist(self) then return result end
            local ok, value = pcall(function()
                local r = result
                -- The game's armour slowdown is taken out; the armour slot
                -- applies the same value below.
                local armour = self:mod_movement_penalty(self:body_armor_value("movement", nil, 1))
                if armour < 1 then r = r + (1 - armour) end
                return r * Carry.GetSpeedFactor()
            end)
            if ok and type(value) == "number" then return value end
            return result
        end
    end)
    -- The game slows you for the bag in your hands; for loot that is part of
    -- the loot factor now.
    local carry = wrap("PlayerCarry", "_get_max_walk_speed", function(orig)
        return function(self, ...)
            local loot = Carry.enabled and PDTI.Loot and PDTI.Loot.CarriedId and PDTI.Loot.CarriedId()
            if loot and PlayerCarry.super and PlayerCarry.super._get_max_walk_speed then
                return PlayerCarry.super._get_max_walk_speed(self, ...)
            end
            return orig(self, ...)
        end
    end)
    if speed and not hooks._logged then
        hooks._logged = true
        log(string.format("movement penalty installed (free %d kg, slow at %d kg; loot and armour apply)",
            Carry.FREE_WEIGHT, Carry.FULL_WEIGHT))
    end
    return speed and carry
end

-- The current factor, for the inventory screen.
function Carry.Refresh()
    return Carry.GetSpeedFactor()
end
