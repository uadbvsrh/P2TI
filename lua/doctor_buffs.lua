-- Combat Doctor: the doctor bag buffs (SKILLS_REWORK_SPEC.md §3, R7).
--
-- A doctor bag charge that heals at least one black part (arms, legs, torso;
-- never the head) gives a buff:
--   * the parts healed pick the groups: the torso (stamina, calm, shrug off,
--     focus), the legs (second wind, steady legs), the arms (steady aim, fast
--     hands, interaction);
--   * ace: 60 s for every black part healed, and an arm or leg effect is
--     stronger when both limbs of the pair were healed;
--   * basic: 60 s, half of the one-limb values, the on/off effects halved;
--   * a new buff replaces the one running.
-- Without Combat Doctor a doctor bag only heals.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local Buffs = PDTI.DoctorBuffs or {}
PDTI.DoctorBuffs = Buffs

Buffs.SECONDS = 60
-- [1] one limb (or the torso), [2] both limbs; basic is the basic value.
Buffs.ACE = {
    stamina = 0.5, shake = 0, crit = 0.10, tase_ignore = 1, flash = 0,
    relief = { 0.25, 0.5 }, push = { 0.5, 0 }, aim = { 0.85, 0.70 },
    hands = { 0.15, 0.30 }, interact = { 0.125, 0.25 }
}
Buffs.BASIC = {
    stamina = 0.25, shake = 0.5, crit = 0.05, tase_ignore = 0.5, flash = 0.5,
    relief = 0.125, push = 0.75, aim = 0.925, hands = 0.075, interact = 0.0625
}

-- buff: { ends, ace, torso, legs, arms, count }
Buffs.state = Buffs.state or { buff = nil }
local state = Buffs.state

-- Tests replace these.
Buffs.random = function() return math.random() end

local function now()
    local Body = PDTI.Body
    if Body and Body.clock then return Body.clock() end
    return os.clock()
end

local hint = PDTI.Hint

function Buffs.Owned()
    return Skills.BodyOn() and Skills.Basic("medic_2x")
end

-- The buff in force, or nil.
function Buffs.Current()
    local b = state.buff
    if not b then return nil end
    if now() >= b.ends or not Skills.BodyOn() then
        state.buff = nil
        return nil
    end
    return b
end

function Buffs.Clear()
    state.buff = nil
end

