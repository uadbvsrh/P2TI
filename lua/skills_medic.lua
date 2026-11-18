-- Mastermind, Medic branch (SKILLS_REWORK_SPEC.md §3).
--   Combat Medic  ace: the head heals to full when you revive someone or get
--                 revived (was: +30% health for the one you revive)
--   Quick Fix     basic: first aid kits deploy twice as fast only while your
--                 armour is broken; ace: overheal, up to +25% of a part
--   Painkillers   basic: a black part passes on 50% (not 75%); ace: a part
--                 that goes black keeps working for 40 s
--   Uppers        basic: first aid kits stack 3 to a slot; ace: the auto-revive
--                 heals the head to full
--   Combat Doctor the doctor bag buffs (doctor_buffs.lua)
--   Inspire       vanilla
-- With health per body part off, the vanilla skills stay.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local Medic = PDTI.Medic or {}
PDTI.Medic = Medic

Medic.OVERHEAL = 0.25
Medic.SPILL = 0.5
Medic.SUSPEND = 40
Medic.FAK_STACK = 3

local function body() return Skills.BodyOn() end

------------------------------------------------------------ Combat Medic

Skills.Off("player", "revive_health_boost", function() return body() and Skills.Ace("combat_medic") end)

------------------------------------------------------------ Quick Fix

-- Light armour at 0, or heavy armour broken (until a plate goes in).
function Medic.ArmourBroken()
    local Armour = PDTI.Armour
    if Armour and Armour.IsHeavy and Armour.IsHeavy() and Skills.ArmourOn() then
        return Armour.IsBroken() == true
    end
    local ok, armor = pcall(function()
        return managers.player:player_unit():character_damage():get_real_armor()
    end)
    return ok and type(armor) == "number" and armor <= 0
end

Skills.Override("first_aid_kit", "deploy_time_multiplier", function(value, default)
    local v = nil
    if Skills.Basic("tea_time") and not Medic.ArmourBroken() then v = default or 1 end
    -- Sangres' room (tier 3): half the time, with or without the skill.
    local perks = PDTI.Perks
    local f = perks and perks.FakTimeFactor and perks.FakTimeFactor() or 1
    if f ~= 1 then return (tonumber(v or value) or 1) * f end
    return v
end)
Skills.Off("first_aid_kit", "damage_reduction_upgrade", function() return body() and Skills.Ace("tea_time") end)

------------------------------------------------------------ Painkillers

Skills.Off("player", "revive_damage_reduction_level", function() return body() and Skills.Basic("fast_learner") end)

------------------------------------------------------------ Uppers

function Medic.FakStack()
    if Skills.Basic("tea_cookies") and Skills.DeployablesOn() then return Medic.FAK_STACK end
    return 1
end

------------------------------------------------------------ the body hooks

local function mod_revive_head_full() return Skills.Ace("combat_medic") end
local function mod_auto_revive_full() return Skills.Ace("tea_cookies") or Skills.Ace("combat_medic") end
local function mod_overheal_cap() return Skills.Ace("tea_time") and Medic.OVERHEAL or nil end
local function mod_spill_rate() return Skills.Basic("fast_learner") and Medic.SPILL or nil end
local function mod_suspend_time() return Skills.Ace("fast_learner") and Medic.SUSPEND or nil end

local function install_body_mods()
    local Body = PDTI.Body
    if not Body or not Body.mods then return end
    local m = Body.mods
    m.revive_head_full = mod_revive_head_full
    m.auto_revive_full = mod_auto_revive_full
    m.overheal_cap = mod_overheal_cap
    m.spill_rate = mod_spill_rate
    m.suspend_time = mod_suspend_time
end

-- Combat Medic ace: reviving someone heals your own head.
local function make_ReviveInteractionExt_interact(orig)
    return function(self, reviving_unit, ...)
        local result = orig(self, reviving_unit, ...)
        pcall(function()
            if self.tweak_data ~= "revive" then return end
            if not reviving_unit or reviving_unit ~= managers.player:player_unit() then return end
            if body() and Skills.Ace("combat_medic") then PDTI.Body.HealHead(1) end
        end)
        return result
    end
end

local function install_revive_hook()
    return Skills.wrap("ReviveInteractionExt", "interact", make_ReviveInteractionExt_interact)
end

local function apply_items()
    local def = PDTI.items and PDTI.items.first_aid_kit
    if def then def.max_stack = Medic.FakStack() end
end

Skills.OnInstall("medic", function()
    install_body_mods()
    apply_items()
    install_revive_hook()
end)

------------------------------------------------------------ the texts

Skills.Text("combat_medic", "BASIC: ##$basic##\n"
    .. "You gain a ##30%## damage reduction for ##5## seconds both during and after reviving another player.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Reviving a crew member, or being revived, heals your ##head to full##.")
Skills.Text("tea_time", "BASIC: ##$basic##\n"
    .. "While your armor is broken, you deploy First Aid Kits ##50%## faster. Light armor counts as broken until "
    .. "it regenerates, heavy armor until you insert a plate.\n\n"
    .. "ACE: ##$pro##\n"
    .. "First Aid Kit healing beyond a body part's maximum is kept as ##overheal##, up to ##25%## of that part's "
    .. "maximum. Overheal does not fade and is lost first when that part takes damage.")
Skills.Text("fast_learner", "BASIC: ##$basic##\n"
    .. "Adrenaline: damage to a black body part passes on at ##50%## instead of 75%.\n\n"
    .. "ACE: ##$pro##\n"
    .. "When an arm, a leg or your torso goes black, its penalties are suspended for ##40## seconds. "
    .. "The part stays black.")
Skills.Text("tea_cookies", "BASIC: ##$basic##\n"
    .. "First Aid Kits stack up to ##3## per inventory slot.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Your First Aid Kits automatically revive you or a crew member going down within ##5## meters. "
    .. "This can happen at most once every ##20## seconds per player. The revive heals your ##head to full##.")
Skills.Text("medic_2x", "BASIC: ##$basic##\n"
    .. "A Doctor Bag that heals at least one black body part gives you a buff for ##60## seconds, by the parts "
    .. "it healed: torso - stamina, calm, shrug off tasers and flashbangs, focus; legs - lighter load, steady "
    .. "legs; arms - steady aim, fast hands, faster interactions. Half strength.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Full strength. The buff lasts ##60## seconds for every black part healed, and arm and leg effects "
    .. "double when both limbs were healed. Your Doctor Bags have ##2## more charges.")
