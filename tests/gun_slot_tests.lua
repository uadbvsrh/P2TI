-- 0.17.1: in a heist the weapon's slot holds the magazine that is in the
-- gun. Taking it out of the slot takes it out of the gun; a magazine put
-- into the empty slot goes into the gun.
--   luajit tests/gun_slot_tests.lua
local script = arg and arg[0] or "tests/gun_slot_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_gunslot") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end
NewRaycastWeaponBase._get_current_damage = function(self, dmg_mul) return (self._damage or 10) * (dmg_mul or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function(self) return self._armor_piercing_chance or 0.25 end
_G.CopDamage = { roll_critical_hit = function(_, attack_data) return false, attack_data.damage end }
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })
dofile(ROOT .. "lua/ammo_hud.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo, Plan = PDTI.Ammo, PDTI.Plan
T("the hooks are in place", Ammo.InstallHooks() == true)

local current = {}
local function fresh(name, capacity, selection)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  PDTI.SetEquipment("backpack", "large_backpack")
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon(name or "test_ar", { "wpn_no_part" }, capacity or 30, { _selection = selection or 2 })
  unit:set_weapon(wep)
  current.unit, current.wep = unit, wep
  Ammo.EnsureSupply(wep)
  wep.clip = wep:get_ammo_max_per_clip()
  Ammo.SyncTotal(wep)
  return wep, Ammo.Identify(wep)
end
local function slot_items(c) return PDTI.GetContainerInfo(c or "gun_primary").items end
local function count_mag_items(key)
  return #PDTI.FindItems(function(_, item)
    return item.item_id == Ammo.MAGAZINE_ITEM and type(item.data) == "table" and item.data.queue_key == key
  end)
end
local function sync(w) Ammo.SyncGunSlot(w) end
local function to_backpack(id)
  local it = PDTI.FindItem("gun_primary", id)
  local bx, by, rot = PDTI.FindFreeSpace("backpack", { item_id = it.item_id, data = it.data }, true)
  return PDTI.RequestMove("gun_primary", id, "backpack", bx, by, rot)
end

---------------------------------------------------- the gun's magazine is there

local wep, info = fresh("test_ar", 30)
local key = info.key
local mags_before = #Ammo.AllMagazines(key)
sync(wep)
local g = slot_items()[1]
T("in a heist the weapon's slot holds the magazine in the gun", #slot_items() == 1 and g.data.in_gun == true
  and g.data.rounds == 30 and g.data.size == "standard")
