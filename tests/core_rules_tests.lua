-- 0.22.0: the core rules of the skill rework (SKILLS_REWORK_SPEC.md).
--   R1 a black part's damage goes at 75% to the body, then to the head
--   R2 first aid kits never heal black parts
--   R3 ECM durations x0.5 (15 s at most), not with restoration-mod
--   R4 weight costs concealment: 1 point per 3 kg over 15 kg
--   R5 ammo boxes stay at two stacks
--   R6 the game's deployable quantity upgrades do not count
--   luajit tests/core_rules_tests.lua
local script = arg and arg[0] or "tests/core_rules_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_core_rules") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Application = _G.Application or {}
Application.digest_value = function(_, v) return v end
Application.time = Application.time or function() return os.clock() end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end

------------------------------------------------------------- R1, R2: the body

local downs = 0
_G.PlayerDamage = {}
local PD = PlayerDamage
PD.__index = PD
function PD:_max_health() return self.max end
function PD:get_real_health() return self._health end
function PD:set_health(h) self._health = math.max(0, math.min(self.max, h)) end
function PD:change_health(d) self:set_health(self._health + d) end
function PD:need_revive() return self.downed end
function PD:_check_bleed_out()
  if self._health <= 0 and not self.downed then self.downed = true; downs = downs + 1 end
end
function PD:_calc_health_damage(a) self:change_health(-a.damage); self:_check_bleed_out() end
function PD:damage_bullet(a) if a.damage > 0 then self:_calc_health_damage(a) end end
function PD:damage_melee(a) self:damage_bullet(a) end
function PD:damage_fall(a) self:_calc_health_damage(a) end
function PD:damage_explosion(a) self:_calc_health_damage(a) end
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
dofile(ROOT .. "lua/body.lua")
local Body = PDTI.Body
T("the body hooks are in place", Body.InstallHooks() == true)

-- Max 44: head 3.5, body 15.5, arms 6, legs 6.5.
local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }
local function player()
  Body.OnHeistStart()
  downs = 0
  return setmetatable({ max = 44, _health = 44, armor = 0, downed = false }, PD)
end
local function shoot(pd, part, dmg) rolls = { ROLL[part] }; pd:damage_bullet({ damage = dmg }) end
local function hp(id) return Body.HP(id) end
local function untouched(ids)
  local full = { head = 3.5, body = 15.5, arm_l = 6, arm_r = 6, leg_l = 6.5, leg_r = 6.5 }
  for _, id in ipairs(ids) do if not near(hp(id), full[id]) then return false, id .. "=" .. hp(id) end end
  return true
end

local pd = player()
shoot(pd, "arm_l", 6)                 -- black, nothing over
shoot(pd, "arm_l", 4)                 -- 3 to the body
T("R1: a hit on a black arm goes at 75% to the body", near(hp("body"), 12.5), hp("body"))
T("R1: and to nothing else", untouched({ "head", "arm_r", "leg_l", "leg_r" }))
T("R1: the game's health agrees", near(pd._health, Body.Sum()), pd._health .. " " .. Body.Sum())

pd = player()
shoot(pd, "leg_r", 10)                -- 6.5 taken, 3.5 over: 2.625 to the body
T("R1: what a leg cannot take goes to the body", Body.IsBlack("leg_r") and near(hp("body"), 12.875)
  and untouched({ "head", "arm_l", "arm_r", "leg_l" }), hp("body"))

pd = player()
shoot(pd, "body", 15.5)               -- the body black
shoot(pd, "arm_r", 6)                 -- the arm black
shoot(pd, "arm_r", 2)                 -- 1.5 to the head
T("R1: with the body black it goes to the head", near(hp("head"), 2), hp("head"))
T("R1: the other limbs are left alone", untouched({ "arm_l", "leg_l", "leg_r" }))
shoot(pd, "body", 2)                  -- a hit on the black body: 1.5 to the head
T("R1: a hit on the black body goes to the head", near(hp("head"), 0.5) and downs == 0, hp("head"))
shoot(pd, "arm_r", 2)                 -- 1.5 more: the head is black
T("R1: and takes you down when the head is gone", Body.IsBlack("head") and downs == 1 and pd.downed,
  hp("head") .. " downs " .. downs)

