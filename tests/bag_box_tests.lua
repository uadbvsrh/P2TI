-- 0.21.3: an ammo bag never gains uses from what you take (restoration-mod
-- works out the share as "1 - total / max", less than nothing above the
-- maximum), and ammo boxes give loose rounds up to two stacks per weapon;
-- with both guns there the boxes stay on the floor.
--   luajit tests/bag_box_tests.lua
local script = arg and arg[0] or "tests/bag_box_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_bag_box") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, true)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end

-- restoration-mod's add_ammo_from_bag (raycastweaponbase.lua), as it is.
RaycastWeaponBase.add_ammo_from_bag = function(self, available)
  local function process_ammo(ammo_base, amount_available)
    if ammo_base:get_ammo_max() == ammo_base:get_ammo_total() then return 0 end
    local ammo_max = ammo_base:get_ammo_max()
    local ammo_total = ammo_base:get_ammo_total()
    local wanted = 1 - ammo_total / ammo_max
    local ratio = ammo_base._ammo_ratio or 1
    local can_have = math.min(wanted, amount_available / ratio)
    ammo_base:set_ammo_total(math.min(ammo_max, ammo_total + math.ceil(can_have * ammo_max)))
    return can_have * ratio
  end
  return process_ammo(self, available)
end
-- restoration-mod's AmmoClip:_pickup: a box is taken when a gun took
-- rounds, or anyway when the grenades are not full.
_G.AmmoClip = { _pickup = function(self, unit)
  local picked = false
  for _, sel in pairs(unit:inventory():available_selections()) do
    local ok = RaycastWeaponBase.add_ammo(sel.unit:base(), 1, self._ammo_count)
    picked = ok or picked
  end
  if not picked and not self.grenades_full then picked = true end
  if picked then self._picked_up = true end
  return picked
end }
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true and Ammo.hooks["AmmoClip._pickup"] ~= nil)

local function fresh()
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetSessionOnly(true)
  return ENV.make_unit()
end

-- The game's ammo bag (restoration-mod's _take_ammo): what each gun took
-- comes off the bag.
local function take(bag, unit)
  local taken = 0
  for _, sel in pairs(unit:inventory():available_selections()) do
    local took = RaycastWeaponBase.add_ammo_from_bag(sel.unit:base(), bag.amount)
    taken = taken + took
    bag.amount = bag.amount - took
    if bag.amount <= 0 then bag.amount = 0; break end
  end
  return taken
end

----------------------------------------------------------------- the bag

do -- A pump shotgun with more shells than the game's maximum (48).
  local unit = fresh()
  local pump = ENV.make_weapon("test_pump", { "wpn_mag_test" }, 6, { _use_shotgun_reload = true, ammo_max = 48 })
  unit:set_weapon(pump)
  Ammo.EnsureSupply(pump)
  local info = Ammo.Identify(pump)
  Ammo.AddLooseKey(info.key, 100, info)
  Ammo.SyncTotal(pump)
  T("the inventory holds more than the game's maximum", pump:get_ammo_total() > pump:get_ammo_max(),
    pump:get_ammo_total())
  local bag = { amount = 2 }
  local before = Ammo.LooseOfKey(info.key)
  local took = take(bag, unit)
  T("the bag takes nothing, not less than nothing", took == 0 and bag.amount == 2, took .. " / " .. bag.amount)
  for _ = 1, 5 do take(bag, unit) end
  T("taking again and again never gives the bag more uses", bag.amount == 2, bag.amount)
  T("and the shells you carry stay", Ammo.LooseOfKey(info.key) == before and pump:get_ammo_total() == before
    + pump:get_ammo_remaining_in_clip(), Ammo.LooseOfKey(info.key))
  -- Below the maximum the bag gives shells and loses them.
  for _, s in ipairs(Ammo.LooseStacks(info.key)) do PDTI.RemoveItem(s.container, s.instance_id) end
  Ammo.AddLooseKey(info.key, 10, info)
  Ammo.SyncTotal(pump)
  local had = Ammo.LooseOfKey(info.key)
  took = take(bag, unit)
  T("below the maximum the bag gives shells", took > 0 and bag.amount < 2 and Ammo.LooseOfKey(info.key) > had,
    took .. " / " .. Ammo.LooseOfKey(info.key))
  local left = bag.amount
  take(bag, unit)
  T("and a second take from a full gun takes nothing", bag.amount == left, bag.amount)
end

