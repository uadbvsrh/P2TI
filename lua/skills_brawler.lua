-- Fugitive, Brawler: Berserker and Frenzy (SKILLS_REWORK_SPEC.md §8).
--   Berserker  basic: melee damage +10% per black body part (arms, legs,
--              body; at most 5); ace: bullets too. Replaces the low-health
--              damage scaling.
--   Frenzy     basic: both arms and both legs start the heist black and hold
--              at most 1 HP (the rest of their health is gone); ace: the body
--              too, and everything the capped parts lost goes to the head.
--              Replaces the health cap and the ace's damage reduction.
-- Both need the health per body part; without it the vanilla skills stay.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local BR = PDTI.Brawler or {}
PDTI.Brawler = BR

BR.PER_PART = 0.10
BR.MAX_PARTS = 5
-- A Frenzy part's max (game units: 1 HP on the screen).
BR.CAP = 0.1
BR.LIMBS = { "arm_l", "arm_r", "leg_l", "leg_r" }
BR.BLACK_PARTS = { "arm_l", "arm_r", "leg_l", "leg_r", "body" }

local function body_on() return Skills.BodyOn() end
local function Body() return PDTI.Body end

local player_unit = PDTI.PlayerUnit

------------------------------------------------------------ Berserker

local function berserker() return body_on() and Skills.Basic("wolverine") end

Skills.Off("player", "melee_damage_health_ratio_multiplier", berserker)
Skills.Off("player", "damage_health_ratio_multiplier", berserker)

function BR.Black()
    local B = Body()
    if not B or not B.Active or not B.Active() then return 0 end
    local n = 0
    for _, id in ipairs(BR.BLACK_PARTS) do
        if B.IsBlack(id) then n = n + 1 end
    end
    return math.min(BR.MAX_PARTS, n)
end

-- The damage multiplier for a hit of this kind ("melee" or "bullet").
function BR.Multiplier(kind)
    if not berserker() then return 1 end
    if kind ~= "melee" and not Skills.Ace("wolverine") then return 1 end
    return 1 + BR.PER_PART * BR.Black()
end

local function make_hit(kind)
    return function(orig)
        return function(self, attack_data, ...)
            if type(attack_data) == "table" and type(attack_data.damage) == "number"
                and attack_data.attacker_unit ~= nil and attack_data.attacker_unit == player_unit() then
                local mul = BR.Multiplier(kind)
                if mul ~= 1 then attack_data.damage = attack_data.damage * mul end
            end
            return orig(self, attack_data, ...)
        end
    end
end

-- Installed every frame: the makers are built once.
local make_melee_hit, make_bullet_hit = make_hit("melee"), make_hit("bullet")

local function install_berserker()
    Skills.wrap("CopDamage", "damage_melee", make_melee_hit, "berserker")
    Skills.wrap("CopDamage", "damage_bullet", make_bullet_hit, "berserker")
    Skills.wrap("SentryGunDamage", "damage_bullet", make_bullet_hit, "berserker")
end

------------------------------------------------------------ Frenzy

local function frenzy() return body_on() and Skills.Basic("frenzy") end

Skills.Off("player", "max_health_reduction", frenzy)
-- The ace's damage reduction: the basic's again.
Skills.Override("player", "health_damage_reduction", function(value)
    if not (frenzy() and Skills.Ace("frenzy")) then return nil end
    local ok, basic = pcall(function() return tweak_data.upgrades.values.player.health_damage_reduction[1] end)
    if ok and type(basic) == "number" then return basic end
    return 0.9
end)

-- Is this part capped at 1 HP?
function BR.Capped(id)
    if not frenzy() then return false end
    if id == "body" then return Skills.Ace("frenzy") end
    for _, limb in ipairs(BR.LIMBS) do
        if limb == id then return true end
    end
    return false
end

-- Body.mods.part_max: the capped parts hold BR.CAP; with the ace the head
-- takes what they lost.
function BR.PartMax(id, max)
    if not frenzy() then return nil end
    if BR.Capped(id) then return BR.CAP end
    if id == "head" and Skills.Ace("frenzy") then
        local B = Body()
        local head = B.ShareMax("head", max)
        for _, p in ipairs(B.PARTS) do
            if BR.Capped(p.id) then head = head + math.max(0, B.ShareMax(p.id, max) - BR.CAP) end
        end
        return head
    end
    return nil
end

local function mod_part_max(id, max) return BR.PartMax(id, max) end
local function mod_start_black(id) return BR.Capped(id) end

local function install_frenzy()
    local B = Body()
    if not B or not B.mods then return end
    B.mods.part_max = mod_part_max
    B.mods.start_black = mod_start_black
end
install_frenzy()

Skills.OnInstall("brawler", function()
    install_berserker()
    install_frenzy()
end)

------------------------------------------------------------ the texts

Skills.Text("wolverine", "BASIC: ##$basic##\n"
    .. "Your melee damage is increased by ##10%## for each black body part (arms, legs, body), up to ##50%##.\n\n"
    .. "ACE: ##$pro##\n"
    .. "The bonus also applies to your bullets.")
Skills.Text("frenzy", "BASIC: ##$basic##\n"
    .. "Both arms and both legs start the heist black and hold at most ##1## health; the rest of their health "
    .. "is gone. A doctor bag fills them. You take ##10%## less health damage. Healing is ##75%## less effective.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Your body also starts black with at most ##1## health, and the health your arms, legs and body lost "
    .. "goes to your head. Healing is no longer reduced.", nil, "menu_frenzy")

return BR
