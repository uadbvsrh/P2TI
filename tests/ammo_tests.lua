-- The ammunition system of the merged mod: the inventory IS the magazine
-- supply. These tests run the real modules against a fake game.
--   texlua tests/ammo_tests.lua
local script = arg and arg[0] or "tests/ammo_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_ammo") .. "/")
_G.ModPath = ROOT
ENV.install_game()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

dofile(ROOT .. "lua/items.lua")
dofile(ROOT .. "lua/inventory.lua")
dofile(ROOT .. "lua/ammo.lua")
dofile(ROOT .. "lua/ammo_hooks.lua")
local Ammo = PDTI.Ammo

local unit = ENV.make_unit()
local wep = ENV.make_weapon("test_rifle")
unit:set_weapon(wep)

local function rig_items() return PDTI.GetContainer("rig").items end
local function pack_items() return PDTI.GetContainer("backpack").items end
local function find_mag(key)
  for _, entry in ipairs(Ammo.AllMagazines(key)) do return entry end
end

---------------------------------------------------------------- the supply

Ammo.EnsureSupply(wep)
local key = Ammo.Identify(wep).key
T("the starting magazines are created", Ammo.MagCount(key) == 3, Ammo.MagCount(key))
T("the starting magazines are full", (find_mag(key) or {}).rounds == 30)
T("the starting magazines are in the rig", #rig_items() == 3)

-- A magazine in the backpack is carried but not ready.
local first = rig_items()[1]
PDTI.MoveItem("rig", first.instance_id, "backpack", 0, 0, false)
T("a magazine in the backpack is not part of the supply", Ammo.MagCount(key) == 2, Ammo.MagCount(key))
T("the magazine is still in the inventory", #pack_items() == 1)
PDTI.MoveItem("backpack", first.instance_id, "rig", 0, 0, false)
T("moving it back makes it ready again", Ammo.MagCount(key) == 3, Ammo.MagCount(key))

-- Discarding a magazine removes it; nothing replaces it.
local victim = rig_items()[2]
PDTI.RemoveItem("rig", victim.instance_id)
T("a discarded magazine is gone", Ammo.MagCount(key) == 2, Ammo.MagCount(key))
T("a discarded magazine does not come back", #PDTI.FindItems(function(_, item)
  return item.item_id == "spare_magazine" and item.data and item.data.queue_key == key
end) == 2)

------------------------------------------------------------- loose rounds

local ok = Ammo.AddLoose(wep, 60)
T("loose rounds can be added", ok == true)
T("the loose rounds are counted", Ammo.LooseOf(wep) == 60, Ammo.LooseOf(wep))
T("the loose rounds are inventory items", #PDTI.FindItems(function(_, item)
  return item.item_id == "loose_ammo"
end) == 1)

-- The rounds really leave the stack when they are used.
Ammo.ConsumeLoose(wep, 25)
T("used rounds leave the stack", Ammo.LooseOf(wep) == 35, Ammo.LooseOf(wep))

Ammo.SetLoose(wep, 10)
T("the loose rounds can be set", Ammo.LooseOf(wep) == 10, Ammo.LooseOf(wep))
Ammo.SetLoose(wep, 40)
T("the loose rounds can be raised", Ammo.LooseOf(wep) == 40, Ammo.LooseOf(wep))

------------------------------------------------------------- packing them

-- The magazines are full (30 rounds each) and so is the gun: the loose
-- rounds have nowhere to go. No magazine is made out of loose rounds.
wep.clip = 30
Ammo.SetLoose(wep, 100)
local left = Ammo.FillMagazines(wep, 100)
T("packing fills the gun", wep.clip == 30, wep.clip)
T("packing never starts a new magazine", Ammo.MagCount(key) == 2, Ammo.MagCount(key))
T("packing takes the rounds out of the loose ammunition", Ammo.LooseOf(wep) == left)
T("rounds without a magazine stay loose", Ammo.LooseOf(wep) == 100, Ammo.LooseOf(wep))
T("the rounds are in the magazines", Ammo.MagazineRounds(key) == 60,
  Ammo.MagazineRounds(key))

