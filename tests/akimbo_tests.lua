-- 0.13.0: akimbo guns. Each gun has its own magazine of half the weapon's
-- capacity; one tap changes both, two taps change one (x2), three taps
-- change both and drop the old ones (x2.5).
--   luajit tests/akimbo_tests.lua
local script = arg and arg[0] or "tests/akimbo_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_akimbo") .. "/")
_G.ModPath = ROOT
ENV.install_game()
ENV.load_mod(ROOT, false)
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })
dofile(ROOT .. "lua/ammo_hud.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true)

-- Akimbo pistols, 34 rounds in both guns together.
local function fresh()
  PDTI.Reset()
  Ammo.Reset()
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_akimbo", { "wpn_no_part" }, 34)
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  wep.clip = 34
  Ammo.SyncTotal(wep)
  return wep, Ammo.Identify(wep).key
end
local function mags(key) return Ammo.Magazines(key) end
local function rounds_list(key)
  local out = {}
  for _, m in ipairs(mags(key)) do out[#out + 1] = m.rounds end
  table.sort(out)
  return table.concat(out, ",")
end
local function pair(wep) local p = Ammo.AkimboPair(wep); return p[1] .. "," .. p[2] end

local function make_state(w)
  local st = { _state_data = {}, interrupted = 0 }
  st._interupt_action_reload = function(self) self.interrupted = self.interrupted + 1; self._state_data.reload_expire_t = nil end
  st.check = function(self, t, input)
    if input and input.btn_reload_press and not self._state_data.reload_expire_t then
      self._state_data.reload_expire_t = t + 2 / NewRaycastWeaponBase.reload_speed_multiplier(w)
      return true
    end
    return false
  end
  return st
end
local function start_reload(wep, t)
  local st = make_state(wep)
  st:check(t, { btn_reload_press = true })
  Ammo.track_wep, Ammo.track_start = wep, t
  return st
end

---------------------------------------------------------------- the basics

-- The game's akimbo weapon has its second gun in _second_gun; the mod used to
-- take that for an underbarrel and skipped akimbo guns altogether.
do
  local w = fresh()
  local second = ENV.make_weapon("test_akimbo", { "wpn_no_part" }, 34)
  w._second_gun = { base = function() return second end }
  T("an akimbo weapon (with _second_gun) is managed", Ammo.SkipWeapon(w) == false, Ammo.SkipReason(w))
  T("its second gun is not", Ammo.SkipWeapon(second) == true, Ammo.SkipReason(second))
  local marked = ENV.make_weapon("test_akimbo", { "wpn_no_part" }, 34, { parent_weapon = {} })
  T("a gun marked with its parent weapon is not either", Ammo.SkipWeapon(marked) == true)
end

local wep, key = fresh()
local info = Ammo.Identify(wep)
T("akimbo is recognised", info.akimbo == true and Ammo.IsAkimbo(wep))
T("a magazine holds half the weapon's capacity", info.capacity == 17, info.capacity)
T("twice as many starting magazines", #mags(key) == 4, #mags(key))
T("they are full 17-round magazines", rounds_list(key) == "17,17,17,17", rounds_list(key))
local m1 = mags(key)[1]
T("each magazine is one gun's (a 17-round pistol magazine: one slot)",
  PDTI.ItemSize(PDTI.FindItem(m1.container, m1.instance_id)) == 1)
T("both guns are loaded", pair(wep) == "17,17", pair(wep))
T("the maximum counts two magazines in the guns", Ammo.MaxTotal(wep) == math.floor((34 + 4 * 17) * 1.25), Ammo.MaxTotal(wep))
T("a single gun of the same type is not akimbo", Ammo.IsAkimbo(ENV.make_weapon("test_pistol", { "wpn_no_part" }, 17)) == false)

wep.clip = 29
T("the guns fire in turn", pair(wep) == "14,15", pair(wep))
wep.clip = 3
T("down to the last rounds", pair(wep) == "1,2", pair(wep))
wep._pdti_pair = { 0, 5 }
wep.clip = 4
T("an empty gun: the other one keeps firing", pair(wep) == "0,4", pair(wep))

----------------------------------------------------------- one tap: both

wep, key = fresh()
wep._pdti_pair = { 6, 4 }
wep.clip = 10
Ammo.SyncTotal(wep)
T("a normal reload has the game's speed", near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1))
NewRaycastWeaponBase.on_reload(wep)
T("one tap: both guns get a full magazine", wep.clip == 34 and pair(wep) == "17,17", pair(wep))
T("both old magazines go back with their rounds", rounds_list(key) == "4,6,17,17", rounds_list(key))
T("the state stays valid", PDTI.ValidateState() == true)

------------------------------------------------------- two taps: one mag

wep, key = fresh()
wep._pdti_pair = { 12, 3 }
wep.clip = 15
Ammo.SyncTotal(wep)
local st = start_reload(wep, 10)
T("two taps in time: one magazine", Ammo.TryFastReload(st, 10.3, wep, st.check) == true)
T("the mode is one magazine", wep._pdti_akimbo_mode == "one")
T("200% speed: it ends at half the time from the first tap", near(st._state_data.reload_expire_t, 11), st._state_data.reload_expire_t)
NewRaycastWeaponBase.on_reload(wep)
T("only the emptier magazine was changed", pair(wep) == "12,17", pair(wep))
T("the clip is both magazines", wep.clip == 29, wep.clip)
T("the emptier one went back", rounds_list(key) == "3,17,17,17", rounds_list(key))
T("the taps are forgotten", wep._pdti_akimbo_mode == nil and wep._pdti_taps == nil and wep._pdti_fast_mul == nil)

----------------------------------------------------- three taps: dump both

wep, key = fresh()
wep._pdti_pair = { 5, 2 }
wep.clip = 7
Ammo.SyncTotal(wep)
local loose_before = Ammo.LooseOfKey(key)
st = start_reload(wep, 10)
T("second tap", Ammo.TryFastReload(st, 10.2, wep, st.check) == true)
T("third tap within the window of the second", Ammo.TryFastReload(st, 10.6, wep, st.check) == true)
T("the mode is drop both", wep._pdti_akimbo_mode == "dump")
T("250% speed from the first tap", near(st._state_data.reload_expire_t, 10 + 2 / 2.5), st._state_data.reload_expire_t)
T("a fourth tap does nothing", Ammo.TryFastReload(st, 10.7, wep, st.check) == false)
NewRaycastWeaponBase.on_reload(wep)
T("both guns get a full magazine", pair(wep) == "17,17" and wep.clip == 34, pair(wep))
T("both old magazines are gone", rounds_list(key) == "17,17", rounds_list(key))
T("their rounds are gone too", Ammo.LooseOfKey(key) == loose_before)

-- The third tap too late: the one-magazine reload goes on.
wep, key = fresh()
wep._pdti_pair = { 5, 2 }
wep.clip = 7
st = start_reload(wep, 10)
Ammo.TryFastReload(st, 10.2, wep, st.check)
T("a third tap after the window does nothing", Ammo.TryFastReload(st, 10.8, wep, st.check) == false)
T("the one-magazine reload goes on", wep._pdti_akimbo_mode == "one")

-- A one-gun weapon still has only the double tap.
do
  PDTI.Reset(); Ammo.Reset()
  local unit = ENV.make_unit()
  local rifle = ENV.make_weapon("test_rifle")
  unit:set_weapon(rifle)
  Ammo.EnsureSupply(rifle)
  rifle.clip = 12
  local rs = start_reload(rifle, 10)
  T("one gun: the second tap is the fast reload", Ammo.TryFastReload(rs, 10.2, rifle, rs.check) == true and rifle._pdti_dump == true)
  T("one gun: no third tap", Ammo.TryFastReload(rs, 10.4, rifle, rs.check) == false)
  T("one gun: still 150%", near(rs._state_data.reload_expire_t, 10 + 2 / 1.5))
end

-- Interrupted: everything is forgotten.
wep, key = fresh()
wep._pdti_pair = { 5, 2 }
wep.clip = 7
st = start_reload(wep, 20)
Ammo.TryFastReload(st, 20.2, wep, st.check)
Ammo.TryFastReload(st, 20.4, wep, st.check)
PlayerStandard._interupt_action_reload(st, 21)
T("an interrupted akimbo reload is forgotten", wep._pdti_akimbo_mode == nil and wep._pdti_taps == nil)
NewRaycastWeaponBase.on_reload(wep)
T("so the next reload is a normal one (both kept)", rounds_list(key) == "2,5,17,17", rounds_list(key))

-------------------------------------------------- only one magazine left

wep, key = fresh()
local list = mags(key)
for i = 2, #list do PDTI.RemoveItem(list[i].container, list[i].instance_id) end
wep._pdti_pair = { 8, 2 }
wep.clip = 10
Ammo.SyncTotal(wep)
NewRaycastWeaponBase.on_reload(wep)
T("one magazine left: the emptier gun gets it", pair(wep) == "8,17", pair(wep))
T("and its old magazine goes back", rounds_list(key) == "2", rounds_list(key))

-- No free place: the old magazines go where the new ones were.
wep, key = fresh()
for _, name in ipairs(PDTI.TO_HAND) do
  while PDTI.AddItemAuto(name, "bandage", 1, nil, true) do end
end
wep._pdti_pair = { 3, 1 }
wep.clip = 4
Ammo.SyncTotal(wep)
T("everything to hand is full", Ammo.HasMagazineRoom(17, "pistol", true) == false)
NewRaycastWeaponBase.on_reload(wep)
T("no free place: both old magazines are kept", rounds_list(key) == "1,3,17,17", rounds_list(key))
T("in the rig or pockets, not the backpack", #PDTI.GetContainer("backpack").items == 0)

--------------------------------------------------------- packing and HUD

wep, key = fresh()
for _, m in ipairs(mags(key)) do Ammo.SetMagazineRounds(m.container, m.instance_id, 10) end
Ammo.AddLooseKey(key, 20, Ammo.Identify(wep))
local left = Ammo.FillMagazines(wep, 20)
T("loose rounds fill akimbo magazines up to 17", rounds_list(key) == "10,16,17,17", rounds_list(key))
T("nothing left loose", left == 0, left)

wep._pdti_pair = { 9, 11 }
wep.clip = 20
local rows = Ammo.HudRows()
T("the HUD shows a box for each gun", rows and rows.akimbo and rows.akimbo[1].rounds == 9 and rows.akimbo[2].rounds == 11)
T("with the magazine capacity", rows and rows.capacity == 17)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
