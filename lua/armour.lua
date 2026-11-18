-- Light and heavy armour.
--
--   * Light armour (the suit up to the Heavy Ballistic Vest) is the game's:
--     it regenerates by itself, and once broken it protects nothing.
--   * Heavy armour (Flak Jacket, Combined Tactical Vest, ICTV) does not come
--     back by the game's regeneration timer once it is broken. The player
--     inserts a new plate (an inventory item, to hand) to fill it again.
--     Perk decks and skills that give armour back still work: only the
--     timer (and a revive) is blocked.
--   * Broken heavy armour still takes part of the damage to every body part
--     but the head (Armour.HEAVY: the ICTV takes 25% off).
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Armour = PDTI.Armour or {}
PDTI.Armour = Armour

-- What broken heavy armour still takes off the damage to a body part.
Armour.HEAVY = { level_5 = 0.10, level_6 = 0.18, level_7 = 0.25 }
Armour.NAMES = {
    level_1 = "Two-piece Suit", level_2 = "Lightweight Ballistic Vest", level_3 = "Ballistic Vest",
    level_4 = "Heavy Ballistic Vest", level_5 = "Flak Jacket", level_6 = "Combined Tactical Vest",
    level_7 = "ICTV"
}
Armour.PLATE_ITEM = "armor_kit"
Armour.PLATE_TIME = 3      -- seconds to insert a plate
Armour.PLATE_SPEED = 0.6   -- the speed while inserting it
Armour.HINT_EVERY = 0.5

-- had_armor: the armour was seen above 0 this heist. Only then can it break:
-- in the first frames of a heist (or with a deck that has no armour) the
-- armour can read 0 without anything having broken it.
local state = { broken = false, plating = nil, hinted_broken = false, last_hint = nil, id = nil, had_armor = false }
Armour.state = state

local log = PDTI.Logger("PDTI ARMOUR")

local hint = PDTI.Hint

function Armour.Enabled()
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return not (s and s.heavy_armour == false)
end

-- The equipped armour ("level_1" .. "level_7"), once per heist.
function Armour.Id()
    if state.id then return state.id end
    local ok, id = pcall(function() return managers.blackmarket:equipped_armor(true, true) end)
    if ok and type(id) == "string" then state.id = id end
    return state.id
end

function Armour.IsHeavy()
    return Armour.Enabled() and Armour.HEAVY[Armour.Id() or ""] ~= nil
end

function Armour.Name()
    local id = Armour.Id()
    return Armour.NAMES[id or ""] or tostring(id or "Armour")
end

local player_damage = PDTI.PlayerDamage

