-- 0.14.0: what you bring is chosen in the menu, per profile, and every heist
-- starts with exactly that.
--   luajit tests/plan_tests.lua
local script = arg and arg[0] or "tests/plan_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_plan") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo, Plan = PDTI.Ammo, PDTI.Plan
tweak_data.weapon.test_rifle.CLIP_AMMO_MAX = 30
tweak_data.weapon.test_pistol.CLIP_AMMO_MAX = 15
tweak_data.weapon.test_pump.CLIP_AMMO_MAX = 6
tweak_data.weapon.test_pump.use_shotgun_reload = true
tweak_data.weapon.test_akimbo.CLIP_AMMO_MAX = 34

-- The menu's weapons (BlackMarketManager:equipped_primary/secondary).
local menu_weapons = { primary = { weapon_id = "test_rifle", blueprint = { "wpn_no_part" } },
  secondary = { weapon_id = "test_pistol", blueprint = { "wpn_no_part" } } }
_G.managers = _G.managers or {}
managers.blackmarket = {
  equipped_primary = function() return menu_weapons.primary end,
  equipped_secondary = function() return menu_weapons.secondary end
}

local function count(kind) return Plan.Count(kind) end
local function in_menu()
  PDTI.SetSessionOnly(false)
  ENV.game.unit = nil -- no player in the menu
end
-- A new heist: the game loads Lua again, so the inventory comes from the
-- save of the profile, and nothing is saved in the heist.
local function start_heist()
  PDTI.LoadProfile()
  PDTI.SetSessionOnly(true)
  Ammo.OnHeistStart()
end
-- The weapons of the heist.
local function heist_weapons(primary_capacity)
  local unit = ENV.make_unit()
  local rifle = ENV.make_weapon("test_rifle", { "wpn_no_part" }, primary_capacity or 30, { _selection = 2 })
  local pistol = ENV.make_weapon("test_pistol", { "wpn_no_part" }, 15, { _selection = 1 })
  unit:set_weapon(rifle)
  Ammo.EnsureSupply(rifle)
  unit:set_weapon(pistol)
  Ammo.EnsureSupply(pistol)
  return rifle, pistol
end
local function real_mags(wep) return Ammo.Magazines(Ammo.Identify(wep).key) end

------------------------------------------------------------ the first plan

in_menu()
PDTI.Reset()
T("a new inventory has no ammunition plan", PDTI.IsAmmoPlanned() == false)
local info = Plan.Info("primary")
T("the menu knows the primary", info and info.weapon_id == "test_rifle" and info.capacity == 30, info and info.capacity)
T("not used in a heist yet: the size is the weapon's own", info and info.exact == false)
PDTI.OnUIOpen()
T("opening the inventory in the menu fills in the game's starting magazines",
  count("mag:primary") == 2 and count("mag:secondary") == 3, count("mag:primary") .. "/" .. count("mag:secondary"))
T("and the plan is decided", PDTI.IsAmmoPlanned() == true)

-------------------------------------------- the user's example, step by step

in_menu()
PDTI.Reset()
assert(PDTI.SetEquipment("rig", "medical_rig"))
assert(PDTI.SetEquipment("backpack", "large_backpack"))
for _ = 1, 4 do Plan.Add("first_aid_kit") end
for _ = 1, 2 do Plan.Add("doctor_bag") end
for _ = 1, 2 do Plan.Add("mag:primary") end
for _ = 1, 2 do Plan.Add("mag:secondary") end
Plan.Add("loose:primary")
Plan.Add("loose:secondary")
T("4 first aid kits", count("first_aid_kit") == 4, count("first_aid_kit"))
T("2 medic bags", count("doctor_bag") == 2, count("doctor_bag"))
T("2 primary and 2 secondary magazines", count("mag:primary") == 2 and count("mag:secondary") == 2)
T("a magazine's worth of loose rounds for each", count("loose:primary") == 30 and count("loose:secondary") == 15,
  count("loose:primary") .. "/" .. count("loose:secondary"))
