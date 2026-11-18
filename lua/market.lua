-- The market (0.33.0): what a stashed bag sells for, and contracts.
--
-- Price of a bag = its value (fixed when it was captured: the difficulty and
-- its quality) x the day's drift of its loot type (+-20%, the same all day)
-- x the saturation of that type (each bag of it sold takes 8% off, which
-- comes back 4% a day) x Ethan & Hila's +25% on the day's featured type.
-- "Sell now" after a heist pays a share of this price.
--
-- Contracts: a few offers a day (the same all day). Accept one, then deliver
-- the bags it asks for (that type, at least that quality) from the stash
-- before it is due. It pays the bags' value x its multiplier (no drift or
-- saturation), Continental coins, and the hardest ones a "High roll": the
-- next bag you pick up is at least High.
--
-- The state lives in the stash file (stash.lua) under "market".
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Market = PDTI.Market or {}
PDTI.Market = Market

local log = PDTI.Logger("PDTI MARKET")

Market.DRIFT = 0.2          -- the day's drift: 1 - DRIFT .. 1 + DRIFT
Market.SAT_STEP = 0.08      -- each bag of a type sold
Market.SAT_RECOVER = 0.04   -- comes back per day
Market.SAT_MAX = 0.6        -- the price never drops below 40% by sales
Market.FEATURED = 1.25      -- Ethan & Hila, tier 3
Market.OFFERS = 3
Market.MAX_ACTIVE = 3
Market.HIGH_ROLL = "high_roll"
Market.HISTORY_DAYS = 7     -- the price graph: the last 7 days with today
Market.SALES_KEEP = 20      -- days of the sales log kept (saturation of past days)

-- Contract difficulty: bags asked, the least quality, days to deliver, pay
-- multiplier and coins.
Market.LEVELS = {
    { name = "Easy",   count = { 1, 2 }, quality = { 1, 1 }, days = 1, mult = 1.3, coins = { 1, 2 } },
    { name = "Medium", count = { 2, 3 }, quality = { 1, 2 }, days = 2, mult = 1.6, coins = { 2, 4 } },
    { name = "Hard",   count = { 2, 4 }, quality = { 2, 2 }, days = 3, mult = 2.0, coins = { 4, 6 }, rare = true },
}

-- Loot types contracts ask for: these, and any type that is in your stash.
Market.POOL = { "gold", "money", "diamonds", "coke", "meth", "weapon", "painting", "circuit",
    "counterfeit_money", "artifact_statue" }

function Market.Enabled()
    local stash = PDTI.Stash
    return stash ~= nil and stash.Enabled()
end

------------------------------------------------------------------ the day

-- "YYYY-MM-DD" (tests replace it).
Market.Today = function() return os.date("%Y-%m-%d") end

-- Days since 1970 of a "YYYY-MM-DD" (noon, so summer time does not matter).
function Market.DayNumber(day)
    local y, m, d = tostring(day or ""):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return 0 end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return t and math.floor(t / 86400) or 0
end
local function today_number() return Market.DayNumber(Market.Today()) end

-- A number in [0, 1) from a text: the same text always gives the same number.
function Market.Hash(text)
    local h = 5381
    text = tostring(text)
    for i = 1, #text do h = (h * 33 + text:byte(i)) % 2147483647 end
    for _ = 1, 3 do h = (h * 48271) % 2147483647 end
    return h / 2147483647
end

-- The roll of the day's drift (tests replace it: 0.5 is no drift).
Market.DriftRoll = function(carry_id, day) return Market.Hash("drift|" .. day .. "|" .. carry_id) end

------------------------------------------------------------------ the state

local function blank() return { sat = {}, sales = {}, active = {}, taken = {}, taken_day = "", high_rolls = 0 } end

