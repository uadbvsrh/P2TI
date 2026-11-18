-- 0.29.0: the safehouse stash. A won job captures the secured bags and the
-- bags in your inventory; the game pays nothing for bags any more; each
-- captured bag goes to the stash or is sold at once for half its value.
--   luajit tests/stash_tests.lua
local script = arg and arg[0] or "tests/stash_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_stash") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

tweak_data.carry.types = {
  heavy = { can_run = false, move_speed_modifier = 0.5, jump_modifier = 0.5 },
  medium = { can_run = false, move_speed_modifier = 0.75, jump_modifier = 1 },
  light = { can_run = true, move_speed_modifier = 1, jump_modifier = 1 }
}
tweak_data.carry.small_loot = { diamond_small = 1000 }
-- (small loot with a carry entry too, so only the small loot check keeps it out)
tweak_data.carry.diamond_small = { type = "light", bag_value = "diamonds" }
tweak_data.carry.car = { type = "heavy", bag_value = "car", is_vehicle = true }

-- The game's loot, money, job and end of mission (only what the mod reads).
local paid, game_paid = 0, {}
local BAG = { diamond_small = 1, gold = 10000, money = 6000, diamonds = 8000, car = 50000 }
local secured = {}
_G.LootManager = {
  -- what the game would pay for the secured bags (vehicles separately)
  get_secured_bonus_bags_value = function(self, level_id, is_vehicle)
    local v = 0
    for _, s in ipairs(self._global.secured) do
      local t = tweak_data.carry[s.carry_id]
      if t and t.is_vehicle == (is_vehicle == true or nil) then v = v + BAG[s.carry_id] end
    end
    return v
  end,
  get_secured_mandatory_bags_value = function(self, is_vehicle) return is_vehicle and 0 or 1234 end
}
_G.MissionEndState = {
  at_enter = function(self)
    -- the game secures the bag in hands, then pays out
    if self._success and ENV.game.carry_id then
      secured[#secured + 1] = { carry_id = ENV.game.carry_id, multiplier = 1 }
    end
    game_paid.bonus = managers.loot:get_secured_bonus_bags_value("level")
    game_paid.vehicle = managers.loot:get_secured_bonus_bags_value(nil, true)
    game_paid.mandatory = managers.loot:get_secured_mandatory_bags_value()
  end
}
_G.ElementCarry = { on_executed = function(self, instigator) self.ran = instigator end }
MissionEndState._continue_blocked = function() return false end
_G.HUDStageEndScreen = { update = function(self) self.counted = (self.counted or 0) + 1 end }

ENV.load_mod(ROOT, false)
ENV.make_unit()
managers.loot = setmetatable({ _global = { secured = secured } }, { __index = LootManager })
local last_stage = true
local job_id = "branchbank"
managers.job = {
  on_last_stage = function() return last_stage end,
  current_job_id = function() return job_id end
}
managers.money = {
  get_secured_bonus_bag_value = function(_, carry_id) return BAG[carry_id] * 2 end,
  add_to_total = function(_, amount) paid = paid + amount end,
  get_payouts = function(self) return { bag_payout = self._bag_payout } end
}

local LQ, Loot, Stash = PDTI.LootQuality, PDTI.Loot, PDTI.Stash
local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function rolls(list)
  local i = 0
  LQ.random = function() i = i + 1; return list[i] or 0 end
end
local function fresh()
  PDTI.Reset()
  Loot.Reset()
  LQ.Reset()
  os.remove(TMP .. "pdti_stash.json")
  Stash.Reset()
  for i = #secured, 1, -1 do secured[i] = nil end
  ENV.game.carry_id = nil
  last_stage, job_id, paid = true, "branchbank", 0
  LQ.random = function() return 0 end
end
local function finish(success)
  MissionEndState.at_enter({ _success = success })
end

T("the hooks go in", Stash.InstallHooks() == true)
T("installed twice: still one hook", (function()
  local f = MissionEndState.at_enter
  Stash.InstallHooks()
  return MissionEndState.at_enter == f
end)())

------------------------------------------------------------- the payout

fresh()
secured[1] = { carry_id = "gold" }
secured[2] = { carry_id = "car" }
finish(true)
T("the game pays nothing for bags", game_paid.bonus == 0 and game_paid.mandatory == 0, game_paid.bonus)
T("a vehicle is still paid", game_paid.vehicle == 50000, game_paid.vehicle)
T("off with restoration-mod: the game pays again", (function()
  _G.restoration = {}
  local v = managers.loot:get_secured_bonus_bags_value("level")
  local m = managers.loot:get_secured_mandatory_bags_value()
  _G.restoration = nil
  return v == 10000 and m == 1234
end)())

------------------------------------------------------------- capture

T("the secured bag is captured, the vehicle is not", #Stash.Pending() == 1 and Stash.Pending()[1].carry_id == "gold",
  #Stash.Pending())
T("its value is what the game pays for it", Stash.Pending()[1].value == 20000, Stash.Pending()[1].value)

fresh()
secured[1] = { carry_id = "gold" }
secured[2] = { carry_id = "diamond_small" }
Loot.Add(1, { carry_id = "money", quality = 2, mods = "light" })
Loot.Add(1, { carry_id = "diamonds" })
ENV.game.carry_id = "diamonds"
Loot.Tick()
rolls({ 0.1 })
finish(true)
local p = Stash.Pending()
T("secured bags, the bag in hands and the bags in the inventory: 4", #p == 4, #p)
local by = {}
for _, b in ipairs(p) do by[b.carry_id] = (by[b.carry_id] or 0) + 1 end
T("small loot is not a bag", by.diamond_small == nil)
T("the bag in hands counted once", by.diamonds == 2, by.diamonds)
local money
for _, b in ipairs(p) do if b.carry_id == "money" then money = b end end
T("an inventory bag keeps its quality and modifier", money and money.quality == 2 and money.mods == "light")
T("High quality is worth twice", money and money.value == 24000, money and money.value)

fresh()
rolls({ 0.9, 0 })
ENV.game.carry_id = "gold"
Loot.Tick()
local held = LQ.HandsData()
finish(true)
T("the bag in your hands keeps the roll it had", Stash.Pending()[1].quality == held.quality
  and Stash.Pending()[1].mods == held.mods, Stash.Pending()[1].mods)

-- A bag you threw into the secure zone keeps its roll too.
fresh()
local cd = { _pdti_quality = { quality = 3, mods = { "light", "padded" } } }
function cd:value() return 1 end
function cd:carry_id() return "gold" end
local element = { _values = { operation = "secure" } }
ElementCarry.on_executed(element, { carry_data = function() return cd end })
secured[1] = { carry_id = "gold" }
secured[2] = { carry_id = "gold" }
rolls({ 0.1 })
finish(true)
p = Stash.Pending()
local q = { p[1].quality, p[2].quality }
table.sort(q)
T("the thrown Exceptional bag is matched, the other rolls", q[1] == 1 and q[2] == 3, table.concat(q, ","))
T("the game's secure still runs", element.ran ~= nil)

------------------------------------------------------------- failure, custody, days

fresh()
Loot.Add(2, { carry_id = "money", quality = 2, mods = "stackable", max_stack = 4 })
finish(true)
T("a stack of 2 in the inventory: 2 bags captured", #Stash.Pending() == 2, #Stash.Pending())

-- 0.35.2: a Stackable bag with others riding on it: each with its own roll.
fresh()
Loot.Add(1, { carry_id = "money", quality = 2, mods = "stackable", max_stack = 4 })
Loot.Add(1, { carry_id = "money", quality = 1, mods = "" })
Loot.Add(1, { carry_id = "money", quality = 3, mods = "light,padded" })
finish(true)
do
  local q = {}
  for _, b in ipairs(Stash.Pending()) do q[#q + 1] = (b.quality or (b.info and b.info.quality) or 0) end
  table.sort(q)
  T("a mixed stack: every bag captured with its own quality", #q == 3 and q[1] == 1 and q[2] == 2 and q[3] == 3,
    table.concat(q, ","))
end

fresh()
secured[1] = { carry_id = "gold" }
Loot.Add(1, { carry_id = "money" })
finish(false)
T("a lost job captures nothing", #Stash.Pending() == 0)

fresh()
secured[1] = { carry_id = "gold" }
Loot.Add(1, { carry_id = "money" })
local unit = ENV.game.unit
ENV.game.unit = nil
finish(true)
ENV.game.unit = unit
T("in custody: the secured bag counts, the inventory bag is lost",
  #Stash.Pending() == 1 and Stash.Pending()[1].carry_id == "gold", #Stash.Pending())

fresh()
last_stage = false
secured[1] = { carry_id = "gold" }
Loot.Add(1, { carry_id = "money" })
rolls({ 0.9, 0 })
ENV.game.carry_id = "gold"
Loot.Tick()
local day1 = LQ.HandsData().mods
finish(true)
T("day 1 of 2: the inventory bag is captured, the secured ones wait",
  #Stash.Pending() == 1 and Stash.Pending()[1].carry_id == "money", #Stash.Pending())
-- The next day the mod is loaded again (the file is all that is left).
Stash.Reset()
PDTI.Reset()
ENV.game.carry_id = nil
last_stage = true
rolls({ 0.1 })
finish(true)
p = Stash.Pending()
local kept_roll = 0
for _, b in ipairs(p) do if b.carry_id == "gold" and b.mods == day1 then kept_roll = kept_roll + 1 end end
T("the last day: the secured bags come, the one held on day 1 with its roll", #p == 3 and kept_roll == 1, kept_roll)

fresh()
last_stage = false
rolls({ 0.9, 0 })
ENV.game.carry_id = "gold"
Loot.Tick()
finish(true)
Stash.Reset()
ENV.game.carry_id = nil
finish(false)
T("a lost last day forgets the rolls of the earlier days", #Stash._Data().known == 0 and #Stash.Pending() == 0)

fresh()
job_id = "chill_combat"
secured[1] = { carry_id = "gold" }
finish(true)
T("the safehouse raid captures nothing", #Stash.Pending() == 0)

------------------------------------------------------------- choosing

fresh()
for _ = 1, 3 do secured[#secured + 1] = { carry_id = "gold" } end
finish(true)
local ids = {}
for _, b in ipairs(Stash.Pending()) do ids[#ids + 1] = b.id end
T("every captured bag has its own id", ids[1] ~= ids[2] and ids[2] ~= ids[3])
local ok, got = Stash.SellNow(ids[1])
T("sell now pays half, through the game's payout", ok and got == 10000 and paid == 10000, paid)
T("keep: into the stash", Stash.Keep(ids[2]) and #Stash.Bags() == 1 and #Stash.Pending() == 1)
T("an unknown bag is refused", not Stash.Keep(999) and not Stash.SellNow(999) and not Stash.Sell(999))
paid = 0
ok, got = Stash.Sell(ids[2])
-- (one gold was sold just now: the market pays 8% less for the next one)
T("sold from the stash at the market's price", ok and got == 18400 and #Stash.Bags() == 0, got)

-- The file keeps it all.
Stash.Reset()
T("what waits is still there after a restart", #Stash.Pending() == 1 and Stash.Pending()[1].id == ids[3])
T("new ids go on after the old ones", (function()
  for i = #secured, 2, -1 do secured[i] = nil end
  finish(true)
  local p2 = Stash.Pending()
  return #p2 == 2 and p2[2].id > ids[3]
end)())

------------------------------------------------------------- space

fresh()
local d = Stash._Data()
for i = 1, 12 do d.bags[i] = { id = i, carry_id = "gold", quality = 1, mods = "", value = 1 } end
d.next_id = 13
T("12 bags fill the stash", Stash.CellsUsed() == 48 and Stash.CellsUsed() == Stash.Capacity())
d.pending[1] = { id = 20, carry_id = "gold", quality = 1, mods = "", value = 1 }
local kept, why = Stash.Keep(20)
T("a 13th does not fit", not kept and tostring(why):find("full") ~= nil, why)
T("and keeps waiting", #Stash.Pending() == 1)
table.remove(d.bags)
d.bags[#d.bags + 1] = { id = 30, carry_id = "gold", quality = 2, mods = "compact", value = 1 }
T("a Compact bag takes half a place", Stash.CellsUsed() == 46, Stash.CellsUsed())
local list = {}
for i = 1, 5 do list[i] = { id = i, carry_id = "money", quality = 2, mods = "stackable", value = 1 } end
T("5 Stackable bags of a kind take 2 places", Stash.CellsUsed(list) == 8, Stash.CellsUsed(list))
T("a different one does not join the stack", (function()
  list[5].quality = 3
  return Stash.CellsUsed({ list[1], list[5] }) == 8
end)())

fresh()
d = Stash._Data()
for i = 1, 11 do d.bags[i] = { id = i, carry_id = "gold", quality = 1, mods = "", value = 1 } end
for i = 1, 3 do d.pending[i] = { id = 100 + i, carry_id = "gold", quality = 1, mods = "", value = 2 } end
T("keep all: what fits goes in, the rest waits", Stash.KeepAll() == 2 and #Stash.Bags() == 12)
paid = 0
T("sell all now: half of what is left (2 bags of 2)", Stash.SellAllNow() == 2 and paid == 2 and #Stash.Pending() == 0, paid)

------------------------------------------------------------- the file

T("a broken file starts an empty stash", (function()
  local f = io.open(TMP .. "pdti_stash.json", "w"); f:write("{not json"); f:close()
  Stash.Reset()
  return #Stash.Bags() == 0 and #Stash.Pending() == 0
end)())
T("bad entries are dropped, odd values fixed", (function()
  local s = Stash._Sanitize({ bags = { { id = 1, carry_id = "gold", quality = 9, value = -5 },
    { id = 1, carry_id = "money" }, "junk", { quality = 2 } } })
  return #s.bags == 2 and s.bags[1].quality == 1 and s.bags[1].value == 0 and s.bags[2].id ~= 1
end)())
T("profile 2 has its own file", Stash.FileName(2) == "pdti_stash_profile2.json" and Stash.FileName(1) == "pdti_stash.json")

T("off with restoration-mod: nothing captured", (function()
  fresh()
  _G.restoration = {}
  secured[1] = { carry_id = "gold" }
  finish(true)
  _G.restoration = nil
  return #Stash.Pending() == 0
end)())

------------------------------------------------------------- the end screen

-- 0.29.1: the end screen waits for the choice.
fresh()
secured[1] = { carry_id = "gold" }
finish(true)
T("without a window nothing waits (no BeardLib)", MissionEndState._continue_blocked({}) == false
  and not Stash.Holding() and #Stash.Pending() == 1)

local window = { open = false, opened = 0 }
PDTI.SetCaptureOpen = function(open) window.open = open; window.opened = window.opened + 1; return true end
PDTI.IsCaptureOpen = function() return window.open end
fresh()
secured[1] = { carry_id = "gold" }
secured[2] = { carry_id = "money" }
managers.money._bag_payout = 0
finish(true)
local screen = { _stage = 1 }
HUDStageEndScreen.update(screen, 0, 0.1)
T("bags to choose for: the payout is not counted up yet", (screen.counted or 0) == 0)
T("the captured loot window opens", window.open == true)
T("you cannot continue", MissionEndState._continue_blocked({}) == true)
HUDStageEndScreen.update(screen, 0, 0.1)
T("opened once", window.opened == 1, window.opened)
local first = Stash.Pending()[1]
Stash.SellNow(first.id)
T("one bag left: still waiting", Stash.Holding() and MissionEndState._continue_blocked({}) == true)
T("the sale shows as the bags' payout", managers.money._bag_payout == 10000, managers.money._bag_payout)
Stash.Keep(Stash.Pending()[1].id)
HUDStageEndScreen.update(screen, 0, 0.1)
T("all chosen: the payout counts up", screen.counted == 1)
T("and you can continue", MissionEndState._continue_blocked({}) == false)
T("a stashed bag adds nothing to the payout", managers.money._bag_payout == 10000)
screen._stage = 5
fresh()
secured[1] = { carry_id = "gold" }
finish(true)
HUDStageEndScreen.update(screen, 0, 0.1)
T("later stages are never held", screen.counted == 2)
fresh()
secured[1] = { carry_id = "gold" }
finish(false)
T("a lost job: nothing to wait for", not Stash.Holding())
fresh()
window.open = false
PDTI.SetCaptureOpen = function() error("broken window") end
secured[1] = { carry_id = "gold" }
finish(true)
T("a window that fails to open: nothing waits", MissionEndState._continue_blocked({}) == false and not Stash.Holding())
-- A window BeardLib is still making: wait, but not for ever.
fresh()
local tries = 0
PDTI.SetCaptureOpen = function() tries = tries + 1; return "wait" end
secured[1] = { carry_id = "gold" }
finish(true)
T("a window not made yet: the end screen waits for it", MissionEndState._continue_blocked({}) == true)
for _ = 1, Stash.WINDOW_TRIES do MissionEndState._continue_blocked({}) end
T("never made: after a while nothing waits", MissionEndState._continue_blocked({}) == false and tries >= Stash.WINDOW_TRIES - 1,
  tries)
PDTI.SetCaptureOpen, PDTI.IsCaptureOpen = nil, nil

-- A bag being spawned has no carry data yet: nothing breaks.
T("no carry data: no error", PDTI.CarryExt({ carry_data = function() return nil end }) == nil
  and PDTI.CarryExt(nil) == nil and PDTI.CarryExt({}) == nil)

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