-- A magazine with room is filled first, and the rounds come from the stack.
local roomy = rig_items()[1]
Ammo.SetMagazineRounds("rig", roomy.instance_id, 10)
Ammo.SetLoose(wep, 5)
Ammo.FillMagazines(wep, 5)
local after = PDTI.FindItem("rig", roomy.instance_id)
T("a magazine with room is filled", after.data.rounds == 15, after.data.rounds)
T("the rounds came out of the loose ammunition", Ammo.LooseOf(wep) == 0, Ammo.LooseOf(wep))

--------------------------------------------------------------- the totals

Ammo.SyncTotal(wep)
T("the total is the clip, the loose rounds and the magazines",
  wep.total == wep.clip + Ammo.LooseOf(wep) + Ammo.MagazineRounds(key),
  wep.total .. " vs " .. (wep.clip + Ammo.LooseOf(wep) + Ammo.MagazineRounds(key)))

------------------------------------------------------------ the reload

-- Another weapon type, so it has a supply of its own.
local unit2 = ENV.make_unit()
local wep2 = ENV.make_weapon("test_smg")
unit2:set_weapon(wep2)
Ammo.EnsureSupply(wep2)
local key2 = Ammo.Identify(wep2).key
T("the second weapon type has its own supply", Ammo.MagCount(key2) == 3, Ammo.MagCount(key2))

wep2.clip = 12
wep2._issr_mag_installed = { rounds = 12 }
NewRaycastWeaponBase.on_reload(wep2)

local mags_after = Ammo.MagCount(key2)
T("a reload does not invent magazines", mags_after == 3, mags_after)
local rounds = {}
for _, entry in ipairs(Ammo.Magazines(key2)) do rounds[#rounds + 1] = entry.rounds end
table.sort(rounds)
T("the old magazine goes back into the inventory",
  rounds[1] == 12 and rounds[2] == 30 and rounds[3] == 30, table.concat(rounds, "/"))
T("the gun holds the magazine that was taken", wep2.clip == 30, wep2.clip)
T("the total is the magazine in the gun and the ones in the inventory",
  wep2.total == 30 + 72, wep2.total)

------------------------------------------------------------- the pickup

-- A third weapon type.
local unit3 = ENV.make_unit()
local pickup = ENV.make_weapon("test_smg", { "wpn_mag_small" })
unit3:set_weapon(pickup)
local pickup_key = Ammo.Identify(pickup).key
local before = Ammo.LooseOf(pickup)
local added, added_amount = RaycastWeaponBase.add_ammo(pickup, 1, 40)
T("a pickup is accepted", added == true and added_amount == 40, tostring(added_amount))
T("the picked up rounds are loose ammunition in the inventory",
  Ammo.LooseOf(pickup) == before + 40, Ammo.LooseOf(pickup))
T("the picked up rounds are a real inventory item", #PDTI.FindItems(function(_, item)
  return item.item_id == "loose_ammo" and item.data and item.data.queue_key == pickup_key
end) == 1)

------------------------------------------------------------- the ammo bag

-- A fourth weapon type, with a supply of its own. The inventory is emptied
-- first, so the magazines really fit.
PDTI.Reset()
Ammo.Reset()
local unit4 = ENV.make_unit()
local bag_weapon = ENV.make_weapon("test_pistol")
unit4:set_weapon(bag_weapon)
Ammo.EnsureSupply(bag_weapon)
local bag_key = Ammo.Identify(bag_weapon).key
bag_weapon.clip = 0
bag_weapon.total = 0
RaycastWeaponBase.add_ammo_from_bag(bag_weapon, 60, nil)
T("the bag's ammunition is packed into the magazines",
  Ammo.MagazineRounds(bag_key) == 90, Ammo.MagazineRounds(bag_key))
