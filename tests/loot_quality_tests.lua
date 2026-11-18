-- 0.28.0: loot quality. A bag rolls Standard / High / Exceptional the first
-- time it is picked up, keeps the roll when thrown and picked up again, and
-- its modifiers work while it is carried.
--   luajit tests/loot_quality_tests.lua
local script = arg and arg[0] or "tests/loot_quality_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_loot_quality") .. "/")
ENV.install_game()

-- The game's carry classes (the rest of the mock has none).
tweak_data.carry.types = {
  heavy = { can_run = false, move_speed_modifier = 0.5, jump_modifier = 0.5, throw_distance_multiplier = 0.5 },
  medium = { can_run = false, move_speed_modifier = 0.75, jump_modifier = 1, throw_distance_multiplier = 1 },
  light = { can_run = true, move_speed_modifier = 1, jump_modifier = 1, throw_distance_multiplier = 1 }
}

_G.Vector3 = function(r, g, b) return { r, g, b } end
_G.Idstring = function(s) return "ids:" .. s end

-- A bag lying in the world, as the game's carry data sees it. Its material
-- records the outline the game (or the mod) paints.
local function world_bag(carry_id)
  local attention = { data = { prop_carry_bag = {} } }
  function attention:attention_data() return self.data end
  function attention:remove_attention(id) self.data[id] = nil end
  local cd = { _id = carry_id }
  function cd:carry_id() return self._id end
  local material = { vars = {} }
  function material:set_variable(id, v) self.vars[id] = v end
  local unit = { _attention = attention, _cd = cd, _material = material }
  local ext = setmetatable({ _unit = unit, _materials = { material }, _tweak_data = {} },
    { __index = CarryInteractionExt })
  unit._ext = ext
  function unit:carry_data() return self._cd end
  function unit:attention() return self._attention end
  function unit:interaction() return self._ext end
  return unit
end

local calls = {}
_G.PlayerManager = {
  modify_value = function(_, key, value) return value end,
  drop_carry = function(self)
    local id = managers.player:current_carry_id()
    managers.player:drop_carry()
    self._carry_blocked_cooldown_t = 99
    local unit = world_bag(id)
    PlayerManager.sync_carry_data(self, unit, id, 1, nil, nil, nil, "pos", 10, 0, nil, 1)
    calls.thrown_unit = unit
  end,
  sync_carry_data = function(_, unit, carry_id, _, _, _, _, _, dir)
    calls.dir = dir
  end
}
PlayerManager.force_drop_carry = PlayerManager.drop_carry
_G.PlayerCarry = {
  super = {
    _check_action_run = function() calls.run = "standard" end,
    _perform_jump = function(_, v) calls.jump = v end
  },
  _check_action_run = function() calls.run = "carry" end,
  _perform_jump = function(_, v) calls.jump = v * 0.5 end
}

-- The game's own outline (what BaseInteractionExt:set_contour does).
CarryInteractionExt.super.set_contour = function(self, color, opacity)
  for _, m in ipairs(self._materials) do
    m:set_variable("ids:contour_color", "game:" .. tostring(color))
    m:set_variable("ids:contour_opacity", opacity or 0)
  end
end

ENV.load_mod(ROOT, false)
ENV.make_unit()
ENV.game.peer.id = function() return 1 end

local LQ, Loot = PDTI.LootQuality, PDTI.Loot
LQ.InstallHooks()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

-- The rolls come from a list (first the tier, then each modifier pick).
local function rolls(list)
  local i = 0
  LQ.random = function() i = i + 1; return list[i] or 0 end
end
local function loot()
  return PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end)
end
local function clear()
  PDTI.Reset()
  Loot.Reset()
  LQ.Reset()
  ENV.game.carry_id = nil
  ENV.game.cooldown = false
end

------------------------------------------------------------------ the roll

