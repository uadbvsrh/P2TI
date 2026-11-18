-- 0.27.0: the Yakuza perk deck by black limbs (perk_yakuza.lua) and this
-- mod's buffs in Extra Heist Info (ehi_buffs.lua).
--   luajit tests/yakuza_ehi_tests.lua
local script = arg and arg[0] or "tests/yakuza_ehi_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_yakuza") .. "/")
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

local clock = 100
_G.TimerManager = { game = function() return { time = function() return clock end } end }

local owned = {}
_G.PlayerManager = {}
function PlayerManager:upgrade_value(cat, up, default)
  local v = owned[cat .. "." .. up]
  if v == nil then return default or 0 end
  return v
end
function PlayerManager:has_category_upgrade(cat, up) return owned[cat .. "." .. up] ~= nil end
function PlayerManager:upgrade_level() return 0 end
-- The game's: 1 - health ratio / threshold (0.5).
function PlayerManager:get_damage_health_ratio(health_ratio, category)
  return math.max(0, 1 - health_ratio / 0.5)
end
function PlayerManager:modify_value(key, value) return value end
local unit = {}
local pm = setmetatable({ player_unit = function() return unit end }, { __index = PlayerManager })
_G.managers = _G.managers or {}
managers.player = pm
managers.hud = { show_hint = function() end, set_player_health = function() end, set_max_stamina = function() end }
_G.CopDamage = {}
function CopDamage:damage_melee() end
function CopDamage:damage_bullet() end

-- Extra Heist Info: its callbacks, its buff classes, its buff manager.
local callbacks = {}
_G.EHI = { AddCallback = function(_, id, f) callbacks[id] = callbacks[id] or {}; table.insert(callbacks[id], f) end }
local Refresh = {}
Refresh.__index = Refresh
function Refresh:PreUpdate() self._player_manager = managers.player; self.base_pre = true end
function Refresh:ActivateSoft() self.visible = true end
function Refresh:DeactivateSoft() self.visible = false end
function Refresh:SetRatio(r) self._ratio = r end
function Refresh:SetPersistent() self._persistent = true end
function Refresh:CanActivateUpdateLoop() self.loop = true end
function Refresh:delete_with_class() self.deleted = true end
_G.EHISkillRefreshBuffTracker = Refresh
local function subclass() local c = setmetatable({}, { __index = Refresh }); c.__index = c; return c end
_G.EHIYakuzaBuffTracker = subclass()
function EHIYakuzaBuffTracker:UpdateValue() self.vanilla = true end
_G.EHIBerserkerBuffTracker = subclass()
function EHIBerserkerBuffTracker:PreUpdate() self.vanilla_pre = true; self:delete_with_class() end
function EHIBerserkerBuffTracker:UpdateValue() self.vanilla = true end

tweak_data.skilltree = { skills = { fast_fire = { icon_xy = { 3, 4 } }, medic_2x = { icon_xy = { 5, 6 } } } }
tweak_data.ehi = { buff = {} }

dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/armour.lua")
local Body = PDTI.Body
Body.clock = function() return clock end
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_medic.lua")
dofile(ROOT .. "lua/doctor_buffs.lua")
dofile(ROOT .. "lua/skills_ap.lua")
dofile(ROOT .. "lua/skills_brawler.lua")
dofile(ROOT .. "lua/perk_yakuza.lua")
dofile(ROOT .. "lua/ehi_buffs.lua")
-- Silent Killer's timers (its module needs the ammo system's guns).
PDTI.SilentKiller = PDTI.SilentKiller or { state = { momentum_until = 0, ignite_until = 0 }, now = function() return clock end }
local Skills, Y, E = PDTI.Skills, PDTI.Yakuza, PDTI.EHIBuffs
local steps = {}
Skills.step_of = function(id) return steps[id] or 0 end
Skills.known = function() return true end
local function own(list) steps = {}; for id, s in pairs(list or {}) do steps[id] = s end end

T("the body hooks are in place", Body.InstallHooks() == true)
T("the skill hooks are in place", Skills.Install() == true)

local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }
local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local function player()
  Body.OnHeistStart()
  PDTI.DoctorBuffs.OnHeistStart()
  local p = setmetatable({ max = 44, _health = 44, downed = false }, PD)
  unit.character_damage = function() return p end
  Body.AttachPlayer()
  return p
end
-- Exactly what the part holds: black, nothing spills.
local function blacken(p, part) rolls = { ROLL[part] }; p:damage_bullet({ damage = Body.HP(part) }) end
local function ratio(cat, h) return pm:get_damage_health_ratio(h or 1, cat or "armor_regen") end

------------------------------------------------------------- Yakuza

