-- Shotgun shells: the game's own ammunition types, shell by shell.
--
-- The game gives a shotgun one ammunition type: the ammo mod in its
-- blueprint. NewRaycastWeaponBase:_update_stats_values (and ShotgunBase's,
-- which adds rays and near/far damage) turns the blueprint into the weapon's
-- fields: _ammo_data, _rays, _bullet_class, damage, spread, falloff, effects.
--
-- To let every shell be a different type without changing what the types
-- do, this module asks the game itself: for each shell it runs the weapon's
-- own _update_stats_values on a copy of the blueprint with that shell's ammo
-- part (and no other ammo part), keeps the fields that came out (a profile),
-- and puts the real blueprint back. A shot then copies the profile of the
-- shell being fired onto the weapon, right before the game works out the
-- shot (ammo_hooks.lua, the damage hook).
--
-- The weapon's own ammo mod does not count: the shells you load decide, as
-- the magazines you load decide for assault rifles.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Ammo then return end
local Ammo = PDTI.Ammo

local Shells = PDTI.Shells or {}
PDTI.Shells = Shells

local function log(message)
    if Ammo.log then Ammo.log(message) end
end

-- Fields the ammunition type sets (always copied, also when equal).
Shells.FIELDS = {
    "_ammo_data", "_rays", "_damage_near", "_damage_far",
    "_bullet_class", "_bullet_slotmask", "_blank_slotmask",
    "_can_shoot_through_shield", "_can_shoot_through_enemy", "_can_shoot_through_wall",
    "_armor_piercing_chance",
    "_current_stats", "_current_stats_indices",
    "_spread", "_recoil", "_spread_moving", "_suppression", "_alert_size", "_spread_multiplier",
    "_optimal_distance", "_optimal_range", "_near_falloff", "_far_falloff",
    "_near_multiplier", "_far_multiplier",
    "_muzzle_effect", "_muzzle_effect_table", "_trail_effect", "_trail_effect_table",
    "_fire_rate_multiplier", "_movement_penalty"
}

-- Never copied: the ammunition counts belong to the inventory, the fire mode
-- to the player, the rest to the weapon's identity and this mod.
Shells.NEVER = {
    _extra_ammo = true, _total_ammo_mod = true, _fire_mode = true, _locked_fire_mode = true,
    _blueprint = true, _parts = true, _factory_id = true, _name_id = true, _unit = true,
    _setup = true, _ammo = true, _assembly_complete = true, _second_gun = true
}

local SCALAR = { number = true, boolean = true, string = true }

local function is_ammo_part(part_id)
    local parts = tweak_data and tweak_data.weapon and tweak_data.weapon.factory and tweak_data.weapon.factory.parts
    local part = parts and parts[part_id]
    return type(part) == "table" and part.type == "ammo"
end

-- The blueprint with this shell's ammo part instead of any other.
function Shells.Blueprint(blueprint, id)
    local out = {}
    for _, part in ipairs(blueprint or {}) do
        if not is_ammo_part(part) then out[#out + 1] = part end
    end
    local def = Ammo.BULLETS[id]
    if def and def.family == "shell" and def.part then out[#out + 1] = def.part end
    return out
end

local function snapshot(wep)
    local snap = {}
    for k, v in pairs(wep) do
        if type(k) == "string" and not Shells.NEVER[k] and not k:find("^_pdti") and not k:find("^_issr") then
            snap[k] = v
        end
    end
    return snap
end

-- Is the weapon one this module manages?
function Shells.Applies(wep)
    if not wep or type(wep._update_stats_values) ~= "function" or type(wep._blueprint) ~= "table" then
        return false
    end
    local info = Ammo.Identify(wep)
    return info ~= nil and info.family == "shell"
end

-- Works out the profile of every shell the weapon takes. Returns the
-- profiles, or nil when the game's function failed (logged once).
function Shells.Capture(wep)
    if not Shells.Applies(wep) or wep._pdti_capturing then return nil end
    local info = Ammo.Identify(wep)
    local real = wep._blueprint
    local ids = Ammo.BulletsFor(info)
    local snaps = {}
    wep._pdti_capturing = true
    local ok, err = pcall(function()
        for _, id in ipairs(ids) do
            wep._blueprint = Shells.Blueprint(real, id)
            wep:_update_stats_values(true)
            snaps[id] = snapshot(wep)
        end
    end)
    -- The real blueprint and the game's own values come back in any case.
    wep._blueprint = real
    pcall(wep._update_stats_values, wep, true)
    wep._pdti_capturing = nil
    if not ok or not snaps.standard then
        if not wep._pdti_shell_error then
            wep._pdti_shell_error = true
            log("shells: could not read the ammunition types of " .. tostring(wep._name_id) .. ": " .. tostring(err))
        end
        return nil
    end

    -- The keys a shell can change: the known fields, and every plain value
    -- that differs from buckshot in some shell.
    local keys = {}
    for _, k in ipairs(Shells.FIELDS) do keys[k] = true end
    local base = snaps.standard
    for _, id in ipairs(ids) do
        for k, v in pairs(snaps[id]) do
            if not keys[k] and SCALAR[type(v)] and v ~= base[k] then keys[k] = true end
        end
        for k, v in pairs(base) do
            if not keys[k] and SCALAR[type(v)] and snaps[id][k] ~= v then keys[k] = true end
        end
    end

    local profiles = {}
    for _, id in ipairs(ids) do
        local p = {}
        for k in pairs(keys) do p[k] = snaps[id][k] end
        profiles[id] = p
    end
    wep._pdti_shells = { keys = keys, profiles = profiles, ids = ids, blueprint = real, n = #real }
    -- What the game has now (its own values): seen, so not a recalculation.
    wep._pdti_shell_stamp = wep._current_stats
    wep._pdti_shell = nil
    return wep._pdti_shells
end

-- The profiles, captured again when the game worked the weapon out anew
-- (a new blueprint, or its own _update_stats_values replaced the values).
function Shells.Profiles(wep)
    local s = wep and wep._pdti_shells
    if s and s.blueprint == wep._blueprint and s.n == #(wep._blueprint or {})
        and wep._current_stats == wep._pdti_shell_stamp then
        return s
    end
    return Shells.Capture(wep)
end

-- Sets the weapon up for this shell (standard: buckshot). Returns true when
-- the weapon has the shell's profile now.
function Shells.Apply(wep, id)
    if not Shells.Applies(wep) or wep._pdti_capturing then return false end
    local s = Shells.Profiles(wep)
    if not s then return false end
    id = Ammo.BulletId(id)
    local p = s.profiles[id] or s.profiles.standard
    if not s.profiles[id] then id = "standard" end
    for k in pairs(s.keys) do
        local v = p[k]
        -- The tables are copied, so the game changing one (a muzzle effect)
        -- never changes the profile.
        if type(v) == "table" and (k == "_current_stats" or k == "_muzzle_effect_table" or k == "_trail_effect_table") then
            local copy = {}
            for a, b in pairs(v) do copy[a] = b end
            v = copy
        end
        wep[k] = v
    end
    wep._pdti_shell = id
    wep._pdti_shell_stamp = wep._current_stats
    return true
end

-- The shell whose profile the weapon has now.
function Shells.Current(wep)
    return wep and wep._pdti_shell or nil
end

return Shells
