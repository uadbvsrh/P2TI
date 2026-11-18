-- Weapon parts (0.38.0): the parts you buy are grid items ("weapon_part").
--
-- Scarface's market sells the parts a weapon takes (those the game lets
-- drop, of the DLC you own) at the game's price, changed every day. A
-- bought part goes into the locker. Drag a part onto a weapon to fit it:
-- the part it replaces, and any part the new one does not go with, come off
-- as items next to the weapon (a standard part of the weapon just goes, as
-- in the game). Right-click (or Shift+click) a weapon to see every part on
-- it, take one off (the weapon's own part of that kind comes back) or sell
-- the weapon.
--
-- In a heist (0.39.0) parts are changed too, timed (armory_hotmod.lua), but
-- not magazines, and not in the locker; selling waits for home. A part
-- carried into a heist that fails is lost, like the weapons (armory.lua); a
-- fitted part goes with its weapon.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Armory then return end

local Armory = PDTI.Armory
local Parts = PDTI.Parts or {}
PDTI.Parts = Parts

local log = PDTI.Logger("PDTI PARTS")

Parts.ITEM_ID = Armory.PART_ITEM_ID or "weapon_part"
Parts.SELL_SHARE = 0.5
-- A part's place in the grid and its weight (kg), by its type.
Parts.SIZES = {
    sight = { 1, 1, 0.3 }, gadget = { 1, 1, 0.2 }, grip = { 1, 1, 0.2 }, bonus = { 1, 1, 0 },
    barrel_ext = { 2, 1, 0.5 }, foregrip = { 2, 1, 0.4 }, vertical_grip = { 2, 1, 0.4 },
    stock = { 2, 1, 0.6 }, slide = { 2, 1, 0.4 },
    upper_reciever = { 2, 1, 0.6 }, lower_reciever = { 2, 1, 0.6 },
    barrel = { 3, 1, 0.8 }, magazine = { 1, 2, 0.4 }
}
Parts.DEFAULT_SIZE = { 1, 1, 0.2 }
-- The short word on a part's cell.
Parts.TAGS = {
    sight = "Sight", gadget = "Gadget", grip = "Grip", bonus = "Boost", barrel_ext = "Muzzle",
    foregrip = "Fore", vertical_grip = "VGrip", stock = "Stock", slide = "Slide",
    upper_reciever = "Upper", lower_reciever = "Lower", barrel = "Barrel", magazine = "Mag"
}
-- A weapon's slots, named, in the order the weapon view lists them (the
-- rest after these, by name).
Parts.TYPE_NAMES = {
    sight = "Sight", barrel = "Barrel", barrel_ext = "Muzzle", upper_reciever = "Upper receiver",
    lower_reciever = "Lower receiver", slide = "Slide", foregrip = "Handguard", vertical_grip = "Vertical grip",
    grip = "Grip", stock = "Stock", magazine = "Magazine", gadget = "Gadget", ammo = "Ammunition", bonus = "Boost",
    custom = "Custom", extra = "Extra", drag_handle = "Charging handle"
}
Parts.ORDER = { "sight", "barrel", "barrel_ext", "upper_reciever", "lower_reciever", "slide", "foregrip",
    "vertical_grip", "grip", "stock", "magazine", "gadget", "ammo", "bonus" }
-- Where a part that comes off a weapon goes when its weapon's place has no
-- room (or is a weapon slot).
Parts.PLACES = { "locker", "backpack", "rig", "rig_2", "rig_3" }

---------------------------------------------------------- the game's data

local function factory_part(part_id)
    local t = rawget(_G, "tweak_data")
    local parts = t and t.weapon and t.weapon.factory and t.weapon.factory.parts
    local p = type(parts) == "table" and type(part_id) == "string" and parts[part_id]
    return type(p) == "table" and p or nil
end

