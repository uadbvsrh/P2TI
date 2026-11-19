-- Weapon skins (0.49.0). A weapon of yours can wear a skin or a weapon colour
-- you own in the game (its Steam inventory copies, and the colours it
-- unlocked). Sydney, in the safehouse, changes them: her room's menu opens
-- the skins screen (your weapons, then the skins each one takes).
--
--   * Any number of your guns can wear the same skin.
--   * The skin is kept on the weapon item (skin_id, skin_iid, skin_quality,
--     skin_bonus, skin_color): the game's weapon slot and the gun in your
--     hands get it as the game's cosmetics (armory.lua), so other players
--     see it, and a StatBoost works as in the game.
--   * A legendary skin brings its own parts: the parts you fitted come off
--     (next to the weapon, the locker, the backpack, the rig: all or none),
--     the skin's parts go on, free (not in the price), and a locked one takes
--     no other part while it is on. Removed, the gun gets its own parts back.
--   * A lost weapon loses nothing of the skin (it is the game's item); an
--     insured one comes back with it. A skin you no longer own (sold) comes
--     off at the menu, as the game does.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Armory or not PDTI.Parts then return end

local Armory, Parts = PDTI.Armory, PDTI.Parts
local Skins = PDTI.WeaponSkins or {}
PDTI.WeaponSkins = Skins

local log = PDTI.Logger("PDTI SKINS")

Skins.FIELDS = { "skin_id", "skin_iid", "skin_quality", "skin_bonus", "skin_color" }
-- The game's qualities, best first.
Skins.QUALITIES = { "mint", "fine", "general", "worn", "poor" }
Skins.QUALITY_NAMES = { mint = "Mint-Condition", fine = "Lightly-Marked", general = "Broken-In", worn = "Well-Used",
    poor = "Battle-Worn" }

function Skins.Enabled() return Armory.Enabled() end

local function bm() local m = rawget(_G, "managers"); return m and m.blackmarket end

function Skins.Tweak(skin_id)
    local td = rawget(_G, "tweak_data")
    local all = td and td.blackmarket and td.blackmarket.weapon_skins
    local t = type(skin_id) == "string" and type(all) == "table" and all[skin_id]
    return type(t) == "table" and t or nil
end

local function text(id)
    local m = rawget(_G, "managers")
    if type(id) ~= "string" or not m or not m.localization then return nil end
    local ok, v = pcall(function() return m.localization:text(id) end)
    return ok and type(v) == "string" and v or nil
end

function Skins.Name(skin_id)
    local t = Skins.Tweak(skin_id)
    return t and text(t.name_id) or tostring(skin_id)
end

local function set_of(list)
    local out = {}
    for _, v in ipairs(list or {}) do out[v] = true end
    return out
end

-- The skin's own parts (a legendary skin), or nil.
function Skins.Blueprint(skin_id)
    local t = Skins.Tweak(skin_id)
    return t and type(t.default_blueprint) == "table" and #t.default_blueprint > 0 and t.default_blueprint or nil
end

function Skins.Locked(skin_id)
    local t = Skins.Tweak(skin_id)
    return t ~= nil and t.locked == true
end

-- The build without the skin's own parts (they are free).
function Skins.WithoutSkinParts(skin_id, bp)
    local own = set_of(Skins.Blueprint(skin_id))
    local out = {}
    for _, p in ipairs(bp or {}) do
        if not own[p] then out[#out + 1] = p end
    end
    return out
end

-- Does the game let this skin go on this weapon?
local function fits(weapon_id, skin_id)
    local b = bm()
    local ok, v = pcall(function() return b:weapon_cosmetics_type_check(weapon_id, skin_id) end)
    return ok and v == true
end

-- A skin with no Steam copy (a weapon colour, an unlocked skin): owned when
-- the game says you have it.
local function unlocked(skin_id, t)
    if not t.is_a_unlockable and not t.is_a_color_skin then return false end
    local b, m = bm(), rawget(_G, "managers")
    local ok, has = pcall(function()
        if t.dlc and not m.dlc:is_dlc_unlocked(t.dlc) then return false end
        local gv = t.global_value or (t.dlc and m.dlc:dlc_to_global_value(t.dlc)) or "normal"
        return b:has_item(gv, "weapon_skins", skin_id)
    end)
    return ok and has == true
end

local function rank(q)
    for i, v in ipairs(Skins.QUALITIES) do
        if v == q then return i end
    end
    return #Skins.QUALITIES + 1
end

local function tradables()
    local b = bm()
    local ok, list = pcall(function() return b:get_inventory_tradable() end)
    return ok and type(list) == "table" and list or nil
end

-- The skins you own that this weapon takes, one per skin (your best copy:
-- a StatBoost first, then the best quality), by name:
-- { id, iid, quality, bonus, color, name, legendary, locked }.
function Skins.Owned(weapon_id)
    local best = {}
    for iid, item in pairs(tradables() or {}) do
        local id = type(item) == "table" and item.category == "weapon_skins" and item.entry
        if Skins.Tweak(id) and fits(weapon_id, id) then
            local e = { id = id, iid = iid, quality = item.quality or "mint", bonus = item.bonus and true or false }
            local cur = best[id]
            if not cur or (e.bonus and not cur.bonus)
                or (e.bonus == cur.bonus and rank(e.quality) < rank(cur.quality)) then
                best[id] = e
            end
        end
    end
    local td = rawget(_G, "tweak_data")
    for id, t in pairs(td.blackmarket.weapon_skins or {}) do
        if not best[id] and type(t) == "table" and fits(weapon_id, id) and unlocked(id, t) then
            best[id] = { id = id, iid = id, quality = "mint", bonus = false, color = t.is_a_color_skin and 1 or nil }
        end
    end
    local out = {}
    for id, e in pairs(best) do
        e.name = Skins.Name(id)
        e.legendary = Skins.Blueprint(id) ~= nil
        e.locked = Skins.Locked(id)
        out[#out + 1] = e
    end
    table.sort(out, function(a, c)
        if a.name ~= c.name then return a.name < c.name end
        return a.id < c.id
    end)
    return out
end

-- "Golden Grip (Mint-Condition, StatBoost)".
function Skins.Label(e)
    if type(e) ~= "table" or not e.id then return "none" end
    local extra = {}
    if e.color then extra[#extra + 1] = "colour"
    else extra[#extra + 1] = Skins.QUALITY_NAMES[e.quality] or tostring(e.quality) end
    if e.bonus then extra[#extra + 1] = "StatBoost" end
    if e.legendary then extra[#extra + 1] = "legendary" end
    return Skins.Name(e.id) .. " (" .. table.concat(extra, ", ") .. ")"
end

-- The skin a weapon item wears, as Skins.Owned's entries, or nil.
function Skins.Of(d)
    if type(d) ~= "table" or type(d.skin_id) ~= "string" then return nil end
    return { id = d.skin_id, iid = d.skin_iid, quality = d.skin_quality, bonus = d.skin_bonus == true,
        color = tonumber(d.skin_color), legendary = Skins.Blueprint(d.skin_id) ~= nil }
end

------------------------------------------------------------ changing it

local function at_home()
    if not Skins.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if Armory.InHeist() then return false, "skins are changed at home (Sydney, in the safehouse)" end
    return true
end

local function weapon_item(c, iid)
    local item = PDTI.FindItem(c, iid)
    if not item or item.item_id ~= Armory.ITEM_ID or type(item.data) ~= "table" then return nil end
    return item
end

local function name_of(d) return tostring(d.name or d.weapon_id) end

-- The build after the skin changes (nil: the parts do not change), and the
-- parts of yours that come off. A legendary skin coming on: its own parts,
-- yours come off. One coming off: the weapon's own parts, plus what you
-- fitted beside the skin's.
local function new_build(d, skin_id)
    local skin_bp = skin_id and Skins.Blueprint(skin_id)
    local old_bp = d.skin_id and Skins.Blueprint(d.skin_id)
    if not skin_bp and not old_bp then return nil, {} end
    local bp = Armory.SplitBlueprint(d.blueprint)
    local default, old_own = set_of(Armory.DefaultBlueprint(d.factory_id)), set_of(old_bp)
    local yours = {}
    for _, p in ipairs(bp) do
        if not default[p] and not old_own[p] and Parts.Buyable(p) then yours[#yours + 1] = p end
    end
    if skin_bp then return { unpack(skin_bp) }, yours end
    local new = Armory.DefaultBlueprint(d.factory_id)
    for _, p in ipairs(yours) do new[#new + 1] = p end
    return new, {}
end
Skins._NewBuild = new_build

local function set_skin(c, iid, fields)
    local data = {}
    for _, k in ipairs(Skins.FIELDS) do
        local v = fields[k]
        if v == nil then v = false end
        data[k] = v
    end
    PDTI.EditItems({ update = { { container = c, instance_id = iid, data = data } } })
end

-- The game's slot and the gun in your hands follow (a new build does it in
-- armory_parts.lua's set_build).
local function follow(c, iid, new)
    if new then
        Parts.SetBuild(c, iid, weapon_item(c, iid).data, new)
    elseif PDTI.HAND_SLOTS[c] then
        pcall(Armory.SyncEquipped)
        pcall(Armory.ApplyHands)
    end
end

-- Puts a skin you own (its id) on the weapon item.
function Skins.Apply(c, iid, skin_id)
    local home, why = at_home()
    if not home then return false, why end
    local item = weapon_item(c, iid)
    if not item then return false, "no such weapon" end
    local d = item.data
    local e = nil
    for _, o in ipairs(Skins.Owned(d.weapon_id)) do
        if o.id == skin_id then e = o break end
    end
    if not e then return false, "you do not own that skin for the " .. name_of(d) end
    if d.skin_id == e.id and d.skin_iid == e.iid then return false, "it wears that skin already" end
    local new, off = new_build(d, e.id)
    if #off > 0 then
        local placed, reason = Parts.PlaceOff(off, c, d.weapon_id)
        if not placed then return false, reason end
    end
    set_skin(c, iid, { skin_id = e.id, skin_iid = e.iid, skin_quality = e.quality, skin_bonus = e.bonus,
        skin_color = e.color })
    follow(c, iid, new)
    log(string.format("%s on the %s (uid %s)", e.id, tostring(d.weapon_id), tostring(d.uid)))
    local text = "The " .. name_of(d) .. " wears " .. Skins.Label(e)
    if #off > 0 then text = text .. "; " .. #off .. " part(s) came off" end
    return true, text
end

-- Takes the skin off the weapon item.
function Skins.Remove(c, iid)
    local home, why = at_home()
    if not home then return false, why end
    local item = weapon_item(c, iid)
    if not item then return false, "no such weapon" end
    local d = item.data
    if not d.skin_id then return false, "it wears no skin" end
    local new = new_build(d, nil)
    set_skin(c, iid, {})
    follow(c, iid, new)
    log(string.format("the skin off the %s (uid %s)", tostring(d.weapon_id), tostring(d.uid)))
    return true, "The " .. name_of(d) .. " wears no skin now"
end

-- A locked skin keeps parts off (armory_parts.lua asks): nil, or why.
function Skins.LockReason(d)
    if type(d) ~= "table" or not Skins.Locked(d.skin_id) then return nil end
    return "the " .. Skins.Name(d.skin_id) .. " skin locks the " .. name_of(d) .. ": Sydney takes it off"
end

-- At the menu: a skin you no longer own (a Steam copy sold) comes off.
function Skins.Sweep()
    if not Skins.Enabled() or Armory.InHeist() then return 0 end
    local tradable = tradables()
    if not tradable then return 0 end
    local n = 0
    for _, e in ipairs(Armory.Items(function(_, it) return type(it.data.skin_id) == "string" end)) do
        local d = e.item.data
        local t = Skins.Tweak(d.skin_id)
        local have = t ~= nil and (tradable[d.skin_iid] ~= nil or unlocked(d.skin_id, t))
        if not have then
            local new = new_build(d, nil)
            set_skin(e.container, e.item.instance_id, {})
            follow(e.container, e.item.instance_id, new)
            n = n + 1
            log("you no longer own the " .. tostring(d.skin_id) .. ": it came off the " .. name_of(d))
        end
    end
    return n
end
