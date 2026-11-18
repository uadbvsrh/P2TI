-- The safehouse stash: the loot bags you got out of a heist (0.29.0).
--
-- When a job is won, every bag the crew secured and every bag still in your
-- inventory is captured. The game no longer pays money for bags (contract,
-- small loot, vehicles and XP stay); captured bags wait in a "Captured loot"
-- list where each one goes to the stash or is sold at once for SELL_NOW of
-- its value. A bag in the stash keeps its quality and can be sold later for
-- its full value (the market of 0.31.0 will set that price).
--
-- The stash has its own file next to the inventory save: in a heist the
-- inventory is kept in memory only, but what you captured must not be lost.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Stash = PDTI.Stash or {}
PDTI.Stash = Stash

local log = PDTI.Logger("PDTI STASH")

-- Space, counted in cells of an 8 x 6 grid: a bag takes 2 x 2 (a Compact one
-- 2 x 1); up to 4 Stackable bags of the same kind share one place.
Stash.CELLS = 48
Stash.BAG_CELLS = 4
Stash.COMPACT_CELLS = 2
Stash.SELL_NOW = 0.5      -- "sell now" after a heist pays this share
Stash.SELL_STORED = 1.0   -- a bag sold from the stash without the market
Stash.FILE_VERSION = 1

local function LQ() return PDTI.LootQuality end

function Stash.Enabled()
    local lq = LQ()
    return lq ~= nil and lq.Enabled()
end

------------------------------------------------------------------ saving

local data, loaded_profile = nil, nil

local function file_name(index)
    local own = PDTI.SaveFileName and PDTI.SaveFileName("stash", index)
    if own then return own end
    if index == 1 then return "pdti_stash.json" end
    return "pdti_stash_profile" .. tostring(index) .. ".json"
end
Stash.FileName = file_name

local function path(index)
    return (rawget(_G, "SavePath") or "") .. file_name(index)
end

local function clean_bag(b)
    if type(b) ~= "table" or type(b.carry_id) ~= "string" then return nil end
    local q = math.floor(tonumber(b.quality) or 1)
    if q < 1 or q > 3 then q = 1 end
    return {
        id = math.floor(tonumber(b.id) or 0),
        carry_id = b.carry_id,
        quality = q,
        mods = type(b.mods) == "string" and b.mods or "",
        value = math.max(0, math.floor(tonumber(b.value) or 0))
    }
end

