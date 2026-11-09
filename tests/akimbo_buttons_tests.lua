-- 0.17.2: akimbo guns follow the mouse buttons. The left button fires the
-- left gun, the right button fires the right gun instead of aiming. Each gun
-- fires from its own magazine.
--   luajit tests/akimbo_buttons_tests.lua
local script = arg and arg[0] or "tests/akimbo_buttons_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_akimbo_buttons") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Idstring = function(s) return "ids:" .. tostring(s) end

-- The game: a gun's fire takes a round out of the main gun's clip (the
-- second gun's ammo base is its parent) and works out the damage.
local shots = {}
local function base_fire(self)
  local ammo = self._parent_main or self
  if ammo.clip <= 0 then return nil end
  ammo.clip = ammo.clip - 1
  local dmg = NewRaycastWeaponBase._get_current_damage(self, 1)
  shots[#shots + 1] = { gun = self._parent_main and "left" or "right", dmg = dmg,
    through = self._can_shoot_through_enemy }
  return { hit_enemy = true }
end
NewRaycastWeaponBase._get_current_damage = function(self, dmg_mul) return (self._damage or 10) * (dmg_mul or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function(self) return 0.25 end
NewRaycastWeaponBase.fire = base_fire
local vanilla_fired = 0
_G.AkimboWeaponBase = {
  super = NewRaycastWeaponBase,
  -- the game's own: both guns
  fire = function(self, ...)
    vanilla_fired = vanilla_fired + 1
    return base_fire(self, ...)
  end
}
_G.CopDamage = { roll_critical_hit = function(_, a) return false, a.damage end }
-- The player's input, as PlayerStandard:_get_input gives it.
local raw = {}
PlayerStandard._get_input = function() return raw end
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true and Ammo.hooks["AkimboWeaponBase.fire"] ~= nil
  and Ammo.hooks["PlayerStandard._get_input"] ~= nil)

-- Akimbo SMGs: 20 rounds per gun, hollow points on the left, armour
-- piercing on the right.
local mode = "single"
local function fresh()
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_akimbo_smg", { "wpn_no_part" }, 40, { _damage = 10 })
  function wep:fire_mode() return mode end
  wep.dryfired = 0
  function wep:dryfire() self.dryfired = self.dryfired + 1 end
  function wep:selection_index() return 2 end
  local second = { _parent_main = wep, _damage = 10, super = NewRaycastWeaponBase, sounds = 0, anims = 0,
    parent_weapon = { base = function() return wep end } }
  function second:_fire_sound() self.sounds = self.sounds + 1 end
  function second:tweak_data_anim_play() self.anims = self.anims + 1 end
  wep._second_gun = { base = function() return second end }
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  Ammo.SetLoaded(wep, { size = "standard", bullet = "hollow" }, { size = "standard", bullet = "ap" })
  wep._pdti_pair = { 20, 20 }
  wep.clip = 40
  Ammo.ApplyLoaded(wep)
  Ammo.SyncTotal(wep)
  shots = {}
  return wep, second
end

local state = {}
local function player()
  state = { _shooting = false, _state_data = { in_steelsight = true }, stopped = 0 }
  function state:_end_action_steelsight() self._state_data.in_steelsight = false end
  function state:_check_stop_shooting() self._shooting = false; self.stopped = self.stopped + 1 end
  return state
end
local function frame(input)
  raw = input
  return PlayerStandard._get_input(state, 1, 0.016, false)
end
local function trigger(wep) return AkimboWeaponBase.fire(wep) end

----------------------------------------------------------------- the input

local wep = fresh()
player()
local input = frame({ btn_steelsight_press = true, btn_steelsight_state = true })
T("the right button does not aim with akimbo guns", input.btn_steelsight_press == nil
  and input.btn_steelsight_state == false and state._state_data.in_steelsight == false)
T("it is a trigger pull for the game", input.btn_primary_attack_press == true and input.btn_primary_attack_state == true)
T("for the right gun only", wep._pdti_want.right == true and wep._pdti_want.left == false)
input = frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
T("the left button: the left gun only", input.btn_primary_attack_press == true
  and wep._pdti_want.left == true and wep._pdti_want.right == false)
input = frame({ btn_primary_attack_state = true, btn_steelsight_release = true })
T("letting go of one button while the other is held is no release", input.btn_primary_attack_release == nil
  and input.btn_primary_attack_state == true)
input = frame({ btn_primary_attack_release = true })
T("letting go of both is", input.btn_primary_attack_release == true and not input.btn_primary_attack_state)

-- Single fire: holding the left button and pressing the right one starts a
-- new shot.
state._shooting = true
frame({ btn_primary_attack_state = true, btn_steelsight_press = true, btn_steelsight_state = true })
T("single fire: a new press while the other is held is a new shot", state.stopped == 1 and state._shooting == false)
T("held without a new press, a single-fire gun does not fire again", (function()
  frame({ btn_primary_attack_state = true, btn_steelsight_state = true })
  return wep._pdti_want.left == false and wep._pdti_want.right == false
end)())

----------------------------------------------------------------- the shots

wep = fresh()
player()
frame({ btn_steelsight_press = true, btn_steelsight_state = true })
trigger(wep)
local pair = Ammo.AkimboPair(wep)
T("the right button fires the right gun", #shots == 1 and shots[1].gun == "right" and vanilla_fired == 0)
T("from the right gun's magazine", pair[1] == 20 and pair[2] == 19 and wep.clip == 39, pair[1] .. "," .. pair[2])
T("with its armour-piercing bullets", near(shots[1].dmg, 8.5) and shots[1].through == true)

frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
trigger(wep)
pair = Ammo.AkimboPair(wep)
T("the left button fires the left gun", #shots == 2 and shots[2].gun == "left")
T("from the left gun's magazine", pair[1] == 19 and pair[2] == 19, pair[1] .. "," .. pair[2])
T("with its hollow points", near(shots[2].dmg, 13) and shots[2].through == false)

-- Again with the left: its magazine now holds fewer rounds than the right
-- one, and the round still comes out of the left.
frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
trigger(wep)
frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
trigger(wep)
pair = Ammo.AkimboPair(wep)
T("the left gun keeps firing from its own magazine", pair[1] == 17 and pair[2] == 19, pair[1] .. "," .. pair[2])
shots = { shots[1], shots[2] }
wep._pdti_pair = { 19, 19 }
wep.clip = 38

-- Full auto, both buttons held: both guns fire.
mode = "auto"
frame({ btn_primary_attack_state = true, btn_steelsight_state = true })
for _ = 1, 5 do trigger(wep) end
pair = Ammo.AkimboPair(wep)
T("both held on full auto: both guns fire", #shots == 12 and pair[1] == 14 and pair[2] == 14, #shots .. " " .. pair[1] .. "," .. pair[2])
frame({ btn_steelsight_state = true })
for _ = 1, 14 do trigger(wep) end
pair = Ammo.AkimboPair(wep)
T("the right gun alone empties its magazine", pair[1] == 14 and pair[2] == 0, pair[1] .. "," .. pair[2])
local before = #shots
trigger(wep)
T("then its button only clicks", #shots == before and wep.dryfired == 1)
frame({ btn_primary_attack_state = true, btn_steelsight_state = true })
trigger(wep)
T("the left gun still fires", #shots == before + 1 and shots[#shots].gun == "left")
T("the total follows", (function() Ammo.SyncTotal(wep); return wep.clip == 13 end)(), wep.clip)

-- The weapon's slot shows each gun's magazine.
Ammo.SyncGunSlot(wep)
local cells = {}
for _, it in ipairs(PDTI.GetContainerInfo("gun_primary").items) do cells[it.x] = it.data.rounds end
T("the slot shows the left gun on the left, the right gun on the right", cells[0] == 13 and cells[1] == 0,
  tostring(cells[0]) .. " " .. tostring(cells[1]))
mode = "single"

----------------------------------------------- what keeps the game's ways

do
  local w = fresh()
  Ammo.settings.akimbo_buttons = false
  player()
  local i = frame({ btn_steelsight_press = true, btn_steelsight_state = true })
  T("turned off: the right button aims again", i.btn_steelsight_press == true and i.btn_primary_attack_press == nil)
  w._pdti_want = { left = true, right = false }
  local n = vanilla_fired
  trigger(w)
  T("and the game fires the guns", vanilla_fired == n + 1)
  Ammo.settings.akimbo_buttons = true
end

do
  PDTI.Reset()
  Ammo.Reset()
  local unit = ENV.make_unit()
  local rifle = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  unit:set_weapon(rifle)
  player()
  local i = frame({ btn_steelsight_press = true, btn_steelsight_state = true })
  T("a weapon that is not akimbo aims as before", i.btn_steelsight_press == true and i.btn_primary_attack_press == nil
    and state._state_data.in_steelsight == true)
end

---------------------------------------- a black arm cannot hold its gun (0.18.6)

_G.Application = _G.Application or {}
local hint_clock = 100
Application.time = function() return hint_clock end
dofile(ROOT .. "lua/body.lua")
local Body = PDTI.Body
local hints = {}
managers.hud = managers.hud or {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end
local function black(id)
  Body.OnHeistStart()
  Body.state.owner = {}
  Body.state.max = 23
  local spread = Body.EFFECTS.spread_damage
  Body.EFFECTS.spread_damage = 0
  for _, part in ipairs(type(id) == "table" and id or { id }) do Body.Damage(10, part, 23) end
  Body.EFFECTS.spread_damage = spread
end

do
  local w = fresh()
  player()
  black("arm_l")
  frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
  local n = #shots
  trigger(w)
  local pair = Ammo.AkimboPair(w)
  T("left arm black: the left button fires nothing", #shots == n and pair[1] == 20, pair[1])
  T("no empty click either (the gun is not empty)", w.dryfired == 0)
  T("a hint says why", (hints[#hints] or ""):find("left arm is black") ~= nil, hints[#hints])
  frame({ btn_steelsight_press = true, btn_steelsight_state = true })
  trigger(w)
  T("the right gun still fires", #shots == n + 1 and shots[#shots].gun == "right")
  -- Both buttons on full auto: only the right gun.
  mode = "auto"
  frame({ btn_primary_attack_state = true, btn_steelsight_state = true })
  for _ = 1, 4 do trigger(w) end
  pair = Ammo.AkimboPair(w)
  T("both held: only the right gun fires", pair[1] == 20 and pair[2] == 15, pair[1] .. "," .. pair[2])
  mode = "single"
  local before = #hints
  hint_clock = hint_clock + 0.5
  frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
  trigger(w)
  T("the hint is not repeated on every shot", #hints == before)
end

do -- The game's own akimbo fire (the buttons setting off): the arm still counts.
  local w = fresh()
  Ammo.settings.akimbo_buttons = false
  black("arm_r")
  w._pdti_want = nil
  local n, v = #shots, vanilla_fired
  trigger(w)
  T("buttons off, right arm black: only the left gun fires", #shots == n + 1 and shots[#shots].gun == "left"
    and vanilla_fired == v)
  Ammo.settings.akimbo_buttons = true
end

do
  local w = fresh()
  player()
  black({ "arm_l", "arm_r" })
  frame({ btn_primary_attack_press = true, btn_primary_attack_state = true, btn_steelsight_press = true,
    btn_steelsight_state = true })
  local n = #shots
  trigger(w)
  T("both arms black: the akimbo guns cannot fire", #shots == n)
  T("the health window lists it", (function()
    local text = table.concat(Body.EffectLines(), "|")
    return text:find("left akimbo gun cannot fire", 1, true) and text:find("right akimbo gun cannot fire", 1, true)
  end)())
  Body.RestoreAll()
  trigger(w)
  T("healed by a medic bag: they fire again", #shots == n + 2, #shots - n)
end

do
  local w = fresh()
  player()
  black("arm_l")
  Ammo.settings.body_parts = false
  frame({ btn_primary_attack_press = true, btn_primary_attack_state = true })
  local n = #shots
  trigger(w)
  T("body health turned off: a black arm changes nothing", #shots == n + 1)
  Ammo.settings.body_parts = true
  Body.OnHeistStart()
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
