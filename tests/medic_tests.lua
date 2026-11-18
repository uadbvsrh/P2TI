-- 0.23.0: the skill rework frame and the Medic branch (SKILLS_REWORK_SPEC.md §3).
--   luajit tests/medic_tests.lua
local script = arg and arg[0] or "tests/medic_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_medic") .. "/")
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

local downs = 0
_G.PlayerDamage = {}
local PD = PlayerDamage
PD.__index = PD
function PD:_max_health() return self.max end
function PD:get_real_health() return self._health end
function PD:get_real_armor() return self.armor end
function PD:set_health(h) self._health = math.max(0, math.min(self.max, h)) end
function PD:change_health(d) self:set_health(self._health + d) end
function PD:need_revive() return self.downed end
local kit_near = false
function PD:_check_bleed_out()
  if self._health <= 0 and not self.downed then
    -- Uppers: a first aid kit nearby takes the down.
    if kit_near then self:band_aid_health(); return end
    self.downed = true; downs = downs + 1
  end
end
function PD:_calc_health_damage(a) self:change_health(-a.damage); self:_check_bleed_out() end
function PD:damage_bullet(a) if a.damage > 0 then self:_calc_health_damage(a) end end
PD.pushes = {}
function PD:damage_melee(a) PD.pushes[#PD.pushes + 1] = a.push_vel; self:damage_bullet(a) end
function PD:damage_explosion(a) self:_calc_health_damage(a) end
function PD:damage_fall(a) self:_calc_health_damage(a) end
function PD:damage_tase() self.tased = (self.tased or 0) + 1 end
function PD:on_flashbanged(mul) self.flash = mul end
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
NewRaycastWeaponBase.reload_speed_multiplier = function() return 1 end
_G.BaseInteractionExt = { _get_timer = function() return 4 end }
_G.CoreEnvironmentControllerManager = { set_flashbang = function(self, p, l, t, li, d) self.duration = d end }

-- The upgrades the player owns (vanilla values).
local owned = {}
_G.PlayerManager = {}
function PlayerManager:upgrade_value(cat, up, default)
  local v = owned[cat .. "." .. up]
  if v == nil then return default or 0 end
  return v
end
function PlayerManager:has_category_upgrade(cat, up) return owned[cat .. "." .. up] ~= nil end
function PlayerManager:critical_hit_chance() return 0.03 end
local unit = {}
local pm = setmetatable({ player_unit = function() return unit end }, { __index = PlayerManager })
_G.managers = _G.managers or {}
managers.player = pm
local hints = {}
managers.hud = { show_hint = function(_, h) hints[#hints + 1] = h.text end, set_player_health = function() end,
  set_max_stamina = function() end }

local clock = 100
dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/armour.lua")
local Body = PDTI.Body
Body.clock = function() return clock end
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_medic.lua")
dofile(ROOT .. "lua/doctor_buffs.lua")
local Skills, Medic, Buffs = PDTI.Skills, PDTI.Medic, PDTI.DoctorBuffs
local steps = {}
Skills.step_of = function(id) return steps[id] or 0 end
local function own(id, step) steps = {}; if id then steps[id] = step end end

T("the body hooks are in place", Body.InstallHooks() == true)
T("the skill hooks are in place", Skills.Install() == true)
T("the revive hook waits for its class", _G.ReviveInteractionExt == nil)

-- Max 44: head 3.5, body 15.5, arms 6, legs 6.5.
local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }
local function player()
  Body.OnHeistStart(); Buffs.OnHeistStart()
  downs = 0
  local p = setmetatable({ max = 44, _health = 44, armor = 0, downed = false }, PD)
  unit.character_damage = function() return p end
  Body.AttachPlayer()
  return p
end
local function shoot(p, part, dmg) rolls = { ROLL[part] }; p:damage_bullet({ damage = dmg }) end
local function hp(id) return Body.HP(id) end

----------------------------------------------------------- the frame

own(nil)
T("nothing owned: the game's values", pm:upgrade_value("player", "revive_health_boost", 0) == 0)
owned["player.revive_health_boost"] = 1
T("a vanilla upgrade reads as the game has it", pm:upgrade_value("player", "revive_health_boost", 0) == 1)
own("combat_medic", 2)
T("Combat Medic ace switches the +30% revive health off", pm:upgrade_value("player", "revive_health_boost", 0) == 0
  and pm:has_category_upgrade("player", "revive_health_boost") == false)
_G.restoration = {}
T("with restoration-mod the game's skills stay", pm:upgrade_value("player", "revive_health_boost", 0) == 1
  and Skills.Step("combat_medic") == 0)
_G.restoration = nil
PDTI.Ammo.settings.body_parts = false
T("with body parts off the vanilla skill stays", pm:upgrade_value("player", "revive_health_boost", 0) == 1)
PDTI.Ammo.settings.body_parts = true
owned["player.revive_health_boost"] = nil
T("every reworked Medic skill has its text", Skills.texts.menu_combat_medic_beta_desc and Skills.texts.menu_tea_time_beta_desc
  and Skills.texts.menu_fast_learner_beta_desc and Skills.texts.menu_tea_cookies_beta_desc
  and Skills.texts.menu_medic_2x_beta_desc and not Skills.texts.menu_inspire_beta_desc and true)
local added
_G.LocalizationManager = { add_localized_strings = function(_, t) added = t end }
T("the texts go to the game", Skills.ApplyTexts() == true and added.menu_tea_cookies_beta_desc ~= nil)
_G.restoration = {}
added = nil
T("not with restoration-mod", Skills.ApplyTexts() == false and added == nil)
_G.restoration = nil

------------------------------------------------------- Combat Medic ace

local p = player()
own(nil)
shoot(p, "head", 3.5)
T("downed", p.downed)
p:revive()
T("no skill: revived with 1 HP on the head", near(hp("head"), 0.1), hp("head"))
own("combat_medic", 2)
p = player()
shoot(p, "head", 3.5)
p:revive()
T("Combat Medic ace: revived with the head full", near(hp("head"), 3.5) and near(p._health, Body.Sum()), hp("head"))
-- Reviving someone heals your head.
_G.ReviveInteractionExt = { interact = function() end }
Skills.Install()
p = player()
shoot(p, "head", 2)
local ext = setmetatable({ tweak_data = "revive" }, { __index = ReviveInteractionExt })
ReviveInteractionExt.interact(ext, unit)
T("Combat Medic ace: reviving someone heals your head", near(hp("head"), 3.5) and near(p._health, 44), hp("head"))
shoot(p, "head", 2)
ReviveInteractionExt.interact(setmetatable({ tweak_data = "free" }, { __index = ReviveInteractionExt }), unit)
T("freeing a cuffed player does not", near(hp("head"), 1.5), hp("head"))
ReviveInteractionExt.interact(ext, { other = true })
T("someone else's revive does not", near(hp("head"), 1.5))
own("combat_medic", 1)
ReviveInteractionExt.interact(ext, unit)
T("basic only: no head heal", near(hp("head"), 1.5))

------------------------------------------------------------ Quick Fix

owned["first_aid_kit.deploy_time_multiplier"] = 0.5
own("tea_time", 1)
p = player()
p.armor = 5
T("Quick Fix: armour up, the kit deploys at normal speed",
  pm:upgrade_value("first_aid_kit", "deploy_time_multiplier", 1) == 1)
p.armor = 0
T("Quick Fix: armour broken, twice as fast", pm:upgrade_value("first_aid_kit", "deploy_time_multiplier", 1) == 0.5)
own(nil)
p.armor = 5
T("without the skill: the game's value", pm:upgrade_value("first_aid_kit", "deploy_time_multiplier", 1) == 0.5)
owned["first_aid_kit.deploy_time_multiplier"] = nil
-- Heavy armour: broken until a plate.
own("tea_time", 1)
owned["first_aid_kit.deploy_time_multiplier"] = 0.5
local Armour = PDTI.Armour
local real_heavy, real_broken = Armour.IsHeavy, Armour.IsBroken
Armour.IsHeavy = function() return true end
Armour.IsBroken = function() return true end
p.armor = 5 -- a perk gave some back: still broken until a plate
T("Quick Fix: heavy armour broken (no plate yet) counts", pm:upgrade_value("first_aid_kit", "deploy_time_multiplier", 1) == 0.5)
Armour.IsBroken = function() return false end
p.armor = 0
T("Quick Fix: heavy armour plated counts as up", pm:upgrade_value("first_aid_kit", "deploy_time_multiplier", 1) == 1)
Armour.IsHeavy, Armour.IsBroken = real_heavy, real_broken
owned["first_aid_kit.deploy_time_multiplier"] = nil

-- Ace: overheal.
owned["first_aid_kit.damage_reduction_upgrade"] = true
own("tea_time", 2)
T("Quick Fix ace switches the FAK damage reduction off",
  pm:has_category_upgrade("first_aid_kit", "damage_reduction_upgrade") == false)
owned["first_aid_kit.damage_reduction_upgrade"] = nil
p = player()
shoot(p, "leg_l", 2)
p:band_aid_health()
T("overheal: the kit fills the parts, the rest is kept", near(hp("leg_l"), 6.5) and near(Body.Over("body"), 15.5 * 0.25)
  and near(Body.Over("head"), 3.5 * 0.25), Body.Over("body"))
T("capped at +25% of each part", near(Body.Over("arm_l"), 1.5) and near(Body.Over("leg_r"), 6.5 * 0.25))
T("the game's health stays at its max", near(p._health, 44), p._health)
shoot(p, "body", 3)
T("overheal is lost first", near(hp("body"), 15.5) and near(Body.Over("body"), 15.5 * 0.25 - 3), hp("body"))
shoot(p, "body", 3)
T("then the part", near(Body.Over("body"), 0) and near(hp("body"), 15.5 - (3 - (15.5 * 0.25 - 3))), hp("body"))
p:change_health(5) -- a perk heal is not a kit: no overheal
T("only a first aid kit overheals", near(Body.Over("body"), 0))
Body.OnHeistStart()
T("overheal is gone at the next heist", near(Body.Over("head"), 0))
own("tea_time", 1)
p = player()
p:band_aid_health()
T("basic only: no overheal", near(Body.Over("body"), 0))

------------------------------------------------------------ Painkillers

own("fast_learner", 1)
owned["player.revive_damage_reduction_level"] = 2
T("Painkillers switches the vanilla revive damage reduction off",
  pm:upgrade_value("player", "revive_damage_reduction_level", 0) == 0)
owned["player.revive_damage_reduction_level"] = nil
p = player()
shoot(p, "arm_l", 6); shoot(p, "arm_l", 4)
T("Painkillers: a black arm passes on 50%", near(hp("body"), 13.5), hp("body"))
own(nil)
p = player()
shoot(p, "arm_l", 6); shoot(p, "arm_l", 4)
T("without it: 75%", near(hp("body"), 12.5), hp("body"))
-- Ace: 40 s.
own("fast_learner", 2)
p = player()
clock = 100
shoot(p, "leg_l", 6.5)
T("Painkillers ace: a black leg can still sprint", Body.IsBlack("leg_l") and Body.CanSprint() == true)
T("and no slowdown", near(Body.SpeedFactor(), 1))
clock = 139
T("39 s later still", Body.CanSprint() == true)
clock = 140.5
T("after 40 s the penalties come", Body.CanSprint() == false and near(Body.SpeedFactor(), 0.85))
shoot(p, "arm_r", 6)
T("a part going black later gets its own 40 s", Body.Suspended("arm_r") and near(Body.RecoilMul(), 1))
shoot(p, "head", 3.5)
T("the head is never suspended", p.downed and not Body.Suspended("head"))
own("fast_learner", 1)
p = player()
shoot(p, "leg_l", 6.5)
T("basic only: no suspension", Body.CanSprint() == false)

------------------------------------------------------------ Uppers

own("tea_cookies", 1)
Skills.Install()
T("Uppers: first aid kits stack 3 to a slot", PDTI.items.first_aid_kit.max_stack == 3)
own(nil)
Skills.Install()
T("without it: 1", PDTI.items.first_aid_kit.max_stack == 1)
own("tea_cookies", 1)
PDTI.Deployables.enabled = false
Skills.Install()
T("with the deployables system off: 1", PDTI.items.first_aid_kit.max_stack == 1)
PDTI.Deployables.enabled = true
-- The auto-revive inside the bleed-out check.
kit_near = true
own("tea_cookies", 2)
p = player()
shoot(p, "head", 3.5)
T("Uppers ace: the kit takes the down", not p.downed and downs == 0)
T("and the head is full", near(hp("head"), 3.5) and p._health > 0, hp("head") .. " " .. p._health)
own(nil)
p = player()
shoot(p, "head", 3.5)
-- (the kit then heals every part that is not black, the head too)
T("an auto-revive without the ace no longer leaves you at 0 health", not p.downed and p._health > 0
  and not Body.IsBlack("head"), hp("head") .. " " .. p._health)
kit_near = false

------------------------------------------------------- Combat Doctor

own("medic_2x", 2)
p = player()
clock = 100
p:recover_health()
T("no black parts: no buff", Buffs.Current() == nil)
shoot(p, "body", 15.5); shoot(p, "leg_l", 6.5); shoot(p, "leg_r", 6.5)
hints = {}
p:recover_health()
local b = Buffs.Current()
T("torso + both legs: 3 parts, 180 s", b and b.count == 3 and b.seconds == 180 and b.torso and b.legs == 2, b and b.seconds)
T("a hint says so", hints[1] and hints[1]:find("180") ~= nil, hints[1])
T("the doctor bag still heals everything", near(hp("leg_l"), 6.5) and near(p._health, 44))
T("stamina +50%", near(Body.StaminaMul(), 1.5) and near(pm:upgrade_value("player", "stamina_regen_multiplier", 1), 1.5))
T("calm: no screen shake", pm:upgrade_value("player", "damage_shake_multiplier", 1) == 0)
T("focus: +10% crit", near(pm:critical_hit_chance(), 0.13))
p:damage_tase({})
T("shrug off: no tase", (p.tased or 0) == 0)
p:on_flashbanged(1)
T("shrug off: no flashbang", p.flash == nil)
local env = setmetatable({}, { __index = CoreEnvironmentControllerManager })
CoreEnvironmentControllerManager.set_flashbang(env, nil, nil, nil, nil, 2)
T("shrug off: no white screen", env.duration == 0)
T("second wind x2: half the load's slowdown", near(PDTI.Carry.LoadRelief(), 0.5))
PD.pushes = {}
p:damage_melee({ damage = 0, push_vel = 10 })
T("steady legs x2: no push", PD.pushes[1] == 0, PD.pushes[1])
T("no arm effects (no arm healed)", near(Body.RecoilMul(), 1) and near(BaseInteractionExt._get_timer({}), 4))
-- Arms: one arm.
p = player()
clock = 200
shoot(p, "arm_l", 6)
p:recover_health()
b = Buffs.Current()
T("one arm: 60 s, the arm group at one limb", b and b.seconds == 60 and b.arms == 1 and not b.torso)
T("steady aim -15%", near(Body.RecoilMul(), 0.85) and near(Body.SpreadMul(), 0.85))
local wep = { _setup = { user_unit = unit } }
T("fast hands +15% reload", near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1.15))
T("fast hands: packing rounds 15% faster", near(PDTI.Ammo.RoundInterval(), PDTI.Ammo.settings.round_interval / 1.15))
T("interaction +12.5%", near(BaseInteractionExt._get_timer({}), 4 / 1.125))
T("no torso effects", near(pm:critical_hit_chance(), 0.03) and near(Body.StaminaMul(), 1))
-- Both arms; a new buff replaces the running one.
shoot(p, "arm_l", 6); shoot(p, "arm_r", 6)
p:recover_health()
b = Buffs.Current()
T("both arms: steady aim -30%, fast hands +30%, interaction +25%", b.arms == 2 and near(Body.RecoilMul(), 0.70)
  and near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1.30) and near(BaseInteractionExt._get_timer({}), 4 / 1.25))
