-- 0.19.0: the mouse wheel chooses the magazine the next reload loads, or the
-- magazine in the gun: R then takes it out (the reload animation runs until
-- the magazine leaves the gun, and the gun is left without one).
--   luajit tests/wheel_tests.lua
local script = arg and arg[0] or "tests/wheel_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_wheel") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end
NewRaycastWeaponBase._get_current_damage = function(self, dmg_mul) return (self._damage or 10) * (dmg_mul or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function(self) return self._armor_piercing_chance or 0.25 end
_G.CopDamage = { roll_critical_hit = function(_, attack_data) return false, attack_data.damage end }
-- The game's _get_input returns what the test puts in `raw`.
local raw = {}
PlayerStandard._get_input = function() local r = raw; raw = {}; return r end
-- Like the game: a dropped magazine is a unit in the enemy manager's list.
managers.enemy = managers.enemy or {}
managers.enemy._magazines = {}
local unit_n = 0
local function fake_unit()
  unit_n = unit_n + 1
  local key = "mag" .. unit_n
  return { set_scale = function() end, key = function() return key end, set_slot = function() end,
    position = function() return "floor" end }
end
-- Like the game's EnemyManager:add_magazine (the list is replaced when its
-- limit is reached, as the game does).
managers.enemy.MAX = 50
managers.enemy.add_magazine = function(self, mag, col)
  table.insert(self._magazines, { mag, col })
  if #self._magazines > self.MAX then
    local new = {}
    for i = 2, #self._magazines do new[#new + 1] = self._magazines[i] end
    self._magazines = new
  end
end
local game_add = managers.enemy.add_magazine
-- A magazine-drop mod (or the game's own drop_magazine_object).
local mod_drops = true
NewRaycastWeaponBase.drop_magazine_object = function()
  if mod_drops then managers.enemy:add_magazine(fake_unit(), fake_unit()) end
end
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })
dofile(ROOT .. "lua/ammo_hud.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true)

-- The mouse wheel: which way it turned this frame.
-- The wheel is read from the mouse itself: nil, "up" or "down" this frame.
local wheel = nil
_G.Input = { mouse = function() return { pressed = function(_, id)
  return wheel ~= nil and id == "ids:mouse wheel " .. wheel end } end }
local hints = {}
managers.hud = managers.hud or {}
managers.hud.show_hint = function(_, p) hints[#hints + 1] = p.text end

local current = {}
local function fresh(rounds_list)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  PDTI.SetEquipment("backpack", "large_backpack")
  Ammo.selection = {}
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2 })
  unit:set_weapon(wep)
  current.unit, current.wep = unit, wep
  Ammo.EnsureSupply(wep)
  local info = Ammo.Identify(wep)
  -- The spare magazines as the test wants them, in grid order.
  if rounds_list then
    for _, m in ipairs(Ammo.Magazines(info.key)) do PDTI.RemoveItem(m.container, m.instance_id) end
    for _, r in ipairs(rounds_list) do Ammo.AddMagazineKey(info.key, r, info) end
  end
  wep.clip = 30
  Ammo.SyncTotal(wep)
  Ammo.SyncGunSlot(wep)
  return wep, info
end
local function rounds_of(id)
  for _, m in ipairs(Ammo.Magazines(current.info.key)) do if m.instance_id == id then return m.rounds end end
end