local function clean_contract(c)
    if type(c) ~= "table" or type(c.carry_id) ~= "string" or type(c.key) ~= "string" then return nil end
    local level = math.floor(tonumber(c.level) or 1)
    if not Market.LEVELS[level] then level = 1 end
    return {
        key = c.key, carry_id = c.carry_id, level = level,
        count = math.max(1, math.min(10, math.floor(tonumber(c.count) or 1))),
        quality = math.max(1, math.min(3, math.floor(tonumber(c.quality) or 1))),
        due = math.floor(tonumber(c.due) or 0),
        mult = math.max(1, math.min(5, tonumber(c.mult) or 1)),
        coins = math.max(0, math.min(20, math.floor(tonumber(c.coins) or 0))),
        rare = type(c.rare) == "string" and c.rare or nil
    }
end

-- What the stash file holds under "market", made safe.
function Market.Sanitize(raw)
    local st = blank()
    if type(raw) ~= "table" then return st end
    if type(raw.sat) == "table" then
        for id, s in pairs(raw.sat) do
            if type(id) == "string" and type(s) == "table" and tonumber(s.level) then
                st.sat[id] = { level = math.max(0, math.min(Market.SAT_MAX, tonumber(s.level))),
                    day = math.floor(tonumber(s.day) or 0) }
            end
        end
    end
    -- The sales log: { carry_id = { ["<day number>"] = count } }.
    if type(raw.sales) == "table" then
        for id, days in pairs(raw.sales) do
            if type(id) == "string" and type(days) == "table" then
                local clean, n = {}, 0
                for d, count in pairs(days) do
                    local dn, c = tonumber(d), tonumber(count)
                    if dn and c and c >= 1 and n < 64 then
                        clean[tostring(math.floor(dn))] = math.min(99, math.floor(c))
                        n = n + 1
                    end
                end
                if n > 0 then st.sales[id] = clean end
            end
        end
    end
    if type(raw.active) == "table" then
        for _, c in ipairs(raw.active) do
            local cc = clean_contract(c)
            if cc and #st.active < Market.MAX_ACTIVE then st.active[#st.active + 1] = cc end
        end
    end
    if type(raw.taken) == "table" and type(raw.taken_day) == "string" then
        st.taken_day = raw.taken_day
        for k, v in pairs(raw.taken) do if type(k) == "string" and v == true then st.taken[k] = true end end
    end
    st.high_rolls = math.max(0, math.min(99, math.floor(tonumber(raw.high_rolls) or 0)))
    return st
end

local function state()
    local stash = PDTI.Stash
    local d = stash and stash._Data and stash._Data()
    if not d then return blank() end
    if type(d.market) ~= "table" or d.market.sat == nil then d.market = Market.Sanitize(d.market) end
    if type(d.market.sales) ~= "table" then d.market.sales = {} end
    return d.market
end
Market._State = state

local function save()
    local stash = PDTI.Stash
    if stash and stash.Save then return stash.Save() end
    return false
end

------------------------------------------------------------------ prices

local function perk_level()
    local perks = PDTI.Perks
    return perks and perks.Level and perks.Level("ecp") or 0
end