local function mod_tweak(part_id)
    local t = rawget(_G, "tweak_data")
    local mods = t and t.blackmarket and t.blackmarket.weapon_mods
    local m = type(mods) == "table" and type(part_id) == "string" and mods[part_id]
    return type(m) == "table" and m or nil
end

local function factory()
    local m = rawget(_G, "managers")
    return m and m.weapon_factory or nil
end

local function copy(list)
    local out = {}
    for i, v in ipairs(list or {}) do out[i] = v end
    return out
end

local function set_of(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

function Parts.Type(part_id)
    local p = factory_part(part_id)
    return p and type(p.type) == "string" and p.type or nil
end

function Parts.Name(part_id)
    local p, m = factory_part(part_id), mod_tweak(part_id)
    local name_id = (p and p.name_id) or (m and m.name_id)
    if name_id then
        local ok, text = pcall(function() return managers.localization:text(name_id) end)
        if ok and type(text) == "string" and text ~= "" and not text:find("ERROR") then return text end
    end
    return tostring(part_id)
end

local function dlc_owned(dlc)
    local ok, yes = pcall(function() return managers.dlc:is_dlc_unlocked(dlc) end)
    return ok and yes == true
end

-- The game's global value of a part you may have: "normal", "infamous" or
-- the DLC it comes with. Nil for a DLC part whose DLC you do not own.
function Parts.GlobalValue(part_id)
    local m = mod_tweak(part_id)
    if not m then return nil end
    if m.infamous then return "infamous" end
    local dlcs = {}
    for _, d in ipairs(type(m.dlcs) == "table" and m.dlcs or {}) do dlcs[#dlcs + 1] = d end
    if m.dlc then dlcs[#dlcs + 1] = m.dlc end
    if #dlcs == 0 then return "normal" end
    for _, d in ipairs(dlcs) do
        if dlc_owned(d) then return d end
    end
    return nil
end

-- Is this part a thing you can have as an item? The game's rule for a part
-- that drops (it has a drop value, it is not hidden, not an achievement's),
-- and not an ammunition part (the ammunition system owns shells).
function Parts.Buyable(part_id)
    local p, m = factory_part(part_id), mod_tweak(part_id)
    if not p or not m then return false end
    if p.unatainable or m.is_a_unlockable or p.type == "ammo" then return false end
    return m.pc ~= nil or (type(m.pcs) == "table" and #m.pcs > 0)
end

-- The parts the game lets a weapon take: { [type] = { part_id, ... } }.
local function weapon_parts(weapon_id)
    local f = factory()
    if not f or type(weapon_id) ~= "string" then return {} end
    local ok, lists = pcall(function() return f:get_parts_from_weapon_id(weapon_id) end)
    return ok and type(lists) == "table" and lists or {}
end

-- Does the weapon take this part (the game's list for the part's type)?
function Parts.Takes(weapon_id, part_id)
    local list = weapon_parts(weapon_id)[Parts.Type(part_id) or ""]
    if type(list) ~= "table" then return false end
    for _, p in ipairs(list) do
        if p == part_id then return true end
    end
    return false
end

-- Assault rifles and SMGs: PDTI's own magazine sizes replace the game's
-- magazine parts (plan.lua), so those are not sold.
local function own_magazines(weapon_id)
    local P = PDTI.Plan
    if not P or not P.InfoFor then return false end
    local ok, info = pcall(P.InfoFor, weapon_id, nil, nil)
    return ok and type(info) == "table" and info.sized == true
end

------------------------------------------------------------------ prices

-- The game's price of a part for this weapon (its kind changes the price).
function Parts.NormalPrice(weapon_id, part_id, gv)
    gv = gv or Parts.GlobalValue(part_id) or "normal"
    local ok, v = pcall(function() return managers.money:get_weapon_modify_price(weapon_id, part_id, gv) end)
    return ok and math.max(0, math.floor(tonumber(v) or 0)) or 0
end

-- Today's price: each part has its own change of the day.
function Parts.Price(weapon_id, part_id, gv)
    return math.floor(Parts.NormalPrice(weapon_id, part_id, gv) * Armory.Factor(part_id) + 0.5)
end

-- The parts on sale for a weapon, by type, then price.
function Parts.ForWeapon(weapon_id)
    local rows = {}
    local fid = Armory.FactoryId(weapon_id)
    if not fid then return rows end
    local default = set_of(Armory.DefaultBlueprint(fid))
    local no_mags = own_magazines(weapon_id)
    local seen = {}
    for _, list in pairs(weapon_parts(weapon_id)) do
        for _, part_id in ipairs(type(list) == "table" and list or {}) do
            local ptype = Parts.Type(part_id)
            local gv = not seen[part_id] and not default[part_id] and Parts.Buyable(part_id)
                and not (no_mags and ptype == "magazine") and Parts.GlobalValue(part_id)
            if gv then
                seen[part_id] = true
                rows[#rows + 1] = {
                    part_id = part_id, ptype = ptype, name = Parts.Name(part_id), global_value = gv,
                    normal = Parts.NormalPrice(weapon_id, part_id, gv), today = Parts.Price(weapon_id, part_id, gv),
                    factor = Armory.Factor(part_id)
                }
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.ptype ~= b.ptype then return a.ptype < b.ptype end
        if a.today ~= b.today then return a.today < b.today end
        return a.part_id < b.part_id
    end)
    return rows
end

------------------------------------------------------------- part items

function Parts.Size(ptype)
    local s = Parts.SIZES[ptype] or Parts.DEFAULT_SIZE
    return s[1], s[2], s[3]
end

-- A part item's data (flat). for_weapon: the weapon it was bought for or
-- taken off (its price is that weapon's).
function Parts.MakeData(part_id, for_weapon, uid)
    local ptype = Parts.Type(part_id) or "custom"
    local w, h, kg = Parts.Size(ptype)
    return {
        uid = uid, part_id = part_id, ptype = ptype, name = Parts.Name(part_id), for_weapon = for_weapon,
        global_value = Parts.GlobalValue(part_id) or "normal", w = w, h = h, weight = kg
    }
end

-- The short word for a part's type (its cell).
function Parts.Tag(ptype)
    local t = Parts.TAGS[ptype]
    if t then return t end
    local s = tostring(ptype or "Part"):gsub("_", "")
    return s:sub(1, 1):upper() .. s:sub(2, 6)
end

-- Buys one of a weapon's parts: it goes into the locker.
function Parts.Buy(weapon_id, part_id)
    if not Armory.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if Armory.InHeist() then return false, "the market is closed during a heist" end
    local row = nil
    for _, r in ipairs(Parts.ForWeapon(weapon_id)) do
        if r.part_id == part_id then row = r break end
    end
    if not row then return false, "not a part for sale for this weapon" end
    local data = Parts.MakeData(part_id, weapon_id, nil)
    data.global_value = row.global_value
    if PDTI.FindFreeSpace("locker", { item_id = Parts.ITEM_ID, data = data }, true) == nil then
        return false, "your locker is full"
    end
    if not Armory.Take(row.today) then return false, "not enough money" end
    data.uid = Armory.NewUid()
    if not PDTI.AddItemAuto("locker", Parts.ITEM_ID, 1, data, true) then
        Armory.Give(row.today)
        return false, "your locker is full"
    end
    Armory.Save()
    log(string.format("bought %s for %s: %d", part_id, tostring(weapon_id), row.today))
    return true, data
end

---------------------------------------------------- fitting, taking off

-- Selling waits for home (the menu or the safehouse).
local function at_home()
    if Armory.InHeist() then return false, "things are sold at home (the menu or the safehouse)" end
    return true
end

-- Parts change in a heist too (0.39.0: armory_hotmod.lua times it), but
-- not magazines: they size the magazines you carry.
local function changeable(part_id)
    if Armory.InHeist() and Parts.Type(part_id) == "magazine" then return false, "magazines are changed at home" end
    return true
end

-- Can this place be used now? In a heist the locker stays at home.
function Parts.Reachable(c)
    if Armory.InHeist() and c == "locker" then return false, "the locker stays at home" end
    return true
end

-- The build after a change, and the parts that come off it as items (a
-- standard part of the weapon, or one that is no item, just goes).
local function change(weapon_data, part_id, remove)
    local fid, f = weapon_data.factory_id, factory()
    if not f or type(fid) ~= "string" then return nil end
    local old = Armory.SplitBlueprint(weapon_data.blueprint)
    local new = copy(old)
    local ok = pcall(function() f:change_part_blueprint_only(fid, part_id, new, remove or nil) end)
    if not ok then return nil end
    local keep, default = set_of(new), set_of(Armory.DefaultBlueprint(fid))
    local off = {}
    for _, p in ipairs(old) do
        if not keep[p] and not default[p] and Parts.Buyable(p) then off[#off + 1] = p end
    end
    return new, off
end

local function weapon_name(d)
    return tostring(d.name or d.weapon_id)
end

local function names(list)
    local out = {}
    for i, p in ipairs(list) do out[i] = Parts.Name(p) end
    return table.concat(out, ", ")
end

-- Can this part go onto this weapon? ok, why, then the parts that would
-- come off and the new build.
function Parts.CanFit(part_data, weapon_data)
    if type(part_data) ~= "table" or type(weapon_data) ~= "table" then return false, "not a part" end
    local part_id = part_data.part_id
    local can, why = changeable(part_id)
    if not can then return false, why end
    if not Parts.Takes(weapon_data.weapon_id, part_id) then
        return false, string.format("the %s does not fit the %s", Parts.Name(part_id), weapon_name(weapon_data))
    end
    local bp = Armory.SplitBlueprint(weapon_data.blueprint)
    if set_of(bp)[part_id] then return false, "the " .. weapon_name(weapon_data) .. " has it already" end
    local ok, blocker = pcall(function() return factory():can_add_part(weapon_data.factory_id, part_id, bp) end)
    if ok and type(blocker) == "string" then
        return false, string.format("take the %s off the %s first", Parts.Name(blocker), weapon_name(weapon_data))
    end
    -- (The weapon takes it and nothing fitted forbids it: the game fits it.)
    local new, off = change(weapon_data, part_id)
    if not new then return false, "the game does not fit it" end
    return true, nil, off, new
end

-- Puts the parts that came off next to their weapon (its place, then the
-- locker, the backpack, the rig; in a heist not the locker). All or none:
-- false when one has no room.
local function place_off(off, near, weapon_id)
    local places = {}
    if near and not PDTI.HAND_SLOTS[near] and not PDTI.GUN_SLOTS[near] then places[1] = near end
    for _, c in ipairs(Parts.PLACES) do
        if c ~= near and Parts.Reachable(c) then places[#places + 1] = c end
    end
    local added = {}
    for _, part_id in ipairs(off) do
        local data = Parts.MakeData(part_id, weapon_id, Armory.NewUid())
        local put = nil
        for _, c in ipairs(places) do
            local ok, item = PDTI.AddItemAuto(c, Parts.ITEM_ID, 1, data, true)
            if ok then put = { c, item.instance_id } break end
        end
        if not put then
            for _, a in ipairs(added) do PDTI.RemoveItem(a[1], a[2]) end
            return false, "no room for the " .. Parts.Name(part_id) .. " that comes off"
        end
        added[#added + 1] = put
    end
    return true
end

-- The weapon's new build: its weight follows, and so does its loaded
-- magazine (a magazine part). In your hands: the game's slot, and in the
-- safehouse the gun you hold, made again at once (Armory.ApplyHands).
local function set_build(c, iid, d, bp)
    PDTI.EditItems({ update = { { container = c, instance_id = iid, data = {
        blueprint = Armory.JoinBlueprint(bp), weight = Armory.Weight(d.weapon_id, d.factory_id, bp) } } } })
    if PDTI.Plan and PDTI.Plan.ReshapeStored then pcall(PDTI.Plan.ReshapeStored, d.uid) end
    if PDTI.HAND_SLOTS[c] then
        pcall(Armory.SyncEquipped)
        pcall(Armory.ApplyHands)
    end
end
Parts.SetBuild = set_build

-- Can the part item go onto the weapon item now? ok, why, then the part,
-- the weapon, the parts that would come off and the new build.
function Parts.CheckFit(part_c, part_iid, weapon_c, weapon_iid)
    local part, weapon = PDTI.FindItem(part_c, part_iid), PDTI.FindItem(weapon_c, weapon_iid)
    if not part or part.item_id ~= Parts.ITEM_ID or type(part.data) ~= "table" then return false, "no such part" end
    if not weapon or weapon.item_id ~= Armory.ITEM_ID or type(weapon.data) ~= "table" then return false, "no such weapon" end
    local here, there = Parts.Reachable(part_c)
    if here then here, there = Parts.Reachable(weapon_c) end
    if not here then return false, there end
    local ok, why, off, new = Parts.CanFit(part.data, weapon.data)
    if not ok then return false, why end
    return true, nil, part, weapon, off, new
end

-- Fits the part item onto the weapon item.
function Parts.Fit(part_c, part_iid, weapon_c, weapon_iid)
    local ok, why, part, weapon, off, new = Parts.CheckFit(part_c, part_iid, weapon_c, weapon_iid)
    if not ok then return false, why end
    -- The part leaves its place first: a part that comes off may take it.
    if not PDTI.RemoveItem(part_c, part_iid) then return false, "the part could not be taken" end
    local placed, reason = place_off(off, weapon_c, weapon.data.weapon_id)
    if not placed then
        PDTI.AddItem(part_c, Parts.ITEM_ID, part.x, part.y, part.rotated == true, 1, part.data)
        return false, reason
    end
    set_build(weapon_c, weapon_iid, weapon.data, new)
    log(string.format("fitted %s to %s", tostring(part.data.part_id), tostring(weapon.data.weapon_id)))
    local text = string.format("The %s is on the %s", Parts.Name(part.data.part_id), weapon_name(weapon.data))
    if #off > 0 then text = text .. "; off: " .. names(off) end
    return true, text
end

-- A slot's name ("Muzzle"; an unknown one from its id).
function Parts.TypeName(ptype)
    local n = Parts.TYPE_NAMES[ptype]
    if n then return n end
    local s = tostring(ptype or "part"):gsub("_", " ")
    return s:sub(1, 1):upper() .. s:sub(2)
end

local function type_rank(ptype)
    for i, t in ipairs(Parts.ORDER) do
        if t == ptype then return i end
    end
    return #Parts.ORDER + 1
end

local function by_slot(a, b)
    local ra, rb = type_rank(a.ptype), type_rank(b.ptype)
    if ra ~= rb then return ra < rb end
    if a.ptype ~= b.ptype then return a.ptype < b.ptype end
    return (a.part_id or "") < (b.part_id or "")
end

-- Is there a name for this part (the game's own text)? Nil when not: many
-- of a weapon's own parts have none.
function Parts.KnownName(part_id)
    local n = Parts.Name(part_id)
    return n ~= tostring(part_id) and n or nil
end

-- Every part on a weapon (the weapon view), by slot: { part_id, ptype,
-- name (nil without one), standard (the weapon's own), removable }.
function Parts.OnWeapon(weapon_data)
    local out = {}
    if type(weapon_data) ~= "table" then return out end
    local default = set_of(Armory.DefaultBlueprint(weapon_data.factory_id))
    for _, p in ipairs(Armory.SplitBlueprint(weapon_data.blueprint)) do
        local standard = default[p] == true
        out[#out + 1] = { part_id = p, ptype = Parts.Type(p) or "custom", name = Parts.KnownName(p),
            standard = standard, removable = not standard and Parts.Buyable(p) }
    end
    table.sort(out, by_slot)
    return out
end

-- The weapon's slots (the weapon view), in order: one for each part on it
-- (as Parts.OnWeapon) and one for each kind of part for sale it has none of
-- ({ ptype } alone: an empty slot).
function Parts.Slots(weapon_data)
    local out = Parts.OnWeapon(weapon_data)
    if type(weapon_data) ~= "table" then return out end
    local taken = {}
    for _, s in ipairs(out) do taken[s.ptype] = true end
    for _, r in ipairs(Parts.ForWeapon(weapon_data.weapon_id)) do
        if not taken[r.ptype] then
            taken[r.ptype] = true
            out[#out + 1] = { ptype = r.ptype }
        end
    end
    table.sort(out, by_slot)
    return out
end

-- The game's concealment of a weapon's build, or nil.
function Parts.Concealment(weapon_data)
    if type(weapon_data) ~= "table" then return nil end
    local ok, v = pcall(function()
        return managers.blackmarket:_calculate_weapon_concealment({ factory_id = weapon_data.factory_id,
            weapon_id = weapon_data.weapon_id, blueprint = Armory.SplitBlueprint(weapon_data.blueprint) })
    end)
    return ok and tonumber(v) or nil
end

-- The parts on a weapon beyond its own: { part_id, ptype, name, removable }.
function Parts.Fitted(weapon_data)
    local out = {}
    if type(weapon_data) ~= "table" then return out end
    local default = set_of(Armory.DefaultBlueprint(weapon_data.factory_id))
    for _, p in ipairs(Armory.SplitBlueprint(weapon_data.blueprint)) do
        if not default[p] then
            out[#out + 1] = { part_id = p, ptype = Parts.Type(p) or "?", name = Parts.Name(p), removable = Parts.Buyable(p) }
        end
    end
    return out
end

-- Can this part come off? The weapon's own part of that type comes back (or
-- none, when it has none). ok, why, then the parts that come off (this one
-- with them) and the new build.
function Parts.CanTakeOff(weapon_data, part_id)
    local can, why = changeable(part_id)
    if not can then return false, why end
    if type(weapon_data) ~= "table" then return false, "no such weapon" end
    if not set_of(Armory.SplitBlueprint(weapon_data.blueprint))[part_id] then return false, "it is not on the weapon" end
    local default = Armory.DefaultBlueprint(weapon_data.factory_id)
    if set_of(default)[part_id] then return false, "it is the weapon's own part" end
    if not Parts.Buyable(part_id) then return false, "it comes with the weapon" end
    local ptype, back = Parts.Type(part_id), nil
    for _, p in ipairs(default) do
        if Parts.Type(p) == ptype then back = p break end
    end
    local new, off
    if back then new, off = change(weapon_data, back) else new, off = change(weapon_data, part_id, true) end
    if not new then return false, "the game does not take it off" end
    return true, nil, off, new
end

-- Takes a part off a weapon item. It goes next to the weapon, or to this
-- place (to_c at x, y: dragged out of its slot in the weapon view); any
-- other part that comes off goes next to the weapon. All or nothing.
-- Can this part come off the weapon item now (to_c: where it would go)?
-- ok, why, then the weapon, the parts that come off and the new build.
function Parts.CheckTakeOff(weapon_c, weapon_iid, part_id, to_c)
    local weapon = PDTI.FindItem(weapon_c, weapon_iid)
    if not weapon or weapon.item_id ~= Armory.ITEM_ID or type(weapon.data) ~= "table" then return false, "no such weapon" end
    local here, there = Parts.Reachable(weapon_c)
    if here and to_c then here, there = Parts.Reachable(to_c) end
    if not here then return false, there end
    local ok, why, off, new = Parts.CanTakeOff(weapon.data, part_id)
    if not ok then return false, why end
    return true, nil, weapon, off, new
end

function Parts.TakeOff(weapon_c, weapon_iid, part_id, to_c, x, y, rotated)
    local ok, why, weapon, off, new = Parts.CheckTakeOff(weapon_c, weapon_iid, part_id, to_c)
    if not ok then return false, why end
    local d, put, rest = weapon.data, nil, off
    if to_c then
        local added, item = PDTI.AddItem(to_c, Parts.ITEM_ID, x, y, rotated == true, 1,
            Parts.MakeData(part_id, d.weapon_id, Armory.NewUid()))
        if not added then return false, item end
        put, rest = item, {}
        for _, p in ipairs(off) do
            if p ~= part_id then rest[#rest + 1] = p end
        end
    end
    local placed, reason = place_off(rest, weapon_c, d.weapon_id)
    if not placed then
        if put then PDTI.RemoveItem(to_c, put.instance_id) end
        return false, reason
    end
    set_build(weapon_c, weapon_iid, d, new)
    log(string.format("took %s off %s", tostring(part_id), tostring(d.weapon_id)))
    return true, "Off the " .. weapon_name(d) .. ": " .. names(off)
end

-- Your weapons that take this part (their names).
function Parts.FitsYours(part_id)
    local out = {}
    for _, w in ipairs(Armory.Weapons()) do
        if Parts.Takes(w.data.weapon_id, part_id) then out[#out + 1] = weapon_name(w.data) end
    end
    return out
end

------------------------------------------------------------------ selling

-- What selling this item pays: half of today's price (a weapon with the
-- parts on it beyond its own). (A free weapon is not sold: Parts.Sell.)
function Parts.SellPrice(item)
    if type(item) ~= "table" or type(item.data) ~= "table" then return 0 end
    local d = item.data
    local total = 0
    if item.item_id == Parts.ITEM_ID then
        total = Parts.Price(d.for_weapon, d.part_id, d.global_value)
    elseif item.item_id == Armory.ITEM_ID then
        total = Armory.TodayPrice(d.weapon_id)
        for _, f in ipairs(Parts.Fitted(d)) do
            if f.removable then total = total + Parts.Price(d.weapon_id, f.part_id) end
        end
    end
    return math.floor(total * Parts.SELL_SHARE + 0.5)
end

-- Sells a weapon or part item (in the menu or the safehouse). A weapon's
-- loaded magazine is paid back as the Bring list pays one back.
function Parts.Sell(c, iid)
    if not Armory.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    local home, why = at_home()
    if not home then return false, why end
    local item = PDTI.FindItem(c, iid)
    if not item or type(item.data) ~= "table" or (item.item_id ~= Parts.ITEM_ID and item.item_id ~= Armory.ITEM_ID) then
        return false, "nothing to sell"
    end
    local weapon = item.item_id == Armory.ITEM_ID
    if weapon and item.data.free then return false, "a free weapon sells for nothing: throw it away instead" end
    local price = Parts.SellPrice(item)
    if not PDTI.RemoveItem(c, iid) then return false, "it could not be sold" end
    local back = 0
    if weapon and PDTI.Plan and PDTI.Plan.SellMagazines then
        local ok, n = pcall(PDTI.Plan.SellMagazines, item.data)
        back = ok and tonumber(n) or 0
    end
    Armory.Give(price)
    if weapon and PDTI.HAND_SLOTS[c] then pcall(Armory.SyncEquipped) end
    Armory.Save()
    local name = weapon and weapon_name(item.data) or Parts.Name(item.data.part_id)
    log(string.format("sold %s for %d", name, price))
    local text = "Sold the " .. name .. " for " .. PDTI.Ammo.Money(price)
    if back > 0 then text = text .. " (its magazine: " .. PDTI.Ammo.Money(back) .. " back)" end
    return true, text
end