local function clean_list(list, out)
    if type(list) ~= "table" then return out end
    for _, b in ipairs(list) do
        local c = clean_bag(b)
        if c then out[#out + 1] = c end
    end
    return out
end

local function sanitize(raw)
    local d = { version = Stash.FILE_VERSION, next_id = 1, bags = {}, pending = {}, known = {} }
    if type(raw) ~= "table" then return d end
    clean_list(raw.bags, d.bags)
    clean_list(raw.pending, d.pending)
    clean_list(raw.known, d.known)
    local top = 0
    for _, list in ipairs({ d.bags, d.pending }) do
        for _, b in ipairs(list) do if b.id > top then top = b.id end end
    end
    d.next_id = math.max(top + 1, math.floor(tonumber(raw.next_id) or 1))
    -- The market's state (market.lua) lives in the same file.
    local market = PDTI.Market
    if market and market.Sanitize then d.market = market.Sanitize(raw.market) end
    -- A bag without an id (or with the id of another) gets a new one.
    local seen = {}
    for _, list in ipairs({ d.bags, d.pending }) do
        for _, b in ipairs(list) do
            if b.id < 1 or seen[b.id] then b.id = d.next_id; d.next_id = d.next_id + 1 end
            seen[b.id] = true
        end
    end
    return d
end
Stash._Sanitize = sanitize

local function read_file(index)
    local f = io.open(path(index), "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local js = rawget(_G, "json")
    if not js or type(text) ~= "string" or text == "" then return nil end
    local ok, raw = pcall(js.decode, text)
    if not ok then log("the stash file could not be read: " .. tostring(raw)); return nil end
    return raw
end

function Stash.Load(index)
    index = index or (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1
    data = sanitize(read_file(index))
    loaded_profile = index
    return data
end

local function get()
    local index = (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1
    if not data or loaded_profile ~= index then Stash.Load(index) end
    return data
end
Stash._Data = get

-- Written at once, also in a heist (the stash is not part of the inventory
-- the heist keeps in memory).
function Stash.Save()
    local d = get()
    local js = rawget(_G, "json")
    if not js then log("no JSON library: the stash is not saved"); return false end
    local ok, text = pcall(js.encode, d)
    if not ok or type(text) ~= "string" then log("the stash could not be encoded"); return false end
    local p = path(loaded_profile or 1)
    local tmp = p .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then log("the stash could not be written: " .. tostring(err)); return false end
    local wrote = f:write(text)
    f:close()
    if not wrote then os.remove(tmp); log("the stash could not be written"); return false end
    os.remove(p)
    if not os.rename(tmp, p) then log("the stash file could not be replaced"); return false end
    return true
end

------------------------------------------------------------------ the bags

local function new_bag(carry_id, info, value)
    local d = get()
    local bag = {
        id = d.next_id, carry_id = carry_id, quality = info and info.quality or 1,
        mods = info and table.concat(info.mods or {}, ",") or "", value = value or 0
    }
    d.next_id = d.next_id + 1
    return bag
end

function Stash.Bags() return get().bags end
function Stash.Pending() return get().pending end

local function has(bag, mod)
    local lq = LQ()
    return lq ~= nil and lq.Has(bag, mod)
end

local function cells_of(bag)
    return has(bag, "compact") and Stash.COMPACT_CELLS or Stash.BAG_CELLS
end

local function key_of(bag)
    return bag.carry_id .. "|" .. tostring(bag.quality) .. "|" .. tostring(bag.mods)
end

-- The cells the bags take (Stackable bags of the same kind share places).
function Stash.CellsUsed(bags)
    bags = bags or get().bags
    local used, stacks = 0, {}
    local per_stack = (LQ() and LQ().STACK) or 4
    for _, bag in ipairs(bags) do
        if has(bag, "stackable") then
            local k = key_of(bag)
            local n = (stacks[k] or 0) + 1
            stacks[k] = n
            if (n - 1) % per_stack == 0 then used = used + cells_of(bag) end
        else
            used = used + cells_of(bag)
        end
    end
    return used
end

-- The vault's room adds places (perks.lua).
function Stash.Capacity()
    local perks = PDTI.Perks
    local extra = perks and perks.StashCells and perks.StashCells(Stash.BAG_CELLS) or 0
    return Stash.CELLS + extra
end

-- The share sell-now pays (Scarface's room raises it, perks.lua).
function Stash.SellNowShare()
    local perks = PDTI.Perks
    if perks and perks.SellNowShare then return perks.SellNowShare(Stash.SELL_NOW) end
    return Stash.SELL_NOW
end

function Stash.HasRoomFor(bag)
    local bags = get().bags
    bags[#bags + 1] = bag
    local fits = Stash.CellsUsed(bags) <= Stash.Capacity()
    bags[#bags] = nil
    return fits
end

-- What the game would have paid for this bag at this job's difficulty
-- (risk and skills included, before the offshore split), times its quality.
function Stash.BagValue(carry_id, quality)
    local ok, base = pcall(function() return managers.money:get_secured_bonus_bag_value(carry_id, 1) end)
    if not ok or type(base) ~= "number" then base = 0 end
    local tier = LQ() and LQ().TIERS[quality or 1]
    return math.floor(base * (tier and tier.value or 1) + 0.5)
end

local function market()
    local m = PDTI.Market
    return m and m.Price and m or nil
end

local function pay(amount)
    amount = math.floor((tonumber(amount) or 0) + 0.5)
    if amount <= 0 then return 0 end
    -- The game's own way to pay out a heist: split into spending and offshore.
    local ok = pcall(function() managers.money:add_to_total(amount, "pdti_loot") end)
    return ok and amount or 0
end

-- On the heist's end screen a sale now shows as the bags' line of the payout
-- (the money itself is paid by pay(); this only changes what is counted up).
local function show_on_end_screen(paid)
    if not Stash.at_end_screen or paid <= 0 then return end
    pcall(function()
        local mm = managers.money
        mm._bag_payout = (tonumber(mm._bag_payout) or 0) + paid
    end)
end

local function find(list, id)
    for i, b in ipairs(list) do if b.id == id then return i, b end end
    return nil
end

function Stash.Name(bag)
    local lq = LQ()
    local name = lq and lq.CarryName(bag.carry_id) or bag.carry_id
    local tier = lq and lq.TIERS[bag.quality]
    if tier and bag.quality > 1 then name = name .. " (" .. tier.name .. ")" end
    return name
end

-- The market's price today (market.lua), or the bag's value.
function Stash.StoredPrice(bag)
    local m = market()
    if m then return m.Price(bag) end
    return math.floor((bag.value or 0) * Stash.SELL_STORED + 0.5)
end
function Stash.SellNowPrice(bag) return math.floor(Stash.StoredPrice(bag) * Stash.SellNowShare() + 0.5) end

local function sold(bag)
    local m = market()
    if m and m.OnSold then m.OnSold(bag.carry_id) end
end

Stash.Pay = pay

-- A bag leaves the stash without a sale (a contract takes it).
function Stash.Remove(id)
    local d = get()
    local i = find(d.bags, id)
    if not i then return false end
    table.remove(d.bags, i)
    return true
end

-- A captured bag goes to the stash (if it fits).
function Stash.Keep(id)
    local d = get()
    local i, bag = find(d.pending, id)
    if not i then return false, "no such bag" end
    if not Stash.HasRoomFor(bag) then return false, "The safehouse stash is full: sell something first" end
    table.remove(d.pending, i)
    d.bags[#d.bags + 1] = bag
    Stash.Save()
    log("stashed " .. Stash.Name(bag))
    return true
end

-- A captured bag is sold at once, for less.
function Stash.SellNow(id)
    local d = get()
    local i, bag = find(d.pending, id)
    if not i then return false, "no such bag" end
    local paid = pay(Stash.SellNowPrice(bag))
    show_on_end_screen(paid)
    sold(bag)
    table.remove(d.pending, i)
    Stash.Save()
    log(string.format("sold %s at once for %d", Stash.Name(bag), paid))
    return true, paid
end

-- A bag from the stash is sold.
function Stash.Sell(id)
    local d = get()
    local i, bag = find(d.bags, id)
    if not i then return false, "no such bag" end
    local paid = pay(Stash.StoredPrice(bag))
    sold(bag)
    table.remove(d.bags, i)
    Stash.Save()
    log(string.format("sold %s from the stash for %d", Stash.Name(bag), paid))
    return true, paid
end

-- Every captured bag that fits goes to the stash; returns how many did not.
function Stash.KeepAll()
    local d = get()
    local left = {}
    for _, bag in ipairs(d.pending) do
        if Stash.HasRoomFor(bag) then d.bags[#d.bags + 1] = bag else left[#left + 1] = bag end
    end
    d.pending = left
    Stash.Save()
    return #left
end

function Stash.SellAllNow()
    local d = get()
    local total = 0
    for _, bag in ipairs(d.pending) do
        total = total + pay(Stash.SellNowPrice(bag))
        sold(bag)
    end
    show_on_end_screen(total)
    d.pending = {}
    Stash.Save()
    log("sold every captured bag at once for " .. tostring(total))
    return total
end

------------------------------------------------------------------ capture

-- Bags whose quality is known when they are secured (thrown into the secure
-- zone by you, or in your hands at the escape). Kept in the file, because the
-- secured list of a job of several days is counted on its last day.
function Stash.Remember(carry_id, info)
    local d = get()
    d.known[#d.known + 1] = new_bag(carry_id, info, 0)
end

local function take_known(carry_id)
    local known = get().known
    for i, b in ipairs(known) do
        if b.carry_id == carry_id then
            table.remove(known, i)
            return LQ().InfoOf(b)
        end
    end
    return nil
end

-- A bag of loot (not small loot, a vehicle, a person or a special item).
local function is_bag(carry_id)
    local carry = rawget(_G, "tweak_data") and tweak_data.carry
    if type(carry) ~= "table" or type(carry_id) ~= "string" then return false end
    if type(carry.small_loot) == "table" and carry.small_loot[carry_id] then return false end
    local t = carry[carry_id]
    if type(t) ~= "table" or t.is_vehicle or t.skip_exit_secure then return false end
    return t.bag_value ~= nil
end
Stash.IsLootBag = is_bag

local function secured_list()
    local ok, list = pcall(function() return managers.loot._global.secured end)
    if ok and type(list) == "table" then return list end
    return {}
end

local function on_last_stage()
    local ok, last = pcall(function() return managers.job:on_last_stage() end)
    return not ok or last ~= false
end

local function current_job()
    local ok, id = pcall(function() return managers.job:current_job_id() end)
    return ok and id or nil
end

local function capture(list, carry_id, info)
    info = info or LQ().Roll(carry_id)
    list[#list + 1] = new_bag(carry_id, info, Stash.BagValue(carry_id, info.quality))
end

-- The job (or one day of it) ended; the game has secured the bags in hands.
function Stash.OnMissionEnd(success)
    if not Stash.Enabled() then return 0 end
    local job = current_job()
    if job == "chill" or job == "chill_combat" then return 0 end
    local d = get()
    if not success then
        -- A lost job: nothing is captured, and what was remembered goes too.
        if #d.known > 0 then d.known = {}; Stash.Save() end
        log("the job was lost: no loot captured")
        return 0
    end
    local lq = LQ()
    local count = 0
    -- The bag in your hands was secured by the game: remember its quality.
    local hands = lq.HandsData and lq.HandsData()
    local hands_info = hands and lq.InfoOf(hands)
    if hands_info and type(hands.carry_id) == "string" then Stash.Remember(hands.carry_id, hands_info) end
    -- Bags in your inventory go with you, unless you are in custody.
    local in_custody = PDTI.PlayerUnit ~= nil and PDTI.PlayerUnit() == nil
    for _, entry in ipairs(PDTI.FindItems(function(_, item)
        return item.item_id == "loot_bag" and type(item.data) == "table" and not item.data.active
    end)) do
        local bag = entry.item.data
        if in_custody then
            log("in custody: the " .. tostring(bag.carry_id) .. " bag in your inventory is lost")
        elseif is_bag(bag.carry_id) then
            -- Every bag of a stack, each with its own roll.
            local amount = math.max(1, entry.item.amount or 1)
            local rolls = lq.StackRolls(bag, amount)
            for i = 1, amount do
                capture(d.pending, bag.carry_id, rolls[i])
                count = count + 1
            end
        end
    end
    -- The secured bags are counted on the job's last day.
    if on_last_stage() then
        for _, s in ipairs(secured_list()) do
            if type(s) == "table" and is_bag(s.carry_id) then
                capture(d.pending, s.carry_id, take_known(s.carry_id))
                count = count + 1
            end
        end
        d.known = {}
    end
    Stash.Save()
    Stash.at_end_screen = true
    Stash.window_failed = false
    Stash.window_tries = 0
    pcall(Stash.InstallHooks) -- the end screen's classes are surely there now
    log(string.format("captured %d bag(s), %d waiting for a choice", count, #d.pending))
    return count
end

------------------------------------------------------------------ hooks

local hooks = {}

local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(hooks, "stash", class_name, fn_name, make)
end

-- The game pays nothing for loot bags any more (vehicles stay paid):
-- get_secured_bonus_bags_value(level_id, is_vehicle) and
-- get_secured_mandatory_bags_value(is_vehicle).
local function make_zero_bonus(orig)
    return function(self, level_id, is_vehicle, ...)
        if not is_vehicle and Stash.Enabled() then return 0 end
        return orig(self, level_id, is_vehicle, ...)
    end
end

local function make_zero_mandatory(orig)
    return function(self, is_vehicle, ...)
        if not is_vehicle and Stash.Enabled() then return 0 end
        return orig(self, is_vehicle, ...)
    end
end

local function make_mission_end(orig)
    return function(self, ...)
        Stash.at_end_screen = false
        local r = orig(self, ...)
        local ok, err = pcall(Stash.OnMissionEnd, self._success == true)
        if not ok then log("capture failed: " .. tostring(err)) end
        -- A failed heist loses the weapons you brought (armory.lua).
        local armory = PDTI.Armory
        if armory and armory.OnMissionEnd then
            local aok, aerr = pcall(armory.OnMissionEnd, self._success == true)
            if not aok then log("the armory failed at the end: " .. tostring(aerr)) end
        end
        pcall(function()
            log("the game's payout for bags: " .. tostring(managers.money:get_payouts().bag_payout))
        end)
        return r
    end
end

------------------------------------------------------------------ end screen

-- After a won job the end screen waits until every captured bag is stashed
-- or sold: the payout is not counted up and you cannot continue before.
-- If the window cannot be shown (no BeardLib) nothing waits: the bags stay
-- in Captured for the menu.
function Stash.Holding()
    return Stash.at_end_screen == true and not Stash.window_failed and Stash.Enabled() and #get().pending > 0
end

-- The window may need a few frames ("wait": BeardLib makes it on its next
-- update); after WINDOW_TRIES frames without it, nothing waits any more.
Stash.WINDOW_TRIES = 600
local function show_capture()
    if PDTI.IsCaptureOpen and PDTI.IsCaptureOpen() then return end
    local ok, opened = false, "no window"
    if PDTI.SetCaptureOpen then ok, opened = pcall(PDTI.SetCaptureOpen, true) end
    if ok and opened == "wait" then
        Stash.window_tries = (Stash.window_tries or 0) + 1
        if Stash.window_tries < Stash.WINDOW_TRIES then return end
    end
    if not ok or opened ~= true then
        Stash.window_failed = true
        log("the captured loot window could not open (" .. tostring(opened) .. "): choose in the menu")
    end
end
Stash._ShowCapture = show_capture

local function make_continue_blocked(orig)
    return function(self, ...)
        if Stash.Holding() then
            show_capture()
            if Stash.Holding() then return true end
        end
        return orig(self, ...)
    end
end

-- The end screen's first stage counts up the money: it waits for the choice.
local function make_endscreen_update(orig)
    return function(self, t, dt, ...)
        if self._stage == 1 and Stash.Holding() then
            show_capture()
            if Stash.Holding() then return end
        end
        return orig(self, t, dt, ...)
    end
end

-- A bag of known quality is secured (where the mission runs: host or offline).
local function make_carry_element(orig)
    return function(self, instigator, ...)
        local op = self._values and self._values.operation
        if (op == "secure" or op == "secure_silent") and Stash.Enabled() then
            local cd = PDTI.CarryExt(instigator)
            local info = cd and cd._pdti_quality
            if type(info) == "table" then
                pcall(function()
                    if cd:value() > 0 then Stash.Remember(cd:carry_id(), info) end
                end)
            end
        end
        return orig(self, instigator, ...)
    end
end

function Stash.InstallHooks()
    if not Stash.Enabled() then return false end
    local a = wrap("LootManager", "get_secured_bonus_bags_value", make_zero_bonus)
    local b = wrap("LootManager", "get_secured_mandatory_bags_value", make_zero_mandatory)
    local c = wrap("MissionEndState", "at_enter", make_mission_end)
    local e = wrap("ElementCarry", "on_executed", make_carry_element)
    local f = wrap("MissionEndState", "_continue_blocked", make_continue_blocked)
    local g = wrap("HUDStageEndScreen", "update", make_endscreen_update)
    return a and b and c and e and f and g
end

function Stash.Reset()
    data, loaded_profile = nil, nil
    Stash.at_end_screen = false
    Stash.window_failed = false
end
