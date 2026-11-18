-- 0.25.0: Ghost, Silent Killer (SKILLS_REWORK_SPEC.md §7.3).
--   luajit tests/silent_killer_tests.lua
local script = arg and arg[0] or "tests/silent_killer_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_silent_killer") .. "/")
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

----------------------------------------------------------------- vectors

local VM = {}
VM.__index = VM
local function V(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VM) end
VM.__sub = function(a, b) return V(a.x - b.x, a.y - b.y, a.z - b.z) end
mvector3.distance = function(a, b) local d = a - b; return math.sqrt(d.x * d.x + d.y * d.y + d.z * d.z) end
mvector3.normalize = function(v)
  local l = math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if l > 0 then v.x, v.y, v.z = v.x / l, v.y / l, v.z / l end
end
mvector3.dot = function(a, b) return a.x * b.x + a.y * b.y + a.z * b.z end
math.UP = V(0, 0, 1)

---------------------------------------------------------------- the game

local clock = 100
_G.TimerManager = { game = function() return { time = function() return clock end } end }
local hints = {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end
managers.hud.on_crit_confirmed = function() end
managers.hud.set_player_health = function() end
managers.hud.set_max_stamina = function() end

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
function PlayerManager:movement_speed_multiplier() return 1 end
function PlayerManager:modify_value(key, value) return value end
local pm = managers.player
setmetatable(pm, { __index = PlayerManager })

-- The player's body (from the Medic tests).
_G.PlayerDamage = {}
local PD = PlayerDamage
PD.__index = PD
function PD:_max_health() return self.max end
function PD:get_real_health() return self._health end
function PD:get_real_armor() return 0 end
function PD:set_health(h) self._health = math.max(0, math.min(self.max, h)) end
function PD:change_health(d) self:set_health(self._health + d) end
function PD:need_revive() return false end
function PD:_check_bleed_out() end
function PD:damage_bullet(a) self:change_health(-a.damage) end
function PD:damage_melee(a) self:damage_bullet(a) end
_G.PlayerMovement = { _max_stamina = function() return 50 end }
PlayerStandard._start_action_running = function() end
NewRaycastWeaponBase.recoil_multiplier = function() return 1 end
NewRaycastWeaponBase.spread_multiplier = function() return 1 end
NewRaycastWeaponBase._get_current_damage = function(self, m) return 10 * (m or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function() return 0 end

-- Enemies (the parts of vanilla CopDamage that count).
local healed_by_medic = false
_G.CopDamage = {}
local CD = CopDamage
CD.__index = CD
CD.is_civilian = function(name) return name == "civilian" end
function CD:can_be_critical() return true end
function CD:roll_critical_hit(attack_data, damage) return false, damage or attack_data.damage end
function CD:check_medic_heal() return healed_by_medic end
function CD:is_head(body) return body and body.head == true end
function CD:die() self._dead = true end
function CD:_take(attack_data, damage)
  if self._dead then return nil end
  if self._health <= damage then
    if self:check_medic_heal() then
      attack_data.result = { type = "healed" }
      return attack_data.result
    end
    self._health = 0
    self:die(attack_data)
    attack_data.result = { type = "death" }
  else
    self._health = self._health - damage
    attack_data.result = { type = "hurt" }
  end
  self.taken = (self.taken or 0) + damage
  return attack_data.result
end
function CD:damage_bullet(attack_data)
  local damage = attack_data.damage
  if attack_data.attacker_unit == pm:player_unit() then
    local crit, d = self:roll_critical_hit(attack_data, damage)
    if crit then attack_data.critical_hit = true; damage = d end
  end
  return self:_take(attack_data, damage)
end
function CD:damage_explosion(attack_data)
  if attack_data.variant == "stun" then
    self.sick = (self.sick or 0) + 1
    attack_data.result = { type = "hurt_sick" }
    return attack_data.result
  end
  return self:_take(attack_data, attack_data.damage)
end
function CD:damage_fire(attack_data) return self:_take(attack_data, attack_data.damage) end
function CD:damage_melee(attack_data) return self:_take(attack_data, attack_data.damage) end
function CD:stun_hit(attack_data) self.stunned = (self.stunned or 0) + 1 end
_G.SentryGunDamage = {}
local SG = SentryGunDamage
SG.__index = SG
function SG:damage_bullet(a) return CD._take(self, a, a.damage) end
function SG:damage_explosion(a) return CD._take(self, a, a.damage) end
function SG:die() self._dead = true end
function SG:check_medic_heal() return false end

local all_enemies = {}
managers.enemy = { all_enemies = function() return all_enemies end }
local function enemy(tweak, pos, facing, health)
  local unit = { pos = pos or V(0, 0, 0), facing = facing or V(0, 1, 0) }
  local dmg = setmetatable({ _unit = unit, _health = health or 100, _char_tweak = { headshot_dmg_mul = 3 } }, CD)
  unit.base = function() return { _tweak_table = tweak } end
  unit.position = function() return unit.pos end
  unit.rotation = function() return { y = function() return unit.facing end } end
  unit.character_damage = function() return dmg end
  unit.key = function() return tostring(unit) end
  all_enemies[tostring(unit)] = { unit = unit }
  return dmg, unit
end
local function turret(health)
  local unit = { pos = V(0, 0, 0) }
  local dmg = setmetatable({ _unit = unit, _health = health or 100, _char_tweak = {} }, SG)
  unit.base = function() return { _tweak_table = "swat_turret" } end
  unit.position = function() return unit.pos end
  unit.rotation = function() return {} end
  return dmg
end

-- Cop hurt actions (the concussion and the sickness).
_G.CopActionHurt = { init = function(self, desc)
  if desc.hurt_type == "concussion" then self._sick_time = clock + 3 end
  if desc.hurt_type == "hurt_sick" then self._sick_time = clock + 1.5 end
  return true
end }
local function hurt(dmg, kind)
  local action = setmetatable({ _unit = { character_damage = function() return dmg end } }, { __index = CopActionHurt })
  CopActionHurt.init(action, { hurt_type = kind })
  return action
end

local fires = {}
managers.fire = { add_doted_enemy = function(_, unit, t, weapon, length, dot, user) fires[#fires + 1] = { unit = unit, length = length } end }
local spoils = {}
_G.safe_spawn_unit = function(name, pos)
  local clip = { _ammo_box = true }
  local unit = { pos = pos }
  unit.pickup = function() return clip end
  unit.contour = function() return { add = function() end } end
  clip._unit = unit
  function clip:consume() unit.slot = 0 end
  spoils[#spoils + 1] = unit
  return unit
end
tweak_data.pickups = { ammo = { unit = "units/pickups/ammo/ammo_pickup" } }
_G.AmmoClip = { _pickup = function(self, unit) self._picked_up = true; return true end }
_G.AmmoBagBase = { spawn = function() end, sync_setup = function() end, _take_ammo = function() return 0 end,
  take_ammo = function() return false end }
_G.BaseInteractionExt = { _get_timer = function() return 1 end }

dofile(ROOT .. "lua/ammo_hooks.lua")
dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_ammo.lua")
dofile(ROOT .. "lua/skills_silent.lua")
dofile(ROOT .. "lua/skills_ap.lua")

local Ammo, Skills, SK, Body, AS = PDTI.Ammo, PDTI.Skills, PDTI.SilentKiller, PDTI.Body, PDTI.AmmoSkills
local steps = {}
Skills.step_of = function(id) return steps[id] or 0 end
Skills.known = function() return true end
local function own(list) steps = {}; for id, step in pairs(list or {}) do steps[id] = step end end

T("the ammo hooks are in place", Ammo.InstallHooks() == true)
Body.InstallHooks() -- the mock player lacks a few of the game's functions; the ones used here are in
T("the skill hooks are in place", Skills.Install() == true)
T("no part failed", Skills.failed == nil, Skills.failed and next(Skills.failed))

-- A typed gun with a bullet.
local unit
local function gun(name, bullet, capacity)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  AS.OnHeistStart()
  SK.OnHeistStart()
  PDTI.Barrier.OnHeistStart()
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetSessionOnly(true)
  unit = ENV.make_unit()
  unit.position = function() return V(0, -100, 0) end
  local wep = ENV.make_weapon(name or "test_ar", { "wpn_no_part" }, capacity or 30)
  wep._setup = { user_unit = unit }
  local wu = { base = function() return wep end, key = function() return "wep" end }
  wep._unit = wu
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  wep.clip = wep:get_ammo_max_per_clip()
  if bullet then
    Ammo.SetLoaded(wep, { size = "standard", bullet = bullet })
    Ammo.ApplyLoaded(wep)
  end
  Ammo.SyncTotal(wep)
  hints = {}; fires = {}; spoils = {}; all_enemies = {}
  clock = clock + 100
  return wep, wu
end
local ARM = { name = function() return Idstring("rag_LeftArm") end }
local LEG = { name = function() return Idstring("rag_RightLeg") end }
local CHEST = { name = function() return Idstring("Spine1") end }
local HEAD = { name = function() return Idstring("Head") end, head = true }
local function shoot(dmg, wu, body, damage)
  return dmg:damage_bullet({ damage = damage or 10, attacker_unit = unit, weapon_unit = wu,
    variant = "bullet", col_ray = { body = body or CHEST, position = V() } })
end
local function blast(dmg, wu, damage)
  Ammo.he_blast = { weapon = wu }
  local r = dmg:damage_explosion({ damage = damage or 5, attacker_unit = unit, weapon_unit = wu,
    variant = "explosion", col_ray = { position = V(), ray = V(0, 1, 0) } })
  Ammo.he_blast = nil
  return r
end

------------------------------------------------------------ Momentum

do
  local wep, wu = gun("test_ar", "hollow")
  own({})
  local d = enemy("swat")
  shoot(d, wu, ARM)
  T("no Second Wind: no Momentum", pm:movement_speed_multiplier() == 1)
  own({ scavenger = 1 })
  shoot(enemy("swat"), wu, ARM)
  T("an HP limb crit: +10% speed", near(pm:movement_speed_multiplier(), 1.1))
  clock = clock + 3.1
  T("for 3 s", pm:movement_speed_multiplier() == 1)
  shoot(enemy("swat"), wu, CHEST)
  T("an HP body hit is no sure crit", pm:movement_speed_multiplier() == 1)
  local wep2, wu2 = gun("test_ar", "standard")
  own({ scavenger = 1 })
  shoot(enemy("swat"), wu2, ARM)
  T("a standard round on a limb: nothing", pm:movement_speed_multiplier() == 1)
  local lmg, lu = gun("test_smg", nil, 30)
  own({ scavenger = 1 })
  blast(enemy("tank"), lu)
  T("an HE crit on a bulldozer: +10%", near(pm:movement_speed_multiplier(), 1.1))
  clock = clock + 5
  blast(turret(), lu)
  T("on a turret too", near(pm:movement_speed_multiplier(), 1.1))
  clock = clock + 5
  blast(enemy("swat"), lu)
  T("not an HE hit on a cop (no sure crit)", pm:movement_speed_multiplier() == 1)
  owned["player.team_damage_speed_multiplier_send"] = 1
  own({ scavenger = 2 })
  T("ace: the crew speed is off", pm:upgrade_value("player", "team_damage_speed_multiplier_send", 0) == 0)
  Ammo.settings.enabled = false
  T("ammo off: the vanilla ace", pm:upgrade_value("player", "team_damage_speed_multiplier_send", 0) == 1)
  Ammo.settings.enabled = true
  owned["player.team_damage_speed_multiplier_send"] = nil
end

------------------------------------------------------- Second Wind ace

do
  local wep, wu = gun("test_ar", "hollow")
  local info = Ammo.Identify(wep)
  wep.clip = 10
  Ammo.SyncTotal(wep)
  Ammo.AddLooseKey(info.key, 50, info, "hollow")
  own({ scavenger = 2 })
  local d = enemy("swat", nil, nil, 5)
  d:damage_melee({ damage = 10, attacker_unit = unit, variant = "melee", col_ray = { position = V() } })
  T("a melee kill fills the HP magazine from loose HP", wep.clip == 30 and Ammo.LooseOfKey(info.key, "hollow") == 30,
    wep.clip .. "/" .. Ammo.LooseOfKey(info.key, "hollow"))
  wep.clip = 10
  enemy("swat", nil, nil, 50):damage_melee({ damage = 10, attacker_unit = unit, variant = "melee", col_ray = { position = V() } })
  T("not a melee hit that doesn't kill", wep.clip == 10)
  own({ scavenger = 1 })
  enemy("swat", nil, nil, 5):damage_melee({ damage = 10, attacker_unit = unit, variant = "melee", col_ray = { position = V() } })
  T("basic only: nothing", wep.clip == 10)
  local w2 = gun("test_ar", "standard")
  local info2 = Ammo.Identify(w2)
  w2.clip = 10
  Ammo.AddLooseKey(info2.key, 50, info2)
  own({ scavenger = 2 })
  enemy("swat", nil, nil, 5):damage_melee({ damage = 10, attacker_unit = unit, variant = "melee", col_ray = { position = V() } })
  T("standard rounds: nothing", w2.clip == 10)
end

------------------------------------------------------- Optical Illusions

do
  local wep, wu = gun("test_ar", "hollow")
  own({})
  local c = enemy("spooc")
  shoot(c, wu, CHEST)
  T("no skill: an HP body hit on a cloaker is no crit", c.taken == 10)
  own({ optic_illusions = 1 })
  c = enemy("spooc")
  shoot(c, wu, CHEST)
  T("basic: HP always crits cloakers", c.taken == 30, c.taken)
  local cop = enemy("swat")
  shoot(cop, wu, CHEST)
  T("not other enemies", cop.taken == 10)
  owned["player.camouflage_bonus"] = 1
  T("the concealment upgrades are off", pm:upgrade_value("player", "camouflage_bonus", 0) == 0)
  owned["player.camouflage_bonus"] = nil
  -- Ace: the medic.
  healed_by_medic = true
  own({ optic_illusions = 1 })
  local m = enemy("swat", nil, nil, 5)
  shoot(m, wu, ARM)
  T("basic: a medic saves a crit kill", not m._dead)
  own({ optic_illusions = 2 })
  m = enemy("swat", nil, nil, 5)
  shoot(m, wu, ARM)
  T("ace: a crit kill can't be saved", m._dead == true)
  m = enemy("swat", nil, nil, 5)
  shoot(m, wu, CHEST)
  T("a kill that is no crit can", not m._dead)
  healed_by_medic = false
end

------------------------------------------------------- The Professional

do
  local lmg, lu = gun("test_smg", nil, 30)
  own({})
  local d = enemy("swat")
  blast(d, lu, 1)
  local a = hurt(d, "concussion")
  T("an HE hit stuns", d.stunned == 1)
  T("no skill: the game's 3 s", near(a._sick_time, clock + 3))
  own({ silence_expert = 1 })
  d = enemy("swat")
  blast(d, lu, 1)
  a = hurt(d, "concussion")
  T("Concussive: 4.5 s", near(a._sick_time, clock + 4.5), a._sick_time - clock)
  local before = d.taken
  shoot(d, lu, CHEST, 10)
  T("basic: no damage bonus", d.taken - before == 10)
  own({ silence_expert = 2 })
  before = d.taken
  shoot(d, lu, CHEST, 10)
  T("ace: a stunned enemy takes +20%", near(d.taken - before, 12), d.taken - before)
  local other = enemy("swat")
  shoot(other, lu, CHEST, 10)
  T("not one that isn't stunned", other.taken == 10)
  clock = clock + 5
  before = d.taken
  shoot(d, lu, CHEST, 10)
  T("the stun ends", d.taken - before == 10)
end

------------------------------------------------------------ Low Blow

do
  local wep, wu = gun("test_ar", "hollow")
  local p = setmetatable({ max = 44, _health = 44 }, PD)
  unit.character_damage = function() return p end
  game.unit = unit
  Body.OnHeistStart()
  Body.AttachPlayer()
  -- Hurt both arms, the left one more.
  local st = Body.state or {}
  local max_l = Body.PartMax("arm_l")
  Body.HealPart("arm_l", 0)
  local function set(id, frac) Body.state.frac[id] = frac end
  if Body.state and Body.state.frac then set("arm_l", 0.5); set("arm_r", 0.8); set("leg_l", 0.9); set("leg_r", 0) end
  own({ backstab = 1 })
  shoot(enemy("swat"), wu, ARM)
  T("an HP arm hit heals your more hurt arm by 2%", near(Body.HP("arm_l"), max_l * 0.52, 1e-4), Body.HP("arm_l") / max_l)
  T("not the other arm", near(Body.HP("arm_r") / Body.PartMax("arm_r"), 0.8))
  shoot(enemy("swat"), wu, LEG)
  T("a leg hit heals a leg, not the black one", near(Body.HP("leg_l") / Body.PartMax("leg_l"), 0.92)
    and Body.IsBlack("leg_r"))
  shoot(enemy("swat"), wu, CHEST)
  T("a body hit heals nothing", near(Body.HP("arm_l") / max_l, 0.52))
  own({})
  shoot(enemy("swat"), wu, ARM)
  T("without Low Blow nothing", near(Body.HP("arm_l") / max_l, 0.52))
  own({ backstab = 1 })
  Ammo.settings.body_parts = false
  shoot(enemy("swat"), wu, ARM)
  T("body parts off: nothing", near(Body.HP("arm_l") / max_l, 0.52))
  Ammo.settings.body_parts = true
  owned["player.detection_risk_add_crit_chance"] = { 0.03, 3 }
  T("the concealment crit is off", pm:upgrade_value("player", "detection_risk_add_crit_chance", 0) == 0)
  owned["player.detection_risk_add_crit_chance"] = nil

  -- Ace: a medic from behind. The player stands at (0,-100); the medic at 0
  -- looks along +y (away from the player): behind.
  own({ backstab = 2 })
  local medic = enemy("medic", V(0, 0, 0), V(0, 1, 0), 5)
  local near_cop = enemy("swat", V(500, 0, 0))
  local far_cop = enemy("swat", V(1500, 0, 0))
  local civ = enemy("civilian", V(100, 0, 0))
  shoot(medic, wu, CHEST)
  T("a medic killed from behind: the cops near him are sick", near_cop.sick == 1)
  T("not beyond 10 m", far_cop.sick == nil)
  T("not civilians", civ.sick == nil)
  local a = hurt(near_cop, "hurt_sick")
  T("for 4 s", near(a._sick_time, clock + 4), a._sick_time - clock)
  all_enemies = {}
  local front = enemy("medic", V(0, 0, 0), V(0, -1, 0), 5)
  local cop2 = enemy("swat", V(300, 0, 0))
  shoot(front, wu, CHEST)
  T("not from the front", cop2.sick == nil)
  all_enemies = {}
  own({ backstab = 1 })
  local m2 = enemy("medic", V(0, 0, 0), V(0, 1, 0), 5)
  local cop3 = enemy("swat", V(300, 0, 0))
  shoot(m2, wu, CHEST)
  T("basic only: nothing", cop3.sick == nil)
  all_enemies = {}
  own({ backstab = 2 })
  local s2 = enemy("swat", V(0, 0, 0), V(0, 1, 0), 5)
  local cop4 = enemy("swat", V(300, 0, 0))
  shoot(s2, wu, CHEST)
  T("not another enemy", cop4.sick == nil)
end

---------------------------------------------------- High Value Target

do
  own({})
  T("no skill: the HE blast is 60 cm", Ammo.BlastRange(Ammo.BULLETS.explosive) == 60)
  own({ hitman = 1 })
  T("Shrapnel: 78 cm", Ammo.BlastRange(Ammo.BULLETS.explosive) == 78)
  owned["player.marked_enemy_extra_damage"] = 1
  T("the marked damage bonus is off", not pm:has_category_upgrade("player", "marked_enemy_extra_damage"))
  owned["player.marked_enemy_extra_damage"] = nil
  local lmg, lu = gun("test_smg", nil, 30)
  own({ hitman = 2 })
  blast(enemy("swat"), lu, 1)
  T("no sure crit yet: no fire", #fires == 0)
  blast(enemy("tank", nil, nil, 1000), lu, 1)
  local cop = enemy("swat")
  blast(cop, lu, 1)
  T("Ignition: after a dozer crit an HE hit sets fire for 3 s", #fires >= 1 and fires[#fires].length == 3
    and fires[#fires].unit == cop._unit, #fires)
  local n = #fires
  shoot(enemy("swat"), lu, CHEST)
  T("not a bullet", #fires == n)
  clock = clock + 2.5
  blast(enemy("swat"), lu, 1)
  T("not after 2 s", #fires == n)
  own({ hitman = 1 })
  blast(enemy("tank", nil, nil, 1000), lu, 1)
  blast(enemy("swat"), lu, 1)
  T("basic only: no fire", #fires == n)
end

------------------------------------------------------- Unseen Strike

do
  local lmg, lu = gun("test_smg", nil, 30)
  own({ unseen_strike = 1 })
  blast(enemy("tank", nil, nil, 1), lu, 5)
  T("Trophy Ammo: an HE crit kill on a dozer drops a round", #spoils == 1
    and spoils[1].pickup()._pdti_spoils.loose.bullet == "explosive")
  local before = Ammo.LooseOfKey(Ammo.Identify(lmg).key)
  T("picking it up gives the round", AmmoClip._pickup(spoils[1].pickup(), unit)
    and Ammo.LooseOfKey(Ammo.Identify(lmg).key) == before + 1)
  blast(enemy("swat", nil, nil, 1), lu, 5)
  T("not a cop", #spoils == 1)
  local wep, wu = gun("test_ar", "hollow")
  own({ unseen_strike = 1 })
  shoot(enemy("spooc", nil, nil, 5), wu, ARM)
  T("an HP crit kill on a cloaker drops a hollow point", #spoils == 1
    and spoils[1].pickup()._pdti_spoils.loose.bullet == "hollow")
  shoot(enemy("spooc", nil, nil, 5), wu, CHEST)
  T("not a kill that is no crit", #spoils == 1)
  own({})
  shoot(enemy("spooc", nil, nil, 5), wu, ARM)
  T("without the skill nothing", #spoils == 1)

  -- Ace.
  own({ unseen_strike = 2 })
  local info = Ammo.Identify(wep)
  for _ = 1, 25 do shoot(enemy("swat", nil, nil, 1000), wu, CHEST) end
  T("special hits store rounds, at most 20", SK.Stored() == 20, SK.Stored())
  local loose = Ammo.LooseOfKey(info.key, "hollow")
  T("the next ammo box gives them", AmmoClip._pickup({}, unit) and Ammo.LooseOfKey(info.key, "hollow") == loose + 20
    and SK.Stored() == 0)
  for _ = 1, 5 do shoot(enemy("swat", nil, nil, 1000), wu, CHEST) end
  pm:modify_value("damage_taken", 2)
  T("taking damage clears them", SK.Stored() == 0)
  local w2, wu2 = gun("test_ar", "standard")
  own({ unseen_strike = 2 })
  shoot(enemy("swat", nil, nil, 1000), wu2, CHEST)
  T("standard rounds store nothing", SK.Stored() == 0)
  -- R8.
  local w3, wu3 = gun("test_ar", "hollow")
  own({ unseen_strike = 2, ammo_2x = 1 })
  for _ = 1, 3 do shoot(enemy("swat", nil, nil, 1000), wu3, CHEST) end
  local info3 = Ammo.Identify(w3)
  local l3 = Ammo.LooseOfKey(info3.key, "hollow")
  local box = {}
  T("bag path: the box stays", AmmoClip._pickup(box, unit) == false and not box._picked_up)
  T("but the stored rounds are taken", Ammo.LooseOfKey(info3.key, "hollow") == l3 + 3 and SK.Stored() == 0)
  owned["player.unseen_increased_crit_chance"] = 1
  T("the vanilla crit is off", not pm:has_category_upgrade("player", "unseen_increased_crit_chance"))
  owned["player.unseen_increased_crit_chance"] = nil
end

------------------------------------------------------------ fallbacks

do
  local wep, wu = gun("test_ar", "hollow")
  own({ scavenger = 2, optic_illusions = 2, silence_expert = 2, backstab = 2, hitman = 2, unseen_strike = 2 })
  Ammo.settings.enabled = false
  local c = enemy("spooc")
  shoot(c, wu, CHEST)
  T("ammo off: none of it (no cloaker crit)", c.taken == 10 and SK.Stored() == 0 and Ammo.BlastRange(Ammo.BULLETS.explosive) == 60)
  owned["player.camouflage_bonus"] = 1
  T("ammo off: the vanilla upgrades", pm:upgrade_value("player", "camouflage_bonus", 0) == 1)
  Ammo.settings.enabled = true
  _G.restoration = {}
  T("restoration-mod: the vanilla upgrades", pm:upgrade_value("player", "camouflage_bonus", 0) == 1)
  _G.restoration = nil
  owned["player.camouflage_bonus"] = nil
end

T("every Silent Killer skill has its text", Skills.texts.menu_scavenger_beta_desc and Skills.texts.menu_optic_illusions_desc
  and Skills.texts.menu_silence_expert_beta_desc and Skills.texts.menu_backstab_beta_desc
  and Skills.texts.menu_spotter_teamwork_beta_desc and Skills.texts.menu_unseen_strike_beta_desc and true)
-- The game's text ids (skilltreetweakdata.lua): Optical Illusions and High
-- Value Target are not menu_<id>_beta.
T("Optical Illusions and High Value Target use the game's text ids", Skills.texts.menu_optic_illusions_beta_desc == nil
  and Skills.texts.menu_hitman_beta_desc == nil
  and Skills.texts.menu_optic_illusions_desc:find("Cloakers") ~= nil
  and Skills.texts.menu_spotter_teamwork_beta_desc:find("Shrapnel") ~= nil)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
