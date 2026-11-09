-- The game loads its weapon classes after the mod. The ammunition hooks have
-- to be installed as soon as the classes are there, otherwise the whole
-- system stays switched off and the game reloads like vanilla.
--   texlua tests/install_tests.lua
local script = arg and arg[0] or "tests/install_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_install") .. "/")
_G.ModPath = ROOT
ENV.install_game()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

-- The classes of the game are not there yet when the mod loads.
local saved = {
  NewRaycastWeaponBase = _G.NewRaycastWeaponBase,
  RaycastWeaponBase = _G.RaycastWeaponBase,
  PlayerInventory = _G.PlayerInventory,
  HUDTeammate = _G.HUDTeammate
}
-- the functions of the game, before the mod wraps them
local original = {
  on_reload = saved.NewRaycastWeaponBase.on_reload,
  add_ammo = saved.RaycastWeaponBase.add_ammo,
  add_ammo_from_bag = saved.RaycastWeaponBase.add_ammo_from_bag
}
_G.NewRaycastWeaponBase = nil
_G.RaycastWeaponBase = nil
_G.PlayerInventory = nil
_G.HUDTeammate = nil

dofile(ROOT .. "lua/items.lua")
dofile(ROOT .. "lua/inventory.lua")
dofile(ROOT .. "lua/ammo.lua")
dofile(ROOT .. "lua/ammo_hooks.lua")

local Ammo = PDTI.Ammo

T("the installation waits for the classes of the game", Ammo.InstallHooks() == false)
T("nothing is wrapped while the classes are missing",
  Ammo.hooks == nil or Ammo.hooks["NewRaycastWeaponBase.on_reload"] == nil
  or Ammo.hooks["NewRaycastWeaponBase.on_reload"].hook == nil)

-- The game loads its classes.
_G.NewRaycastWeaponBase = saved.NewRaycastWeaponBase
_G.RaycastWeaponBase = saved.RaycastWeaponBase
_G.PlayerInventory = saved.PlayerInventory
_G.HUDTeammate = saved.HUDTeammate

T("the hooks are installed once the classes are there", Ammo.InstallHooks() == true)
T("the reload hook is in place", _G.NewRaycastWeaponBase.on_reload ~= original.on_reload)
T("the pickup hook is in place", _G.RaycastWeaponBase.add_ammo ~= original.add_ammo)
T("the bag hook is in place", _G.RaycastWeaponBase.add_ammo_from_bag ~= original.add_ammo_from_bag)

local wrapped = _G.NewRaycastWeaponBase.on_reload
Ammo.InstallHooks()
T("the hooks are not wrapped twice", _G.NewRaycastWeaponBase.on_reload == wrapped)

------------------------------------------------------ the system works

local unit = ENV.make_unit()
local wep = ENV.make_weapon("test_rifle")
unit:set_weapon(wep)

Ammo.EnsureSupply(wep)
local key = Ammo.Identify(wep).key
T("the supply exists", Ammo.MagCount(key) == 3, Ammo.MagCount(key))

-- A pickup becomes loose ammunition in the inventory. The game's maximum is
-- raised by the mod (the magazines plus the ammo_max setting).
wep:set_ammo_max(Ammo.MaxTotal(wep))
local picked, amount = _G.RaycastWeaponBase.add_ammo(wep, 1, 40)
T("the pickup is accepted", picked == true and amount == 40, tostring(amount))
T("the picked up rounds are loose ammunition", Ammo.LooseOf(wep) == 40, Ammo.LooseOf(wep))
T("the loose rounds are an inventory item", #PDTI.FindItems(function(_, item)
  return item.item_id == "loose_ammo"
end) == 1)

-- The reload takes a magazine out of the rig and puts it into the gun.
wep.clip = 5
_G.NewRaycastWeaponBase.on_reload(wep)
T("the gun is loaded from the inventory", wep.clip == 30, wep.clip)
T("the old magazine goes back into the inventory", Ammo.MagCount(key) == 3, Ammo.MagCount(key))
T("the old magazine keeps its rounds", Ammo.MagazineRounds(key) == 5 + 30 + 30,
  Ammo.MagazineRounds(key))
T("the loose rounds are not used by the reload", Ammo.LooseOf(wep) == 40, Ammo.LooseOf(wep))

-- The panel follows the gun.
Ammo.panel_dirty = false
wep.clip = 12
Ammo.GameTick({ _state_data = {} }, 10, 0.016, false)
T("the panel is marked dirty when the clip changes", Ammo.panel_dirty == true)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
