-- The loadout: the primary, the secondary, the throwables and the armour.
--
-- They have their own slots: they take no space in the grids and cannot be
-- moved, but they have a weight, and the weight counts.
--
--   * A weapon weighs what its category weighs, lighter the better its
--     concealment: a pistol is always lighter than an assault rifle, and a
--     concealable rifle is lighter than a bulky one.
--   * A throwable weighs per piece; the pieces you still carry count.
--   * The armour replaces the game's own armour slowdown: it slows you by
--     exactly the game's value for that armour (skills that lower the armour
--     penalty still work). Its kilograms are shown, but it is not counted a
--     second time in the load.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Loadout = PDTI.Loadout or {}
PDTI.Loadout = Loadout

-- Weapon weight in kg by category: { at concealment 0, at concealment 30 }.
-- The first category of the list that a weapon has decides.
Loadout.WEAPON_WEIGHTS = {
    { "minigun", 20.0, 12.0 },
    { "flamethrower", 12.0, 6.0 },
    { "saw", 7.0, 5.0 },
    { "lmg", 11.0, 6.0 },
    { "snp", 8.0, 3.5 },
    { "grenade_launcher", 6.0, 2.0 },
    { "crossbow", 4.0, 2.0 },
    { "bow", 2.0, 0.8 },
    { "shotgun", 4.5, 2.5 },
    { "assault_rifle", 4.8, 2.8 },
    { "smg", 3.5, 1.6 },
    { "revolver", 1.8, 0.9 },
    { "pistol", 1.5, 0.6 }
}
Loadout.DEFAULT_WEAPON = { 4.0, 2.0 }
Loadout.CONCEALMENT_MAX = 30

-- Throwables in kg per piece. Perk deck abilities (a flask, an injector)
-- weigh nothing.
Loadout.THROWABLE_WEIGHTS = {
    frag = 0.4, frag_com = 0.4, dada_com = 0.4, concussion = 0.35,
    molotov = 0.8, fir_com = 0.5, dynamite = 0.5, sticky_grenade = 0.45,
    poison_gas_grenade = 0.4, wpn_gre_electric = 0.4,
    wpn_prj_four = 0.1, wpn_prj_ace = 0.05, wpn_prj_target = 0.15,
    wpn_prj_hur = 0.8, wpn_prj_jav = 1.5
}
Loadout.DEFAULT_THROWABLE = 0.4

-- Armour in kg by its level (two-piece suit .. improved combined tactical vest).
Loadout.ARMOUR_WEIGHTS = { 0, 2, 4, 6, 9, 12, 15 }

local function text(id, fallback)
    local ok, value = pcall(function() return managers.localization:text(id) end)
    if ok and type(value) == "string" and value ~= "" then return value end
    return fallback
end

-- The weight of a weapon of these categories with this concealment.
function Loadout.WeaponWeight(categories, concealment)
    local low_conceal, high_conceal = Loadout.DEFAULT_WEAPON[1], Loadout.DEFAULT_WEAPON[2]
    local list = type(categories) == "table" and categories or {}
    local has = {}
    for _, c in ipairs(list) do has[c] = true end
    for _, entry in ipairs(Loadout.WEAPON_WEIGHTS) do
        if has[entry[1]] then
            low_conceal, high_conceal = entry[2], entry[3]
            break
        end
    end
    local c = tonumber(concealment) or 0
    local t = math.max(0, math.min(1, c / Loadout.CONCEALMENT_MAX))
    local weight = low_conceal - (low_conceal - high_conceal) * t
    -- Two guns weigh twice as much.
    if has.akimbo then weight = weight * 2 end
    return math.floor(weight * 100 + 0.5) / 100
end