T("choosing ammunition decides the plan", PDTI.IsAmmoPlanned() == true)
T("the state is valid", PDTI.ValidateState() == true)

start_heist()
local rifle, pistol = heist_weapons()
T("in the heist the primary magazines are the rifle's, full", #real_mags(rifle) == 2
  and real_mags(rifle)[1].rounds == 30 and real_mags(rifle)[2].rounds == 30)
T("the secondary magazines are the pistol's", #real_mags(pistol) == 2 and real_mags(pistol)[1].rounds == 15)
T("no extra starting magazines are made", count("mag:primary") == 0)
T("the loose rounds are the weapons'", Ammo.LooseOf(rifle) == 30 and Ammo.LooseOf(pistol) == 15,
  Ammo.LooseOf(rifle) .. "/" .. Ammo.LooseOf(pistol))
T("the deployables are there", count("first_aid_kit") == 4 and count("doctor_bag") == 2)

T("the ammunition maximum takes in what you brought", Ammo.MaxTotal(rifle) >= 30 + 2 * 30 + 30, Ammo.MaxTotal(rifle))
do
  PDTI.SetSessionOnly(true)
  for _ = 1, 6 do Ammo.AddMagazineKey("x", 1, { capacity = 1 }, { "backpack" }) end
end

-- Use everything and throw the magazines away.
for _, entry in ipairs(PDTI.FindItems(function(_, item) return true end)) do
  PDTI.RemoveItem(entry.container, entry.item.instance_id)
end
T("in the heist it is all gone", #PDTI.FindItems(function() return true end) == 0)

start_heist()
T("the next heist: 4 first aid kits again", count("first_aid_kit") == 4)
T("2 medic bags again", count("doctor_bag") == 2)
T("2 primary and 2 secondary magazines again", count("mag:primary") == 2 and count("mag:secondary") == 2)
T("the loose rounds again", count("loose:primary") == 30 and count("loose:secondary") == 15)
T("and the same rig and backpack", PDTI.GetEquipment().rig == "medical_rig" and PDTI.GetEquipment().backpack == "large_backpack")

---------------------------------------------- what a heist teaches the menu

start_heist()
heist_weapons(35) -- an extended magazine: 35 rounds in the heist
in_menu()
PDTI.LoadProfile()
info = Plan.Info("primary")
T("after a heist the menu knows the real magazine size", info.capacity == 35 and info.exact == true, info.capacity)
PDTI.OnUIOpen()
local m = Plan.Magazines("primary")[1]
T("the planned magazines take the real size", m and m.item.data.capacity == 35 and m.item.data.rounds == 35)

--------------------------------------------------------- weapon changes

menu_weapons.secondary = { weapon_id = "test_pump", blueprint = {} }
PDTI.OnUIOpen()
T("a shotgun loaded shell by shell has no magazines", count("mag:secondary") == 0)
T("its magazines became loose shells", count("loose:secondary") >= 30, count("loose:secondary"))
local ok, why = Plan.Add("mag:secondary")
T("and no magazine can be added", ok == false and tostring(why):find("round by round") ~= nil, why)
menu_weapons.secondary = { weapon_id = "test_akimbo", blueprint = {} }
T("akimbo pistols: a magazine is half the weapon's", Plan.Info("secondary").capacity == 17)
Plan.Add("mag:secondary")
T("their magazine is a 17-round one", Plan.Magazines("secondary")[1].item.data.capacity == 17)
menu_weapons.secondary = { weapon_id = "test_pistol", blueprint = { "wpn_no_part" } }

-- Removing: one less of each.
local before = count("mag:primary")
T("one less magazine", Plan.Remove("mag:primary") == true and count("mag:primary") == before - 1)
local loose_before = count("loose:primary")
Plan.Remove("loose:primary")
T("a magazine's worth less loose rounds", count("loose:primary") == math.max(0, loose_before - 35), count("loose:primary"))
T("one less first aid kit", Plan.Remove("first_aid_kit") == true and count("first_aid_kit") == 3)

-- The rows of the menu.
local rows = Plan.Rows()
local kinds = {}
for _, row in ipairs(rows) do kinds[row.kind] = row end
T("the bring list has the magazines and loose rounds of both guns",
  kinds["mag:primary"] and kinds["loose:primary"] and kinds["mag:secondary"] and kinds["loose:secondary"])
T("and the deployables", kinds.first_aid_kit and kinds.doctor_bag and kinds.ammo_bag and kinds.bodybags_bag)
T("but not items without an effect", kinds.grenade == nil and kinds.loot_bag == nil)

-- More than the game would give: the maximum grows with it.
do
  in_menu()
  for _ = 1, 5 do Plan.Add("mag:primary") end
  local planned = count("mag:primary")
  start_heist()
  local r = heist_weapons(35)
  T("a plan above the game's default fits under the maximum",
    Ammo.MaxTotal(r) >= 35 + planned * 35 + count("loose:primary"), Ammo.MaxTotal(r) .. " for " .. planned .. " mags")
  T("every planned magazine is bound, the backpack's too", #Ammo.AllMagazines(Ammo.Identify(r).key) == planned)
  in_menu()
  PDTI.LoadProfile()
end

------------------------------------------------------------ in the heist

PDTI.SetSessionOnly(true)
T("in a heist the plan cannot be changed", Plan.Add("first_aid_kit") == false)
T("in a heist the rig cannot be changed", PDTI.RequestEquip("rig", "general_rig") == false)
in_menu()

---------------------------------------------------------------- profiles

in_menu()
PDTI.LoadProfile(1)
local p1_items = #PDTI.FindItems(function() return true end)
Global.multi_profile._current_profile = 2
PDTI.OnUIOpen()
T("switching the profile loads its inventory", PDTI.loaded_profile == 2)
T("a profile without an inventory starts as a copy of the first", #PDTI.FindItems(function() return true end) == p1_items)
PDTI.Reset()
assert(PDTI.SetEquipment("rig", "general_rig"))
assert(PDTI.SetEquipment("backpack", "small_backpack"))
Plan.Add("first_aid_kit")
T("the second profile has its own file", io.open(TMP .. "pdti_inventory_profile2.json", "r") ~= nil)

Global.multi_profile._current_profile = 1
PDTI.OnUIOpen()
T("back to the first profile: medical rig and large backpack",
  PDTI.GetEquipment().rig == "medical_rig" and PDTI.GetEquipment().backpack == "large_backpack")
T("with its own things", #PDTI.FindItems(function() return true end) == p1_items)
Global.multi_profile._current_profile = 2
PDTI.OnUIOpen()
T("the second profile: general rig and small backpack",
  PDTI.GetEquipment().rig == "general_rig" and PDTI.GetEquipment().backpack == "small_backpack")
T("with one first aid kit", count("first_aid_kit") == 1)

-- The heist starts with the profile chosen in the menu.
start_heist()
T("a heist of the second profile has its inventory", PDTI.GetEquipment().rig == "general_rig" and count("first_aid_kit") == 1)
Global.multi_profile._current_profile = 1
PDTI.SetSessionOnly(false)

----------------------------------------------- leftovers of older versions

in_menu()
PDTI.LoadProfile(1)
Ammo.AddMagazineKey("old|key", 10, { capacity = 30 }, { "backpack" })
start_heist()
T("at the start of a heist old weapon-bound ammunition goes, the plan stays",
  #Ammo.AllMagazines("old|key") == 0 and count("mag:primary") > 0)

-- Not planned yet (the inventory was never opened in the menu): the game's
-- starting magazines, as before.
in_menu()
PDTI.Reset()
PDTI.SetSessionOnly(true)
Ammo.OnHeistStart()
rifle = heist_weapons()
T("no plan: the weapon gets the game's starting magazines", #real_mags(rifle) == 2, #real_mags(rifle))
PDTI.SetSessionOnly(false)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
