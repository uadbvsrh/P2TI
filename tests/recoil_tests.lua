-- 0.18.2: armour-piercing rounds are less stable. Every shot kicks harder,
-- and the kick builds up in full auto.
--   luajit tests/recoil_tests.lua
local script = arg and arg[0] or "tests/recoil_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_recoil") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Idstring = function(s) return "ids:" .. tostring(s) end
-- The game's recoil multiplier (skills, the weapon's mods): 0.8 here.
NewRaycastWeaponBase.recoil_multiplier = function() return 0.8 end
NewRaycastWeaponBase._get_current_damage = function(self, m) return 10 * (m or 1) end
_G.CopDamage = { roll_critical_hit = function(_, a) return false, a.damage end }
-- The clock: the test moves it.
local clock = 100
_G.Application = _G.Application or {}
Application.time = function() return clock end
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo = PDTI.Ammo
T("the recoil hook is in place", Ammo.InstallHooks() == true
  and Ammo.hooks["NewRaycastWeaponBase.recoil_multiplier"] ~= nil)

-- An assault rifle firing 600 rounds a minute (0.1 s between shots).
local function rifle(bullet, name)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon(name or "test_ar", { "wpn_no_part" }, 30)
  -- The game's tweak data of the gun, with its rate of fire.
  local tweak = tweak_data.weapon[name or "test_ar"]
  tweak.fire_mode_data = { fire_rate = 0.1 }
  function wep:weapon_tweak_data() return tweak end
  function wep:fire_rate_multiplier() return 1 end
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  if bullet then
    Ammo.SetLoaded(wep, { size = "standard", bullet = bullet })
    Ammo.ApplyLoaded(wep)
  end
  return wep
end
-- One shot: the time moves on, the game asks for the recoil.
local function shot(wep, gap)
  clock = clock + (gap or 0.1)
  return NewRaycastWeaponBase.recoil_multiplier(wep)
end

local ap = rifle("ap")
local first = shot(ap, 5)
T("an AP shot kicks half again as hard", near(first, 0.8 * 1.5), first)
local kicks = { first }
for i = 2, 10 do kicks[i] = shot(ap) end
T("in full auto every shot kicks harder than the last", kicks[2] > kicks[1] and kicks[4] > kicks[3]
  and kicks[7] > kicks[6], table.concat(kicks, " "))
T("up to 2.4 times the gun's own recoil", near(kicks[7], 0.8 * 2.4) and near(kicks[10], 0.8 * 2.4), kicks[10])
T("which is the most it gets (not absurd)", kicks[10] <= 0.8 * 2.4 + 1e-9)
local after_pause = shot(ap, 0.4)
T("a pause of a few tenths settles the gun again", near(after_pause, 0.8 * 1.5), after_pause)
-- Tapping single shots at a steady pace: each shot on its own.
local taps = {}
for i = 1, 5 do taps[i] = shot(ap, 0.25) end
T("aimed single shots keep the base kick", near(taps[5], 0.8 * 1.5), taps[5])
-- Fast taps still count as a burst: spamming the trigger is no way around it.
local fast = {}
for i = 1, 4 do fast[i] = shot(ap, 0.15) end
T("spamming the trigger builds up like full auto", fast[4] > fast[1], table.concat(fast, " "))

-- A slower gun (0.2 s between shots) gets the same build-up at its own pace.
local slow = rifle("ap")
tweak_data.weapon.test_ar.fire_mode_data = { fire_rate = 0.2 }
shot(slow, 5)
local s2 = shot(slow, 0.2)
T("the build-up follows the gun's own rate of fire", s2 > 0.8 * 1.5 + 1e-9, s2)

for _, bullet in ipairs({ "standard", "hollow" }) do
  local w = rifle(bullet)
  local k = {}
  for i = 1, 8 do k[i] = shot(w, i == 1 and 5 or 0.1) end
  T(bullet .. " rounds keep the gun's recoil, even in full auto", near(k[1], 0.8) and near(k[8], 0.8), k[8])
end

-- A mixed magazine: the round that was fired decides.
local mixed = rifle("standard")
mixed._pdti_shot_bullet = "ap"
local m1 = shot(mixed, 5)
mixed._pdti_shot_bullet = "standard"
local m2 = shot(mixed)
T("in a mixed magazine an AP round kicks", near(m1, 0.8 * 1.5), m1)
T("and the standard round after it does not", near(m2, 0.8), m2)

-- A weapon without bullet types is not touched.
local lmg = rifle(nil, "test_smg")
T("weapons without bullet types keep their recoil", near(shot(lmg, 5), 0.8) and near(shot(lmg), 0.8))

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