pd = player()
shoot(pd, "body", 17.5)               -- 2 over the body: 1.5 to the head
T("R1: what the body cannot take goes to the head", Body.IsBlack("body") and near(hp("head"), 2), hp("head"))

pd = player()
shoot(pd, "leg_l", 6.5)               -- black
pd:damage_explosion({ damage = 4.4 }) -- every part by share; the leg's 0.65 -> 0.4875 to the body
T("R1: an explosion's share on a black part goes to the body",
  near(hp("body"), 15.5 - 1.55 - 0.4875) and near(hp("head"), 3.15) and near(hp("leg_r"), 5.85), hp("body"))

pd = player()
local spill = Body.EFFECTS.spread_damage
T("R1: the rate is 75%", spill == 0.75)
Body.EFFECTS.spread_damage = 0
shoot(pd, "arm_l", 6); shoot(pd, "arm_l", 4)
T("R1: a rate of 0 passes nothing on", near(hp("body"), 15.5))
Body.EFFECTS.spread_damage = spill

-- R2
pd = player()
shoot(pd, "arm_l", 6)                 -- black
shoot(pd, "leg_l", 3)
pd:band_aid_health()
T("R2: a first aid kit heals what is not black", near(hp("leg_l"), 6.5))
T("R2: but never a black part", Body.IsBlack("arm_l"))
pd:recover_health()
T("R2: a doctor bag does", near(hp("arm_l"), 6))

--------------------------------------------------------------------- R3: ECM

local function ecm_tweak()
  tweak_data.upgrades = {
    ecm_jammer_base_battery_life = 20, ecm_jammer_base_low_battery_life = 8,
    ecm_feedback_min_duration = 15, ecm_feedback_max_duration = 20, ecm_jammer_base_range = 2500
  }
end
ecm_tweak()
dofile(ROOT .. "lua/skill_rules.lua")
local Rules = PDTI.Rules
local up = tweak_data.upgrades
T("R3: the jammer lasts 10 s", up.ecm_jammer_base_battery_life == 10, up.ecm_jammer_base_battery_life)
T("R3: 15 s with both duration skills (x1.5)", near(up.ecm_jammer_base_battery_life * 1.5, 15))
T("R3: the low battery and the feedback are halved too", up.ecm_jammer_base_low_battery_life == 4
  and up.ecm_feedback_min_duration == 7.5 and up.ecm_feedback_max_duration == 10)
T("R3: the range is not a duration", up.ecm_jammer_base_range == 2500)
Rules.Install(); Rules.Install()
T("R3: installing again does not halve again", up.ecm_jammer_base_battery_life == 10, up.ecm_jammer_base_battery_life)
ecm_tweak()
_G.restoration = {}
Rules.ApplyEcm()
T("R3: with restoration-mod the ECMs stay as they are", tweak_data.upgrades.ecm_jammer_base_battery_life == 20,
  tweak_data.upgrades.ecm_jammer_base_battery_life)
_G.restoration = nil

-------------------------------------------------------- R4: weight -> concealment

local Carry = PDTI.Carry
local cases = { { 0, 0 }, { 15, 0 }, { 17.9, 0 }, { 18, 1 }, { 30, 5 }, { 45, 10 }, { 60, 15 } }
local all = true
local bad
for _, c in ipairs(cases) do
  if Rules.ConcealmentPenalty(c[1]) ~= c[2] then all = false; bad = c[1] .. " kg -> " .. Rules.ConcealmentPenalty(c[1]) end
end
T("R4: 1 point per 3 kg over 15 kg (30 kg -5, 60 kg -15)", all, bad)

_G.BlackMarketManager = { visibility_modifiers = function() return 2 end }
local weight = 30
local real_weight = Carry.LoadWeight
Carry.LoadWeight = function() return weight end
Rules.InvalidateCache()
T("R4: the concealment hook goes in", Rules.InstallConcealment() == true)
T("R4: the game's visibility plus the weight", BlackMarketManager:visibility_modifiers() == 7,
  BlackMarketManager:visibility_modifiers())
