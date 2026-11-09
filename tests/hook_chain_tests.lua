-- 0.18.4: parts of the mod that hook the same game function must not wrap
-- each other again every frame. In 0.18.2 the AP recoil and the arm health
-- both hooked recoil_multiplier; each frame one wrapped the other again,
-- the chain grew, and after a few minutes a shot overflowed the stack and
-- crashed the game.
--   luajit tests/hook_chain_tests.lua
local script = arg and arg[0] or "tests/hook_chain_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_hook_chain") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Idstring = function(s) return "ids:" .. tostring(s) end
local clock = 100
_G.Application = _G.Application or {}
Application.time = function() return clock end
Application.digest_value = function(_, v) return v end

-- Every game function the parts of the mod hook.
NewRaycastWeaponBase.recoil_multiplier = function() return 0.8 end
NewRaycastWeaponBase.spread_multiplier = function() return 1 end
NewRaycastWeaponBase._get_current_damage = function(self, m) return 10 * (m or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function() return 0.25 end
_G.CopDamage = { roll_critical_hit = function(_, a) return false, a.damage end }
_G.AkimboWeaponBase = { super = NewRaycastWeaponBase, fire = function() end }
_G.PlayerDamage = {}
for _, fn in ipairs({ "change_health", "set_health", "revive", "recover_health", "replenish", "damage_bullet",
  "damage_melee", "damage_fall", "damage_explosion", "damage_fire", "damage_killzone", "damage_simple" }) do
  PlayerDamage[fn] = function() end
end
_G.PlayerMovement = _G.PlayerMovement or {}
PlayerMovement._max_stamina = function() return 50 end
PlayerMovement._apply_attention_setting_modifications = PlayerMovement._apply_attention_setting_modifications or function() end
PlayerStandard._start_action_running = function() end
PlayerStandard._check_action_run = function() end
dofile(ROOT .. "lua/ammo_hooks.lua")
dofile(ROOT .. "lua/body.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

-- Every part installs its hooks, as the game tick does each frame.
local function frame()
  pcall(PDTI.Ammo.InstallHooks)
  pcall(PDTI.Body.InstallHooks)
  if PDTI.Carry and PDTI.Carry.InstallHooks then pcall(PDTI.Carry.InstallHooks) end
  if PDTI.Loot and PDTI.Loot.InstallHooks then pcall(PDTI.Loot.InstallHooks) end
  if PDTI.Gear and PDTI.Gear.InstallHooks then pcall(PDTI.Gear.InstallHooks) end
end
local CLASSES = { "NewRaycastWeaponBase", "RaycastWeaponBase", "PlayerStandard", "PlayerDamage", "PlayerMovement",
  "PlayerManager", "PlayerCarry", "PlayerInventory", "CopDamage", "AkimboWeaponBase", "CarryInteractionExt",
  "HUDTeammate" }
local function snapshot()
  local out = {}
  for _, name in ipairs(CLASSES) do
    local cls = rawget(_G, name)
    if type(cls) == "table" then
      for k, v in pairs(cls) do if type(v) == "function" then out[name .. "." .. k] = v end end
    end
  end
  return out
end

frame()
frame()
local first = snapshot()
for _ = 1, 100 do frame() end
local later = snapshot()
local changed = {}
for key, fn in pairs(later) do if first[key] ~= fn then changed[#changed + 1] = key end end
table.sort(changed)
T("a hundred frames later no game function was wrapped again", #changed == 0, table.concat(changed, ", "))

-- The recoil has both parts once: AP (x1.5) and a black arm (x1.35).
PDTI.Reset()
PDTI.Ammo.Reset()
PDTI.Ammo.OnHeistStart()
PDTI.SetSessionOnly(true)
local unit = ENV.make_unit()
local wep = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
local tweak = tweak_data.weapon.test_ar
tweak.fire_mode_data = { fire_rate = 0.1 }
function wep:weapon_tweak_data() return tweak end
function wep:fire_rate_multiplier() return 1 end
wep._setup = { user_unit = unit }
unit:set_weapon(wep)
PDTI.Ammo.EnsureSupply(wep)
PDTI.Ammo.SetLoaded(wep, { size = "standard", bullet = "ap" })
PDTI.Ammo.ApplyLoaded(wep)
local Body = PDTI.Body
Body.OnHeistStart()
Body.state.owner = {}
Body.state.max = 23
Body.Damage(10, "arm_l", 23)
T("the arm is black", Body.IsBlack("arm_l"))
clock = clock + 5
local kick = NewRaycastWeaponBase.recoil_multiplier(wep)
T("the recoil is the gun's x AP x arm, once each", near(kick, 0.8 * 1.5 * 1.35), kick)

-- Another mod replaces the function: our parts wrap it again, once each.
NewRaycastWeaponBase.recoil_multiplier = function() return 0.5 end
frame()
local again = NewRaycastWeaponBase.recoil_multiplier
for _ = 1, 20 do frame() end
T("a function replaced by another mod is wrapped again once", NewRaycastWeaponBase.recoil_multiplier == again)
clock = clock + 5
kick = NewRaycastWeaponBase.recoil_multiplier(wep)
T("with both parts on it", near(kick, 0.5 * 1.5 * 1.35), kick)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
