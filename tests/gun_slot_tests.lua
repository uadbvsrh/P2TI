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
T("in the menu the slot holds the plan's magazine (the weapon's)", plan_gun and plan_gun.data.in_gun == nil
  and plan_gun.data.plan_weapon == "test_ar")
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
  and slot_items()[1].data.in_gun == nil and slot_items()[1].data.plan_weapon == "test_ar")

----------------------------- a weapon swapped in the heist (0.37.5)
-- A weapon put into your hands in the heist (picked up, or out of the
-- backpack) has its own magazine in the slot: the one of the gun that left
-- your hands went with that gun.

do
  local old = fresh("test_ar", 30)
  sync(old)
  local old_id = slot_items()[1].instance_id
  local new = ENV.make_weapon("test_rifle", { "wpn_mag_test" }, 30, { _selection = 2 })
  current.unit:set_weapon(new)
  Ammo.EnsureSupply(new)
  new.clip = 30
  Ammo.SyncTotal(new)
  sync(new)
  local ni = Ammo.Identify(new)
  local it = slot_items()[1]
  T("another weapon in your hands: its own magazine in the slot, the old gun's gone with it", #slot_items() == 1
    and it.instance_id ~= old_id and it.data.queue_key == ni.key and it.data.in_gun == true, #slot_items())
  T("  its magazine can be taken out (no false 'no room')", Ammo.UnloadPlaces(new) ~= nil)
  local again = ENV.make_weapon("test_rifle", { "wpn_mag_test" }, 30, { _selection = 2 })
  current.unit:set_weapon(again)
  again.clip = 12
  Ammo.SyncTotal(again)
  sync(again)
  T("  the same model again (another gun): its own magazine, with its own rounds", #slot_items() == 1
    and slot_items()[1].instance_id ~= it.instance_id and slot_items()[1].data.rounds == 12)
  sync(again)
  T("  the gun in hand keeps its magazine", #slot_items() == 1 and Ammo.UnloadPlaces(again) ~= nil)
  local pump = ENV.make_weapon("test_pump", { "wpn_no_part" }, 6, { _selection = 2, _use_shotgun_reload = true })
  current.unit:set_weapon(pump)
  sync(pump)
  T("  a shotgun loaded shell by shell: no magazine in the slot", #slot_items() == 0)
  -- A magazine taken out of the gun on purpose is yours (not in the gun).
  local w2 = fresh("test_ar", 30)
  sync(w2)
  local gid = slot_items()[1].instance_id
  T("Ammo.DropGunLeftovers keeps the gun's own", Ammo.DropGunLeftovers("gun_primary", w2._pdti_gun_items) == 0
    and #slot_items() == 1)
  T("  and takes a gone gun's", Ammo.DropGunLeftovers("gun_primary") == 1 and #slot_items() == 0
    and PDTI.FindItem("gun_primary", gid) == nil)
  w2._pdti_unarmed = true -- the armory's stand-in when you hold no weapon
  T("the stand-in is not a gun to the ammunition system", Ammo.Identify(w2) == nil)
  w2._pdti_unarmed = nil
  T("  (the same weapon is one otherwise)", Ammo.Identify(w2) ~= nil)
end

------------------------ the gun's magazine goes with the weapon (0.37.7)
-- A weapon leaving your hands keeps what is in its gun (its item holds it);
-- put back, it has the same magazine, not a free full one.

do
  local w = fresh("test_ar", 30)
  sync(w)
  w.clip = 22
  sync(w)
  local state = Ammo.GunState(w)
  T("a weapon leaving your hands: its gun is read (one magazine, its rounds, its weight)", state and state.gun_set == 1
    and state.gun_n == 1 and state.gun1_rounds == 22 and state.gun1_size == "standard" and state.gun_weight > 0
    and state.gun_in == 0, state and state.gun1_rounds)
  local carried = Ammo.MagazineRounds(Ammo.Identify(w).key)
  local back = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
  current.unit:set_weapon(back)
  back.clip = 30 -- the game spawns it full
  T("put back into your hands: the same magazine, not a full one", Ammo.LoadGun(back, state) and back.clip == 22
    and #slot_items() == 1 and slot_items()[1].data.rounds == 22 and slot_items()[1].data.in_gun == true, back.clip)
  sync(back)
  T("  the slot keeps it as the gun's", #slot_items() == 1 and slot_items()[1].data.rounds == 22)
  T("  no free rounds: the total is what you carry", back.total == 22 + carried, back.total .. " vs " .. (22 + carried))
  state.gun1_size, state.gun1_bullet, state.gun1_load, state.gun1_rounds = "extended", "ap", "ap:40", 40
  local spec = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
  current.unit:set_weapon(spec)
  spec.clip = 30
  T("  its magazine's size and bullets come back too", Ammo.LoadGun(spec, state) and spec.clip == 40
    and slot_items()[1].data.size == "extended" and slot_items()[1].data.bullet == "ap", spec.clip)
  local e = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
  current.unit:set_weapon(e)
  e.clip = 30
  T("a weapon whose magazine you took out comes back without one", Ammo.LoadGun(e, Ammo.GunFields({}))
    and e.clip == 0 and e._issr_mag_gone == true and #slot_items() == 0, e.clip)
  local f = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
  current.unit:set_weapon(f)
  f.clip = 30
  T("a weapon never settled keeps the game's full magazine", Ammo.LoadGun(f, { uid = 5 }) == false and f.clip == 30)
  T("  one whose magazine is in the gun already is not loaded again",
    Ammo.LoadGun(f, { gun_set = 1, gun_in = 1, gun_n = 0 }) == false and f.clip == 30)
  local chambered = Ammo.GunFields({ { rounds = 10, size = "standard", bullet = "standard", load = "standard:10" } })
  chambered.gun_chamber = 1
  f.get_chamber = function() return 1 end
  T("  the round in the chamber stays in it", Ammo.LoadGun(f, chambered) and f.clip == 11, f.clip)
  local pump = fresh("test_pump", 6)
  pump._use_shotgun_reload = true
  pump.clip = 4
  local ps = Ammo.GunState(pump)
  T("a shotgun loaded shell by shell: its shells are read", ps and ps.gun_clip == 4 and ps.gun_n == 0, ps and ps.gun_clip)
  local pump2 = ENV.make_weapon("test_pump", { "wpn_no_part" }, 6, { _selection = 2, _use_shotgun_reload = true })
  current.unit:set_weapon(pump2)
  pump2.clip = 6
  T("  and come back with it", Ammo.LoadGun(pump2, ps) and pump2.clip == 4, pump2.clip)
  local ak = fresh("test_akimbo_smg", 40)
  sync(ak)
  ak._pdti_pair = { 20, 7 }
  ak.clip = 27
  sync(ak)
  local as = Ammo.GunState(ak)
  T("akimbo: both guns' magazines are read", as and as.gun_n == 2 and as.gun1_rounds == 20 and as.gun2_rounds == 7,
    as and (tostring(as.gun1_rounds) .. "/" .. tostring(as.gun2_rounds)))
  local ak2 = ENV.make_weapon("test_akimbo_smg", { "wpn_no_part" }, 40, { _selection = 2 })
  current.unit:set_weapon(ak2)
  ak2.clip = 40
  T("  and both come back", Ammo.LoadGun(ak2, as) and ak2.clip == 27 and #slot_items() == 2, ak2.clip)
  local one = Ammo.GunFields({ { rounds = 15, size = "standard", bullet = "standard", load = "standard:15" } })
  local ak3 = ENV.make_weapon("test_akimbo_smg", { "wpn_no_part" }, 40, { _selection = 2 })
  current.unit:set_weapon(ak3)
  ak3.clip = 40
  T("  one gun emptied: only the other has a magazine", Ammo.LoadGun(ak3, one) and ak3.clip == 15
    and #slot_items() == 1 and ak3._pdti_gun_empty and ak3._pdti_gun_empty[2] == true, ak3.clip)
  T("the stored magazines: at most two (one per gun)", #Ammo.StoredMagazines({ gun_n = 3 }) == 2)
  local m = { rounds = 30, capacity = 30, mag_class = "assault_rifle" }
  local w1, w2 = Ammo.GunFields({ m }).gun_weight, Ammo.GunFields({ m, m }).gun_weight
  T("  their weight: all of them", w1 > 0 and math.abs(w2 - 2 * w1) < 1e-9, w2 .. " vs " .. w1)
end

do
  -- What is read from a gun: only magazines it has, and the round in the chamber.
  local e = fresh("test_ar", 30)
  sync(e)
  Ammo.LoadGun(e, Ammo.GunFields({}))
  T("a gun without a magazine is read as one without", Ammo.GunState(e).gun_n == 0)
  local real_wis = Ammo.WeaponInSlot
  Ammo.WeaponInSlot = function(slot) return slot == "primary" and e or nil end
  local okf, whyf = PDTI.AddItem("gun_primary", Ammo.MAGAZINE_ITEM, 0, 0, false, 1,
    { queue_key = "other|mag", slot = "primary", rounds = 5, capacity = 30 })
  T("in a heist only a magazine of the gun in that slot goes into its box", okf == false
    and tostring(whyf):find("this weapon", 1, true) ~= nil, whyf)
  Ammo.WeaponInSlot = real_wis
  e.get_chamber = function() return 1 end
  Ammo.LoadGun(e, Ammo.GunFields({ { rounds = 10, size = "standard", bullet = "standard", load = "standard:10" } }))
  e.clip = 11
  local st2 = Ammo.GunState(e)
  T("  a chambered round: 1 in the chamber, 10 in the magazine", st2.gun_chamber == 1 and st2.gun1_rounds == 10,
    tostring(st2.gun_chamber) .. "/" .. tostring(st2.gun1_rounds))
  local pump = fresh("test_pump", 6)
  pump._use_shotgun_reload = true
  local pinfo = Ammo.Identify(pump)
  local ps = Ammo.GunState(pump)
  T("a shotgun's loaded shell is read", ps and (not pinfo.typed or (ps.gun1_bullet ~= ""
    and ps.gun1_bullet == Ammo.CurrentBullet(pump))), ps and ps.gun1_bullet)
  T("heist ammunition is labelled by its weapon (round by round too)",
    Ammo.LooseData(pinfo.key, pinfo).wtag == Ammo.WeaponTag("test_pump") and Ammo.WeaponTag("test_pump") ~= nil)
  local rifle = ENV.make_weapon("test_rifle", { "wpn_mag_test" }, 30, { _selection = 2 })
  local rinfo = Ammo.Identify(rifle)
  T("  a magazine of the game's sizes too", rinfo and Ammo.MagazineData(rinfo.key, 10, rinfo).wtag == Ammo.WeaponTag("test_rifle"))
  tweak_data.weapon.tag_one = { name_id = "AMCAR Rifle" }
  tweak_data.weapon.tag_two = { name_id = "Akimbo Chimano 88 Pistols" }
  local real_loc = managers.localization
  managers.localization = { text = function(_, id) return id end }
  T("a weapon's short name: its first word, akimbo as 2x", Ammo.WeaponTag("tag_one") == "AMCAR"
    and Ammo.WeaponTag("tag_two") == "2xChima", Ammo.WeaponTag("tag_two"))
  managers.localization = real_loc
end

do
  -- Ammunition chosen in the menu: a weapon put into your hands takes its
  -- kind's first, then keeps its own magazine.
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  PDTI.SetAmmoPlanned(true)
  local unit = ENV.make_unit()
  local w = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
  unit:set_weapon(w)
  current.unit = unit
  w.clip = 30
  T("planned ammunition: a weapon put into your hands keeps its own magazine",
    Ammo.LoadGun(w, Ammo.GunFields({ { rounds = 12, size = "standard", bullet = "standard", load = "standard:12" } }))
    and w.clip == 12, w.clip)
  Ammo.EnsureSupply(w)
  T("  (its kind's ammunition was taken first: nothing changes after)", w.clip == 12, w.clip)
  -- Your weapon in hand at the start of a heist, its magazine box empty:
  -- what the weapon item holds.
  local real_inuse = PDTI.Armory.InUse
  PDTI.Armory.InUse = function() return true end
  local function start(fields)
    PDTI.Reset()
    Ammo.Reset()
    Ammo.OnHeistStart()
    PDTI.SetSessionOnly(true)
    PDTI.SetAmmoPlanned(true)
    local data = { uid = 7, weapon_id = "test_ar", category = "primaries", picked = true, w = 4, h = 2, weight = 3 }
    for k, v in pairs(fields) do data[k] = v end
    PDTI.AddItem("hand_primary", "weapon", 0, 0, false, 1, data)
    local g = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
    unit:set_weapon(g)
    g.clip = 30
    Ammo.EnsureSupply(g)
    return g
  end
  local emptied = start(Ammo.GunFields({}))
  T("your weapon emptied in the menu starts the heist without a magazine", emptied.clip == 0
    and emptied._issr_mag_gone == true, emptied.clip)
  local kept = start(Ammo.GunFields({ { rounds = 12, size = "standard", bullet = "standard", load = "standard:12" } }))
  T("  one holding its magazine starts with that one", kept.clip == 12, kept.clip)
  PDTI.Armory.InUse = real_inuse
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