do -- A rifle with magazines: never less than nothing, the ratio honoured.
  local unit = fresh()
  local wep = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { ammo_max = 150, _ammo_ratio = 0.5 })
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  local info = Ammo.Identify(wep)
  local first = Ammo.Magazines(info.key)[1]
  Ammo.SetMagazineRounds(first.container, first.instance_id, 0)
  local bag = { amount = 2 }
  local took = take(bag, unit)
  T("a magazine gun takes a share", took > 0 and took <= 2, took)
  -- 30 rounds of 150 at ratio 0.5: the game would count 0.2 * 0.5.
  T("by the weapon's ammo ratio (restoration-mod)", math.abs(took - 30 / Ammo.BaseTotal(wep) * 0.5) < 1e-6, took)
  local left = bag.amount
  for _ = 1, 5 do take(bag, unit) end
  T("a full gun takes nothing again", bag.amount <= left and bag.amount >= 0, bag.amount)
end

----------------------------------------------------------------- the boxes

-- Two guns: a rifle and a pistol.
local unit = fresh()
local rifle = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { ammo_max = 1000, _ammo_pickup = { 60, 60 } })
local pistol = ENV.make_weapon("test_pistol", { "wpn_mag_test" }, 15, { ammo_max = 1000, _ammo_pickup = { 60, 60 },
  _selection = 1 })
unit:set_weapon(rifle)
local inventory = unit:inventory()
function inventory:available_selections()
  return { { unit = { base = function() return rifle end } }, { unit = { base = function() return pistol end } } }
end
Ammo.EnsureSupply(rifle)
Ammo.EnsureSupply(pistol)
local rinfo, pinfo = Ammo.Identify(rifle), Ammo.Identify(pistol)
for _, k in ipairs({ rinfo.key, pinfo.key }) do
  for _, s in ipairs(Ammo.LooseStacks(k)) do PDTI.RemoveItem(s.container, s.instance_id) end
end
T("the limit is two stacks (200 rounds)", Ammo.BoxLimit() == 200, Ammo.BoxLimit())

local function box() return setmetatable({}, { __index = AmmoClip }) end
Ammo.AddLooseKey(rinfo.key, 170, rinfo)
local b = box()
T("a box is picked up", AmmoClip._pickup(b, unit) == true)
T("the rifle is filled only up to two stacks", Ammo.LooseOfKey(rinfo.key) == 200, Ammo.LooseOfKey(rinfo.key))
T("the pistol gets its rounds", Ammo.LooseOfKey(pinfo.key) == 60, Ammo.LooseOfKey(pinfo.key))
for _ = 1, 4 do AmmoClip._pickup(box(), unit) end
T("the pistol stops at two stacks too", Ammo.LooseOfKey(pinfo.key) == 200, Ammo.LooseOfKey(pinfo.key))
T("both guns are full for the boxes", Ammo.BoxesFull(unit) == true)
b = box()
T("a box is not picked up any more (even with grenades to fill)", AmmoClip._pickup(b, unit) == false
  and not b._picked_up)
local g = setmetatable({ _projectile_id = "frag" }, { __index = AmmoClip })
T("a throwable box is left to the game", AmmoClip._pickup(g, unit) == true)
local arrows = setmetatable({ _weapon_category = "bow" }, { __index = AmmoClip })
T("one weapon's arrows are left to the game", AmmoClip._pickup(arrows, unit) == true)
-- Shooting: the rifle's rounds drop below the limit, the boxes come back.
local s = Ammo.LooseStacks(rinfo.key)[1]
PDTI.RemoveItem(s.container, s.instance_id)
T("below the limit boxes are picked up again", Ammo.BoxesFull(unit) == false and AmmoClip._pickup(box(), unit) == true)
T("rounds brought in other bullets count too", (function()
  for _, st in ipairs(Ammo.LooseStacks(rinfo.key)) do PDTI.RemoveItem(st.container, st.instance_id) end
  Ammo.AddLooseKey(rinfo.key, 200, rinfo, "ap")
  return Ammo.BoxRoom(rifle) == 0
end)())
for _, st in ipairs(Ammo.LooseStacks(pinfo.key)) do PDTI.RemoveItem(st.container, st.instance_id) end
Ammo.AddLooseKey(pinfo.key, 200, pinfo)
T("both full again", Ammo.BoxesFull(unit) == true, Ammo.LooseOfKey(rinfo.key) .. "/" .. Ammo.LooseOfKey(pinfo.key))
Ammo.settings.enabled = false
T("with the ammunition system off the game decides (it takes the box)", AmmoClip._pickup(box(), unit) == true)
Ammo.settings.enabled = true

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