weight = 10
Rules.InvalidateCache()
T("R4: light: only the game's", BlackMarketManager:visibility_modifiers() == 2)
weight = 60
Rules.InvalidateCache()
Carry.enabled = false
T("R4: with the weight penalty off nothing is added", BlackMarketManager:visibility_modifiers() == 2)
Carry.enabled = true
Rules.InvalidateCache()
T("R4: on again: 15 points", BlackMarketManager:visibility_modifiers() == 17)
T("R4: installing again does not add it twice", Rules.InstallConcealment() == true
  and BlackMarketManager:visibility_modifiers() == 17)
_G.restoration = {}
Rules.InvalidateCache()
T("R4: vanilla only: with restoration-mod nothing is added", BlackMarketManager:visibility_modifiers() == 2)
_G.restoration = nil
-- 0.22.1: a failed weight read (the game not ready) keeps the last value.
Rules.InvalidateCache()
T("R4: 60 kg read", BlackMarketManager:visibility_modifiers() == 17)
Carry.LoadWeight = function() error("the game is not ready") end
Rules.CACHE_TIME = -1
T("R4: a failed read keeps the last penalty (not 0)", BlackMarketManager:visibility_modifiers() == 17,
  BlackMarketManager:visibility_modifiers())
Rules.CACHE_TIME = 0.5
-- The menu's detection meter is redrawn when the inventory screen closes.
local redrawn = 0
managers.menu_component = { _player_inventory_gui = { update_detection = function() redrawn = redrawn + 1 end } }
T("R4: the menu's detection meter is redrawn", Rules.RefreshMenuDetection() == true and redrawn == 1)
managers.menu_component = nil
Carry.LoadWeight = real_weight

-- 0.22.1: while the player spawns the game has no grenade count yet; the
-- weight is read without asking for it (the game logged a fatal error).
do
  local asked = false
  local real_bm, real_pm, real_net = managers.blackmarket, managers.player, managers.network
  managers.blackmarket = { equipped_grenade = function() return "frag", 3 end }
  managers.player = { player_unit = function() return {} end, _global = { synced_grenades = {} },
    get_grenade_amount = function(_, peer) asked = true; return managers.player._global.synced_grenades[peer].amount end }
  managers.network = { session = function() return { local_peer = function() return { id = function() return 1 end } end } end }
  local ok = pcall(PDTI.Loadout.Get)
  T("R4: spawning: the throwable count is not asked for before the game has it", ok and not asked)
  managers.player._global.synced_grenades[1] = { amount = 2 }
  pcall(PDTI.Loadout.Get)
  T("R4: and is once it has", asked)
  managers.blackmarket, managers.player, managers.network = real_bm, real_pm, real_net
end

------------------------------------------------------------- R5, R6

_G.Idstring = _G.Idstring or function(s) return "ids:" .. tostring(s) end
_G.AmmoClip = _G.AmmoClip or { _pickup = function() return true end }
dofile(ROOT .. "lua/ammo_hooks.lua")
T("R5: ammo boxes stay at two stacks", PDTI.Ammo.BoxLimit() == 200, PDTI.Ammo.BoxLimit())

for _, c in ipairs({ "rig", "pockets", "backpack" }) do
  for _, it in ipairs(PDTI.GetContainer(c).items) do PDTI.RemoveItem(c, it.instance_id) end
end
_G.managers = _G.managers or {}
managers.player = managers.player or {}
local real_up = managers.player.upgrade_value
managers.player.upgrade_value = function(_, cat, name, default)
  if name == "quantity" or name:find("quantity") then return 5 end
  return default
end
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
T("R6: a quantity upgrade does not add deployables", PDTI.Deployables.Count("ammo_bag") == 1,
  PDTI.Deployables.Count("ammo_bag"))
managers.player.upgrade_value = real_up

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