local function weapon_entry(slot, category)
    local bm = managers and managers.blackmarket
    if not bm then return nil end
    local ok, weapon = pcall(function()
        return category == "primaries" and bm:equipped_primary() or bm:equipped_secondary()
    end)
    if not ok or type(weapon) ~= "table" then return nil end
    local weapon_id = weapon.weapon_id
    local tweak = weapon_id and tweak_data.weapon and tweak_data.weapon[weapon_id]
    if not tweak then return nil end
    local cok, concealment = pcall(function() return bm:calculate_weapon_concealment(category) end)
    if not cok or type(concealment) ~= "number" then concealment = 0 end
    return {
        slot = slot,
        id = weapon_id,
        name = text(tweak.name_id, tostring(weapon_id)),
        categories = tweak.categories,
        concealment = concealment,
        weight = Loadout.WeaponWeight(tweak.categories, concealment),
        counts_in_load = true
    }
end

local function throwable_entry()
    local bm = managers and managers.blackmarket
    if not bm then return nil end
    local ok, id, max_amount = pcall(function() return bm:equipped_grenade() end)
    if not ok or not id then return nil end
    local tweak = tweak_data.blackmarket and tweak_data.blackmarket.projectiles
        and tweak_data.blackmarket.projectiles[id] or {}
    local amount = tonumber(max_amount) or 0
    -- In a heist: the pieces you still carry.
    -- (Not in the menu: there is no session, and the game logs every error,
    -- even one caught.)
    local _, in_heist = pcall(function()
        return managers.player:player_unit() ~= nil and managers.network:session() ~= nil
    end)
    if in_heist == true then pcall(function()
        local peer = managers.network:session():local_peer():id()
        local current = managers.player:get_grenade_amount(peer)
        if type(current) == "number" then amount = current end
    end) end
    local per_piece = tweak.ability and 0 or (Loadout.THROWABLE_WEIGHTS[id] or Loadout.DEFAULT_THROWABLE)
    return {
        slot = "throwable",
        id = id,
        name = text(tweak.name_id, tostring(id)),
        amount = amount,
        per_piece = per_piece,
        weight = math.floor(per_piece * math.max(0, amount) * 100 + 0.5) / 100,
        counts_in_load = true
    }
end

-- The armour's slowdown as the game computes it (0 = none, 0.425 = 42.5%).
-- A light armour that makes you faster keeps its bonus in the game's own
-- calculation, so here it is 0.
function Loadout.ArmourPenalty(upgrade_level)
    local pm = managers and managers.player
    if not pm then return 0 end
    local ok, value = pcall(function()
        return pm:mod_movement_penalty(pm:body_armor_value("movement", upgrade_level, 1))
    end)
    if not ok or type(value) ~= "number" or value >= 1 then return 0 end
    return 1 - value
end

local function armour_entry()
    local bm = managers and managers.blackmarket
    if not bm then return nil end
    local ok, id = pcall(function() return bm:equipped_armor(true, true) end)
    if not ok or not id then return nil end
    local tweak = tweak_data.blackmarket and tweak_data.blackmarket.armors
        and tweak_data.blackmarket.armors[id] or {}
    local level = tonumber(tweak.upgrade_level) or 1
    return {
        slot = "armour",
        id = id,
        name = text(tweak.name_id, tostring(id)),
        level = level,
        weight = Loadout.ARMOUR_WEIGHTS[level] or 0,
        penalty = Loadout.ArmourPenalty(),
        counts_in_load = false
    }
end

-- The four slots. A slot that cannot be read (in a menu without a profile)
-- is left out.
function Loadout.Get()
    local out = {}
    local function add(entry) if entry then out[#out + 1] = entry end end
    add(weapon_entry("primary", "primaries"))
    add(weapon_entry("secondary", "secondaries"))
    add(throwable_entry())
    add(armour_entry())
    return out
end

-- The kilograms of the loadout that count in the load (not the armour).
function Loadout.LoadWeight()
    local total = 0
    for _, entry in ipairs(Loadout.Get()) do
        if entry.counts_in_load then total = total + (entry.weight or 0) end
    end
    return total
end

-- Every kilogram of the loadout, the armour included (for the screen).
function Loadout.TotalWeight()
    local total = 0
    for _, entry in ipairs(Loadout.Get()) do total = total + (entry.weight or 0) end
    return total
end
