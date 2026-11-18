-- The Yakuza perk deck (Irezumi), reworked for health per body part.
--   Vanilla: the armour recovers faster (cards 1, 5, 7: up to 20/40/60%)
--   and you move faster (card 3: up to 20%) the lower your health; card 9
--   doubles the health range where that starts.
--   Here: the bonuses grow with the number of black limbs (arms and legs,
--   0 to 4) instead of missing health; card 9 makes them reach their
--   maximum at 2 black limbs instead of 4.
-- The game reads the scale through PlayerManager:get_damage_health_ratio
-- (categories "armor_regen" and "movement_speed"), so its own formulas stay:
-- armour regen time x (1 - card value x scale), speed x (1 + 0.2 x scale).
-- A limb black under Painkillers' suspension counts. Needs the health per
-- body part; without it (or with restoration-mod) the vanilla deck stays.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local Y = PDTI.Yakuza or {}
PDTI.Yakuza = Y

Y.LIMBS = { "arm_l", "arm_r", "leg_l", "leg_r" }
Y.FULL = 4      -- black limbs for the full bonus
Y.FULL_9 = 2    -- with card 9
Y.CATEGORIES = { armor_regen = true, movement_speed = true }

local function pm() return rawget(_G, "managers") and managers.player end

-- The vanilla upgrade check (the game's own function, not Skills.Off'd).
local function has(upgrade)
    local m = pm()
    if not m or type(m.has_category_upgrade) ~= "function" then return false end
    local ok, v = pcall(m.has_category_upgrade, m, "player", upgrade)
    return ok and v == true
end

-- The deck is equipped (any of its scaling cards).
function Y.Owned()
    return has("armor_regen_damage_health_ratio_multiplier")
        or has("movement_speed_damage_health_ratio_multiplier")
end

function Y.Card9()
    return has("armor_regen_damage_health_ratio_threshold_multiplier")
        or has("movement_speed_damage_health_ratio_threshold_multiplier")
end

function Y.Active()
    return Skills.Enabled() and Skills.BodyOn() and Y.Owned()
end

function Y.BlackLimbs()
    local B = PDTI.Body
    if not B or not B.Active or not B.Active() then return 0 end
    local n = 0
    for _, id in ipairs(Y.LIMBS) do
        if B.IsBlack(id) then n = n + 1 end
    end
    return n
end

-- 0..1: how much of the deck's bonus is in force.
function Y.Scale()
    if not Y.Active() then return 0 end
    local full = Y.Card9() and Y.FULL_9 or Y.FULL
    return math.min(1, Y.BlackLimbs() / full)
end

local function make_PlayerManager_get_damage_health_ratio(orig)
    return function(self, health_ratio, category, ...)
        if category and Y.CATEGORIES[category] and Y.Active() then
            return Y.Scale()
        end
        return orig(self, health_ratio, category, ...)
    end
end

local function install()
    Skills.wrap("PlayerManager", "get_damage_health_ratio", make_PlayerManager_get_damage_health_ratio, "yakuza")
end
Skills.OnInstall("yakuza", install)

------------------------------------------------------------ the texts

local function card(n, text) Skills.texts["menu_deck12_" .. n .. "_desc"] = text end

Skills.texts.menu_st_spec_12_desc = "The more of your arms and legs are black, the faster your armor recovers "
    .. "and the faster you move. A doctor bag that fills a black limb takes its share of the bonus away."
card(1, "Your armor recovers up to ##20%## faster: ##5%## for each black arm or leg.")
card(3, "You move up to ##20%## faster: ##5%## for each black arm or leg.")
card(5, "Your armor recovers up to ##40%## faster: ##10%## for each black arm or leg.")
card(7, "Your armor recovers up to ##60%## faster: ##15%## for each black arm or leg.")
card(9, "The bonuses of this perk deck reach their maximum with ##2## black limbs instead of ##4##.\n\n"
    .. "Increases the chance of getting a higher quality item from a Payday by ##10%##.")

return Y
