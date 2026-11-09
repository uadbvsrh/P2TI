-- 0.18.0: health per body part.
--   luajit tests/body_tests.lua
local script = arg and arg[0] or "tests/body_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_body") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Application = _G.Application or {}
Application.digest_value = function(_, v) return v end
Application.time = Application.time or function() return os.clock() end

-- The game's PlayerDamage, the parts the mod uses, as the game does them.
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
function PD:_calc_health_damage(a)
  self:change_health(-a.damage)
  self:_check_bleed_out()
end
function PD:_calc_armor_damage(a)
  local take = math.min(self.armor, a.damage)
  self.armor = self.armor - take
  a.damage = a.damage - take
end
function PD:damage_bullet(a) self:_calc_armor_damage(a); if a.damage > 0 then self:_calc_health_damage(a) end end
function PD:damage_melee(a) self:damage_bullet(a) end
function PD:damage_fall(a) self:_calc_health_damage(a) end
function PD:damage_explosion(a) self:_calc_health_damage(a) end
function PD:band_aid_health() self:change_health(self:_max_health()) end
function PD:revive() self.downed = false; self:set_health(self.max * 0.4) end
function PD:_regenerated() self:set_health(self:_max_health()) end
function PD:recover_health()
  if self:need_revive() then self:revive(true) end
  self:_regenerated()
end
function PD:replenish() self:recover_health() end

-- Movement and weapons.
_G.PlayerMovement = { _max_stamina = function() return 50 end }
local sprints = 0
PlayerStandard._start_action_running = function() sprints = sprints + 1 end
PlayerStandard._check_action_run = function() end
NewRaycastWeaponBase.recoil_multiplier = function() return 1 end
NewRaycastWeaponBase.spread_multiplier = function() return 1 end

dofile(ROOT .. "lua/body.lua")
local Body = PDTI.Body

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end

T("the hooks are in place", Body.InstallHooks() == true)

-- Max health 44: every share is a tenth of Tarkov's HP (head 3.5, body
-- 15.5, arms 6, legs 6.5).
local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local function player()
  Body.OnHeistStart()
  downs = 0
  local pd = setmetatable({ max = 44, _health = 44, armor = 0, downed = false }, PD)
  return pd
end
-- A roll that lands on a part, for the bullet weights (head .06, body .42,
-- arms .12, legs .14).
local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }
local function shoot(pd, part, dmg)
  rolls = { ROLL[part] }
  pd:damage_bullet({ damage = dmg })
end
local function hp(id) return Body.HP(id) end
local function sum_ok(pd) return near(pd._health, Body.Sum(), 1e-6) end

------------------------------------------------------------- where it lands

local pd = player()
shoot(pd, "arm_l", 2)
T("a bullet on the left arm hurts only the left arm", near(hp("arm_l"), 4) and near(hp("body"), 15.5)
  and near(hp("head"), 3.5) and near(hp("leg_l"), 6.5), hp("arm_l"))
T("the game's health is the sum of the parts", sum_ok(pd) and near(pd._health, 42), pd._health)

-- The armour takes it first.
pd.armor = 5
shoot(pd, "arm_l", 3)
T("the armour stops a hit, the parts keep their health", near(hp("arm_l"), 4) and pd.armor == 2)
pd.armor = 0

-- The left arm goes black: what is left over goes on at 70%.
shoot(pd, "arm_l", 9)
T("the arm is black", Body.IsBlack("arm_l"))
-- 5 over, 3.5 spread over the five other parts, 0.7 each.
T("the rest spreads at 70% over the others", near(hp("body"), 14.8) and near(hp("head"), 2.8)
  and near(hp("arm_r"), 5.3), hp("body"))
T("still the sum", sum_ok(pd), pd._health .. " " .. Body.Sum())
shoot(pd, "arm_l", 5)
T("a hit on a black arm spreads too", Body.IsBlack("arm_l") and near(hp("body"), 14.1) and near(hp("leg_r"), 5.1),
  hp("body"))
T("not down while the head lives", downs == 0 and not pd.downed)

-- Fall: the legs. Explosion: every part by share.
pd = player()
rolls = { 0.2 }
pd:damage_fall({ damage = 3 })
T("a fall hurts a leg", near(hp("leg_l"), 3.5) and near(hp("leg_r"), 6.5) and near(hp("body"), 15.5))
pd = player()
pd:damage_explosion({ damage = 4.4 })
T("an explosion spreads by share", near(hp("head"), 3.15) and near(hp("body"), 13.95) and near(hp("leg_l"), 5.85),
  hp("head"))
