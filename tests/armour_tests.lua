-- 0.18.8: light and heavy armour. Heavy armour does not regenerate once
-- broken (a plate fills it), and broken it still takes part of the damage to
-- every body part but the head. Also the colours of the body parts.
--   luajit tests/armour_tests.lua
local script = arg and arg[0] or "tests/armour_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_armour") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.load_mod(ROOT, false)
_G.Application = _G.Application or {}
Application.digest_value = function(_, v) return v end
local clock = 100
Application.time = function() return clock end

-- The game's PlayerDamage, the parts about armour as the game does them.
_G.PlayerDamage = {}
local PD = PlayerDamage
PD.__index = PD
function PD:_max_health() return self.max end
function PD:get_real_health() return self._health end
function PD:set_health(h) self._health = math.max(0, math.min(self.max, h)) end
function PD:change_health(d) self:set_health(self._health + d) end
function PD:need_revive() return self.downed end
function PD:_check_bleed_out() if self._health <= 0 then self.downed = true end end
function PD:_max_armor() return self.max_armor end
function PD:get_real_armor() return self.armor end
function PD:set_armor(a) self.armor = math.max(0, math.min(self.max_armor, a)) end
function PD:change_armor(c) self:set_armor(self.armor + c) end
function PD:restore_armor(a) self:change_armor(a) end
function PD:_regenerate_armor() self:set_armor(self:_max_armor()); self._current_state = nil end
function PD:set_regenerate_timer_to_max() self._regenerate_timer = 3; self._current_state = self._update_regenerate_timer end
function PD:_update_regenerate_timer(t, dt)
  self._regenerate_timer = math.max(self._regenerate_timer - dt, 0)
  if self._regenerate_timer <= 0 then self:_regenerate_armor() end
end
function PD:update(t, dt) if self._current_state then self:_current_state(t, dt) end end
-- As the game: armour up takes the whole hit; an armour-piercing hit passes
-- what the armour did not take on to the health.
function PD:damage_bullet(a)
  local had = self.armor
  if had > 0 then self:change_armor(-a.damage) end
  self:set_regenerate_timer_to_max()
  local rest = had <= 0 and a.damage or (a.armor_piercing and math.max(0, a.damage - had) or 0)
  if rest > 0 then self:change_health(-rest); self:_check_bleed_out() end
end
function PD:damage_explosion(a) self:change_health(-a.damage) end
function PD:revive() self.downed = false; self:set_health(self.max * 0.4); self:_regenerate_armor() end

function PD:damage_melee(a) self:damage_bullet(a) end
function PD:damage_fall(a) self:change_health(-a.damage) end
function PD:recover_health() self:set_health(self.max) end
function PD:replenish() self:recover_health() end
_G.PlayerMovement = { _max_stamina = function() return 50 end }
PlayerStandard._start_action_running = function() end
PlayerStandard._check_action_run = function() end
NewRaycastWeaponBase.recoil_multiplier = function() return 1 end
NewRaycastWeaponBase.spread_multiplier = function() return 1 end
dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/armour.lua")
local Body, Armour = PDTI.Body, PDTI.Armour

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b, eps) return math.abs((a or -999) - b) < (eps or 1e-6) end

T("the body hooks are in place", Body.InstallHooks() == true)
T("the armour hooks are in place", Armour.InstallHooks() == true)