T("the bag's rounds do not go into the magazine in the gun", bag_weapon.clip == 0, bag_weapon.clip)
T("a bag restocks magazines and gives no loose rounds (0.18.5)", Ammo.LooseOf(bag_weapon) == 0,
  Ammo.LooseOf(bag_weapon))

----------------------------------------------------------- the heist start

Ammo.OnHeistStart()
T("a new heist clears the magazines", #PDTI.FindItems(function(_, item)
  return item.item_id == "spare_magazine"
end) == 0)
T("a new heist clears the loose ammunition", #PDTI.FindItems(function(_, item)
  return item.item_id == "loose_ammo"
end) == 0)

-- magazine sizes follow the capacity
do
  local function size(cap) local w, h = PDTI.MagazineSize(cap); return w .. "x" .. h end
  T("under 30 rounds: one cell", size(20) == "1x1" and size(29) == "1x1", size(20))
  T("30 rounds: two cells", size(30) == "1x2" and size(45) == "1x2", size(30))
  T("60 rounds: three in one line", size(60) == "1x3" and size(99) == "1x3", size(60))
  T("100 rounds: a 2x2 square", size(100) == "2x2" and size(200) == "2x2", size(100))
  for _, c in ipairs({ "pockets", "rig", "backpack" }) do
    for _, it in ipairs(PDTI.GetContainer(c).items) do PDTI.RemoveItem(c, it.instance_id) end
  end
  local function mag(cap) return { queue_key = "T|m" .. cap, rounds = cap, capacity = cap, caliber = "T" } end
  local function cells(container, inst)
    local map, n = PDTI.GetOccupancyMap(container), 0
    for _, row in ipairs(map.cells) do for _, id in ipairs(row) do if id == inst then n = n + 1 end end end
    return n
  end
  local _, small = PDTI.AddItemAuto("pockets", "spare_magazine", 1, mag(17), true)
  local _, std = PDTI.AddItemAuto("rig", "spare_magazine", 1, mag(30), true)
  local _, drum = PDTI.AddItemAuto("rig", "spare_magazine", 1, mag(75), true)
  local _, box = PDTI.AddItemAuto("rig", "spare_magazine", 1, mag(100), true)
  T("a 17-round magazine takes one cell", small and cells("pockets", small.instance_id) == 1)
  T("a 30-round magazine takes two", std and cells("rig", std.instance_id) == 2)
  T("a 75-round drum takes three", drum and cells("rig", drum.instance_id) == 3)
  T("a 100-round box takes a 2x2 square", box and cells("rig", box.instance_id) == 4)
  local map = PDTI.GetOccupancyMap("rig")
  local bx, by = box.x + 1, box.y + 1
  local rot = PDTI.FindItem("rig", box.instance_id).rotated
  T("the square is two wide and two tall", map.cells[by][bx] == box.instance_id and map.cells[by + 1][bx + 1] == box.instance_id)
  -- four 17-round magazines fill the 2x2 pockets
  for _ = 1, 3 do PDTI.AddItemAuto("pockets", "spare_magazine", 1, mag(17), true) end
  T("four small magazines fit in the pockets", #PDTI.GetContainer("pockets").items == 4)
  T("room for a magazine depends on its size", Ammo.HasMagazineRoom(17) == (PDTI.FindFreeSpace("rig", { item_id = "spare_magazine", data = { capacity = 17 } }) ~= nil))
  local moved = PDTI.MoveItem("rig", drum.instance_id, "backpack", 0, 0, false)
  T("a moved magazine keeps its size", moved and cells("backpack", drum.instance_id) == 3)
  T("arranging keeps every magazine", PDTI.AutoArrange("rig", true) and #PDTI.GetContainer("rig").items == 2)
  T("the state stays valid", PDTI.ValidateState() == true)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