T("still the sum", sum_ok(pd))

------------------------------------------------------------------- the head

pd = player()
shoot(pd, "head", 4)
T("the head at 0: you go down", downs == 1 and pd.downed and pd._health == 0, pd._health)
T("though the other parts still have health", Body.Sum() > 30, Body.Sum())
pd:revive()
T("revived: the head has 1 HP on the screen", near(hp("head"), 0.1) and not pd.downed, hp("head"))
T("the rest as it was", near(hp("body"), 15.5 - 0.1, 0.2) and sum_ok(pd), hp("body"))

-- A black arm stays black after a revive.
pd = player()
shoot(pd, "arm_r", 6)
shoot(pd, "head", 3.5)
T("down again", pd.downed)
pd:revive()
T("a black arm stays black after a revive", Body.IsBlack("arm_r") and near(hp("head"), 0.1))

------------------------------------------------------------------- healing

pd = player()
shoot(pd, "arm_l", 6)       -- black
shoot(pd, "body", 5)
pd:band_aid_health()
T("a first aid kit heals what is not black", near(hp("body"), 15.5) and near(hp("head"), 3.5))
T("but not a black arm", Body.IsBlack("arm_l"))
T("and the game's health agrees", sum_ok(pd) and near(pd._health, 38), pd._health)
pd:change_health(2)  -- a skill heals
T("skills do not heal black parts either", Body.IsBlack("arm_l"))
pd:recover_health()  -- the medic bag
T("a medic bag heals every part, black ones too", near(hp("arm_l"), 6) and near(pd._health, 44), pd._health)

-- Down, then a medic bag gets you up: full.
pd = player()
shoot(pd, "leg_l", 7)
shoot(pd, "head", 4)
T("down", pd.downed)
pd:recover_health()
T("a medic bag while down: up with every part full", not pd.downed and near(pd._health, 44) and not Body.IsBlack("leg_l"),
  pd._health)

-- The medical rig: getting up with its medic bag.
pd = player()
shoot(pd, "leg_r", 7)
shoot(pd, "head", 4)
Body.FullOnNextRevive()
pd:revive()
T("getting up with the medical rig's medic bag: every part full", near(pd._health, 44) and not Body.IsBlack("leg_r"))

-------------------------------------------------------------------- effects

pd = player()
local player_unit = ENV.make_unit()
local mine = { _setup = { user_unit = player_unit } }
local theirs = { _setup = { user_unit = {} } }
shoot(pd, "arm_l", 7)
T("one black arm: more recoil", near(NewRaycastWeaponBase.recoil_multiplier(mine), 1.35))
T("and spread", near(NewRaycastWeaponBase.spread_multiplier(mine), 1.25))
shoot(pd, "arm_r", 7)
T("two black arms: both", near(NewRaycastWeaponBase.recoil_multiplier(mine), 1.35 ^ 2))
T("only your own weapon", NewRaycastWeaponBase.recoil_multiplier(theirs) == 1)

pd = player()
PlayerStandard._start_action_running({})
T("sprinting with healthy legs", sprints == 1)
T("full speed", Body.SpeedFactor() == 1)
shoot(pd, "leg_l", 7)
PlayerStandard._start_action_running({})
T("a black leg: no sprinting", sprints == 1)
T("and slower", near(Body.SpeedFactor(), 0.85))
T("the speed on the screen has it", near(PDTI.Carry.GetBreakdown().legs, 0.85))
shoot(pd, "leg_r", 7)
T("two black legs: slower still", near(Body.SpeedFactor(), 0.7225))

pd = player()
T("full stamina", PlayerMovement._max_stamina({}) == 50)
shoot(pd, "body", 16)
T("a black body: half the stamina", PlayerMovement._max_stamina({}) == 25)

------------------------------------------- a higher max health (skills, perks)

-- The game's own rescale when the max health changes (as in the game).
function PD:_check_update_max_health()
  self._current_max_health = self._current_max_health or self:_max_health()
  if self._current_max_health ~= self:_max_health() then
    self._health = math.max(0, math.min(self:_max_health(), self._health * self:_max_health() / self._current_max_health))
    self._current_max_health = self:_max_health()
  end
end
local real_change = PD.change_health
-- The game's change_health rescales first, then sets.
PD.change_health = function(self, d)
  self:_check_update_max_health()
  return self:set_health(self:get_real_health() + d)