-- A doctor bag healed these black parts.
function Buffs.OnDoctorBag(healed)
    if not Buffs.Owned() or type(healed) ~= "table" then return nil end
    local b = { ace = Skills.Ace("medic_2x"), torso = false, legs = 0, arms = 0, count = 0 }
    for _, id in ipairs(healed) do
        if id == "body" then b.torso = true; b.count = b.count + 1
        elseif id == "leg_l" or id == "leg_r" then b.legs = b.legs + 1; b.count = b.count + 1
        elseif id == "arm_l" or id == "arm_r" then b.arms = b.arms + 1; b.count = b.count + 1 end
    end
    if b.count == 0 then return nil end
    b.seconds = b.ace and Buffs.SECONDS * b.count or Buffs.SECONDS
    b.ends = now() + b.seconds
    state.buff = b
    local groups = {}
    if b.torso then groups[#groups + 1] = "torso" end
    if b.legs > 0 then groups[#groups + 1] = b.legs == 2 and "legs x2" or "legs" end
    if b.arms > 0 then groups[#groups + 1] = b.arms == 2 and "arms x2" or "arms" end
    hint(string.format("Doctor's orders: %s - %d s", table.concat(groups, ", "), b.seconds))
    return b
end

-- The value of an effect now, or nil when it is not in force.
--   group: "torso" | "legs" | "arms"
function Buffs.Value(name, group)
    local b = Buffs.Current()
    if not b then return nil end
    local n
    if group == "torso" then n = b.torso and 1 or 0
    elseif group == "legs" then n = b.legs
    else n = b.arms end
    if n <= 0 then return nil end
    if b.ace then
        local v = Buffs.ACE[name]
        if type(v) == "table" then return v[math.min(2, n)] end
        return v
    end
    return Buffs.BASIC[name]
end

function Buffs.Line()
    local b = Buffs.Current()
    if not b then return nil end
    local groups = {}
    if b.torso then groups[#groups + 1] = "torso" end
    if b.legs > 0 then groups[#groups + 1] = b.legs == 2 and "legs x2" or "legs" end
    if b.arms > 0 then groups[#groups + 1] = b.arms == 2 and "arms x2" or "arms" end
    return string.format("Doctor's orders (%s): %d s", table.concat(groups, ", "),
        math.max(0, math.ceil(b.ends - now())))
end

------------------------------------------------------------- the effects

-- Torso: stamina (max in body.lua, regeneration here), calm.
Skills.Override("player", "stamina_regen_multiplier", function(value)
    local v = Buffs.Value("stamina", "torso")
    if v then return (tonumber(value) or 1) * (1 + v) end
    return nil
end)
Skills.Override("player", "damage_shake_multiplier", function(value)
    local v = Buffs.Value("shake", "torso")
    if v then return (tonumber(value) or 1) * v end
    return nil
end)

-- Shrug off: ace ignores a tase; basic ignores half of them.
function Buffs.IgnoreTase()
    local v = Buffs.Value("tase_ignore", "torso")
    return v ~= nil and Buffs.random() < v
end

function Buffs.FlashMul()
    return Buffs.Value("flash", "torso") or 1
end

local function make_PlayerDamage_damage_tase(orig)
    return function(self, ...)
        if Buffs.IgnoreTase() then return end
        return orig(self, ...)
    end
end

local function make_PlayerDamage_on_flashbanged(orig)
    return function(self, sound_eff_mul, ...)
        local mul = Buffs.FlashMul()
        if mul <= 0 then return end
        if mul < 1 and type(sound_eff_mul) == "number" then sound_eff_mul = sound_eff_mul * mul end
        return orig(self, sound_eff_mul, ...)
    end
end

local function make_CoreEnvironmentControllerManager_set_flashbang(orig)
    return function(self, pos, los, travel, linear, duration, ...)
        local mul = Buffs.FlashMul()
        if mul < 1 and type(duration) == "number" then duration = duration * mul end
        return orig(self, pos, los, travel, linear, duration, ...)
    end
end

local function make_PlayerManager_critical_hit_chance(orig)
    return function(self, ...)
        local value = orig(self, ...)
        local v = Buffs.Value("crit", "torso")
        if v and type(value) == "number" then return value + v end
        return value
    end
end

local function make_PlayerDamage_damage_melee(orig)
    return function(self, attack_data, ...)
        local v = Buffs.Value("push", "legs")
        if v and type(attack_data) == "table" and attack_data.push_vel then
            local ok, scaled = pcall(function() return attack_data.push_vel * v end)
            if ok then attack_data.push_vel = scaled end
        end
        return orig(self, attack_data, ...)
    end
end

local function make_NewRaycastWeaponBase_reload_speed_multiplier(orig)
    return function(self, ...)
        local value = orig(self, ...)
        local v = Buffs.Value("hands", "arms")
        if not v or type(value) ~= "number" then return value end
        local mine = pcall(function()
            assert(self._setup and self._setup.user_unit == managers.player:player_unit())
        end)
        if mine then return value * (1 + v) end
        return value
    end
end

local function make_BaseInteractionExt__get_timer(orig)
    return function(self, ...)
        local value = orig(self, ...)
        local v = Buffs.Value("interact", "arms")
        if v and type(value) == "number" then return value / (1 + v) end
        return value
    end
end

local function mod_on_doctor_bag(healed) Buffs.OnDoctorBag(healed) end
local function mod_stamina()
    local v = Buffs.Value("stamina", "torso")
    return v and (1 + v) or nil
end
local function mod_aim() return Buffs.Value("aim", "arms") end
local function mod_buff_line() return Buffs.Line() end
local function carry_relief() return Buffs.Value("relief", "legs") or 0 end
local function hands_speed()
    local v = Buffs.Value("hands", "arms")
    return v and (1 + v) or 1
end

local function install_hooks()
    local Body = PDTI.Body
    if Body and Body.mods then
        local m = Body.mods
        m.on_doctor_bag = mod_on_doctor_bag
        m.stamina = mod_stamina
        m.recoil = mod_aim
        m.spread = mod_aim
        m.buff_line = mod_buff_line
    end
    if PDTI.Carry then
        PDTI.Carry.relief = carry_relief
    end
    if PDTI.Ammo then
        PDTI.Ammo.round_speed_mods = PDTI.Ammo.round_speed_mods or {}
        PDTI.Ammo.round_speed_mods.doctor = hands_speed
    end
    Skills.wrap("PlayerDamage", "damage_tase", make_PlayerDamage_damage_tase)
    Skills.wrap("PlayerDamage", "on_flashbanged", make_PlayerDamage_on_flashbanged)
    Skills.wrap("CoreEnvironmentControllerManager", "set_flashbang", make_CoreEnvironmentControllerManager_set_flashbang)
    -- Focus.
    Skills.wrap("PlayerManager", "critical_hit_chance", make_PlayerManager_critical_hit_chance)
    -- Steady legs: the push of a melee hit.
    Skills.wrap("PlayerDamage", "damage_melee", make_PlayerDamage_damage_melee)
    -- Fast hands: reloads.
    Skills.wrap("NewRaycastWeaponBase", "reload_speed_multiplier", make_NewRaycastWeaponBase_reload_speed_multiplier)
    -- Interaction speed.
    Skills.wrap("BaseInteractionExt", "_get_timer", make_BaseInteractionExt__get_timer)
end

Skills.OnInstall("doctor_buffs", install_hooks)

function Buffs.OnHeistStart()
    state.buff = nil
end
