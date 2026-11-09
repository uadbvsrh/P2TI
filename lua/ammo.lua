-- Ammunition: the inventory IS the magazine supply.
--
-- This module merges the InsurgencySandstormStyleReload mod into the Tactical
-- Inventory. ISSR kept its own magazine queue (ISSR.mags) next to the
-- inventory and had to reconcile the two; every mismatch showed up in game as
-- ammunition that appeared, vanished or duplicated. Here there is only one
-- list, so nothing can get out of step:
--
--   * A "spare_magazine" item in the rig or the pockets can be loaded into the
--     gun. One in the backpack is stored, not ready.
--   * A "loose_ammo" item is loose rounds; its stack size is the number of
--     rounds. Packing a magazine takes the rounds out of that stack, so the
--     loose ammunition you carry really is the ammunition that gets used.
--   * Picking up ammunition adds loose rounds to the inventory.
--   * An ammo bag adds its ammunition to the inventory and packs it at once.
--
-- The old ISSR API is still exposed (ISSR.api) so that HUD mods and other
-- mods that talk to ISSR keep working.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Ammo = PDTI.Ammo or {}
PDTI.Ammo = Ammo

Ammo.MAGAZINE_ITEM = "spare_magazine"
Ammo.LOOSE_ITEM = "loose_ammo"

-- Containers whose contents are "to hand". A magazine here can be loaded, a
-- magazine in the backpack is carried but not ready.
Ammo.ACTIVE = { "rig", "rig_2", "rig_3", "pockets" }

-- Every container, for things that are stored but still usable (loose rounds).
Ammo.STORAGE = { "rig", "rig_2", "rig_3", "pockets", "backpack" }

