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
-- The ammo pouch (Fully Loaded) holds only loose rounds: it comes first, so
-- loose rounds go there first and are taken from there first.
Ammo.ACTIVE = { "pouch", "rig", "rig_2", "rig_3", "pockets" }

-- Every container, for things that are stored but still usable (loose rounds).
Ammo.STORAGE = { "pouch", "rig", "rig_2", "rig_3", "pockets", "backpack" }

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

local log = PDTI.Logger("PDTI AMMO")

Ammo.log = log

------------------------------------------------------------------ settings

-- The settings of the merged ISSR mod. The old save files are read so the
-- values the player already chose survive the merge.
Ammo.settings = {
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
    -- Heavy armour: plates instead of regeneration once broken (armour.lua).
    heavy_armour = true,
    -- The size of the inventory screen (ui_beardlib.lua), from the next open.
    ui_scale = 1,
    -- Pictures of weapons and parts on the inventory screen (ui_pictures.lua).
    item_pictures = true,
    -- Names written over those pictures (in the grid, PRI / SEC).
    item_picture_names = true,
    -- The mouse wheel chooses the next magazine (and "gun": take it out).
    wheel_choose = true,
    -- Start in the safehouse, and go back there after every job (safehouse.lua).
    safehouse_home = true,
    enabled = true
}

local SETTING_FILES = {
    { file = "issr_settings.txt", keys = {
        "drop_mode", "hold_time", "overlay_always",
        "show_mags", "show_loose", "show_ammo_type", "max_boxes", "show_more",
        "font_size", "pad_right", "pad_bottom", "enabled" } },
    { file = "issr_reload_settings.txt", keys = {
        "round_interval", "sound", "unblock_bag", "akimbo_buttons", "body_parts", "heavy_armour", "ui_scale", "wheel_choose",
        "safehouse_home", "item_pictures", "item_picture_names" } }
}
Ammo.SETTING_FILES = SETTING_FILES

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
Ammo.LoadSettings = load_settings

-- Writes the settings back into the same two files (the options menu).
function Ammo.SaveSettings()
    if not rawget(_G, "json") then return false, "no json" end
    local all = true
    for _, entry in ipairs(SETTING_FILES) do
        local data = {}
        for _, key in ipairs(entry.keys) do data[key] = Ammo.settings[key] end
        local ok = pcall(function()
            local file = assert(io.open((rawget(_G, "SavePath") or "") .. entry.file, "w"))
            file:write(json.encode(data))
            file:close()
        end)
        if not ok then all = false end
    end
    if not all then log("could not save the settings") end
    return all
end

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

local function equipped_of(unit)
    return unit:inventory():equipped_unit()
end

function Ammo.EquippedUnit()
    local unit = Ammo.PlayerUnit()
    if not unit then return nil end
    local ok, equipped = pcall(equipped_of, unit)
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
    if info.sized then
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

-- Weapons that are loaded round by round take their ammunition straight from
-- the loose rounds you carry and have no magazines: shotguns that load shell
-- by shell, double-barrelled shotguns, bows, crossbows, grenade launchers and
-- the rifles that are loaded one cartridge at a time.
local LOOSE_CATEGORIES = { bow = true, crossbow = true, grenade_launcher = true }
Ammo.LOOSE_CATEGORIES = LOOSE_CATEGORIES

local SHOTGUN_ONLY = { shotgun = true }
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
    if has_category(wep, SHOTGUN_ONLY) and size and size <= 2 then return "loose" end
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
local function selection_of(wep) return wep:selection_index() end
function Ammo.SlotOf(wep)
    local ok, index = pcall(selection_of, wep)
    if ok and index == 2 then return "primary" end
    if ok and index == 1 then return "secondary" end
    return nil
end

-- The size class of a weapon's magazines (PDTI.MagazineSize): the first of
-- these categories the weapon has. Akimbo guns carry a magazine for each gun.
Ammo.SIZE_CLASSES = { "grenade_launcher", "crossbow", "bow", "shotgun", "snp", "lmg", "minigun", "flamethrower", "smg", "revolver", "pistol", "assault_rifle" }

local EMPTY = {}
function Ammo.SizeClass(wep)
    local tweak = weapon_tweak(wep)
    local categories = tweak and tweak.categories or EMPTY
    local akimbo = false
    for _, category in ipairs(categories) do
        if category == "akimbo" then akimbo = true break end
    end
    for _, class in ipairs(Ammo.SIZE_CLASSES) do
        for _, category in ipairs(categories) do
            if category == class then return class, akimbo end
        end
    end
    return nil, akimbo
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
-- weapon's own); limb_crit: every hit on an arm or a leg is a critical hit.
Ammo.BULLETS = {
    standard = { name = "Standard", short = "STD", damage = 1.0 },
    -- Hollow points hit a little harder than standard rounds and make every
    -- limb hit a critical; armour piercing hits hardest (it is the dearest).
    hollow = { name = "Hollow point", short = "HP", damage = 1.1, pierce = 0, through = false,
        limb_crit = true },
    -- Armour piercing is less stable: every shot kicks harder (recoil), and
    -- the kick builds up while you keep firing (recoil_build per shot in a
    -- row, up to recoil_build_max shots), so full auto climbs away and single
    -- aimed shots are the way to use it.
    ap = { name = "Armour piercing", short = "AP", damage = 1.3, pierce = 1, through = true,
        recoil = 1.5, recoil_build = 0.1, recoil_build_max = 6, family = "rifle" },

    -- Shotgun shells: the game's own ammunition types. Their effect is the
    -- game's, exactly as if the ammo mod was on the gun (shells.lua takes it
    -- from the game per shell), so nothing here changes damage or flags.
    -- part: the game's ammo part; parts: also counts as this shell.
    custom = { name = "000 Buckshot", short = "000", family = "shell",
        part = "wpn_fps_upg_a_custom", parts = { "wpn_fps_upg_a_custom_free" } },
    flechette = { name = "Flechette", short = "FL", family = "shell", part = "wpn_fps_upg_a_piercing" },
    slug = { name = "AP Slug", short = "SLG", family = "shell", part = "wpn_fps_upg_a_slug" },
    tombstone = { name = "Tombstone Slug", short = "TS", family = "shell", part = "wpn_fps_upg_a_rip" },
    dragon = { name = "Dragon's Breath", short = "DB", family = "shell", part = "wpn_fps_upg_a_dragons_breath" },
    he = { name = "HE Round", short = "HE", family = "shell", part = "wpn_fps_upg_a_explosive" },

    -- LMG rounds.
    -- explosive: a weak round that bursts on impact. The hit itself does
    -- little, and a small blast (blast_range, in cm) does the same low damage
    -- around the point of impact. It never goes through anything.
    -- A concussion round against people, an anti-armour round against
    -- bulldozers and turrets:
    --   * the blast can be a critical hit (the player's crit chance, as a
    --     bullet), and always is on a bulldozer or a turret (sure_crit);
    --   * on a bulldozer or a turret it does heavy_mul times the damage
    --     (before the crit): 0.35 x 4 x 2 = 2.8 standard rounds, and
    --     restoration-mod's bulldozers take x2.5 from explosions on top;
    --   * every other enemy who lives through it is dazed (stun_chance 1:
    --     the concussion grenade's stun). Bulldozers are not.
    explosive = { name = "HE round", short = "HE", family = "lmg", damage = 0.35, pierce = 0, through = false,
        explosive = true, blast_range = 60, blast_crit = true, sure_crit = true, heavy_mul = 4,
        stun_chance = 1, dozer_stun_chance = 0 },
    -- penetrator: a heavy core that goes through armour, shields, enemies and
    -- thin walls. Fired from the shoulder it kicks very hard, and the kick
    -- climbs fast while you hold the trigger; on the bipod (bipod_recoil) it
    -- is a little harder than a standard round and does not climb.
    penetrator = { name = "Penetrator", short = "PEN", family = "lmg", damage = 1.5, pierce = 1, through = true,
        wall = true, recoil = 4, recoil_build = 0.25, recoil_build_max = 8, bipod_recoil = 1.15 }
}
Ammo.BULLETS.hollow.family = "rifle"
-- Rifle bullets (assault rifles, SMGs) and shotgun shells. "standard" is in
-- both: a standard rifle round, or buckshot (the gun without an ammo mod).
Ammo.BULLET_ORDER = { "standard", "hollow", "ap" }
Ammo.SHELL_ORDER = { "standard", "custom", "flechette", "slug", "tombstone", "dragon", "he" }
Ammo.LMG_ORDER = { "standard", "explosive", "penetrator" }
Ammo.FAMILY_ORDER = { rifle = Ammo.BULLET_ORDER, shell = Ammo.SHELL_ORDER, lmg = Ammo.LMG_ORDER }
-- The names "standard" has in each family.
Ammo.STANDARD_NAMES = { rifle = { name = "Standard", short = "STD" }, shell = { name = "Buckshot", short = "BK" } }