T("a new buff replaces the running one (120 s from now)", b.seconds == 120 and near(b.ends, 320))
shoot(p, "body", 15.5)
p:recover_health()
b = Buffs.Current()
T("replaced, not stacked: only the torso now", b.torso and b.arms == 0 and near(Body.RecoilMul(), 1))
clock = 400
T("the buff ends", Buffs.Current() == nil and near(pm:critical_hit_chance(), 0.03))
-- Basic.
own("medic_2x", 1)
p = player()
clock = 500
shoot(p, "body", 15.5); shoot(p, "leg_l", 6.5); shoot(p, "leg_r", 6.5); shoot(p, "arm_l", 6); shoot(p, "arm_r", 6)
p:recover_health()
b = Buffs.Current()
T("basic: 60 s whatever was healed", b and b.seconds == 60, b and b.seconds)
T("basic: half values", near(Body.StaminaMul(), 1.25) and near(pm:critical_hit_chance(), 0.08)
  and near(PDTI.Carry.LoadRelief(), 0.125) and near(Body.RecoilMul(), 0.925)
  and near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1.075), Body.RecoilMul())
T("basic: no two-limb scaling", near(BaseInteractionExt._get_timer({}), 4 / 1.0625))
T("basic: calm halves the shake", pm:upgrade_value("player", "damage_shake_multiplier", 1) == 0.5)
PD.pushes = {}
p:damage_melee({ damage = 0, push_vel = 10 })
T("basic: steady legs halves... to 75% of the push", near(PD.pushes[1], 7.5))
Buffs.random = function() return 0.4 end
p.tased = 0
p:damage_tase({})
T("basic: half of the tases are ignored (roll 0.4)", p.tased == 0)
Buffs.random = function() return 0.6 end
p:damage_tase({})
T("basic: the other half are not (roll 0.6)", p.tased == 1)
CoreEnvironmentControllerManager.set_flashbang(env, nil, nil, nil, nil, 2)
T("basic: the flash lasts half as long", env.duration == 1)
-- Without the skill.
own(nil)
p = player()
shoot(p, "arm_l", 6)
p:recover_health()
T("without Combat Doctor a doctor bag only heals", Buffs.Current() == nil and near(hp("arm_l"), 6))
own("medic_2x", 2)
PDTI.Ammo.settings.body_parts = false
T("with body parts off: no buff system", Buffs.Owned() == false)
PDTI.Ammo.settings.body_parts = true
-- The replenish at spawn is no doctor bag.
p = player()
shoot(p, "arm_l", 6)
p:replenish()
T("a full refill (replenish) gives no buff", Buffs.Current() == nil)
T("the health window shows the buff", (function()
  shoot(p, "arm_l", 6); p:recover_health()
  for _, l in ipairs(Body.EffectLines()) do if l:find("Doctor's orders") then return true end end
  return false
end)())

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