-- The player state: the reload starts like the game's (when the weapon can
-- reload) and lasts 2 s.
local function make_state()
  local st = { _state_data = {}, interrupted = 0, redirects = {}, started = 0 }
  st._interupt_action_reload = function(self)
    self.interrupted = self.interrupted + 1
    self._state_data.reload_expire_t = nil
    if current.wep and NewRaycastWeaponBase.on_reload_stop then end
  end
  st._start_action_reload_enter = function(self, t)
    if NewRaycastWeaponBase.can_reload(current.wep) then
      self.started = self.started + 1
      self._state_data.reload_expire_t = t + 2
    end
  end
  st._is_reloading = function(self) return self._state_data.reload_expire_t ~= nil end
  st._changing_weapon = function() return false end
  st._is_meleeing = function() return false end
  st._interacting = function() return false end
  st._is_throwing_projectile = function() return false end
  st.is_shooting_count = function() return false end
  st.get_animation = function(_, name) return name end
  st._ext_camera = { play_redirect = function(_, id) st.redirects[#st.redirects + 1] = id end }
  return st
end
local function scroll(st, t, up)
  wheel = up and "up" or "down"
  raw = { btn_switch_weapon_press = true }
  local input = PlayerStandard._get_input(st, t or 1, 0.016, false)
  wheel = nil
  return input
end

------------------------------------------------------------ choosing

local wep, info = fresh({ 30, 10, 20 })
current.info = info
local spare = Ammo.Magazines(info.key)
local list = Ammo.ChoiceList(wep)
T("the wheel goes through the gun's magazine and the spare ones", #list == 4 and list[1] == "gun"
  and list[2] == spare[1].instance_id and list[4] == spare[3].instance_id, #list)
T("without a choice the next reload loads the first full one", Ammo.CurrentChoice(wep) == spare[1].instance_id)
local st = make_state()
local input = scroll(st, 1)
T("the wheel is not a weapon switch any more", input.btn_switch_weapon_press == nil)
T("down: the next magazine is chosen", Ammo.CurrentChoice(wep) == spare[2].instance_id)
T("the panel shows the choice", Ammo.panel_until ~= nil and Ammo.panel_until > 1)
scroll(st, 1)
T("down again: the third", Ammo.CurrentChoice(wep) == spare[3].instance_id)
scroll(st, 1)
T("it goes round to the gun's magazine", Ammo.CurrentChoice(wep) == "gun")
scroll(st, 1, true)
T("up goes back", Ammo.CurrentChoice(wep) == spare[3].instance_id)
local rows = Ammo.HudRows()
T("the panel marks the chosen magazine", rows and rows.choice == 3, rows and rows.choice)

-- A reload loads the chosen magazine, not the first one.
scroll(st, 1, true)
T("the 20-round magazine is chosen (the second fullest)", rounds_of(Ammo.CurrentChoice(wep)) == 20)
wep.clip = 5
Ammo.SyncTotal(wep)
NewRaycastWeaponBase.on_reload(wep)
T("the reload loads the chosen magazine", wep.clip == 20, wep.clip)
T("then the choice starts again from the first in the rig", Ammo.selection[info.key] == nil
  and Ammo.CurrentChoice(wep) == Ammo.NextMagazine(wep).instance_id)

-- During a reload the wheel does nothing (and does not switch weapons).
st._state_data.reload_expire_t = 50
local before = Ammo.CurrentChoice(wep)
input = scroll(st, 49)
T("during a reload the wheel is blocked", Ammo.CurrentChoice(wep) == before and input.btn_switch_weapon_press == nil)
st._state_data.reload_expire_t = nil

-- A key bound to "switch weapon" (no wheel turn) still switches weapons.
raw = { btn_switch_weapon_press = true }
before = Ammo.CurrentChoice(wep)
input = PlayerStandard._get_input(st, 3, 0.016, false)
T("a switch-weapon key without the wheel still switches", input.btn_switch_weapon_press == true
  and Ammo.CurrentChoice(wep) == before)

-- The wheel while typing in the chat is left alone.
managers.hud.chat_focus = function() return true end
input = scroll(st, 4)
T("in the chat the wheel does not choose", Ammo.CurrentChoice(wep) == before)
managers.hud.chat_focus = nil

-- The order: the fullest first, the empty ones last.
wep, info = fresh({ 0, 12, 30, 0, 30 })
current.info = info
local order = {}
for _, m in ipairs(Ammo.Magazines(info.key)) do order[#order + 1] = m.rounds end
T("full magazines first, empty ones last", table.concat(order, ",") == "30,30,12,0,0", table.concat(order, ","))
T("the next reload takes a full one", Ammo.NextMagazine(wep).rounds == 30)
st = make_state()

-- The player HUD panel is missing (another HUD mod): the log says why.
do
  local real_script = managers.hud.script
  managers.hud.script = function() return nil end
  Ammo.panel_visible = false
  local ok = pcall(Ammo.SetPanel, true)
  local said = false
  for _, l in ipairs(ENV.logs) do if l:find("player HUD panel is missing", 1, true) then said = true end end
  T("without the HUD panel nothing breaks and the log says why", ok and said and not Ammo.panel_visible)
  managers.hud.script = real_script
end

-- Turned off: the wheel switches weapons as in the game.
Ammo.settings.wheel_choose = false
input = scroll(st, 2)
T("turned off, the wheel switches weapons", input.btn_switch_weapon_press == true)
Ammo.settings.wheel_choose = true

------------------------------------------------- a chosen magazine, a full gun

wep, info = fresh({ 30, 30 })
current.info = info
wep.clip = 30
Ammo.SyncTotal(wep)
st = make_state()
scroll(st, 1)
T("a magazine is chosen while the gun is full", Ammo.selection[info.key] ~= nil)
T("R loads it even into a full gun", Ammo.ChosenReload(st, 2, wep) == true and st.started == 1)

------------------------------------------------------- taking it out

wep, info = fresh({ 30 })
current.info = info
wep.clip = 22
Ammo.SyncTotal(wep)
Ammo.SyncGunSlot(wep)
st = make_state()
scroll(st, 1, true)
T("up from the first magazine: the gun's", Ammo.CurrentChoice(wep) == "gun")
rows = Ammo.HudRows()
T("the panel marks the gun's magazine", rows.choice == "gun")
local mags_before = #Ammo.AllMagazines(info.key)
T("R starts the reload animation", Ammo.ChosenReload(st, 10, wep) == true and st.started == 1
  and wep._pdti_unload == true)
Ammo.GameTick(st, 10, 0.016, false)
Ammo.GameTick(st, 10.4, 0.016, false)
T("before the magazine leaves the gun nothing happens", wep.clip == 22 and wep._pdti_unload == true)
Ammo.GameTick(st, 10.7, 0.016, false)
T("when it leaves the gun the reload stops", st.interrupted == 1 and st._state_data.reload_expire_t == nil
  and st.redirects[#st.redirects] == "idle")
T("the gun has no magazine", wep.clip == 0 and wep._issr_no_mag == true and wep._issr_mag_gone == true, wep.clip)
local out = nil
for _, m in ipairs(Ammo.AllMagazines(info.key)) do if m.rounds == 22 then out = m end end
T("the magazine is in the inventory with its 22 rounds", out ~= nil and out.container ~= "gun_primary"
  and #Ammo.AllMagazines(info.key) == mags_before + 1)
T("the weapon's slot is empty", #PDTI.GetContainerInfo("gun_primary").items == 0)
T("the take-out is over", wep._pdti_unload == nil and Ammo.selection[info.key] == nil)
T("the total is the magazines carried", wep.total == 22 + 30, wep.total)
T("no magazine fell on the floor", next(Ammo.Dropped) == nil)
T("the state stays valid", PDTI.ValidateState() == true)
-- Now a normal reload loads a magazine again.
T("with no magazine in the gun the choice is a magazine", Ammo.CurrentChoice(wep) ~= "gun")
NewRaycastWeaponBase.on_reload(wep)
T("and a reload loads it", wep.clip == 30 or wep.clip == 22, wep.clip)

-- The only magazine is the one in the gun: it can still be taken out (the
-- game would not reload with nothing to load).
wep, info = fresh({})
current.info = info
wep.clip = 25
Ammo.SyncTotal(wep)
st = make_state()
Ammo.selection[info.key] = "gun"
T("with no spare magazine the take-out still starts", Ammo.ChosenReload(st, 15, wep) == true and st.started == 1)
-- The game's own magazine drop (an animation event) is not used: the
-- magazine goes into the inventory, not on the floor.
do
  Ammo.settings.drop_mode = 2
  wep._issr_in_reload = true
  local before_mags = #managers.enemy._magazines
  NewRaycastWeaponBase.drop_magazine_object(wep)
  T("no magazine falls while it is taken out", #managers.enemy._magazines == before_mags,
    #managers.enemy._magazines - before_mags)
  -- A normal reload still drops (drop mode "always").
  local unload = wep._pdti_unload
  wep._pdti_unload = nil
  NewRaycastWeaponBase.drop_magazine_object(wep)
  T("a normal reload still drops it (drop mode always)", #managers.enemy._magazines == before_mags + 1)
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  wep._pdti_unload = unload
  wep._issr_reload_dropped = nil
  wep._issr_drop_count = 0
  Ammo.settings.drop_mode = 1
  wep._issr_in_reload = nil
end
Ammo.GameTick(st, 15, 0.016, false)
Ammo.GameTick(st, 15.7, 0.016, false)
T("and the gun is left empty with the magazine in the inventory", wep.clip == 0 and #Ammo.AllMagazines(info.key) == 1
  and Ammo.AllMagazines(info.key)[1].rounds == 25, wep.clip)

-- A fast reload drops the magazine even when the drop mode keeps
-- magazines with rounds, and the dropped one is not also put back.
wep, info = fresh({ 30 })
current.info = info
wep.clip = 20
Ammo.SyncTotal(wep)
do
  Ammo.settings.drop_mode = 1
  managers.enemy._magazines = {}
  wep._issr_in_reload, wep._pdti_dump = true, true
  NewRaycastWeaponBase.drop_magazine_object(wep)
  T("a fast reload drops a magazine with rounds (drop mode: only empty)", #managers.enemy._magazines == 1
    and wep._issr_drop_count == 1)
  NewRaycastWeaponBase.on_reload(wep)
  T("the dropped magazine is on the floor, not in the inventory", #Ammo.AllMagazines(info.key) == 0
    and wep.clip == 30, #Ammo.AllMagazines(info.key))
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  wep._issr_in_reload, wep._pdti_dump = nil, nil
end

-- Interrupted before the magazine left the gun: nothing changes.
wep, info = fresh({ 30 })
current.info = info
wep.clip = 15
Ammo.SyncTotal(wep)
st = make_state()
Ammo.selection[info.key] = "gun"
Ammo.ChosenReload(st, 20, wep)
Ammo.GameTick(st, 20, 0.016, false)
PlayerStandard._interupt_action_reload(st, 20.2)
Ammo.GameTick(st, 20.3, 0.016, false)
T("an interrupted take-out is forgotten", wep._pdti_unload == nil)
T("and the magazine stays in the gun", wep.clip == 15 and not wep._issr_no_mag, wep.clip)

-- No room anywhere: R does nothing and says why.
wep, info = fresh({})
current.info = info
for _, name in ipairs(Ammo.STORAGE) do
  while PDTI.AddItemAuto(name, "bandage", 1, nil, true) do end
end
st = make_state()
Ammo.selection[info.key] = "gun"
hints = {}
T("with no room the magazine is not taken out", Ammo.ChosenReload(st, 30, wep) == true and st.started == 0
  and wep._pdti_unload == nil)
T("and a hint says why", hints[1] and hints[1]:find("No room") ~= nil, hints[1])

-- A weapon just put into your hands (picked up): its magazine is not in the
-- slot yet. R syncs it and takes it out (0.37.5: it said "no room").
wep, info = fresh({})
current.info = info
Ammo.ClearGunItems(wep)
st = make_state()
Ammo.selection[info.key] = "gun"
hints = {}
T("a magazine not in the slot yet: synced, then taken out", Ammo.ChosenReload(st, 31, wep) == true
  and st.started == 1 and #hints == 0, hints[1])
PlayerStandard._interupt_action_reload(st, 31.1)
Ammo.GameTick(st, 31.2, 0.016, false)
-- Another weapon's magazine put into the slot: the gun's cannot be shown
-- there; the hint says so (not "no room").
wep, info = fresh({})
current.info = info
Ammo.ClearGunItems(wep)
PDTI.AddItem("gun_primary", Ammo.MAGAZINE_ITEM, 0, 0, false, 1,
  Ammo.MagazineData("other_rifle", 5, { slot = "primary", capacity = 30 }))
st = make_state()
Ammo.selection[info.key] = "gun"
hints = {}
T("the slot holds another weapon's magazine: R says to move it out", Ammo.ChosenReload(st, 32, wep) == true
  and st.started == 0 and hints[1] == "The weapon's magazine slot holds another magazine: move it out first", hints[1])

-- Akimbo: both guns' magazines come out.
do
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  PDTI.SetEquipment("backpack", "large_backpack")
  Ammo.selection = {}
  local unit = ENV.make_unit()
  local w = ENV.make_weapon("test_akimbo_smg", { "wpn_no_part" }, 40, { _selection = 2 })
  unit:set_weapon(w)
  current.wep = w
  Ammo.EnsureSupply(w)
  local inf = Ammo.Identify(w)
  w.clip = 40
  Ammo.SyncTotal(w)
  Ammo.SyncGunSlot(w)
  local before_n = #Ammo.AllMagazines(inf.key)
  local s2 = make_state()
  Ammo.selection[inf.key] = "gun"
  T("akimbo: R takes the magazines out", Ammo.ChosenReload(s2, 40, w) == true and w._pdti_unload == true)
  Ammo.GameTick(s2, 40, 0.016, false)
  Ammo.GameTick(s2, 40.7, 0.016, false)
  T("akimbo: both magazines are in the inventory, the guns are empty",
    #Ammo.AllMagazines(inf.key) == before_n + 2 and w._issr_no_mag == true and w.clip == 0,
    #Ammo.AllMagazines(inf.key) - before_n)
  T("akimbo: the state stays valid", PDTI.ValidateState() == true)
end

------------------------------------------------------- the panel order

local order, marked, hidden = Ammo.HudOrder(1, 6, 5, 4)
T("a chosen magazine beyond the boxes takes the last box", order[4] == 6 and marked[4] and hidden == 3,
  table.concat(order, ","))
order, marked = Ammo.HudOrder(2, 3, "gun", 4)
T("akimbo: both guns are marked for the take-out", marked[1] and marked[2] and not marked[3])
order, marked = Ammo.HudOrder(1, 2, 1, 4)
T("a visible choice stays in its place", order[2] == 2 and marked[2] and #order == 3)

-------------------------------------------------- the ISSR leftovers

T("no 'extra magazines' or 'most ammunition' settings", Ammo.settings.max_extra_mags == nil
  and Ammo.settings.ammo_max == nil and Ammo.ExtraMags == nil)
wep, info = fresh({ 30, 30 })
T("the ammunition maximum is the normal ammunition (no 125%)", Ammo.MaxTotal(wep) == Ammo.BaseTotal(wep)
  and Ammo.BaseTotal(wep) == 30 + Ammo.ChamberOf(wep) + Ammo.MagAmount(info, wep._name_id) * 30, Ammo.MaxTotal(wep))
-- A box: the inventory decides, not the maximum.
wep.total = Ammo.MaxTotal(wep)
local picked = RaycastWeaponBase.add_ammo(wep, 1, 40)
T("a box is picked up beyond the old maximum when it fits", picked == true and Ammo.LooseOfKey(info.key) >= 40,
  Ammo.LooseOfKey(info.key))

------------------------------------------- 0.19.2: the mod's own magazine drop

local loaded, spawned

do
  wep, info = fresh({ 30 })
  current.info = info
  wep.clip = 0
  Ammo.SyncTotal(wep)
  -- The gun's magazine part and the game's units.
  tweak_data.weapon.factory = tweak_data.weapon.factory or {}
  tweak_data.weapon.factory.parts = tweak_data.weapon.factory.parts or {}
  tweak_data.weapon.factory.parts.wpn_test_mag = { type = "magazine",
    bullet_objects = { prefix = "g_bullet_", amount = 2 } }
  local hidden = 0
  local part_unit = {
    position = function() return "pos" end, rotation = function() return "rot" end,
    oobb = function() return { center = function() return "center" end } end
  }
  wep._parts = { wpn_test_mag = { name = "ids:mag_unit", unit = part_unit } }
  wep._unit = wep._unit or {}
  loaded = { ["ids:mag_unit"] = true,
    ["ids:units/payday2/weapons/box_collision/box_collision_medium_ar"] = true }
  _G.PackageManager = { has = function(_, _, ids) return loaded[ids] == true end }
  spawned = {}
  _G.World = { spawn_unit = function(_, name, pos)
    local u = fake_unit()
    u.name, u.pos = name, pos
    u.link = function(self, obj, child) self.linked = { obj, child } end
    u.push = function(self) self.pushed = true end
    u.get_object = function() return { set_visibility = function(_, v) if not v then hidden = hidden + 1 end end } end
    spawned[#spawned + 1] = u
    return u
  end }
  managers.enemy._magazines = {}

  Ammo.settings.drop_mode = 1
  wep._issr_in_reload, wep._issr_reload_dropped, wep._issr_drop_count = true, nil, 0
  Ammo.OwnDrop(wep)
  T("without a drop mod the mod drops the magazine itself", #spawned == 2 and #managers.enemy._magazines == 1
    and spawned[1].name == "ids:mag_unit", #spawned)
  T("in the rifle's collision box, linked to it", spawned[2].name
    == "ids:units/payday2/weapons/box_collision/box_collision_medium_ar" and spawned[2].linked
    and spawned[2].linked[2] == spawned[1] and spawned[2].pos == "center")
  T("the empty magazine shows no rounds", hidden == 2, hidden)
  T("it is counted as dropped and can be picked up", wep._issr_drop_count == 1 and next(Ammo.Dropped) ~= nil)
  Ammo.OwnDrop(wep)
  T("only once per reload", #managers.enemy._magazines == 1)

  -- Not loaded: nothing is spawned (an unloaded unit would crash the game).
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  spawned = {}
  loaded["ids:units/payday2/weapons/box_collision/box_collision_medium_ar"] = nil
  wep._issr_reload_dropped, wep._issr_drop_count = nil, 0
  Ammo.OwnDrop(wep)
  T("a unit that is not loaded is never spawned", #spawned == 0 and (wep._issr_drop_count or 0) == 0)
  local said = false
  for _, l in ipairs(ENV.logs) do if l:find("collision box is not loaded", 1, true) then said = true end end
  T("and the log says why", said)

  -- The collision box of a pistol.
  tweak_data.weapon.test_pistol_crew = { pull_magazine_during_reload = "pistol" }
  local real_name = wep._name_id
  wep._name_id = "test_pistol"
  T("a pistol's magazine falls in the pistol box", Ammo.MagazineCollision(wep) == "pistol")
  wep._name_id = real_name
  wep._issr_in_reload = nil
  Ammo.settings.drop_mode = 1
end

-- The game's drop_magazine_object drops nothing for the player's gun (the
-- user's game): the mod drops the magazine itself.
do
  loaded["ids:units/payday2/weapons/box_collision/box_collision_medium_ar"] = true
  mod_drops = false
  spawned = {}
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  Ammo.settings.drop_mode = 2
  wep._issr_in_reload, wep._issr_reload_dropped, wep._issr_drop_count = true, nil, 0
  NewRaycastWeaponBase.drop_magazine_object(wep)
  T("when the existing drop drops nothing, the mod drops it", #spawned == 2 and wep._issr_drop_count == 1
    and next(Ammo.Dropped) ~= nil, #spawned)
  T("and add_magazine is the game's again", managers.enemy.add_magazine == game_add
    and #managers.enemy._magazines == 1)
  mod_drops = true

  -- At the game's limit the oldest is removed and the list replaced: the new
  -- magazine is still recorded.
  managers.enemy.MAX = 1
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  spawned = {}
  wep._issr_reload_dropped, wep._issr_drop_count = nil, 0
  NewRaycastWeaponBase.drop_magazine_object(wep)
  local n = 0
  for _ in pairs(Ammo.Dropped) do n = n + 1 end
  T("at the floor limit the new magazine is still recorded (and not dropped twice)", n == 1
    and wep._issr_drop_count == 1 and #spawned == 0, n)
  managers.enemy.MAX = 50
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  wep._issr_in_reload = nil
  Ammo.settings.drop_mode = 1
end

-- 0.19.4: picking a dropped magazine up (hold the interact key 1 s, no
-- holstering), and the hint goes away when you look away.
do
  wep, info = fresh({})
  current.info = info
  wep.clip = 20
  Ammo.SyncTotal(wep)
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  Ammo.settings.drop_mode = 2
  wep._issr_in_reload, wep._issr_reload_dropped, wep._issr_drop_count = true, nil, 0
  NewRaycastWeaponBase.drop_magazine_object(wep)
  wep._issr_in_reload = nil
  local _, tag = next(Ammo.Dropped)
  T("a magazine lies on the floor", tag ~= nil)

  local shown, removed, bar = 0, 0, 0
  managers.hud.show_interact = function() shown = shown + 1 end
  managers.hud.remove_interact = function() removed = removed + 1 end
  managers.hud.show_interaction_bar = function() bar = bar + 1 end
  managers.hud.set_interaction_bar_width = function() end
  managers.hud.hide_interaction_bar = function() end
  managers.localization.btn_macro = function() return "[F]" end
  current.unit.camera = function() return { position = function() return "eye" end,
    rotation = function() return { y = function() return "fwd" end } end } end
  local aimed = true
  local real_raycast = World.raycast
  World.raycast = function() return aimed and tag and { unit = tag.col, position = "hit" } or nil end

  st = make_state()
  local held = false
  st._controller = { get_input_bool = function(_, name) return name == "interact" and held end }
  Ammo.interact_held = nil
  local mags_before = #Ammo.AllMagazines(info.key)

  Ammo.UpdatePickup(st, 100)
  T("aiming at it shows the hint once", shown == 1 and Ammo.pickup_tag == tag, shown)
  Ammo.UpdatePickup(st, 100.05)
  T("and does not show it again every frame", shown == 1)

  -- The interact key does not also make the game shout at nobody.
  raw = { btn_interact_press = true, btn_interact_state = true }
  local inp = PlayerStandard._get_input(st, 100.1, 0.016, false)
  T("the interact key is the pickup's while a magazine is aimed at", inp.btn_interact_press == nil
    and inp.btn_interact_state == false and Ammo.interact_held == true)
  Ammo.interact_held = nil

  held = true
  Ammo.UpdatePickup(st, 100.2)
  T("holding the key starts the bar without holstering", bar == 1 and st.started == 0
    and st._unequip_weapon_expire_t == nil)
  Ammo.UpdatePickup(st, 100.7)
  T("half a second is not enough", next(Ammo.Dropped) ~= nil)
  Ammo.UpdatePickup(st, 101.3)
  T("after a second the magazine is picked up", next(Ammo.Dropped) == nil
    and #Ammo.AllMagazines(info.key) == mags_before + 1, #Ammo.AllMagazines(info.key))
  T("and the hint is removed", removed >= 1 and Ammo.pickup_tag == nil)
  held = false

  -- Looking away removes the hint.
  wep._issr_in_reload, wep._issr_reload_dropped, wep._issr_drop_count = true, nil, 0
  NewRaycastWeaponBase.drop_magazine_object(wep)
  wep._issr_in_reload = nil
  _, tag = next(Ammo.Dropped)
  Ammo.UpdatePickup(st, 110)
  local removed_before = removed
  aimed = false
  Ammo.UpdatePickup(st, 110.1)
  T("looking away removes the hint", removed == removed_before + 1 and Ammo.pickup_tag == nil)
  Ammo.UpdatePickup(st, 110.2)
  T("only once", removed == removed_before + 1)
  aimed = true
  Ammo.UpdatePickup(st, 110.3)
  T("looking back shows it again", Ammo.pickup_tag == tag and Ammo.pickup_hint == true)

  -- Something the game can interact with comes first.
  st._interacting = function() return true end
  Ammo.UpdatePickup(st, 110.4)
  T("the game's own interaction comes first", Ammo.pickup_tag == nil)
  st._interacting = function() return false end

  World.raycast = real_raycast
  managers.enemy._magazines = {}
  for k in pairs(Ammo.Dropped) do Ammo.Dropped[k] = nil end
  Ammo.settings.drop_mode = 1
end

-- A gun without a magazine reloads faster.
do
  wep, info = fresh({ 30 })
  current.info = info
  local normal = NewRaycastWeaponBase.reload_speed_multiplier(wep)
  wep._issr_no_mag = true
  local empty = NewRaycastWeaponBase.reload_speed_multiplier(wep)
  T("a gun without a magazine reloads faster (the taking out is skipped)",
    math.abs(empty / normal - 1 / 0.7) < 1e-6, empty / normal)
  wep._issr_no_mag = nil
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
