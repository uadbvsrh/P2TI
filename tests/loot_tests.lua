-- Loot: the bag the player carries is an inventory item, so it costs space
-- and weight.
--   texlua tests/loot_tests.lua
local script = arg and arg[0] or "tests/loot_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_loot") .. "/")
ENV.install_game()
ENV.load_mod(ROOT, false)
-- Loot is carried by a spawned player (in the menu nothing is asked).
ENV.make_unit()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local function loot_items()
  return PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end)
end

-- 1. without a bag there is no loot item
ENV.game.carry_id = nil
PDTI.Loot.Tick()
T("without loot there is no loot item", #loot_items() == 0)

-- 2. a bag of loot becomes an item
ENV.game.carry_id = "gold"
PDTI.Loot.Tick()
T("a bag of loot becomes an item", #loot_items() == 1, #loot_items())
T("the item is a loot bag", loot_items()[1].item.item_id == "loot_bag")
T("the loot is counted", PDTI.Loot.Count() == 1, PDTI.Loot.Count())
T("the loot weighs something", PDTI.GetTotalWeight() == 4, PDTI.GetTotalWeight())
T("the bag lies in the rig or the backpack", loot_items()[1].container ~= "pockets",
  loot_items()[1].container)

-- 3. the bag is banked or dropped: the item goes away
ENV.game.carry_id = nil
PDTI.Loot.Tick()
T("the deposited bag leaves the inventory", #loot_items() == 0, #loot_items())
T("the loot is not counted any more", PDTI.Loot.Count() == 0)

-- 4. a corpse is not loot
ENV.game.carry_id = "person"
PDTI.Loot.Tick()
T("a body is not a loot bag", #loot_items() == 0, #loot_items())

-- 5. another bag of loot
ENV.game.carry_id = "money"
PDTI.Loot.Tick()
T("another bag of loot is carried", #loot_items() == 1, #loot_items())

-- 6. a new heist clears the loot
PDTI.Loot.OnHeistStart()
T("a new heist clears the loot", #loot_items() == 0, #loot_items())

------------------------------------------- throwing one bag after another

local Loot = PDTI.Loot
local function bag_ext(id) return { _carry_id = id, _unit = { carry_data = function() return {
  carry_id = function() return id end, is_attached_to_zipline_unit = function() return false end } end } } end
local function pick(id)
  local ext = bag_ext(id)
  if CarryInteractionExt._interact_blocked(ext) then return false end
  CarryInteractionExt.interact(ext)
  Loot.Tick()
  return true
end
local function fresh()
  PDTI.Reset()
  Loot.Reset()
  ENV.game.carry_id = nil
  ENV.game.cooldown = false
  ENV.game.registered = {}
  ENV.game.thrown = {}
  ENV.game.cannot_carry = nil
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.SetEquipment("backpack", "large_backpack")
end
T("the carry hooks are in place", Loot.InstallHooks() == true)

fresh()
pick("gold"); pick("money"); pick("diamonds")
T("three bags: one carried, two in the inventory", ENV.game.carry_id == "diamonds" and Loot.StoredCount() == 2,
  tostring(ENV.game.carry_id) .. " " .. Loot.StoredCount())
managers.player:drop_carry()
T("the game's carry cooldown is running after the throw", ENV.game.cooldown == true)
Loot.Tick()
T("the next bag is in your hands on the next frame, without waiting for the cooldown",
  ENV.game.carry_id ~= nil, tostring(ENV.game.carry_id))
managers.player:drop_carry()
Loot.Tick()
T("and the next one after it", ENV.game.carry_id ~= nil and Loot.StoredCount() == 0)
managers.player:drop_carry()
Loot.Tick()
T("all three thrown one after another", #ENV.game.thrown == 3 and ENV.game.carry_id == nil and Loot.Count() == 0,
  #ENV.game.thrown)
T("the game's bag books are right", #ENV.game.registered == 0, #ENV.game.registered)
T("the cooldown still keeps you from grabbing a thrown bag from the floor", pick("gold") == false)
ENV.game.cooldown = false

------------------------------------------------ no more bags than room

-- Fill every place a bag could go, but leave one place for one bag.
local function fill_but(free_bags)
  for _, name in ipairs(Loot.CONTAINERS) do
    while PDTI.AddItemAuto(name, "loot_bag", 1, { carry_id = "gold" }, true) do end
  end
  local filler = PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end)
  for i = 1, free_bags do PDTI.RemoveItem(filler[i].container, filler[i].item.instance_id) end
  -- the filler bags are not loot of the heist: make them something else
  for _, entry in ipairs(PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end)) do
    PDTI.ReplaceItemData(entry.container, entry.item.instance_id, { carry_id = "gold", filler = true })
  end
end

fresh()
fill_but(0)
T("a full inventory has no room for a bag", Loot.HasRoom() == false)
local logs_before = #ENV.logs
T("without room the first bag cannot be picked up", pick("money") == false and ENV.game.carry_id == nil)
T("the player is told why", #ENV.logs > logs_before and ENV.logs[#ENV.logs]:find("no room") ~= nil, ENV.logs[#ENV.logs])
T("the interaction itself refuses too", CarryInteractionExt.interact(bag_ext("money")) == false and ENV.game.carry_id == nil)
T("a body bag is not loot: the game's rule applies", CarryInteractionExt._interact_blocked(bag_ext("person")) == false)

fresh()
fill_but(2)
T("room for two bags: the first is picked up", pick("money") == true and ENV.game.carry_id == "money")
T("the second too (the first goes into the inventory)", pick("diamonds") == true and ENV.game.carry_id == "diamonds"
  and #PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" and item.data.carry_id == "money" end) == 1)
T("a third has no place: it stays on the floor", pick("gold") == false and ENV.game.carry_id == "diamonds")
T("nothing was lost or added", Loot.Count() - #PDTI.FindItems(function(_, item)
  return item.item_id == "loot_bag" and item.data and item.data.filler end) == 2)

-- A bag carried without a place in the inventory (a mission gave it to you
-- while you had no room): no other bag on top of it.
fresh()
fill_but(0)
ENV.game.carry_id = "money"
Loot.Tick()
T("a bag you carry without a place is not in the inventory", Loot.Count() == #PDTI.FindItems(function(_, item)
  return item.item_id == "loot_bag" and item.data and item.data.filler end))
local _, first = next(PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end))
PDTI.RemoveItem(first.container, first.item.instance_id)
T("even with one free place, no second bag on top of it", pick("diamonds") == false and ENV.game.carry_id == "money")

-- The game's own rule for a bag still counts.
fresh()
pick("gold")
ENV.game.cannot_carry = "diamonds"
T("a bag the game does not let you carry stays blocked", CarryInteractionExt._interact_blocked(bag_ext("diamonds")) == true)

-- In the menu (no player) the game's carry data is not asked: the game logs
-- its error even when it is caught.
local asked = false
local old_carry = managers.player.current_carry_id
managers.player.current_carry_id = function() asked = true; return "gold" end
local old_unit = ENV.game.unit
ENV.game.unit = nil
T("in the menu nothing is carried, and the game is not asked", PDTI.Loot.CarriedId() == nil and not asked)
ENV.game.unit = old_unit
managers.player.current_carry_id = old_carry

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
