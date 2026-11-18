-- 0.19.5: loose rounds dragged onto a magazine in the inventory screen are
-- loaded into it: round by round in a heist (until full, the stack runs out,
-- or an action key), all at once in the menu.
--   luajit tests/load_tests.lua
local script = arg and arg[0] or "tests/load_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_load") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, true)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end
-- The game's _get_input returns what the test puts in `raw`.
local raw = {}
PlayerStandard._get_input = function() local r = raw; raw = {}; return r end
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true)
local hints = {}
managers.hud = managers.hud or {}
managers.hud.show_hint = function(_, p) hints[#hints + 1] = p.text end
Ammo.settings.round_interval = 0.25

local function fresh(in_heist)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.StopLoad()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(in_heist)
  PDTI.SetEquipment("backpack", "large_backpack")
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  local info = Ammo.Identify(wep)
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do PDTI.RemoveItem(m.container, m.instance_id) end
  for _, s in ipairs(Ammo.LooseStacks(info.key)) do PDTI.RemoveItem(s.container, s.instance_id) end
  return wep, info
end

local function find(pred)
  local f = PDTI.FindItems(pred)
  return f[1] and f[1].container, f[1] and f[1].item
end
local function mag_of(id)
  local _, item = find(function(_, it) return it.instance_id == id end)
  return item
end
local function loose_left(key)
  return Ammo.LooseOfKey(key)
end
-- One magazine with `rounds` (and its bullets), one loose stack.
local function setup(in_heist, rounds, mag_bullet, loose, loose_bullet)
  local wep, info = fresh(in_heist)
  Ammo.AddMagazineKey(info.key, rounds, info, { "pockets" }, { size = "standard", bullet = mag_bullet or "standard" })
  Ammo.AddLooseKey(info.key, loose, info, loose_bullet)
  local mc, mag = find(function(_, it) return it.item_id == Ammo.MAGAZINE_ITEM end)
  local lc, stack = find(function(_, it) return it.item_id == Ammo.LOOSE_ITEM end)
  return wep, info, { c = mc, item = mag }, { c = lc, item = stack }
end
local function drag(from, to)
  local ok = PDTI.UIDragStart(from.c, from.item.x, from.item.y)
  if not ok then return false, "no drag" end
  return PDTI.UIDragDrop({ container = to.c, x = to.item.x, y = to.item.y })
end

--------------------------------------------------------------- in a heist

local wep, info, mag, stack = setup(true, 10, "standard", 30, "ap")
PDTI.UIDragStart(stack.c, stack.item.x, stack.item.y)
local p = PDTI.UIDragPreview(mag.c, mag.item.x, mag.item.y)
T("over a magazine the rounds fit, the magazine lights up green", p and p.valid and p.load
  and p.x == mag.item.x and p.y == mag.item.y)
PDTI.UIResetInteraction()

local ok = drag(stack, mag)
T("dropping loose rounds on a magazine starts loading", ok == true and Ammo.LoadActive())
T("the stack is not moved onto the magazine", mag_of(mag.item.instance_id).data.rounds == 10
  and loose_left(info.key) == 30)
T("a hint says how to stop", hints[#hints] and hints[#hints]:find("stops") ~= nil, hints[#hints])

Ammo.LoadTick(0.25)
T("one round per round time", mag_of(mag.item.instance_id).data.rounds == 11 and loose_left(info.key) == 29)
Ammo.LoadTick(0.5)
T("two more", mag_of(mag.item.instance_id).data.rounds == 13 and loose_left(info.key) == 27)
local load = Ammo.LoadOf(mag_of(mag.item.instance_id).data)
T("the new rounds go on top with their own bullets", load[1][1] == "ap" and load[1][2] == 3
  and load[2][1] == "standard" and load[2][2] == 10, Ammo.LoadString(load))

-- Moving does not stop it; shooting does.
raw = { btn_run_press = true, btn_jump_press = true, btn_duck_press = true }
PlayerStandard._get_input({}, 1, 0.016, false)
T("moving, jumping and crouching do not stop it", Ammo.LoadActive())
raw = { btn_primary_attack_press = true }
PlayerStandard._get_input({}, 1, 0.016, false)
T("shooting stops it", not Ammo.LoadActive())
Ammo.LoadTick(1)
T("and no more rounds go in", mag_of(mag.item.instance_id).data.rounds == 13)

for _, key in ipairs({ "btn_reload_press", "btn_steelsight_press", "btn_melee_press", "btn_interact_press",
  "btn_switch_weapon_press", "btn_throw_grenade_press" }) do
  Ammo.StartLoad(stack.item.instance_id, mag.item.instance_id)
  raw = { [key] = true }
  PlayerStandard._get_input({}, 1, 0.016, false)
  T(key .. " stops it", not Ammo.LoadActive())
end

-- Until the magazine is full.
Ammo.StartLoad(stack.item.instance_id, mag.item.instance_id)
Ammo.LoadTick(0.25 * 40)
T("it stops when the magazine is full", not Ammo.LoadActive() and mag_of(mag.item.instance_id).data.rounds == 30
  and loose_left(info.key) == 10, mag_of(mag.item.instance_id).data.rounds)
T("a full magazine cannot be loaded", PDTI._UILoadTarget ~= nil and select(2, Ammo.StartLoad(stack.item.instance_id,
  mag.item.instance_id)) == "the magazine is full")

-- Until the stack runs out.
wep, info, mag, stack = setup(true, 0, "standard", 7)
drag(stack, mag)
Ammo.LoadTick(0.25 * 20)
T("it stops when the stack runs out", not Ammo.LoadActive() and mag_of(mag.item.instance_id).data.rounds == 7
  and loose_left(info.key) == 0 and PDTI.FindItem(stack.c, stack.item.instance_id) == nil)

-- Rounds of another weapon do not go in.
do
  local _, info2 = fresh(true)
  Ammo.AddMagazineKey(info2.key, 5, info2, { "pockets" }, { size = "standard", bullet = "standard" })
  local mc, m = find(function(_, it) return it.item_id == Ammo.MAGAZINE_ITEM end)
  Ammo.AddLooseKey("other_weapon_key", 20, { caliber = "x", pid = "y" })
  local lc, s = find(function(_, it) return it.item_id == Ammo.LOOSE_ITEM end)
  PDTI.UIDragStart(lc, s.x, s.y)
  local pv = PDTI.UIDragPreview(mc, m.x, m.y)
  T("rounds of another weapon light the magazine red", pv and pv.load and not pv.valid)
  PDTI.UIResetInteraction()
  local okd = drag({ c = lc, item = s }, { c = mc, item = m })
  T("and are not loaded", okd == false and not Ammo.LoadActive() and mag_of(m.instance_id).data.rounds == 5)
end

------------------------------------------------------------------ in the menu

wep, info, mag, stack = setup(false, 4, "hollow", 50, "standard")
local real_player = managers.player.player_unit
managers.player.player_unit = function() return nil end
T("in the menu (no player)", not PDTI.InHeist())
ok = drag(stack, mag)
T("in the menu the magazine is loaded at once", ok == true and not Ammo.LoadActive()
  and mag_of(mag.item.instance_id).data.rounds == 30 and loose_left(info.key) == 24,
  mag_of(mag.item.instance_id).data.rounds)
managers.player.player_unit = real_player

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
