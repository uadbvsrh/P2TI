-- What you bring: chosen in the menu, per profile.
--
-- In the menu the inventory is the plan. You pick the rig and the backpack,
-- and you put in what you bring: deployables, magazines and loose rounds for
-- the primary and the secondary. Every heist starts with exactly that,
-- because nothing is written to the save during a heist.
--
-- The magazines and loose rounds of the menu are a weapon's: data.plan_weapon
-- (the weapon id; older plans had data.plan_slot and the id in data.pid).
-- Changing the weapon in a slot changes none of them. The first time a
-- weapon is used in a heist, its kind's become real (Plan.Bind). The
-- magazine loaded in a weapon goes with the weapon (Plan.SyncGunSlots).
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Plan = PDTI.Plan or {}
PDTI.Plan = Plan

local log = PDTI.Logger("PDTI PLAN")

Plan.SLOTS = { "primary", "secondary" }
Plan.SLOT_TAGS = { primary = "PRI", secondary = "SEC" }
-- Items you can bring: the deployables (the items with an effect), these
-- first, then any other in name order.
Plan.FIRST_ITEMS = { "first_aid_kit", "doctor_bag", "ammo_bag", "bodybags_bag", "armor_kit" }

-- A deployable the game does not have (an older game, or a mod's item for a
-- deployable that is not installed) is not offered.
local function game_has(def)
    if not def.deployable_id then return true end
    local equipments = rawget(_G, "tweak_data") and tweak_data.equipments
    if type(equipments) ~= "table" then return true end
    return equipments[def.deployable_id] ~= nil
end
Plan.GameHas = game_has