local function real_armor(pd)
    local ok, value = pcall(function() return pd:get_real_armor() end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function max_armor(pd)
    local ok, value = pcall(function() return pd:_max_armor() end)
    if ok and type(value) == "number" then return value end
    return nil
end

local function is_player(pd)
    return pd ~= nil and pd == player_damage()
end

-- Notes heavy armour at 0 as broken (until a plate), once it was seen
-- above 0 in this heist.
local function check_broken(pd)
    if not Armour.IsHeavy() then return state.broken end
    local armor = real_armor(pd)
    if armor and armor > 0 then state.had_armor = true end
    local max = max_armor(pd)
    if armor and armor <= 0 and not state.broken and state.had_armor and (max == nil or max > 0) then
        state.broken = true
        if not state.hinted_broken then
            state.hinted_broken = true
            hint("Armour broken: insert a plate (Insert Armour Plate key)")
        end
        log(Armour.Name() .. " broken")
    end
    return state.broken
end

function Armour.IsBroken()
    return Armour.IsHeavy() and state.broken
end

-- What broken heavy armour takes off a body part's damage (0 to 1). While a
-- perk has given some armour back, the game's armour protects as usual.
function Armour.Protection(pd)
    if not Armour.IsHeavy() then return 0 end
    pd = pd or player_damage()
    if not pd then return 0 end
    local armor = real_armor(pd)
    if not armor or armor > 0 then return 0 end
    if not check_broken(pd) then return 0 end
    return Armour.HEAVY[Armour.Id()] or 0
end

-- John Wick's and Jiro's rooms (perks.lua).
local function perks() return PDTI.Perks end

function Armour.PlateTime()
    local p = perks()
    if p and p.PlateTime then return p.PlateTime(Armour.PLATE_TIME) end
    return Armour.PLATE_TIME
end

function Armour.SpeedFactor()
    if not state.plating then return 1 end
    local p = perks()
    if p and p.PlateFullSpeed and p.PlateFullSpeed() then return 1 end
    return Armour.PLATE_SPEED
end

------------------------------------------------------------------ hooks

Armour.hooks = Armour.hooks or {}
local hooks = Armour.hooks
local in_revive = false
local plate_refill = false

local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(hooks, "armour", class_name, fn_name, make)
end

-- The game's regeneration timer: stopped on broken heavy armour.
local function make_timer(orig)
    return function(self, ...)
        if Armour.IsHeavy() and is_player(self) and check_broken(self) and not plate_refill then
            self._current_state = nil
            return
        end
        return orig(self, ...)
    end
end

-- The refill itself: blocked only when it comes from a revive. Perks (the
-- armour bag, regeneration on the side, the mission) still refill.
local function make_regenerate(orig)
    return function(self, ...)
        if in_revive and not plate_refill and Armour.IsHeavy() and is_player(self) and state.broken then
            self._current_state = nil
            return
        end
        return orig(self, ...)
    end
end

local function make_revive(orig)
    return function(self, ...)
        if not (Armour.IsHeavy() and is_player(self)) then return orig(self, ...) end
        check_broken(self)
        in_revive = true
        local ok, result = pcall(orig, self, ...)
        in_revive = false
        if not ok then error(result, 0) end
        return result
    end
end

function Armour.InstallHooks()
    -- Every frame: no closure; all three are tried, as before.
    local a = wrap("PlayerDamage", "_update_regenerate_timer", make_timer)
    local b = wrap("PlayerDamage", "_regenerate_armor", make_regenerate)
    local c = wrap("PlayerDamage", "revive", make_revive)
    return a and b and c
end

------------------------------------------------------------------ plates

-- A plate in the pockets or the rig: container and instance id.
function Armour.FindPlate()
    for _, name in ipairs(PDTI.TO_HAND or { "pockets", "rig", "rig_2", "rig_3" }) do
        for _, entry in ipairs(PDTI.FindItems(function(c, item)
            return c == name and item.item_id == Armour.PLATE_ITEM
        end)) do
            return entry.container, entry.item.instance_id
        end
    end
    return nil
end

local function downed()
    local ok, s = pcall(function() return managers.player:current_state() end)
    return ok and (s == "bleed_out" or s == "fatal" or s == "incapacitated" or s == "arrested")
end

-- Starts inserting a plate. Returns true, or false and why.
function Armour.StartPlate()
    local function refuse(why) hint(why); return false, why end
    if PDTI.InSafehouse() then return refuse("Not in the safehouse") end
    if not Armour.Enabled() then return refuse("Heavy armour rules are off") end
    if state.plating then return false, "already inserting a plate" end
    if not Armour.IsHeavy() then return refuse(Armour.Name() .. " is light armour: it regenerates by itself") end
    if downed() then return refuse("Not while you are down") end
    local pd = player_damage()
    if not pd then return false, "no player" end
    local armor, max = real_armor(pd), max_armor(pd)
    if armor and max and armor >= max - 1e-6 then return refuse("Your armour is whole") end
    if not Armour.FindPlate() then
        local in_bag = #PDTI.FindItems(function(_, item) return item.item_id == Armour.PLATE_ITEM end) > 0
        return refuse(in_bag and "Your plates are in the backpack: move one to the rig or the pockets"
            or "You have no armour plates")
    end
    local time = Armour.PlateTime()
    state.plating = { left = time }
    state.last_hint = nil
    if PDTI.Carry and PDTI.Carry.InvalidateCache then pcall(PDTI.Carry.InvalidateCache) end
    hint(string.format("Inserting plate... %.1f s", time))
    return true
end

function Armour.CancelPlate(why)
    if not state.plating then return end
    state.plating = nil
    if PDTI.Carry and PDTI.Carry.InvalidateCache then pcall(PDTI.Carry.InvalidateCache) end
    if why then hint("Plate not inserted: " .. why) end
end

-- The plate is in: one plate is used, the armour is full.
local function finish_plate()
    state.plating = nil
    if PDTI.Carry and PDTI.Carry.InvalidateCache then pcall(PDTI.Carry.InvalidateCache) end
    local container, instance_id = Armour.FindPlate()
    if not container then hint("Plate not inserted: no plate to hand"); return false end
    local pd = player_damage()
    if not pd then return false end
    local ok = PDTI.RemoveItem(container, instance_id, 1)
    if not ok then return false end
    state.broken = false
    state.hinted_broken = false
    plate_refill = true
    local done = pcall(function() pd:_regenerate_armor() end)
    plate_refill = false
    if not done then pcall(function() pd:set_armor(pd:_max_armor()) end) end
    hint("Plate inserted")
    log("plate inserted")
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    return true
end

-- Every frame of the heist (the game tick, with the state's input).
function Armour.Tick(input, dt)
    local pd = player_damage()
    if pd and Armour.IsHeavy() then check_broken(pd) end
    local p = state.plating
    if not p then return end
    if downed() then Armour.CancelPlate("you went down"); return end
    local p_ = perks()
    local keeps = p_ and p_.PlateKeepsFiring and p_.PlateKeepsFiring()
    if input and input.btn_reload_press then
        Armour.CancelPlate("you reloaded")
        return
    end
    if input and not keeps and (input.btn_primary_attack_press or input.btn_primary_attack_state) then
        Armour.CancelPlate("you fired")
        return
    end
    p.left = p.left - (tonumber(dt) or 0)
    if p.left <= 0 then
        finish_plate()
        return
    end
    local now = PDTI.AppTime()
    if not state.last_hint or now - state.last_hint >= Armour.HINT_EVERY then
        state.last_hint = now
        hint(string.format("Inserting plate... %.1f s", p.left))
    end
end

-- One line for the health window.
function Armour.StatusLine()
    if not Armour.Enabled() then return nil end
    local id = Armour.Id()
    if not id then return nil end
    if not Armour.IsHeavy() then return "Armour: " .. Armour.Name() .. " (light, regenerates)" end
    local pct = math.floor((Armour.HEAVY[id] or 0) * 100 + 0.5)
    if state.plating then return string.format("Armour: %s, inserting a plate", Armour.Name()) end
    if state.broken then
        return string.format("Armour: %s broken: body -%d%% damage, insert a plate", Armour.Name(), pct)
    end
    return string.format("Armour: %s (heavy, plates; broken: -%d%%)", Armour.Name(), pct)
end

function Armour.OnHeistStart()
    state.broken = false
    state.plating = nil
    state.hinted_broken = false
    state.last_hint = nil
    state.id = nil
    state.had_armor = false
end