rolls({ 0.5 })
local r = LQ.Roll("gold")
T("80%: Standard, no modifier", r.quality == 1 and #r.mods == 0, r.quality)
rolls({ 0.85, 0 })
r = LQ.Roll("gold")
T("the next 17%: High quality, one modifier", r.quality == 2 and #r.mods == 1, r.quality)
rolls({ 0.99, 0, 0 })
r = LQ.Roll("gold")
T("the last 3%: Exceptional, two different modifiers", r.quality == 3 and #r.mods == 2 and r.mods[1] ~= r.mods[2],
  table.concat(r.mods, ","))

local function has(list, id) for _, v in ipairs(list) do if v == id then return true end end return false end
T("a heavy bag can roll Runner and Nimble", has(LQ.Eligible("gold"), "runner") and has(LQ.Eligible("gold"), "nimble"))
T("a bag you can run with cannot roll Runner", not has(LQ.Eligible("diamonds"), "runner"))
T("a bag without a jump penalty cannot roll Nimble", not has(LQ.Eligible("money"), "nimble"))

local counts = { 0, 0, 0 }
for i = 1, 1000 do
  local v = (i - 0.5) / 1000
  LQ.random = function() return v end
  local q = LQ.Roll("gold").quality
  counts[q] = counts[q] + 1
end
T("over evenly spread rolls the tiers come 80/17/3", counts[1] == 800 and counts[2] == 170 and counts[3] == 30,
  table.concat(counts, "/"))

------------------------------------------------ a bag picked up rolls once

clear()
rolls({ 0.9, 0 })  -- High, the first eligible modifier of gold: runner
ENV.game.carry_id = "gold"
Loot.Tick()
local item = loot()[1] and loot()[1].item
T("the bag in your hands has a quality", item and item.data.quality == 2, item and item.data.quality)
T("and its modifier", item and item.data.mods == "runner", item and item.data.mods)
T("it is shown with the bag", LQ.Describe(item.data):find("High quality", 1, true) ~= nil
  and LQ.Describe(item.data):find("Runner", 1, true) ~= nil, LQ.Describe(item.data))
T("worth twice its kind", LQ.ValueMul(item.data) == 2)

rolls({ 0.99, 0.99, 0.99 })
Loot.Tick()
item = loot()[1].item
T("it does not roll again while carried", item.data.quality == 2 and item.data.mods == "runner", item.data.mods)

-- 0.28.1: a better bag says so on the screen when you pick it up.
local hints = {}
managers.hud.show_hint = function(_, p) hints[#hints + 1] = p end
clear()
rolls({ 0.9, 0 })
ENV.game.carry_id = "gold"
Loot.Tick()
T("a High quality bag shows a hint", #hints == 1 and hints[1].text:find("High quality", 1, true) ~= nil
  and hints[1].text:find("Runner", 1, true) ~= nil, hints[1] and hints[1].text)
T("long enough to read", hints[1] and hints[1].time == LQ.HINT_TIME)
Loot.Tick()
T("only once, when it comes into your hands", #hints == 1, #hints)
clear()
rolls({ 0.1 })
ENV.game.carry_id = "gold"
Loot.Tick()
T("a Standard bag shows no hint", #hints == 1, #hints)
-- Back to the High quality Runner bag for the modifier checks below.
clear()
rolls({ 0.9, 0 })
ENV.game.carry_id = "gold"
Loot.Tick()

------------------------------------------ runner, nimble, padded, light

PlayerCarry._check_action_run({})
T("Runner: you can run with a heavy bag", calls.run == "standard", calls.run)
PlayerCarry._perform_jump({}, 10)
T("without Nimble the jump is the game's", calls.jump == 5, calls.jump)

local function carry_bag(mods, carry_id)
  clear()
  rolls({ 0 })
  ENV.game.carry_id = carry_id or "gold"
  Loot.Tick()
  local entry = loot()[1]
  local data = {}
  for k, v in pairs(entry.item.data) do data[k] = v end
  LQ.Apply(data, { quality = 3, mods = mods })
  for _, key in ipairs(Loot.QUALITY_FIELDS) do if data[key] == nil then data[key] = false end end
  PDTI.EditItems({ update = { { container = entry.container, instance_id = entry.item.instance_id, data = data } } })
  return PDTI.FindItem(entry.container, entry.item.instance_id)
end

carry_bag({ "nimble" })
PlayerCarry._perform_jump({}, 10)
T("Nimble: no jump penalty", calls.jump == 10, calls.jump)
PlayerCarry._check_action_run({})
T("without Runner a heavy bag stops you running", calls.run == "carry", calls.run)

T("without Padded the damage is the game's", PlayerManager.modify_value({}, "damage_taken", 10) == 10)
carry_bag({ "padded" })
T("Padded: 15% less damage while carried", near(PlayerManager.modify_value({}, "damage_taken", 10), 8.5),
  PlayerManager.modify_value({}, "damage_taken", 10))
T("Padded leaves other values alone", PlayerManager.modify_value({}, "other", 10) == 10)

carry_bag({})
local plain = PDTI.Carry.LootFactor()
carry_bag({ "light" })
local light = PDTI.Carry.LootFactor()
T("a heavy bag halves your speed", near(plain, 0.5), plain)
T("Light: only half of that slowdown", near(light, 0.75), light)

carry_bag({ "compact" })
local cw, ch = PDTI.ItemSize(loot()[1].item)
T("Compact: the bag takes 2x1", cw and ch and cw * ch == 2, tostring(cw) .. "x" .. tostring(ch))

------------------------------------------------- thrown and picked up

carry_bag({ "long_throw", "discreet", "quick_hands" })
PlayerManager.drop_carry(managers.player)
Loot.Tick()
local unit = calls.thrown_unit
T("the thrown bag keeps its roll in the world", unit and unit:carry_data()._pdti_quality ~= nil
  and unit:carry_data()._pdti_quality.quality == 3)
T("Balanced: thrown 50% further", calls.dir == 15, calls.dir)
T("Discreet: guards do not notice it", next(unit:attention():attention_data()) == nil)
T("Quick hands: no wait after the throw", managers.player._carry_blocked_cooldown_t == 0,
  managers.player._carry_blocked_cooldown_t)
T("the thrown bag left the inventory", #loot() == 0, #loot())

rolls({ 0.1 })  -- a new roll would be Standard
ENV.game.cooldown = false
local ext = { _unit = unit, _carry_id = "gold" }
CarryInteractionExt.interact(ext, ENV.game.unit)
Loot.Tick()
item = loot()[1] and loot()[1].item
T("picked up again it is the same bag", item and item.data.quality == 3
  and item.data.mods == "discreet,long_throw,quick_hands", item and item.data.mods)

-- 0.28.2: a thrown bag of quality is outlined in its colour.
local vars = unit._material.vars
T("the thrown Exceptional bag is outlined in gold", type(vars["ids:contour_color"]) == "table"
  and vars["ids:contour_color"][1] == 1.0 and vars["ids:contour_color"][2] == 0.75, tostring(vars["ids:contour_color"]))
T("always visible", vars["ids:contour_opacity"] == 1, vars["ids:contour_opacity"])
unit:interaction():set_contour("selected_color", 1)
T("looking at it shows the game's selected outline", vars["ids:contour_color"] == "game:selected_color",
  tostring(vars["ids:contour_color"]))
unit:interaction():set_contour("standard_color", 0)
T("looking away: its colour again, still visible", type(vars["ids:contour_color"]) == "table"
  and vars["ids:contour_opacity"] == 1)

carry_bag({})
local function set_quality(q)
  local e = loot()[1]
  PDTI.EditItems({ update = { { container = e.container, instance_id = e.item.instance_id, data = { quality = q } } } })
end
set_quality(2)
PlayerManager.drop_carry(managers.player)
Loot.Tick()
vars = calls.thrown_unit._material.vars
T("a High quality bag is outlined in blue", type(vars["ids:contour_color"]) == "table"
  and vars["ids:contour_color"][3] == 1.0, tostring(vars["ids:contour_color"]))

carry_bag({})
set_quality(1)
PlayerManager.drop_carry(managers.player)
Loot.Tick()
vars = calls.thrown_unit._material.vars
calls.thrown_unit:interaction():set_contour("standard_color", 0)
T("a Standard bag keeps the game's outline", vars["ids:contour_color"] == "game:standard_color"
  and vars["ids:contour_opacity"] == 0, tostring(vars["ids:contour_color"]))

carry_bag({})
PlayerManager.drop_carry(managers.player)
T("a plain bag is thrown as far as the game throws it", calls.dir == 10, calls.dir)
T("and keeps the game's wait", managers.player._carry_blocked_cooldown_t == 99)

------------------------------------------------------------- stacking

clear()
local def = PDTI.GetItemDefinition("loot_bag")
local base = { carry_id = "gold", multiplier = 1, active = false }
LQ.Apply(base, { quality = 2, mods = { "stackable" } })
for _ = 1, 5 do
  local copy = {}
  for k, v in pairs(base) do copy[k] = v end
  Loot.Add(1, copy)
end
local amounts = {}
for _, e in ipairs(loot()) do amounts[#amounts + 1] = e.item.amount end
table.sort(amounts)
T("Stackable: four bags in one place, the fifth on its own", #amounts == 2 and amounts[1] == 1 and amounts[2] == 4,
  table.concat(amounts, ","))
T("five bags are counted", Loot.Count() == 5, Loot.Count())
T("a stack of four is one bag's place", def.max_stack == 1 and PDTI.ItemMaxStack(def, base) == 4)

local other = { carry_id = "money", multiplier = 1, active = false }
LQ.Apply(other, { quality = 2, mods = { "light" } })
Loot.Add(1, other)
Loot.Add(1, other)
local singles = 0
for _, e in ipairs(loot()) do if e.item.data.carry_id == "money" then singles = singles + 1 end end
T("another loot does not ride on a Stackable bag", singles == 2, singles)
-- Taking a bag off the stack: it comes into your hands on a place of its own.
local stack
for _, e in ipairs(loot()) do if e.item.amount == 4 then stack = e end end
local ok, why = Loot.TakeOut({ container = stack.container, instance_id = stack.item.instance_id,
  amount = stack.item.amount, data = stack.item.data })
T("a bag can be taken off a stack", ok, why)
T("the stack has three left", PDTI.FindItem(stack.container, stack.item.instance_id).amount == 3)
T("the game carries it", ENV.game.carry_id == "gold")
T("no bag was made or lost", Loot.Count() == 7, Loot.Count())

-- 0.35.2: any gold bag rides on a Stackable gold bag.
clear()
local lead0 = { carry_id = "gold", multiplier = 1, active = false }
LQ.Apply(lead0, { quality = 2, mods = { "stackable" } })
Loot.Add(1, lead0)
local std = { carry_id = "gold", multiplier = 1, active = false }
LQ.Apply(std, { quality = 1, mods = {} })
Loot.Add(1, std)
local lt = { carry_id = "gold", multiplier = 1, active = false }
LQ.Apply(lt, { quality = 2, mods = { "light" } })
Loot.Add(1, lt)
local rider
for _, e in ipairs(loot()) do if e.item.data.carry_id == "gold" and e.item.amount == 3 then rider = e end end
T("bags of the same loot, any quality, ride on a Stackable bag", rider ~= nil and rider.item.data.extra == "1:;2:light",
  rider and rider.item.data.extra)
T("  the stack is still its Stackable bag", rider and rider.item.data.quality == 2 and rider.item.data.mods == "stackable")
T("  its tooltip lists them", rider and LQ.Describe(rider.item.data):find("with 1 High quality, 1 Standard", 1, true) ~= nil,
  rider and LQ.Describe(rider.item.data))
T("  every bag counted with its own roll", (function()
  local r = LQ.StackRolls(rider.item.data, rider.item.amount)
  return #r == 3 and r[1].quality == 2 and r[2].quality == 1 and r[3].quality == 2 and r[3].mods[1] == "light"
end)())
T("  a Light bag riding on it still counts as Light", LQ.AnyCarried("light") == true)
T("  the speed counts each bag with its own roll (the Light one costs half)", (function()
  local C = PDTI.Carry
  if not C or not C.LootFactor then return false end
  -- (A slight slowdown, so three bags do not reach the floor of 0.)
  local heavy = tweak_data.carry.types.heavy
  local saved_mod = heavy.move_speed_modifier
  heavy.move_speed_modifier = 0.9
  local with_light = C.LootFactor()
  local d = rider.item.data
  local saved = d.extra
  d.extra = "1:;2:"
  local without = C.LootFactor()
  d.extra = saved
  local slow = 1 - C.BagSpeed("gold")
  heavy.move_speed_modifier = saved_mod
  return slow > 0 and math.abs((with_light - without) - slow * (1 - LQ.LIGHT_SHARE)) < 1e-6
end)())
T("  ... and a modifier no bag has does not", LQ.AnyCarried("padded") == false)
-- Off the stack: the last one, with its own roll.
local ok1 = Loot.TakeOut({ container = rider.container, instance_id = rider.item.instance_id,
  amount = rider.item.amount, data = rider.item.data })
local hands = LQ.HandsData()
T("taking a bag off: the last one, with its own roll", ok1 and hands and hands.quality == 2 and hands.mods == "light"
  and (hands.extra == nil or hands.extra == ""), hands and hands.mods)
local left = PDTI.FindItem(rider.container, rider.item.instance_id)
T("  the stack keeps the others", left.amount == 2 and left.data.extra == "1:", left.data.extra)
ENV.game.carry_id = nil
for _, e in ipairs(loot()) do if e.item.data.active then PDTI.RemoveItem(e.container, e.item.instance_id) end end
T("Loot.Remove takes the last bags off a stack first", (function()
  local before = Loot.Count()
  Loot.Remove(1)
  local it = PDTI.FindItem(rider.container, rider.item.instance_id)
  return Loot.Count() == before - 1 and it and it.amount == 1 and (it.data.extra or "") == ""
end)())
-- A Stackable bag stored after the others gathers them.
clear()
Loot.Add(1, { carry_id = "gold", multiplier = 1, active = false, quality = 1, mods = "" })
Loot.Add(1, { carry_id = "gold", multiplier = 1, active = false, quality = 1, mods = "" })
local lead = { carry_id = "gold", multiplier = 1, active = false }
LQ.Apply(lead, { quality = 2, mods = { "stackable" } })
Loot.Add(1, lead)
T("a Stackable bag stored after them gathers the single bags of its loot", #loot() == 1 and loot()[1].item.amount == 3,
  #loot())
T("  nothing more to gather", Loot.Gather() == 0)
do
  carry_bag({ "stackable" })
  Loot.Add(1, { carry_id = "gold", multiplier = 1, active = false, quality = 1, mods = "" })
  local before = #loot()
  Loot.StashCarried()
  T("a Stackable bag put away from your hands gathers them too", before == 2 and #loot() == 1
    and loot()[1].item.amount == 2, #loot())
  ENV.game.carry_id = nil
end
T("  a stack does not ride on another one", Loot.StackOnto({ carry_id = "gold", multiplier = 1, active = false,
  quality = 1, mods = "", extra = "1:" }) == false)
-- A stack made before 0.35.2: copies of its own roll.
clear()
local old = { carry_id = "gold", multiplier = 1, active = false }
LQ.Apply(old, { quality = 3, mods = { "stackable" } })
Loot.Add(1, old)
local e0 = loot()[1]
PDTI.EditItems({ set_amount = { { container = e0.container, instance_id = e0.item.instance_id, amount = 2 } } })
Loot.Add(1, { carry_id = "gold", multiplier = 1, active = false, quality = 1, mods = "" })
local e1 = PDTI.FindItem(e0.container, e0.item.instance_id)
T("an old stack keeps its copies when a bag joins", e1.amount == 3 and e1.data.extra == "3:stackable;1:", e1.data.extra)


------------------------------------------------- off with restoration-mod

clear()
_G.restoration = {}
ENV.game.carry_id = "gold"
Loot.Tick()
item = loot()[1].item
T("with restoration-mod bags have no quality", item.data.quality == nil, item.data.quality)
_G.restoration = nil

------------------------------------------------- 0.35.2: fewer hints

do
  clear()
  local hints = {}
  local real_hint = PDTI.Hint
  PDTI.Hint = function(text) hints[#hints + 1] = text end
  -- A thrown High bag picked up again: you know it, no hint.
  local mine = world_bag("gold")
  mine:carry_data()._pdti_quality = { quality = 3, mods = {} }
  CarryInteractionExt.interact({ _unit = mine, _carry_id = "gold" }, ENV.game.unit)
  ENV.game.carry_id = "gold"
  Loot.Tick()
  local it = loot()[1] and loot()[1].item
  T("a thrown bag picked up again keeps its roll", it and it.data.quality == 3, it and it.data.quality)
  T("  and says nothing (you know it)", #hints == 0, hints[1])
  clear()
  -- A bag picked up the first time rolls then; a High roll says so.
  rolls({ 0.85, 0 })
  local fresh = world_bag("gold")
  CarryInteractionExt.interact({ _unit = fresh, _carry_id = "gold" }, ENV.game.unit)
  ENV.game.carry_id = "gold"
  Loot.Tick()
  it = loot()[1] and loot()[1].item
  T("a bag rolls when you first pick it up", it and it.data.quality == 2, it and it.data.quality)
  T("  a High roll says what it is", #hints == 1, #hints)
  T("a bag lying in the level has no roll before", fresh:carry_data()._pdti_quality == nil)
  PDTI.Hint = real_hint
  clear()
end

------------------------------------------------- 0.35.1: stacking on pickup

do
  -- Stacking: a Stackable bag picked up with no free place goes onto its stack.
  clear()
  local stk = { carry_id = "gold", multiplier = 1, active = false }
  LQ.Apply(stk, { quality = 2, mods = { "stackable" } })
  local function copy(t) local c = {} for k, v in pairs(t) do c[k] = v end return c end
  Loot.Add(1, copy(stk))
  Loot.Add(1, copy(stk))
  T("two Stackable bags in one place", #loot() == 1 and loot()[1].item.amount == 2)
  local same = copy(stk); same.has_dye_pack = false; same.dye_value_multiplier = nil
  T("  missing and false fields count as the same", Loot.StackKey(same) == Loot.StackKey(stk))
  local other = copy(stk); other.mods = "light"; other.quality = 1
  T("  quality and modifiers do not matter", Loot.StackKey(other) == Loot.StackKey(stk))
  local money = copy(stk); money.carry_id = "money"
  T("  the loot does", Loot.StackKey(money) ~= Loot.StackKey(stk))

  local real_room, real_add = Loot.HasRoom, PDTI.AddItemAuto
  Loot.HasRoom = function() return false end
  local u = world_bag("gold")
  u:carry_data()._pdti_quality = { quality = 2, mods = { "stackable" } }
  local ext = { _unit = u, _carry_id = "gold" }
  T("no free place, but its stack has room: the pickup is allowed", Loot.PickupBlocked(ext) == nil)
  local u2 = world_bag("money")
  u2:carry_data()._pdti_quality = { quality = 2, mods = { "light" } }
  T("  a bag of another loot is still blocked", Loot.PickupBlocked({ _unit = u2, _carry_id = "money" }) == "room")
  local u5 = world_bag("gold")
  u5:carry_data()._pdti_quality = { quality = 1, mods = {} }
  T("  a Standard bag of the same loot is allowed (it rides on it)", Loot.PickupBlocked({ _unit = u5, _carry_id = "gold" }) == nil)
  local u3 = world_bag("gold")
  T("  an unrolled bag is blocked", Loot.PickupBlocked({ _unit = u3, _carry_id = "gold" }) == "room")

  PDTI.AddItemAuto = function() return false end
  CarryInteractionExt.interact(ext, ENV.game.unit)
  ENV.game.carry_id = "gold"
  Loot.Tick()
  T("picked up: it goes onto the stack", #loot() == 1 and loot()[1].item.amount == 3, loot()[1] and loot()[1].item.amount)
  T("  your hands are free", ENV.game.carry_id == nil, ENV.game.carry_id)
  T("  no bag made or lost", Loot.Count() == 3, Loot.Count())
  -- Carrying a bag (it has its place) and picking up a Stackable one.
  Loot.HasRoom, PDTI.AddItemAuto = real_room, real_add
  ENV.game.carry_id = "gold"
  rolls({ 0 })
  Loot.Tick()
  Loot.HasRoom = function() return false end
  local u4 = world_bag("gold")
  u4:carry_data()._pdti_quality = { quality = 2, mods = { "stackable" } }
  local blocked = CarryInteractionExt._interact_blocked({ _unit = u4, _carry_id = "gold" }, ENV.game.unit)
  T("carrying a bag: a Stackable one like your stack can still be picked up", blocked == false, tostring(blocked))
  Loot.HasRoom = real_room
  clear()
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
