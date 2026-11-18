-- 0.24.0: Enforcer, Ammo Specialist (SKILLS_REWORK_SPEC.md §4, R8).
--   luajit tests/ammo_specialist_tests.lua
local script = arg and arg[0] or "tests/ammo_specialist_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_ammo_specialist") .. "/")
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

---------------------------------------------------------------- the game

local clock = 100
_G.TimerManager = { game = function() return { time = function() return clock end } end }
local hints = {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end
local sent = {}
local PEER_ID = 1
managers.network = { session = function()
  return {
    local_peer = function() return { id = function() return PEER_ID end } end,
    send_to_peers_synched = function(_, msg, unit, amount) sent[#sent + 1] = { msg, unit, amount } end
  }
end }

-- The upgrades the player owns (vanilla values) and their levels.
local owned, levels = {}, {}
_G.PlayerManager = {}
function PlayerManager:upgrade_value(cat, up, default)
  local v = owned[cat .. "." .. up]
  if v == nil then return default or 0 end
  return v
end
function PlayerManager:has_category_upgrade(cat, up) return owned[cat .. "." .. up] ~= nil end
function PlayerManager:upgrade_level(cat, up, default) return levels[cat .. "." .. up] or default or 0 end
local base_player = managers.player
setmetatable(base_player, { __index = PlayerManager })
local pm = base_player

_G.BaseInteractionExt = { _get_timer = function(self) return 4 end }
NewRaycastWeaponBase.fire = function(self) return { hit = true } end

-- The game's ammo bag (vanilla ammobagbase.lua, the parts that count).
_G.AmmoBagBase = {}
local BagBase = AmmoBagBase
BagBase.__index = BagBase
local bag_units = {}
local function new_bag_unit(pos)
  local unit = { pos = pos or { x = 0, y = 0, z = 0 } }
  function unit:position() return self.pos end
  function unit:key() return tostring(self) end
  function unit:set_slot(s) self.slot = s end
  bag_units[#bag_units + 1] = unit
  return unit
end
function BagBase.spawn(pos, rot, lvl, peer_id, bs)
  local unit = new_bag_unit(pos)
  local base = setmetatable({ _unit = unit }, BagBase)
  unit.base = function() return base end
  base:setup(lvl, bs)
  return unit
end
function BagBase:setup(lvl, bs)
  self._bullet_storm_level = bs
  self._ammo_amount = 4 + ((lvl or 0) >= 1 and 2 or 0)
  self._max_ammo_amount = self._ammo_amount
end
function BagBase:sync_setup(lvl, peer_id, bs) self:setup(lvl, bs) end
function BagBase:_set_visual_stage() self.stage = self._ammo_amount end
function BagBase:_set_empty() self._ammo_amount = 0; self._empty = true; self._unit.slot = 0 end
-- Each take: a whole use (or what is left).
function BagBase:_take_ammo(unit)
  local took = math.min(1, self._ammo_amount)
  self._ammo_amount = self._ammo_amount - took
  if self._ammo_amount <= 0 then
    self:_set_empty()
    return self._max_ammo_amount
  end
  return took
end
function BagBase:take_ammo(unit)
  if self._empty then return false, false end
  local taken = self:_take_ammo(unit)
  if self._ammo_amount <= 0 then self:_set_empty() else self:_set_visual_stage() end
  return taken > 0, false
end

-- Enemies.
_G.CopDamage = { roll_critical_hit = function(_, a) return false, a.damage end }
CopDamage.__index = CopDamage
local drops = {}
function CopDamage:drop_pickup(extra) drops[#drops + 1] = "ammo" end
function CopDamage:die(attack_data) self:drop_pickup() ; self._dead = true end
local function enemy(tweak)
  local unit = {}
  unit.base = function() return { _tweak_table = tweak } end
  unit.rotation = function() return {} end
  unit.movement = function()
    return { nav_tracker = function()
      return { lost = function() return false end, position = function() return { x = 1 } end }
    end }
  end
  return setmetatable({ _unit = unit }, CopDamage)
end

-- Pickups.
local spawned = {}
tweak_data.pickups = { ammo = { unit = "units/pickups/ammo/ammo_pickup" } }
_G.safe_spawn_unit = function(name, pos, rot)
  local clip = { _ammo_box = true }
  local unit = { name = name }
  unit.pickup = function() return clip end
  unit.contour = function() return { add = function(_, c) unit.contour_id = c end } end
  unit.set_slot = function(_, s) unit.slot = s end
  function clip:consume() unit.slot = 0; self.consumed = true end
  clip._unit = unit
  spawned[#spawned + 1] = unit
  return unit
end
local box_taken = 0
_G.AmmoClip = { _pickup = function(self, unit) box_taken = box_taken + 1; self._picked_up = true; return true end }

dofile(ROOT .. "lua/ammo_hooks.lua")
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/doctor_buffs.lua")
dofile(ROOT .. "lua/skills_ammo.lua")

local Ammo, Skills, AS = PDTI.Ammo, PDTI.Skills, PDTI.AmmoSkills
local steps = {}
Skills.step_of = function(id) return steps[id] or 0 end
Skills.known = function() return true end
local function own(list) steps = {}; for id, step in pairs(list or {}) do steps[id] = step end end

T("the ammo hooks are in place", Ammo.InstallHooks() == true)
T("the skill hooks are in place", Skills.Install() == true)
T("the skill rework is in", Skills.failed == nil or Skills.failed.ammo == nil)

local function fresh(name, capacity, extra)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  AS.OnHeistStart()
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  unit.position = function() return { x = 0, y = 0, z = 0 } end
  local wep = ENV.make_weapon(name or "test_ar", { "wpn_no_part" }, capacity or 30, extra)
  wep._setup = { user_unit = unit }
  wep._unit = { base = function() return wep end, key = function() return "wep" end }
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  wep.clip = math.min(wep.clip > 0 and wep.clip or 999, wep:get_ammo_max_per_clip())
  Ammo.SyncTotal(wep)
  hints = {}; sent = {}; drops = {}; spawned = {}; box_taken = 0
  return wep, Ammo.Identify(wep), unit
end
local function clear_mags(key)
  for _, m in ipairs(Ammo.AllMagazines(key)) do PDTI.RemoveItem(m.container, m.instance_id) end
end
local function loose_in(container)
  local n = 0
  for _, e in ipairs(PDTI.FindItems(function(c, item) return c == container and item.item_id == "loose_ammo" end)) do
    n = n + (e.item.amount or 0)
  end
  return n
end
local function count_item(id)
  local n = 0
  for _, e in ipairs(PDTI.FindItems(function(_, item) return item.item_id == id end)) do n = n + (e.item.amount or 1) end
  return n
end

------------------------------------------------------------ the frame

do
  local a, b = 0, 0
  _G.FrameTest = { f = function() return 1 end }
  Skills.wrap("FrameTest", "f", function(orig) return function(...) a = a + 1; return orig(...) end end, "one")
  Skills.wrap("FrameTest", "f", function(orig) return function(...) b = b + 1; return orig(...) end end, "two")
  Skills.wrap("FrameTest", "f", function(orig) return function(...) b = b + 100; return orig(...) end end, "two")
  FrameTest.f()
  T("two modules wrap one function (each once)", a == 1 and b == 1, a .. "/" .. b)
end
own({})
levels["ammo_bag.ammo_increase"] = 0
T("nothing owned: the game's level", pm:upgrade_level("ammo_bag", "ammo_increase") == 0)
own({ ammo_2x = 1 })
T("Extra Lead basic: the bag's level 1 (+2 uses)", pm:upgrade_level("ammo_bag", "ammo_increase") == 1)
_G.restoration = {}
T("with restoration-mod the game's level", pm:upgrade_level("ammo_bag", "ammo_increase") == 0)
_G.restoration = nil
Ammo.settings.enabled = false
T("with the ammo system off the game's level", pm:upgrade_level("ammo_bag", "ammo_increase") == 0)
Ammo.settings.enabled = true

------------------------------------------------------------ Scavenger

do
  fresh()
  own({})
  T("no Scavenger: magazines on the floor from 2.5 m", Ammo.PickupRange() == 250)
  T("no Scavenger: the bag takes as long as the game says",
    BaseInteractionExt._get_timer({ tweak_data = "ammo_bag" }) == 4)
  own({ scavenging = 1 })
  T("Scavenger: from 3.75 m", Ammo.PickupRange() == 375)
  T("Scavenger: ammo bags 50% faster", near(BaseInteractionExt._get_timer({ tweak_data = "ammo_bag" }), 4 / 1.5))
  T("not other interactions", BaseInteractionExt._get_timer({ tweak_data = "doctor_bag" }) == 4)
  local wep = fresh()
  T("basic: no reload bonus", NewRaycastWeaponBase.reload_speed_multiplier(wep) == 1)
  own({ scavenging = 2 })
  T("ace: reload +15%", near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1.15))
  local other = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  other._setup = { user_unit = { key = function() return "mate" end } }
  T("not a teammate's gun", NewRaycastWeaponBase.reload_speed_multiplier(other) == 1)
  owned["player.double_drop"] = 1
  T("ace: the extra box drop is off", pm:upgrade_value("player", "double_drop", 0) == 0
    and not pm:has_category_upgrade("player", "double_drop"))
  Ammo.settings.enabled = false
  T("ammo off: vanilla Scavenger (double drop, the game's reload)",
    pm:upgrade_value("player", "double_drop", 0) == 1 and NewRaycastWeaponBase.reload_speed_multiplier(wep) == 1
    and Ammo.PickupRange() == 250)
  Ammo.settings.enabled = true
  owned["player.double_drop"] = nil
end

------------------------------------------------------------ Bulletstorm

do
  local wep, info, unit = fresh()
  own({ ammo_reservoir = 1 })
  wep.clip = 3
  Ammo.SyncTotal(wep)
  local mags_before = #Ammo.Magazines(info.key)
  local bag = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0)
  T("a bag you place is yours", AS.Mine(bag:base()) and #AS.state.bags == 1)
  local ok = bag:base():take_ammo(unit)
  T("Hot Swap: the bag reloads the gun at once", ok and wep.clip == 30, wep.clip)
  local three = false
  for _, m in ipairs(Ammo.Magazines(info.key)) do if m.rounds == 3 then three = true end end
  T("the old magazine (3 rounds) went back", three and #Ammo.Magazines(info.key) == mags_before)
  own({})
  wep.clip = 3
  bag:base():take_ammo(unit)
  T("without Bulletstorm the gun is not reloaded", wep.clip == 3)
  own({ ammo_reservoir = 1 })
  levels["player.no_ammo_cost"] = 2
  T("the no-ammo-cost window is gone", pm:upgrade_level("player", "no_ammo_cost") == 0)
  levels["player.no_ammo_cost"] = nil

  -- Clean Swap.
  own({ ammo_reservoir = 2 })
  T("Clean Swap near your bag: the magazine comes out full", Ammo.EjectRounds(wep, 4) > 30)
  bag.pos = { x = 400 }
  mvector3.distance = function(a, b) return math.abs((a.x or 0) - (b.x or 0)) end
  T("not 4 m away", Ammo.EjectRounds(wep, 4) == 4)
  bag.pos = { x = 250 }
  T("2.5 m is close enough", Ammo.EjectRounds(wep, 4) > 30)
  AS.state.bags = {}
  local mate = BagBase.spawn({ x = 0 }, nil, 0, 2, 0)
  T("a teammate's bag does not count", not AS.Mine(mate:base()) and Ammo.EjectRounds(wep, 4) == 4)
  local own_bag = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0)
  own_bag:base():_set_empty()
  T("an empty bag does not count", Ammo.EjectRounds(wep, 4) == 4)
  own({ ammo_reservoir = 1 })
  BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0)
  T("basic only: no Clean Swap", Ammo.EjectRounds(wep, 4) == 4)
  -- The reload itself.
  own({ ammo_reservoir = 2 })
  for _, m in ipairs(Ammo.Magazines(info.key)) do Ammo.SetMagazineRounds(m.container, m.instance_id, 10) end
  wep.clip = 5
  Ammo.SyncTotal(wep)
  NewRaycastWeaponBase.on_reload(wep)
  local full, five = 0, 0
  for _, m in ipairs(Ammo.Magazines(info.key)) do
    if m.rounds == 30 then full = full + 1 end
    if m.rounds == 5 then five = five + 1 end
  end
  T("a reload next to your bag puts the old magazine back full", full == 1 and five == 0 and wep.clip == 10,
    full .. "/" .. five .. "/" .. wep.clip)
  mvector3.distance = function() return 0 end
end

------------------------------------------------------------ Spoils

local function kill(tweak, variant, weapon_unit)
  local e = enemy(tweak)
  e:die({ attacker_unit = game.unit, variant = variant or "bullet", weapon_unit = weapon_unit })
  return e
end

do
  fresh()
  own({ portable_saw = 1 })
  for _ = 1, 9 do kill("taser") end
  T("9 specials: ammo boxes", #spawned == 0 and #drops == 9)
  kill("swat")
  T("an ordinary cop does not count", AS.state.specials == 9 and #spawned == 0)
  kill("sniper")
  T("a police sniper does not count", AS.state.specials == 9 and #spawned == 0)
  kill("taser")
  T("the 10th special drops spoils, not ammo", #spawned == 1 and #drops == 11, #drops)
  T("the counter starts again", AS.state.specials == 0)
  local clip = spawned[1].pickup()
  T("the drop is a Taser's: a drum of hollow points", clip._pdti_spoils.bullet == "hollow" and clip._pdti_spoils.mag == "drum")
  T("it is marked", spawned[1].contour_id ~= nil)
  local wep, info, unit = fresh()
  own({ portable_saw = 1 })
  AS.state.specials = 9
  kill("taser")
  local mags = #Ammo.Magazines(info.key)
  T("walking over it", AmmoClip._pickup(spawned[1].pickup(), unit) == true and spawned[1].slot == 0)
  local drum
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do if m.size == "drum" and m.bullet == "hollow" then drum = m end end
  T("gives a 75-round magazine of HP", drum and drum.rounds == 75, drum and drum.rounds)
  T("not an ammo box's rounds", box_taken == 0)

  AS.state.specials = 9
  kill("marshal_marksman")
  AmmoClip._pickup(spawned[2].pickup(), unit)
  local ap
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do if m.bullet == "ap" and m.rounds == 30 then ap = m end end
  T("a Marshal sniper: a 30-round magazine of AP", ap ~= nil)

  local items = { medic = "first_aid_kit", shield = "armor_kit", spooc = "grenade", tank_green = "ammo_bag",
    tank_medic = "first_aid_kit", phalanx_minion = "armor_kit" }
  local all = true
  for tweak, item in pairs(items) do
    local before = count_item(item)
    AS.state.specials = 9
    kill(tweak)
    local ok = AmmoClip._pickup(spawned[#spawned].pickup(), unit)
    if not ok or count_item(item) ~= before + 1 then all = false; print("  missing " .. tweak) end
  end
  T("Medic FAK, Shield plate, Cloaker throwable, Dozer ammo bag", all)
  local bag
  for _, e in ipairs(PDTI.FindItems(function(_, item) return item.item_id == "ammo_bag" end)) do bag = e.item end
  T("the Dozer's bag has one use", bag and bag.data and bag.data.uses == 1)

  -- Trophy.
  AS.state.specials = 3
  local n = #spawned
  kill("medic", "melee")
  T("basic: a melee kill counts like any other", #spawned == n and AS.state.specials == 4)
  own({ portable_saw = 2 })
  kill("medic", "melee")
  T("Trophy: a melee kill on a special always drops", #spawned == n + 1)
  T("and leaves the counter", AS.state.specials == 4)
  kill("medic", "bullet")
  T("Trophy: not a gun kill", #spawned == n + 1 and AS.state.specials == 5)

  -- No room.
  own({ portable_saw = 1 })
  local real_add = PDTI.AddItemAuto
  PDTI.AddItemAuto = function() return false, "full" end
  AS.state.specials = 9
  kill("medic")
  local full = spawned[#spawned]
  local before = count_item("first_aid_kit")
  local ok = AmmoClip._pickup(full.pickup(), unit)
  T("no room: the spoils stay on the floor", not ok and full.slot == nil and count_item("first_aid_kit") == before)
  T("and you are told why", hints[#hints] and hints[#hints]:find("no room") ~= nil, hints[#hints])
  PDTI.AddItemAuto = real_add
  T("with room again it is picked up", AmmoClip._pickup(full.pickup(), unit) == true and full.slot == 0)

  -- A teammate walking over it.
  T("not for a teammate", AmmoClip._pickup(spawned[1].pickup(), {}) == false)

  -- Kills of teammates.
  own({ portable_saw = 1 })
  AS.state.specials = 9
  enemy("medic"):die({ attacker_unit = {}, variant = "bullet" })
  T("a teammate's kill does not count", AS.state.specials == 9)

  Ammo.settings.enabled = false
  AS.state.specials = 9
  n = #spawned
  kill("medic")
  T("ammo off: no spoils (the vanilla skill)", #spawned == n and AS.state.specials == 9)
  Ammo.settings.enabled = true
  owned["saw.extra_ammo_multiplier"] = 1.5
  T("the saw's upgrades are off", pm:upgrade_value("saw", "extra_ammo_multiplier", 1) == 1)
  owned["saw.extra_ammo_multiplier"] = nil
  AS.OnHeistStart()
  T("a new heist starts the counter again", AS.state.specials == 0)
end

do -- No assault rifle or SMG: loose rounds.
  local wep, info, unit = fresh("test_pump", 6, { _use_shotgun_reload = true })
  own({ portable_saw = 1 })
  AS.state.specials = 9
  kill("taser")
  local before = Ammo.LooseOfKey(info.key)
  T("no AR/SMG: the rounds come loose", AmmoClip._pickup(spawned[1].pickup(), unit)
    and Ammo.LooseOfKey(info.key) == before + 75, Ammo.LooseOfKey(info.key) - before)
end

------------------------------------------------------------ Extra Lead

do
  local wep, info, unit = fresh()
  own({ ammo_2x = 1 })
  local lvl = pm:upgrade_level("ammo_bag", "ammo_increase")
  local bag = BagBase.spawn({ x = 0 }, nil, lvl, PEER_ID, 0):base()
  T("Extra Lead: 6 uses", bag._ammo_amount == 6)
  -- Reserve Charge.
  own({ ammo_2x = 2 })
  bag._ammo_amount = 2
  bag:take_ammo(unit)
  T("Reserve Charge: one use stays", bag._ammo_amount == 1 and not bag._empty and bag._unit.slot == nil, bag._ammo_amount)
  local ok = bag:take_ammo(unit)
  T("while you have a loaded magazine it can't be taken", not ok and bag._ammo_amount == 1)
  T("you are told", hints[#hints] and hints[#hints]:find("Reserve") ~= nil)
  clear_mags(info.key)
  ok = bag:take_ammo(unit)
  T("with no loaded magazine left it can", ok and bag._empty == true)
  local b2 = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0):base()
  b2._ammo_amount = 1
  T("a teammate takes everything", b2:take_ammo({}) and b2._empty == true)
  local mate = BagBase.spawn({ x = 0 }, nil, 0, 2, 0):base()
  mate._ammo_amount = 1
  Ammo.AddMagazineKey(info.key, 30, info)
  T("from a teammate's bag you take everything", mate:take_ammo(unit) and mate._empty == true)
  own({ ammo_2x = 1 })
  local b3 = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0):base()
  b3._ammo_amount = 1
  T("basic only: no reserve", b3:take_ammo(unit) and b3._empty == true)
end

do -- The Dozer's one-use bag.
  fresh()
  AS.OnBagDeploy({ uses = 1 })
  local unit = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0)
  T("the bag from the spoils has one use", unit:base()._ammo_amount == 1)
  T("the teammates are told (3 uses taken)", sent[1] and sent[1][1] == "sync_ammo_bag_ammo_taken" and sent[1][3] == 3)
  local u2 = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0)
  T("the next bag is a normal one", u2:base()._ammo_amount == 4)
  AS.OnBagDeploy({ uses = 1 })
  local mate = BagBase.spawn({ x = 0 }, nil, 0, 2, 0)
  T("a teammate's bag is not changed", mate:base()._ammo_amount == 4)
  clock = clock + 10
  local late = BagBase.spawn({ x = 0 }, nil, 0, PEER_ID, 0)
  T("too late: not changed", late:base()._ammo_amount == 4)
  AS.OnBagDeploy({ uses = 1 })
  local c = setmetatable({ _unit = new_bag_unit() }, BagBase)
  c._unit.base = function() return c end
  c:sync_setup(0, PEER_ID, 0)
  T("a client: the bag the host spawned for you", c._ammo_amount == 1 and AS.Mine(c))
end

------------------------------------------------------------ R8

do
  local wep, info, unit = fresh()
  own({})
  T("no bag skill: boxes are picked up", AmmoClip._pickup({}, unit) == true and box_taken == 1)
  own({ ammo_reservoir = 1 })
  T("Bulletstorm: a standard box stays", AmmoClip._pickup({}, unit) == false and box_taken == 1)
  own({ ammo_2x = 1 })
  T("Extra Lead: too", AmmoClip._pickup({}, unit) == false and box_taken == 1)
  T("a grenade pickup is allowed", AmmoClip._pickup({ _projectile_id = "frag" }, unit) == true)
  T("an arrow-like pickup too", AmmoClip._pickup({ _weapon_category = "bow" }, unit) == true)
  local spoil = { _pdti_spoils = AS.SPOILS.medic, _unit = { set_slot = function() end } }
  function spoil:consume() self.consumed = true end
  T("spoils are allowed", AmmoClip._pickup(spoil, unit) == true and spoil.consumed)
  Ammo.settings.enabled = false
  T("ammo off: boxes again", AmmoClip._pickup({}, unit) == true)
  Ammo.settings.enabled = true
end

------------------------------------------------------------ Speed Loader

do
  local wep, info = fresh()
  own({})
  local base = Ammo.RoundInterval()
  own({ carbon_blade = 1 })
  T("packing 3x as fast", near(Ammo.RoundInterval(), base / 3))
  local Buffs = PDTI.DoctorBuffs
  Buffs.state.buff = { ends = math.huge, ace = true, torso = false, legs = 0, arms = 1, count = 1 }
  PDTI.Body = PDTI.Body or {}
  local had_enabled = PDTI.Body.Enabled
  PDTI.Body.Enabled = function() return true end
  PDTI.Body.clock = function() return clock end
  Buffs.state.buff.ends = clock + 100
  Skills.Install()
  T("with fast hands too: both count", near(Ammo.RoundInterval(), base / 3 / 1.15), Ammo.RoundInterval())
  Buffs.state.buff = nil
  PDTI.Body.Enabled = had_enabled
  local pump = ENV.make_weapon("test_pump", { "wpn_no_part" }, 6, { _use_shotgun_reload = true })
  pump._setup = { user_unit = game.unit }
  T("a tube shotgun loads 25% faster", near(NewRaycastWeaponBase.reload_speed_multiplier(pump), 1.25))
  T("not a rifle", NewRaycastWeaponBase.reload_speed_multiplier(wep) == 1)
  own({ carbon_blade = 1, scavenging = 2 })
  T("with Scavenger ace: both", near(NewRaycastWeaponBase.reload_speed_multiplier(pump), 1.25 * 1.15))

  -- Auto-load.
  own({ carbon_blade = 2 })
  for _, m in ipairs(Ammo.Magazines(info.key)) do Ammo.SetMagazineRounds(m.container, m.instance_id, 20) end
  local low = Ammo.Magazines(info.key)[1]
  Ammo.SetMagazineRounds(low.container, low.instance_id, 2)
  Ammo.AddLooseKey(info.key, 40, info)
  NewRaycastWeaponBase.fire(wep)
  kill("swat", "bullet", wep._unit)
  kill("swat", "bullet", wep._unit)
  local function rounds_of(id)
    for _, m in ipairs(Ammo.AllMagazines(info.key)) do if m.instance_id == id then return m.rounds end end
  end
  T("2 kills with one shot: nothing", rounds_of(low.instance_id) == 2)
  kill("swat", "explosion", wep._unit)
  T("the 3rd (an HE blast) packs the emptiest magazine", rounds_of(low.instance_id) == 30, rounds_of(low.instance_id))
  T("from the loose rounds", Ammo.LooseOfKey(info.key) == 12, Ammo.LooseOfKey(info.key))
  Ammo.SetMagazineRounds(low.container, low.instance_id, 2)
  kill("swat", "bullet", wep._unit)
  T("a 4th kill of the same shot does nothing more", rounds_of(low.instance_id) == 2)
  NewRaycastWeaponBase.fire(wep)
  kill("swat", "bullet", wep._unit)
  NewRaycastWeaponBase.fire(wep)
  kill("swat", "bullet", wep._unit)
  kill("swat", "bullet", wep._unit)
  T("a new shot starts again", rounds_of(low.instance_id) == 2)
  NewRaycastWeaponBase.fire(wep)
  kill("swat", "bullet", wep._unit)
  kill("swat", "bullet", wep._unit)
  clock = clock + 2
  kill("swat", "bullet", wep._unit)
  T("a kill 2 s after the shot is not of it", rounds_of(low.instance_id) == 2)
  own({ carbon_blade = 1 })
  NewRaycastWeaponBase.fire(wep)
  for _ = 1, 3 do kill("swat", "bullet", wep._unit) end
  T("basic only: no auto-load", rounds_of(low.instance_id) == 2)
  Ammo.settings.enabled = false
  own({ carbon_blade = 1 })
  T("ammo off: the game's speeds", near(Ammo.RoundInterval(), base) and NewRaycastWeaponBase.reload_speed_multiplier(pump) == 1)
  Ammo.settings.enabled = true
end

------------------------------------------------------------ Fully Loaded

do
  local wep, info = fresh()
  own({})
  local w = PDTI.GetContainerInfo("pouch")
  T("no Fully Loaded: no pouch", w and w.width == 0)
  T("nothing goes into it", not PDTI.AddItemAuto("pouch", "loose_ammo", 10, Ammo.LooseData(info.key, info)))
  own({ bandoliers = 1 })
  w = PDTI.GetContainerInfo("pouch")
  T("Fully Loaded: a 2x2 pouch", w.width == 2 and w.height == 2)
  T("no magazines in it", not PDTI.AddItemAuto("pouch", "spare_magazine", 1, { queue_key = info.key, rounds = 0, capacity = 30 }))
  T("no first aid kits", not PDTI.AddItemAuto("pouch", "first_aid_kit", 1))
  Ammo.AddLooseKey(info.key, 150, info)
  T("loose rounds go into the pouch first", loose_in("pouch") == 150, loose_in("pouch"))
  Ammo.AddLooseKey(info.key, 300, info)
  T("until it is full (4 stacks), then elsewhere", loose_in("pouch") == 400 and Ammo.LooseOfKey(info.key) == 450,
    loose_in("pouch") .. "/" .. Ammo.LooseOfKey(info.key))
  local stacks = Ammo.LooseStacks(info.key)
  T("packing takes from the pouch first", stacks[1].container == "pouch")
  do -- A part-full stack in the rig waits until the pouch is full.
    for _, e in ipairs(PDTI.FindItems(function(_, item) return item.item_id == "loose_ammo" end)) do
      PDTI.RemoveItem(e.container, e.item.instance_id, e.item.amount)
    end
    PDTI.AddItemAuto("pouch", "loose_ammo", 50, Ammo.LooseData(info.key, info))
    PDTI.AddItemAuto("rig", "loose_ammo", 50, Ammo.LooseData(info.key, info))
    Ammo.AddLooseKey(info.key, 100, info)
    T("the pouch fills before a rig stack is topped up", loose_in("pouch") == 150 and loose_in("rig") == 50,
      loose_in("pouch") .. "/" .. loose_in("rig"))
    Ammo.AddLooseKey(info.key, 300, info)
  end
  owned["player.extra_ammo_multiplier"] = 1.25
  T("the +25% ammo is off", pm:upgrade_value("player", "extra_ammo_multiplier", 1) == 1)
  Ammo.settings.enabled = false
  T("ammo off: the +25% ammo again", pm:upgrade_value("player", "extra_ammo_multiplier", 1) == 1.25)
  Ammo.settings.enabled = true
  owned["player.extra_ammo_multiplier"] = nil

  -- On the Move.
  local st = { _state_data = {} }
  for _, m in ipairs(Ammo.Magazines(info.key)) do Ammo.SetMagazineRounds(m.container, m.instance_id, 0) end
  T("basic: packing puts the gun away", not AS.PouchPackAllowed(st, wep))
  own({ bandoliers = 2 })
  T("ace: from the pouch the gun stays in hand", AS.PouchPackAllowed(st, wep) == true)
  st._state_data.in_steelsight = true
  T("not while aiming", not AS.PouchPackAllowed(st, wep))
  st._state_data.in_steelsight = nil
  st._shooting = true
  T("not while shooting", not AS.PouchPackAllowed(st, wep))
  st._shooting = nil
  for _, e in ipairs(PDTI.FindItems(function(c, item) return c == "pouch" end)) do
    PDTI.RemoveItem("pouch", e.item.instance_id, e.item.amount)
  end
  T("an empty pouch: the normal packing", not AS.PouchPackAllowed(st, wep) and Ammo.LooseOfKey(info.key) > 0
    and loose_in("pouch") == 0)

  -- The reload key held, through the game's hooks.
  Ammo.AddLooseKey(info.key, 40, info)
  local unequips = 0
  local ps = setmetatable({ _state_data = {}, _controller = { get_input_bool = function(_, k) return k == "reload" end,
    get_input_pressed = function() return false end, get_input_released = function() return false end } }, { __index = PlayerStandard })
  ps._start_action_unequip_weapon = function() unequips = unequips + 1 end
  Ammo.reload_held_override = true
  local held_ok = pcall(function()
    for i = 1, 20 do
      PlayerStandard._check_action_reload(ps, i * 0.1, { btn_reload_state = true })
      Ammo.GameTick(ps, i * 0.1, 0.1)
    end
  end)
  local packed = 0
  for _, m in ipairs(Ammo.Magazines(info.key)) do packed = packed + m.rounds end
  T("holding R packs from the pouch without putting the gun away", held_ok and unequips == 0 and packed > 0,
    tostring(held_ok) .. " unequips " .. unequips .. " packed " .. packed)

  -- Without the skill what was in the pouch moves out.
  own({})
  local in_pouch = loose_in("pouch")
  AS.TidyPouch()
  T("without the skill the pouch empties into the backpack", loose_in("pouch") == 0 and loose_in("backpack") >= in_pouch)
end

do -- An old save (no pouch) loads.
  local f = io.open(PDTI.SavePath and PDTI.SavePath() or "", "r")
  if f then f:close() end
  local ok = PDTI.ValidateState()
  T("the inventory is valid with the pouch", ok == true or (type(ok) == "table" and #ok == 0), ok)
end

T("every reworked Ammo Specialist skill has its text", Skills.texts.menu_scavenging_beta_desc
  and Skills.texts.menu_ammo_reservoir_beta_desc and Skills.texts.menu_portable_saw_beta_desc
  and Skills.texts.menu_ammo_2x_beta_desc and Skills.texts.menu_carbon_blade_beta_desc
  and Skills.texts.menu_bandoliers_beta_desc and Skills.texts.menu_portable_saw_beta == "Spoils"
  and Skills.texts.menu_carbon_blade_beta == "Speed Loader" and true)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
