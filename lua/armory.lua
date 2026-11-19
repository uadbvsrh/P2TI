-- The armory (0.36.0; grid weapons 0.37.0): the weapons you own.
--
-- Every weapon you own is a grid item ("weapon"): in the safehouse's locker
-- (12x10), in a hand slot (the weapon you take into the heist), or packed in
-- your backpack or rig as a spare. Weapons are bought at the market
-- (Scarface) at the game's own prices, changed every day, and only as many
-- as are for sale that day; a bought weapon goes into the locker.
--
-- The game's own weapon slots only mirror your hands: slot 1 of each kind is
-- the weapon in that hand, or the game's default (AMCAR, Chimano 88) when
-- the hand is empty. This is safe because the mod plays on its own progress
-- save (save_slot.lua). The game then spawns, shows and syncs that weapon
-- with its own code.
--
-- A failed heist is death: every weapon you brought (in your hands, rig,
-- pockets and backpack) is lost. Leaving a heist or quitting the game in one
-- counts as failing it (a mark saved when the heist starts, still there at
-- the next menu). A won heist keeps everything, also from custody. There is
-- no restart. The menu inventory is a plan that a heist never writes to, so
-- the loss is noted at the end and taken out of it at the next menu.
--
-- With the Pick Up Weapons mod a weapon you pick up in a heist becomes that
-- slot's weapon; yours is left on the ground (pick it up again and it is the
-- same item). Win the heist and what you picked up and still carry is yours
-- (into the locker, or the slot it was in); what you left on the ground is
-- lost.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Armory = PDTI.Armory or {}
PDTI.Armory = Armory

local log = PDTI.Logger("PDTI ARMORY")