local hints = {}
managers.hud = { show_hint = function(_, p) hints[#hints + 1] = p.text end }
local armour_id = "level_7"
managers.blackmarket = managers.blackmarket or {}
managers.blackmarket.equipped_armor = function() return armour_id end
local player_state = "standard"
managers.player.current_state = function() return player_state end

local rolls = {}
Body.roll = function() return table.remove(rolls, 1) or 0.5 end
local ROLL = { head = 0.03, body = 0.3, arm_l = 0.5, arm_r = 0.6, leg_l = 0.75, leg_r = 0.9 }

-- A player with 44 health (head 3.5, body 15.5, arms 6, legs 6.5) and 10 armour.
local function player(id)
  armour_id = id
  PDTI.Reset()
  PDTI.SetSessionOnly(true)
  Body.OnHeistStart()
  Armour.OnHeistStart()
  player_state = "standard"
  local pd = setmetatable({ max = 44, _health = 44, armor = 10, max_armor = 10, downed = false }, PD)
  local unit = ENV.make_unit()
  function unit:character_damage() return pd end
  hints = {}
  -- The game's first frame: the mod sees the armour before any hit.
  Armour.Tick({}, 0)
  return pd
end
local function shoot(pd, part, dmg)
  rolls = { ROLL[part] }
  pd:damage_bullet({ damage = dmg })
end
local function frames(pd, seconds)
  for _ = 1, math.floor(seconds * 10) do clock = clock + 0.1; pd:update(clock, 0.1); Armour.Tick({}, 0.1) end
end
local function hp(id) return Body.HP(id) end

------------------------------------------------------------- light armour

local pd = player("level_3")
shoot(pd, "body", 12)
T("light armour: the hit breaks it and the health is untouched", pd.armor == 0 and near(pd._health, 44))
shoot(pd, "arm_l", 4)
T("broken light armour protects nothing", near(hp("arm_l"), 2), hp("arm_l"))
frames(pd, 4)
T("light armour regenerates by itself", pd.armor == 10, pd.armor)
T("light armour is never 'broken'", not Armour.IsBroken())

------------------------------------------------------------- heavy armour

pd = player("level_7")
shoot(pd, "body", 12)
frames(pd, 0.2)
T("heavy armour: broken", Armour.IsBroken() and pd.armor == 0)
T("and says so once", #hints >= 1 and tostring(hints[1]):find("plate") ~= nil, hints[1])
frames(pd, 10)
T("it does not regenerate by itself", pd.armor == 0, pd.armor)
T("the regeneration timer is stopped", pd._current_state == nil)
shoot(pd, "arm_l", 4)
T("broken ICTV: an arm takes 75% of the hit", near(hp("arm_l"), 6 - 3), hp("arm_l"))
T("the game's health is still the sum", near(pd._health, Body.Sum()), pd._health)
shoot(pd, "head", 2)
T("the head takes all of it", near(hp("head"), 1.5), hp("head"))
pd:damage_explosion({ damage = 4.4 })
-- An explosion spreads by share: the head 35/440, the rest x0.75.
T("a spread hit spares only the head", near(hp("head"), 1.5 - 0.35) and near(hp("body"), 15.5 - 1.55 * 0.75),
  hp("head") .. " " .. hp("body"))

-- Perks still give armour back.
pd:restore_armor(4)
T("a perk gives armour back on broken heavy armour", pd.armor == 4)
local before = hp("leg_l")
shoot(pd, "leg_l", 3)
T("armour above 0 protects as in the game (no part damage)", near(hp("leg_l"), before))
pd.armor = 1
local leg_before = hp("leg_r")
rolls = { ROLL.leg_r }
pd:damage_bullet({ damage = 3, armor_piercing = true })
T("an AP hit that breaks the last armour: the rest is reduced by the broken vest",
  near(hp("leg_r"), leg_before - 2 * 0.75), hp("leg_r"))
-- Damage straight to the health while a perk keeps armour up (Stoic's
-- delayed damage): no plate reduction.
pd.armor = 4
local body_before = Body.Sum()
pd:change_health(-4.4)
T("health damage while the armour is above 0 is not reduced", near(Body.Sum(), body_before - 4.4), Body.Sum())
frames(pd, 10)
T("but the timer still does not fill it", pd.armor < 10, pd.armor)
pd.armor = 0

-- A revive does not fix it.
pd.downed = true
pd:revive()
T("a revive does not fix broken heavy armour", pd.armor == 0, pd.armor)

-- 0.18.9: an ICTV that reads 0 in the first frame of a heist (before the
-- game filled it, or a deck without armour) is not "broken": the log showed
-- "ICTV broken" at the start of a heist, and the vest never regenerated.
do
  local p = player("level_7")
  Armour.OnHeistStart()
  p.armor = 0
  hints = {}
  Armour.Tick({}, 0.1)
  T("an ICTV at 0 in the first frame is not broken", not Armour.IsBroken() and #hints == 0)
  -- The game's regeneration timer runs (after the spawn or a hit).
  p:set_regenerate_timer_to_max()
  frames(p, 4)
  T("so the game's timer fills it", p.armor == 10, p.armor)
  shoot(p, "body", 12)
  frames(p, 0.2)
  T("and it breaks once a hit empties it", Armour.IsBroken() and p.armor == 0)
  local q = player("level_7")
  Armour.OnHeistStart()
  q.max_armor, q.armor = 0, 0
  frames(q, 1)
  T("a vest with no armour at all is never broken", not Armour.IsBroken())
  shoot(q, "arm_l", 4)
  T("and gives no broken-vest reduction", near(hp("arm_l"), 2), hp("arm_l"))
end

-- The other heavy vests.
for _, case in ipairs({ { "level_5", 0.10 }, { "level_6", 0.18 } }) do
  local p = player(case[1])
  shoot(p, "body", 12)
  shoot(p, "arm_r", 4)
  T(case[1] .. ": broken, an arm takes " .. (1 - case[2]) * 100 .. "%", near(hp("arm_r"), 6 - 4 * (1 - case[2])), hp("arm_r"))
end

------------------------------------------------------------------ plates

pd = player("level_7")
local ok, why = Armour.StartPlate()
T("no plate while the armour is whole", ok == false and tostring(why):find("whole") ~= nil, why)
shoot(pd, "body", 12)
frames(pd, 0.2)
ok, why = Armour.StartPlate()
T("no plate without one", ok == false and tostring(why):find("no armour plates") ~= nil, why)
PDTI.AddItemAuto("backpack", "armor_kit", 1, nil, true)
ok, why = Armour.StartPlate()
T("a plate in the backpack must be moved first", ok == false and tostring(why):find("backpack") ~= nil, why)
PDTI.AddItemAuto("rig", "armor_kit", 1, nil, true)
local function plates()
  local n = 0
  for _, e in ipairs(PDTI.FindItems(function(_, it) return it.item_id == "armor_kit" end)) do n = n + (e.item.amount or 1) end
  return n
end
T("a plate to hand: it starts", Armour.StartPlate() == true)
T("you are slowed while inserting it", near(Body.SpeedFactor(), 0.6), Body.SpeedFactor())
Armour.Tick({ btn_primary_attack_press = true }, 0.1)
T("firing cancels it, the plate is kept", Armour.state.plating == nil and plates() == 2 and pd.armor == 0)
T("and the speed is back", near(Body.SpeedFactor(), 1))
Armour.StartPlate()
frames(pd, 2)
T("not in yet after 2 s", pd.armor == 0 and Armour.state.plating ~= nil)
frames(pd, 1.2)
T("after 3 s the plate is in: the armour is full", pd.armor == 10, pd.armor)
T("one plate is used", plates() == 1, plates())
T("and the armour is not broken any more", not Armour.IsBroken())
shoot(pd, "arm_l", 4)
T("the armour protects again", near(hp("arm_l"), 6) and pd.armor == 6)
frames(pd, 4)
T("and regenerates again while it is not broken", pd.armor == 10, pd.armor)
player_state = "bleed_out"
pd.armor = 5
ok, why = Armour.StartPlate()
T("no plate while down", ok == false, why)
player_state = "standard"

pd = player("level_2")
pd.armor = 0
PDTI.AddItemAuto("rig", "armor_kit", 1, nil, true)
ok, why = Armour.StartPlate()
T("light armour takes no plate", ok == false and tostring(why):find("light") ~= nil, why)

-- The plate in the menu.
T("the plate is something you bring", (function()
  for _, id in ipairs(PDTI.Plan.Items()) do if id == "armor_kit" then return true end end
end)() == true)
T("and it has a price", PDTI.Ammo.UnitPrice("armor_kit") > 0)

-- The setting off: the game's armour.
pd = player("level_7")
PDTI.Ammo.settings.heavy_armour = false
shoot(pd, "body", 12)
frames(pd, 4)
T("the setting off: heavy armour regenerates as in the game", pd.armor == 10, pd.armor)
pd.armor = 0
shoot(pd, "arm_l", 4)
T("and protects nothing once broken", near(hp("arm_l"), 2), hp("arm_l"))
PDTI.Ammo.settings.heavy_armour = true

T("the health window line names the armour", tostring(Armour.StatusLine()):find("ICTV") ~= nil, Armour.StatusLine())

---------------------------------------------------------------- colours

local expect = { { 1.0, "full" }, { 0.9, "dark_green" }, { 0.76, "dark_green" }, { 0.75, "yellow" },
  { 0.6, "yellow" }, { 0.5, "orange" }, { 0.3, "orange" }, { 0.25, "red" }, { 0.1, "red" }, { 0.01, "red" },
  { 0, "black" } }
local wrong = {}
for _, e in ipairs(expect) do
  if Body.ColorName(e[1]) ~= e[2] then wrong[#wrong + 1] = e[1] .. "=" .. Body.ColorName(e[1]) end
end
T("colours: green full, dark green >75%, yellow >50%, orange >25%, red, black at 0", #wrong == 0,
  table.concat(wrong, " "))
T("every colour is distinct", (function()
  local seen = {}
  for _, c in pairs(Body.COLORS) do
    local k = table.concat(c, ",")
    if seen[k] then return false end
    seen[k] = true
  end
  return true
end)())

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