end
Body.InstallHooks()

do
  -- A Stoic-like build: 66 health (660 on the screen), never hit yet.
  Body.OnHeistStart()
  local stoic = setmetatable({ max = 66, _health = 66, armor = 0, downed = false }, PD)
  local unit = ENV.make_unit()
  function unit:character_damage() return stoic end
  Body.UpdateHud()
  T("before the first hit the parts already have the build's health", near(Body.Sum(), 66)
    and Body.ShownMax("head") == math.floor(66 * 35 / 440 * 10 + 0.5), Body.Sum())
  T("the body's maximum follows it", near(Body.PartMax("body"), 66 * 155 / 440))
  shoot(stoic, "body", 10)
  T("a hit takes from those parts", near(Body.HP("body"), 66 * 155 / 440 - 10) and near(stoic._health, 56), stoic._health)

  -- The max health goes up in the heist (from 66 to 88): the game scales
  -- the health up, the parts keep their share.
  stoic.max = 88
  Body.UpdateHud()
  T("a higher max health in the heist: the parts grow with it", near(Body.Sum(), 56 * 88 / 66, 1e-6)
    and near(Body.PartMax("body"), 88 * 155 / 440), Body.Sum())
  shoot(stoic, "body", 5)
  T("and the game's health still is the sum after the next hit", sum_ok(stoic)
    and near(stoic._health, 56 * 88 / 66 - 5), stoic._health .. " / " .. Body.Sum())

  -- The same change seen first in a hit (no frame in between).
  stoic.max = 110
  shoot(stoic, "body", 5)
  T("a change seen first in a hit: the game's rescale is not counted twice", sum_ok(stoic)
    and near(stoic._health, (56 * 88 / 66 - 5) * 110 / 88 - 5), stoic._health .. " / " .. Body.Sum())
  function unit:character_damage() return nil end
end
PD.change_health = real_change
PD._check_update_max_health = nil

---------------------------------------------------------------- the rest

-- A deadly fall, a kill zone: the game sets the health to 0.
pd = player()
rolls = { 0.2 }
-- (with no spread, so only the rule itself can put you down)
local spread = Body.EFFECTS.spread_damage
Body.EFFECTS.spread_damage = 0
pd._pdti_hit = "leg_l"
pd:set_health(0)
pd._pdti_hit = nil
Body.EFFECTS.spread_damage = spread
pd:_check_bleed_out()
T("health set to 0 by the game: you go down", pd.downed and pd._health == 0 and Body.HeadDown())

-- Frenzy: the max health is lowered, the parts follow.
pd = player()
pd._max_health_reduction = 0.5
pd._health = 22
pd:change_health(-0.0001)
T("a lowered max health: the parts are measured against it", near(Body.Sum(), 22, 0.01)
  and near(Body.HP("head"), 1.75, 0.01), Body.Sum())
pd._max_health_reduction = nil

pd = player()
shoot(pd, "body", 5)
pd.max = 88
pd:change_health(-0.0001)
T("a higher max health keeps the parts' share", near(Body.HP("arm_l"), 12, 0.01), Body.HP("arm_l"))

pd = player()
PDTI.Ammo.settings.body_parts = false
shoot(pd, "head", 10)
T("turned off: the game's own health", pd._health == 34 and downs == 0)
T("and no effects", Body.SpeedFactor() == 1 and Body.Active() == false)
PDTI.Ammo.settings.body_parts = true

-- The open inventory screen is drawn again when a part changes, at most
-- every 0.25 s.
do
  local clock, redraws = 10, 0
  local real_time = Application.time
  Application.time = function() return clock end
  PDTI.IsUIOpen = function() return true end
  PDTI.RedrawUI = function() redraws = redraws + 1; Body.ui_revision = Body.state.revision end
  pd = player()
  Body.UpdateHud()
  local first = redraws
  shoot(pd, "body", 1)
  clock = clock + 0.3
  Body.UpdateHud()
  T("the screen is drawn again after a hit", redraws == first + 1, redraws)
  shoot(pd, "body", 1)
  clock = clock + 0.1
  Body.UpdateHud()
  T("but not more often than every 0.25 s", redraws == first + 1, redraws)
  clock = clock + 0.2
  Body.UpdateHud()
  T("then it is", redraws == first + 2, redraws)
  Body.UpdateHud()
  T("and not when nothing changed", redraws == first + 2, redraws)
  PDTI.IsUIOpen = function() return false end
  Application.time = real_time
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