-- The loot types contracts and the featured type come from.
function Market.Pool()
    local out, seen = {}, {}
    local carry = rawget(_G, "tweak_data") and tweak_data.carry
    local function add(id)
        if seen[id] then return end
        if type(carry) == "table" and next(carry) ~= nil and carry[id] == nil then return end
        seen[id] = true
        out[#out + 1] = id
    end
    for _, id in ipairs(Market.POOL) do add(id) end
    local stash = PDTI.Stash
    if stash and stash._Data then
        local ids = {}
        for _, b in ipairs(stash._Data().bags or {}) do ids[#ids + 1] = b.carry_id end
        table.sort(ids)
        for _, id in ipairs(ids) do add(id) end
    end
    return out
end

-- Ethan & Hila (tier 3): the day's featured type, or nil.
function Market.Featured(day)
    if perk_level() < 3 then return nil end
    local pool = Market.Pool()
    if #pool == 0 then return nil end
    day = day or Market.Today()
    return pool[math.floor(Market.Hash("featured|" .. day) * #pool) + 1]
end

function Market.Drift(carry_id, day)
    local r = tonumber(Market.DriftRoll(carry_id, day or Market.Today())) or 0.5
    return 1 + Market.DRIFT * (2 * math.max(0, math.min(1, r)) - 1)
end

-- How much of the price sales of this type took off now (0 .. SAT_MAX).
function Market.Saturation(carry_id)
    local s = state().sat[carry_id]
    if not s then return 0 end
    local days = math.max(0, today_number() - (s.day or 0))
    return math.max(0, s.level - Market.SAT_RECOVER * days)
end

function Market.Factor(carry_id)
    local f = Market.Drift(carry_id) * (1 - Market.Saturation(carry_id))
    if carry_id ~= nil and carry_id == Market.Featured() then f = f * Market.FEATURED end
    return f
end

function Market.Price(bag)
    if type(bag) ~= "table" then return 0 end
    return math.floor((tonumber(bag.value) or 0) * Market.Factor(bag.carry_id) + 0.5)
end

-- A bag of this type was sold: the next one sells for less.
function Market.OnSold(carry_id)
    if type(carry_id) ~= "string" then return end
    local st = state()
    local today = today_number()
    st.sat[carry_id] = { level = math.min(Market.SAT_MAX, Market.Saturation(carry_id) + Market.SAT_STEP),
        day = today }
    -- The log for the price graph; old days go.
    local log_of = st.sales[carry_id] or {}
    st.sales[carry_id] = log_of
    local key = tostring(today)
    log_of[key] = (log_of[key] or 0) + 1
    for d in pairs(log_of) do
        if (tonumber(d) or 0) < today - Market.SALES_KEEP then log_of[d] = nil end
    end
end

------------------------------------------------------------------ history

-- "YYYY-MM-DD" of a day number (the inverse of DayNumber).
function Market.DayString(n)
    return os.date("!%Y-%m-%d", math.floor(tonumber(n) or 0) * 86400)
end

-- What sales of this type had taken off at the end of day n (from the log).
function Market.SaturationAt(carry_id, n)
    local log_of = state().sales[carry_id]
    if not log_of then return 0 end
    local sat = 0
    for d = n - Market.SALES_KEEP, n do
        sat = math.max(0, sat - Market.SAT_RECOVER)
        local sold = log_of[tostring(d)]
        if sold then sat = math.min(Market.SAT_MAX, sat + Market.SAT_STEP * sold) end
    end
    return sat
end

-- The game's base value of a Standard bag of this type (its "real price"):
-- its bag value, or the game's "default" one for loot without its own. The
-- game keeps these values encoded (strings), so they are read the way the
-- game reads them.
Market.DEFAULT_VALUE = "default"
local function decode(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local app = rawget(_G, "Application")
        if app and type(app.digest_value) == "function" then
            local ok, n = pcall(app.digest_value, app, v, false)
            if ok and tonumber(n) then return tonumber(n) end
        end
        return tonumber(v)
    end
    return nil
end
function Market.BaseValue(carry_id)
    local td = rawget(_G, "tweak_data")
    local carry = td and td.carry and td.carry[carry_id]
    if type(carry) ~= "table" then return 0 end
    local key = carry.bag_value or Market.DEFAULT_VALUE
    local v
    if type(td.get_value) == "function" then
        local ok, got = pcall(td.get_value, td, "money_manager", "bag_values", key)
        if ok then v = decode(got) end
    end
    if not v then
        local values = td.money_manager and td.money_manager.bag_values
        v = type(values) == "table" and decode(values[key]) or nil
    end
    return math.max(0, math.floor((v or 0) + 0.5))
end

-- The price of a Standard bag of this type over the last HISTORY_DAYS days,
-- the oldest first; the last one is today (as it is now).
-- Each: { day = "YYYY-MM-DD", factor, price }.
function Market.History(carry_id)
    local real = Market.BaseValue(carry_id)
    local today = today_number()
    local out = {}
    for i = Market.HISTORY_DAYS - 1, 0, -1 do
        local n = today - i
        local day = Market.DayString(n)
        local f
        if i == 0 then
            f = Market.Factor(carry_id)
        else
            f = Market.Drift(carry_id, day) * (1 - Market.SaturationAt(carry_id, n))
            if carry_id == Market.Featured(day) then f = f * Market.FEATURED end
        end
        out[#out + 1] = { day = day, factor = f, price = math.floor(real * f + 0.5) }
    end
    return out
end

-- Every loot type you can capture (one per name), by name: { carry_id, name,
-- real, now, change, stashed }. The stash's own rule (Stash.IsLootBag: a bag
-- with a value of its own, not small loot, a vehicle or a mission item that
-- is not secured), so mission items (engines, bike parts, batteries...) are
-- not in it.
function Market.Catalog()
    local td = rawget(_G, "tweak_data")
    local carry = td and td.carry
    if type(carry) ~= "table" then return {} end
    local types = type(carry.types) == "table" and carry.types or nil
    local small = type(carry.small_loot) == "table" and carry.small_loot or {}
    local ids = {}
    local stash = PDTI.Stash
    local capturable = stash and stash.IsLootBag
    for id, t in pairs(carry) do
        if type(id) == "string" and type(t) == "table" and type(t.type) == "string" and t.type ~= "being"
            and (types == nil or types[t.type] ~= nil) and not t.is_vehicle and not small[id]
            and t.bag_value ~= nil and (capturable == nil or capturable(id))
            and Market.BaseValue(id) > 0 then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local LQ = PDTI.LootQuality
    local stashed = {}
    if stash and stash._Data then
        for _, b in ipairs(stash._Data().bags or {}) do stashed[b.carry_id] = (stashed[b.carry_id] or 0) + 1 end
    end
    local out, by_name = {}, {}
    for _, id in ipairs(ids) do
        local name = LQ and LQ.CarryName(id) or id
        local row = by_name[name]
        if row then
            -- The same loot under another id: counted with the first.
            row.stashed = row.stashed + (stashed[id] or 0)
        else
            local real = Market.BaseValue(id)
            row = { carry_id = id, name = name, real = real, now = math.floor(real * Market.Factor(id) + 0.5),
                change = Market.FactorText(id), stashed = stashed[id] or 0 }
            by_name[name] = row
            out[#out + 1] = row
        end
    end
    table.sort(out, function(a, b)
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.carry_id < b.carry_id
    end)
    return out
end

-- "+12%" / "-8%" against the bag's value, "" when the same.
function Market.FactorText(carry_id)
    local pct = math.floor((Market.Factor(carry_id) - 1) * 100 + 0.5)
    if pct == 0 then return "" end
    return (pct > 0 and "+" or "") .. pct .. "%"
end

------------------------------------------------------------------ contracts

local function pick(range, r)
    local lo, hi = range[1], range[2]
    return lo + math.min(hi - lo, math.floor(r * (hi - lo + 1)))
end

-- The day's offers (the same all day), without the ones accepted today.
function Market.Offers(day)
    day = day or Market.Today()
    local pool = Market.Pool()
    if #pool == 0 then return {} end
    local n = Market.OFFERS + (perk_level() >= 2 and 1 or 0)
    local st = state()
    local taken = st.taken_day == day and st.taken or {}
    local out = {}
    for i = 1, n do
        local key = day .. "#" .. i
        local function r(what) return Market.Hash(key .. "|" .. what) end
        local level = pick({ 1, 3 }, r("level"))
        local L = Market.LEVELS[level]
        local offer = {
            key = key, level = level,
            carry_id = pool[math.floor(r("type") * #pool) + 1],
            count = pick(L.count, r("count")),
            quality = pick(L.quality, r("quality")),
            days = L.days,
            mult = L.mult,
            coins = pick(L.coins, r("coins")),
            rare = L.rare and Market.HIGH_ROLL or nil
        }
        if not taken[key] then out[#out + 1] = offer end
    end
    return out
end

-- The accepted contracts; the ones past their day are dropped.
function Market.Active()
    local st = state()
    local today = today_number()
    local kept, dropped = {}, 0
    for _, c in ipairs(st.active) do
        if c.due >= today then kept[#kept + 1] = c else dropped = dropped + 1 end
    end
    if dropped > 0 then
        st.active = kept
        log(dropped .. " contract(s) ran out")
        save()
    end
    return st.active
end

local function find_active(key)
    for i, c in ipairs(Market.Active()) do if c.key == key then return i, c end end
    return nil
end

function Market.Accept(key)
    local offer
    for _, o in ipairs(Market.Offers()) do if o.key == key then offer = o break end end
    if not offer then return false, "That offer is gone" end
    if #Market.Active() >= Market.MAX_ACTIVE then
        return false, "You already have " .. Market.MAX_ACTIVE .. " contracts: deliver one first"
    end
    local st = state()
    local day = Market.Today()
    if st.taken_day ~= day then st.taken, st.taken_day = {}, day end
    st.taken[key] = true
    local c = clean_contract({ key = key, carry_id = offer.carry_id, level = offer.level, count = offer.count,
        quality = offer.quality, due = today_number() + offer.days - 1, mult = offer.mult, coins = offer.coins,
        rare = offer.rare })
    st.active[#st.active + 1] = c
    save()
    log(string.format("accepted: %d x %s (quality %d+), due day %d", c.count, c.carry_id, c.quality, c.due))
    return true
end

-- The stash bags that fit a contract, the least valuable first.
function Market.Matching(c)
    local stash = PDTI.Stash
    local out = {}
    if not (stash and c) then return out end
    for _, b in ipairs(stash.Bags()) do
        if b.carry_id == c.carry_id and (b.quality or 1) >= c.quality then out[#out + 1] = b end
    end
    table.sort(out, function(a, b)
        if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) < (b.value or 0) end
        return a.id < b.id
    end)
    return out
end

function Market.CanDeliver(c) return #Market.Matching(c) >= c.count end

-- Days left to deliver (0: today is the last day).
function Market.DaysLeft(c) return math.max(0, c.due - today_number()) end

local function add_coins(n)
    if n <= 0 then return false end
    local ok = pcall(function() managers.custom_safehouse:add_coins(n, "pdti_contract") end)
    return ok
end

function Market.Deliver(key)
    local i, c = find_active(key)
    if not i then return false, "No such contract" end
    local bags = Market.Matching(c)
    if #bags < c.count then
        return false, string.format("The stash has %d of the %d bags it needs", #bags, c.count)
    end
    local stash = PDTI.Stash
    local value = 0
    for n = 1, c.count do
        value = value + (bags[n].value or 0)
        stash.Remove(bags[n].id)
    end
    local paid = stash.Pay(value * c.mult)
    add_coins(c.coins)
    local st = state()
    if c.rare == Market.HIGH_ROLL then st.high_rolls = st.high_rolls + 1 end
    table.remove(st.active, i)
    save()
    log(string.format("delivered %d x %s: %d, %d coin(s)%s", c.count, c.carry_id, paid, c.coins,
        c.rare and (", " .. c.rare) or ""))
    return true, paid
end

------------------------------------------------------------------ High rolls

function Market.HighRolls() return state().high_rolls end

-- The next bag rolls at least High (loot_quality.lua): one is used.
function Market.TakeHighRoll()
    local st = state()
    if st.high_rolls <= 0 then return false end
    st.high_rolls = st.high_rolls - 1
    save()
    log("a High roll from a contract is used")
    return true
end

function Market.LevelName(level) return (Market.LEVELS[level] or {}).name or "?" end