T("it is not a spare magazine", #Ammo.AllMagazines(key) == mags_before and Ammo.NextMagazine(wep).container ~= "gun_primary")
T("and the total does not count it twice", wep.total == 30 + Ammo.MagazineRounds(key), wep.total)
wep.clip = 25
sync(wep)
T("its rounds follow the shots", slot_items()[1].data.rounds == 25)
T("one item only, whatever happens", #slot_items() == 1)

-- Taking it out: into the backpack.
local id = slot_items()[1].instance_id
local x, y = PDTI.FindFreeSpace("backpack", { item_id = Ammo.MAGAZINE_ITEM, data = slot_items()[1].data }, true)
T("the magazine can be taken out of the slot", PDTI.RequestMove("gun_primary", id, "backpack", x, y, false) == true)
sync(wep)
T("the gun has no magazine now", wep.clip == 0 and wep._issr_mag_gone == true and wep._issr_no_mag == true)
local out = PDTI.FindItem("backpack", id)
T("the magazine is in the backpack with its 25 rounds", out and out.data.in_gun == false and out.data.rounds == 25)
T("and counts as a magazine you carry", #Ammo.AllMagazines(key) == mags_before + 1)
T("the total follows", wep.total == Ammo.MagazineRounds(key), wep.total .. " vs " .. Ammo.MagazineRounds(key))
sync(wep)
T("the slot stays empty", #slot_items() == 0)

-- Putting one in: a compact armour-piercing magazine from the pockets.
Ammo.AddMagazineKey(key, 20, info, { "pockets" }, { size = "compact", bullet = "ap" })
local ap = nil
for _, m in ipairs(Ammo.Magazines(key)) do if m.bullet == "ap" then ap = m end end
T("a magazine can be put into the empty slot", PDTI.RequestMove(ap.container, ap.instance_id, "gun_primary", 0, 0, false) == true)
sync(wep)
T("it goes into the gun", wep.clip == 20 and wep:get_ammo_max_per_clip() == 20 and Ammo.CurrentBullet(wep) == "ap"
  and not wep._issr_mag_gone and not wep._issr_no_mag, wep.clip)
T("it stays in the slot, as the gun's magazine", #slot_items() == 1 and slot_items()[1].instance_id == ap.instance_id
  and slot_items()[1].data.in_gun == true)
T("and is no spare any more", #Ammo.AllMagazines(key) == mags_before + 1)

-- A reload: the old magazine goes back, the new one shows in the slot.
local items_before = count_mag_items(key)
wep.clip = 4
sync(wep)
NewRaycastWeaponBase.on_reload(wep)
sync(wep)
T("a reload puts the new magazine in the slot", #slot_items() == 1 and slot_items()[1].data.in_gun == true
  and slot_items()[1].data.rounds == wep.clip and slot_items()[1].data.bullet ~= "ap" or false, wep.clip)
local back = nil
for _, m in ipairs(Ammo.AllMagazines(key)) do if m.bullet == "ap" then back = m end end
T("and the old one is back with its 4 rounds", back and back.rounds == 4 and back.container ~= "gun_primary")
T("no magazine was made or lost", count_mag_items(key) == items_before, count_mag_items(key) .. " vs " .. items_before)

-- During a reload the magazine is out of the gun (from the game's stage).
wep._issr_in_reload = true
wep._issr_no_mag = true
sync(wep)
T("mid-reload the slot is empty", #slot_items() == 0)
wep._issr_no_mag = nil
wep._issr_in_reload = nil
sync(wep)
T("an interrupted reload: the magazine is back in the slot", #slot_items() == 1)

-- Thrown away: the gun is empty and the rounds are gone.
local total_before = wep.total
local clip_before = wep.clip
PDTI.RemoveItem("gun_primary", slot_items()[1].instance_id)
sync(wep)
T("thrown away from the slot: the gun is empty", wep.clip == 0 and wep._issr_mag_gone == true)
T("the rounds went with it", wep.total == total_before - clip_before, wep.total)
T("a reload with no magazine in the gun returns nothing", (function()
  local n = count_mag_items(key)
  NewRaycastWeaponBase.on_reload(wep)
  sync(wep)
  return count_mag_items(key) == n and #slot_items() == 1 and wep.clip > 0
end)())

--------------------------------------------------------- an untyped weapon

do
  local w, i = fresh("test_smg", 30)
  sync(w)
  local it = slot_items()[1]
  T("an LMG's slot holds its magazine too", it and it.data.in_gun == true and it.data.rounds == 30 and it.data.size == nil)
  to_backpack(it.instance_id)
  sync(w)
  T("and taking it out empties the gun", w.clip == 0 and w._issr_mag_gone == true)
  PDTI.RequestMove("backpack", it.instance_id, "gun_primary", 0, 0, false)
  sync(w)
  T("putting it back loads it", w.clip == 30 and not w._issr_mag_gone)
end

------------------------------------------------------------------ akimbo

do
  local w, i = fresh("test_akimbo_smg", 40)
  local k = i.key
  sync(w)
  T("akimbo: a magazine per gun in the slot", #slot_items() == 2 and slot_items()[1].data.rounds == 20
    and slot_items()[2].data.rounds == 20)
  local second = nil
  for _, it in ipairs(slot_items()) do if it.x == 1 then second = it end end
  to_backpack(second.instance_id)
  sync(w)
  local pair = Ammo.AkimboPair(w)
  T("one taken out: that gun is empty, the other keeps its 20", w.clip == 20 and pair[1] == 20 and pair[2] == 0
    and not w._issr_mag_gone, w.clip .. " " .. pair[1] .. "," .. pair[2])
  T("one magazine left in the slot", #slot_items() == 1)
  -- Two taps (one magazine): the empty gun gets one, the other keeps its own.
  local n = count_mag_items(k)
  Ammo.AddMagazineKey(k, 20, i, { "pockets" }, { size = "standard", bullet = "hollow" })
  w._pdti_akimbo_mode = "one"
  NewRaycastWeaponBase.on_reload(w)
  sync(w)
  pair = Ammo.AkimboPair(w)
  T("two taps fill the empty gun", w.clip == 40 and pair[1] == 20 and pair[2] == 20, w.clip)
  T("and give no magazine back", count_mag_items(k) == n + 1, count_mag_items(k) .. " vs " .. (n + 1))
  T("both guns are in the slot again", #slot_items() == 2)
  local bullets = {}
  for _, it in ipairs(slot_items()) do bullets[#bullets + 1] = it.data.bullet end
  table.sort(bullets)
  T("each with its own bullets", bullets[1] == "hollow" and bullets[2] == "standard", table.concat(bullets, ","))
  -- Take one out and put another in by hand.
  local hp_item = nil
  for _, it in ipairs(slot_items()) do if it.data.bullet == "hollow" then hp_item = it end end
  to_backpack(hp_item.instance_id)
  sync(w)
  Ammo.AddMagazineKey(k, 26, i, { "pockets" }, { size = "compact", bullet = "ap" })
  local apm = nil
  for _, m in ipairs(Ammo.Magazines(k)) do if m.bullet == "ap" then apm = m end end
  PDTI.RequestMove(apm.container, apm.instance_id, "gun_primary", hp_item.x, 0, false)
  sync(w)
  pair = Ammo.AkimboPair(w)
  T("a magazine put into the free half goes into that gun", w.clip == 33 and (pair[1] == 13 or pair[2] == 13),
    w.clip .. " " .. pair[1] .. "," .. pair[2])
end

--------------------------------------------------------- the plan and the UI

local menu_weapons = { primary = { weapon_id = "test_ar", blueprint = { "wpn_no_part" } },
  secondary = { weapon_id = "test_pistol", blueprint = { "wpn_no_part" } } }
managers.blackmarket = {
  equipped_primary = function() return menu_weapons.primary end,
  equipped_secondary = function() return menu_weapons.secondary end
}
tweak_data.weapon.test_pistol.CLIP_AMMO_MAX = 15
PDTI.Loadout.Get = function()
  return { { slot = "primary", name = "Test AR", weight = 3.4 }, { slot = "secondary", name = "Test pistol", weight = 1.1 } }
end

PDTI.Reset()
Ammo.Reset()
PDTI.SetSessionOnly(false)
ENV.game.unit = nil
Plan.Refresh()
local plan_gun = slot_items()[1]
T("in the menu the slot holds the plan's magazine", plan_gun and plan_gun.data.in_gun == nil and plan_gun.data.plan_slot == "primary")
Ammo.SyncGunSlot(ENV.make_weapon("test_ar", { "wpn_no_part" }, 30))
T("the menu does not mirror any gun", #slot_items() == 1 and slot_items()[1].instance_id == plan_gun.instance_id)

PDTI.LoadProfile()
PDTI.SetSessionOnly(true)
Ammo.OnHeistStart()
local unit = ENV.make_unit()
local rifle = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
unit:set_weapon(rifle)
rifle.clip = 30
Ammo.GameTick({ _state_data = {} }, 0, 0.016, false)
T("the heist: the plan's magazine went into the gun and shows in the slot",
  #slot_items() == 1 and slot_items()[1].data.in_gun == true and slot_items()[1].data.rounds == 30)

-- In the inventory screen: pick it up and drop it in the backpack.
T("the inventory opens in the heist", PDTI.ToggleUI() == true)
local function windows() return ENV.menus[#ENV.menus].children end
local left = windows()[1]
local held_data = slot_items()[1]
local fx, fy = PDTI.FindFreeSpace("backpack", { item_id = held_data.item_id, data = held_data.data }, false)
left:find("cell_gun_primary_0_0"):click()
local right = windows()[2]
right:find(string.format("cell_backpack_%d_%d", fx, fy)):click()
T("taken out in the inventory screen: the gun is empty at once", rifle.clip == 0 and rifle._issr_mag_gone == true, rifle.clip)
right = windows()[2]
local in_pack = nil
for _, it in ipairs(PDTI.GetContainerInfo("backpack").items) do
  if it.item_id == Ammo.MAGAZINE_ITEM and it.data.rounds == 30 and it.data.in_gun == false then in_pack = it end
end
T("the magazine is in the backpack", in_pack ~= nil)
right:find(string.format("cell_backpack_%d_%d", in_pack.x, in_pack.y)):click()
left = windows()[1]
left:find("cell_gun_primary_0_0"):click()
T("put back in the screen: the gun is loaded at once", rifle.clip == 30 and not rifle._issr_mag_gone, rifle.clip)
T("the slot shows it as the gun's", slot_items()[1] and slot_items()[1].data.in_gun == true)
PDTI.SetUIOpen(false)

-- The next heist starts from the plan again.
PDTI.SetSessionOnly(false)
PDTI.LoadProfile()
T("after the heist the plan's magazine is back in the slot", #slot_items() == 1
  and slot_items()[1].data.in_gun == nil and slot_items()[1].data.plan_slot == "primary")

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