own({})
owned = {}
local p = player()
T("no Yakuza: the game's ratio", near(ratio("armor_regen", 0.25), 0.5))
owned["player.armor_regen_damage_health_ratio_multiplier"] = 0.6
owned["player.movement_speed_damage_health_ratio_multiplier"] = 0.2
T("Yakuza, nothing black: no bonus", near(ratio("armor_regen"), 0) and near(ratio("movement_speed"), 0))
T("Yakuza: low health alone gives nothing", near(ratio("armor_regen", 0.05), 0))
blacken(p, "arm_l")
T("one black arm: a quarter", Body.IsBlack("arm_l") and near(ratio("armor_regen"), 0.25), ratio("armor_regen"))
T("the speed scales the same", near(ratio("movement_speed"), 0.25))
blacken(p, "leg_r")
T("two black limbs: a half", near(ratio("armor_regen"), 0.5))
blacken(p, "body")
T("a black body is not a limb", Body.IsBlack("body") and near(ratio("armor_regen"), 0.5))
blacken(p, "arm_r")
blacken(p, "leg_l")
T("four black limbs: the full bonus", near(ratio("armor_regen"), 1) and Y.BlackLimbs() == 4)
T("other categories: the game's", near(ratio("melee", 0.25), 0.5))
owned["player.armor_regen_damage_health_ratio_threshold_multiplier"] = 2
p = player()
blacken(p, "leg_l")
T("card 9: one black limb is half", near(ratio("armor_regen"), 0.5))
blacken(p, "arm_l")
T("card 9: two give the full bonus", near(ratio("armor_regen"), 1))
blacken(p, "arm_r")
T("card 9: never more than full", near(ratio("armor_regen"), 1))
owned["player.armor_regen_damage_health_ratio_threshold_multiplier"] = nil
p:recover_health()
T("a doctor bag fills them: the bonus goes", near(ratio("armor_regen"), 0) and Y.BlackLimbs() == 0)
own({ fast_learner = 2 })
p = player()
blacken(p, "arm_l")
T("black under Painkillers' suspension counts", Body.Suspended("arm_l") and near(ratio("armor_regen"), 0.25))
own({ frenzy = 1 })
p = player()
T("with Frenzy the limbs start black: full", near(ratio("armor_regen"), 1))
own({})
p = player()
blacken(p, "arm_l")
PDTI.Ammo.settings.body_parts = false
T("body parts off: the vanilla deck", near(ratio("armor_regen", 0.25), 0.5) and near(ratio("armor_regen", 1), 0))
PDTI.Ammo.settings.body_parts = true
_G.restoration = {}
T("restoration-mod: the vanilla deck", near(ratio("armor_regen", 0.25), 0.5))
_G.restoration = nil
T("the deck has its texts", Skills.texts.menu_deck12_1_desc and Skills.texts.menu_deck12_9_desc
  and Skills.texts.menu_st_spec_12_desc and true)

---------------------------------------------------- EHI: the definitions

