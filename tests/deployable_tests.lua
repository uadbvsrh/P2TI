-- Deployable tests: how many you can place, which one you picked, and how it
-- is placed.
--   texlua tests/deployable_tests.lua
local script = arg and arg[0] or "tests/deployable_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_deploy") .. "/")
ENV.install_game()
ENV.load_mod(ROOT, true)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local function clear_inventory()
  for _, c in ipairs({ "rig", "pockets", "backpack" }) do
    for _, it in ipairs(PDTI.GetContainer(c).items) do PDTI.RemoveItem(c, it.instance_id) end
  end
end
local function count_of(container, item_id)
  local n = 0
  for _, it in ipairs(PDTI.GetContainer(container).items) do
    if it.item_id == item_id then n = n + (it.amount or 1) end
  end
  return n
end

-- The equipment object of the game. The placement functions of the game call
-- valid_shape_placement without the equipment data, so the placement dummy
-- has to exist before they are called. Without it, the placement fails.
local PE = { calls = {}, dummy = false }
function PE:valid_shape_placement(equipment_id, equipment_data)
  self.calls[#self.calls + 1] = "valid:" .. tostring(equipment_id)
  if equipment_data then self.dummy = true end
  return { position = { x = 0, y = 0, z = 0 } }
end
for _, name in ipairs({ "use_doctor_bag", "use_ammo_bag", "use_first_aid_kit", "use_bodybags_bag" }) do
  PE[name] = function(self)
    if not self.dummy then return false end
    self.calls[#self.calls + 1] = name
    return true
  end
end
local unit = { equipment = function() return PE end }
_G.alive = function(u) return u ~= nil end
-- the equipment slots of the game: the deployable the game would place
local slots = { selections = {}, selected_index = 1 }
_G.managers = { player = { player_unit = function() return unit end, _equipment = slots } }

-- 1. what counts is what is to hand: the rig and the pockets
clear_inventory()
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
T("a bag in the rig counts", PDTI.Deployables.Count("ammo_bag") == 1)
PDTI.AddItemAuto("backpack", "ammo_bag", 1, nil, true)
T("a bag in the backpack does not count", PDTI.Deployables.Count("ammo_bag") == 1,
  PDTI.Deployables.Count("ammo_bag"))
T("the bag in the backpack is not found", PDTI.Deployables.Find("ammo_bag") == "rig")

-- 2. the grid decides what fits: a big bag needs the rig
clear_inventory()
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
T("two ammo bags fit in the combat rig", PDTI.Deployables.Count("ammo_bag") == 2,
  PDTI.Deployables.Count("ammo_bag"))
T("an ammo bag does not fit in the pockets",
  PDTI.AddItemAuto("pockets", "ammo_bag", 1, nil, true) == false)

-- 3. picking a deployable
clear_inventory()
PDTI.AddItemAuto("rig", "first_aid_kit", 1, nil, true)
T("nothing is picked by default", PDTI.GetDeployable() == nil)
T("while nothing is picked, the first one found is the deployable",
  PDTI.Deployables.Manages() == true and PDTI.Deployables.GetSelection() == "first_aid_kit")
T("an item that is not a deployable is refused", PDTI.SetDeployable("bandage") == false)
T("a deployable can be picked", PDTI.SetDeployable("first_aid_kit") == true)
T("the picked deployable is remembered", PDTI.GetDeployable() == "first_aid_kit")
T("the inventory manages the deployable now", PDTI.Deployables.Manages() == true)
T("the picked deployable is saved", PDTI.Save() == true)

-- 4. the entry the game gets: it looks like the game's own equipment
local entry = PDTI.Deployables.SyntheticEntry()
T("the game gets an equipment entry", type(entry) == "table")
T("the entry names the equipment of the item", entry and entry.equipment == "first_aid_kit",
  entry and entry.equipment)
T("the entry has the placement function", entry and entry.use_function == "use_first_aid_kit",
  entry and entry.use_function)
T("the entry has the amount of the item",
  entry and entry.amount and Application:digest_value(entry.amount[1], false) == 1,
  entry and entry.amount and Application:digest_value(entry.amount[1], false))
T("the entry has the icon of the game", entry and entry.icon == "equipment_firstaid",
  entry and entry.icon)

-- 5. placing the picked deployable
clear_inventory()
PDTI.AddItemAuto("rig", "first_aid_kit", 1, nil, true)
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PE.calls, PE.dummy = {}, false
T("placing the picked deployable works", PDTI.Deployables.Place() == true)
T("the right placement function was used", PE.calls[#PE.calls] == "use_first_aid_kit",
  PE.calls[#PE.calls])
T("the placement is checked with the equipment of the game",
  PE.calls[1] == "valid:first_aid_kit", PE.calls[1])
T("the picked deployable was used up", count_of("rig", "first_aid_kit") == 0)
T("the other deployable was not touched", count_of("rig", "ammo_bag") == 1)
T("the pick is forgotten when it is used up", PDTI.GetDeployable() == nil)
PE.calls = {}
T("then the next one found is placed", PDTI.Deployables.Place() == true and PE.calls[#PE.calls] == "use_ammo_bag",
  PE.calls[#PE.calls])
PE.calls = {}
T("placing without one left fails", PDTI.Deployables.Place() == false)
T("nothing was placed", #PE.calls == 0)

-- 6. the game places the item of the inventory
local PM = {
  _equipment = slots,
  selected_equipment = function(self) return { equipment = "ammo_bag", amount = { 1 } } end,
  can_use_selected_equipment = function(self) return false end,
  use_selected_equipment = function(self, unit) return nil end,
  -- like the game: only equipment the player brought can be checked
  check_equipment_placement_valid = function(self, player, equipment) return false end
}
_G.PlayerManager = PM
dofile(ROOT .. "lua/hooks_player_manager.lua")
clear_inventory()
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PDTI.SetDeployable("ammo_bag")
local game_entry = PM.selected_equipment(PM)
T("the game sees the deployable of the inventory",
  game_entry and game_entry.equipment == "ammo_bag", game_entry and game_entry.equipment)
T("the game may use the deployable", PM.can_use_selected_equipment(PM, unit) == true)
PE.calls, PE.dummy = {}, false
PM.use_selected_equipment(PM, unit)
T("the game places the item of the inventory", PE.calls[#PE.calls] == "use_ammo_bag",
  PE.calls[#PE.calls])
T("the item is taken out of the inventory", count_of("rig", "ammo_bag") == 0)
T("the game's own equipment count is not touched", PM.selected_equipment(PM).equipment == "ammo_bag")

-- 6a. a deployable the player did not bring is checked like the game's own
clear_inventory()
PDTI.AddItemAuto("rig", "doctor_bag", 1, nil, true)
PDTI.SetDeployable("doctor_bag")
PE.calls, PE.dummy = {}, false
T("a deployable that was not brought can be placed (no 'wrong area')",
  PM.check_equipment_placement_valid(PM, unit, "doctor_bag") == true)
T("its placement model is created by the check", PE.calls[1] == "valid:doctor_bag" and PE.dummy == true,
  tostring(PE.calls[1]))
T("other equipment is checked by the game", PM.check_equipment_placement_valid(PM, unit, "sentry_gun") == false)
PDTI.SetDeployable(nil)
clear_inventory()
T("without a deployable to hand the game checks as before", PM.check_equipment_placement_valid(PM, unit, "doctor_bag") == false)
clear_inventory()
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PDTI.SetDeployable("ammo_bag")

-- 6b. the game's own equipment (a sentry gun) is left alone
PDTI._deploy_key_trigger = { fake = true }
PM._equipment.selections[1] = { equipment = "sentry_gun", amount = { 1 } }
T("the game's own sentry gun can be picked", PDTI.Deployables.SetSelection(PDTI.Deployables.GAME) == true)
local should = PDTI.Deployables.ShouldPlaceOurs()
T("the inventory keeps its hands off when the game's own equipment is picked",
  should == false and PDTI.Deployables.Manages() == false, tostring(should))
PDTI.Deployables.SetSelection("ammo_bag")
PM._equipment.selections[1] = { equipment = "ammo_bag", amount = { 1 } }
T("the inventory places its item when the game would place the same kind",
  PDTI.Deployables.ShouldPlaceOurs() == true)
PM._equipment.selections[1] = nil
T("the inventory places its item when the game has nothing selected",
  PDTI.Deployables.ShouldPlaceOurs() == true)
PDTI._deploy_key_trigger = nil

-- 7. while nothing is picked, the game behaves as before
PDTI.SetDeployable(nil)
local vanilla_entry = PM.selected_equipment(PM)
T("the game's own deployable comes back", vanilla_entry ~= nil
  and vanilla_entry.equipment == "ammo_bag", vanilla_entry and vanilla_entry.equipment)

-- 8. the inventory screen picks the held item
clear_inventory()
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PDTI.AddItemAuto("rig", "first_aid_kit", 1, nil, true)
PDTI.SetDeployable("ammo_bag")
local fak = PDTI.GetContainer("rig").items[1]
PDTI.UIPickUp("rig", fak.instance_id)
local ok, message = PDTI.UISelectDeployable()
T("holding an item and pressing the key picks it", ok == true, tostring(message))
T("the held item is the deployable now", PDTI.GetDeployable() == fak.item_id,
  tostring(PDTI.GetDeployable()))
PDTI.UIPickUp("rig", PDTI.GetContainer("rig").items[1].instance_id)
PDTI.UICancelHeld()
T("the key reports when nothing is held",
  (select(2, PDTI.UISelectDeployable()) or ""):find("Pick up") ~= nil)
PDTI.UICancelHeld()

-- 9. clearing the pick gives the deploy back to the game
T("the pick can be cleared", PDTI.UIClearDeployable() == true)
T("nothing is picked", PDTI.GetDeployable() == nil and PDTI.Deployables.GetManual() == nil)
T("the first one found is placed again", PDTI.Deployables.GetSelection() == "ammo_bag")

-- 9b. round 5: what is found first, your own pick, the X key
local Dep = PDTI.Deployables
PM._equipment.selections[1] = nil
clear_inventory()
PDTI.SetDeployable(nil)
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PDTI.AddItemAuto("pockets", "first_aid_kit", 1, nil, true)
T("the pockets are searched before the rig", Dep.GetSelection() == "first_aid_kit", Dep.GetSelection())
T("the kinds to hand in order", table.concat(Dep.ToHand(), ",") == "first_aid_kit,ammo_bag", table.concat(Dep.ToHand(), ","))
PE.calls, PE.dummy = {}, false
Dep.Place()
T("after the first aid kit is placed the ammo bag is next", Dep.GetSelection() == "ammo_bag", Dep.GetSelection())

clear_inventory()
PDTI.AddItemAuto("pockets", "first_aid_kit", 1, nil, true)
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
Dep.SetSelection("ammo_bag")
T("your own pick wins over the one found first", Dep.GetSelection() == "ammo_bag")
PDTI.AddItemAuto("pockets", "first_aid_kit", 1, nil, true)
T("and stays when more of another kind comes in", Dep.GetSelection() == "ammo_bag")
PDTI.AddItemAuto("backpack", "ammo_bag", 1, nil, true)
PE.calls, PE.dummy = {}, false
Dep.Place()
T("when your pick is used up the first one found is next", Dep.GetSelection() == "first_aid_kit" and Dep.GetManual() == nil,
  tostring(Dep.GetSelection()))

-- reading order inside a container: top row first, then left to right
clear_inventory()
PDTI.AddItem("rig", "doctor_bag", 0, 1, false, 1, nil, true)
PDTI.AddItem("rig", "first_aid_kit", 2, 0, false, 1, nil, true)
T("in the rig the top row comes first", Dep.ToHand()[1] == "first_aid_kit", table.concat(Dep.ToHand(), ","))

-- the X key: two first aid kits and an ammo bag
clear_inventory()
PDTI.AddItemAuto("pockets", "first_aid_kit", 1, nil, true)
PDTI.AddItemAuto("rig", "first_aid_kit", 1, nil, true)
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
T("starts with the first aid kit", Dep.GetSelection() == "first_aid_kit")
local hints = 0
managers.hud = { show_hint = function() hints = hints + 1 end }
T("X: the ammo bag (two kits are one kind)", Dep.Cycle() == "ammo_bag" and Dep.GetSelection() == "ammo_bag")
T("X again: back to the first aid kit", Dep.Cycle() == "first_aid_kit" and Dep.GetSelection() == "first_aid_kit")
T("a pick made with X is your own pick", Dep.GetManual() == "first_aid_kit")
-- a third kind: the rig's kit makes room for body bags
PDTI.RemoveItem("rig", select(2, Dep.Find("first_aid_kit")) and (function()
  for _, it in ipairs(PDTI.GetContainer("rig").items) do if it.item_id == "first_aid_kit" then return it.instance_id end end
end)())
T("body bags fit in the rig", PDTI.AddItemAuto("rig", "bodybags_bag", 1, nil, true) == true)
local order = Dep.ToHand()
T("three kinds to hand", #order == 3 and order[1] == "first_aid_kit", table.concat(order, ","))
T("X: the second kind", Dep.Cycle() == order[2], Dep.GetSelection())
T("X: the third kind", Dep.Cycle() == order[3], Dep.GetSelection())
T("after the last comes the first", Dep.Cycle() == "first_aid_kit")
PM._equipment.selections[1] = { equipment = "sentry_gun", amount = { 1 } }
Dep.SetSelection(order[3])
T("the game's own sentry gun comes after your deployables", Dep.Cycle() == Dep.GAME and Dep.Manages() == false)
T("and then the first one again", Dep.Cycle() == "first_aid_kit")
PM._equipment.selections[1] = nil
T("the name shown on the HUD", Dep.DisplayName():find("First Aid Kit x1") ~= nil, Dep.DisplayName())
T("the X key is registered with the deploy key", (function()
  PDTI._deploy_key_trigger, PDTI._cycle_key_trigger = nil, nil
  _G.BeardLib = { Utils = { Input = { Trigger = function(_, key) return { key = key } end } } }
  Dep.EnsureKeyTrigger()
  local ok = PDTI._cycle_key_trigger and PDTI._cycle_key_trigger.key == "x"
  _G.BeardLib, PDTI._deploy_key_trigger, PDTI._cycle_key_trigger = nil, nil, nil
  return ok
end)())
clear_inventory()
T("X with nothing to hand picks nothing", Dep.Cycle() == nil)
T("changing the deployable shows no hint", hints == 0, hints)
managers.hud = nil

-- you brought an ammo bag but carry none: nothing to place
PDTI.SetDeployable(nil)
PM._equipment.selections[1] = { equipment = "ammo_bag", amount = { 1 } }
PM.can_use_selected_equipment = PlayerManager._pdti_original.can_use_selected_equipment
T("the game's ammo bag is blocked when none is carried", Dep.BlocksGame() == true)
PM._pdti_original.can_use_selected_equipment = function() return true end
dofile(ROOT .. "lua/hooks_player_manager.lua")
PDTI.AddItemAuto("rig", "first_aid_kit", 1, nil, true)
PDTI.RemoveItem("rig", PDTI.GetContainer("rig").items[1].instance_id)
T("the game may not place it", (function()
  PM._pdti_deploy_patched = nil
  PM.can_use_selected_equipment = function() return true end
  PM._pdti_original.can_use_selected_equipment = nil
  dofile(ROOT .. "lua/hooks_player_manager.lua")
  return PM.can_use_selected_equipment(PM, unit) == false
end)())
PE.calls = {}
T("and nothing is placed through the game", PM.use_selected_equipment(PM, unit) == nil and #PE.calls == 0)
PM._equipment.selections[1] = { equipment = "sentry_gun", amount = { 1 } }
T("a sentry gun you brought is still the game's", Dep.BlocksGame() == false and PM.can_use_selected_equipment(PM, unit) == true)
PM._equipment.selections[1] = { equipment = "ammo_bag", amount = { 1 } }
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
T("with one in the rig it can be placed again", PM.can_use_selected_equipment(PM, unit) == true)
PM._equipment.selections[1] = nil

-- the HUD line above the magazine panel
do
  local Hud = PDTI.DeployHud
  local function fake_panel(params)
    local p = { params = params or {}, kids = {} }
    function p:panel(q) local c = fake_panel(q); self.kids[#self.kids + 1] = c; return c end
    function p:text(q) local c = fake_panel(q); self.kids[#self.kids + 1] = c; return c end
    function p:rect(q) local c = fake_panel(q); self.kids[#self.kids + 1] = c; return c end
    function p:remove(c) for i, k in ipairs(self.kids) do if k == c then table.remove(self.kids, i) end end end
    function p:child(name) for _, k in ipairs(self.kids) do if k.params.name == name then return k end end end
    function p:w() return 1280 end
    function p:h() return 720 end
    function p:right() return (self.params.x or 0) + (self.params.w or 0) end
    function p:top() return self.params.y or 0 end
    return p
  end
  local root = fake_panel()
  _G.Color = _G.Color or function(...) return { ... } end
  _G.PlayerBase = { PLAYER_INFO_HUD_PD2 = 1 }
  managers.hud = { script = function() return { panel = root } end }
  clear_inventory()
  PDTI.SetDeployable(nil)
  PDTI.AddItemAuto("pockets", "first_aid_kit", 1, nil, true)
  Hud.Update(true)
  local line = root:child("pdti_deploy_panel")
  local text = line and line:child("pdti_deploy_text")
  T("the HUD shows the deployable", text and text.params.text:find("First Aid Kit x1") and text.params.text:find("%[X%]"),
    text and text.params.text)
  root:panel({ name = "pdti_ammo_panel", x = 1000, y = 560, w = 100, h = 60 })
  Hud.Update(true)
  line = root:child("pdti_deploy_panel")
  T("it sits on top of the magazine panel", line and line.params.y + line.params.h <= 560 and line:right() == 1100,
    line and (line.params.y .. "," .. line:right()))
  PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
  Dep.Cycle()
  line = root:child("pdti_deploy_panel")
  T("X redraws it at once", line and line:child("pdti_deploy_text").params.text:find("Ammo Bag") ~= nil)
  local count = 0
  for _, k in ipairs(root.kids) do if k.params.name == "pdti_deploy_panel" then count = count + 1 end end
  T("only one line is ever drawn", count == 1, count)
  managers.hud = nil
  Hud.Remove()
end

-- a new heist forgets the pick
Dep.SetSelection("ammo_bag")
Dep.OnHeistStart()
T("a new heist forgets your pick", Dep.GetManual() == nil)

-- 10. the carry weight slows the player down
clear_inventory()
PDTI.Carry.enabled = true
PDTI.SetEquipment("backpack", "large_backpack")
PDTI.SetEquipment("rig", "assault_rig") -- no speed bonus
PDTI.Carry.InvalidateCache()
T("an empty loadout runs at full speed", PDTI.Carry.GetSpeedFactor() == 1, PDTI.Carry.GetSpeedFactor())
PDTI.AddItemAuto("backpack", "doctor_bag", 1, nil, true)
T("a light loadout still runs at full speed", PDTI.Carry.GetBreakdown().load == 1)
local n = 0
while PDTI.AddItemAuto("backpack", "armor_kit", 1, nil, true) and n < 20 do n = n + 1 end
local heavy = PDTI.Carry.GetBreakdown().load
T("a heavy loadout is slower", heavy < 1 and heavy >= PDTI.Carry.MIN_FACTOR, heavy)
PDTI.Carry.enabled = false
T("the penalty can be switched off", PDTI.Carry.GetSpeedFactor() == 1)
PDTI.Carry.enabled = true

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