-- Rounds in one loose stack (the item's max_stack, 100).
local MAX_STACK = 100
if PDTI.items and PDTI.items.loose_ammo and tonumber(PDTI.items.loose_ammo.max_stack) then
    MAX_STACK = math.floor(PDTI.items.loose_ammo.max_stack)
end
Ammo.MAX_STACK = MAX_STACK

-- The panel of the HUD is drawn by ammo_hud.lua. The flags live here so the
-- hooks work even when the HUD is not loaded.
Ammo.panel_dirty = false
Ammo.panel_visible = false

local function log(message)
    local line = "[PDTI AMMO] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

Ammo.log = log

------------------------------------------------------------------ settings

-- The settings of the merged ISSR mod. The old save files are read so the
-- values the player already chose survive the merge.
Ammo.settings = {
    max_extra_mags = 0,
    ammo_max = 125,
    drop_mode = 1,
    hold_time = 0.2,
    overlay_always = false,
    show_mags = false,
    show_loose = true,
    show_ammo_type = false,
    max_boxes = 4,
    show_more = true,
    font_size = 20,
    pad_right = 220,
    pad_bottom = 100,
    round_interval = 0.25,
    sound = true,
    unblock_bag = true,
    -- Akimbo: the left mouse button fires the left gun, the right one the
    -- right gun (instead of aiming).
    akimbo_buttons = true,
    -- Health per body part (body.lua).
    body_parts = true,
    enabled = true
}

local SETTING_FILES = {
    { file = "issr_settings.txt", keys = {
        "max_extra_mags", "ammo_max", "drop_mode", "hold_time", "overlay_always",
        "show_mags", "show_loose", "show_ammo_type", "max_boxes", "show_more",
        "font_size", "pad_right", "pad_bottom", "enabled" } },
    { file = "issr_reload_settings.txt", keys = {
        "round_interval", "sound", "unblock_bag", "akimbo_buttons", "body_parts" } }
}

local function load_settings()
    if not rawget(_G, "json") then return end
    for _, entry in ipairs(SETTING_FILES) do
        local file = io.open((rawget(_G, "SavePath") or "") .. entry.file, "r")
        if file then
            local raw = file:read("*all")
            file:close()
            local ok, data = pcall(json.decode, raw or "")
            if ok and type(data) == "table" then
                for _, key in ipairs(entry.keys) do
                    local value = data[key]
                    if type(value) == "boolean" then
                        Ammo.settings[key] = value == true or value == "on"
                    elseif type(value) == "number" then
                        Ammo.settings[key] = value
                    end
                end
            end
        end
    end
end

load_settings()

------------------------------------------------------------------- helpers

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function is_active(container)
    for _, name in ipairs(Ammo.ACTIVE) do
        if name == container then return true end
    end
    return false
end

function Ammo.PlayerUnit()
    return managers and managers.player and managers.player:player_unit()
end

function Ammo.EquippedUnit()
    local unit = Ammo.PlayerUnit()
    if not unit then return nil end
    local ok, equipped = pcall(function()
        return unit:inventory():equipped_unit()
    end)
    if not ok then return nil end
    return equipped
end

function Ammo.EquippedBase()
    local unit = Ammo.EquippedUnit()
    return unit and unit:base()
end

function Ammo.IsOurs(wep)
    local unit = Ammo.PlayerUnit()
    local setup = wep and wep._setup
    if not alive(unit) or not setup or not alive(setup.user_unit) then return false end
    return setup.user_unit:key() == unit:key()
end

local function weapon_tweak(wep)
    local ok, tweak = pcall(wep.weapon_tweak_data, wep)
    if ok and type(tweak) == "table" then return tweak end
    return wep._name_id and tweak_data.weapon[wep._name_id] or nil
end

-- Rounds in a full magazine, as the weapon itself reports it.
local function clip_size(wep)
    local ok, value = pcall(wep.get_ammo_max_per_clip, wep)
    if ok and type(value) == "number" and value >= 1 then
        return math.floor(value)
    end
    return nil
end

-- Shown in the HUD: the caliber if NQR provides one, else the weapon category.
local function weapon_label(wep)
    if wep._caliber then return wep._caliber end
    local tweak = weapon_tweak(wep)
    local category = tweak and tweak.categories and tweak.categories[1]
    if category then
        return string.upper((tostring(category):gsub("_", " ")))
    end
    return tostring(wep._name_id or "?")
end

local function find_mag_part(blueprint)
    local magazine = nil
    local clip = nil
    for i = 1, #blueprint do
        local part = tweak_data.weapon.factory.parts[blueprint[i]]
        if part then
            local has_clip = part.stats and part.stats.CLIP_AMMO_MAX
            if has_clip then
                if part.type == "magazine" then return blueprint[i] end
                clip = clip or blueprint[i]
            elseif part.type == "magazine" and not magazine then
                magazine = blueprint[i]
            end
        end
    end
    if rawget(_G, "NQR") ~= nil then return clip or magazine end
    return clip
end

-- Identifies the magazine type of a weapon. With NQR it is the magazine part.
-- Without NQR it is "<weapon id>:<magazine size>", so an extended magazine gets
-- its own supply, just like a different magazine part would.
local function mag_part_id(wep)
    local blueprint = wep._blueprint
    if not blueprint then return nil end
    if wep._issr_pid_bp ~= blueprint or wep._issr_pid_n ~= #blueprint then
        local pid = find_mag_part(blueprint)
        if not pid then
            local size = clip_size(wep)
            if size and wep._name_id then
                pid = tostring(wep._name_id) .. ":" .. tostring(size)
            end
        end
        if not pid then return nil end
        wep._issr_pid = pid
        wep._issr_pid_bp = blueprint
        wep._issr_pid_n = #blueprint
    end
    return wep._issr_pid
end

local function mag_capacity(pid, caliber)
    local part = tweak_data.weapon.factory.parts[pid]
    local value = part and part.stats and part.stats.CLIP_AMMO_MAX
    if type(value) == "number" then return value end
    if type(value) == "table" then
        local by_caliber = value[caliber]
        if type(by_caliber) == "number" then return by_caliber end
        for _, v in pairs(value) do
            if type(v) == "number" then return v end
        end
    end
    if type(pid) == "string" then
        local size = tonumber(pid:match(":(%d+)$"))
        if size then return size end
    end
    return 30
end

function Ammo.ChamberOf(wep)
    if not wep or not wep.get_chamber then return 0 end
    local ok, value = pcall(wep.get_chamber, wep)
    if ok and type(value) == "number" then return value end
    return 0
end

-- Exposed for the hooks: how many rounds fit in a magazine of this type and
-- how many magazines a weapon of this type starts with.
Ammo.MagCapacity = mag_capacity

-- How many magazines a weapon starts with.
local function mag_amount_for(pid, caliber, name_id)
    local part = pid and tweak_data.weapon.factory.parts[pid]
    local value = part and part.stats and part.stats.mag_amount
    local amount = nil
    if type(value) == "table" then
        amount = value[2]
    elseif type(value) == "number" then
        amount = value
    end
    if type(amount) == "number" and amount >= 1 then
        return math.floor(amount)
    end
    local capacity = pid and caliber and mag_capacity(pid, caliber) or 0
    local tweak = name_id and tweak_data.weapon[name_id]
    if capacity > 0 and tweak and type(tweak.AMMO_MAX) == "number" then
        local mags = math.floor(tweak.AMMO_MAX / capacity)
        if type(pid) == "string" and not tweak_data.weapon.factory.parts[pid] then
            mags = mags - 1
        end
        return math.max(1, mags)
    end
    return 3
end

Ammo.MagAmountFor = mag_amount_for

-- Starting magazines of a weapon. Akimbo magazines hold half as much, so
-- there are twice as many of them.
function Ammo.MagAmount(info, name_id)
    if not info then return 0 end
    local amount
    if info.typed then
        -- The weapon's ammunition in base magazines, one of them in the gun.
        local tweak = name_id and tweak_data.weapon[name_id]
        local max = tweak and tonumber(tweak.AMMO_MAX)
        local per = info.capacity * (info.akimbo and 2 or 1)
        amount = max and math.max(1, math.floor(max / per) - 1) or 3
    else
        amount = mag_amount_for(info.pid, info.caliber, name_id)
    end
    if info.akimbo and not info.loose_fed then amount = amount * 2 end
    return amount
end

function Ammo.ExtraMags()
    return math.max(0, math.floor(Ammo.settings.max_extra_mags or 0))
end

-- Weapons that are loaded round by round take their ammunition straight from
-- the loose rounds you carry and have no magazines: shotguns that load shell
-- by shell, double-barrelled shotguns, bows, crossbows, grenade launchers and
-- the rifles that are loaded one cartridge at a time.
local LOOSE_CATEGORIES = { bow = true, crossbow = true, grenade_launcher = true }
Ammo.LOOSE_CATEGORIES = LOOSE_CATEGORIES

local function has_category(wep, wanted)
    local tweak = weapon_tweak(wep)
    for _, category in ipairs(tweak and tweak.categories or {}) do
        if wanted[category] then return true end
    end
    return false
end

-- "loose" (loaded from the loose rounds) or "magazine".
function Ammo.FeedMode(wep)
    if not wep then return "magazine" end
    if wep._use_shotgun_reload or wep._no_reload then return "loose" end
    if has_category(wep, LOOSE_CATEGORIES) then return "loose" end
    local size = clip_size(wep)
    -- A single-shot weapon has no magazine.
    if size and size <= 1 then return "loose" end
    if has_category(wep, { shotgun = true }) and size and size <= 2 then return "loose" end
    return "magazine"
end

function Ammo.IsLooseFed(wep)
    return Ammo.FeedMode(wep) == "loose"
end

-- A bow has no reload: the game keeps the arrow on the string equal to the
-- arrows you carry.
function Ammo.NoReload(wep)
    return wep ~= nil and wep._no_reload and true or false
end

-- "primary" or "secondary": the loose rounds and the magazines of the two
-- guns look different in the inventory.
function Ammo.SlotOf(wep)
    local ok, index = pcall(function() return wep:selection_index() end)
    if ok and index == 2 then return "primary" end
    if ok and index == 1 then return "secondary" end
    return nil
end

-- The size class of a weapon's magazines (PDTI.MagazineSize): the first of
-- these categories the weapon has. Akimbo guns carry a magazine for each gun.
Ammo.SIZE_CLASSES = { "grenade_launcher", "crossbow", "bow", "shotgun", "snp", "lmg", "minigun", "flamethrower", "smg", "revolver", "pistol", "assault_rifle" }

function Ammo.SizeClass(wep)
    local tweak = weapon_tweak(wep)
    local has = {}
    for _, category in ipairs(tweak and tweak.categories or {}) do has[category] = true end
    for _, class in ipairs(Ammo.SIZE_CLASSES) do
        if has[class] then return class, has.akimbo == true end
    end
    return nil, has.akimbo == true
end

-------------------------------------------------- sizes and bullets

-- Assault rifles and SMGs take magazines of four sizes and three kinds of
-- bullets. Every magazine has its own; what is loaded counts.
Ammo.MAG_SIZES = {
    compact = { name = "Compact", short = "C", mul = 0.65, reload = 0.85 },
    standard = { name = "Standard", short = "S", mul = 1.0, reload = 1.0 },
    extended = { name = "Extended", short = "E", mul = 1.5, reload = 1.15 },
    drum = { name = "Drum", short = "D", mul = 2.5, reload = 1.5 }
}
Ammo.SIZE_ORDER = { "compact", "standard", "extended", "drum" }

-- damage: multiplier; pierce: chance against armour plates (nil: the
-- weapon's own); through: shoots through enemies and shields (nil: the
-- weapon's own); no_ap_skill: the AP-bullets skill does not apply;
-- limb_crit: every hit on an arm or a leg is a critical hit.
Ammo.BULLETS = {
    standard = { name = "Standard", short = "STD", damage = 1.0 },
    hollow = { name = "Hollow point", short = "HP", damage = 1.3, pierce = 0, through = false,
        no_ap_skill = true, limb_crit = true },
    -- Armour piercing is less stable: every shot kicks harder (recoil), and
    -- the kick builds up while you keep firing (recoil_build per shot in a
    -- row, up to recoil_build_max shots), so full auto climbs away and single
    -- aimed shots are the way to use it.
    ap = { name = "Armour piercing", short = "AP", damage = 0.85, pierce = 1, through = true,
        recoil = 1.5, recoil_build = 0.1, recoil_build_max = 6 }
}
Ammo.BULLET_ORDER = { "standard", "hollow", "ap" }

-- What things cost. Adding something to the menu plan pays for it from your
-- spending cash, and taking it out pays it back. What a heist uses up (rounds
-- fired, deployables placed, throwables thrown) is paid again to restock the
-- plan (Plan.Spend). A magazine costs its case by size plus its rounds; loose
-- rounds cost their rounds. Weapons without sizes and bullets count as
-- standard. Items: PRICES.item, or a definition's own `price` (other mods).
Ammo.PRICES = {
    round = { standard = 30, hollow = 90, ap = 180 },
    magazine = { compact = 600, standard = 1000, extended = 2000, drum = 5000 },
    item = {
        first_aid_kit = 4000, doctor_bag = 12000, ammo_bag = 10000, bodybags_bag = 3000,
        bandage = 500, painkillers = 800, grenade = 2500, ecm_battery = 5000, armor_kit = 6000
    },
    -- One throwable (grenade, molotov, knife ...) thrown. Abilities (the
    -- perk deck throwables with a cooldown) are free.
    throwable = 2500
}

-- The price of one item that is not ammunition.
function Ammo.UnitPrice(item_id)
    local def = PDTI.items and PDTI.items[item_id]
    if def and tonumber(def.price) then return math.max(0, tonumber(def.price)) end
    return Ammo.PRICES.item[item_id] or 0
end

-- The price of one throwable of the game's (by projectile id).
function Ammo.ThrowablePrice(id)
    local tweak = tweak_data and tweak_data.blackmarket and tweak_data.blackmarket.projectiles
        and tweak_data.blackmarket.projectiles[id]
    if type(tweak) == "table" and (tweak.ability or tweak.base_cooldown) then return 0 end
    return Ammo.PRICES.throwable
end

function Ammo.RoundPrice(bullet)
    return Ammo.PRICES.round[Ammo.BulletId(bullet)] or Ammo.PRICES.round.standard
end

-- The price of a magazine item's data (the case and every round in it).
function Ammo.MagazinePrice(data)
    data = type(data) == "table" and data or {}
    local price = Ammo.PRICES.magazine[Ammo.SizeId(data.size)] or Ammo.PRICES.magazine.standard
    if data.size or data.load or data.bullet then
        for _, part in ipairs(Ammo.LoadOf(data)) do price = price + part[2] * Ammo.RoundPrice(part[1]) end
    else
        price = price + (tonumber(data.rounds) or 0) * Ammo.RoundPrice("standard")
    end
    return price
end

-- The price of an inventory item: a magazine, loose rounds, or the item's
-- price times its amount.
function Ammo.ItemPrice(item)
    if type(item) ~= "table" then return 0 end
    if item.item_id == Ammo.MAGAZINE_ITEM then return Ammo.MagazinePrice(item.data) end
    if item.item_id == Ammo.LOOSE_ITEM then
        local data = type(item.data) == "table" and item.data or {}
        return (tonumber(item.amount) or 0) * Ammo.RoundPrice(data.bullet)
    end
    return (tonumber(item.amount) or 1) * Ammo.UnitPrice(item.item_id)
end

-- "$12,500"
function Ammo.Money(amount)
    local s = tostring(math.floor((tonumber(amount) or 0) + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return "$" .. out:gsub("^,", "")
end

-- The weapon types with sizes and bullets.
Ammo.TYPED_CLASSES = { assault_rifle = true, smg = true }

function Ammo.SizeId(id)
    if Ammo.MAG_SIZES[id] then return id end
    return "standard"
end

function Ammo.BulletId(id)
    if Ammo.BULLETS[id] then return id end
    return "standard"
end

-------------------------------------------------- mixed loads

-- A magazine can hold several kinds of bullets: its load is a list of
-- { bullet, n } from the top (fired first) to the bottom. In the save it is
-- a string, "ap:10,hollow:20" (the save keeps only plain values).
function Ammo.ParseLoad(value)
    local out = {}
    if type(value) == "table" then
        for _, part in ipairs(value) do
            local b, n = part[1] or part.bullet, math.floor(tonumber(part[2] or part.n) or 0)
            if Ammo.BULLETS[b] and n > 0 then out[#out + 1] = { b, n } end
        end
    elseif type(value) == "string" then
        for b, n in value:gmatch("(%a+):(%d+)") do
            n = math.floor(tonumber(n) or 0)
            if Ammo.BULLETS[b] and n > 0 then out[#out + 1] = { b, n } end
        end
    end
    -- Neighbours of the same kind are one run.
    local merged = {}
    for _, part in ipairs(out) do
        local last = merged[#merged]
        if last and last[1] == part[1] then last[2] = last[2] + part[2]
        else merged[#merged + 1] = { part[1], part[2] } end
    end
    return merged
end

function Ammo.LoadString(load)
    local parts = {}
    for _, part in ipairs(Ammo.ParseLoad(load)) do parts[#parts + 1] = part[1] .. ":" .. part[2] end
    return table.concat(parts, ",")
end

function Ammo.LoadTotal(load)
    local total = 0
    for _, part in ipairs(load or {}) do total = total + part[2] end
    return total
end

function Ammo.LoadTop(load)
    return load and load[1] and load[1][1] or nil
end

-- Pushes n rounds of a bullet on top (they are fired first).
function Ammo.LoadPush(load, bullet, n)
    if n <= 0 then return load end
    if load[1] and load[1][1] == bullet then load[1][2] = load[1][2] + n
    else table.insert(load, 1, { bullet, n }) end
    return load
end

-- Takes n rounds off the top. Returns the bullet of the last one taken.
function Ammo.LoadPop(load, n)
    local last = nil
    while n > 0 and load[1] do
        local take = math.min(n, load[1][2])
        last = load[1][1]
        load[1][2] = load[1][2] - take
        n = n - take
        if load[1][2] <= 0 then table.remove(load, 1) end
    end
    return last
end

-- The load fitted to a number of rounds: rounds that were fired leave the
-- top; rounds nobody knows about are added at the bottom as "fill".
function Ammo.FitLoad(load, rounds, fill)
    local total = Ammo.LoadTotal(load)
    local popped = nil
    if total > rounds then popped = Ammo.LoadPop(load, total - rounds)
    elseif total < rounds then
        fill = Ammo.BulletId(fill)
        local last = load[#load]
        if last and last[1] == fill then last[2] = last[2] + (rounds - total)
        else load[#load + 1] = { fill, rounds - total } end
    end
    return load, popped
end

-- The load of a magazine item's data.
function Ammo.LoadOf(data)
    if type(data) ~= "table" then return {} end
    local rounds = math.max(0, math.floor(tonumber(data.rounds) or 0))
    local load = Ammo.ParseLoad(data.load)
    return (Ammo.FitLoad(load, rounds, data.bullet))
end

-- "30 AP", or "30 AP+" when there is more than one kind.
function Ammo.LoadTag(load, fallback)
    local top = Ammo.LoadTop(load) or fallback
    if not top then return "" end
    return Ammo.BULLETS[Ammo.BulletId(top)].short .. ((#(load or {}) > 1) and "+" or "")
end

-- Rounds in a magazine of this size, from the weapon's base magazine.
function Ammo.SpecCapacity(base, size)
    local def = Ammo.MAG_SIZES[Ammo.SizeId(size)]
    return math.max(1, math.floor((tonumber(base) or 30) * def.mul + 0.5))
end

function Ammo.SpecTag(size, bullet)
    return Ammo.MAG_SIZES[Ammo.SizeId(size)].short .. "/" .. Ammo.BULLETS[Ammo.BulletId(bullet)].short
end

function Ammo.IsTypedClass(class)
    return class ~= nil and Ammo.TYPED_CLASSES[class] == true
end

-- An assault rifle or SMG fed from magazines.
function Ammo.Typed(wep)
    if not wep or Ammo.IsLooseFed(wep) then return false end
    return Ammo.IsTypedClass((Ammo.SizeClass(wep)))
end

-- Everything the ammunition code needs to know about a weapon.
function Ammo.Identify(wep)
    if not wep then return nil end
    local caliber = weapon_label(wep)
    if not caliber then return nil end
    if Ammo.IsLooseFed(wep) then
        local name = wep._name_id
        if not name then return nil end
        return {
            key = tostring(caliber) .. "|" .. tostring(name) .. ":loose",
            pid = tostring(name),
            caliber = caliber,
            capacity = clip_size(wep) or 1,
            loose_fed = true,
            slot = Ammo.SlotOf(wep),
            mag_class = (Ammo.SizeClass(wep))
        }
    end
    local class, akimbo = Ammo.SizeClass(wep)
    if Ammo.IsTypedClass(class) and wep._name_id then
        -- The game's magazine mods do not count: the base magazine is the
        -- weapon's own, and the magazine you load sets the size.
        local tweak = weapon_tweak(wep)
        local base = tweak and tonumber(tweak.CLIP_AMMO_MAX)
        if not base then
            wep._pdti_base_clip = wep._pdti_base_clip or clip_size(wep) or 30
            base = wep._pdti_base_clip
        end
        if akimbo then base = base / 2 end
        local pid = tostring(wep._name_id) .. ":typed"
        return {
            key = tostring(caliber) .. "|" .. pid,
            pid = pid,
            caliber = caliber,
            capacity = math.max(1, math.floor(base)),
            slot = Ammo.SlotOf(wep),
            mag_class = class,
            akimbo = akimbo or nil,
            typed = true
        }
    end
    local pid = mag_part_id(wep)
    if not pid then return nil end
    local capacity = mag_capacity(pid, caliber)
    if akimbo then
        -- Two guns, two magazines: each magazine holds half of what the
        -- weapon reports.
        local full = clip_size(wep) or capacity
        capacity = math.max(1, math.floor(full / 2))
    end
    return {
        key = tostring(caliber) .. "|" .. tostring(pid),
        pid = pid,
        caliber = caliber,
        capacity = capacity,
        slot = Ammo.SlotOf(wep),
        mag_class = class,
        akimbo = akimbo or nil
    }
end

-- The second gun of an akimbo pair: the game marks it with its parent
-- weapon; else it is the _second_gun of the weapon in hand.
function Ammo.IsSecondGun(wep)
    if wep.parent_weapon ~= nil or wep._parent_weapon ~= nil or wep.SKIP_AMMO then return true end
    local ok, result = pcall(function()
        local main = Ammo.EquippedBase()
        local second = main and main ~= wep and main._second_gun
        return second ~= nil and second ~= false and alive(second) and second:base() == wep
    end)
    return ok and result == true
end

function Ammo.SkipReason(wep)
    if not Ammo.settings.enabled then return "mod disabled" end
    if not Ammo.IsOurs(wep) then return "not the player's weapon" end
    if not wep._blueprint and not Ammo.IsLooseFed(wep) then return "no blueprint" end
    -- An akimbo weapon is managed through its main gun (it has _second_gun);
    -- the second gun itself shares that gun's ammunition.
    if Ammo.IsSecondGun(wep) then return "second gun of an akimbo pair" end
    if Ammo.IsLooseFed(wep) then
        if not wep._name_id then return "weapon unknown" end
        return nil
    end
    if mag_part_id(wep) == nil then return "magazine size unknown" end
    return nil
end

function Ammo.SkipWeapon(wep)
    return Ammo.SkipReason(wep) ~= nil
end

---------------------------------------------------------------- the supply

-- The order reloads take magazines in.
-- The weapon's own slot comes first: a magazine put there is the next one.
local GRID_RANK = { gun_primary = 0, gun_secondary = 0, pockets = 1, rig = 2, rig_2 = 3, rig_3 = 4 }
Ammo.GRID_RANK = GRID_RANK
Ammo.GUN_SLOTS = { primary = "gun_primary", secondary = "gun_secondary" }
local GUN_CONTAINER = { gun_primary = true, gun_secondary = true }
Ammo.IsGunSlot = function(name) return GUN_CONTAINER[name] == true end

-- Magazine items of one supply that are to hand, in grid order. The
-- magazine in the gun (in_gun, in the weapon's slot) is not one of them.
function Ammo.Magazines(key)
    local out = {}
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        return item.item_id == Ammo.MAGAZINE_ITEM
            and type(item.data) == "table" and item.data.queue_key == key and not item.data.in_gun
    end)) do
        if is_active(entry.container) or GUN_CONTAINER[entry.container] then
            out[#out + 1] = {
                container = entry.container,
                instance_id = entry.item.instance_id,
                rounds = math.max(0, math.floor(tonumber(entry.item.data.rounds) or 0)),
                capacity = math.max(0, math.floor(tonumber(entry.item.data.capacity) or 0)),
                caliber = entry.item.data.caliber,
                pid = entry.item.data.pid,
                size = entry.item.data.size,
                bullet = entry.item.data.bullet,
                load = entry.item.data.size and Ammo.LoadOf(entry.item.data) or nil,
                x = tonumber(entry.item.x) or 0,
                y = tonumber(entry.item.y) or 0
            }
        end
    end
    -- Grid order: the pockets first, then the rig, each read from the top
    -- left. You choose the order of your reloads by where you put them.
    table.sort(out, function(a, b)
        local ra, rb = GRID_RANK[a.container] or 9, GRID_RANK[b.container] or 9
        if ra ~= rb then return ra < rb end
        if a.y ~= b.y then return a.y < b.y end
        if a.x ~= b.x then return a.x < b.x end
        return a.instance_id < b.instance_id
    end)
    return out
end

-- Every magazine item of one supply, wherever it is stored (not the one in
-- the gun).
function Ammo.AllMagazines(key)
    local out = {}
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        return item.item_id == Ammo.MAGAZINE_ITEM
            and type(item.data) == "table" and item.data.queue_key == key and not item.data.in_gun
    end)) do
        out[#out + 1] = {
            container = entry.container,
            instance_id = entry.item.instance_id,
            rounds = math.max(0, math.floor(tonumber(entry.item.data.rounds) or 0)),
            capacity = math.max(0, math.floor(tonumber(entry.item.data.capacity) or 0)),
            size = entry.item.data.size,
            bullet = entry.item.data.bullet,
            load = entry.item.data.size and Ammo.LoadOf(entry.item.data) or nil
        }
    end
    return out
end

-- Loose ammunition stacks of one supply, wherever they are stored. With a
-- bullet, only the stacks of that bullet (no bullet in the data is standard).
function Ammo.LooseStacks(key, bullet)
    local out = {}
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        if item.item_id ~= Ammo.LOOSE_ITEM or type(item.data) ~= "table" or item.data.queue_key ~= key then
            return false
        end
        return bullet == nil or Ammo.BulletId(item.data.bullet) == bullet
    end)) do
        out[#out + 1] = {
            container = entry.container,
            instance_id = entry.item.instance_id,
            rounds = math.max(0, math.floor(tonumber(entry.item.amount) or 0)),
            caliber = entry.item.data.caliber,
            pid = entry.item.data.pid,
            bullet = entry.item.data.bullet
        }
    end
    table.sort(out, function(a, b) return a.instance_id < b.instance_id end)
    return out
end

function Ammo.MagCount(key)
    return #Ammo.Magazines(key)
end

-- Loose rounds of one supply (of one bullet, or all).
function Ammo.LooseOfKey(key, bullet)
    local total = 0
    for _, entry in ipairs(Ammo.LooseStacks(key, bullet)) do
        total = total + entry.rounds
    end
    return total
end

function Ammo.LooseOf(wep)
    local info = Ammo.Identify(wep)
    if not info then return 0 end
    return Ammo.LooseOfKey(info.key)
end

-- Rounds in the magazines of one supply.
function Ammo.MagazineRounds(key)
    local total = 0
    for _, entry in ipairs(Ammo.Magazines(key)) do
        total = total + entry.rounds
    end
    return total
end

---------------------------------------------------------------- mutations

-- The data of a loose stack of a supply. Rounds of an assault rifle or SMG
-- have a bullet (standard when none is given).
function Ammo.LooseData(key, info, bullet)
    return {
        queue_key = key,
        caliber = info and info.caliber or "",
        pid = info and info.pid or "",
        slot = info and info.slot or nil,
        -- A round weighs by its weapon type.
        mag_class = info and info.mag_class or nil,
        bullet = info and info.typed and Ammo.BulletId(bullet) or nil
    }
end

-- Adds rounds to the loose ammunition of a supply. The rounds are real
-- inventory items, so they take up space and weight like anything else.
function Ammo.AddLooseKey(key, rounds, info, bullet)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    if rounds <= 0 then return true end

    local data = Ammo.LooseData(key, info, bullet)

    local remaining = rounds
    -- Top up a stack that is not full yet.
    for _, entry in ipairs(Ammo.LooseStacks(key, data.bullet)) do
        if remaining <= 0 then break end
        local room = MAX_STACK - entry.rounds
        if room > 0 then
            local take = math.min(room, remaining)
            local ok = PDTI.EditItems({ set_amount = {
                { container = entry.container, instance_id = entry.instance_id, amount = entry.rounds + take }
            } })
            if ok then remaining = remaining - take end
        end
    end

    -- The rest goes into new stacks.
    while remaining > 0 do
        local take = math.min(MAX_STACK, remaining)
        local placed = false
        for _, name in ipairs(Ammo.STORAGE) do
            local ok = PDTI.AddItemAuto(name, Ammo.LOOSE_ITEM, take, data)
            if ok then placed = true break end
        end
        if not placed then
            log("no room for " .. tostring(remaining) .. " loose round(s)")
            return false, "no room in the inventory"
        end
        remaining = remaining - take
    end
    return true
end

function Ammo.AddLoose(wep, rounds)
    local info = Ammo.Identify(wep)
    if not info then return false, "weapon not managed" end
    return Ammo.AddLooseKey(info.key, rounds, info)
end

-- Takes rounds out of the loose ammunition. This is what packing a magazine
-- does: the rounds leave the stack and go into the magazine.
function Ammo.ConsumeLooseKey(key, rounds, bullet)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    local remaining = rounds
    for _, entry in ipairs(Ammo.LooseStacks(key, bullet)) do
        if remaining <= 0 then break end
        if entry.rounds > 0 then
            local take = math.min(remaining, entry.rounds)
            local ok = PDTI.RemoveItem(entry.container, entry.instance_id, take)
            if ok then remaining = remaining - take end
        end
    end
    return rounds - remaining
end

function Ammo.ConsumeLoose(wep, rounds)
    local info = Ammo.Identify(wep)
    if not info then return 0 end
    return Ammo.ConsumeLooseKey(info.key, rounds)
end

-- Sets the loose ammunition of a supply to an exact number of rounds.
function Ammo.SetLooseKey(key, value, info)
    local target = math.max(0, math.floor(tonumber(value) or 0))
    local current = Ammo.LooseOfKey(key)
    if target > current then
        return Ammo.AddLooseKey(key, target - current, info)
    elseif target < current then
        Ammo.ConsumeLooseKey(key, current - target)
    end
    return true
end

function Ammo.SetLoose(wep, value)
    local info = Ammo.Identify(wep)
    if not info then return false, "weapon not managed" end
    return Ammo.SetLooseKey(info.key, value, info)
end

-- Creates a magazine item. It goes to the rig, then the pockets.
-- Returns true and the new item when it worked.
local function magazine_data(key, rounds, info, spec)
    local capacity = info and info.capacity or 0
    local size, bullet, load = nil, nil, nil
    if info and info.typed then
        size = Ammo.SizeId(spec and spec.size)
        capacity = Ammo.SpecCapacity(info.capacity, size)
        rounds = math.min(rounds or 0, capacity)
        -- The bullets it holds, top first; rounds without a known bullet
        -- are of the magazine's own kind.
        local list = Ammo.FitLoad(Ammo.ParseLoad(spec and spec.load), rounds, spec and spec.bullet)
        bullet = Ammo.LoadTop(list) or Ammo.BulletId(spec and spec.bullet)
        if rounds > 0 then load = Ammo.LoadString(list) end
    end
    return {
        queue_key = key,
        rounds = rounds,
        capacity = capacity,
        size = size,
        bullet = bullet,
        load = load,
        caliber = info and info.caliber or "",
        pid = info and info.pid or "",
        slot = info and info.slot or nil,
        -- The size of the magazine follows its weapon type and capacity.
        mag_class = info and info.mag_class or nil,
        akimbo = info and info.akimbo or nil
    }
end

Ammo.MagazineData = magazine_data

function Ammo.AddMagazineKey(key, rounds, info, containers, spec)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    local data = magazine_data(key, rounds, info, spec)
    for _, name in ipairs(containers or Ammo.ACTIVE) do
        local ok, instance = PDTI.AddItemAuto(name, Ammo.MAGAZINE_ITEM, 1, data, true)
        if ok then
            return true, { container = name, instance_id = instance.instance_id, rounds = rounds }
        end
    end
    return false, "no room in the rig or pockets"
end

-- Is there room for one more magazine (of this capacity) in the rig or the
-- pockets?
function Ammo.HasMagazineRoom(capacity, class, akimbo)
    local ref = { item_id = Ammo.MAGAZINE_ITEM,
        data = capacity and { capacity = capacity, mag_class = class, akimbo = akimbo } or nil }
    for _, name in ipairs(Ammo.ACTIVE) do
        if PDTI.FindFreeSpace(name, ref, true) then return true end
    end
    return false
end

function Ammo.AddMagazine(wep, rounds, spec)
    local info = Ammo.Identify(wep)
    if not info then return false, "weapon not managed" end
    return Ammo.AddMagazineKey(info.key, rounds, info, nil, spec)
end

-- The magazine a reload would load: the fullest one in the rig or pockets.
-- An empty magazine is only loaded when the gun has no magazine at all.
function Ammo.NextMagazine(wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed then return nil end
    local list = Ammo.Magazines(info.key)
    local any = wep._issr_mag_gone or wep._issr_no_mag
    for _, entry in ipairs(list) do
        if entry.rounds > 0 or any then return entry end
    end
    return nil
end

-- Takes the fullest magazine of a supply out of the inventory: this is what a
-- reload loads. Returns the magazine that was taken.
function Ammo.TakeMagazine(wep)
    local info = Ammo.Identify(wep)
    if not info then return nil end
    local entry = Ammo.NextMagazine(wep)
    if not entry then return nil end
    local ok = PDTI.RemoveItem(entry.container, entry.instance_id, 1)
    if not ok then return nil end
    return {
        rounds = entry.rounds, capacity = entry.capacity,
        caliber = entry.caliber, pid = entry.pid,
        size = entry.size, bullet = entry.bullet, load = entry.load
    }
end

-- A reload when there is no free place to hand for the magazine that comes
-- out of the gun: it takes SWAP_SLOWDOWN longer, and the old magazine goes
-- exactly where the new one was.
Ammo.SWAP_SLOWDOWN = 1.25
-- Tapping R twice: the reload is FAST_RELOAD times faster, the old magazine
-- is dropped with every round left in it. The second tap must come within
-- DOUBLE_TAP seconds of the first.
Ammo.FAST_RELOAD = 1.5
Ammo.DOUBLE_TAP = 0.5
-- Akimbo: two taps reload one magazine twice as fast, three taps reload both
-- 2.5 times as fast and drop both old magazines. Every tap must come within
-- DOUBLE_TAP seconds of the one before.
Ammo.AKIMBO_ONE = 2.0
Ammo.AKIMBO_DUMP = 2.5

-- True when the magazine in the gun has no free place in the rig or the
-- pockets, so a reload swaps it with the one it loads.
function Ammo.MustSwap(wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed then return false end
    if wep._issr_no_mag or wep._issr_mag_gone then return false end
    if not Ammo.NextMagazine(wep) then return false end
    local loaded = Ammo.LoadedSpec(wep)
    return not Ammo.HasMagazineRoom(loaded and loaded.capacity or info.capacity, info.mag_class, info.akimbo)
end

-- Takes the next magazine out and puts the old one (with these rounds) in
-- its place. Returns the magazine that was taken, like TakeMagazine.
function Ammo.SwapMagazine(wep, rounds, spec)
    local info = Ammo.Identify(wep)
    if not info then return nil end
    local entry = Ammo.NextMagazine(wep)
    local item = entry and PDTI.FindItem(entry.container, entry.instance_id)
    if not item then return nil end
    local spot = { container = entry.container, x = item.x, y = item.y, rotated = item.rotated }
    local taken = Ammo.TakeMagazine(wep)
    if not taken then return nil end
    spec = spec or Ammo.LoadedSpec(wep)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    local data = magazine_data(info.key, math.min(rounds, (spec and spec.capacity) or info.capacity), info, spec)
    local ok = PDTI.AddItem(spot.container, Ammo.MAGAZINE_ITEM, spot.x, spot.y, spot.rotated, 1, data)
    if not ok then Ammo.ReturnMagazine(wep, rounds, spec) end
    return taken
end

-- Puts the magazine that was in the gun back into the inventory.
function Ammo.ReturnMagazine(wep, rounds, spec)
    local info = Ammo.Identify(wep)
    if not info then return false, "weapon not managed" end
    spec = spec or Ammo.LoadedSpec(wep)
    local cap = (spec and spec.capacity) or info.capacity
    rounds = clamp(math.floor(tonumber(rounds) or 0), 0, cap)
    -- The magazine is a real object: an empty one is kept too, so you can
    -- pack it again later. It keeps its size and its bullets.
    local ok = Ammo.AddMagazineKey(info.key, rounds, info, nil, spec)
    if ok then return true end
    ok = Ammo.AddMagazineKey(info.key, rounds, info, { "backpack" }, spec)
    if ok then return true, "backpack" end
    -- No room for the magazine anywhere: its rounds stay with you as loose
    -- ammunition and the empty magazine is left behind.
    if rounds <= 0 then return true, "lost" end
    local added = Ammo.AddLooseKey(info.key, rounds, info, spec and spec.bullet)
    if added then return true, "loose" end
    return false, "no room in the inventory"
end

-- Changes the rounds of a magazine item.
function Ammo.SetMagazineRounds(container, instance_id, rounds)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    return PDTI.EditItems({ update = {
        { container = container, instance_id = instance_id, data = { rounds = rounds } }
    } })
end

------------------------------------------------------------------ the total

function Ammo.MaxTotal(wep)
    local info = Ammo.Identify(wep)
    if not info then return nil end
    local amount = Ammo.MagAmount(info, wep._name_id)
    local in_gun = info.akimbo and 2 * info.capacity or info.capacity
    if info.typed then
        -- The magazine in the gun, whatever its size.
        if info.akimbo then
            local specs = Ammo.PairSpecs(wep)
            in_gun = specs[1].capacity + specs[2].capacity
        else
            in_gun = Ammo.LoadedSpec(wep).capacity
        end
    end
    local base = in_gun + Ammo.ChamberOf(wep) + amount * info.capacity
    local max = math.floor(base * math.max(1, (Ammo.settings.ammo_max or 125) / 100))
    -- What you chose to bring always fits.
    local planned = Ammo.plan_max and Ammo.plan_max[info.key]
    if planned and planned > max then max = planned end
    return max
end

-- The weapon's ammunition is the magazine in the gun, the loose rounds you
-- carry and the rounds in the magazines you carry.
--
-- A weapon that is loaded round by round has no magazines: its ammunition is
-- what is in the gun and the loose rounds. A bow has no reload at all: the
-- game keeps the arrow on the string equal to the arrows you carry, so its
-- total is the loose rounds, and an arrow that was shot leaves the stack.
function Ammo.SyncTotal(wep)
    local info = Ammo.Identify(wep)
    if not info then return end
    Ammo.EnsureSupply(wep)

    if Ammo.NoReload(wep) then
        local synced = wep._pdti_synced
        if synced then
            local shot = synced - wep:get_ammo_total()
            if shot > 0 then Ammo.ConsumeLooseKey(info.key, shot) end
        end
        local loose = Ammo.LooseOfKey(info.key)
        wep._pdti_synced = loose
        if wep:get_ammo_total() ~= loose then wep:set_ammo_total(loose) end
        return
    end

    local total = wep:get_ammo_remaining_in_clip() + Ammo.LooseOfKey(info.key)
    if not info.loose_fed then
        total = total + Ammo.MagazineRounds(info.key)
    end
    if wep:get_ammo_total() ~= total then wep:set_ammo_total(total) end
end

------------------------------------------------------------------- packing

-- How many spare magazines this weapon may have.
function Ammo.MaxMagCount(wep)
    local info = Ammo.Identify(wep)
    if not info then return 0 end
    local count = Ammo.MagAmount(info, wep._name_id) + Ammo.ExtraMags()
    if wep._issr_mag_gone then count = count + (info.akimbo and 2 or 1) end
    return count
end

-- How many rounds the magazine in the gun still takes.
function Ammo.InstalledRoom(wep, capacity)
    if wep._issr_no_mag or wep._issr_mag_gone then return 0 end
    local rounds = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))
    if Ammo.IsAkimbo(wep) then capacity = 2 * capacity end
    return math.max(0, capacity - rounds)
end

---------------------------------------------------- the loaded magazine

-- A magazine's spec: { size, bullet, capacity, load }. The load is kept as
-- it was when the magazine went in; shots take rounds off its top.
local function norm_spec(spec, base)
    spec = type(spec) == "table" and spec or {}
    local size = Ammo.SizeId(spec.size)
    local load = spec.load and Ammo.ParseLoad(spec.load) or nil
    return {
        size = size, bullet = Ammo.BulletId(spec.bullet or Ammo.LoadTop(load)),
        capacity = Ammo.SpecCapacity(base, size), load = load
    }
end
Ammo.NormSpec = norm_spec

-- What a spec holds with this many rounds left (a copy).
local function spec_view(spec, rounds)
    local load = spec.load and Ammo.ParseLoad(spec.load) or {}
    Ammo.FitLoad(load, math.max(0, rounds), spec.bullet)
    return {
        size = spec.size, capacity = spec.capacity, load = load,
        bullet = Ammo.LoadTop(load) or spec.bullet
    }
end

local function gun_rounds(wep)
    local ok, clip = pcall(wep.get_ammo_remaining_in_clip, wep)
    return math.max(0, (ok and tonumber(clip) or 0) - Ammo.ChamberOf(wep))
end

-- Akimbo assault rifles and SMGs: the stored spec of each gun's magazine.
function Ammo.PairSpecs(wep)
    local info = Ammo.Identify(wep)
    local base = info and info.capacity or 15
    local specs = wep._pdti_pair_specs
    if type(specs) ~= "table" or not specs[1] or not specs[1].capacity then
        local one = type(specs) == "table" and specs[1] or wep._pdti_loaded
        local two = type(specs) == "table" and specs[2] or wep._pdti_loaded
        specs = { norm_spec(one, base), norm_spec(two, base) }
        wep._pdti_pair_specs = specs
    end
    return specs
end

-- What each akimbo gun holds now (copies).
function Ammo.PairViews(wep)
    local specs = Ammo.PairSpecs(wep)
    local pair = Ammo.AkimboPair(wep) or { 0, 0 }
    return { spec_view(specs[1], pair[1]), spec_view(specs[2], pair[2]) }
end

local function stored_spec(wep, info)
    local spec = wep._pdti_loaded
    if type(spec) ~= "table" or not spec.capacity then
        spec = norm_spec(spec, info.capacity)
        wep._pdti_loaded = spec
    end
    return spec
end

-- The magazine in the gun of an assault rifle or an SMG as it is now, with
-- the rounds it still holds (nil for the other weapons). Akimbo: the
-- magazine that fires next.
function Ammo.LoadedSpec(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed then return nil end
    if info.akimbo then
        local views = Ammo.PairViews(wep)
        local pair = wep._pdti_pair or { 0, 0 }
        if (tonumber(pair[2]) or 0) > (tonumber(pair[1]) or 0) then return views[2] end
        return views[1]
    end
    return spec_view(stored_spec(wep, info), gun_rounds(wep))
end

-- Puts a magazine into the gun: spec = { size, bullet, load } (a magazine
-- that was taken out of the inventory). Akimbo: specs for both guns, or one
-- for both.
function Ammo.SetLoaded(wep, spec, spec2)
    local info = Ammo.Identify(wep)
    if not info or not info.typed then return end
    wep._pdti_shot_bullet = nil
    if info.akimbo then
        wep._pdti_pair_specs = { norm_spec(spec, info.capacity), norm_spec(spec2 or spec, info.capacity) }
    end
    wep._pdti_loaded = norm_spec(spec, info.capacity)
end

-- The bullet of the next shot.
function Ammo.CurrentBullet(wep)
    local spec = Ammo.LoadedSpec(wep)
    return spec and spec.bullet or nil
end

-- A shot was fired (the game takes the round out of the clip before it
-- works out the damage): the round leaves the top of the magazine. Returns
-- the bullet that was fired.
function Ammo.ShotBullet(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed then return nil end
    local fired = nil
    if info.akimbo then
        local specs = Ammo.PairSpecs(wep)
        local before = wep._pdti_pair and { wep._pdti_pair[1], wep._pdti_pair[2] } or nil
        local pair = Ammo.AkimboPair(wep) or { 0, 0 }
        for i = 1, 2 do
            local spec = specs[i]
            spec.load = spec.load or Ammo.FitLoad({}, before and before[i] or pair[i], spec.bullet)
            local _, popped = Ammo.FitLoad(spec.load, pair[i], spec.bullet)
            if popped then fired = popped end
        end
    else
        local spec = stored_spec(wep, info)
        local rounds = gun_rounds(wep)
        spec.load = spec.load or Ammo.FitLoad({}, rounds, spec.bullet)
        local _, popped = Ammo.FitLoad(spec.load, rounds, spec.bullet)
        fired = popped
    end
    fired = fired or Ammo.CurrentBullet(wep) or "standard"
    wep._pdti_shot_bullet = fired
    return fired
end

-- The bullet of the shot that is being worked out (armour, critical hits).
function Ammo.FiredBullet(wep)
    return wep and (wep._pdti_shot_bullet or Ammo.CurrentBullet(wep)) or nil
end

-- The bullet's effect on the weapon's own flags. The weapon's values are
-- kept once and come back with standard bullets.
function Ammo.ApplyBullet(wep, bullet)
    if not wep then return end
    local orig = wep._pdti_orig_flags
    if not orig then
        orig = {
            enemy = wep._can_shoot_through_enemy,
            shield = wep._can_shoot_through_shield,
            ap = wep._use_armor_piercing
        }
        wep._pdti_orig_flags = orig
    end
    local def = Ammo.BULLETS[Ammo.BulletId(bullet)]
    if def.through == nil then
        wep._can_shoot_through_enemy = orig.enemy
        wep._can_shoot_through_shield = orig.shield
    else
        wep._can_shoot_through_enemy = def.through
        wep._can_shoot_through_shield = def.through
    end
    if def.no_ap_skill then
        wep._use_armor_piercing = false
    else
        wep._use_armor_piercing = orig.ap
    end
    wep._pdti_bullet = Ammo.BulletId(bullet)
end

-- The gun takes the loaded magazine's size: the clip's maximum is its
-- capacity (both magazines for akimbo), and the bullets set the flags.
function Ammo.ApplyLoaded(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed then return end
    local max
    if info.akimbo then
        local specs = Ammo.PairSpecs(wep)
        max = specs[1].capacity + specs[2].capacity
    else
        max = stored_spec(wep, info).capacity
    end
    if wep.set_ammo_max_per_clip then pcall(wep.set_ammo_max_per_clip, wep, max) end
    Ammo.ApplyBullet(wep, Ammo.CurrentBullet(wep))
end

-- The reload speed of the magazine a reload loads: bigger is slower.
function Ammo.SizeReloadFactor(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed then return 1 end
    local entry = Ammo.NextMagazine(wep)
    if not entry then return 1 end
    return 1 / Ammo.MAG_SIZES[Ammo.SizeId(entry.size)].reload
end

------------------------------------------------- the magazine in the gun

-- In a heist the weapon's slot shows the magazine that is in the gun: an
-- item marked in_gun that follows the clip. Taking it out of the slot takes
-- the magazine out of the gun; a magazine put into the empty slot goes into
-- the gun. wep._pdti_gun_items[g] is the item of gun g (akimbo: 1 and 2),
-- wep._pdti_gun_empty[g] marks an akimbo gun without a magazine.

local function gun_container(info)
    return info and info.slot and Ammo.GUN_SLOTS[info.slot] or nil
end

local function gun_count(info)
    return info.akimbo and 2 or 1
end

function Ammo.GunHasMagazine(wep, g)
    if wep._issr_no_mag or wep._issr_mag_gone then return false end
    local empty = wep._pdti_gun_empty
    return not (type(empty) == "table" and empty[g or 1])
end

-- The item data of the magazine in gun g as it is now.
local function gun_mag_data(wep, info, g)
    local rounds, spec
    if info.akimbo then
        rounds = (Ammo.AkimboPair(wep) or { 0, 0 })[g] or 0
        if info.typed then spec = Ammo.PairViews(wep)[g] end
    else
        rounds = gun_rounds(wep)
        if info.typed then spec = Ammo.LoadedSpec(wep) end
    end
    local data = magazine_data(info.key, rounds, info, spec)
    if not info.typed then data.rounds = math.min(data.rounds, info.capacity) end
    data.in_gun = true
    return data
end

-- Our code takes the gun's magazine items away (a reload): they are put
-- back from the gun's state on the next sync.
function Ammo.ClearGunItems(wep)
    local info = Ammo.Identify(wep)
    local c = gun_container(info)
    local items = wep._pdti_gun_items
    if c and type(items) == "table" then
        for g, id in pairs(items) do
            if id then PDTI.RemoveItem(c, id) end
            items[g] = nil
        end
    end
end

local function place_gun_item(wep, info, g)
    local c = gun_container(info)
    local data = gun_mag_data(wep, info, g)
    local ok, item = PDTI.AddItem(c, Ammo.MAGAZINE_ITEM, g - 1, 0, false, 1, data)
    if not ok then ok, item = PDTI.AddItemAuto(c, Ammo.MAGAZINE_ITEM, 1, data, false) end
    if ok and type(item) == "table" then wep._pdti_gun_items[g] = item.instance_id end
end

-- The magazine of gun g was taken out of the weapon's slot (moved or thrown
-- away): the gun has no magazine now. The item becomes a magazine you carry.
local function take_out(wep, info, g, id)
    local entry = PDTI.FindItems(function(_, item) return item.instance_id == id end)[1]
    if entry then
        local want = gun_mag_data(wep, info, g)
        PDTI.EditItems({ update = { { container = entry.container, instance_id = id,
            data = { in_gun = false, rounds = want.rounds, load = want.load or "", bullet = want.bullet } } } })
    end
    if info.akimbo then
        local pair = Ammo.AkimboPair(wep) or { 0, 0 }
        local gone = pair[g] or 0
        pair[g] = 0
        wep._pdti_pair = pair
        wep:set_ammo_remaining_in_clip(math.max(0, wep:get_ammo_remaining_in_clip() - gone))
        wep._pdti_gun_empty = wep._pdti_gun_empty or {}
        wep._pdti_gun_empty[g] = true
        if wep._pdti_gun_empty[1] and wep._pdti_gun_empty[2] then
            wep._issr_no_mag = true
            wep._issr_mag_gone = true
        end
        wep._issr_mag_installed = { rounds = pair[1] + pair[2] }
    else
        local clip = wep:get_ammo_remaining_in_clip()
        wep:set_ammo_remaining_in_clip(math.max(0, math.min(Ammo.ChamberOf(wep), clip)))
        wep._issr_no_mag = true
        wep._issr_mag_gone = true
        wep._issr_mag_installed = { rounds = 0 }
    end
    Ammo.SyncTotal(wep)
    Ammo.MarkPanelDirty()
end

-- A magazine was put into the empty slot of gun g: it goes into the gun.
local function put_in(wep, info, g, item, container)
    local data = item.data
    local cap = info.typed and Ammo.SpecCapacity(info.capacity, data.size) or info.capacity
    local rounds = math.max(0, math.min(math.floor(tonumber(data.rounds) or 0), cap))
    local spec = info.typed and { size = data.size, bullet = data.bullet, load = Ammo.LoadOf(data) } or nil
    local chamber = Ammo.ChamberOf(wep)
    if info.akimbo then
        local empty = wep._pdti_gun_empty or {}
        local pair = (wep._issr_mag_gone or wep._issr_no_mag) and { 0, 0 } or (Ammo.AkimboPair(wep) or { 0, 0 })
        if wep._issr_mag_gone or wep._issr_no_mag then empty = { true, true } end
        local kept = math.max(0, math.min(chamber, wep:get_ammo_remaining_in_clip() - pair[1] - pair[2]))
        if info.typed then
            local views = Ammo.PairViews(wep)
            local specs = { views[1], views[2] }
            specs[g] = spec
            Ammo.SetLoaded(wep, specs[1], specs[2])
        end
        pair[g] = rounds
        empty[g] = false
        wep._pdti_gun_empty = empty
        wep._pdti_pair = pair
        wep._issr_no_mag = nil
        wep._issr_mag_gone = nil
        if info.typed then Ammo.ApplyLoaded(wep) end
        wep:set_ammo_remaining_in_clip(pair[1] + pair[2] + kept)
        wep._pdti_pair = { pair[1], pair[2] }
        wep._issr_mag_installed = { rounds = pair[1] + pair[2] }
    else
        local kept = math.max(0, math.min(chamber, wep:get_ammo_remaining_in_clip()))
        if info.typed then
            Ammo.SetLoaded(wep, spec)
            Ammo.ApplyLoaded(wep)
        end
        wep._issr_no_mag = nil
        wep._issr_mag_gone = nil
        wep:set_ammo_remaining_in_clip(rounds + kept)
        wep._issr_mag_installed = { rounds = rounds }
    end
    PDTI.EditItems({ update = { { container = container, instance_id = item.instance_id, data = { in_gun = true } } } })
    wep._pdti_gun_items[g] = item.instance_id
    Ammo.SyncTotal(wep)
    Ammo.MarkPanelDirty()
end

-- Keeps the weapon's slot and the gun in step (every frame in a heist, and
-- after every action in the inventory screen).
function Ammo.SyncGunSlot(wep)
    if not PDTI.session_only or not wep then return end
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed or Ammo.NoReload(wep) or Ammo.SkipWeapon(wep) then return end
    local c = gun_container(info)
    if not c then return end
    wep._pdti_gun_items = wep._pdti_gun_items or {}
    local items = wep._pdti_gun_items
    for g = 1, gun_count(info) do
        local id = items[g]
        local item = id and PDTI.FindItem(c, id)
        if Ammo.GunHasMagazine(wep, g) then
            if item then
                local want = gun_mag_data(wep, info, g)
                if item.data.rounds ~= want.rounds or (item.data.load or "") ~= (want.load or "")
                    or item.data.in_gun ~= true then
                    PDTI.EditItems({ update = { { container = c, instance_id = id,
                        data = { rounds = want.rounds, load = want.load or "", bullet = want.bullet, in_gun = true } } } })
                end
            elseif id then
                items[g] = nil
                take_out(wep, info, g, id)
            elseif not wep._issr_in_reload then
                place_gun_item(wep, info, g)
            end
        else
            if item then
                -- The gun lost its magazine (a reload, a dropped magazine).
                PDTI.RemoveItem(c, id)
                items[g] = nil
            else
                items[g] = nil
                if not wep._issr_in_reload then
                    -- A magazine of this weapon put into the slot goes in.
                    local claimed = {}
                    for _, other in pairs(items) do claimed[other] = true end
                    local pick = nil
                    for _, cand in ipairs((PDTI.GetContainerInfo(c) or { items = {} }).items) do
                        if cand.item_id == Ammo.MAGAZINE_ITEM and type(cand.data) == "table"
                            and cand.data.queue_key == info.key and not claimed[cand.instance_id] then
                            if not pick or cand.x == g - 1 then pick = cand end
                        end
                    end
                    if pick then put_in(wep, info, g, pick, c) end
                end
            end
        end
    end
end

------------------------------------------------------------------ akimbo

-- Akimbo guns: each gun has its own magazine of half the weapon's capacity.
-- The game counts one clip for both guns, so the mod keeps the rounds of the
-- two magazines itself (wep._pdti_pair) and checks them against the clip.
function Ammo.IsAkimbo(wep)
    local info = wep and Ammo.Identify(wep)
    return info ~= nil and info.akimbo == true and not info.loose_fed
end

-- The rounds of the two magazines in the guns, { left, right }. The guns
-- fire in turn, so the shots come out of the fuller magazine first.
function Ammo.AkimboPair(wep)
    local info = Ammo.Identify(wep)
    if not info or not info.akimbo or info.loose_fed then return nil end
    local cap_a, cap_b = info.capacity, info.capacity
    if info.typed then
        local specs = Ammo.PairSpecs(wep)
        cap_a, cap_b = specs[1].capacity, specs[2].capacity
    end
    local loaded = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))
    local pair = wep._pdti_pair
    if type(pair) ~= "table" then
        local a = math.min(cap_a, math.ceil(loaded / 2))
        pair = { a, math.min(cap_b, loaded - a) }
    end
    local a = clamp(math.floor(tonumber(pair[1]) or 0), 0, cap_a)
    local b = clamp(math.floor(tonumber(pair[2]) or 0), 0, cap_b)
    -- The rounds that were fired leave the gun that fired them (1 = left,
    -- 2 = right, set while a gun fires), else the fuller magazine.
    local firing = wep._pdti_fire_gun
    while a + b > loaded do
        if firing == 1 and a > 0 then a = a - 1
        elseif firing == 2 and b > 0 then b = b - 1
        elseif a >= b then a = a - 1 else b = b - 1 end
    end
    while a + b < loaded and (a < cap_a or b < cap_b) do
        if (a <= b or b >= cap_b) and a < cap_a then a = a + 1 elseif b < cap_b then b = b + 1 else a = a + 1 end
    end
    pair = { a, b }
    wep._pdti_pair = pair
    return pair
end

-- The rounds a magazine item holds.
function Ammo.EntryCapacity(info, entry)
    local cap = tonumber(entry.capacity) or 0
    if cap <= 0 then cap = info.capacity end
    return cap
end

-- The bullets a magazine with room can take, or nil: its own bullets, any
-- for an empty magazine (its own first). With a pool (bullet -> rounds),
-- only bullets there are; without, the loose rounds you carry.
function Ammo.FillBullet(info, entry, pool)
    if Ammo.EntryCapacity(info, entry) - entry.rounds <= 0 then return nil end
    local function has(id)
        if pool then return (pool[id] or 0) > 0 end
        return Ammo.LooseOfKey(info.key, info.typed and id or nil) > 0
    end
    if not info.typed then
        if has("all") then return "all" end
        return nil
    end
    -- The magazine's own kind first (the bullets on top), then any: a
    -- magazine can hold several kinds, the new rounds go on top.
    local own = Ammo.BulletId(Ammo.LoadTop(entry.load) or entry.bullet)
    if has(own) then return own end
    for _, id in ipairs(Ammo.BULLET_ORDER) do
        if has(id) then return id end
    end
    return nil
end

-- Does this weapon have anything that could take a round?
function Ammo.NeedsFill(wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed or Ammo.SkipWeapon(wep) then return false end
    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        if Ammo.FillBullet(info, entry) then return true end
    end
    -- Only magazines you carry can be packed: loose rounds never turn into a
    -- new magazine and never go into the magazine in the gun.
    return false
end

-- Moves rounds from the loose ammunition into the magazines and into the
-- magazine in the gun. Returns the number of rounds that stayed loose.
--
-- "extra" are rounds that are not loose yet (the ammunition of an ammo bag).
-- They are used when the loose ammunition runs out.
function Ammo.FillMagazines(wep, amount, extra)
    local info = Ammo.Identify(wep)
    if not info then return 0 end

    local loose = Ammo.LooseOfKey(info.key)
    local extra = math.max(0, math.floor(tonumber(extra) or 0))
    if info.loose_fed then return loose + extra end
    local available = loose + extra
    local want = math.min(math.max(0, math.floor(tonumber(amount) or 0)), available)
    if want <= 0 then return available end

    -- The rounds there are, by bullet ("all" for the other weapons). The
    -- rounds that are not loose yet are standard rounds.
    local pool, from_loose = {}, {}
    if info.typed then
        for _, id in ipairs(Ammo.BULLET_ORDER) do
            pool[id] = Ammo.LooseOfKey(info.key, id)
            from_loose[id] = pool[id]
        end
        pool.standard = pool.standard + extra
    else
        pool.all = loose + extra
        from_loose.all = loose
    end
    local used = {}

    local placed = 0
    local updates = {}

    -- 1. Fill the magazines that are to hand, the fullest first. A
    -- magazine only takes its own bullets; an empty one takes any.
    local magazines = Ammo.Magazines(info.key)
    table.sort(magazines, function(a, b)
        if a.rounds ~= b.rounds then return a.rounds > b.rounds end
        return a.instance_id < b.instance_id
    end)
    for _, entry in ipairs(magazines) do
        local start = entry.rounds
        local data = nil
        while placed < want do
            local room = math.max(0, Ammo.EntryCapacity(info, entry) - entry.rounds)
            local bucket = room > 0 and Ammo.FillBullet(info, entry, pool) or nil
            if not bucket then break end
            local take = math.min(room, want - placed, pool[bucket])
            if take <= 0 then break end
            entry.rounds = entry.rounds + take
            data = data or {}
            data.rounds = entry.rounds
            if info.typed then
                entry.load = Ammo.LoadPush(entry.load or Ammo.FitLoad({}, start, entry.bullet), bucket, take)
                data.bullet = bucket
                data.load = Ammo.LoadString(entry.load)
            end
            pool[bucket] = pool[bucket] - take
            used[bucket] = (used[bucket] or 0) + take
            placed = placed + take
        end
        if data then
            updates[#updates + 1] = { container = entry.container, instance_id = entry.instance_id, data = data }
        end
    end

    -- The magazine in the gun is not packed: it is in the weapon. Loose
    -- rounds never become a new magazine: without a magazine with room in
    -- the rig or the pockets they stay loose.

    if #updates > 0 then
        local ok, reason = PDTI.EditItems({ update = updates })
        if not ok then
            log("could not fill the magazines: " .. tostring(reason))
            return loose
        end
    end

    -- The rounds really leave the loose ammunition: first the loose rounds,
    -- then the rounds that were not loose yet.
    for bucket, n in pairs(used) do
        local take = math.min(n, from_loose[bucket] or 0)
        if take > 0 then
            Ammo.ConsumeLooseKey(info.key, take, info.typed and bucket or nil)
        end
    end

    return available - placed
end

------------------------------------------------------------- the ammo bag

-- The magazine an ammo bag adds: the kind chosen in the menu ("+Mag": its
-- size and the rounds of each bullet), full. Other weapons: a full one.
function Ammo.BagMagazineSpec(wep, info)
    if not info.typed then return nil, info.capacity end
    local p = PDTI.GetPlanSlot and PDTI.GetPlanSlot(Ammo.SlotOf(wep) or "primary") or {}
    local size = Ammo.SizeId(p.pick_size)
    local cap = Ammo.SpecCapacity(info.capacity, size)
    local load = p.pick_load and Ammo.ParseLoad(p.pick_load) or {}
    -- A smaller magazine: the bottom rounds do not fit.
    local over = Ammo.LoadTotal(load) - cap
    while over > 0 and load[#load] do
        local take = math.min(over, load[#load][2])
        load[#load][2] = load[#load][2] - take
        over = over - take
        if load[#load][2] <= 0 then table.remove(load) end
    end
    -- Room left: the chosen bullets at the bottom.
    Ammo.FitLoad(load, cap, p.pick_bullet)
    return { size = size, bullet = Ammo.LoadTop(load), load = Ammo.LoadString(load) }, cap
end

-- An ammo bag restocks magazines, not loose rounds:
--   1. every magazine you carry for the weapon is filled to full with its
--      own bullets (the kind on top), so a half-empty armour-piercing
--      magazine comes back full of armour piercing;
--   2. then new full magazines of the kind chosen in the menu are added, up
--      to the number of magazines you may carry, as far as there is room.
-- available: the share of the weapon's maximum ammunition the bag can still
-- give (as the game passes it). Returns the share used, as the game does.
function Ammo.BagRestock(wep, available)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed then return nil end
    local max = math.max(1, tonumber(wep:get_ammo_max()) or 1)
    local budget = math.floor((tonumber(available) or 1) * max + 1e-6)
    local given = 0

    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        if given >= budget then break end
        local room = math.max(0, Ammo.EntryCapacity(info, entry) - entry.rounds)
        local take = math.min(room, budget - given)
        if take > 0 then
            if info.typed then
                local load = entry.load or Ammo.FitLoad({}, entry.rounds, entry.bullet)
                local own = Ammo.BulletId(Ammo.LoadTop(load) or entry.bullet)
                load = Ammo.LoadPush(load, own, take)
                PDTI.EditItems({ update = { { container = entry.container, instance_id = entry.instance_id,
                    data = { rounds = entry.rounds + take, bullet = own, load = Ammo.LoadString(load) } } } })
            else
                Ammo.SetMagazineRounds(entry.container, entry.instance_id, entry.rounds + take)
            end
            given = given + take
        end
    end

    local spec, cap = Ammo.BagMagazineSpec(wep, info)
    local guard = 0
    while #Ammo.Magazines(info.key) < Ammo.MaxMagCount(wep) and budget - given >= cap and guard < 50 do
        guard = guard + 1
        local ok = Ammo.AddMagazineKey(info.key, cap, info, nil, spec)
        if not ok then
            ok = Ammo.AddMagazineKey(info.key, cap, info, { "backpack" }, spec)
        end
        if not ok then break end
        given = given + cap
    end

    Ammo.SyncTotal(wep)
    Ammo.MarkPanelDirty()
    return math.min(tonumber(available) or 1, given / max), given
end

-- Would an ammo bag give this weapon anything?
function Ammo.BagWanted(wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed then return false end
    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        if Ammo.EntryCapacity(info, entry) > entry.rounds then return true end
    end
    if #Ammo.Magazines(info.key) >= Ammo.MaxMagCount(wep) then return false end
    local _, cap = Ammo.BagMagazineSpec(wep, info)
    local data = { capacity = cap, mag_class = info.mag_class, akimbo = info.akimbo }
    return Ammo.HasMagazineRoom(cap, info.mag_class, info.akimbo)
        or PDTI.FindFreeSpace("backpack", { item_id = Ammo.MAGAZINE_ITEM, data = data }, true) ~= nil
end

------------------------------------------------------------- the fill job

local job = nil

function Ammo.StartJob(wep)
    if not wep then return end
    if job then
        for _, entry in ipairs(job.list) do
            if entry == wep then return end
        end
    end
    job = job or { list = {}, index = 1, t = 0, filled = 0 }
    job.list[#job.list + 1] = wep
end

function Ammo.JobActive()
    return job ~= nil and job.index <= #job.list
end

function Ammo.StopJob()
    job = nil
end

local function fill_one_round()
    if not job then return end

    while job.index <= #job.list do
        local wep = job.list[job.index]
        if not wep or Ammo.SkipWeapon(wep) then
            job.index = job.index + 1
        else
            break
        end
    end

    if job.index > #job.list then
        job = nil
        return
    end

    local wep = job.list[job.index]
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed or Ammo.LooseOfKey(info.key) <= 0 then
        job.index = job.index + 1
        return
    end

    local target = nil
    local magazines = Ammo.Magazines(info.key)
    table.sort(magazines, function(a, b)
        if a.rounds ~= b.rounds then return a.rounds > b.rounds end
        return a.instance_id < b.instance_id
    end)
    local bullet = nil
    for _, entry in ipairs(magazines) do
        bullet = Ammo.FillBullet(info, entry)
        if bullet then
            target = entry
            break
        end
    end

    local into_gun = false

    -- Every magazine is full: the loose rounds stay loose. No new magazine
    -- is made out of thin air.

    if not target and not into_gun then
        job.index = job.index + 1
        return
    end

    if into_gun then
        wep:set_ammo_remaining_in_clip(wep:get_ammo_remaining_in_clip() + 1)
        local installed = wep._issr_mag_installed or { rounds = 0 }
        installed.rounds = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))
        wep._issr_mag_installed = installed
    elseif info.typed then
        local load = Ammo.LoadPush(target.load or Ammo.FitLoad({}, target.rounds, target.bullet), bullet, 1)
        PDTI.EditItems({ update = {
            { container = target.container, instance_id = target.instance_id,
                data = { rounds = target.rounds + 1, bullet = bullet, load = Ammo.LoadString(load) } }
        } })
    else
        Ammo.SetMagazineRounds(target.container, target.instance_id, target.rounds + 1)
    end

    -- The round comes out of the loose ammunition you carry.
    Ammo.ConsumeLooseKey(info.key, 1, info.typed and bullet or nil)
    Ammo.SyncTotal(wep)

    job.filled = job.filled + 1
    -- No sound per round: loading a magazine is silent (0.18.0).
end

function Ammo.Tick(dt)
    if not job then return end
    job.t = job.t + (dt or 0)
    local interval = math.max(0.02, tonumber(Ammo.settings.round_interval) or 0.25)
    if job.t < interval then return end
    job.t = 0
    fill_one_round()
end

--------------------------------------------------------------- the supply

local supply_ready = {}

-- Has a weapon got its ammunition for this heist (the plan or the game's)?
function Ammo.SupplyReady(wep)
    local ok, info = pcall(Ammo.Identify, wep)
    if not ok or not info then return true end
    return supply_ready[info.key] == true
end

-- A new weapon type needs its starting magazines. They are real items in the
-- rig, so the player can move them or leave them behind.
function Ammo.EnsureSupply(wep)
    local info = Ammo.Identify(wep)
    if not info then return false end
    -- An assault rifle or SMG: the magazine in the gun is the mod's, not the
    -- game's magazine mod (a standard one until a reload or the plan says
    -- otherwise).
    if info.typed and not wep._pdti_applied then
        wep._pdti_applied = true
        Ammo.ApplyLoaded(wep)
        local max = info.akimbo and (Ammo.PairSpecs(wep)[1].capacity + Ammo.PairSpecs(wep)[2].capacity)
            or Ammo.LoadedSpec(wep).capacity
        local limit = max + Ammo.ChamberOf(wep)
        if wep:get_ammo_remaining_in_clip() > limit then wep:set_ammo_remaining_in_clip(limit) end
    end
    if supply_ready[info.key] then return true end
    supply_ready[info.key] = true

    -- The ammunition chosen in the menu becomes this weapon's.
    local plan = PDTI.Plan
    if plan then
        pcall(plan.RememberWeapon, wep, info)
        if PDTI.IsAmmoPlanned and PDTI.IsAmmoPlanned() then
            local ok, err = pcall(plan.Bind, wep, info)
            if not ok then log("could not bind the chosen ammunition: " .. tostring(err)) end
            return true
        end
    end

    -- A weapon that is loaded round by round starts with the ammunition the
    -- game gave it, as loose rounds.
    if info.loose_fed then
        local reserve = wep:get_ammo_total()
        if not Ammo.NoReload(wep) then
            reserve = reserve - wep:get_ammo_remaining_in_clip()
        end
        reserve = math.max(0, math.floor(reserve))
        local have = Ammo.LooseOfKey(info.key)
        if reserve > have then
            local ok = Ammo.AddLooseKey(info.key, reserve - have, info)
            if not ok then
                log(string.format("%s: not all of the %d starting round(s) fit in the inventory",
                    tostring(wep._name_id), reserve))
            end
        end
        if Ammo.NoReload(wep) then wep._pdti_synced = Ammo.LooseOfKey(info.key) end
        return true
    end

    local amount = Ammo.MagAmount(info, wep._name_id) + Ammo.ExtraMags()
    local created, stored = 0, 0
    for _ = 1, amount do
        local ok = Ammo.AddMagazineKey(info.key, info.capacity, info)
        if ok then
            created = created + 1
        elseif Ammo.AddMagazineKey(info.key, info.capacity, info, { "backpack" }) then
            -- The rig and the pockets are full: the magazine is packed into
            -- the backpack. Move it to the rig to use it.
            created = created + 1
            stored = stored + 1
        end
    end
    if stored > 0 then
        log(string.format("%s: %d starting magazine(s) went into the backpack (rig and pockets are full)",
            tostring(wep._name_id), stored))
    end
    if created < amount then
        log(string.format("%s: only %d of %d starting magazine(s) fit in the inventory",
            tostring(wep._name_id), created, amount))
    end
    return created > 0
end

-- A new heist: the ammunition resets.
function Ammo.OnHeistStart()
    supply_ready = {}
    Ammo.plan_max = {}
    job = nil
    local spec = { remove = {} }
    -- Ammunition chosen in the menu (plan_slot) stays: it becomes the
    -- weapon's when the weapon is first used. Anything else is left over.
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        if item.item_id ~= Ammo.MAGAZINE_ITEM and item.item_id ~= Ammo.LOOSE_ITEM then return false end
        return not (type(item.data) == "table" and item.data.plan_slot)
    end)) do
        spec.remove[#spec.remove + 1] = {
            container = entry.container, instance_id = entry.item.instance_id
        }
    end
    if #spec.remove > 0 then
        local ok, reason = PDTI.EditItems(spec)
        if not ok then log("could not clear last heist's ammunition: " .. tostring(reason)) end
    end
end

function Ammo.Reset()
    supply_ready = {}
    job = nil
end

-- The HUD panel asks for a redraw. The HUD module replaces this with the
-- real drawing, but the flag is enough for the hooks.
function Ammo.MarkPanelDirty()
    Ammo.panel_dirty = true
end

function Ammo.TakePanelDirty()
    local dirty = Ammo.panel_dirty
    Ammo.panel_dirty = false
    return dirty
end

function Ammo.IsPanelVisible()
    return Ammo.panel_visible
end

function Ammo.SetPanel()
    -- Replaced by ammo_hud.lua.
end

function Ammo.RefreshPanel()
    -- Replaced by ammo_hud.lua.
end

function Ammo.RefreshHud()
    -- Replaced by ammo_hud.lua.
end

---------------------------------------------------------- testing spawns

-- The weapon in a slot: "primary" or "secondary".
function Ammo.WeaponInSlot(slot)
    local pl = Ammo.PlayerUnit()
    if not pl then return nil end
    local index = slot == "primary" and 2 or 1
    local ok, unit = pcall(function() return pl:inventory():unit_by_selection(index) end)
    if not ok or not unit or not alive(unit) then return nil end
    local base_ok, base = pcall(function() return unit:base() end)
    if base_ok then return base end
    return nil
end

local function spawn_target(slot)
    local wep = Ammo.WeaponInSlot(slot)
    if not wep then return nil, nil, "no " .. tostring(slot) .. " weapon (only in a heist)" end
    if Ammo.SkipWeapon(wep) then return nil, nil, "the " .. tostring(slot) .. " is not managed: " .. tostring(Ammo.SkipReason(wep)) end
    local info = Ammo.Identify(wep)
    if not info then return nil, nil, "the " .. tostring(slot) .. " is not managed" end
    -- The starting supply comes first, so a spawn is really one more.
    Ammo.EnsureSupply(wep)
    return wep, info
end

-- Testing: one magazine's worth of loose rounds for a weapon.
-- With a bullet ("hollow", "ap"), rounds of that kind (assault rifles and
-- SMGs only).
function Ammo.DevSpawnLoose(slot, bullet)
    local wep, info, reason = spawn_target(slot)
    if not wep then return false, reason end
    local rounds = math.max(1, info.capacity or 1)
    local ok, why = Ammo.AddLooseKey(info.key, rounds, info, bullet)
    if not ok then return false, why end
    pcall(Ammo.SyncTotal, wep)
    Ammo.MarkPanelDirty()
    return true, rounds
end

-- Testing: a full magazine for a weapon (rig, pockets, then backpack).
function Ammo.DevSpawnMagazine(slot, bullet)
    local wep, info, reason = spawn_target(slot)
    if not wep then return false, reason end
    if info.loose_fed then return false, "this weapon is loaded from loose rounds; it has no magazines" end
    if bullet and bullet ~= "standard" and not info.typed then
        return false, "only assault rifles and SMGs take other bullets"
    end
    local spec = info.typed and { size = "standard", bullet = bullet } or nil
    local ok = Ammo.AddMagazineKey(info.key, info.capacity, info, Ammo.STORAGE, spec)
    if not ok then return false, "no room in the inventory" end
    pcall(Ammo.SyncTotal, wep)
    Ammo.MarkPanelDirty()
    return true, info.capacity
end

------------------------------------------------------------- the summary

-- The loose ammunition the player carries.
function Ammo.GetSummary()
    local stacks = {}
    local total = 0
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        return item.item_id == Ammo.LOOSE_ITEM
    end)) do
        local rounds = math.max(0, math.floor(tonumber(entry.item.amount) or 0))
        total = total + rounds
        stacks[#stacks + 1] = {
            container = entry.container,
            rounds = rounds,
            caliber = entry.item.data and entry.item.data.caliber,
            queue_key = entry.item.data and entry.item.data.queue_key,
            slot = entry.item.data and entry.item.data.slot
        }
    end
    return { stacks = stacks, total = total }
end

-- The magazine supplies the player carries, one entry per magazine type.
function Ammo.GetSupplySummary()
    local out = {}
    local seen = {}
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        return item.item_id == Ammo.MAGAZINE_ITEM
    end)) do
        local data = entry.item.data or {}
        local key = data.queue_key
        if key and not seen[key] then
            seen[key] = true
            local rounds = {}
            for _, mag in ipairs(Ammo.Magazines(key)) do rounds[#rounds + 1] = mag.rounds end
            out[#out + 1] = {
                queue_key = key,
                caliber = data.caliber,
                slot = data.slot,
                weapon_id = data.weapon_id,
                magazines = rounds,
                loose = Ammo.LooseOfKey(key)
            }
        end
    end
    table.sort(out, function(a, b) return tostring(a.queue_key) < tostring(b.queue_key) end)
    return out
end

------------------------------------------------------------- ISSR facade

-- The API of the InsurgencySandstormStyleReload mod, backed by the inventory.
-- Third-party mods and HUD mods that use ISSR keep working.
local function facade_queue_of(wep)
    local info = Ammo.Identify(wep)
    if not info then return nil end
    local queue = {}
    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        queue[#queue + 1] = { rounds = entry.rounds }
    end
    return queue, info.key, info.pid, info.caliber, info.capacity
end

local function facade_fill_mags(wep, amount)
    local left = Ammo.FillMagazines(wep, amount)
    return left
end

local function facade_pickup_dropped(tag)
    if not tag then return false end
    local info = { key = tag.queue_key, capacity = tag.capacity, caliber = tag.caliber, pid = tag.pid,
        mag_class = tag.mag_class, akimbo = tag.akimbo }
    -- A magazine of the gun in your hands gets that gun's size.
    local current = Ammo.EquippedBase()
    local current_info = current and Ammo.Identify(current)
    if current_info and current_info.key == tag.queue_key then
        info.mag_class, info.akimbo = current_info.mag_class, current_info.akimbo
    end
    local ok = Ammo.AddMagazineKey(tag.queue_key, tag.rounds or 0, info)
    if ok then
        local wep = Ammo.EquippedBase()
        if wep then pcall(Ammo.SyncTotal, wep) end
    end
    return ok
end

local function facade_can_pickup_dropped(tag)
    if not tag or not tag.queue_key then return false end
    local cap = mag_amount_for(tag.pid, tag.caliber, tag.name_id) * (tag.akimbo and 2 or 1) + Ammo.ExtraMags()
    return Ammo.MagCount(tag.queue_key) < cap
end

Ammo.facade = {
    queue_of = facade_queue_of,
    sort_queue = function(queue) return queue end,
    new_mag = function(rounds) return { rounds = rounds } end,
    loose_of = function(wep) return Ammo.LooseOf(wep) end,
    set_loose = function(wep, value) return Ammo.SetLoose(wep, value) end,
    sync_total = function(wep) return Ammo.SyncTotal(wep) end,
    max_total = function(wep) return Ammo.MaxTotal(wep) end,
    skip_weapon = function(wep) return Ammo.SkipWeapon(wep) end,
    chamber_of = function(wep) return Ammo.ChamberOf(wep) end,
    needs_fill = function(wep) return Ammo.NeedsFill(wep) end,
    fill_mags = facade_fill_mags,
    mag_count = function(wep)
        local info = Ammo.Identify(wep)
        if not info then return nil end
        return Ammo.MagCount(info.key)
    end,
    equipped_base = function() return Ammo.EquippedBase() end,
    player_unit = function() return Ammo.PlayerUnit() end,
    pickup_dropped = facade_pickup_dropped,
    can_pickup_dropped = facade_can_pickup_dropped,
    tick = function(dt) return Ammo.Tick(dt) end,
    add_to_job = function(wep) return Ammo.StartJob(wep) end,
    nqr_present = function() return rawget(_G, "NQR") ~= nil end
}

-- Expose the facade under the old global so other mods find it.
local issr = rawget(_G, "ISSR")
if type(issr) == "table" and type(issr.api) == "table" then
    log("another InsurgencySandstormStyleReload installation was found; remove that mod")
else
    issr = rawget(_G, "ISSR") or {}
    _G.ISSR = issr
    issr.api = Ammo.facade
    issr.pdti_merged = true
end

Ammo.facade_state = issr