-- A gun without a magazine (taken out, or dropped and the reload stopped)
-- reloads faster: the part of the reload that takes the old magazine out
-- (the first 30%) is skipped, so the rest runs in the time it would take.
Ammo.EMPTY_GUN_SPEED = 1 / 0.7

function Ammo.GunWithoutMagazine(wep)
    if not wep then return false end
    if wep._issr_no_mag or wep._issr_mag_gone then return true end
    local empty = wep._pdti_gun_empty
    return empty ~= nil and empty[1] == true and empty[2] == true
end

-- What things cost. Adding something to the menu plan pays for it from your
-- spending cash, and taking it out pays it back. What a heist uses up (rounds
-- fired, deployables placed, throwables thrown) is paid again to restock the
-- plan (Plan.Spend). A magazine costs its case by size plus its rounds; loose
-- rounds cost their rounds. Weapons without sizes and bullets count as
-- standard. Items: PRICES.item, or a definition's own `price` (other mods).
Ammo.PRICES = {
    round = { standard = 30, hollow = 90, ap = 180,
        custom = 60, flechette = 120, slug = 150, tombstone = 150, dragon = 200, he = 250,
        explosive = 150, penetrator = 220 },
    magazine = { compact = 600, standard = 1000, extended = 2000, drum = 5000 },
    item = {
        first_aid_kit = 4000, doctor_bag = 35000, ammo_bag = 10000, bodybags_bag = 3000,
        bandage = 500, painkillers = 800, grenade = 2500, ecm_battery = 5000, armor_kit = 6000,
        trip_mine = 1500, ecm_jammer = 8000, spy_camera = 3000, sentry_gun = 15000,
        sentry_gun_silent = 15000, grenade_crate = 10000, armor_bag = 6000
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

-------------------------------------------------- bullet families

-- "rifle" (assault rifles, SMGs), "shell" (shotguns) or nil (the other
-- weapons, whose rounds have no kinds). info: from Identify or Plan.Info.
function Ammo.Family(info)
    return type(info) == "table" and info.family or nil
end

local function factory_tweak()
    return tweak_data and tweak_data.weapon and tweak_data.weapon.factory or nil
end

-- Does the game have this shell's ammo part?
function Ammo.ShellExists(id)
    local def = Ammo.BULLETS[id]
    if not def or def.family ~= "shell" then return id == "standard" end
    local factory = factory_tweak()
    local parts = factory and factory.parts
    if type(parts) ~= "table" then return true end
    if parts[def.part] then return true end
    for _, p in ipairs(def.parts or {}) do if parts[p] then return true end end
    return false
end

-- The shells a shotgun takes: the game's ammo parts its own part list has
-- (the same rule as attaching the ammo mod in the menu). Without the game's
-- weapon data (tests, an unknown gun): every shell the game has.
local accepted_cache = {}
function Ammo.ShellsAccepted(factory_id)
    local key = tostring(factory_id)
    if accepted_cache[key] then return accepted_cache[key] end
    local factory = factory_tweak()
    local weapon = factory_id and factory and factory[factory_id]
    local uses = type(weapon) == "table" and type(weapon.uses) == "table" and weapon.uses or nil
    local set = {}
    if uses then for _, p in ipairs(uses) do set[p] = true end end
    local out = {}
    for _, id in ipairs(Ammo.SHELL_ORDER) do
        local def = Ammo.BULLETS[id]
        local ok = id == "standard"
        if not ok and Ammo.ShellExists(id) then
            if not uses then
                ok = true
            else
                ok = set[def.part] == true
                for _, p in ipairs(def.parts or {}) do ok = ok or set[p] == true end
            end
        end
        if ok then out[#out + 1] = id end
    end
    if factory then accepted_cache[key] = out end
    return out
end

function Ammo.ResetShellCache()
    accepted_cache = {}
end

-- The bullets a weapon can use, in menu order. Weapons without kinds: none.
function Ammo.BulletsFor(info)
    local family = Ammo.Family(info)
    if family == "shell" then return Ammo.ShellsAccepted(info.factory_id) end
    if family == "rifle" then return Ammo.BULLET_ORDER end
    if family == "lmg" then return Ammo.LMG_ORDER end
    return {}
end

function Ammo.BulletAllowed(info, id)
    for _, b in ipairs(Ammo.BulletsFor(info)) do
        if b == id then return true end
    end
    return false
end

-- The bullet, or standard when the weapon cannot use it.
function Ammo.SafeBullet(info, id)
    id = Ammo.BulletId(id)
    if Ammo.BulletAllowed(info, id) then return id end
    return "standard"
end

-- A load without the rounds the weapon cannot use (a plan made for another
-- gun): they become standard rounds.
function Ammo.FilterLoad(info, load)
    -- ParseLoad of the same list with the bullets made safe, in one pass.
    local out = {}
    for _, part in ipairs(load or {}) do
        local b = Ammo.SafeBullet(info, part[1])
        local n = math.floor(tonumber(part[2]) or 0)
        if Ammo.BULLETS[b] and n > 0 then
            local last = out[#out]
            if last and last[1] == b then last[2] = last[2] + n
            else out[#out + 1] = { b, n } end
        end
    end
    return out
end

-- The name and the short tag of a bullet, as the weapon's family calls it
-- (standard shells are buckshot).
function Ammo.BulletName(id, family)
    id = Ammo.BulletId(id)
    if id == "standard" and family and Ammo.STANDARD_NAMES[family] then return Ammo.STANDARD_NAMES[family].name end
    return Ammo.BULLETS[id].name
end

function Ammo.BulletShort(id, family)
    id = Ammo.BulletId(id)
    if id == "standard" and family and Ammo.STANDARD_NAMES[family] then return Ammo.STANDARD_NAMES[family].short end
    return Ammo.BULLETS[id].short
end

-------------------------------------------------- ammunition categories

-- The categories the screen groups ammunition by: assault rifles and SMGs
-- (rifle bullets), shotguns (shells), LMGs (LMG rounds) and the
-- other weapons.
Ammo.CATEGORY_ORDER = { "rifle", "shell", "lmg", "other" }
Ammo.CATEGORY_NAMES = { rifle = "AR/SMG", shell = "Shotgun", lmg = "LMG", other = "Other" }
Ammo.CATEGORY_BULLETS = { rifle = Ammo.BULLET_ORDER, shell = Ammo.SHELL_ORDER, lmg = Ammo.LMG_ORDER, other = { "standard" } }

-- The category of a weapon (info from Identify or Plan.Info).
function Ammo.AmmoCategory(info)
    if type(info) ~= "table" then return nil end
    if info.family == "rifle" or info.family == "shell" or info.family == "lmg" then return info.family end
    if info.mag_class == "lmg" then return "lmg" end
    return "other"
end

-- The family of a supply's rounds, from the bullets they carry.
function Ammo.FamilyOfBullet(id)
    local def = Ammo.BULLETS[id]
    return def and def.family or nil
end

-------------------------------------------------- mixed loads

-- A magazine can hold several kinds of bullets: its load is a list of
-- { bullet, n } from the top (fired first) to the bottom. In the save it is
-- a string, "ap:10,hollow:20" (the save keeps only plain values).
-- Neighbours of the same kind are one run: the run is added to the list.
local function add_run(out, b, n)
    local last = out[#out]
    if last and last[1] == b then last[2] = last[2] + n
    else out[#out + 1] = { b, n } end
end

function Ammo.ParseLoad(value)
    local out = {}
    if type(value) == "table" then
        for _, part in ipairs(value) do
            local b, n = part[1] or part.bullet, math.floor(tonumber(part[2] or part.n) or 0)
            if Ammo.BULLETS[b] and n > 0 then add_run(out, b, n) end
        end
    elseif type(value) == "string" then
        for b, n in value:gmatch("(%a+):(%d+)") do
            n = math.floor(tonumber(n) or 0)
            if Ammo.BULLETS[b] and n > 0 then add_run(out, b, n) end
        end
    end
    return out
end

function Ammo.LoadString(load)
    local parts = {}
    if type(load) == "table" then
        -- ParseLoad's runs without the copy: the open run is written when
        -- the next kind starts.
        local cur_b, cur_n = nil, 0
        for _, part in ipairs(load) do
            local b, n = part[1] or part.bullet, math.floor(tonumber(part[2] or part.n) or 0)
            if Ammo.BULLETS[b] and n > 0 then
                if cur_b == b then cur_n = cur_n + n
                else
                    if cur_b then parts[#parts + 1] = cur_b .. ":" .. cur_n end
                    cur_b, cur_n = b, n
                end
            end
        end
        if cur_b then parts[#parts + 1] = cur_b .. ":" .. cur_n end
        return table.concat(parts, ",")
    end
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

-- Does this magazine (item data) know the kinds of its rounds?
function Ammo.HasLoad(data)
    return type(data) == "table" and (data.size ~= nil or data.load ~= nil or data.bullet ~= nil)
end

-- The load of a magazine item's data.
function Ammo.LoadOf(data)
    if type(data) ~= "table" then return {} end
    local rounds = math.max(0, math.floor(tonumber(data.rounds) or 0))
    local load = Ammo.ParseLoad(data.load)
    return (Ammo.FitLoad(load, rounds, data.bullet))
end

-- "30 AP", or "30 AP+" when there is more than one kind.
-- family: "shell" calls standard rounds buckshot (found from the load when
-- not given).
function Ammo.LoadTag(load, fallback, family)
    local top = Ammo.LoadTop(load) or fallback
    if not top then return "" end
    if not family then
        for _, part in ipairs(load or {}) do family = family or Ammo.FamilyOfBullet(part[1]) end
        family = family or Ammo.FamilyOfBullet(fallback)
    end
    return Ammo.BulletShort(top, family) .. ((#(load or {}) > 1) and "+" or "")
end

-- Rounds in a magazine of this size, from the weapon's base magazine.
function Ammo.SpecCapacity(base, size)
    local def = Ammo.MAG_SIZES[Ammo.SizeId(size)]
    return math.max(1, math.floor((tonumber(base) or 30) * def.mul + 0.5))
end

-- "S/AP"; a magazine without a size (shotguns) only its bullet.
function Ammo.SpecTag(size, bullet, family)
    family = family or Ammo.FamilyOfBullet(bullet)
    if not size then return Ammo.BulletShort(bullet, family) end
    return Ammo.MAG_SIZES[Ammo.SizeId(size)].short .. "/" .. Ammo.BulletShort(bullet, family)
end

function Ammo.IsTypedClass(class)
    return class ~= nil and Ammo.TYPED_CLASSES[class] == true
end

-- An assault rifle or SMG fed from magazines (sizes and rifle bullets).
function Ammo.Typed(wep)
    if not wep or Ammo.IsLooseFed(wep) then return false end
    return Ammo.IsTypedClass((Ammo.SizeClass(wep)))
end

-- What Identify adds for a shotgun: the rounds have kinds (typed), but the
-- magazines keep their game sizes (not sized).
local function add_shell(info, wep)
    info.typed = true
    info.family = "shell"
    info.shell = true
    info.factory_id = wep._factory_id
    return info
end

-- What Identify adds for an LMG: the rounds have kinds (LMG rounds), the
-- magazines (box, belt) keep their game sizes.
local function add_lmg(info)
    info.typed = true
    info.family = "lmg"
    return info
end

-- Everything the ammunition code needs to know about a weapon.
function Ammo.Identify(wep)
    -- (The armory's stand-in when you hold no weapon: not a gun of yours.)
    if not wep or wep._pdti_unarmed then return nil end
    local caliber = weapon_label(wep)
    if not caliber then return nil end
    if Ammo.IsLooseFed(wep) then
        local name = wep._name_id
        if not name then return nil end
        local info = {
            key = tostring(caliber) .. "|" .. tostring(name) .. ":loose",
            pid = tostring(name),
            caliber = caliber,
            capacity = clip_size(wep) or 1,
            loose_fed = true,
            slot = Ammo.SlotOf(wep),
            weapon = wep._name_id,
            mag_class = (Ammo.SizeClass(wep))
        }
        if info.mag_class == "shotgun" then add_shell(info, wep) end
        return info
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
            weapon = wep._name_id,
            mag_class = class,
            akimbo = akimbo or nil,
            typed = true,
            sized = true,
            family = "rifle"
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
    local info = {
        key = tostring(caliber) .. "|" .. tostring(pid),
        pid = pid,
        caliber = caliber,
        capacity = capacity,
        slot = Ammo.SlotOf(wep),
        weapon = wep._name_id,
        mag_class = class,
        akimbo = akimbo or nil
    }
    if class == "shotgun" then add_shell(info, wep) end
    if class == "lmg" then add_lmg(info) end
    return info
end

-- The second gun of an akimbo pair: the game marks it with its parent
-- weapon; else it is the _second_gun of the weapon in hand.
local function second_gun_check(wep)
    local main = Ammo.EquippedBase()
    local second = main and main ~= wep and main._second_gun
    return second ~= nil and second ~= false and alive(second) and second:base() == wep
end
function Ammo.IsSecondGun(wep)
    if wep.parent_weapon ~= nil or wep._parent_weapon ~= nil or wep.SKIP_AMMO then return true end
    local ok, result = pcall(second_gun_check, wep)
    return ok and result == true
end

-- Is the ammunition system running? Not when it is switched off, and not in
-- the safehouse: there the weapons are the game's own, so the shooting
-- range uses up nothing of what you bring.
function Ammo.On()
    return Ammo.settings.enabled == true and not PDTI.InSafehouse()
end

-- A weapon's short name for the inventory's cells ("AMCAR", "2xChima"):
-- ammunition is labelled by its weapon, not by the slot.
local tag_cache = {}
function Ammo.WeaponTag(weapon_id)
    if weapon_id == nil then return nil end
    local key = tostring(weapon_id)
    if tag_cache[key] then return tag_cache[key] end
    local name = nil
    pcall(function()
        local t = tweak_data.weapon[weapon_id]
        name = managers.localization:text(t.name_id)
    end)
    if type(name) ~= "string" or name == "" or name:find("ERROR") then name = key end
    local rest = name:match("^[Aa]kimbo%s+(.+)$")
    local word = (rest or name):match("^(%S+)") or key
    local tag = rest and ("2x" .. word:sub(1, 5)) or word:sub(1, 7)
    tag_cache[key] = tag
    return tag
end

function Ammo.SkipReason(wep)
    if not Ammo.On() then return Ammo.settings.enabled and "the safehouse" or "mod disabled" end
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
local GRID_RANK = { gun_primary = 0, gun_secondary = 0, pouch = 1, pockets = 1, rig = 2, rig_2 = 3, rig_3 = 4 }
Ammo.GRID_RANK = GRID_RANK
Ammo.GUN_SLOTS = { primary = "gun_primary", secondary = "gun_secondary" }
local GUN_CONTAINER = { gun_primary = true, gun_secondary = true }
Ammo.IsGunSlot = function(name) return GUN_CONTAINER[name] == true end

-- The magazine items of one supply that are not in the gun.
local function magazine_items(key)
    return PDTI.FindItems(function(container, item)
        return item.item_id == Ammo.MAGAZINE_ITEM
            and type(item.data) == "table" and item.data.queue_key == key and not item.data.in_gun
    end)
end

-- Magazine items of one supply that are to hand, in grid order. The
-- magazine in the gun (in_gun, in the weapon's slot) is not one of them.
function Ammo.Magazines(key)
    local out = {}
    for _, entry in ipairs(magazine_items(key)) do
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
                load = Ammo.HasLoad(entry.item.data) and Ammo.LoadOf(entry.item.data) or nil,
                x = tonumber(entry.item.x) or 0,
                y = tonumber(entry.item.y) or 0
            }
        end
    end
    -- The fullest first and the empty ones last (by how full they are, so a
    -- full compact magazine comes before a half-full drum); equally full ones
    -- (two full ones) in grid order: the pockets first, then the rig, each
    -- read from the top left.
    table.sort(out, function(a, b)
        local fa = a.capacity > 0 and a.rounds / a.capacity or 0
        local fb = b.capacity > 0 and b.rounds / b.capacity or 0
        if math.abs(fa - fb) > 1e-9 then return fa > fb end
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
    for _, entry in ipairs(magazine_items(key)) do
        out[#out + 1] = {
            container = entry.container,
            instance_id = entry.item.instance_id,
            rounds = math.max(0, math.floor(tonumber(entry.item.data.rounds) or 0)),
            capacity = math.max(0, math.floor(tonumber(entry.item.data.capacity) or 0)),
            size = entry.item.data.size,
            bullet = entry.item.data.bullet,
            load = Ammo.HasLoad(entry.item.data) and Ammo.LoadOf(entry.item.data) or nil
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
    -- The ammo pouch first (Fully Loaded): its rounds are used first.
    table.sort(out, function(a, b)
        local pa, pb = a.container == "pouch", b.container == "pouch"
        if pa ~= pb then return pa end
        return a.instance_id < b.instance_id
    end)
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
        wtag = info and Ammo.WeaponTag(info.weapon) or nil,
        -- A round weighs by its weapon type.
        mag_class = info and info.mag_class or nil,
        bullet = info and info.typed and Ammo.SafeBullet(info, bullet) or nil,
        family = info and info.family or nil
    }
end

-- Puts as many of `remaining` rounds as fit into a loose stack; returns the
-- rounds still to place.
local function top_up_stack(entry, remaining)
    local room = MAX_STACK - entry.rounds
    if room <= 0 then return remaining end
    local take = math.min(room, remaining)
    local ok = PDTI.EditItems({ set_amount = {
        { container = entry.container, instance_id = entry.instance_id, amount = entry.rounds + take }
    } })
    if ok then return remaining - take end
    return remaining
end

-- Adds rounds to the loose ammunition of a supply. The rounds are real
-- inventory items, so they take up space and weight like anything else.
function Ammo.AddLooseKey(key, rounds, info, bullet)
    rounds = math.max(0, math.floor(tonumber(rounds) or 0))
    if rounds <= 0 then return true end

    local data = Ammo.LooseData(key, info, bullet)

    local remaining = rounds
    -- The ammo pouch (Fully Loaded) is filled first: its stacks, then new
    -- stacks in it.
    for _, entry in ipairs(Ammo.LooseStacks(key, data.bullet)) do
        if remaining <= 0 or entry.container ~= "pouch" then break end
        remaining = top_up_stack(entry, remaining)
    end
    while remaining > 0 do
        local take = math.min(MAX_STACK, remaining)
        if not PDTI.AddItemAuto("pouch", Ammo.LOOSE_ITEM, take, data) then break end
        remaining = remaining - take
    end
    -- Top up a stack that is not full yet.
    for _, entry in ipairs(Ammo.LooseStacks(key, data.bullet)) do
        if remaining <= 0 then break end
        remaining = top_up_stack(entry, remaining)
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
        -- Assault rifles and SMGs: the magazine's size sets its capacity.
        -- Shotguns keep the game's magazine.
        if info.sized then
            size = Ammo.SizeId(spec and spec.size)
            capacity = Ammo.SpecCapacity(info.capacity, size)
        end
        rounds = math.min(rounds or 0, capacity)
        -- The bullets it holds, top first; rounds without a known bullet
        -- are of the magazine's own kind.
        local fill = Ammo.SafeBullet(info, spec and spec.bullet)
        local list = Ammo.FitLoad(Ammo.FilterLoad(info, Ammo.ParseLoad(spec and spec.load)), rounds, fill)
        bullet = Ammo.LoadTop(list) or fill
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
        wtag = info and Ammo.WeaponTag(info.weapon) or nil,
        -- The size of the magazine follows its weapon type and capacity.
        mag_class = info and info.mag_class or nil,
        akimbo = info and info.akimbo or nil,
        family = info and info.family or nil
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

-- The magazine a reload would load: the one chosen with the mouse wheel, or
-- else the first in the rig or pockets (grid order) that has rounds. An
-- empty magazine is only loaded when the gun has no magazine at all.
function Ammo.NextMagazine(wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed then return nil end
    local list = Ammo.Magazines(info.key)
    local any = wep._issr_mag_gone or wep._issr_no_mag
    local chosen = Ammo.selection[info.key]
    if chosen and chosen ~= "gun" then
        for _, entry in ipairs(list) do
            if entry.instance_id == chosen and (entry.rounds > 0 or any) then return entry end
        end
    end
    for _, entry in ipairs(list) do
        if entry.rounds > 0 or any then return entry end
    end
    return nil
end

------------------------------------------------- choosing the next magazine

-- The mouse wheel chooses what the next reload does, per supply: a magazine
-- you carry (its instance id) or "gun": the magazine in the gun comes out
-- and the gun is left without one. nil: the first magazine with rounds.
Ammo.selection = Ammo.selection or {}

-- Does the gun have a magazine in it (either gun, for akimbo)?
function Ammo.GunLoaded(wep)
    if wep._issr_no_mag or wep._issr_mag_gone then return false end
    local info = Ammo.Identify(wep)
    if not info then return false end
    for g = 1, (info.akimbo and 2 or 1) do
        if Ammo.GunHasMagazine(wep, g) then return true end
    end
    return false
end

-- What the wheel goes through: the magazine in the gun ("gun") first, then
-- the magazines to hand that a reload could load, in grid order.
function Ammo.ChoiceList(wep)
    local info = Ammo.Identify(wep)
    if not info or info.loose_fed or Ammo.NoReload(wep) then return {} end
    local out = {}
    local loaded = Ammo.GunLoaded(wep)
    if loaded then out[#out + 1] = "gun" end
    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        if entry.rounds > 0 or not loaded then out[#out + 1] = entry.instance_id end
    end
    return out
end

-- What the next reload does: "gun" (take the magazine out), the instance id
-- of the magazine it loads, or nil (nothing to load).
function Ammo.CurrentChoice(wep)
    local info = Ammo.Identify(wep)
    if not info then return nil end
    if Ammo.selection[info.key] == "gun" then
        if Ammo.GunLoaded(wep) then return "gun" end
        Ammo.selection[info.key] = nil
    end
    local entry = Ammo.NextMagazine(wep)
    return entry and entry.instance_id or nil
end

-- The wheel: dir 1 is the next choice, -1 the one before (it goes round).
function Ammo.CycleChoice(wep, dir)
    local info = Ammo.Identify(wep)
    if not info then return nil end
    local list = Ammo.ChoiceList(wep)
    if #list == 0 then return nil end
    local now = Ammo.CurrentChoice(wep)
    local at = nil
    for i, id in ipairs(list) do if id == now then at = i end end
    -- Nothing chosen and nothing to load: the wheel starts at the first.
    if not at then at = dir > 0 and 0 or #list + 1 end
    local i = ((at - 1 + (dir > 0 and 1 or -1)) % #list) + 1
    Ammo.selection[info.key] = list[i]
    Ammo.MarkPanelDirty()
    return list[i]
end

-------------------------------------------- the next shell (shotgun tubes)

-- A shotgun loaded shell by shell has no magazines: the wheel chooses which
-- kind of shell the reload loads next (Ammo.selection[key] is its id). The
-- kinds offered are the ones you carry loose rounds of.
function Ammo.ShellChoices(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.loose_fed or info.family ~= "shell" then return {} end
    local out = {}
    for _, id in ipairs(Ammo.BulletsFor(info)) do
        if Ammo.LooseOfKey(info.key, id) > 0 then out[#out + 1] = id end
    end
    return out
end

-- The shell the next reload loads: the chosen one while you carry it, else
-- the first kind you carry (menu order). nil: no shells left.
function Ammo.NextShell(wep)
    local info = wep and Ammo.Identify(wep)
    if not info then return nil end
    local list = Ammo.ShellChoices(wep)
    local chosen = Ammo.selection[info.key]
    for _, id in ipairs(list) do
        if id == chosen then return id end
    end
    return list[1]
end

-- The wheel on a shotgun tube: the next kind of shell (it goes round).
function Ammo.CycleShell(wep, dir)
    local info = wep and Ammo.Identify(wep)
    if not info then return nil end
    local list = Ammo.ShellChoices(wep)
    if #list == 0 then return nil end
    local now = Ammo.NextShell(wep)
    local at = 1
    for i, id in ipairs(list) do if id == now then at = i end end
    local i = ((at - 1 + (dir > 0 and 1 or -1)) % #list) + 1
    Ammo.selection[info.key] = list[i]
    Ammo.MarkPanelDirty()
    return list[i]
end

-- Loads shells into a tube: the clip grows by up to n, taken from the loose
-- shells of the chosen kind (then the other kinds). Each goes on top.
-- Returns the shells loaded and the kinds used ({ { id, n }, ... }).
function Ammo.LoadShells(wep, before, n)
    local info = wep and Ammo.Identify(wep)
    if not info then return 0, {} end
    local clip, used = before, {}
    while n > 0 do
        local id = Ammo.NextShell(wep)
        if not id then break end
        local got = Ammo.ConsumeLooseKey(info.key, n, id)
        if got <= 0 then break end
        clip = clip + got
        n = n - got
        wep:set_ammo_remaining_in_clip(clip)
        Ammo.PushLoaded(wep, id, got)
        used[#used + 1] = { id, got }
    end
    wep:set_ammo_remaining_in_clip(clip)
    return clip - before, used
end

-- Taking the magazine out of the gun ("gun" chosen): is there a place for
-- it (or both, akimbo) in the rig, the pockets or the backpack? Without a
-- place: nil and why ("none": no magazine item in the gun; "room").
function Ammo.UnloadPlaces(wep)
    local info = Ammo.Identify(wep)
    local c = info and Ammo.GUN_SLOTS[info.slot]
    if not c then return nil end
    local items = wep._pdti_gun_items or {}
    local places, taken = {}, {}
    for g = 1, (info.akimbo and 2 or 1) do
        local id = items[g]
        local item = id and Ammo.GunHasMagazine(wep, g) and PDTI.FindItem(c, id)
        if item then
            local ref = { item_id = item.item_id, data = item.data }
            local found = nil
            for _, name in ipairs(Ammo.STORAGE) do
                local x, y, rotated = PDTI.FindFreeSpace(name, ref, true)
                -- Two magazines must not be given the same place.
                if x and not taken[name .. ":" .. x .. ":" .. y] then
                    found = { container = name, x = x, y = y, rotated = rotated }
                    taken[name .. ":" .. x .. ":" .. y] = true
                    break
                end
            end
            if not found then return nil, "room" end
            places[#places + 1] = { from = c, id = id, g = g, to = found }
        end
    end
    if #places == 0 then return nil, "none" end
    return places
end

-- The magazine comes out of the gun into the inventory, as if it was
-- dragged out of the weapon's slot. Returns true when it did.
function Ammo.Unload(wep)
    local places = Ammo.UnloadPlaces(wep)
    if not places then return false end
    local moved = false
    for _, p in ipairs(places) do
        local ok = PDTI.MoveItem(p.from, p.id, p.to.container, p.to.x, p.to.y, p.to.rotated)
        if not ok then
            -- The place taken by the first magazine: any other one.
            local x, y, rotated = PDTI.FindFreeSpace(p.to.container,
                { item_id = Ammo.MAGAZINE_ITEM, data = (PDTI.FindItem(p.from, p.id) or {}).data }, true)
            if x then ok = PDTI.MoveItem(p.from, p.id, p.to.container, x, y, rotated) end
        end
        moved = moved or ok
    end
    -- The weapon's slot sees its magazine gone: the gun has none now.
    Ammo.SyncGunSlot(wep)
    local info = Ammo.Identify(wep)
    if info then Ammo.selection[info.key] = nil end
    Ammo.SyncTotal(wep)
    Ammo.MarkPanelDirty()
    return moved
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
    -- The chosen magazine is in the gun now: the next choice starts again.
    if Ammo.selection[info.key] == entry.instance_id then Ammo.selection[info.key] = nil end
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

-- The weapon's normal ammunition: the magazine in the gun, the chamber and
-- the game's number of magazines, or what you chose to bring if that is more.
-- Ammo bags give a share of this.
function Ammo.BaseTotal(wep)
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
    local max = in_gun + Ammo.ChamberOf(wep) + amount * info.capacity
    -- What you chose to bring always fits.
    local planned = Ammo.plan_max and Ammo.plan_max[info.key]
    if planned and planned > max then max = planned end
    return max
end

-- The game's ammunition maximum. What you carry is limited by the room in
-- your inventory, not by a number: the maximum is the normal ammunition, or
-- what you carry when that is more.
function Ammo.MaxTotal(wep)
    local base = Ammo.BaseTotal(wep)
    if not base then return nil end
    local ok, total = pcall(wep.get_ammo_total, wep)
    if ok and type(total) == "number" and total > base then return total end
    return base
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

-- How many spare magazines an ammo bag fills you up to: the weapon's normal
-- number (one more when the gun has no magazine). A bag refills you, it does
-- not fill your backpack with magazines.
function Ammo.MaxMagCount(wep)
    local info = Ammo.Identify(wep)
    if not info then return 0 end
    local count = Ammo.MagAmount(info, wep._name_id)
    if wep._issr_mag_gone then count = count + (info.akimbo and 2 or 1) end
    return count
end

---------------------------------------------------- the loaded magazine

-- A magazine's spec: { size, bullet, capacity, load }. The load is kept as
-- it was when the magazine went in; shots take rounds off its top.
-- unsized (shotguns): no size, the capacity is the base.
local function norm_spec(spec, base, unsized)
    spec = type(spec) == "table" and spec or {}
    local size = not unsized and Ammo.SizeId(spec.size) or nil
    local load = spec.load and Ammo.ParseLoad(spec.load) or nil
    return {
        size = size, bullet = Ammo.BulletId(spec.bullet or Ammo.LoadTop(load)),
        capacity = unsized and math.max(1, math.floor(tonumber(base) or 1)) or Ammo.SpecCapacity(base, size),
        load = load
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

-- The rounds of the magazine in the gun. A gun loaded round by round
-- (a tube) has no magazine: all its rounds count.
local function gun_rounds(wep, info)
    local ok, clip = pcall(wep.get_ammo_remaining_in_clip, wep)
    if info and info.loose_fed then return math.max(0, ok and tonumber(clip) or 0) end
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
        local unsized = info and not info.sized
        specs = { norm_spec(one, base, unsized), norm_spec(two, base, unsized) }
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
        spec = norm_spec(spec, info.capacity, not info.sized)
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
    return spec_view(stored_spec(wep, info), gun_rounds(wep, info))
end

-- Puts a magazine into the gun: spec = { size, bullet, load } (a magazine
-- that was taken out of the inventory). Akimbo: specs for both guns, or one
-- for both.
function Ammo.SetLoaded(wep, spec, spec2)
    local info = Ammo.Identify(wep)
    if not info or not info.typed then return end
    wep._pdti_shot_bullet = nil
    local unsized = not info.sized
    if info.akimbo then
        wep._pdti_pair_specs = { norm_spec(spec, info.capacity, unsized), norm_spec(spec2 or spec, info.capacity, unsized) }
    end
    wep._pdti_loaded = norm_spec(spec, info.capacity, unsized)
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
        local rounds = gun_rounds(wep, info)
        spec.load = spec.load or Ammo.FitLoad({}, rounds, spec.bullet)
        local _, popped = Ammo.FitLoad(spec.load, rounds, spec.bullet)
        fired = popped
    end
    fired = fired or Ammo.CurrentBullet(wep) or "standard"
    wep._pdti_shot_bullet = fired
    return fired
end

-- A gun loaded round by round (a shotgun's tube): rounds of a bullet went
-- in. They go on top, so the last shell loaded is fired first. Call after
-- the clip grew by n.
function Ammo.PushLoaded(wep, bullet, n)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed or not n or n <= 0 then return end
    local spec = stored_spec(wep, info)
    local rounds = gun_rounds(wep, info)
    local load = spec.load or Ammo.FitLoad({}, math.max(0, rounds - n), spec.bullet)
    -- The load as it was before these rounds went in.
    Ammo.FitLoad(load, math.max(0, rounds - n), spec.bullet)
    Ammo.LoadPush(load, Ammo.SafeBullet(info, bullet), n)
    spec.load = load
    spec.bullet = Ammo.LoadTop(load) or spec.bullet
    wep._pdti_shot_bullet = nil
end

-- The bullet of the shot that is being worked out (armour, critical hits).
function Ammo.FiredBullet(wep)
    return wep and (wep._pdti_shot_bullet or Ammo.CurrentBullet(wep)) or nil
end

-- The bullet's effect on the weapon's own flags. The weapon's values are
-- kept once and come back with standard bullets.
-- The game's explosive bullet (InstantExplosiveBulletBase, the one HE shells
-- and the explosive-bullets skill use) with a smaller blast: range in cm.
-- nil before the game has the class (or in tests without it).
Ammo.explosive_classes = Ammo.explosive_classes or {}

-- The blast of an explosive round, in cm; a skill can widen it
-- (Ammo.blast_mul, a function returning a multiplier).
function Ammo.BlastRange(def)
    local range = tonumber(def and def.blast_range) or 60
    local f = Ammo.blast_mul
    if type(f) == "function" then
        local ok, m = pcall(f)
        if ok and type(m) == "number" and m > 0 then range = range * m end
    end
    return math.floor(range + 0.5)
end
function Ammo.ExplosiveClass(range)
    range = tonumber(range) or 60
    local cached = Ammo.explosive_classes[range]
    if cached then return cached end
    local base = rawget(_G, "InstantExplosiveBulletBase")
    local make = rawget(_G, "class")
    if type(base) ~= "table" or type(make) ~= "function" then return nil end
    local ok, cls = pcall(make, base)
    if not ok or type(cls) ~= "table" then return nil end
    cls.RANGE = range
    local params = {}
    for k, v in pairs(base.EFFECT_PARAMS or {}) do params[k] = v end
    params.feedback_range = range
    params.camera_shake_max_mul = 0.5
    cls.EFFECT_PARAMS = params
    -- The blast of this round: while the game works out its damage,
    -- Ammo.he_blast names the weapon, so the damage hooks know the blast is
    -- an HE round's (critical hits, ammo_hooks.lua).
    cls.on_collision_server = function(self, position, normal, damage, user_unit, weapon_unit, ...)
        local fn = base.on_collision_server
        if type(fn) ~= "function" then return nil end
        local before = Ammo.he_blast
        Ammo.he_blast = { weapon = weapon_unit, user = user_unit }
        local result = { pcall(fn, self, position, normal, damage, user_unit, weapon_unit, ...) }
        Ammo.he_blast = before
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, table.maxn(result))
    end
    Ammo.explosive_classes[range] = cls
    return cls
end

function Ammo.ApplyBullet(wep, bullet)
    if not wep then return end
    local orig = wep._pdti_orig_flags
    if not orig then
        orig = {
            enemy = wep._can_shoot_through_enemy,
            shield = wep._can_shoot_through_shield,
            ap = wep._use_armor_piercing,
            wall = wep._can_shoot_through_wall,
            class = wep._bullet_class,
            slotmask = wep._bullet_slotmask,
            blank = wep._blank_slotmask
        }
        wep._pdti_orig_flags = orig
    end
    local def = Ammo.BULLETS[Ammo.BulletId(bullet)]
    if def.wall ~= nil then
        wep._can_shoot_through_wall = def.wall
    else
        wep._can_shoot_through_wall = orig.wall
    end
    -- Explosive rounds: the game's explosive bullet with this round's blast.
    local cls = def.explosive and Ammo.ExplosiveClass(Ammo.BlastRange(def)) or nil
    if cls then
        if wep._bullet_class ~= cls then
            wep._bullet_class = cls
            local ok, mask = pcall(cls.bullet_slotmask, cls)
            if ok and mask then wep._bullet_slotmask = mask end
            local ok2, blank = pcall(cls.blank_slotmask, cls)
            if ok2 and blank then wep._blank_slotmask = blank end
        end
    elseif wep._bullet_class ~= orig.class then
        wep._bullet_class = orig.class
        wep._bullet_slotmask = orig.slotmask
        wep._blank_slotmask = orig.blank
    end
    if def.through == nil then
        wep._can_shoot_through_enemy = orig.enemy
        wep._can_shoot_through_shield = orig.shield
    else
        wep._can_shoot_through_enemy = def.through
        wep._can_shoot_through_shield = def.through
    end
    wep._use_armor_piercing = orig.ap
    wep._pdti_bullet = Ammo.BulletId(bullet)
end

-- The gun takes the loaded magazine's size: the clip's maximum is its
-- capacity (both magazines for akimbo), and the bullets set the flags.
function Ammo.ApplyLoaded(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed then return end
    if info.family == "shell" then
        -- Shotguns keep the game's magazine; the next shell sets the gun.
        if PDTI.Shells then PDTI.Shells.Apply(wep, Ammo.CurrentBullet(wep)) end
        return
    end
    -- LMGs keep the game's magazine; only AR/SMG magazines have sizes.
    if info.sized then
        local max
        if info.akimbo then
            local specs = Ammo.PairSpecs(wep)
            max = specs[1].capacity + specs[2].capacity
        else
            max = stored_spec(wep, info).capacity
        end
        if wep.set_ammo_max_per_clip then pcall(wep.set_ammo_max_per_clip, wep, max) end
    end
    Ammo.ApplyBullet(wep, Ammo.CurrentBullet(wep))
end

-- The reload speed of the magazine a reload loads: bigger is slower.
function Ammo.SizeReloadFactor(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or not info.sized then return 1 end
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
        -- Ammo.LoadedSpec(wep) for this info (no second Identify each frame).
        if info.typed then spec = spec_view(stored_spec(wep, info), gun_rounds(wep, info)) end
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
    local cap = info.sized and Ammo.SpecCapacity(info.capacity, data.size) or info.capacity
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

-- The magazines left in a weapon's slot by a gun no longer in your hands
-- (put away, swapped for a picked-up one, left in custody) went with that
-- gun: they come out of the slot. keep: the item ids of the gun in hand.
-- (The plan's magazine for the slot is never marked in the gun.)
function Ammo.DropGunLeftovers(c, keep)
    local mine, n = {}, 0
    for _, id in pairs(keep or {}) do mine[id] = true end
    for _, it in ipairs((PDTI.GetContainerInfo(c) or { items = {} }).items) do
        local d = it.data
        if it.item_id == Ammo.MAGAZINE_ITEM and type(d) == "table" and d.in_gun == true
            and not mine[it.instance_id] then
            if PDTI.RemoveItem(c, it.instance_id) then n = n + 1 end
        end
    end
    return n
end

-- The magazine loaded in a weapon goes with the weapon (into the backpack,
-- and back into a slot). A weapon item keeps it in flat fields: gun_n
-- magazines (two for akimbo guns), gun1_rounds / _size / _bullet / _load
-- (and gun2_), their weight gun_weight; gun_set once the weapon's magazine
-- was settled (a weapon you emptied stays empty). In a heist also
-- gun_chamber, gun_clip for a weapon loaded round by round, and gun_in
-- while all of it is in the gun in your hands.

local function nonempty(v)
    if v == nil or v == "" then return nil end
    return v
end

-- The magazines a weapon item holds: { rounds, size, bullet, load } each.
function Ammo.StoredMagazines(d)
    local out = {}
    if type(d) ~= "table" then return out end
    for g = 1, math.min(2, math.floor(tonumber(d.gun_n) or 0)) do
        local p = "gun" .. g .. "_"
        out[#out + 1] = { rounds = math.max(0, math.floor(tonumber(d[p .. "rounds"]) or 0)),
            size = nonempty(d[p .. "size"]), bullet = nonempty(d[p .. "bullet"]), load = nonempty(d[p .. "load"]) }
    end
    return out
end

-- The weapon item's fields for these magazines (magazine item data).
function Ammo.GunFields(list)
    local f = { gun_set = 1, gun_n = #list, gun_weight = 0, gun_in = 0 }
    for g, m in ipairs(list) do
        local p = "gun" .. g .. "_"
        f[p .. "rounds"] = math.max(0, math.floor(tonumber(m.rounds) or 0))
        f[p .. "size"] = m.size or ""
        f[p .. "bullet"] = m.bullet or ""
        f[p .. "load"] = m.load or ""
        f.gun_weight = f.gun_weight + PDTI.ItemWeight({ item_id = Ammo.MAGAZINE_ITEM, amount = 1, data = m })
    end
    return f
end

-- In a heist: what is in the gun now, as a weapon item keeps it. Nil for a
-- weapon the ammunition system leaves alone.
function Ammo.GunState(wep)
    local info = wep and Ammo.Identify(wep)
    if not info or Ammo.SkipWeapon(wep) or Ammo.NoReload(wep) then return nil end
    local ok, clip = pcall(wep.get_ammo_remaining_in_clip, wep)
    clip = math.max(0, math.floor(ok and tonumber(clip) or 0))
    if info.loose_fed then
        local f = Ammo.GunFields({})
        f.gun_clip = clip
        if info.typed then f.gun1_bullet = Ammo.CurrentBullet(wep) or "" end
        return f
    end
    local list = {}
    for g = 1, gun_count(info) do
        if Ammo.GunHasMagazine(wep, g) then list[#list + 1] = gun_mag_data(wep, info, g) end
    end
    local f = Ammo.GunFields(list)
    local in_mags = 0
    for _, m in ipairs(list) do in_mags = in_mags + (tonumber(m.rounds) or 0) end
    f.gun_chamber = math.max(0, math.min(Ammo.ChamberOf(wep), clip - in_mags))
    return f
end

-- The gun without a magazine (what is in the chamber stays).
function Ammo.EmptyGun(wep, chamber)
    local info = Ammo.Identify(wep)
    if not info then return end
    local keep = math.max(0, math.min(Ammo.ChamberOf(wep), math.floor(tonumber(chamber) or 0)))
    if info.akimbo then wep._pdti_pair = { 0, 0 } end
    wep:set_ammo_remaining_in_clip(keep)
    wep._issr_no_mag = true
    wep._issr_mag_gone = true
    wep._issr_mag_installed = { rounds = 0 }
end

-- In a heist: a weapon put into your hands gets what its item holds (d: the
-- weapon item's data). A weapon whose magazine was never settled keeps the
-- game's full one.
function Ammo.LoadGun(wep, d)
    if not wep or type(d) ~= "table" or d.gun_set ~= 1 or d.gun_in == 1 then return false end
    local info = Ammo.Identify(wep)
    if not info or Ammo.SkipWeapon(wep) or Ammo.NoReload(wep) then return false end
    -- The ammunition chosen for this weapon becomes its own first.
    Ammo.EnsureSupply(wep)
    if info.loose_fed then
        local clip = tonumber(d.gun_clip)
        if not clip then return false end
        local bullet = nonempty(d.gun1_bullet)
        if info.typed and bullet then
            Ammo.SetLoaded(wep, { bullet = bullet })
            Ammo.ApplyLoaded(wep)
        end
        wep:set_ammo_remaining_in_clip(math.max(0, math.floor(clip)))
        Ammo.SyncTotal(wep)
        Ammo.MarkPanelDirty()
        return true
    end
    wep._pdti_gun_items = wep._pdti_gun_items or {}
    Ammo.ClearGunItems(wep)
    local c = gun_container(info)
    -- (The gun this one replaced left its magazine in the box: it went with
    -- that gun.)
    if c then Ammo.DropGunLeftovers(c) end
    Ammo.EmptyGun(wep, d.gun_chamber)
    -- (One magazine per gun: the box takes no more.)
    for g, m in ipairs(Ammo.StoredMagazines(d)) do
        local spec = info.typed and { size = m.size, bullet = m.bullet, load = m.load } or nil
        local data = magazine_data(info.key, m.rounds, info, spec)
        local ok, item = PDTI.AddItem(c, Ammo.MAGAZINE_ITEM, g - 1, 0, false, 1, data)
        if not ok then ok, item = PDTI.AddItemAuto(c, Ammo.MAGAZINE_ITEM, 1, data, false) end
        if ok and type(item) == "table" then put_in(wep, info, g, item, c) end
    end
    Ammo.SyncTotal(wep)
    Ammo.MarkPanelDirty()
    return true
end

-- Keeps the weapon's slot and the gun in step (every frame in a heist, and
-- after every action in the inventory screen).
function Ammo.SyncGunSlot(wep)
    if not PDTI.session_only or not wep then return end
    local info = Ammo.Identify(wep)
    local c = gun_container(info)
    if not c then return end
    wep._pdti_gun_items = wep._pdti_gun_items or {}
    local items = wep._pdti_gun_items
    Ammo.DropGunLeftovers(c, items)
    if info.loose_fed or Ammo.NoReload(wep) or Ammo.SkipWeapon(wep) then return end
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
    local own = Ammo.SafeBullet(info, Ammo.LoadTop(entry.load) or entry.bullet)
    if has(own) then return own end
    for _, id in ipairs(Ammo.BulletsFor(info)) do
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
        for _, id in ipairs(Ammo.BulletsFor(info)) do
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
    local size = info.sized and Ammo.SizeId(p.pick_size) or nil
    local cap = info.sized and Ammo.SpecCapacity(info.capacity, size) or info.capacity
    local load = p.pick_load and Ammo.FilterLoad(info, Ammo.ParseLoad(p.pick_load)) or {}
    -- A smaller magazine: the bottom rounds do not fit.
    local over = Ammo.LoadTotal(load) - cap
    while over > 0 and load[#load] do
        local take = math.min(over, load[#load][2])
        load[#load][2] = load[#load][2] - take
        over = over - take
        if load[#load][2] <= 0 then table.remove(load) end
    end
    -- Room left: the chosen bullets at the bottom.
    Ammo.FitLoad(load, cap, Ammo.SafeBullet(info, p.pick_bullet))
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
    local max = math.max(1, tonumber(Ammo.BaseTotal(wep)) or 1)
    local budget = math.floor((tonumber(available) or 1) * max + 1e-6)
    local given = 0

    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        if given >= budget then break end
        local room = math.max(0, Ammo.EntryCapacity(info, entry) - entry.rounds)
        local take = math.min(room, budget - given)
        if take > 0 then
            if info.typed then
                local load = entry.load or Ammo.FitLoad({}, entry.rounds, entry.bullet)
                local own = Ammo.SafeBullet(info, Ammo.LoadTop(load) or entry.bullet)
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
    -- New magazines up to the normal number, as long as the bag has rounds.
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

------------------------------------- loading a stack into one magazine

-- Loose rounds dropped onto a magazine in the inventory screen are loaded
-- into it: in a heist one round at a time (round_interval each) until the
-- magazine is full, the stack runs out, or you do something (shoot, reload,
-- aim, ...: Ammo.StopLoad); in the menu all at once.

local function find_by_id(instance_id)
    local found = PDTI.FindItems(function(_, item) return item.instance_id == instance_id end)
    local entry = found and found[1]
    if not entry then return nil end
    return entry.container, entry.item
end

-- Can this loose stack go into this magazine? Returns true, or false and why.
function Ammo.CanLoadInto(loose, mag)
    if type(loose) ~= "table" or type(mag) ~= "table" then return false, "nothing to load" end
    if loose.item_id ~= Ammo.LOOSE_ITEM or mag.item_id ~= Ammo.MAGAZINE_ITEM then return false, "not rounds and a magazine" end
    local ld, md = loose.data or {}, mag.data or {}
    if not ld.queue_key or ld.queue_key ~= md.queue_key then return false, "these rounds do not fit this magazine" end
    if md.in_gun then return false, "the magazine is in the gun" end
    if (tonumber(loose.amount) or 1) < 1 then return false, "the stack is empty" end
    local rounds, cap = math.floor(tonumber(md.rounds) or 0), math.floor(tonumber(md.capacity) or 0)
    if cap > 0 and rounds >= cap then return false, "the magazine is full" end
    return true
end

-- Moves one round from the stack into the magazine, with one save.
-- Returns true, or false and why it stopped.
function Ammo.LoadOneRound(loose_id, mag_id)
    local lc, loose = find_by_id(loose_id)
    local mc, mag = find_by_id(mag_id)
    if not loose then return false, "the stack is used up" end
    if not mag then return false, "the magazine is gone" end
    local ok, why = Ammo.CanLoadInto(loose, mag)
    if not ok then return false, why end

    local md = mag.data
    local rounds = math.floor(tonumber(md.rounds) or 0)
    local data = { rounds = rounds + 1 }
    if Ammo.HasLoad(md) or (loose.data and loose.data.bullet) then
        -- A magazine that knows its bullets: the new round goes on top.
        local bullet = Ammo.BulletId(loose.data.bullet)
        local load = Ammo.LoadPush(Ammo.LoadOf(md), bullet, 1)
        data.bullet = bullet
        data.load = Ammo.LoadString(load)
    end
    local spec = { update = { { container = mc, instance_id = mag_id, data = data } } }
    local amount = math.floor(tonumber(loose.amount) or 1)
    if amount > 1 then
        spec.set_amount = { { container = lc, instance_id = loose_id, amount = amount - 1 } }
    else
        spec.remove = { { container = lc, instance_id = loose_id } }
    end
    local saved, err = PDTI.EditItems(spec)
    if not saved then return false, err or "could not save" end
    return true
end

-- Loads the whole stack (or until full) at once. Returns the rounds loaded.
function Ammo.LoadAllInto(loose_id, mag_id)
    local n = 0
    while n < 1000 and Ammo.LoadOneRound(loose_id, mag_id) do n = n + 1 end
    return n
end

local load_job = nil

-- The inventory screen, if it is open, shows each round going in (not while
-- something is being dragged: that would lose the drag's preview).
local function redraw_screen()
    if PDTI.UIIsDragging and PDTI.UIIsDragging() then return end
    if PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
end

local function hint(text) PDTI.Hint(text, 2) end

local function load_done(why)
    local j = load_job
    load_job = nil
    if not j then return end
    if j.loaded > 0 then
        log(string.format("loaded %d round(s) into the magazine (%s)", j.loaded, tostring(why)))
    end
    if j.loaded > 0 and why ~= "stopped" then hint("Magazine loaded: " .. tostring(why)) end
    local wep = Ammo.EquippedBase and Ammo.EquippedBase()
    if wep then pcall(Ammo.SyncTotal, wep) end
    if Ammo.MarkPanelDirty then pcall(Ammo.MarkPanelDirty) end
    redraw_screen()
end

-- Starts loading the stack into the magazine (in a heist), or loads it at
-- once (in the menu). Returns true, or false and why.
function Ammo.StartLoad(loose_id, mag_id)
    local _, loose = find_by_id(loose_id)
    local _, mag = find_by_id(mag_id)
    local ok, why = Ammo.CanLoadInto(loose, mag)
    if not ok then return false, why end
    if not PDTI.InHeist() then
        local n = Ammo.LoadAllInto(loose_id, mag_id)
        return n > 0, string.format("%d round(s) loaded", n)
    end
    if load_job then load_done("stopped") end
    load_job = { loose = loose_id, mag = mag_id, t = 0, loaded = 0 }
    hint("Loading the magazine... (shooting, reloading or aiming stops)")
    return true, "loading"
end

function Ammo.LoadActive()
    return load_job ~= nil
end

function Ammo.StopLoad(why)
    if load_job then load_done(why or "stopped") end
end

-- Seconds per round packed into a magazine. Skills speed it up through
-- Ammo.round_speed_mods[name] (functions returning a multiplier, 1.15 = 15%
-- faster); they multiply. Ammo.round_speed (one function) still counts.
Ammo.round_speed_mods = Ammo.round_speed_mods or {}
function Ammo.RoundSpeed()
    local mul = 1
    local function apply(f)
        if type(f) ~= "function" then return end
        local ok, m = pcall(f)
        if ok and type(m) == "number" and m > 0 then mul = mul * m end
    end
    apply(Ammo.round_speed)
    for _, f in pairs(Ammo.round_speed_mods) do apply(f) end
    return mul
end

function Ammo.RoundInterval()
    local base = math.max(0.02, tonumber(Ammo.settings.round_interval) or 0.25)
    base = base / Ammo.RoundSpeed()
    return math.max(0.02, base)
end

-- The rounds the magazine that comes out of the gun keeps (a skill can fill
-- it: Bulletstorm ace). Ammo.eject_rounds(wep, rounds) returns the new count.
function Ammo.EjectRounds(wep, rounds)
    local f = Ammo.eject_rounds
    if type(f) ~= "function" then return rounds end
    local ok, r = pcall(f, wep, rounds)
    if ok and type(r) == "number" then return r end
    return rounds
end

-- How far a magazine on the floor can be picked up from (Scavenger).
Ammo.PICKUP_RANGE = 250
function Ammo.PickupRange()
    local mul = 1
    local f = Ammo.pickup_range_mul
    if type(f) == "function" then
        local ok, m = pcall(f)
        if ok and type(m) == "number" and m > 0 then mul = m end
    end
    return Ammo.PICKUP_RANGE * mul
end

local function load_tick(dt)
    if not load_job then return end
    load_job.t = load_job.t + (dt or 0)
    local interval = Ammo.RoundInterval()
    while load_job and load_job.t >= interval do
        load_job.t = load_job.t - interval
        local ok, why = Ammo.LoadOneRound(load_job.loose, load_job.mag)
        if ok then
            load_job.loaded = load_job.loaded + 1
            if Ammo.MarkPanelDirty then pcall(Ammo.MarkPanelDirty) end
            redraw_screen()
        else
            load_done(why)
        end
    end
end
Ammo.LoadTick = load_tick

function Ammo.Tick(dt)
    load_tick(dt)
    if not job then return end
    job.t = job.t + (dt or 0)
    local interval = Ammo.RoundInterval()
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

    local amount = Ammo.MagAmount(info, wep._name_id)
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
    -- Ammunition chosen in the menu (plan_weapon; older plans plan_slot)
    -- stays: it becomes the weapon's when the weapon is first used. Anything
    -- else is left over.
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        if item.item_id ~= Ammo.MAGAZINE_ITEM and item.item_id ~= Ammo.LOOSE_ITEM then return false end
        local d = item.data
        return not (type(d) == "table" and (d.plan_weapon ~= nil or d.plan_slot ~= nil))
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

-- Testing: one magazine's worth of loose rounds for a weapon (or `rounds`:
-- Ctrl+click spawns a full stack). With a bullet ("hollow", "ap", "slug"
-- ...), rounds of that kind (only bullets the weapon takes).
function Ammo.DevSpawnLoose(slot, bullet, rounds)
    local wep, info, reason = spawn_target(slot)
    if not wep then return false, reason end
    if bullet and bullet ~= "standard" and not Ammo.BulletAllowed(info, bullet) then
        return false, "this weapon does not take these rounds"
    end
    rounds = math.max(1, math.floor(tonumber(rounds) or info.capacity or 1))
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
    if bullet and bullet ~= "standard" and not Ammo.BulletAllowed(info, bullet) then
        return false, "this weapon does not take these rounds"
    end
    local spec = info.typed and { size = info.sized and "standard" or nil, bullet = bullet } or nil
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

-- A magazine on the floor can be picked up when it fits in the inventory.
function Ammo.DroppedFits(tag)
    if not tag or not tag.queue_key then return false end
    local cap = tag.typed and tag.base_capacity and tag.size
        and Ammo.SpecCapacity(tag.base_capacity, tag.size) or Ammo.MagCapacity(tag.pid, tag.caliber)
    local class = nil
    local wep = Ammo.EquippedBase()
    local info = wep and Ammo.Identify(wep)
    if info and info.key == tag.queue_key then class = info.mag_class end
    local ref = { item_id = Ammo.MAGAZINE_ITEM, data = { capacity = cap, mag_class = class, akimbo = tag.akimbo } }
    for _, name in ipairs(Ammo.STORAGE) do
        if PDTI.FindFreeSpace(name, ref, true) then return true end
    end
    return false
end

local function facade_can_pickup_dropped(tag)
    return Ammo.DroppedFits(tag)
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
