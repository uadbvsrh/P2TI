-- 0.11.1: tapping R twice, reloading when there is no free place, and the
-- colours of the slots.
--   luajit tests/reload_tests.lua
local script = arg and arg[0] or "tests/reload_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_reload") .. "/")
_G.ModPath = ROOT
ENV.install_game()
ENV.load_mod(ROOT, false)
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true)
T("the reload speed is hooked", Ammo.hooks["NewRaycastWeaponBase.reload_speed_multiplier"] ~= nil)
local speed = function(wep) return NewRaycastWeaponBase.reload_speed_multiplier(wep) end

local function fresh()
  PDTI.Reset()
  Ammo.Reset()
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_rifle")
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  return wep, Ammo.Identify(wep).key
end
local function mags(key) return Ammo.Magazines(key) end
-- Fills every free place to hand with bandages.
local function fill_to_hand()
  for _, name in ipairs(PDTI.TO_HAND) do
    while PDTI.AddItemAuto(name, "bandage", 1, nil, true) do end
  end
end
local function loose_total(key) return Ammo.LooseOfKey(key) end

------------------------------------------------------ a free place

local wep, key = fresh()
wep.clip = 12
Ammo.SyncTotal(wep)
T("with a free place the reload has the game's speed", near(speed(wep), 1), speed(wep))
NewRaycastWeaponBase.on_reload(wep)
T("the old magazine goes back into the inventory", #mags(key) == 3, #mags(key))
T("and a full one is loaded", wep.clip == 30, wep.clip)

------------------------------------------------- no free place: swap

wep, key = fresh()
fill_to_hand()
wep.clip = 12
Ammo.SyncTotal(wep)
T("everything to hand is full", Ammo.HasMagazineRoom(30) == false)
T("the reload must swap", Ammo.MustSwap(wep) == true)
T("it lasts 25% longer", near(speed(wep), 1 / 1.25), speed(wep))
local next_mag = Ammo.NextMagazine(wep)
local spot = PDTI.FindItem(next_mag.container, next_mag.instance_id)
local sx, sy, sc = spot.x, spot.y, next_mag.container
NewRaycastWeaponBase.on_reload(wep)
T("a full magazine is loaded", wep.clip == 30, wep.clip)
T("the old magazine is kept", #mags(key) == 3, #mags(key))
local at = nil
for _, m in ipairs(mags(key)) do
  local item = PDTI.FindItem(m.container, m.instance_id)
  if m.container == sc and item.x == sx and item.y == sy then at = m end
end
T("it lies where the new one was, with its rounds", at and at.rounds == 12, at and at.rounds)
T("nothing went to the backpack", #PDTI.GetContainer("backpack").items == 0)
T("the state stays valid", PDTI.ValidateState() == true)

------------------------------------------------------- tapping twice

-- The player state: _check_action_reload starts a reload of 2 s at the
-- weapon's reload speed, like the game.
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

wep, key = fresh()
wep.clip = 12
Ammo.SyncTotal(wep)
local loose_before = loose_total(key)
local st = make_state(wep)
st:check(10, { btn_reload_press = true })
Ammo.track_wep, Ammo.track_start = wep, 10
T("a second tap after the window does nothing", Ammo.TryFastReload(st, 10.8, wep, st.check) == false)
T("a second tap in time: fast reload", Ammo.TryFastReload(st, 10.3, wep, st.check) == true)
T("the first reload was stopped and a new one started", st.interrupted == 1 and st._state_data.reload_expire_t ~= nil)
T("it ends 50% sooner than the first would have (2 s / 1.5 from the first tap)",
  near(st._state_data.reload_expire_t, 10 + 2 / 1.5), st._state_data.reload_expire_t)
T("a third tap does not stack", Ammo.TryFastReload(st, 10.4, wep, st.check) == false)
NewRaycastWeaponBase.on_reload(wep)
T("a full magazine is loaded", wep.clip == 30, wep.clip)
T("the old magazine is gone", #mags(key) == 2, #mags(key))
T("its rounds are gone too (not loose)", loose_total(key) == loose_before, loose_total(key))
T("the next reload is normal again", near(speed(wep), 1) and wep._pdti_dump == nil)

-- Interrupted (weapon switch): the fast reload is forgotten.
wep, key = fresh()
wep.clip = 12
st = make_state(wep)
st:check(20, { btn_reload_press = true })
Ammo.track_wep, Ammo.track_start = wep, 20
Ammo.TryFastReload(st, 20.2, wep, st.check)
PlayerStandard._interupt_action_reload(st, 21)
T("an interrupted fast reload is forgotten", wep._pdti_dump == nil and wep._pdti_fast_mul == nil)
NewRaycastWeaponBase.on_reload(wep)
T("so the magazine is kept", #mags(key) == 3, #mags(key))

-- Without a magazine to load there is no fast reload.
wep, key = fresh()
for _, m in ipairs(mags(key)) do PDTI.RemoveItem(m.container, m.instance_id) end
st = make_state(wep)
st._state_data.reload_expire_t = 32
Ammo.track_wep, Ammo.track_start = wep, 30
T("no magazine: no fast reload", Ammo.TryFastReload(st, 30.2, wep, st.check) == false)

-------------------------------------------------------- slot colours

do
  ENV.install_menuui(false)
  dofile(ROOT .. "lua/ui_beardlib.lua")
  PDTI.Reset()
  PDTI.SetEquipment("rig", "medical_rig")
  PDTI.AddItemAuto("rig", "first_aid_kit", 1, nil, true)
  PDTI.SetUIOpen(true)
  local all = {}
  for _, w in ipairs(ENV.menus[#ENV.menus].children) do for _, c in ipairs(w.children) do all[c.params.name or ""] = c end end
  local C = PDTI.SLOT_KIND_COLORS
  local function bg(name) local c = all[name]; return c and c.params.background_color end
  local function same(col, want) return col and near(col[1], want[1]) and near(col[2], want[2]) and near(col[3], want[3]) end
  T("the medical part is green", same(bg("cell_rig_7_1"), C.medical), bg("cell_rig_7_1") and table.concat(bg("cell_rig_7_1"), ","))
  T("the ammo pouches are amber", same(bg("cell_rig_2_0_0"), C.ammo) and same(bg("cell_rig_3_0_2"), C.ammo))
  T("the pockets have their colour", same(bg("cell_pockets_1_1"), C.pockets))
  T("the backpack has its colour", same(bg("cell_backpack_0_0"), C.backpack))
  T("a slot with an item shows the item", not same(bg("cell_rig_0_0"), C.medical))
  PDTI.SetUIOpen(false)
  PDTI.SetEquipment("rig", "assault_rig")
  PDTI.SetUIOpen(true)
  all = {}
  for _, w in ipairs(ENV.menus[#ENV.menus].children) do for _, c in ipairs(w.children) do all[c.params.name or ""] = c end end
  T("assault rig: ammunition amber, ammo bags blue", same(bg("cell_rig_0_0"), C.ammo) and same(bg("cell_rig_2_0_0"), C.ammo_bags))
  T("every kind has its own colour", (function()
    local seen = {}
    for _, col in pairs(C) do
      local k = table.concat(col, ",")
      if seen[k] then return false end
      seen[k] = true
    end
    return true
  end)())
  PDTI.SetUIOpen(false)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
