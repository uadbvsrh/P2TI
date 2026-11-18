-- 0.25.0: Technician, Oppressor: Surefire and Body Expertise, the Stacked
-- Barrier (SKILLS_REWORK_SPEC.md §6).
--   luajit tests/barrier_tests.lua
local script = arg and arg[0] or "tests/barrier_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_barrier") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
local game = ENV.install_game()
ENV.load_mod(ROOT, false)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end
_G.Application = _G.Application or {}
Application.digest_value = function(_, v) return v end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end

local clock = 100
_G.TimerManager = { game = function() return { time = function() return clock end } end }
local hints = {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end
managers.hud.on_crit_confirmed = function() end

local owned = {}
_G.PlayerManager = {}
function PlayerManager:upgrade_value(cat, up, default)
  local v = owned[cat .. "." .. up]
  if v == nil then return default or 0 end
  return v
end
function PlayerManager:has_category_upgrade(cat, up) return owned[cat .. "." .. up] ~= nil end
function PlayerManager:upgrade_level(cat, up, default) return default or 0 end
function PlayerManager:critical_hit_chance() return 0 end
-- The game's modifiers (a skill of the game halves the damage here).
local game_mul = 1
function PlayerManager:modify_value(key, value) if key == "damage_taken" then return value * game_mul end return value end
local pm = managers.player
setmetatable(pm, { __index = PlayerManager })

NewRaycastWeaponBase._get_current_damage = function(self, m) return 10 * (m or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function() return 0 end
-- Vanilla Body Expertise: automatic rifles, SMGs and LMGs get an added
-- headshot multiplier.
NewRaycastWeaponBase.get_add_head_shot_mul = function(self) return self._auto and 0.3 or nil end

_G.CopDamage = {}
local CD = CopDamage
CD.__index = CD
CD.is_civilian = function(name) return name == "civilian" end
function CD:can_be_critical() return true end
function CD:roll_critical_hit(a, d) return false, d or a.damage end
function CD:check_medic_heal() return false end
function CD:is_head(body) return body and body.head == true end
function CD:damage_bullet(a)
  if self._dead then return nil end
  self._health = self._health - a.damage
  if self._health <= 0 then self._dead = true end
  a.result = { type = self._dead and "death" or "hurt" }
  return a.result
end
function CD:damage_explosion(a) return self:damage_bullet(a) end
function CD:damage_fire(a) return self:damage_bullet(a) end
function CD:damage_melee(a) return self:damage_bullet(a) end
_G.AmmoClip = { _pickup = function() return true end }
_G.AmmoBagBase = { spawn = function() end, sync_setup = function() end, _take_ammo = function() return 0 end,
  take_ammo = function() return false end }
_G.BaseInteractionExt = { _get_timer = function() return 1 end }

dofile(ROOT .. "lua/ammo_hooks.lua")
dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_ammo.lua")
dofile(ROOT .. "lua/skills_silent.lua")
dofile(ROOT .. "lua/skills_ap.lua")

local Ammo, Skills, B, Body = PDTI.Ammo, PDTI.Skills, PDTI.Barrier, PDTI.Body
local steps = {}
Skills.step_of = function(id) return steps[id] or 0 end
Skills.known = function() return true end
local function own(list) steps = {}; for id, step in pairs(list or {}) do steps[id] = step end end

T("the ammo hooks are in place", Ammo.InstallHooks() == true)
T("the skill hooks are in place", Skills.Install() == true)

local unit
local function gun(name, bullet, extra)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  B.OnHeistStart()
  PDTI.SetSessionOnly(true)
  unit = ENV.make_unit()
  local wep = ENV.make_weapon(name or "test_ar", { "wpn_no_part" }, 30, extra)
  wep._setup = { user_unit = unit }
  local wu = { base = function() return wep end, key = function() return "wep" end }
  wep._unit = wu
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  wep.clip = 30
  if bullet then
    Ammo.SetLoaded(wep, { size = "standard", bullet = bullet })
    Ammo.ApplyLoaded(wep)
  end
  Ammo.SyncTotal(wep)
  clock = clock + 100
  hints = {}
  return wep, wu
end
local function enemy(tweak)
  local u = {}
  u.base = function() return { _tweak_table = tweak or "swat" } end
  return setmetatable({ _unit = u, _health = 1000, _char_tweak = {} }, CD)
end
local HEAD = { head = true, name = function() return "ids:Head" end }
local CHEST = { name = function() return "ids:Spine1" end }
local function shoot(wu, body, who)
  return (who or enemy()):damage_bullet({ damage = 1, attacker_unit = unit, weapon_unit = wu, variant = "bullet",
    col_ray = { body = body or HEAD, position = {} } })
end
local function shown() return math.floor(B.Value() * 10 + 0.5) end

------------------------------------------------------------ Surefire

do
  local wep, wu = gun("test_ar", "ap")
  own({})
  shoot(wu)
  T("no skill: no barrier", shown() == 0)
  own({ fast_fire = 1 })
  shoot(wu)
  T("an AP headshot: 10", shown() == 10)
  T("you are told once", #hints == 1)
  for _ = 1, 9 do shoot(wu) end
  T("up to 50", shown() == 50, shown())
  shoot(wu, CHEST)
  T("an AP body shot: nothing (no Body Expertise)", shown() == 50)
  clock = clock + 2.9
  T("it stays for 3 s after the last headshot", shown() == 50)
  clock = clock + 0.2
  T("then it fades", shown() == 0)
  shoot(wu)
  T("no barrier during the 10 s cooldown", shown() == 0)
  T("the window shows the cooldown", (B.Line() or ""):find("cooldown") ~= nil, B.Line())
  clock = clock + 10
  shoot(wu)
  T("after the cooldown it builds again", shown() == 10)
  T("the window shows it", (B.Line() or ""):find("Barrier: 10") ~= nil, B.Line())
  T("in the health window", (function()
    for _, l in ipairs(Body.ExtraLines and Body.ExtraLines() or {}) do if l:find("Barrier") then return true end end
    return Body.lines.barrier ~= nil
  end)())
  own({ fast_fire = 2 })
  for _ = 1, 10 do shoot(wu) end
  T("ace: up to 60", shown() == 60)
  clock = clock + 3.9
  T("ace: it stays 4 s", shown() == 60)
  clock = clock + 0.2
  T("ace: then fades", shown() == 0)
  clock = clock + 8.9
  shoot(wu)
  T("ace: a 9 s cooldown", shown() == 0)
  clock = clock + 0.2
  shoot(wu)
  T("then builds", shown() == 10)

  own({ fast_fire = 1 })
  local w2, wu2 = gun("test_ar", "hollow")
  own({ fast_fire = 1 })
  shoot(wu2)
  T("an HP headshot: nothing", shown() == 0)
  local w3, wu3 = gun("test_ar", "standard")
  own({ fast_fire = 1 })
  shoot(wu3)
  T("a standard headshot: nothing", shown() == 0)
  local w4, wu4 = gun("test_ar", "ap")
  own({ fast_fire = 1 })
  shoot(wu4, HEAD, enemy("civilian"))
  T("not a civilian", shown() == 0)
  local lmg, lu = gun("test_smg", nil)
  Ammo.SetLoaded(lmg, { bullet = "penetrator" })
  lmg._pdti_shot_bullet = "penetrator"
  own({ fast_fire = 1 })
  shoot(lu)
  T("an LMG penetrator counts as AP", shown() == 10, shown())
end

------------------------------------------------------- Body Expertise

do
  local wep, wu = gun("test_ar", "ap", { get_add_head_shot_mul = function() return 0.3 end })
  own({ body_expertise = 1 })
  shoot(wu, CHEST)
  T("Body Expertise: an AP body shot of an automatic weapon: 3", shown() == 3)
  shoot(wu, HEAD)
  T("a headshot without Surefire: nothing", shown() == 3)
  own({ body_expertise = 2 })
  shoot(wu, CHEST)
  T("ace: 9", shown() == 12)
  for _ = 1, 10 do shoot(wu, CHEST) end
  T("alone: Surefire basic's cap (50)", shown() == 50)
  own({ body_expertise = 1, fast_fire = 2 })
  for _ = 1, 10 do shoot(wu, CHEST) end
  T("with Surefire ace the cap is 60", shown() == 60)
  local w2, wu2 = gun("test_ar", "ap")
  own({ body_expertise = 2 })
  shoot(wu2, CHEST)
  T("not a weapon outside vanilla's scope", shown() == 0)
end

------------------------------------------------------------ the soak

do
  local wep, wu = gun("test_ar", "ap")
  own({ fast_fire = 1 })
  for _ = 1, 3 do shoot(wu) end
  T("a 30 barrier", shown() == 30)
  T("a hit of 2.0 (20 shown) is soaked whole", pm:modify_value("damage_taken", 2.0) == 0 and shown() == 10)
  T("the rest of a bigger one goes on", near(pm:modify_value("damage_taken", 3.0), 2.0) and shown() == 0)
  T("then nothing is soaked", pm:modify_value("damage_taken", 1.0) == 1.0)
  for _ = 1, 3 do shoot(wu) end
  game_mul = 0.5
  T("after the game's own reductions", pm:modify_value("damage_taken", 2.0) == 0 and shown() == 20)
  game_mul = 1
  T("other values are not touched", pm:modify_value("something", 2.0) == 2.0 and shown() == 20)
  T("used up, it builds again at once (no cooldown)", (function()
    pm:modify_value("damage_taken", 9)
    shoot(wu)
    return shown() == 10
  end)())
end

------------------------------------------------------------ fallbacks

do
  local wep, wu = gun("test_ar", "ap")
  owned["player.automatic_mag_increase"] = 15
  owned["player.ap_bullets"] = 1
  own({ fast_fire = 2 })
  T("Surefire: +15 magazine and the AP ace are off", pm:upgrade_value("player", "automatic_mag_increase", 0) == 0
    and not pm:has_category_upgrade("player", "ap_bullets"))
  Ammo.settings.enabled = false
  T("ammo off: the vanilla Surefire", pm:upgrade_value("player", "automatic_mag_increase", 0) == 15
    and pm:has_category_upgrade("player", "ap_bullets"))
  shoot(wu)
  T("ammo off: no barrier", shown() == 0 and pm:modify_value("damage_taken", 1) == 1)
  Ammo.settings.enabled = true
  _G.restoration = {}
  T("restoration-mod: vanilla", pm:upgrade_value("player", "automatic_mag_increase", 0) == 15)
  _G.restoration = nil
  owned = {}
  B.OnHeistStart()
  T("a new heist: no barrier", shown() == 0)
end

T("both skills have their texts", Skills.texts.menu_fast_fire_beta_desc and Skills.texts.menu_body_expertise_beta_desc and true)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