T("registered with EHI's BuffsInit", callbacks.BuffsInit and #callbacks.BuffsInit == 1)
for _, f in ipairs(callbacks.BuffsInit) do f() end
local defs = tweak_data.ehi.buff
T("every buff is defined", defs.PDTI_Barrier and defs.PDTI_BarrierCooldown and defs.PDTI_Doctor and defs.PDTI_Painkillers
  and defs.PDTI_Overheal and defs.PDTI_Momentum and defs.PDTI_Ignite and true)
T("the icon is the skill's", defs.PDTI_Barrier.u100skill[1] == 3 and defs.PDTI_Barrier.u100skill[2] == 4)
T("gauges and timers", defs.PDTI_Barrier.class == "EHIGaugeBuffTracker" and defs.PDTI_Doctor.class == nil)
T("no EHI option: always created", defs.PDTI_Doctor.option == nil and defs.PDTI_Doctor.deck_option == nil)
T("the cooldown in EHI's cooldown colour", defs.PDTI_BarrierCooldown.group == "cooldown")

-------------------------------------------------------- EHI: the bar

local calls = {}
local mgr = { _buffs = {} }
for id in pairs(defs) do mgr._buffs[id] = { _active = false, _time = 0 } end
function mgr:AddBuff(id, t)
  calls[#calls + 1] = { "add", id, t }
  local b = self._buffs[id]; b._active = true; b._time = t
end
function mgr:AddGauge(id, r, v)
  calls[#calls + 1] = { "gauge", id, r, v }
  local b = self._buffs[id]
  if b._active and b._ratio == r then return end
  b._active = true; b._ratio = r; b.value = v
end
function mgr:RemoveBuff(id)
  calls[#calls + 1] = { "remove", id }
  self._buffs[id]._active = false
end
managers.ehi_buff = mgr
local function last(id)
  for i = #calls, 1, -1 do if calls[i][2] == id then return calls[i] end end
end
local function poll() calls = {}; E.Poll(true) end

own({})
p = player()
poll()
T("nothing in force: nothing shown", #calls == 0, #calls)

-- Stacked Barrier.
own({ fast_fire = 1 })
PDTI.Barrier.OnHeistStart()
PDTI.Barrier.OnApHit(true)
poll()
local g = last("PDTI_Barrier")
T("the barrier: a gauge with its value", g and g[1] == "gauge" and near(g[3], 0.2) and g[4] == 10, g and g[4])
clock = clock + 3.1
poll()
T("faded: the gauge goes", last("PDTI_Barrier") and last("PDTI_Barrier")[1] == "remove")
local cd = last("PDTI_BarrierCooldown")
T("then its cooldown: 10 s", cd and cd[1] == "add" and near(cd[3], 10, 0.01), cd and cd[3])
mgr._buffs.PDTI_BarrierCooldown._time = 9.9
clock = clock + 0.1
poll()
T("a timer running is left to EHI", last("PDTI_BarrierCooldown") == nil)
clock = clock + 10
poll()
T("the cooldown over: removed", last("PDTI_BarrierCooldown") and last("PDTI_BarrierCooldown")[1] == "remove")

-- Doctor's orders.
own({ medic_2x = 2 })
PDTI.DoctorBuffs.OnDoctorBag({ "arm_l", "leg_l" })
poll()
local d = last("PDTI_Doctor")
T("Combat Doctor ace, 2 parts: 120 s", d and d[1] == "add" and near(d[3], 120), d and d[3])
mgr._buffs.PDTI_Doctor._time = 50
clock = clock + 70
PDTI.DoctorBuffs.OnDoctorBag({ "arm_l" })
poll()
d = last("PDTI_Doctor")
T("a new buff: the timer is set again", d and d[1] == "add" and near(d[3], 60), d and d[3])
clock = clock + 61
poll()
T("over: removed", last("PDTI_Doctor") and last("PDTI_Doctor")[1] == "remove")

-- Painkillers.
own({ fast_learner = 2 })
p = player()
blacken(p, "arm_l")
clock = clock + 5
blacken(p, "leg_l")
poll()
local pk = last("PDTI_Painkillers")
T("Painkillers: the longest suspension left", pk and near(pk[3], 40), pk and pk[3])
clock = clock + 41
poll()
T("Painkillers over: removed", last("PDTI_Painkillers") and last("PDTI_Painkillers")[1] == "remove")

-- Overheal.
own({ tea_time = 2 })
p = player()
Body.state.over.head = 0.5
poll()
local o = last("PDTI_Overheal")
T("Overheal: a gauge with the amount", o and o[1] == "gauge" and o[4] == 5, o and o[4])
Body.state.over.head = 0.3
poll()
T("a new amount is shown", mgr._buffs.PDTI_Overheal.value == 3, mgr._buffs.PDTI_Overheal.value)
Body.state.over.head = 0
poll()
T("no overheal: removed", last("PDTI_Overheal") and last("PDTI_Overheal")[1] == "remove")

-- Silent Killer's timers.
local SK = PDTI.SilentKiller
SK.state.momentum_until = SK.now() + 3
SK.state.ignite_until = SK.now() + 2
poll()
T("Momentum and Ignite", last("PDTI_Momentum") and near(last("PDTI_Momentum")[3], 3)
  and last("PDTI_Ignite") and near(last("PDTI_Ignite")[3], 2))
SK.state.momentum_until, SK.state.ignite_until = 0, 0

-- Throttle and fallbacks.
calls = {}
E.Poll()
E.Poll()
T("polled at most every 0.1 s", #calls <= 2)
managers.ehi_buff = nil
T("without EHI's bar: nothing breaks", pcall(E.Poll, true))
managers.ehi_buff = mgr

-------------------------------------------- EHI: Yakuza and Berserker

owned = { ["player.armor_regen_damage_health_ratio_multiplier"] = 0.6,
  ["player.movement_speed_damage_health_ratio_multiplier"] = 0.2 }
own({})
p = player()
blacken(p, "arm_l")
blacken(p, "leg_l")
local yt = setmetatable({ _armor_regen_multiplier = 0.6, _movement_multiplier = 0.2, _persistent = true }, EHIYakuzaBuffTracker)
yt:UpdateValue()
T("EHI's Yakuza: by black limbs", near(yt._ratio, 0.5) and near(yt._current_armor_regen_multiplier, 1.3)
  and near(yt._current_movement_multiplier, 1.1) and not yt.vanilla, yt._ratio)
PDTI.Ammo.settings.body_parts = false
yt:UpdateValue()
T("EHI's Yakuza, body parts off: EHI's own", yt.vanilla == true)
PDTI.Ammo.settings.body_parts = true

own({ wolverine = 2 })
local bt = setmetatable({ _text_format = "$dmg;$postfix; $mle;$postfix;" }, EHIBerserkerBuffTracker)
bt:PreUpdate()
T("EHI's Berserker is kept (the vanilla upgrades are off)", not bt.deleted and bt.loop and bt._persistent)
bt:UpdateValue()
T("EHI's Berserker: +10% a black part, bullets with the ace", near(bt._current_melee_damage_multiplier, 1.2)
  and near(bt._current_damage_multiplier, 1.2) and near(bt._ratio, 0.4), bt._current_melee_damage_multiplier)
own({ wolverine = 1 })
local bt2 = setmetatable({ _text_format = "$dmg;$postfix;" }, EHIBerserkerBuffTracker)
bt2:PreUpdate()
T("basic, bullets-only display: removed (no bullet bonus)", bt2.deleted == true)
own({})
local bt3 = setmetatable({ _text_format = "$dmg;$postfix; $mle;$postfix;" }, EHIBerserkerBuffTracker)
bt3:PreUpdate()
T("no Berserker: EHI's own check", bt3.vanilla_pre == true)
owned = {}

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
