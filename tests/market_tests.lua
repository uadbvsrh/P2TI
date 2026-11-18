-- 0.33.0: the market (prices of the day, saturation) and contracts.
--   luajit tests/market_tests.lua
local script = arg and arg[0] or "tests/market_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_market") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()
ENV.load_mod(ROOT, false)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -99) - b) < (eps or 1e-6) end

local Market, Stash, LQ = PDTI.Market, PDTI.Stash, PDTI.LootQuality

-- The game: money, coins, room tiers.
local paid, coins = 0, 0
managers.money = { add_to_total = function(_, amount) paid = paid + amount end }
local tiers = {}
local safehouse = { _global = { rooms = {} } }
function safehouse:get_room_current_tier(room) return tiers[room] or 1 end
function safehouse:add_coins(n) coins = coins + n end
local function set_tier(room, tier) tiers[room] = tier; safehouse._global.rooms[room] = { tier_current = tier } end
managers.custom_safehouse = safehouse

local today = "2026-11-17"
Market.Today = function() return today end

local function fresh()
  os.remove(TMP .. "pdti_stash.json")
  Stash.Reset()
  Stash.Load(1)
  paid, coins = 0, 0
  today = "2026-11-17"
end

local function add_bag(carry_id, quality, value)
  local d = Stash._Data()
  local bag = { id = d.next_id, carry_id = carry_id, quality = quality or 1, mods = "", value = value or 1000 }
  d.next_id = d.next_id + 1
  d.bags[#d.bags + 1] = bag
  return bag
end

---------------------------------------------------------------- the day

T("days count by one", Market.DayNumber("2026-11-18") - Market.DayNumber("2026-11-17") == 1)
T("  across a month", Market.DayNumber("2026-12-01") - Market.DayNumber("2026-11-30") == 1)
T("  a bad day is 0", Market.DayNumber("soon") == 0 and Market.DayNumber(nil) == 0)
T("the hash is the same for the same text, in [0, 1)", Market.Hash("a") == Market.Hash("a")
  and Market.Hash("a") >= 0 and Market.Hash("a") < 1 and Market.Hash("a") ~= Market.Hash("b"))

---------------------------------------------------------------- prices

fresh()
local roll = 0.5
Market.DriftRoll = function() return roll end
T("no drift: the price is the bag's value", Market.Price({ carry_id = "gold", value = 1000 }) == 1000)
roll = 0
T("the lowest drift: -20%", Market.Price({ carry_id = "gold", value = 1000 }) == 800)
roll = 1
T("the highest: +20%", Market.Price({ carry_id = "gold", value = 1000 }) == 1200)
T("  shown as +20%", Market.FactorText("gold") == "+20%")
roll = 0.5
T("  no change: no text", Market.FactorText("gold") == "")

-- The real drift: the same all day, inside the range, not the same every day.
local real_roll = function(carry_id, day) return Market.Hash("drift|" .. day .. "|" .. carry_id) end
Market.DriftRoll = real_roll
local a, b = Market.Drift("gold"), Market.Drift("gold")
local seen, inside = {}, true
for d = 1, 20 do
  local v = Market.Drift("gold", string.format("2026-11-%02d", d))
  if v < 0.8 - 1e-9 or v > 1.2 + 1e-9 then inside = false end
  seen[string.format("%.4f", v)] = true
end
local kinds = 0
for _ in pairs(seen) do kinds = kinds + 1 end
T("the day's drift is the same all day", a == b)
T("  always within +-20%, and it changes from day to day", inside and kinds >= 10, kinds)
T("  gold and money drift differently", Market.Drift("gold", "2026-11-03") ~= Market.Drift("money", "2026-11-03"))
Market.DriftRoll = function() return 0.5 end

-- Saturation.
fresh()
local g1 = add_bag("gold", 1, 1000)
local g2 = add_bag("gold", 1, 1000)
add_bag("money", 1, 1000)
local ok, got = Stash.Sell(g1.id)
T("a stashed bag sells for the market's price", ok and got == 1000 and paid == 1000)
T("  the next gold sells for 8% less", Stash.StoredPrice(g2) == 920 and Market.FactorText("gold") == "-8%")
T("  money does not", Stash.StoredPrice({ carry_id = "money", value = 1000 }) == 1000)
today = "2026-11-18"
T("a day later half of it is back (4%)", Stash.StoredPrice(g2) == 960)
today = "2026-11-19"
T("two days: all of it", Stash.StoredPrice(g2) == 1000)
today = "2026-11-17"
for _ = 1, 20 do Market.OnSold("coke") end
T("many sales: never below 40%", near(Market.Saturation("coke"), 0.6))
T("sell now: a share of the market's price", Stash.SellNowPrice(g2) == math.floor(920 * Stash.SellNowShare() + 0.5))
T("a bag with no loot type is not featured", Market.Factor(nil) == 1)

---------------------------------------------------------------- contracts

fresh()
local offers = Market.Offers()
T("three offers a day", #offers == 3)
local same = Market.Offers()
T("  the same all day", same[1].key == offers[1].key and same[1].carry_id == offers[1].carry_id
  and same[2].count == offers[2].count and same[3].level == offers[3].level)
local fine = true
for d = 1, 28 do
  for _, o in ipairs(Market.Offers(string.format("2026-02-%02d", d))) do
    local L = Market.LEVELS[o.level]
    if not L or o.count < L.count[1] or o.count > L.count[2] or o.quality < L.quality[1] or o.quality > L.quality[2]
      or o.coins < L.coins[1] or o.coins > L.coins[2] or o.days ~= L.days or o.mult ~= L.mult
      or (L.rare and o.rare ~= Market.HIGH_ROLL) or (not L.rare and o.rare) or type(o.carry_id) ~= "string" then
      fine = false
    end
  end
end
T("  every offer keeps to its level (a month of them)", fine)
set_tier("ecp", 2)
T("Ethan & Hila tier 2: four offers", #Market.Offers() == 4)
T("  tier 2: no featured type", Market.Featured() == nil)
set_tier("ecp", 1)

-- Accepting.
fresh()
offers = Market.Offers()
local first = offers[1]
T("accept an offer", Market.Accept(first.key) == true and #Market.Active() == 1)
T("  it leaves the offers", #Market.Offers() == 2)
ok = Market.Accept(first.key)
T("  not twice", ok == false)
T("  due after its days", Market.DaysLeft(Market.Active()[1]) == first.days - 1)
Market.Accept(Market.Offers()[1].key)
Market.Accept(Market.Offers()[1].key)
T("three contracts taken", #Market.Active() == 3)
-- A fourth (an offer of the next day, with every contract still due).
for _, cc in ipairs(Market._State().active) do cc.due = cc.due + 5 end
today = "2026-11-18"
local why
ok, why = Market.Accept(Market.Offers()[1].key)
T("a fourth contract is refused", ok == false and tostring(why):find("3 contracts") ~= nil, why)
T("a new day: the offers are full again", #Market.Offers() == 3)
today = "2026-11-30"
T("past their day the contracts are gone", #Market.Active() == 0)

-- Delivering.
fresh()
first = Market.Offers()[1]
Market.Accept(first.key)
local c = Market.Active()[1]
c.quality = 2   -- at least High, so a Standard bag does not count
ok, why = Market.Deliver(c.key)
T("deliver with no bags: refused, says how many", ok == false and tostring(why):find("0 of") ~= nil, why)
for _ = 1, c.count - 1 do add_bag(c.carry_id, 3, 5000) end
add_bag(c.carry_id == "gold" and "money" or "gold", 3, 5000)
add_bag(c.carry_id, 1, 100)
T("  too few of the right bags: refused", Market.Deliver(c.key) == false and not Market.CanDeliver(c))
add_bag(c.carry_id, c.quality, 2000)
add_bag(c.carry_id, 3, 9000)
T("  enough: it can be delivered", Market.CanDeliver(c))
local before = #Stash.Bags()
ok, got = Market.Deliver(c.key)
-- The cheapest bags that fit: 2000 and the 5000s (the 9000 stays).
local want = (2000 + 5000 * (c.count - 1)) * c.mult
T("delivered: pays the bags' value x its multiplier", ok and near(got, math.floor(want + 0.5), 1) and near(paid, got, 1),
  tostring(got) .. " vs " .. want)
T("  the bags leave the stash, the dearest stays", #Stash.Bags() == before - c.count
  and #Market.Matching(c) == 1 and Market.Matching(c)[1].value == 9000)
T("  the coins are paid", coins == c.coins)
T("  the contract is done", #Market.Active() == 0 and Market.Deliver(c.key) == false)

-- A Hard contract: a High roll.
fresh()
local hard
for d = 1, 28 do
  today = string.format("2026-03-%02d", d)
  for _, o in ipairs(Market.Offers()) do if o.level == 3 then hard = o break end end
  if hard then break end
end
T("a Hard offer turns up within a month", hard ~= nil)
if hard then
  Market.Accept(hard.key)
  for _ = 1, hard.count do add_bag(hard.carry_id, 2, 1000) end
  T("  delivered", Market.Deliver(hard.key) == true)
  T("  a High roll waits", Market.HighRolls() == 1)
  LQ.random = function() return 0 end
  local info = LQ.ForPickup("gold")
  T("  the next bag picked up is High", info.quality == 2 and #info.mods == 1 and Market.HighRolls() == 0)
  info = LQ.ForPickup("gold")
  T("  the one after rolls as usual", info.quality == 1)
  Market._State().high_rolls = 1
  LQ.random = function() return 0.995 end
  info = LQ.ForPickup("gold")
  T("  a bag that rolls better anyway keeps the High roll for later", info.quality == 3 and Market.HighRolls() == 1)
  LQ.random = function() return 0 end
end

---------------------------------------------------------------- saving

fresh()
Market.OnSold("gold")
Market.Accept(Market.Offers()[2].key)
Market._State().high_rolls = 2
Stash.Save()
Stash.Reset()
Stash.Load(1)
local st = Market._State()
T("saved and loaded: saturation, contracts, High rolls", st.sat.gold ~= nil and near(st.sat.gold.level, 0.08)
  and #st.active == 1 and st.high_rolls == 2 and #Market.Offers() == 2)
local clean = Market.Sanitize({ sat = { gold = { level = 9 }, x = "bad" }, high_rolls = -4,
  active = { { key = "k", carry_id = "gold", level = 7, count = 99, quality = 9, mult = 50, coins = 99 }, "bad" } })
T("bad data is made safe", near(clean.sat.gold.level, Market.SAT_MAX) and clean.sat.x == nil and clean.high_rolls == 0
  and #clean.active == 1 and clean.active[1].level == 1 and clean.active[1].count == 10 and clean.active[1].quality == 3
  and clean.active[1].mult == 5 and clean.active[1].coins == 20)
local many = {}
for i = 1, 6 do many[i] = { key = "k" .. i, carry_id = "gold" } end
T("a file with too many contracts keeps 3", #Market.Sanitize({ active = many }).active == Market.MAX_ACTIVE)
T("nothing at all: an empty market", #Market.Sanitize(nil).active == 0 and Market.Sanitize("x").high_rolls == 0)

---------------------------------------------------------------- Ethan & Hila tier 3

fresh()
set_tier("ecp", 3)
local featured = Market.Featured()
T("tier 3: a featured type today", type(featured) == "string")
T("  the same all day", Market.Featured() == featured)
T("  it sells for +25%", Market.Price({ carry_id = featured, value = 1000 }) == 1250)
local other = featured == "gold" and "money" or "gold"
T("  the others do not", Market.Price({ carry_id = other, value = 1000 }) == 1000)
T("  four offers too", #Market.Offers() == 4)
set_tier("ecp", 1)
T("without the room: nothing featured", Market.Featured() == nil)

---------------------------------------------------------------- 0.34.0: prices and the graph

fresh()
T("a day number back to its date", Market.DayString(Market.DayNumber("2026-11-17")) == "2026-11-17"
  and Market.DayString(Market.DayNumber("2027-01-01")) == "2027-01-01")
tweak_data.money_manager = { bag_values = { gold = 2875, money = 1500, diamonds = 1000 } }
tweak_data.carry.small_loot = { gold_ring = true }
tweak_data.carry.gold_ring = { type = "light", bag_value = "gold" }
tweak_data.carry.gold_car = { type = "heavy", bag_value = "gold", is_vehicle = true }
tweak_data.carry.gold_two = { type = "heavy", bag_value = "gold", name_id = "gold" }
T("the real price is the game's bag value", Market.BaseValue("gold") == 2875 and Market.BaseValue("person") == 0
  and Market.BaseValue("nothing") == 0)
add_bag("money", 1, 5000)
add_bag("money", 2, 9000)
local cat = Market.Catalog()
local by = {}
for _, r in ipairs(cat) do by[r.carry_id] = r end
T("the list: every loot type with a value, by name", #cat == 3 and cat[1].name == "diamonds" and cat[2].name == "gold"
  and cat[3].name == "money", #cat)
T("  not small loot, not vehicles, not without a value", not by.gold_ring and not by.gold_car and not by.person
  and not by.circuit)
T("  now and real; how many are in the stash", by.money.real == 1500 and by.money.now == 1500 and by.money.stashed == 2
  and by.gold.stashed == 0)
Market.DriftRoll = function() return 1 end
T("  now follows today's change", Market.Catalog()[2].now == 3450 and Market.Catalog()[2].change == "+20%")
Market.DriftRoll = function() return 0.5 end

-- The 7 days.
local h = Market.History("gold")
T("the graph: 7 days, the last is today", #h == 7 and h[7].day == "2026-11-17" and h[1].day == "2026-11-11")
T("  no sales, no drift: the real price every day", h[1].price == 2875 and h[7].price == 2875)
Market.DriftRoll = function(_, day) return day == "2026-11-14" and 0 or 0.5 end
T("  a past day's drift is that day's", Market.History("gold")[4].price == 2300 and Market.History("gold")[5].price == 2875)
Market.DriftRoll = function() return 0.5 end
today = "2026-11-15"
Market.OnSold("gold"); Market.OnSold("gold")
today = "2026-11-17"
h = Market.History("gold")
T("  two sales on the 15th: -16% that day", h[5].price == math.floor(2875 * 0.84 + 0.5), h[5].price)
T("  -12% on the 16th (4% back)", h[6].price == math.floor(2875 * 0.88 + 0.5), h[6].price)
T("  today: the live price (-8%)", h[7].price == math.floor(2875 * 0.92 + 0.5) and h[7].price == math.floor(2875 * Market.Factor("gold") + 0.5))
T("  before the sales: the full price", h[4].price == 2875)
today = "2026-12-20"
Market.OnSold("money")
Market.OnSold("gold")
local kept = 0
for d in pairs(Market._State().sales.gold) do kept = kept + 1; assert(tonumber(d) >= Market.DayNumber(today) - 20) end
T("  old days go when a sale is logged", kept == 1, kept)
today = "2026-11-17"
Stash.Save(); Stash.Reset(); Stash.Load(1)
T("the log is saved", Market._State().sales.money ~= nil and Market._State().sales.money[tostring(Market.DayNumber("2026-12-20"))] == 1)
local cl = Market.Sanitize({ sales = { gold = { ["20000"] = 3, bad = 2, ["20001"] = -1 }, x = 5 } })
T("  bad log entries are dropped", cl.sales.gold["20000"] == 3 and cl.sales.gold.bad == nil and cl.sales.gold["20001"] == nil
  and cl.sales.x == nil)
-- The game keeps its values encoded (strings), and loot without a value of
-- its own is worth the game's default.
local real_app = Application.digest_value
Application.digest_value = function(_, v, enc)
  if type(v) == "string" and v:sub(1, 4) == "enc:" then return tonumber(v:sub(5)) end
  return real_app(_, v, enc)
end
tweak_data.money_manager.bag_values = { gold = "enc:2875", money = "enc:1500", diamonds = "enc:1000", default = "enc:100" }
T("encoded values are read as the game reads them", Market.BaseValue("gold") == 2875 and Market.BaseValue("money") == 1500)
tweak_data.get_value = function() return "enc:4321" end
T("  the game's get_value first", Market.BaseValue("diamonds") == 4321)
tweak_data.get_value = nil
tweak_data.carry.engine_01 = { type = "heavy" }
tweak_data.carry.no_type = { bag_value = "gold" }
tweak_data.carry.gold_mission = { type = "heavy", bag_value = "gold", skip_exit_secure = true }
local seen_ids = {}
for _, r in ipairs(Market.Catalog()) do seen_ids[r.carry_id] = r end
T("mission items you cannot capture are left out (no value of their own)", seen_ids.engine_01 == nil
  and Market.BaseValue("engine_01") == 100)
T("  and the ones the escape does not secure", seen_ids.gold_mission == nil)
T("  capturable loot stays", seen_ids.gold ~= nil and seen_ids.money ~= nil)
T("  people and entries that are not bags are left out", not seen_ids.person and not seen_ids.no_type)
tweak_data.money_manager.bag_values = { gold = 2875, money = 1500, diamonds = 1000 }
Application.digest_value = real_app
-- A save of 0.33.0: sales counted, no log. Today shows them, past days cannot.
Market._State().sat.diamonds = { level = 0.3, day = Market.DayNumber(today) }
h = Market.History("diamonds")
T("today is the live price even without a log", h[7].price == 700 and h[6].price == 1000, h[7].price)
-- Two ids with the same name are one row; their stashed bags count together.
tweak_data.carry.gold.name_id = "gold"
local real_loc = managers.localization
managers.localization = { text = function(_, id) return id == "gold" and "Gold Bars" or id end }
add_bag("gold_two", 1, 100)
add_bag("gold", 1, 100)
local golds = 0
for _, r in ipairs(Market.Catalog()) do
  if r.name == "Gold Bars" then golds = golds + 1; T("  one row for both, both bags counted", r.carry_id == "gold" and r.stashed == 2, r.stashed) end
end
T("two ids with one name: one row", golds == 1, golds)
managers.localization = real_loc

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
