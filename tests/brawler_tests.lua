-- 0.26.0: Fugitive, Brawler: Berserker and Frenzy (SKILLS_REWORK_SPEC.md §8).
--   luajit tests/brawler_tests.lua
local script = arg and arg[0] or "tests/brawler_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_brawler") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Application = _G.Application or {}
Application.digest_value = function(_, v) return v end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end

---------------------------------------------------------------- the game

_G.PlayerDamage = {}
local PD = PlayerDamage
PD.__index = PD
function PD:_max_health() return self.max end
function PD:get_real_health() return self._health end
function PD:get_real_armor() return 0 end
function PD:set_health(h) self._health = math.max(0, math.min(self.max, h)) end
function PD:change_health(d) self:set_health(self._health + d) end
function PD:need_revive() return self.downed end
function PD:_check_bleed_out() if self._health <= 0 and not self.downed then self.downed = true end end
function PD:_calc_health_damage(a) self:change_health(-a.damage); self:_check_bleed_out() end
function PD:damage_bullet(a) if a.damage > 0 then self:_calc_health_damage(a) end end
function PD:damage_melee(a) self:damage_bullet(a) end
function PD:damage_explosion(a) self:_calc_health_damage(a) end
function PD:damage_fall(a) self:_calc_health_damage(a) end
function PD:band_aid_health() self:change_health(self:_max_health()) end
function PD:revive() self.downed = false; self:set_health(self.max * 0.4) end
function PD:_regenerated() self:set_health(self:_max_health()) end
function PD:recover_health() if self:need_revive() then self:revive(true) end self:_regenerated() end
function PD:replenish() self:recover_health() end
_G.PlayerMovement = { _max_stamina = function() return 50 end }
PlayerStandard._start_action_running = function() end
PlayerStandard._check_action_run = function() end
NewRaycastWeaponBase.recoil_multiplier = function() return 1 end
NewRaycastWeaponBase.spread_multiplier = function() return 1 end

local owned = {}
_G.PlayerManager = {}
function PlayerManager:upgrade_value(cat, up, default)
  local v = owned[cat .. "." .. up]
  if v == nil then return default or 0 end
  return v
end
function PlayerManager:has_category_upgrade(cat, up) return owned[cat .. "." .. up] ~= nil end
function PlayerManager:upgrade_level() return 0 end
local unit = {}
local pm = setmetatable({ player_unit = function() return unit end }, { __index = PlayerManager })
_G.managers = _G.managers or {}
managers.player = pm
managers.hud = { show_hint = function() end, set_player_health = function() end, set_max_stamina = function() end }

-- Enemies: the damage that reaches them.
local got = {}
_G.CopDamage = {}
function CopDamage:damage_melee(a) got.melee = a.damage end
function CopDamage:damage_bullet(a) got.bullet = a.damage end
_G.SentryGunDamage = {}
function SentryGunDamage:damage_bullet(a) got.turret = a.damage end

local clock = 100
dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/armour.lua")
local Body = PDTI.Body
Body.clock = function() return clock end
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_medic.lua")
dofile(ROOT .. "lua/doctor_buffs.lua")
dofile(ROOT .. "lua/skills_brawler.lua")
local Skills, BR = PDTI.Skills, PDTI.Brawler
local steps = {}
Skills.step_of = function(id) return steps[id] or 0 end
Skills.known = function() return true end
local function own(list) steps = {}; for id, s in pairs(list or {}) do steps[id] = s end end

T("the body hooks are in place", Body.InstallHooks() == true)
T("the skill hooks are in place", Skills.Install() == true)

-- Max 44: head 3.5, body 15.5, arms 6, legs 6.5.
local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }
local function player()
  Body.OnHeistStart()
  PDTI.DoctorBuffs.OnHeistStart()
  local p = setmetatable({ max = 44, _health = 44, downed = false }, PD)
  unit.character_damage = function() return p end
  Body.AttachPlayer()
  return p
end
local function shoot(p, part, dmg) rolls = { ROLL[part] }; p:damage_bullet({ damage = dmg }) end
local function hp(id) return Body.HP(id) end
local function hit(kind, cls, attacker)
  got = {}
  local a = { damage = 10, attacker_unit = attacker or unit }
  local self = setmetatable({}, { __index = cls or CopDamage })
  if kind == "melee" then (cls or CopDamage).damage_melee(self, a) else (cls or CopDamage).damage_bullet(self, a) end
  return got[kind == "melee" and "melee" or (cls == SentryGunDamage and "turret" or "bullet")]
end

---------------------------------------------------------------- Frenzy

own({})
local p = player()
T("no skill: every part at full", near(hp("arm_l"), 6) and near(Body.Sum(), 44))

own({ frenzy = 1 })
p = player()
T("Frenzy: the arms and legs start black", Body.IsBlack("arm_l") and Body.IsBlack("arm_r")
  and Body.IsBlack("leg_l") and Body.IsBlack("leg_r"))
T("Frenzy: they hold at most 1 HP", near(Body.PartMax("arm_l"), 0.1) and near(Body.PartMax("leg_r"), 0.1)
  and Body.ShownMax("arm_l") == 1)
T("Frenzy basic: the head and the body as they were", near(Body.PartMax("head"), 3.5)
  and near(Body.PartMax("body"), 15.5) and not Body.IsBlack("body"))