Armory.FILE_VERSION = 2
Armory.DRIFT = 0.3          -- a day's price is the game's price x (1 +- 0.3)
Armory.MAX_STOCK = 3        -- at most this many of a weapon for sale a day
Armory.CATEGORIES = { "primaries", "secondaries" }
Armory.HANDS = { primaries = "hand_primary", secondaries = "hand_secondary" }
-- The game's default weapons: a hand without your own weapon gets these
-- (free, never lost).
Armory.FALLBACK = {
    primaries = { weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar" },
    secondaries = { weapon_id = "glock_17", factory_id = "wpn_fps_pis_g17" }
}
-- A weapon's place in the grid, by its first matching category.
Armory.SIZES = {
    { "pistol", 2, 1 }, { "smg", 3, 2 }, { "shotgun", 4, 2 }, { "assault_rifle", 4, 2 },
    { "snp", 5, 2 }, { "lmg", 5, 2 }, { "minigun", 5, 2 }
}
Armory.DEFAULT_SIZE = { 4, 2 }
Armory.ITEM_ID = "weapon"
-- A weapon part you own (armory_parts.lua): lost like a weapon.
Armory.PART_ITEM_ID = "weapon_part"

function Armory.Enabled()
    local stash = PDTI.Stash
    return stash ~= nil and stash.Enabled ~= nil and stash.Enabled() == true
end

------------------------------------------------------------------ saving

local data, loaded_profile = nil, nil

local function file_name(index)
    local own = PDTI.SaveFileName and PDTI.SaveFileName("armory", index)
    if own then return own end
    if index == 1 then return "pdti_armory.json" end
    return "pdti_armory_profile" .. tostring(index) .. ".json"
end
Armory.FileName = file_name

local function path(index)
    return (rawget(_G, "SavePath") or "") .. file_name(index)
end

local function uid_list(raw)
    local out, seen = {}, {}
    if type(raw) ~= "table" then return out end
    for _, v in ipairs(raw) do
        local n = math.floor(tonumber(v) or 0)
        if n > 0 and not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    return out
end

local function sanitize(raw)
    -- free_due: the free AMCAR / Chimano 88 are given for a kind you own
    -- none of on a new save and after a loss, not after you threw yours away.
    -- taken: what you carried when the heist's first spawn came (taken_bp:
    -- the weapons' builds then); after: what a won heist changed (0.39.0,
    -- armory_hotmod.lua).
    -- policies, returns, ended_at: the insurance (armory_insurance.lua).
    local d = { version = Armory.FILE_VERSION, next_uid = 1, stock = { day = "", bought = {} },
        in_heist = false, brought = {}, lost = {}, captured = {}, free_due = true,
        taken = {}, taken_bp = {}, taken_set = false, after = { builds = {}, gone = {}, parts = {} },
        policies = {}, returns = {}, ended_at = nil, wear = {} }
    if type(raw) ~= "table" then return d end
    d.free_due = raw.free_due == true
    d.next_uid = math.max(1, math.floor(tonumber(raw.next_uid) or 1))
    if type(raw.stock) == "table" and type(raw.stock.day) == "string" then
        d.stock.day = raw.stock.day
        if type(raw.stock.bought) == "table" then
            for id, n in pairs(raw.stock.bought) do
                if type(id) == "string" and tonumber(n) then d.stock.bought[id] = math.max(0, math.floor(tonumber(n))) end
            end
        end
    end
    d.in_heist = raw.in_heist == true
    d.brought = uid_list(raw.brought)
    d.lost = uid_list(raw.lost)
    d.taken = uid_list(raw.taken)
    d.taken_set = raw.taken_set == true
    for k, v in pairs(type(raw.taken_bp) == "table" and raw.taken_bp or {}) do
        local uid = math.floor(tonumber(k) or 0)
        if uid > 0 and type(v) == "string" then d.taken_bp[tostring(uid)] = v end
    end
    local after = type(raw.after) == "table" and raw.after or {}
    for _, b in ipairs(type(after.builds) == "table" and after.builds or {}) do
        local uid = type(b) == "table" and math.floor(tonumber(b.uid) or 0) or 0
        if uid > 0 and type(b.blueprint) == "string" then
            d.after.builds[#d.after.builds + 1] = { uid = uid, blueprint = b.blueprint }
        end
    end
    d.after.gone = uid_list(after.gone)
    for _, e in ipairs(type(after.parts) == "table" and after.parts or {}) do
        local p = type(e) == "table" and e.data
        local uid = type(p) == "table" and math.floor(tonumber(p.uid) or 0) or 0
        if uid > 0 and type(p.part_id) == "string" then
            local data = { uid = uid }
            for _, k in ipairs({ "part_id", "ptype", "name", "for_weapon", "global_value" }) do
                if type(p[k]) == "string" then data[k] = p[k] end
            end
            for _, k in ipairs({ "w", "h", "weight" }) do
                if tonumber(p[k]) then data[k] = tonumber(p[k]) end
            end
            d.after.parts[#d.after.parts + 1] = { data = data, at = type(e.at) == "string" and e.at or "locker" }
            d.next_uid = math.max(d.next_uid, uid + 1)
        end
    end
    d.captured = {}
    for _, e in ipairs(type(raw.captured) == "table" and raw.captured or {}) do
        local w = type(e) == "table" and e.data
        local uid = type(w) == "table" and math.floor(tonumber(w.uid) or 0) or 0
        if uid > 0 and type(w.weapon_id) == "string" and type(w.factory_id) == "string" then
            local data = { uid = uid }
            for _, k in ipairs({ "weapon_id", "factory_id", "category", "blueprint", "name",
                "skin_id", "skin_iid", "skin_quality" }) do
                if type(w[k]) == "string" then data[k] = w[k] end
            end
            if w.skin_bonus == true then data.skin_bonus = true end
            for _, k in ipairs({ "w", "h", "weight", "cond", "skin_color" }) do
                if tonumber(w[k]) then data[k] = tonumber(w[k]) end
            end
            d.captured[#d.captured + 1] = { data = data, at = type(e.at) == "string" and e.at or "locker" }
        end
    end
    for k, p in pairs(type(raw.policies) == "table" and raw.policies or {}) do
        local uid = math.floor(tonumber(k) or 0)
        if uid > 0 and type(p) == "table" and type(p.bp) == "string" and tonumber(p.paid) then
            d.policies[tostring(uid)] = { paid = math.max(0, math.floor(tonumber(p.paid))), bp = p.bp,
                name = type(p.name) == "string" and p.name or nil,
                weapon_id = type(p.weapon_id) == "string" and p.weapon_id or nil, at = tonumber(p.at) or 0 }
        end
    end
    for _, e in ipairs(type(raw.returns) == "table" and raw.returns or {}) do
        local w = type(e) == "table" and e.data
        local uid = type(w) == "table" and math.floor(tonumber(w.uid) or 0) or 0
        if uid > 0 and type(w.weapon_id) == "string" and type(w.factory_id) == "string" and tonumber(e.due) then
            local data = { uid = uid }
            for _, k in ipairs({ "weapon_id", "factory_id", "category", "blueprint", "name",
                "skin_id", "skin_iid", "skin_quality" }) do
                if type(w[k]) == "string" then data[k] = w[k] end
            end
            if w.skin_bonus == true then data.skin_bonus = true end
            for _, k in ipairs({ "w", "h", "weight", "gun_set", "gun_n", "gun_weight", "cond", "skin_color" }) do
                if tonumber(w[k]) then data[k] = tonumber(w[k]) end
            end
            d.returns[#d.returns + 1] = { data = data, due = math.floor(tonumber(e.due)),
                name = type(e.name) == "string" and e.name or data.name or data.weapon_id, told = e.told == true }
            d.next_uid = math.max(d.next_uid, uid + 1)
        end
    end
    d.ended_at = tonumber(raw.ended_at)
    -- wear: the condition of your weapons after the heist's shots, by uid
    -- (armory_wear.lua), until the menu puts it onto them.
    for k, v in pairs(type(raw.wear) == "table" and raw.wear or {}) do
        local uid = math.floor(tonumber(k) or 0)
        local c = tonumber(v)
        if uid > 0 and c and c == c then d.wear[tostring(uid)] = math.max(0, math.min(100, c)) end
    end
    return d
end
Armory._Sanitize = sanitize

local function read_file(index)
    local f = io.open(path(index), "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local js = rawget(_G, "json")
    if not js or type(text) ~= "string" or text == "" then return nil end
    local ok, raw = pcall(js.decode, text)
    if not ok then log("the armory file could not be read: " .. tostring(raw)); return nil end
    return raw
end

function Armory.Load(index)
    index = index or (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1
    data = sanitize(read_file(index))
    loaded_profile = index
    return data
end

local function get()
    local index = (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1
    if not data or loaded_profile ~= index then Armory.Load(index) end
    return data
end
Armory._Data = get

-- Written at once, also in a heist.
function Armory.Save()
    local d = get()
    local js = rawget(_G, "json")
    if not js then log("no JSON library: the armory is not saved"); return false end
    local ok, text = pcall(js.encode, d)
    if not ok or type(text) ~= "string" then log("the armory could not be encoded"); return false end
    local p = path(loaded_profile or 1)
    local tmp = p .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then log("the armory could not be written: " .. tostring(err)); return false end
    local wrote = f:write(text)
    f:close()
    if not wrote then os.remove(tmp); log("the armory could not be written"); return false end
    os.remove(p)
    if not os.rename(tmp, p) then log("the armory file could not be replaced"); return false end
    return true
end

function Armory.Reset()
    data, loaded_profile = nil, nil
end

---------------------------------------------------------- the game's data

local function weapon_tweak(weapon_id)
    local w = rawget(_G, "tweak_data") and tweak_data.weapon
    local t = w and type(weapon_id) == "string" and w[weapon_id]
    return type(t) == "table" and t or nil
end

-- "primaries" or "secondaries" (the game's selection: 2 and 1).
function Armory.Category(weapon_id)
    local t = weapon_tweak(weapon_id)
    local sel = t and type(t.use_data) == "table" and t.use_data.selection_index
    if sel == 2 then return "primaries" end
    if sel == 1 then return "secondaries" end
    return nil
end

-- The market's pages (0.42.0): a weapon's type, from the game's categories
-- (akimbo first; a kind not listed here is Special: bows, launchers, saws,
-- miniguns, flamethrowers). In the order a page lists them: the primaries'
-- rifles, shotguns, LMGs, snipers, akimbo, special; the secondaries'
-- pistols, SMGs, shotguns, special.
Armory.TYPES = {
    { id = "assault_rifle", name = "Assault rifles", short = "Rifles" },
    { id = "pistol", name = "Pistols", short = "Pistols" },
    { id = "smg", name = "Submachine guns", short = "SMGs" },
    { id = "shotgun", name = "Shotguns", short = "Shotguns" },
    { id = "lmg", name = "Light machine guns", short = "LMGs" },
    { id = "snp", name = "Sniper rifles", short = "Snipers" },
    { id = "akimbo", name = "Akimbo", short = "Akimbo" },
    { id = "special", name = "Special", short = "Special" }
}

function Armory.Type(weapon_id)
    local t = weapon_tweak(weapon_id)
    local cats = t and type(t.categories) == "table" and t.categories or {}
    for _, c in ipairs(cats) do
        if c == "akimbo" then return "akimbo" end
    end
    for _, ty in ipairs(Armory.TYPES) do
        if ty.id == cats[1] and ty.id ~= "special" then return ty.id end
    end
    return "special"
end

function Armory.FactoryId(weapon_id)
    local ok, id = pcall(function() return managers.weapon_factory:get_factory_id_by_weapon_id(weapon_id) end)
    if ok and type(id) == "string" then return id end
    return nil
end

local function clean_blueprint(list)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, part in ipairs(list) do
        if type(part) == "string" and part ~= "" then out[#out + 1] = part end
    end
    return out
end

function Armory.DefaultBlueprint(factory_id)
    local ok, bp = pcall(function() return managers.weapon_factory:get_default_blueprint_by_factory_id(factory_id) end)
    if ok and type(bp) == "table" then return clean_blueprint(bp) end
    return {}
end

-- A grid item keeps its blueprint as one text ("part,part,...").
function Armory.SplitBlueprint(text)
    local out = {}
    if type(text) ~= "string" then return out end
    for part in text:gmatch("[^,]+") do out[#out + 1] = part end
    return out
end

function Armory.JoinBlueprint(list)
    return table.concat(clean_blueprint(list), ",")
end

function Armory.Name(weapon_id)
    local t = weapon_tweak(weapon_id)
    if t and t.name_id then
        local ok, text = pcall(function() return managers.localization:text(t.name_id) end)
        if ok and type(text) == "string" and text ~= "" and not text:find("ERROR") then return text end
    end
    return tostring(weapon_id)
end

local function unlocked(weapon_id)
    local ok, yes = pcall(function() return managers.blackmarket:weapon_unlocked(weapon_id) end)
    return ok and yes == true
end
Armory.Unlocked = unlocked

------------------------------------------------------------------ prices

-- The game's buy price of the bare weapon.
function Armory.BasePrice(weapon_id)
    local ok, v = pcall(function() return managers.money:get_weapon_price_modified(weapon_id) end)
    return ok and math.max(0, math.floor(tonumber(v) or 0)) or 0
end

-- The game's price of the parts a build has beyond the weapon's own.
function Armory.PartsPrice(weapon_id, factory_id, blueprint)
    local default = {}
    for _, p in ipairs(Armory.DefaultBlueprint(factory_id)) do default[p] = true end
    local total = 0
    for _, part in ipairs(blueprint or {}) do
        if not default[part] then
            local ok, v = pcall(function() return managers.money:get_weapon_modify_price(weapon_id, part, "normal") end)
            if ok then total = total + math.max(0, math.floor(tonumber(v) or 0)) end
        end
    end
    return total
end

-- What a weapon is worth (the weapon and all its parts). w: a weapon
-- item's data, or a build with a blueprint list.
function Armory.BuildPrice(w)
    if type(w) ~= "table" then return 0 end
    local bp = type(w.blueprint) == "table" and w.blueprint or Armory.SplitBlueprint(w.blueprint)
    -- A skin's own parts are free (armory_skins.lua).
    local S = PDTI.WeaponSkins
    if S and w.skin_id then bp = S.WithoutSkinParts(w.skin_id, bp) end
    return Armory.BasePrice(w.weapon_id) + Armory.PartsPrice(w.weapon_id, w.factory_id, bp)
end

local function today()
    local m = PDTI.Market
    return m and m.Today and m.Today() or os.date("%Y-%m-%d")
end
Armory.Today = today

local function hash(text)
    local m = PDTI.Market
    if m and m.Hash then return m.Hash(text) end
    return 0.5
end

-- The day's rolls (tests replace them).
Armory.FactorRoll = function(weapon_id, day) return hash("weapon_price|" .. day .. "|" .. weapon_id) end
Armory.StockRoll = function(weapon_id, day) return hash("weapon_stock|" .. day .. "|" .. weapon_id) end

function Armory.Factor(weapon_id, day)
    local r = tonumber(Armory.FactorRoll(weapon_id, day or today())) or 0.5
    return 1 + Armory.DRIFT * (2 * math.max(0, math.min(1, r)) - 1)
end

function Armory.TodayPrice(weapon_id)
    return math.floor(Armory.BasePrice(weapon_id) * Armory.Factor(weapon_id) + 0.5)
end

local function stock_state()
    local d = get()
    if d.stock.day ~= today() then d.stock = { day = today(), bought = {} } end
    return d.stock
end

-- How many are for sale today, after what you bought.
function Armory.Stock(weapon_id)
    local r = tonumber(Armory.StockRoll(weapon_id, today())) or 0
    local n = math.min(Armory.MAX_STOCK, math.floor(math.max(0, math.min(1, r)) * (Armory.MAX_STOCK + 1)))
    return math.max(0, n - (stock_state().bought[weapon_id] or 0))
end

-- Every weapon the game lets you have, with today's price and stock.
function Armory.Catalog()
    local rows = {}
    local list = rawget(_G, "tweak_data") and tweak_data.weapon
    if type(list) ~= "table" then return rows end
    for id, t in pairs(list) do
        if type(id) == "string" and type(t) == "table" and Armory.Category(id) and Armory.FactoryId(id) and unlocked(id) then
            local normal = Armory.BasePrice(id)
            rows[#rows + 1] = {
                weapon_id = id, name = Armory.Name(id), category = Armory.Category(id), wtype = Armory.Type(id),
                normal = normal, today = Armory.TodayPrice(id), stock = Armory.Stock(id),
                factor = Armory.Factor(id)
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.category ~= b.category then return a.category == "primaries" end
        if a.name ~= b.name then return a.name < b.name end
        return a.weapon_id < b.weapon_id
    end)
    return rows
end

-- "+12%" / "-8%" / "" for the day's change.
function Armory.FactorText(weapon_id)
    local pct = math.floor((Armory.Factor(weapon_id) - 1) * 100 + 0.5)
    if pct == 0 then return "" end
    return (pct > 0 and "+" or "") .. pct .. "%"
end

------------------------------------------------------------------ money

local function money()
    local ok, v = pcall(function() return managers.money:total() end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function take(amount)
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if amount <= 0 then return true end
    local have = money()
    if not have or have < amount then return false end
    return pcall(function() managers.money:deduct_from_total(amount) end)
end
Armory.Take = take

-- Pays you (a sale): spending cash, none of it offshore.
function Armory.Give(amount)
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if amount <= 0 then return 0 end
    local ok = pcall(function()
        local mm = managers.money
        if type(mm.add_to_spending) == "function" then mm:add_to_spending(amount)
        elseif type(mm._add_to_total) == "function" then mm:_add_to_total(amount, { no_offshore = true })
        else mm:add_to_total(amount) end
    end)
    return ok and amount or 0
end

----------------------------------------------------------- weapon items

local function in_heist()
    if PDTI.InSafehouse and PDTI.InSafehouse() then return false end
    return PDTI.InHeist ~= nil and PDTI.InHeist() == true
end
Armory.InHeist = in_heist

function Armory.Size(weapon_id)
    local t = weapon_tweak(weapon_id)
    local has = {}
    for _, c in ipairs(t and t.categories or {}) do has[c] = true end
    for _, s in ipairs(Armory.SIZES) do
        if has[s[1]] then return s[2], s[3] end
    end
    return Armory.DEFAULT_SIZE[1], Armory.DEFAULT_SIZE[2]
end

-- The weapon's weight (the loadout's rule: by its class and concealment).
function Armory.Weight(weapon_id, factory_id, blueprint)
    local L = PDTI.Loadout
    local t = weapon_tweak(weapon_id)
    if not L or not L.WeaponWeight then return 3 end
    local conceal = 0
    pcall(function()
        conceal = managers.blackmarket:_calculate_weapon_concealment({ factory_id = factory_id,
            weapon_id = weapon_id, blueprint = blueprint })
    end)
    return L.WeaponWeight(t and t.categories or {}, conceal)
end

-- A weapon item's data (flat: the inventory saves only plain fields).
function Armory.MakeData(weapon_id, blueprint, uid)
    local factory = Armory.FactoryId(weapon_id)
    local bp = clean_blueprint(blueprint or Armory.DefaultBlueprint(factory))
    local width, height = Armory.Size(weapon_id)
    return {
        uid = uid, weapon_id = weapon_id, factory_id = factory, category = Armory.Category(weapon_id),
        blueprint = Armory.JoinBlueprint(bp), name = Armory.Name(weapon_id),
        w = width, h = height, weight = Armory.Weight(weapon_id, factory, bp)
    }
end

local function new_uid()
    local d = get()
    local uid = d.next_uid
    d.next_uid = uid + 1
    return uid
end
Armory.NewUid = new_uid

local function weapon_items(pred)
    return PDTI.FindItems(function(name, item)
        return item.item_id == Armory.ITEM_ID and type(item.data) == "table" and (pred == nil or pred(name, item))
    end)
end
Armory.Items = weapon_items

-- Your weapons and the parts you own: a loss names them by uid.
local function owned_items(pred)
    return PDTI.FindItems(function(name, item)
        return (item.item_id == Armory.ITEM_ID or item.item_id == Armory.PART_ITEM_ID) and type(item.data) == "table"
            and (pred == nil or pred(name, item))
    end)
end
Armory.Owned = owned_items

-- Every weapon you own (the grid items), with where it is.
function Armory.Weapons()
    local out = {}
    for _, e in ipairs(weapon_items()) do
        out[#out + 1] = { container = e.container, data = e.item.data, instance_id = e.item.instance_id }
    end
    return out
end

-- The weapon item in a hand, or nil.
function Armory.HandItem(cat)
    local hand = Armory.HANDS[cat]
    -- (A slot holds nothing but a weapon item: inventory.lua's placement.)
    local _, item = PDTI.FindFirstItem(function(name) return name == hand end)
    return item
end

-- Are your weapons grid items (the armory on, and you own a weapon)?
function Armory.InUse()
    if not Armory.Enabled() then return false end
    return PDTI.FindFirstItem(function(_, it) return it.item_id == Armory.ITEM_ID end) ~= nil
end

-- A hand takes only a weapon the game lets you use (inventory.lua asks).
function Armory.HandCheck(item_data)
    if not rawget(_G, "managers") or not managers.blackmarket then return true end
    -- A weapon you picked up in the heist is in your hands, unlocked or not.
    -- (Only a heist has such items: a won one is yours, without the mark.)
    if item_data.picked == true then return true end
    if unlocked(item_data.weapon_id) then return true end
    return false, "you have not unlocked the " .. tostring(item_data.name or item_data.weapon_id) .. " yet"
end
PDTI.HandCheck = Armory.HandCheck

-- Buys one of today's weapons: it goes into the locker.
function Armory.Buy(weapon_id)
    if not Armory.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if in_heist() then return false, "the market is closed during a heist" end
    local cat, factory = Armory.Category(weapon_id), Armory.FactoryId(weapon_id)
    if not cat or not factory then return false, "not a weapon you can own" end
    if not unlocked(weapon_id) then return false, "you have not unlocked this weapon" end
    if Armory.Stock(weapon_id) <= 0 then return false, "none for sale today" end
    local item_data = Armory.MakeData(weapon_id, nil, nil)
    local x = PDTI.FindFreeSpace("locker", { item_id = Armory.ITEM_ID, data = item_data }, true)
    if x == nil then return false, "your locker is full" end
    local price = Armory.TodayPrice(weapon_id)
    if not take(price) then return false, "not enough money" end
    item_data.uid = new_uid()
    if not PDTI.AddItemAuto("locker", Armory.ITEM_ID, 1, item_data, true) then
        pcall(function() managers.money:add_to_total(price) end)
        return false, "your locker is full"
    end
    local st = stock_state()
    st.bought[weapon_id] = (st.bought[weapon_id] or 0) + 1
    Armory.Save()
    log(string.format("bought %s for %d (%s today)", weapon_id, price, Armory.FactorText(weapon_id)))
    return true, item_data
end

-- The free weapons (0.37.2): when you own no weapon of a kind (none in the
-- slots, the locker, the backpack or the rig), the game's free one (AMCAR,
-- Chimano 88) is put into its slot as a real weapon item. So a new save and
-- a death leave you with weapons you can drag like any other. Only in the
-- menu. Returns how many were given.
function Armory.IssueFree()
    if not Armory.Enabled() or PDTI.session_only or in_heist() then return 0 end
    local d = get()
    if not d.free_due then return 0 end
    local owned = {}
    for _, e in ipairs(weapon_items()) do owned[e.item.data.category or ""] = true end
    local n = 0
    for _, cat in ipairs(Armory.CATEGORIES) do
        local f = Armory.FALLBACK[cat]
        if not owned[cat] and Armory.Category(f.weapon_id) == cat and Armory.FactoryId(f.weapon_id) then
            local item_data = Armory.MakeData(f.weapon_id, nil, new_uid())
            item_data.free = true
            local ok = PDTI.AddItemAuto(Armory.HANDS[cat], Armory.ITEM_ID, 1, item_data, true)
                or PDTI.AddItemAuto("locker", Armory.ITEM_ID, 1, item_data, true)
            if ok then
                n = n + 1
                log(string.format("you had no %s: the free %s is in its slot", cat, tostring(item_data.name)))
            end
        end
    end
    d.free_due = false
    Armory.Save()
    return n
end

------------------------------------------- the game's slots mirror your hands

-- The build the game gets for a hand: your weapon, or its default.
function Armory.Build(cat)
    local item = Armory.HandItem(cat)
    if item then
        local d = item.data
        local build = { equipped = true, weapon_id = d.weapon_id, factory_id = d.factory_id,
            blueprint = Armory.SplitBlueprint(d.blueprint), global_values = {}, cosmetics = Armory.Cosmetics(d) }
        -- A locked skin (armory_skins.lua): the game's screens show it so.
        local sk = PDTI.WeaponSkins and PDTI.WeaponSkins.Tweak(d.skin_id)
        if sk then build.customize_locked, build.locked_name = sk.locked, sk.rarity == "legendary" end
        return build
    end
    local f = Armory.FALLBACK[cat]
    return { equipped = true, weapon_id = f.weapon_id, factory_id = f.factory_id,
        blueprint = Armory.DefaultBlueprint(f.factory_id), global_values = {} }
end

local function same_build(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if a.weapon_id ~= b.weapon_id or a.factory_id ~= b.factory_id or not a.equipped then return false end
    local ca, cb = a.cosmetics or {}, b.cosmetics or {}
    if ca.id ~= cb.id or ca.instance_id ~= cb.instance_id or ca.color_index ~= cb.color_index then return false end
    return Armory.JoinBlueprint(a.blueprint) == Armory.JoinBlueprint(b.blueprint)
end

local function crafted_items()
    local g = rawget(_G, "Global")
    local bm = type(g) == "table" and g.blackmarket_manager
    return type(bm) == "table" and type(bm.crafted_items) == "table" and bm.crafted_items or nil
end

-- Writes your hands into the game's weapon slots (slot 1 of each kind, the
-- only one). Only in the menu: in a heist the weapons are already out.
-- Returns true when something changed.
function Armory.SyncEquipped()
    if not Armory.Enabled() or PDTI.session_only or in_heist() then return false end
    local crafted = crafted_items()
    if not crafted then return false end
    Armory.IssueFree()
    local changed = {}
    for _, cat in ipairs(Armory.CATEGORIES) do
        local build = Armory.Build(cat)
        local slots = crafted[cat]
        local only_one = type(slots) == "table" and next(slots) == 1 and next(slots, 1) == nil
        if not (only_one and same_build(slots[1], build)) then
            if type(slots) ~= "table" then slots = {}; crafted[cat] = slots end
            for k in pairs(slots) do slots[k] = nil end
            slots[1] = build
            changed[#changed + 1] = cat
        end
    end
    if #changed == 0 then return false end
    local bm = rawget(_G, "managers") and managers.blackmarket
    if bm then
        pcall(function() bm:_update_menu_scene_primary() end)
        pcall(function() bm:_update_menu_scene_secondary() end)
    end
    local mch = rawget(_G, "MenuCallbackHandler")
    if mch and mch._update_outfit_information then pcall(function() mch:_update_outfit_information() end) end
    -- The planned magazines follow the new guns.
    if PDTI.Plan and PDTI.Plan.Refresh then pcall(PDTI.Plan.Refresh) end
    log("the game's weapons now: " .. table.concat(changed, ", ") .. " from your hands")
    return true
end

----------------------------------------- the weapons in your hands (in game)

-- The game's weapon selections: 2 the primary, 1 the secondary.
Armory.SELECTION = { primaries = 2, secondaries = 1 }

local function player_unit()
    local ok, unit = pcall(function() return managers.player:player_unit() end)
    if ok and unit ~= nil and (not rawget(_G, "alive") or alive(unit)) then return unit end
    return nil
end

local function selections(inv)
    local ok, s = pcall(function() return inv:available_selections() end)
    return ok and type(s) == "table" and s or {}
end

local function unit_factory(unit)
    local ok, id = pcall(function() return unit:base()._factory_id end)
    return ok and id or nil
end

-- A weapon out of the player's hands (never the last one: the game needs
-- one). The unit goes the way the game removes a replaced weapon.
-- A weapon's skin (armory_skins.lua) as the game's cosmetics, or nil.
function Armory.Cosmetics(d)
    if type(d) ~= "table" or type(d.skin_id) ~= "string" then return nil end
    local c = { id = d.skin_id, instance_id = d.skin_iid or d.skin_id, quality = d.skin_quality or "mint",
        bonus = d.skin_bonus == true, color_index = tonumber(d.skin_color) }
    -- A weapon colour: the game's default pattern size.
    if c.color_index then
        local td = rawget(_G, "tweak_data")
        c.pattern_scale = td and td.blackmarket and td.blackmarket.weapon_color_pattern_scale_default
    end
    return c
end

-- What a gun in your hands is made from: the build and the skin.
function Armory.BuildKey(d)
    local key = tostring(d.blueprint or "")
    if type(d.skin_id) == "string" then key = key .. "#" .. d.skin_id .. ":" .. tostring(d.skin_color or "") end
    return key
end

-- Which weapon item a unit in your hands is: its uid on the unit, and the
-- build (the item's blueprint text) it was made with.
local function tag_unit(unit, uid, blueprint)
    if unit == nil or uid == nil then return end
    pcall(function()
        local b = unit:base()
        b._pdti_uid = uid
        b._pdti_bp = blueprint
    end)
end

-- The build a unit in your hands was made with, or nil (the game made it at
-- spawn, from the build your hands gave it).
local function unit_bp(unit)
    local bp = nil
    if unit ~= nil then pcall(function() bp = unit:base()._pdti_bp end) end
    return bp
end

local function unit_uid(unit)
    local uid = nil
    if unit ~= nil then pcall(function() uid = unit:base()._pdti_uid end) end
    return uid
end

-- A weapon leaving your hands: what is in its gun goes with its item (into
-- the backpack, and back into a slot). Read before the game deletes the
-- unit. (In the menu and the safehouse there is nothing to read.)
local function stash_gun(unit)
    local Ammo = PDTI.Ammo
    if unit == nil or not Ammo or not Ammo.GunState then return false end
    if rawget(_G, "alive") and not alive(unit) then return false end
    local base = unit:base()
    -- (The stand-in has no item: mark_stand_in took its uid.)
    if base == nil or base._pdti_uid == nil then return false end
    local ok, fields = pcall(Ammo.GunState, base)
    if not ok or type(fields) ~= "table" then return false end
    local uid = base._pdti_uid
    local entry = PDTI.FindItems(function(_, it)
        return it.item_id == Armory.ITEM_ID and type(it.data) == "table" and it.data.uid == uid
    end)[1]
    if not entry then return false end
    return PDTI.EditItems({ update = { { container = entry.container, instance_id = entry.item.instance_id,
        data = fields } } }) == true
end
Armory._StashGun = stash_gun

-- A weapon put into your hands gets what its item holds; then it is in the
-- gun (and its slot's magazine box), not in the item (gun_in).
local function load_gun(inv, sel, cat, d)
    local entry = selections(inv)[sel]
    local unit = entry and entry.unit
    if unit == nil then return end
    tag_unit(unit, d.uid, Armory.BuildKey(d))
    local Ammo = PDTI.Ammo
    if not Ammo or not Ammo.LoadGun then return end
    local ok, done = pcall(Ammo.LoadGun, unit:base(), d)
    if ok and done then
        local item = Armory.HandItem(cat)
        if item then
            PDTI.EditItems({ update = { { container = Armory.HANDS[cat], instance_id = item.instance_id,
                data = { gun_n = 0, gun_weight = 0, gun_in = 1 } } } })
        end
    end
end

local function take_out(inv, sel)
    local s = selections(inv)
    local entry = s[sel]
    local other = sel == 1 and 2 or 1
    if not entry or not s[other] then return false end
    stash_gun(entry.unit)
    if inv:equipped_selection() == sel then inv:equip_selection(other, true) end
    local unit = entry.unit
    inv:remove_selection(sel, true)
    if unit ~= nil and (not rawget(_G, "alive") or alive(unit)) then
        pcall(function()
            local gun = unit:base()._second_gun
            if gun ~= nil and alive(gun) then gun:set_slot(0) end
        end)
        pcall(function() unit:base():set_slot(unit, 0) end)
        pcall(function() World:delete_unit(unit) end)
    end
    pcall(function() managers.hud:set_ammo_amount(sel, 0, 0, 0, 0) end)
    -- Its magazine went with it: the slot's in-gun item comes out.
    local Ammo = PDTI.Ammo
    local c = Ammo and Ammo.GUN_SLOTS and Ammo.GUN_SLOTS[sel == 2 and "primary" or "secondary"]
    if c and Ammo.DropGunLeftovers then pcall(Ammo.DropGunLeftovers, c) end
    return true
end

local function put_in(inv, d)
    inv:add_unit_by_factory_name(d.factory_id, false, true, Armory.SplitBlueprint(d.blueprint), Armory.Cosmetics(d))
end

-- No weapon in your hands. The game cannot run without a weapon unit, so
-- the last one stays as a stand-in, the way the game's casing mode keeps
-- your guns: hidden, empty, never refilled, and it cannot fire, aim or
-- reload (the hooks below). Melee and throwables still work.
local function is_stand_in(unit)
    if unit == nil then return false end
    local b = unit:base()
    return b ~= nil and b._pdti_unarmed == true
end
Armory.IsStandIn = is_stand_in

local function mark_stand_in(unit, sel)
    local b = unit:base()
    b._pdti_unarmed = true
    b._pdti_uid = nil
    -- Pick Up Weapons drops only your own weapons: never this one (and its
    -- refill gives it nothing).
    b._picked_up_weapon_data = { is_npc = true, ammo = { total = 0, clip = 0 } }
    pcall(function() b:set_ammo_remaining_in_clip(0) end)
    pcall(function() b:set_ammo_total(0) end)
    pcall(function() b:set_visibility_state(false) end)
    pcall(function() managers.hud:set_ammo_amount(sel, 0, 0, 0, 0) end)
    -- It holds no magazine: the slot's goes with the gun it was.
    local Ammo = PDTI.Ammo
    local c = Ammo and Ammo.GUN_SLOTS and Ammo.GUN_SLOTS[sel == 2 and "primary" or "secondary"]
    if c and Ammo.DropGunLeftovers then pcall(Ammo.DropGunLeftovers, c) end
end

-- Both slots empty: nothing in your hands. The stand-in is a pistol (a
-- heavy gun would slow you): the secondary's unit, else the Chimano 88.
local function make_unarmed(inv)
    local s = selections(inv)
    if (s[1] and is_stand_in(s[1].unit) and not s[2]) or (s[2] and is_stand_in(s[2].unit) and not s[1]) then
        return false
    end
    if not s[1] and s[2] then
        local factory = Armory.FactoryId(Armory.FALLBACK.secondaries.weapon_id)
        if factory then
            pcall(function()
                inv:add_unit_by_factory_name(factory, false, true, Armory.DefaultBlueprint(factory))
            end)
            s = selections(inv)
        end
    end
    local sel = s[1] and 1 or 2
    local entry = s[sel]
    if not entry then return false end
    if inv:equipped_selection() ~= sel then inv:equip_selection(sel, true) end
    if sel == 1 and s[2] then take_out(inv, 2) end
    if not is_stand_in(entry.unit) then
        -- (Your weapon's unit stays as the stand-in: its gun goes with it.)
        stash_gun(entry.unit)
        mark_stand_in(entry.unit, sel)
    end
    log("no weapon in your hands")
    return true
end

-- The player's hands hold what your slots hold: a weapon put into a slot is
-- in your hands, a weapon taken out of one is gone from them (you cannot
-- switch to it); both slots empty, no weapon at all. Returns true when the
-- weapons changed.
local function apply_inventory(inv)
    local want = {}
    for _, cat in ipairs(Armory.CATEGORIES) do
        local item = Armory.HandItem(cat)
        want[cat] = item and item.data or nil
    end
    if not want.primaries and not want.secondaries then return make_unarmed(inv) end
    local changed = false
    -- In first, then out (the stand-in goes last). A unit is that weapon when
    -- it is built from it and is not another item's (two of one model).
    for _, cat in ipairs(Armory.CATEGORIES) do
        local sel = Armory.SELECTION[cat]
        local d, cur = want[cat], selections(inv)[sel]
        local same = d ~= nil and cur ~= nil and unit_factory(cur.unit) == d.factory_id and not is_stand_in(cur.unit)
        if same then
            local uid = unit_uid(cur.unit)
            same = uid == nil or uid == d.uid
            -- Its parts changed (armory_parts.lua; in a heist armory_hotmod.lua):
            -- a gun made with another build is made again. One the game made
            -- (at spawn, or picked up) is taken as it is.
            if same then
                local bp = unit_bp(cur.unit)
                same = bp == nil or bp == Armory.BuildKey(d)
            end
            if same then tag_unit(cur.unit, d.uid, Armory.BuildKey(d)) end
        end
        if d and not same then
            -- The game deletes the weapon it replaces: its gun is read first.
            if cur then stash_gun(cur.unit) end
            local ok, err = pcall(put_in, inv, d)
            if ok then
                changed = true
                load_gun(inv, sel, cat, d)
                log("in your hands: " .. tostring(d.name or d.weapon_id))
            else
                log("could not put the " .. tostring(d.weapon_id) .. " into your hands: " .. tostring(err))
            end
        end
    end
    for _, cat in ipairs(Armory.CATEGORIES) do
        local sel = Armory.SELECTION[cat]
        if not want[cat] and selections(inv)[sel] then
            local ok, done = pcall(take_out, inv, sel)
            if ok and done then
                changed = true
                log("out of your hands: the " .. cat .. " (its slot is empty)")
            elseif not ok then
                log("could not take the " .. cat .. " out of your hands: " .. tostring(done))
            end
        end
    end
    return changed
end

function Armory.ApplyHands(unit)
    if not Armory.Enabled() then return false end
    unit = unit or player_unit()
    local okinv, inv = pcall(function() return unit:inventory() end)
    if not okinv or not inv then return false end
    return apply_inventory(inv)
end

-- A player unit appears (the heist begins, or after custody): its weapons
-- follow your slots.
function Armory.OnSpawn(unit)
    if not Armory.Enabled() then return false end
    pcall(Armory.InstallHooks)
    pcall(Armory.TakeSnapshot)
    return Armory.ApplyHands(unit)
end

---------------------------------- picked-up weapons (the Pick Up Weapons mod)

-- Your weapons left on the ground in this heist (that mod drops the slot's
-- weapon when you pick up another): their items, given back when you pick
-- one up again.
Armory._dropped = Armory._dropped or {}

local function bp_key(factory, list)
    local parts = clean_blueprint(list)
    table.sort(parts)
    return tostring(factory) .. "|" .. table.concat(parts, ",")
end

local CATEGORY_OF = { [2] = "primaries", [1] = "secondaries" }

-- Pick Up Weapons put a weapon into selection sel of the player's hands: it
-- is that slot's weapon now. The slot's weapon before lies on the ground (or
-- is gone, when it was an enemy's: that mod drops only yours). before: nil
-- when the selection was empty, else { enemy = was it an enemy's }, read
-- before the swap (the game deletes the old weapon: never touch it after).
function Armory.OnPickup(inv, picked, before, sel)
    local cat = CATEGORY_OF[sel]
    local entry = cat and selections(inv)[sel]
    local unit = entry and entry.unit
    if unit == nil then return false end
    local base = unit:base()
    local factory = base._factory_id
    local bp = clean_blueprint(base._blueprint or picked.blueprint)
    local old = Armory.HandItem(cat)
    if old then
        PDTI.RemoveItem(Armory.HANDS[cat], old.instance_id)
        local enemy = before ~= nil and before.enemy == true
        local name = tostring(old.data.name or old.data.weapon_id)
        if before ~= nil and not enemy then
            Armory._dropped[#Armory._dropped + 1] = { data = old.data,
                key = bp_key(old.data.factory_id, Armory.SplitBlueprint(old.data.blueprint)) }
            log("left on the ground: your " .. name)
        elseif enemy then
            log("gone: the " .. name .. " (Pick Up Weapons does not drop an enemy's weapon again)")
        else
            log("not in your hands, so not on the ground: the " .. name .. " (it is not lost)")
        end
    end
    -- One of yours picked up again: the same item. Else a new one.
    local data
    if not picked.is_npc then
        local key, at = bp_key(factory, bp), nil
        for i, e in ipairs(Armory._dropped) do if e.key == key then at = i; break end end
        if not at then
            for i, e in ipairs(Armory._dropped) do if e.data.factory_id == factory then at = i; break end end
        end
        if at then data = table.remove(Armory._dropped, at).data end
    end
    if not data then
        local weapon_id = picked.weapon_id or base._name_id
        data = Armory.MakeData(weapon_id, #bp > 0 and bp or nil, new_uid())
        data.factory_id = factory or data.factory_id
        data.picked = true
        Armory.Save()
    end
    local ok, why = PDTI.AddItemAuto(Armory.HANDS[cat], Armory.ITEM_ID, 1, data, true)
    if ok then
        log("picked up: the " .. tostring(data.name) .. " is your " .. (sel == 2 and "primary" or "secondary") .. " now")
    else
        log("the picked-up " .. tostring(data.name) .. " could not go into its slot: " .. tostring(why))
    end
    -- The stand-in (no weapon in your hands) leaves now.
    apply_inventory(inv)
    if PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    return ok == true
end

local function dropped_uids()
    local out = {}
    for _, e in ipairs(Armory._dropped) do
        local uid = math.floor(tonumber(e.data.uid) or 0)
        if uid > 0 then out[#out + 1] = uid end
    end
    return out
end

-- The weapons picked up in this heist that you still carry, and where.
local function picked_now()
    local out = {}
    for _, e in ipairs(weapon_items(function(_, item) return item.data.picked == true end)) do
        local data = {}
        for k, v in pairs(e.item.data) do if k ~= "picked" then data[k] = v end end
        out[#out + 1] = { data = data, at = e.container }
    end
    return out
end

-- Weapons won in a heist go into the menu inventory: into the slot they were
-- in if it is empty and the game lets you use the weapon, else the locker.
-- With no room they wait for the next menu.
function Armory.ApplyCaptured()
    local d = get()
    if #d.captured == 0 then return 0 end
    local have = {}
    for _, e in ipairs(weapon_items()) do have[math.floor(tonumber(e.item.data.uid) or 0)] = true end
    local keep, n = {}, 0
    for _, e in ipairs(d.captured) do
        if not have[e.data.uid] then
            local hand = Armory.HANDS[e.data.category]
            local ok = (hand ~= nil and e.at == hand and PDTI.AddItemAuto(hand, Armory.ITEM_ID, 1, e.data, true))
                or PDTI.AddItemAuto("locker", Armory.ITEM_ID, 1, e.data, true)
            if ok then
                n = n + 1
                have[e.data.uid] = true
                log("yours now (picked up in the heist): " .. tostring(e.data.name))
            else
                keep[#keep + 1] = e
                log("no room in the locker for the " .. tostring(e.data.name) .. ": it waits")
            end
        end
    end
    d.captured = keep
    Armory.Save()
    return n
end

------------------------------------------------------------------ death

-- Every weapon and part you take into a heist: all but the locker's.
function Armory.Brought()
    local out = {}
    for _, e in ipairs(owned_items(function(name) return name ~= "locker" end)) do
        local uid = math.floor(tonumber(e.item.data.uid) or 0)
        if uid > 0 then out[#out + 1] = uid end
    end
    return out
end

-- What you carry when the heist's first spawn comes (the briefing is over;
-- the locker stays at home from now): a weapon or part of it that is gone
-- at the end was fitted or thrown away, and a failed heist loses it too.
-- The weapons' builds then tell what the heist changed (armory_hotmod.lua).
function Armory.TakeSnapshot()
    local d = get()
    if not d.in_heist or d.taken_set then return false end
    d.taken, d.taken_bp, d.taken_set = Armory.Brought(), {}, true
    for _, e in ipairs(weapon_items(function(name) return name ~= "locker" end)) do
        local uid = math.floor(tonumber(e.item.data.uid) or 0)
        if uid > 0 then d.taken_bp[tostring(uid)] = tostring(e.item.data.blueprint or "") end
    end
    -- (Read only in this level: at its end, which writes the file.)
    return true
end

-- A heist starts (not the safehouse): the mark that makes leaving count,
-- and the weapons that go with you. What a won heist changed is written
-- into the inventory first (the next day of a heist starts with it).
function Armory.OnHeistStart()
    if not Armory.Enabled() or (PDTI.InSafehouse and PDTI.InSafehouse()) then return false end
    -- (A weapon in your hands: the game's slot follows, before the spawn.)
    if PDTI.HotMod and PDTI.HotMod.ApplyWin then pcall(PDTI.HotMod.ApplyWin) end
    local d = get()
    d.in_heist = true
    d.brought = Armory.Brought()
    d.taken, d.taken_bp, d.taken_set = {}, {}, false
    Armory._dropped = {}
    Armory.Save()
    -- The wear goes on from what earlier days of the heist wrote.
    if PDTI.Wear then pcall(PDTI.Wear.OnHeistStart) end
    return true
end

-- The uids in both lists, once.
local function union(a, b)
    local out, seen = {}, {}
    for _, list in ipairs({ a, b }) do
        for _, uid in ipairs(list or {}) do
            if not seen[uid] then seen[uid] = true; out[#out + 1] = uid end
        end
    end
    return out
end

local function mark_lost(d)
    -- When the heist ended: an insured weapon lost in it comes back a while
    -- after (armory_insurance.lua).
    local I = PDTI.Insurance
    d.ended_at = I and I.Now() or os.time()
    local have = {}
    for _, uid in ipairs(d.lost) do have[uid] = true end
    for _, uid in ipairs(d.brought) do
        if not have[uid] then d.lost[#d.lost + 1] = uid; have[uid] = true end
    end
    d.brought = {}
    d.in_heist = false
    d.taken, d.taken_bp, d.taken_set = {}, {}, false
    if #d.lost > 0 then d.free_due = true end
end

-- The heist (or a day of it) ended. Lost: death, taken out at the next menu
-- (a heist never writes the menu inventory).
function Armory.OnMissionEnd(success)
    if not Armory.Enabled() or (PDTI.InSafehouse and PDTI.InSafehouse()) then return 0 end
    -- The last shots' wear is written (armory_wear.lua).
    if PDTI.Wear then pcall(PDTI.Wear.Flush) end
    local d = get()
    if success then
        -- Won: what you left on the ground is lost, what you picked up and
        -- still carry is yours.
        local have = {}
        for _, e in ipairs(d.captured) do have[e.data.uid] = true end
        for _, e in ipairs(picked_now()) do
            if not have[e.data.uid] then d.captured[#d.captured + 1] = e; have[e.data.uid] = true end
        end
        d.brought = dropped_uids()
        -- The parts changed in the heist are yours as they are now.
        if PDTI.HotMod and PDTI.HotMod.RecordWin then pcall(PDTI.HotMod.RecordWin, d) end
        local n = #d.brought
        mark_lost(d)
        Armory._dropped = {}
        Armory.Save()
        if n > 0 then log(string.format("won: %d weapon(s) left on the ground are lost", n)) end
        return n
    end
    -- What you brought: every weapon and part not in the locker now (moves
    -- in the briefing and in the heist count), yours left on the ground, and
    -- what you carried at spawn (fitted or thrown away since).
    d.brought = union(union(Armory.Brought(), dropped_uids()), d.taken)
    d.captured = {}
    Armory._dropped = {}
    local n = #d.brought
    mark_lost(d)
    Armory.Save()
    log(string.format("the heist failed: %d weapon(s) lost", n))
    return n
end

-- Takes the lost weapons and parts out of the menu inventory.
function Armory.ApplyLost()
    local d = get()
    if #d.lost == 0 then return 0 end
    local lost = {}
    for _, uid in ipairs(d.lost) do lost[uid] = true end
    local n = 0
    for _, e in ipairs(owned_items(function(_, item) return lost[math.floor(tonumber(item.data.uid) or 0)] end)) do
        if PDTI.RemoveItem(e.container, e.item.instance_id) then
            n = n + 1
            log(string.format("lost %s", tostring(e.item.data.weapon_id or e.item.data.part_id)))
            -- Insured: it comes back (armory_insurance.lua).
            if e.item.item_id == Armory.ITEM_ID and PDTI.Insurance then
                pcall(PDTI.Insurance.Claim, e.item.data, d.ended_at)
            end
        end
    end
    d.lost = {}
    Armory.Save()
    return n
end

-- At the menu: a heist still marked was left or the game quit in it; the
-- losses come out of the inventory; the game's slots follow your hands.
function Armory.OnMenu()
    if not Armory.Enabled() then return false end
    if PDTI.EnsureProfile then pcall(PDTI.EnsureProfile) end
    local d = get()
    if d.in_heist then
        -- The inventory now is the plan the heist began with (a heist never
        -- writes it): what was not in the locker was brought (a part fitted
        -- in the heist is still an item here: d.taken adds nothing).
        d.brought = Armory.Brought()
        d.captured = {}
        local n = #d.brought
        mark_lost(d)
        Armory.Save()
        log(string.format("a heist was left unfinished: %d weapon(s) lost", n))
    end
    -- The heist's wear onto the weapons first: a lost insured weapon comes
    -- back as worn as it was lost (armory_wear.lua).
    if PDTI.Wear then pcall(PDTI.Wear.Apply, false) end
    pcall(Armory.ApplyLost)
    pcall(Armory.ApplyCaptured)
    if PDTI.HotMod and PDTI.HotMod.ApplyWin then pcall(PDTI.HotMod.ApplyWin) end
    if PDTI.Wear then pcall(PDTI.Wear.Apply, true) end
    -- The game's own weapon mods (its drops) into the locker (armory_parts.lua).
    if PDTI.Parts and PDTI.Parts.ImportGameMods then pcall(PDTI.Parts.ImportGameMods) end
    -- The insurance: policies with nothing left to cover are paid back, the
    -- weapons due back come in (armory_insurance.lua).
    if PDTI.Insurance then
        pcall(PDTI.Insurance.Sweep)
        pcall(PDTI.Insurance.Deliver)
    end
    -- A skin you no longer own comes off (armory_skins.lua).
    if PDTI.WeaponSkins then pcall(PDTI.WeaponSkins.Sweep) end
    pcall(Armory.SyncEquipped)
    return true
end

------------------------------------------------------------------ hooks

Armory._hooks = Armory._hooks or {}
local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(Armory._hooks, "armory", class_name, fn_name, make)
end

local function no(orig)
    return function(self, ...)
        if Armory.Enabled() then return false end
        return orig(self, ...)
    end
end

local function blocked(orig)
    return function(self, ...)
        if Armory.Enabled() then
            PDTI.Hint("No restart: a failed heist is lost", 3)
            return nil
        end
        return orig(self, ...)
    end
end

-- The fail screen: continue leaves the job (as a professional job alone
-- does in the game); it does not retry the day.
local function make_go_super(name)
    return function(orig)
        return function(self, ...)
            local base = rawget(_G, "MissionEndState")
            if Armory.Enabled() and base and type(base[name]) == "function" then return base[name](self, ...) end
            return orig(self, ...)
        end
    end
end

local function make_gameover_continue(orig)
    return function(self, ...)
        if not Armory.Enabled() then return orig(self, ...) end
        if self._continue_blocked and self:_continue_blocked() then return end
        self:gsm():change_state_by_name("empty")
    end
end

-- A dialog in the menu (no HUD there).
function Armory.Tell(text)
    local sm = rawget(_G, "managers") and managers.system_menu
    if not sm then log(text); return false end
    pcall(function()
        sm:show({ title = "Tactical Inventory", text = text,
            button_list = { { text = "OK", is_cancel_button = true } } })
    end)
    return true
end

Armory.GRID_TEXT = "Your weapons are grid items now: buy them at Scarface's market and choose them in the "
    .. "Tactical Inventory (its Locker tab). Parts are sold there too: drag one onto a weapon to fit it, "
    .. "right-click a weapon to see its slots (drag a part out of its slot, or Ctrl+click it, to take it off) "
    .. "or sell it."

local function is_weapon_data(d)
    return type(d) == "table" and (d.category == "primaries" or d.category == "secondaries")
end

-- The game's weapon screen: no buying, selling or modding of weapons there.
local function make_gui_block(only_weapons)
    return function(orig)
        return function(self, d, ...)
            if Armory.Enabled() and (not only_weapons or is_weapon_data(d)) then
                Armory.Tell(Armory.GRID_TEXT)
                return nil
            end
            return orig(self, d, ...)
        end
    end
end

-- The game read its save (at the start, or another profile): its weapon
-- slots are the saved ones again, so they follow your hands once more.
local function make_after_load(orig)
    return function(self, ...)
        local r = orig(self, ...)
        if Armory.Enabled() and not PDTI.session_only then
            if PDTI.EnsureProfile then pcall(PDTI.EnsureProfile) end
            pcall(Armory.SyncEquipped)
        end
        return r
    end
end

-- Pick Up Weapons gives you a weapon through the game's own call, with its
-- data set while it runs: the weapon goes into your slot.
local function make_pickup_hook(orig)
    return function(self, factory_name, ...)
        local mod = rawget(_G, "PickUpWeapons")
        local picked = type(mod) == "table" and mod._picked_up_weapon_data or nil
        if type(picked) ~= "table" or not PDTI.session_only or not Armory.InUse() then
            return orig(self, factory_name, ...)
        end
        local sel = nil
        pcall(function() sel = tweak_data.weapon[picked.weapon_id].use_data.selection_index end)
        -- The weapon it replaces, read now: the game deletes it in the call.
        local entry = sel and selections(self)[sel]
        local before = nil
        if entry and entry.unit ~= nil and (not rawget(_G, "alive") or alive(entry.unit)) then
            before = { enemy = false }
            pcall(function()
                local p = entry.unit:base()._picked_up_weapon_data
                before.enemy = type(p) == "table" and p.is_npc == true
            end)
        end
        local r = orig(self, factory_name, ...)
        local ok, err = pcall(Armory.OnPickup, self, picked, before, sel)
        if not ok then log("the picked-up weapon could not go into your slot: " .. tostring(err)) end
        return r
    end
end

-- No weapon in your hands (the stand-in equipped): no firing, aiming,
-- reloading, fire mode, gadget, inspecting, bipod or underbarrel.
local function holds_nothing(state)
    local u = state and state._equipped_unit
    if u == nil or (rawget(_G, "alive") and not alive(u)) then return false end
    return is_stand_in(u)
end
Armory.HoldsNothing = holds_nothing

local function make_no_action(orig)
    return function(self, t, input, ...)
        if holds_nothing(self) then return nil end
        return orig(self, t, input, ...)
    end
end

local function make_no_steelsight(orig)
    return function(self, t, input, ...)
        if holds_nothing(self) then
            if self._state_data and self._state_data.in_steelsight and self._end_action_steelsight then
                pcall(self._end_action_steelsight, self, t)
            end
            return nil
        end
        return orig(self, t, input, ...)
    end
end

-- The game shows the weapon in hand again after every update: hidden again.
local function make_hide_stand_in(orig)
    return function(self, t, dt, ...)
        local r = orig(self, t, dt, ...)
        if holds_nothing(self) then
            self._equipped_visibility_timer = nil
            local u = self._equipped_unit
            if u:visible() then u:base():set_visibility_state(false) end
        end
        return r
    end
end

-- Ammunition boxes and bags give the stand-in nothing (they stay for you).
local function make_no_ammo(orig)
    return function(self, ...)
        if self._pdti_unarmed then return false, 0 end
        return orig(self, ...)
    end
end
local function make_no_bag_ammo(orig)
    return function(self, ...)
        if self._pdti_unarmed then return 0 end
        return orig(self, ...)
    end
end

Armory.NO_WEAPON_ACTIONS = { "_check_action_primary_attack", "_check_action_reload", "_check_action_weapon_firemode",
    "_check_action_weapon_gadget", "_check_action_deploy_underbarrel", "_check_action_cash_inspect",
    "_check_action_deploy_bipod" }

-- (The main menu's entry calls Armory.OnMenu: safehouse.lua's hook.)
function Armory.InstallHooks()
    local a = wrap("MenuCallbackHandler", "singleplayer_restart", no)
    wrap("MenuCallbackHandler", "_restart_level_visible", no)
    wrap("MenuCallbackHandler", "restart_game", blocked)
    wrap("MenuCallbackHandler", "restart_level", blocked)
    wrap("VoteManager", "restart", blocked)
    wrap("VoteManager", "restart_auto", blocked)
    wrap("GameOverState", "_shut_down_network", make_go_super("_shut_down_network"))
    wrap("GameOverState", "_load_start_menu", make_go_super("_load_start_menu"))
    wrap("GameOverState", "continue", make_gameover_continue)
    wrap("BlackMarketGui", "buy_weapon_callback", make_gui_block(false))
    wrap("BlackMarketGui", "choose_weapon_mods_callback", make_gui_block(false))
    wrap("BlackMarketGui", "sell_item_callback", make_gui_block(true))
    wrap("BlackMarketManager", "load", make_after_load)
    wrap("PlayerInventory", "add_unit_by_factory_name", make_pickup_hook)
    for _, fn in ipairs(Armory.NO_WEAPON_ACTIONS) do wrap("PlayerStandard", fn, make_no_action) end
    wrap("PlayerStandard", "_check_action_steelsight", make_no_steelsight)
    wrap("PlayerStandard", "update", make_hide_stand_in)
    wrap("RaycastWeaponBase", "add_ammo", make_no_ammo)
    wrap("RaycastWeaponBase", "add_ammo_from_bag", make_no_bag_ammo)
    return a
end

pcall(Armory.InstallHooks)