function Plan.Items()
    local list, seen = {}, {}
    for _, id in ipairs(Plan.FIRST_ITEMS) do
        local def = PDTI.items[id]
        if def and (def.deployable or def.plan_item) and not def.no_supply and game_has(def) then
            list[#list + 1] = id; seen[id] = true
        end
    end
    local rest = {}
    for id, def in pairs(PDTI.items) do
        if not seen[id] and (def.deployable or def.plan_item) and not def.ammo_managed and not def.no_supply
            and game_has(def) then
            rest[#rest + 1] = id
        end
    end
    table.sort(rest)
    for _, id in ipairs(rest) do list[#list + 1] = id end
    return list
end
-- Where new things go: to hand first, then the backpack.
Plan.ORDER = { "rig", "rig_2", "rig_3", "pockets", "backpack" }
-- At most this many magazines per weapon when the menu fills in defaults.
Plan.DEFAULT_MAX_MAGS = 6
-- Rounds in one loose stack: the item's limit (100).
Plan.MAX_LOOSE = (PDTI.items.loose_ammo and tonumber(PDTI.items.loose_ammo.max_stack)) or 100
-- The most loose rounds the menu fills in for a weapon loaded round by round.
Plan.DEFAULT_MAX_LOOSE = 300
Plan.CACHE_FILE = "pdti_weapons.json"

------------------------------------------------------------- weapon cache

-- What a heist learned about a weapon (the real magazine size with every
-- mod and skill), so the menu shows the right size next time.
local cache = nil

local function cache_path()
    return (rawget(_G, "SavePath") or "") .. Plan.CACHE_FILE
end

local function load_cache()
    if cache then return cache end
    cache = {}
    local f = io.open(cache_path(), "r")
    if f then
        local raw = f:read("*all")
        f:close()
        local ok, data = pcall(function() return json.decode(raw) end)
        if ok and type(data) == "table" then cache = data end
    end
    return cache
end

local function blueprint_key(weapon_id, blueprint)
    local parts = {}
    for _, part in ipairs(type(blueprint) == "table" and blueprint or {}) do parts[#parts + 1] = tostring(part) end
    table.sort(parts)
    return tostring(weapon_id) .. "|" .. table.concat(parts, ",")
end

function Plan.RememberWeapon(wep, info)
    if not wep or not info or not wep._name_id then return end
    local entry = {
        capacity = info.capacity, loose_fed = info.loose_fed == true,
        mag_class = info.mag_class, akimbo = info.akimbo == true
    }
    local c = load_cache()
    local key = blueprint_key(wep._name_id, wep._blueprint)
    local old = c[key]
    if type(old) == "table" and old.capacity == entry.capacity and old.loose_fed == entry.loose_fed
        and old.mag_class == entry.mag_class and old.akimbo == entry.akimbo then
        return
    end
    c[key] = entry
    c[tostring(wep._name_id)] = entry
    pcall(function()
        local f = io.open(cache_path(), "w")
        if f then
            f:write(json.encode(c))
            f:close()
        end
    end)
end

------------------------------------------------------- the menu's weapons

-- The weapon of a slot as the menu has it: weapon id and blueprint (and,
-- with your weapons as grid items, the hand item's data). With grid weapons
-- an empty slot has none.
local function hand_cat(slot)
    return slot == "primary" and "primaries" or "secondaries"
end

local function armory_on()
    local A = PDTI.Armory
    return A ~= nil and A.InUse ~= nil and A.InUse() == true
end

-- The hand item of a slot: { container, item } (nil without grid weapons).
local function hand_entry(slot)
    if not armory_on() then return nil end
    local A = PDTI.Armory
    local item = A.HandItem(hand_cat(slot))
    if not item then return nil end
    return { container = A.HANDS[hand_cat(slot)], item = item }
end

function Plan.MenuWeapon(slot)
    if armory_on() then
        local hand = hand_entry(slot)
        local d = hand and hand.item.data
        if type(d) ~= "table" or not d.weapon_id then return nil end
        return d.weapon_id, PDTI.Armory.SplitBlueprint(d.blueprint), d
    end
    local ok, weapon = pcall(function()
        local bm = managers.blackmarket
        if slot == "primary" then return bm:equipped_primary() end
        return bm:equipped_secondary()
    end)
    if not ok or type(weapon) ~= "table" or not weapon.weapon_id then return nil end
    return weapon.weapon_id, weapon.blueprint
end

local function weapon_name(weapon_id, tweak)
    local ok, text = pcall(function()
        return managers.localization:text(tweak.name_id)
    end)
    if ok and type(text) == "string" and text ~= "" and not text:find("ERROR") then return text end
    return tostring(weapon_id)
end

-- What the plan needs to know about a weapon: magazine size, weapon type,
-- akimbo, loaded round by round. slot: the slot it is in (or nil).
function Plan.InfoFor(weapon_id, blueprint, slot)
    if not weapon_id then return nil end
    local tweak = tweak_data and tweak_data.weapon and tweak_data.weapon[weapon_id] or {}
    local has = {}
    for _, category in ipairs(tweak.categories or {}) do has[category] = true end
    local class = nil
    for _, c in ipairs(PDTI.Ammo and PDTI.Ammo.SIZE_CLASSES or {}) do
        if has[c] then class = c break end
    end
    local info = {
        slot = slot, weapon_id = weapon_id, name = weapon_name(weapon_id, tweak),
        mag_class = class, akimbo = has.akimbo == true or nil,
        ammo_max = tonumber(tweak.AMMO_MAX)
    }
    -- Assault rifles and SMGs: the weapon's own magazine is the base, the
    -- game's magazine mods do not count.
    local Ammo = PDTI.Ammo
    local loose_cats = Ammo and Ammo.LOOSE_CATEGORIES or {}
    local loose_cat = false
    for category in pairs(has) do
        if loose_cats[category] then loose_cat = true end
    end
    if Ammo and Ammo.IsTypedClass(class) and not loose_cat and not tweak.use_shotgun_reload then
        local full = math.max(1, math.floor(tonumber(tweak.CLIP_AMMO_MAX) or 30))
        info.capacity = info.akimbo and math.max(1, math.floor(full / 2)) or full
        info.loose_fed = false
        info.typed = true
        info.sized = true
        info.family = "rifle"
        info.exact = true
        return info
    end
    -- Shotguns: the rounds are shells of the game's ammunition types (the
    -- ones the gun takes); the magazines keep the game's sizes.
    if class == "shotgun" then
        info.typed = true
        info.family = "shell"
        info.shell = true
        local ok, fid = pcall(function()
            return managers.weapon_factory:get_factory_id_by_weapon_id(weapon_id)
        end)
        info.factory_id = ok and fid or nil
    end
    -- LMGs: LMG rounds; the magazines keep the game's sizes.
    if class == "lmg" then
        info.typed = true
        info.family = "lmg"
    end
    local c = load_cache()
    local known = c[blueprint_key(weapon_id, blueprint)]
    info.exact = type(known) == "table"
    known = info.exact and known or c[tostring(weapon_id)]
    if type(known) == "table" and tonumber(known.capacity) then
        info.capacity = math.max(1, math.floor(known.capacity))
        info.loose_fed = known.loose_fed == true
        info.mag_class = known.mag_class or info.mag_class
        info.akimbo = known.akimbo == true or nil
        return info
    end
    -- Not used in a heist yet: the weapon's own magazine size.
    local full = math.max(1, math.floor(tonumber(tweak.CLIP_AMMO_MAX) or 30))
    local loose = PDTI.Ammo and PDTI.Ammo.LOOSE_CATEGORIES or {}
    info.loose_fed = false
    for category in pairs(has) do
        if loose[category] then info.loose_fed = true end
    end
    if tweak.use_shotgun_reload or full <= 1 or (has.shotgun and full <= 2) then info.loose_fed = true end
    info.capacity = full
    if info.akimbo and not info.loose_fed then info.capacity = math.max(1, math.floor(full / 2)) end
    return info
end

-- The weapon of a slot (nil without one). info.uid: the hand item's.
function Plan.Info(slot)
    local weapon_id, blueprint, hand = Plan.MenuWeapon(slot)
    local info = Plan.InfoFor(weapon_id, blueprint, slot)
    if info then
        info.blueprint = blueprint
        info.uid = hand and hand.uid or nil
    end
    return info
end

-- What the plan knows about a kind of weapon whose ammunition you have: the
-- one in your hands first (its parts), else a weapon of yours of that kind,
-- else the game's. Nil for a weapon nobody knows.
function Plan.KindInfo(kind)
    if kind == nil then return nil end
    for _, slot in ipairs(Plan.SLOTS) do
        local weapon_id, blueprint = Plan.MenuWeapon(slot)
        if weapon_id == kind then return Plan.InfoFor(kind, blueprint, slot) end
    end
    local _, item = PDTI.FindFirstItem(function(_, it)
        return it.item_id == "weapon" and type(it.data) == "table" and it.data.weapon_id == kind
    end)
    if item and PDTI.Armory then return Plan.InfoFor(kind, PDTI.Armory.SplitBlueprint(item.data.blueprint), nil) end
    local known = tweak_data and tweak_data.weapon and tweak_data.weapon[kind]
    if known or type(load_cache()[tostring(kind)]) == "table" then return Plan.InfoFor(kind, nil, nil) end
    return nil
end

function Plan.WeaponTag(weapon_id)
    local Ammo = PDTI.Ammo
    return Ammo and Ammo.WeaponTag and Ammo.WeaponTag(weapon_id) or tostring(weapon_id)
end

-- A magazine of the plan, full. An assault rifle's or SMG's has the size
-- and bullets of spec ({ size, bullet }).
local function mag_data(info, spec)
    local tag = Plan.WeaponTag(info.weapon_id)
    local data = {
        plan_weapon = info.weapon_id, queue_key = "plan:" .. tostring(info.weapon_id), wtag = tag,
        rounds = info.capacity, capacity = info.capacity,
        mag_class = info.mag_class, akimbo = info.akimbo or nil,
        caliber = tag, pid = info.weapon_id
    }
    if info.typed then
        -- The rounds it holds: the load given (top first), the rounds given,
        -- or full of the given bullets. Shotgun magazines have no size.
        local Ammo = PDTI.Ammo
        data.family = info.family
        if info.sized then
            data.size = Ammo.SizeId(spec and spec.size)
            data.capacity = Ammo.SpecCapacity(info.capacity, data.size)
        end
        local fill = Ammo.SafeBullet(info, spec and spec.bullet)
        local load
        if spec and spec.load ~= nil then
            load = Ammo.FilterLoad(info, Ammo.ParseLoad(spec.load))
            Ammo.FitLoad(load, math.min(Ammo.LoadTotal(load), data.capacity), fill)
        else
            local rounds = spec and tonumber(spec.rounds) or data.capacity
            load = Ammo.FitLoad({}, math.min(math.max(0, rounds), data.capacity), fill)
        end
        data.rounds = Ammo.LoadTotal(load)
        data.bullet = Ammo.LoadTop(load) or fill
        if data.rounds > 0 then data.load = Ammo.LoadString(load) end
    end
    return data
end

-- The rounds of a magazine of the plan: AR/SMG magazines by size.
local function spec_cap(info, size)
    if info.sized then return PDTI.Ammo.SpecCapacity(info.capacity, size) end
    return info.capacity
end

local function loose_data(info, bullet)
    local tag = Plan.WeaponTag(info.weapon_id)
    return {
        plan_weapon = info.weapon_id, queue_key = "plan:" .. tostring(info.weapon_id), wtag = tag,
        mag_class = info.mag_class, caliber = tag, pid = info.weapon_id,
        bullet = info.typed and PDTI.Ammo.SafeBullet(info, bullet) or nil,
        family = info.family
    }
end

-- The magazine "+ mag" adds: its size and the rounds of each bullet, top
-- first. Without a choice, full of pick_bullet.
function Plan.PickSpec(slot)
    local Ammo = PDTI.Ammo
    local p = PDTI.GetPlanSlot(slot)
    local info = Plan.Info(slot)
    local cap = info and spec_cap(info, p.pick_size) or Ammo.SpecCapacity(30, p.pick_size)
    -- A plan made for another gun: bullets this one cannot use are standard.
    local pick_bullet = info and Ammo.SafeBullet(info, p.pick_bullet) or Ammo.BulletId(p.pick_bullet)
    local load
    if p.pick_load ~= nil then
        load = info and Ammo.FilterLoad(info, Ammo.ParseLoad(p.pick_load)) or Ammo.ParseLoad(p.pick_load)
        -- A smaller magazine: the bottom rounds do not fit.
        local over = Ammo.LoadTotal(load) - cap
        while over > 0 and load[#load] do
            local take = math.min(over, load[#load][2])
            load[#load][2] = load[#load][2] - take
            over = over - take
            if load[#load][2] <= 0 then table.remove(load) end
        end
    else
        load = { { pick_bullet, cap } }
    end
    return { size = (not info or info.sized) and p.pick_size or nil, bullet = Ammo.LoadTop(load) or pick_bullet,
        load = load, rounds = Ammo.LoadTotal(load), capacity = cap }
end

-- The rounds of a bullet in the magazine "+ mag" adds.
function Plan.PickCount(slot, bullet)
    local n = 0
    for _, part in ipairs(Plan.PickSpec(slot).load) do
        if part[1] == bullet then n = n + part[2] end
    end
    return n
end

-- Rounds per click when choosing what goes into a magazine.
function Plan.PickStep(slot)
    local cap = Plan.PickSpec(slot).capacity
    if cap < 10 then return 1 end
    return 5
end

-- Sets the rounds of a bullet in the magazine "+ mag" adds (at most what
-- the magazine still takes). A new kind goes under the others.
function Plan.SetPickCount(slot, bullet, n)
    if PDTI.InHeist and PDTI.InHeist() then return false, "What you bring is chosen in the menu" end
    local Ammo = PDTI.Ammo
    if not Ammo.BULLETS[bullet] then return false, "unknown bullets" end
    local info = Plan.Info(slot)
    if info and not Ammo.BulletAllowed(info, bullet) then return false, "these rounds do not fit this weapon" end
    local spec = Plan.PickSpec(slot)
    local others, list, at = 0, {}, nil
    for _, part in ipairs(spec.load) do
        if part[1] == bullet then
            at = at or #list + 1
        else
            others = others + part[2]
            list[#list + 1] = { part[1], part[2] }
        end
    end
    n = math.max(0, math.min(math.floor(tonumber(n) or 0), spec.capacity - others))
    if n > 0 then table.insert(list, at or (#list + 1), { bullet, n }) end
    local ok = PDTI.SetPlanSlot(slot, "pick_load", Ammo.LoadString(list))
    if ok then PDTI.SetAmmoPlanned(true) end
    return ok, (n == 0 and others >= spec.capacity) and "the magazine is full" or nil
end

function Plan.ChangePickCount(slot, bullet, add)
    local step = Plan.PickStep(slot)
    local now = Plan.PickCount(slot, bullet)
    if add then
        local spec = Plan.PickSpec(slot)
        if spec.rounds >= spec.capacity then return false, "the magazine is full" end
        -- Fill up to the next step, and never past full.
        return Plan.SetPickCount(slot, bullet, now + step - (now % step == 0 and 0 or now % step))
    end
    if now <= 0 then return false, "none of these in it" end
    return Plan.SetPickCount(slot, bullet, now - (now % step == 0 and step or now % step))
end

-- Ctrl+click on "+": the rest of the magazine is this bullet.
function Plan.FillPick(slot, bullet)
    local spec = Plan.PickSpec(slot)
    if spec.rounds >= spec.capacity then return false, "the magazine is full" end
    return Plan.SetPickCount(slot, bullet, spec.capacity)
end

-- Ctrl+click on "-": none of this bullet.
function Plan.ClearPick(slot, bullet)
    if Plan.PickCount(slot, bullet) <= 0 then return false, "none of these in it" end
    return Plan.SetPickCount(slot, bullet, 0)
end

-- Turns the magazine's load upside down (the bottom rounds are fired first).
function Plan.FlipPick(slot)
    if PDTI.InHeist and PDTI.InHeist() then return false, "What you bring is chosen in the menu" end
    local load = Plan.PickSpec(slot).load
    local flipped = {}
    for i = #load, 1, -1 do flipped[#flipped + 1] = load[i] end
    return PDTI.SetPlanSlot(slot, "pick_load", PDTI.Ammo.LoadString(flipped))
end

-- The magazine in the gun when its slot is empty (older plans).
function Plan.GunSpec(slot)
    local p = PDTI.GetPlanSlot(slot)
    local info = Plan.Info(slot)
    local bullet = info and info.typed and PDTI.Ammo.SafeBullet(info, p.gun_bullet) or p.gun_bullet
    return { size = (not info or info.sized) and p.gun_size or nil, bullet = bullet }
end

-- Choose a size or bullets ("gun_size", "pick_bullet", ...). Only in the menu.
function Plan.SetSpec(slot, field, value)
    if PDTI.InHeist and PDTI.InHeist() then return false, "What you bring is chosen in the menu" end
    local Ammo = PDTI.Ammo
    if field:match("_size$") and not Ammo.MAG_SIZES[value] then return false, "unknown size" end
    if field:match("_bullet$") and not Ammo.BULLETS[value] then return false, "unknown bullets" end
    if field:match("_bullet$") then
        local info = Plan.Info(slot)
        if info and not Ammo.BulletAllowed(info, value) then return false, "these rounds do not fit this weapon" end
    end
    local ok = PDTI.SetPlanSlot(slot, field, value)
    if ok and field == "pick_size" and PDTI.GetPlanSlot(slot).pick_load then
        -- Keep what still fits.
        PDTI.SetPlanSlot(slot, "pick_load", Ammo.LoadString(Plan.PickSpec(slot).load))
    end
    if ok then PDTI.SetAmmoPlanned(true) end
    return ok
end

------------------------------------------------------------- the plan

-- The weapon a piece of the plan's ammunition is for: its weapon id.
local function kind_of(data)
    if type(data) ~= "table" then return nil end
    if data.plan_weapon ~= nil then return data.plan_weapon end
    if data.plan_slot ~= nil then return data.pid end
    return nil
end
Plan.KindOf = kind_of

-- The kind of the weapon in a slot (the slot's rows act on it).
local function slot_kind(slot)
    return (Plan.MenuWeapon(slot))
end

local function plan_items(item_id, kind)
    if kind == nil then return {} end
    return PDTI.FindItems(function(_, item)
        return item.item_id == item_id and kind_of(item.data) == kind
    end)
end

-- The magazines you carry for the slot's weapon (not the one in it).
function Plan.Magazines(slot)
    local out = {}
    for _, entry in ipairs(plan_items(PDTI.Ammo.MAGAZINE_ITEM, slot_kind(slot))) do
        if not PDTI.IsGunSlot(entry.container) then out[#out + 1] = entry end
    end
    return out
end

-- The magazine in the slot's weapon: the heist starts with it in the gun
-- (akimbo: up to two).
function Plan.GunMagazines(slot)
    local c = PDTI.Ammo.GUN_SLOTS[slot]
    return PDTI.FindItems(function(name, item)
        return name == c and item.item_id == PDTI.Ammo.MAGAZINE_ITEM
    end)
end

-- Every magazine of the plan for a kind of weapon.
local function all_magazines(kind)
    return plan_items(PDTI.Ammo.MAGAZINE_ITEM, kind)
end

-- Loose stacks of a kind of weapon (of one bullet, or all).
local function loose_stacks(kind, bullet)
    local list = plan_items(PDTI.Ammo.LOOSE_ITEM, kind)
    if not bullet then return list end
    local out = {}
    for _, entry in ipairs(list) do
        if PDTI.Ammo.BulletId(entry.item.data.bullet) == bullet then out[#out + 1] = entry end
    end
    return out
end

-- Loose stacks for the slot's weapon (of one bullet, or all).
function Plan.LooseStacks(slot, bullet)
    local list = plan_items(PDTI.Ammo.LOOSE_ITEM, slot_kind(slot))
    if not bullet then return list end
    local out = {}
    for _, entry in ipairs(list) do
        if PDTI.Ammo.BulletId(entry.item.data.bullet) == bullet then out[#out + 1] = entry end
    end
    return out
end

function Plan.LooseRounds(slot, bullet)
    local total = 0
    for _, entry in ipairs(Plan.LooseStacks(slot, bullet)) do total = total + (tonumber(entry.item.amount) or 0) end
    return total
end

-- "mag:primary", "loose:secondary", "loose:primary:hollow" or an item id.
local function parse(kind)
    local what, slot, bullet = tostring(kind):match("^(%a+):(%a+):(%a+)$")
    if what and Plan.SLOT_TAGS[slot] and PDTI.Ammo.BULLETS[bullet] then return what, slot, bullet end
    what, slot = tostring(kind):match("^(%a+):(%a+)$")
    if what and Plan.SLOT_TAGS[slot] then return what, slot end
    return "item", kind
end

function Plan.Count(kind)
    local what, arg, bullet = parse(kind)
    if what == "mag" then return #Plan.Magazines(arg) end
    if what == "loose" then return Plan.LooseRounds(arg, bullet) end
    local total = 0
    for _, entry in ipairs(PDTI.FindItems(function(_, item) return item.item_id == arg end)) do
        total = total + (tonumber(entry.item.amount) or 1)
    end
    return total
end

-- Loose rounds come and go a magazine at a time.
function Plan.LooseStep(info)
    return math.max(1, math.floor(tonumber(info and info.capacity) or 30))
end

local function add_auto(item_id, amount, data)
    local last
    for _, name in ipairs(Plan.ORDER) do
        local ok, reason = PDTI.AddItemAuto(name, item_id, amount, data, true)
        if ok then return true, name end
        last = reason
    end
    return false, "no room for it (" .. tostring(last) .. ")"
end

local function add_loose(info, rounds, bullet)
    rounds = math.max(0, math.floor(rounds))
    local data = loose_data(info, bullet)
    for _, entry in ipairs(loose_stacks(info.weapon_id, data.bullet)) do
        if rounds <= 0 then return true end
        local amount = tonumber(entry.item.amount) or 0
        local room = Plan.MAX_LOOSE - amount
        if room > 0 then
            local take = math.min(room, rounds)
            if PDTI.EditItems({ set_amount = { { container = entry.container,
                instance_id = entry.item.instance_id, amount = amount + take } } }) then
                rounds = rounds - take
            end
        end
    end
    while rounds > 0 do
        local take = math.min(Plan.MAX_LOOSE, rounds)
        local ok, reason = add_auto(PDTI.Ammo.LOOSE_ITEM, take, data)
        if not ok then return false, reason end
        rounds = rounds - take
    end
    return true
end

local function remove_loose(slot, rounds, bullet)
    local stacks = Plan.LooseStacks(slot, bullet)
    for i = #stacks, 1, -1 do
        if rounds <= 0 then break end
        local entry = stacks[i]
        local amount = tonumber(entry.item.amount) or 0
        local take = math.min(amount, rounds)
        if take >= amount then
            PDTI.RemoveItem(entry.container, entry.item.instance_id)
        else
            PDTI.EditItems({ set_amount = { { container = entry.container,
                instance_id = entry.item.instance_id, amount = amount - take } } })
        end
        rounds = rounds - take
    end
    return true
end

---------------------------------------------------------------- the price

-- Everything you bring costs money (Ammo.PRICES). Adding something to the
-- plan pays for it from your spending cash at once; taking it out pays it
-- back (at most what was paid: PDTI.PlanPaid). The plan comes back every
-- heist, so what a heist uses up (rounds fired, deployables placed,
-- throwables thrown) is paid again to restock it, as it is used.

-- What the plan is worth: every item in it, ammunition by size and bullet.
function Plan.Cost()
    local Ammo = PDTI.Ammo
    local total = 0
    for _, entry in ipairs(PDTI.FindItems(function() return true end)) do
        total = total + Ammo.ItemPrice(entry.item)
    end
    return total
end

-- The player's money (nil where the game's money manager is not there).
function Plan.Money()
    local ok, value = pcall(function() return managers.money:total() end)
    if ok and type(value) == "number" then return value end
    return nil
end

function Plan.CanAfford(price)
    local money = Plan.Money()
    if not money then return true end
    return (tonumber(price) or 0) <= money
end

-- What one more of a kind costs ("mag:primary", "loose:primary:ap", an item).
function Plan.AddPrice(kind)
    local Ammo = PDTI.Ammo
    local what, arg, bullet = parse(kind)
    if what == "item" then return Ammo.UnitPrice(arg) end
    local info = Plan.Info(arg)
    if not info then return 0 end
    if what == "mag" then return Ammo.MagazinePrice(mag_data(info, Plan.PickSpec(arg))) end
    return Plan.LooseStep(info) * Ammo.RoundPrice(info.typed and Ammo.SafeBullet(info, bullet) or "standard")
end

-- Takes money from the spending cash. Returns what was taken.
local function take_money(amount)
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if amount <= 0 then return 0 end
    local money = Plan.Money()
    if not money then return 0 end
    amount = math.min(amount, money)
    local ok = pcall(function() managers.money:deduct_from_total(amount) end)
    return ok and amount or 0
end

-- Gives money back to the spending cash (none of it offshore).
local function give_money(amount)
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if amount <= 0 then return 0 end
    local ok = pcall(function()
        local mm = managers.money
        if type(mm.add_to_spending) == "function" then mm:add_to_spending(amount)
        else mm:_add_to_total(amount, { no_offshore = true }) end
    end)
    return ok and amount or 0
end

-- Pays for something added to the plan.
function Plan.Pay(price)
    local paid = take_money(price)
    if paid > 0 then PDTI.SetPlanPaid(PDTI.PlanPaid() + paid) end
    return paid
end

-- Pays back something taken out of the plan, never more than was paid.
function Plan.Refund(price)
    local back = give_money(math.min(tonumber(price) or 0, PDTI.PlanPaid()))
    if back > 0 then PDTI.SetPlanPaid(PDTI.PlanPaid() - back) end
    return back
end

------------------------------------------------------------- the restock

-- In a heist: what the plan brought is the most that is paid again (rounds
-- from ammo boxes and bags are free, and so is using them).
Plan.restock = nil
-- Money is taken at most this often (seconds); the rest waits.
Plan.RESTOCK_EVERY = 1

local function plan_rounds(rounds, item)
    local Ammo = PDTI.Ammo
    local data = type(item.data) == "table" and item.data or {}
    if item.item_id == Ammo.MAGAZINE_ITEM then
        if data.size or data.load or data.bullet then
            for _, part in ipairs(Ammo.LoadOf(data)) do
                local id = Ammo.BulletId(part[1])
                rounds[id] = (rounds[id] or 0) + part[2]
            end
        else
            rounds.standard = (rounds.standard or 0) + (tonumber(data.rounds) or 0)
        end
        return true
    end
    if item.item_id == Ammo.LOOSE_ITEM then
        local id = Ammo.BulletId(data.bullet)
        rounds[id] = (rounds[id] or 0) + (tonumber(item.amount) or 0)
        return true
    end
    return false
end

-- When the heist starts (the inventory is still the plan): what it brings.
function Plan.StartRestock()
    local rounds, items = {}, {}
    for _, entry in ipairs(PDTI.FindItems(function() return true end)) do
        local item = entry.item
        if not plan_rounds(rounds, item) and PDTI.Ammo.UnitPrice(item.item_id) > 0 then
            items[item.item_id] = (items[item.item_id] or 0) + (tonumber(item.amount) or 1)
        end
    end
    local have = {}
    for id, n in pairs(items) do have[id] = n end
    Plan.restock = { rounds = rounds, items = items, have = have, throwables = nil, owed = 0, spent = 0,
        weapons = {}, grenades = nil, last_pay = nil }
    return Plan.restock
end

-- Something of the plan was used up: "round" (id = bullet), "item" (an item
-- id) or "throwable" (a projectile id). Paid at the next Plan.PayRestock.
function Plan.Spend(what, id, n)
    local r = Plan.restock
    if not r then return 0 end
    n = math.max(0, math.floor(tonumber(n) or 0))
    if n == 0 then return 0 end
    local Ammo = PDTI.Ammo
    local left, price
    if what == "round" then
        id = Ammo.BulletId(id)
        left, price = r.rounds[id] or 0, Ammo.RoundPrice(id)
    elseif what == "item" then
        left, price = r.items[id] or 0, Ammo.UnitPrice(id)
    elseif what == "throwable" then
        left, price = r.throwables or 0, Ammo.ThrowablePrice(id)
    else
        return 0
    end
    local take = math.min(n, left)
    if take <= 0 then return 0 end
    if what == "round" then r.rounds[id] = left - take
    elseif what == "item" then r.items[id] = left - take
    else r.throwables = left - take end
    r.owed = r.owed + take * price
    return take * price
end

-- Takes what is owed from the spending cash.
function Plan.PayRestock(force)
    local r = Plan.restock
    if not r or r.owed < 1 then return 0 end
    local now = PDTI.AppTime()
    if not force and r.last_pay and now - r.last_pay < Plan.RESTOCK_EVERY then return 0 end
    r.last_pay = now
    local amount = math.floor(r.owed)
    r.owed = r.owed - amount
    take_money(amount)
    r.spent = r.spent + amount
    return amount
end

local function bullet_of(base)
    local Ammo = PDTI.Ammo
    local ok, typed = pcall(function()
        return (Ammo.TypedBase and Ammo.TypedBase(base)) or (Ammo.ShellBase and Ammo.ShellBase(base))
    end)
    if ok and typed then return Ammo.FiredBullet(typed) or "standard" end
    return "standard"
end

-- Every frame of the heist: the rounds the player's weapons lost (fired, or
-- left on the ground) and the throwables thrown since the last frame.
function Plan.RestockTick()
    local r = Plan.restock
    if not r then return end
    local unit = PDTI.Ammo.PlayerUnit and PDTI.Ammo.PlayerUnit()
    if unit then
        pcall(function()
            local selections = unit:inventory():available_selections()
            for index = 1, 2 do
                local sel = selections[index]
                local base = sel and sel.unit and sel.unit:base()
                if base and base.get_ammo_total and base.get_ammo_remaining_in_clip then
                    -- A round fired leaves the clip and the total. A reload
                    -- changes the clip only; the plan becoming the weapon's
                    -- (before it is ready) does not count.
                    local total = tonumber(base:get_ammo_total()) or 0
                    local clip = tonumber(base:get_ammo_remaining_in_clip()) or 0
                    local seen = r.weapons[index]
                    local ready = not PDTI.Ammo.SupplyReady or PDTI.Ammo.SupplyReady(base)
                    if ready and seen and seen.unit == sel.unit then
                        local fired = math.min(seen.total - total, seen.clip - clip)
                        if fired > 0 then Plan.Spend("round", bullet_of(base), fired) end
                    end
                    r.weapons[index] = ready and { unit = sel.unit, total = total, clip = clip } or nil
                end
            end
        end)
        pcall(function()
            local pm = managers.player
            local peer = managers.network:session():local_peer():id()
            local amount = pm:get_grenade_amount(peer)
            local id = managers.blackmarket:equipped_grenade()
            if type(amount) ~= "number" then return end
            if r.throwables == nil then r.throwables = amount end
            if r.grenades and amount < r.grenades then Plan.Spend("throwable", id, r.grenades - amount) end
            r.grenades = amount
        end)
    end
    -- Items placed, used or left behind: fewer of them than before.
    local counts = {}
    for _, entry in ipairs(PDTI.FindItems(function(_, item) return r.have[item.item_id] ~= nil end)) do
        local id = entry.item.item_id
        counts[id] = (counts[id] or 0) + (tonumber(entry.item.amount) or 1)
    end
    for id, before in pairs(r.have) do
        local now = counts[id] or 0
        if now < before then Plan.Spend("item", id, before - now) end
        r.have[id] = now
    end
    Plan.PayRestock(false)
end

-- One more of something: a magazine, a magazine's worth of loose rounds, or
-- one item. Only in the menu.
function Plan.Add(kind)
    if PDTI.InHeist and PDTI.InHeist() then return false, "What you bring is chosen in the menu" end
    local what, arg, bullet = parse(kind)
    local price = Plan.AddPrice(kind)
    local function poor()
        return false, string.format("Not enough money: it costs %s, you have %s",
            PDTI.Ammo.Money(price), PDTI.Ammo.Money(Plan.Money()))
    end
    local ok, reason
    if what == "item" then
        if not PDTI.items[arg] then return false, "unknown item" end
        if not Plan.CanAfford(price) then return poor() end
        ok, reason = add_auto(arg, 1, nil)
        if ok then Plan.Pay(price) end
        return ok, reason
    end
    local info = Plan.Info(arg)
    if not info then return false, "no " .. arg .. " weapon" end
    if not Plan.CanAfford(price) then return poor() end
    if what == "mag" then
        if info.loose_fed then return false, info.name .. " is loaded round by round: bring loose rounds" end
        ok, reason = add_auto(PDTI.Ammo.MAGAZINE_ITEM, 1, mag_data(info, Plan.PickSpec(arg)))
    else
        if bullet and info.typed and not PDTI.Ammo.BulletAllowed(info, bullet) then
            return false, "these rounds do not fit this weapon"
        end
        ok, reason = add_loose(info, Plan.LooseStep(info), bullet)
    end
    if ok then
        Plan.Pay(price)
        PDTI.SetAmmoPlanned(true)
    end
    return ok, reason
end

-- One less. Magazines leave the backpack first.
function Plan.Remove(kind)
    if PDTI.InHeist and PDTI.InHeist() then return false, "What you bring is chosen in the menu" end
    local what, arg, bullet = parse(kind)
    local list
    if what == "item" then
        list = PDTI.FindItems(function(_, item) return item.item_id == arg end)
    elseif what == "mag" then
        list = Plan.Magazines(arg)
        -- The chosen kind of magazine first, then any.
        local info = Plan.Info(arg)
        if info and info.typed then
            local pick, same_kind = Plan.PickSpec(arg), {}
            for _, entry in ipairs(list) do
                if entry.item.data.size == pick.size and entry.item.data.bullet == pick.bullet then
                    same_kind[#same_kind + 1] = entry
                end
            end
            if #same_kind > 0 then list = same_kind end
        end
    else
        local info = Plan.Info(arg)
        local have = Plan.LooseRounds(arg, bullet)
        if have <= 0 then return false, "nothing to remove" end
        local rounds = math.min(have, Plan.LooseStep(info))
        remove_loose(arg, rounds, bullet)
        Plan.Refund(rounds * PDTI.Ammo.RoundPrice(bullet))
        PDTI.SetAmmoPlanned(true)
        return true
    end
    if #list == 0 then return false, "nothing to remove" end
    local pick = list[#list]
    for _, entry in ipairs(list) do
        if entry.container == "backpack" then pick = entry end
    end
    local price = PDTI.Ammo.ItemPrice({ item_id = pick.item.item_id, amount = 1, data = pick.item.data })
    local ok, reason = PDTI.RemoveItem(pick.container, pick.item.instance_id, 1)
    if ok then Plan.Refund(price) end
    if ok and what == "mag" then PDTI.SetAmmoPlanned(true) end
    return ok, reason
end

-------------------------------------------- the magazine in the weapon

-- The magazine loaded in a weapon is that weapon's. In the menu it sits in
-- the slot's magazine box while the weapon is in the slot (data.weapon_uid:
-- the weapon item's uid) and goes with the weapon when it leaves: the weapon
-- item keeps it (Ammo.GunFields). Without grid weapons the box holds the
-- magazine of the game's weapon of the slot.

local function update_item(entry, fields)
    return PDTI.EditItems({ update = { { container = entry.container,
        instance_id = entry.item.instance_id, data = fields } } })
end

local function weapon_entry(uid)
    if uid == nil then return nil end
    return PDTI.FindItems(function(_, item)
        return item.item_id == "weapon" and type(item.data) == "table" and item.data.uid == uid
    end)[1]
end

-- A weapon's build changed (a part fitted or taken off, 0.38.0): the
-- magazines it keeps take the size of its new build (an extended pistol
-- magazine). Returns true when they were reshaped.
function Plan.ReshapeStored(uid)
    local e = weapon_entry(uid)
    local d = e and e.item.data
    if not d or (tonumber(d.gun_n) or 0) <= 0 then return false end
    local A = PDTI.Armory
    local info = Plan.InfoFor(d.weapon_id, A and A.SplitBlueprint(d.blueprint) or nil, nil)
    if not info or info.loose_fed then return false end
    local list = {}
    for _, m in ipairs(PDTI.Ammo.StoredMagazines(d)) do
        list[#list + 1] = mag_data(info, { size = m.size, bullet = m.bullet, load = m.load, rounds = m.rounds })
    end
    update_item(e, PDTI.Ammo.GunFields(list))
    return true
end

-- A weapon sold (0.38.0): its loaded magazine, kept in the weapon or in its
-- slot's box, is paid back as the Bring list pays back one taken out (never
-- more than was paid). Returns what was paid back. (A box magazine of a
-- weapon that is gone leaves at the next Plan.SyncGunSlots.)
function Plan.SellMagazines(d)
    local Ammo = PDTI.Ammo
    if type(d) ~= "table" then return 0 end
    local price = 0
    local A = PDTI.Armory
    local info = Plan.InfoFor(d.weapon_id, A and A.SplitBlueprint(d.blueprint) or nil, nil)
    if info and not info.loose_fed then
        for _, m in ipairs(Ammo.StoredMagazines(d)) do
            price = price + Ammo.MagazinePrice(mag_data(info, { size = m.size, bullet = m.bullet, load = m.load, rounds = m.rounds }))
        end
    end
    local uid = tonumber(d.uid) or 0
    if uid > 0 then
        for _, b in ipairs(PDTI.FindItems(function(name, item)
            return PDTI.GUN_SLOTS[name] ~= nil and item.item_id == Ammo.MAGAZINE_ITEM and type(item.data) == "table"
                and tonumber(item.data.weapon_uid) == uid
        end)) do
            price = price + Ammo.ItemPrice(b.item)
        end
    end
    return Plan.Refund(price)
end

-- A weapon of yours of this kind, not in your hands, holding no magazine.
local function empty_weapon(kind)
    if kind == nil then return nil end
    return PDTI.FindItems(function(name, item)
        local d = item.data
        return item.item_id == "weapon" and type(d) == "table" and d.weapon_id == kind
            and not PDTI.HAND_SLOTS[name] and (tonumber(d.gun_n) or 0) == 0
    end)[1]
end

-- A magazine leaving a weapon's box with no weapon to go with: into the
-- grid (marked was_gun: it goes back into that gun), else paid back.
local function to_grid(c, item)
    local data = {}
    for k, v in pairs(item.data or {}) do data[k] = v end
    data.weapon_uid = nil
    data.was_gun = 1
    PDTI.RemoveItem(c, item.instance_id)
    if add_auto(item.item_id, item.amount or 1, data) then return true end
    Plan.Refund(PDTI.Ammo.ItemPrice(item))
    log("a magazine had no room in the inventory and was paid back")
    return false
end

-- Without grid weapons: the kinds of weapon whose free magazine a slot gave
-- ("a,b"; each kind once).
local function filled_kinds(slot)
    local out = {}
    for k in tostring(PDTI.GetPlanSlot(slot).gun_filled or ""):gmatch("[^,]+") do out[k] = true end
    return out
end

local function mark_filled(slot, kind)
    local have = filled_kinds(slot)
    if kind == nil or have[tostring(kind)] then return end
    local list = {}
    for k in pairs(have) do if k ~= "1" then list[#list + 1] = k end end
    list[#list + 1] = tostring(kind)
    table.sort(list)
    PDTI.SetPlanSlot(slot, "gun_filled", table.concat(list, ","))
end

-- Full magazine(s) for the slot's weapon (akimbo: two), free: a weapon
-- comes with its magazine.
local function fill_gun(slot, info, spec)
    local data = mag_data(info, spec)
    data.weapon_uid = info.uid
    for _ = 1, info.akimbo and 2 or 1 do
        PDTI.AddItemAuto(PDTI.Ammo.GUN_SLOTS[slot], PDTI.Ammo.MAGAZINE_ITEM, 1, data, true)
    end
    local hand = hand_entry(slot)
    if hand then
        update_item(hand, { gun_set = 1, gun_n = 0, gun_weight = 0 })
    else
        mark_filled(slot, info.weapon_id)
    end
end

-- Puts each magazine where its weapon is: a weapon that left a slot took
-- its magazine along (a weapon that is gone, thrown away or lost, took it
-- with it); the weapon in a slot has its own back in the box (a new weapon
-- comes with a full one, a weapon you emptied stays empty). Menu only.
function Plan.SyncGunSlots()
    if PDTI.InHeist and PDTI.InHeist() then return false end
    local Ammo = PDTI.Ammo
    local armory = armory_on()
    local changed = false
    -- A magazine you took out of a box is no weapon's any more.
    for _, e in ipairs(PDTI.FindItems(function(name, it)
        return it.item_id == Ammo.MAGAZINE_ITEM and not PDTI.IsGunSlot(name) and type(it.data) == "table"
            and (tonumber(it.data.weapon_uid) or 0) > 0
    end)) do
        PDTI.EditItems({ update = { { container = e.container, instance_id = e.item.instance_id,
            data = { weapon_uid = 0 } } } })
    end
    for _, slot in ipairs(Plan.SLOTS) do
        local c = Ammo.GUN_SLOTS[slot]
        local info = Plan.Info(slot)
        local hand = hand_entry(slot)
        local hd = hand and hand.item.data or nil
        local kind = info and info.weapon_id
        local owned, others, keep = {}, {}, 0
        for _, it in ipairs((PDTI.GetContainerInfo(c) or { items = {} }).items) do
            local d = type(it.data) == "table" and it.data or {}
            local owner = tonumber(d.weapon_uid) or 0
            if it.item_id ~= Ammo.MAGAZINE_ITEM then
                -- (nothing else goes into a magazine box)
            elseif hd and owner == hd.uid then
                keep = keep + 1
            elseif armory and owner > 0 then
                owned[owner] = owned[owner] or {}
                table.insert(owned[owner], it)
            elseif kind and kind_of(d) == kind then
                -- A magazine of this weapon put into its box: its own now.
                keep = keep + 1
                if hd then
                    PDTI.EditItems({ update = { { container = c, instance_id = it.instance_id,
                        data = { weapon_uid = hd.uid } } } })
                end
            else
                local k = tostring(kind_of(d))
                others[k] = others[k] or {}
                table.insert(others[k], it)
            end
        end
        for uid, list in pairs(owned) do
            local w = weapon_entry(uid)
            local mags = {}
            for _, it in ipairs(list) do mags[#mags + 1] = it.data end
            if w then update_item(w, Ammo.GunFields(mags)) end
            for _, it in ipairs(list) do PDTI.RemoveItem(c, it.instance_id) end
            changed = true
        end
        -- Another weapon's magazine without its weapon (an older plan, or
        -- the game's weapon changed): into a weapon of yours of its kind
        -- that holds none, else into the grid.
        for k, list in pairs(others) do
            local w = armory and empty_weapon(k) or nil
            local room = 0
            if w then room = (Plan.KindInfo(k) or {}).akimbo and 2 or 1 end
            local mags = {}
            for _, it in ipairs(list) do
                if #mags < room then
                    mags[#mags + 1] = it.data
                    PDTI.RemoveItem(c, it.instance_id)
                else
                    to_grid(c, it)
                end
            end
            if w and #mags > 0 then update_item(w, Ammo.GunFields(mags)) end
            changed = true
        end
        if info and not info.loose_fed and keep == 0 then
            if hd and hd.gun_set ~= 1 then
                fill_gun(slot, info, Plan.GunSpec(slot))
                changed = true
            elseif hd and (tonumber(hd.gun_n) or 0) > 0 then
                for _, m in ipairs(Ammo.StoredMagazines(hd)) do
                    local data = mag_data(info, { size = m.size, bullet = m.bullet, load = m.load, rounds = m.rounds })
                    data.weapon_uid = hd.uid
                    PDTI.AddItemAuto(c, Ammo.MAGAZINE_ITEM, 1, data, true)
                end
                update_item(hand, { gun_n = 0, gun_weight = 0 })
                changed = true
            elseif not hd and not armory then
                -- The game's weapon of the slot: the magazine that left its
                -- gun goes back in; a kind new to the slot comes with one.
                local spare = nil
                for _, e in ipairs(Plan.Magazines(slot)) do
                    if (tonumber(e.item.data.was_gun) or 0) == 1 then spare = e break end
                end
                if spare then
                    local x, y = PDTI.FindFreeSpace(c, { item_id = spare.item.item_id, data = spare.item.data }, false)
                    if x and PDTI.MoveItem(spare.container, spare.item.instance_id, c, x, y, false) then
                        PDTI.EditItems({ update = { { container = c, instance_id = spare.item.instance_id,
                            data = { was_gun = 0 } } } })
                    end
                    changed = true
                elseif not filled_kinds(slot)[tostring(kind)] then
                    fill_gun(slot, info, Plan.GunSpec(slot))
                    changed = true
                end
            end
        elseif info and keep > 0 then
            -- Its magazine is settled (put in by hand, or an older plan's).
            if hd and hd.gun_set ~= 1 then update_item(hand, { gun_set = 1, gun_n = 0, gun_weight = 0 })
            elseif not hd then mark_filled(slot, kind) end
        end
    end
    return changed
end

-- May this magazine go into a slot's magazine box? Only one of the weapon
-- in that slot (inventory.lua asks).
function PDTI.GunSlotAccepts(slot, data)
    local Ammo = PDTI.Ammo
    if PDTI.InHeist and PDTI.InHeist() then
        local wep = Ammo.WeaponInSlot and Ammo.WeaponInSlot(slot)
        if not wep then
            -- (No player to ask: the magazine's own slot decides.)
            if data.slot == slot then return true end
            return false, "only a magazine of this weapon goes here"
        end
        local ok, info = pcall(Ammo.Identify, wep)
        if not ok or not info then return false, "no weapon in this slot" end
        if data.queue_key == info.key or kind_of(data) == info.weapon then return true end
        return false, "only a magazine of this weapon goes here"
    end
    local kind = slot_kind(slot)
    if not kind then return false, "no weapon in this slot" end
    if kind_of(data) ~= kind then return false, "only a magazine of this weapon goes here" end
    return true
end

-- How many magazines a weapon gets by default (the game's reserve, less the
-- magazine in the gun).
function Plan.DefaultMagazines(info)
    local per_gun = info.akimbo and 2 or 1
    local full = info.capacity * per_gun
    local n = 2
    if info.ammo_max and full > 0 then n = math.max(1, math.floor(info.ammo_max / full) - 1) end
    return math.min(Plan.DEFAULT_MAX_MAGS, n * per_gun)
end

-- Fills in a first plan from the game's starting ammunition.
function Plan.Defaults()
    local any = false
    for _, slot in ipairs(Plan.SLOTS) do
        local info = Plan.Info(slot)
        if info then
            any = true
            if info.loose_fed then
                add_loose(info, math.min(Plan.DEFAULT_MAX_LOOSE, info.ammo_max or (info.capacity * 4)))
            else
                -- The magazine in the gun (one per gun), then the spares.
                if #Plan.GunMagazines(slot) == 0 then fill_gun(slot, info, Plan.PickSpec(slot)) end
                for _ = 1, Plan.DefaultMagazines(info) do
                    if not add_auto(PDTI.Ammo.MAGAZINE_ITEM, 1, mag_data(info, Plan.PickSpec(slot))) then break end
                end
            end
        end
    end
    -- Without the menu's weapons nothing is decided yet.
    if any then PDTI.SetAmmoPlanned(true) end
    return any
end

local function same(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then return false end
    end
    return true
end

-- In the menu: each weapon's ammunition keeps the shape of its own weapon
-- (the real magazine size, once a heist learned it). Changing the weapon in
-- a slot changes none of it: it stays its weapon's. A weapon loaded round by
-- round gets the rounds of its magazines as loose rounds.
function Plan.Refresh()
    if not PDTI.IsAmmoPlanned() then
        Plan.Defaults()
        Plan.SyncGunSlots()
        return
    end
    Plan.SyncGunSlots()
    local Ammo = PDTI.Ammo
    local kinds = {}
    for _, entry in ipairs(PDTI.FindItems(function(_, item)
        return (item.item_id == Ammo.MAGAZINE_ITEM or item.item_id == Ammo.LOOSE_ITEM) and kind_of(item.data) ~= nil
    end)) do
        kinds[kind_of(entry.item.data)] = true
    end
    for kind in pairs(kinds) do
        local info = Plan.KindInfo(kind)
        if info then
            local rounds = 0
            for _, entry in ipairs(all_magazines(kind)) do
                if info.loose_fed then
                    rounds = rounds + (tonumber(entry.item.data.capacity) or 0)
                    PDTI.RemoveItem(entry.container, entry.item.instance_id)
                else
                    local old = entry.item.data
                    local known = Ammo.HasLoad(old)
                    local want = mag_data(info, { size = old.size, bullet = old.bullet,
                        load = known and old.load or nil, rounds = known and old.rounds or nil })
                    want.was_gun = old.was_gun
                    -- (An older plan's never matches: it has no plan_weapon.)
                    if not same(want, old) or (not info.typed and old.size) then
                        local ok = PDTI.ReplaceItemData(entry.container, entry.item.instance_id, want, Plan.ORDER)
                        if not ok then
                            PDTI.RemoveItem(entry.container, entry.item.instance_id)
                            log(tostring(kind) .. ": a magazine of the new size had no room and was left out")
                        end
                    end
                end
            end
            if rounds > 0 then add_loose(info, rounds) end
            for _, entry in ipairs(loose_stacks(kind)) do
                local want = loose_data(info, entry.item.data.bullet)
                if not same(want, entry.item.data) or (not info.typed and entry.item.data.bullet) then
                    PDTI.ReplaceItemData(entry.container, entry.item.instance_id, want, Plan.ORDER)
                end
            end
        end
    end
end

--------------------------------------------------------------- the heist

-- The first use of a weapon in a heist: the magazines and loose rounds
-- chosen for its slot become its own, full.
function Plan.Bind(wep, info)
    local Ammo = PDTI.Ammo
    local slot = info and info.slot
    if not slot or PDTI.InSafehouse() then return false end
    -- A weapon is used: this is the heist, never saved (the plan stays as it
    -- was chosen).
    if not PDTI.session_only then PDTI.SetSessionOnly(true) end
    local names = Plan.ORDER
    local extra = 0
    local gun_mags = {}
    -- The ammunition of this kind of weapon (wherever it is).
    local kind = wep._name_id
    local box = Ammo.GUN_SLOTS[slot]
    for _, entry in ipairs(all_magazines(kind)) do
        if info.loose_fed then
            extra = extra + (tonumber(entry.item.data.capacity) or 0)
            PDTI.RemoveItem(entry.container, entry.item.instance_id)
        elseif entry.container == box then
            -- The magazine of the weapon's box goes into the gun. (Another
            -- box holds another kind of weapon's.)
            gun_mags[#gun_mags + 1] = entry.item.data
            PDTI.RemoveItem(entry.container, entry.item.instance_id)
        else
            local data = entry.item.data
            local spec = info.typed and { size = data.size, bullet = data.bullet, load = Ammo.LoadOf(data) } or nil
            local rounds = info.typed and (tonumber(data.rounds) or 0) or info.capacity
            local ok = PDTI.ReplaceItemData(entry.container, entry.item.instance_id,
                Ammo.MagazineData(info.key, rounds, info, spec), names)
            if not ok then
                PDTI.RemoveItem(entry.container, entry.item.instance_id)
                log(slot .. ": a magazine had no room at its real size")
            end
        end
    end
    for _, entry in ipairs(loose_stacks(kind)) do
        PDTI.ReplaceItemData(entry.container, entry.item.instance_id,
            Ammo.LooseData(info.key, info, entry.item.data.bullet), names)
    end
    if extra > 0 then Ammo.AddLooseKey(info.key, extra, info) end
    -- The magazine in the gun: the size and bullets chosen for it, full.
    local in_gun = info.loose_fed and info.capacity or (info.akimbo and 2 or 1) * info.capacity
    if info.typed and info.loose_fed then
        -- A shotgun tube: the shells the game put in are of the kind chosen
        -- for the gun (buckshot unless the plan says otherwise).
        local bullet = Ammo.SafeBullet(info, Plan.GunSpec(slot).bullet)
        Ammo.SetLoaded(wep, { bullet = bullet })
        Ammo.ApplyLoaded(wep)
    elseif info.typed then
        -- Each gun: the magazine of the weapon's slot, as it was packed, or
        -- (an empty slot) a full one of the older choice.
        local specs, rounds = {}, {}
        for i = 1, info.akimbo and 2 or 1 do
            local data = gun_mags[i]
            if data then
                specs[i] = { size = data.size, bullet = data.bullet, load = Ammo.LoadOf(data) }
                rounds[i] = math.max(0, math.floor(tonumber(data.rounds) or 0))
            else
                specs[i] = Plan.GunSpec(slot)
                rounds[i] = spec_cap(info, specs[i].size)
                specs[i].load = { { Ammo.SafeBullet(info, specs[i].bullet), rounds[i] } }
            end
            rounds[i] = math.min(rounds[i], spec_cap(info, specs[i].size))
        end
        Ammo.SetLoaded(wep, specs[1], specs[2])
        local cap = Ammo.LoadedSpec(wep).capacity
        local loaded = rounds[1]
        if info.akimbo then
            local both = Ammo.PairSpecs(wep)
            cap = both[1].capacity + both[2].capacity
            loaded = rounds[1] + rounds[2]
            wep._pdti_pair = { rounds[1], rounds[2] }
        end
        if wep.set_ammo_remaining_in_clip then
            wep:set_ammo_remaining_in_clip(loaded + Ammo.ChamberOf(wep))
        end
        Ammo.ApplyLoaded(wep)
        in_gun = cap
        wep._issr_mag_installed = { rounds = loaded }
    end
    -- The ammunition maximum takes in everything you brought.
    Ammo.plan_max = Ammo.plan_max or {}
    local carried = Ammo.LooseOfKey(info.key)
    for _, mag in ipairs(Ammo.AllMagazines(info.key)) do carried = carried + mag.rounds end
    Ammo.plan_max[info.key] = in_gun + carried
    if Ammo.NoReload(wep) then wep._pdti_synced = Ammo.LooseOfKey(info.key) end
    -- Your weapon's box was empty: what the weapon item holds (a weapon you
    -- emptied starts without a magazine).
    local hand = #gun_mags == 0 and hand_entry(slot) or nil
    if hand and hand.item.data.weapon_id == kind and Ammo.LoadGun then
        pcall(Ammo.LoadGun, wep, hand.item.data)
    end
    Ammo.MarkPanelDirty()
    return true
end

---------------------------------------------------------- opening the UI

-- Are we back in the menu after a heist in the same Lua state? (The game
-- normally reloads Lua between the two, which already does this.)
local function in_game_state()
    local utils = rawget(_G, "Utils")
    if type(utils) == "table" and type(utils.IsInGameState) == "function" then
        local ok, result = pcall(utils.IsInGameState, utils)
        if ok then return result == true end
    end
    return nil
end

-- Called when the inventory screen opens.
function PDTI.OnUIOpen()
    if PDTI.session_only and in_game_state() == false then
        PDTI.SetSessionOnly(false)
        PDTI.LoadProfile()
    end
    PDTI.EnsureProfile()
    if not PDTI.InHeist() then
        local ok, err = pcall(Plan.Refresh)
        if not ok then log("refresh failed: " .. tostring(err)) end
    end
end

-- The rows of the menu's "Bring" list.
-- The weapon slots by ammunition category (AR/SMG, shotgun, LMG, other),
-- each with its category: { slot, info, category }.
function Plan.SlotsByCategory()
    local Ammo = PDTI.Ammo
    local rank = {}
    for i, c in ipairs(Ammo.CATEGORY_ORDER) do rank[c] = i end
    local out = {}
    for i, slot in ipairs(Plan.SLOTS) do
        local info = Plan.Info(slot)
        if info then
            local cat = Ammo.AmmoCategory(info) or "other"
            out[#out + 1] = { slot = slot, info = info, category = cat, order = (rank[cat] or 9) * 10 + i }
        end
    end
    table.sort(out, function(a, b) return a.order < b.order end)
    return out
end

function Plan.Rows()
    local rows = {}
    local last_cat = nil
    for _, entry in ipairs(Plan.SlotsByCategory()) do
        local slot, info = entry.slot, entry.info
        -- A heading for each ammunition category.
        if entry.category ~= last_cat then
            last_cat = entry.category
            rows[#rows + 1] = { kind = "cat:" .. entry.category, category = entry.category,
                text = PDTI.Ammo.CATEGORY_NAMES[entry.category] .. " ammunition" }
        end
        if info then
            local tag = Plan.SLOT_TAGS[slot]
            local size = (info.exact and "" or "~") .. tostring(info.capacity)
            if info.typed then
                local Ammo = PDTI.Ammo
                if info.loose_fed then
                    -- A shotgun loaded shell by shell: only loose shells.
                    rows[#rows + 1] = { kind = "weapon:" .. slot, header = true, slot = slot, name = info.name,
                        text = info.name }
                else
                    local pick = Plan.PickSpec(slot)
                    local size_tag = info.sized and (Ammo.MAG_SIZES[Ammo.SizeId(pick.size)].short .. " ") or ""
                    rows[#rows + 1] = { kind = "mag:" .. slot, typed = true, slot = slot, sized = info.sized,
                        family = info.family, bullets = Ammo.BulletsFor(info),
                        text = string.format("%s mags x%d (+%s%d %s)", tag, #Plan.Magazines(slot),
                            size_tag, pick.rounds, Ammo.LoadTag(pick.load, pick.bullet, info.family)),
                        pick = pick, name = info.name }
                end
                for _, id in ipairs(Ammo.BulletsFor(info)) do
                    rows[#rows + 1] = { kind = "loose:" .. slot .. ":" .. id, bullet = id, family = info.family,
                        text = string.format("%s %s %d", tag, Ammo.BulletShort(id, info.family), Plan.LooseRounds(slot, id)),
                        name = info.name }
                end
            elseif not info.loose_fed then
                rows[#rows + 1] = { kind = "mag:" .. slot,
                    text = string.format("%s mags x%d (%s rds)", tag, #Plan.Magazines(slot), size),
                    name = info.name }
            end
            if not info.typed then
                rows[#rows + 1] = { kind = "loose:" .. slot,
                    text = string.format("%s loose %d (+%d)", tag, Plan.LooseRounds(slot), Plan.LooseStep(info)),
                    name = info.name }
            end
        end
    end
    for _, id in ipairs(Plan.Items()) do
        local def = PDTI.items[id]
        if def then
            rows[#rows + 1] = { kind = id, text = string.format("%s x%d  %s", def.name, Plan.Count(id),
                PDTI.Ammo.Money(PDTI.Ammo.UnitPrice(id))) }
        end
    end
    return rows
end