T("the lost health is gone: the game's health is the sum", near(p._health, 19) and near(Body.Sum(), 19), p._health)
T("no Painkillers suspension at the start", Body.state.black_at.arm_l == nil)
shoot(p, "arm_l", 2)
T("a hit on a black arm: 75% to the body", near(hp("body"), 15.5 - 1.5), hp("body"))
p:band_aid_health()
T("a first aid kit does not heal them", Body.IsBlack("arm_l") and near(hp("body"), 15.5))
local healed
local real_bag = Body.mods.on_doctor_bag
Body.mods.on_doctor_bag = function(list) healed = list end
p:recover_health()
Body.mods.on_doctor_bag = real_bag
T("a doctor bag fills them to 1 HP", near(hp("arm_l"), 0.1) and near(hp("leg_r"), 0.1)
  and not Body.IsBlack("arm_l"), hp("arm_l"))
T("they count as healed black parts (Combat Doctor)", healed and #healed == 4, healed and #healed)
shoot(p, "arm_l", 0.05)
T("not black until their next hit", near(hp("arm_l"), 0.05) and not Body.IsBlack("arm_l"))
shoot(p, "arm_l", 0.2)
T("then black again", Body.IsBlack("arm_l"))
T("a new damage extension (custody): black again", (function()
  p:recover_health()
  local p2 = setmetatable({ max = 44, _health = 44, downed = false }, PD)
  unit.character_damage = function() return p2 end
  Body.AttachPlayer()
  return Body.IsBlack("arm_r") and near(p2._health, 19)
end)())

own({ frenzy = 2 })
p = player()
T("Frenzy ace: the body too", Body.IsBlack("body") and near(Body.PartMax("body"), 0.1))
T("Frenzy ace: the head holds what they lost", near(Body.PartMax("head"), 43.5), Body.PartMax("head"))
T("the whole max stays", near(Body.PartMax("head") + 5 * 0.1, 44))
T("the game's health is the head", near(p._health, 43.5) and near(hp("head"), 43.5))
shoot(p, "leg_l", 4)
T("a body hit: 75% reaches the head", near(hp("head"), 40.5), hp("head"))
shoot(p, "head", 4)
T("a headshot: all of it", near(hp("head"), 36.5), hp("head"))
shoot(p, "head", 40)
T("the head at 0: down", p.downed)
p:revive()
T("a revive gives the head 1 HP", near(hp("head"), 0.1))

owned["player.max_health_reduction"] = 0.3
owned["player.health_damage_reduction"] = 0.75
T("Frenzy: no health cap", pm:upgrade_value("player", "max_health_reduction", 1) == 1)
T("Frenzy ace: the damage reduction is the basic's", pm:upgrade_value("player", "health_damage_reduction", 1) == 0.9)
own({ frenzy = 1 })
owned["player.health_damage_reduction"] = 0.9
T("Frenzy basic: its 10% stays", pm:upgrade_value("player", "health_damage_reduction", 1) == 0.9)
PDTI.Ammo.settings.body_parts = false
owned["player.health_damage_reduction"] = 0.75
own({ frenzy = 2 })
T("body parts off: the vanilla Frenzy", pm:upgrade_value("player", "max_health_reduction", 1) == 0.3
  and pm:upgrade_value("player", "health_damage_reduction", 1) == 0.75 and Body.PartMax("arm_l", 44) > 1)
PDTI.Ammo.settings.body_parts = true
_G.restoration = {}
T("restoration-mod: vanilla", pm:upgrade_value("player", "max_health_reduction", 1) == 0.3
  and Body.PartMax("arm_l", 44) > 1)
_G.restoration = nil
owned = {}

------------------------------------------------------------- Berserker

own({})
p = player()
T("no skill: melee as it is", hit("melee") == 10)
own({ wolverine = 1 })
T("Berserker: nothing black, nothing more", hit("melee") == 10)
shoot(p, "arm_l", 6)
T("one black part: +10% melee", near(hit("melee"), 11), hit("melee"))
T("basic: bullets as they are", hit("bullet") == 10)
shoot(p, "arm_r", 6); shoot(p, "leg_l", 6.5); shoot(p, "leg_r", 6.5)
T("four black parts: +40%", near(hit("melee"), 14))
shoot(p, "body", 15.5)
T("five: +50%", near(hit("melee"), 15) and BR.Black() == 5)
shoot(p, "head", 10)
T("the head does not count (still +50% when it goes black)", Body.IsBlack("head") and BR.Black() == 5
  and near(hit("melee"), 15))
own({ wolverine = 2 })
T("ace: bullets too", near(hit("bullet"), 15))
T("ace: turrets too", near(hit("bullet", SentryGunDamage), 15))
T("not someone else's hit", hit("melee", nil, { other = true }) == 10)
own({ wolverine = 2, frenzy = 2 })
p = player()
T("with Frenzy ace: +50% from the start", near(hit("melee"), 15) and near(hit("bullet"), 15))
own({ wolverine = 1, frenzy = 1 })
p = player()
T("with Frenzy basic: +40%", near(hit("melee"), 14))
owned["player.melee_damage_health_ratio_multiplier"] = 2.5
owned["player.damage_health_ratio_multiplier"] = 1
own({ wolverine = 2 })
T("the low-health scaling is off", pm:upgrade_value("player", "melee_damage_health_ratio_multiplier", 0) == 0
  and not pm:has_category_upgrade("player", "damage_health_ratio_multiplier"))
PDTI.Ammo.settings.body_parts = false
T("body parts off: vanilla Berserker", pm:upgrade_value("player", "melee_damage_health_ratio_multiplier", 0) == 2.5
  and hit("melee") == 10)
PDTI.Ammo.settings.body_parts = true
owned = {}

T("both skills have their texts", Skills.texts.menu_wolverine_beta_desc ~= nil and Skills.texts.menu_frenzy_desc ~= nil
  and Skills.texts.menu_frenzy_beta_desc == nil)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
