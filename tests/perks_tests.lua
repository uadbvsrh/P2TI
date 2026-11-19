-- 0.31.0: safehouse room bonuses (perks.lua).
--   luajit tests/perks_tests.lua
local script = arg and arg[0] or "tests/perks_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_perks") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()
ENV.load_mod(ROOT, false)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Perks = PDTI.Perks

-- The game's safehouse: room tiers.
local tiers = {}
local safehouse = { _global = { rooms = {} } }
function safehouse:get_room_current_tier(room) return tiers[room] or 1 end
local function set_tier(room, tier) tiers[room] = tier; safehouse._global.rooms[room] = { tier_current = tier } end
managers.custom_safehouse = safehouse
local armour_id = "level_1"
managers.blackmarket = managers.blackmarket or {}
managers.blackmarket.equipped_armor = function() return armour_id end

local function fresh()
  tiers = {}
  safehouse._global.rooms = {}
  PDTI.Reset()
  Perks.Reset()
end
local function size(name) local i = PDTI.GetContainerInfo(name); return i.width .. "x" .. i.height end

------------------------------------------------------------ the table

T("every piece has two rooms, each an option of that piece", (function()
  for piece, p in pairs(Perks.PIECES) do
    if #p.rooms ~= 2 then return false end
    for _, room in ipairs(p.rooms) do
      local o = Perks.OPTIONS[room]
      if not o or o.piece ~= piece or not Perks.ROOMS[room] then return false end
    end
  end
  return true
end)())
T("no room is an option of two pieces", (function()
  local seen = {}
  for _, p in pairs(Perks.PIECES) do
    for _, room in ipairs(p.rooms) do
      if seen[room] then return false end
      seen[room] = true
    end
  end
  return true
end)())
T("the piece order names every piece once", (function()
  local n = 0
  for _, piece in ipairs(Perks.PIECE_ORDER) do if not Perks.PIECES[piece] then return false end; n = n + 1 end
  local m = 0
  for _ in pairs(Perks.PIECES) do m = m + 1 end
  return n == m
end)())

------------------------------------------------------------ choosing

fresh()
PDTI.SetEquipment("rig", "assault_rig")
T("tier 1: Chains' option cannot be picked", PDTI.SetPerkChoice("assault_rig", "spanish") == false)
T("  it says to upgrade the room", select(2, PDTI.SetPerkChoice("assault_rig", "spanish")):find("tier 2") ~= nil)
T("  the rig stays 7x3", size("rig") == "7x3", size("rig"))
set_tier("spanish", 2)
T("tier 2: it can be picked", PDTI.SetPerkChoice("assault_rig", "spanish") == true)
T("  the ammunition part is 7x4", size("rig") == "7x4", size("rig"))
T("  the choice shows it picked at tier 2", (function()
  local c = PDTI.Perks.Choices("assault_rig")
  return c[1].chosen and c[1].unlocked and c[1].text:find("Chains %(tier 2%)") ~= nil
end)())
set_tier("spanish", 3)
T("tier 3: 8x4", size("rig") == "8x4", size("rig"))
T("another room's option is refused", PDTI.SetPerkChoice("assault_rig", "german") == false)
T("a bonus not made yet is refused", (function()
  set_tier("wild", 3)
  Perks.OPTIONS.wild.ready = false
  local ok, why = PDTI.SetPerkChoice("assault_rig", "wild")
  Perks.OPTIONS.wild.ready = nil
  return ok == false and why:find("not made yet") ~= nil
end)())
T("an unknown piece is refused", PDTI.SetPerkChoice("rocket_rig", "spanish") == false)

-- An item in the last row stays when the save is read with no safehouse.
T("a magazine goes in the eighth column",
  PDTI.AddItem("rig", "spare_magazine", 7, 2, false, 1, { capacity = 30, rounds = 30 }) == true)
local saved_cs = managers.custom_safehouse
managers.custom_safehouse = nil
PDTI.LoadProfile(PDTI.loaded_profile)
T("without the safehouse, the saved tier counts: still 8x4", size("rig") == "8x4", size("rig"))
T("  the magazine is where it was", (function()
  for _, item in ipairs(PDTI.GetContainer("rig").items) do
    if item.item_id == "spare_magazine" and item.x == 7 then return true end
  end
  return false
end)())
managers.custom_safehouse = saved_cs

T("no bonus: the rig is 7x3 again and the magazine is kept", (function()
  local ok = PDTI.SetPerkChoice("assault_rig", nil)
  if not ok or size("rig") ~= "7x3" then return false end
  return #PDTI.FindItems(function(_, item) return item.item_id == "spare_magazine" end) == 1
end)())

-- A choice already in the save (edited, or an older version) only counts
-- when it could be picked now.
fresh()
PDTI.SetEquipment("rig", "assault_rig")
PDTI.PerkState().perks.assault_rig = "spanish"
T("a saved choice of a tier 1 room does nothing", Perks.Active("assault_rig") == nil and size("rig") == "7x3", size("rig"))
set_tier("wild", 3)
PDTI.PerkState().perks.assault_rig = "wild"
Perks.OPTIONS.wild.ready = false
T("a saved choice of a bonus not made yet does nothing", Perks.Active("assault_rig") == nil)
Perks.OPTIONS.wild.ready = nil
set_tier("german", 3)
PDTI.PerkState().perks.assault_rig = "german"
T("a saved choice of another piece's room does nothing", Perks.Active("assault_rig") == nil and size("rig") == "7x3")

------------------------------------------------------------ room tiers

fresh()
T("tiers seen are remembered", PDTI.NoteRoomTiers({ german = 2 }) == true and PDTI.PerkState().room_tiers.german == 2)
T("a lower tier does not replace a higher one", PDTI.NoteRoomTiers({ german = 1 }) == false
  and PDTI.PerkState().room_tiers.german == 2)
T("a nonsense tier is ignored", PDTI.NoteRoomTiers({ german = 7, bonnie = "x" }) == false)
T("the saved tier counts with the game's at 1", Perks.Tier("german") == 2)
set_tier("german", 3)
T("the game's higher tier counts", Perks.Tier("german") == 3)
T("Refresh saves the game's tiers", Perks.Refresh() == true and PDTI.PerkState().room_tiers.german == 3)
T("setting a room's tier in the game is remembered", (function()
  _G.CustomSafehouseManager = { set_room_tier = function(self, room, tier) set_tier(room, tier); return true end }
  Perks.InstallHooks()
  CustomSafehouseManager.set_room_tier(safehouse, "bonnie", 2)
  return PDTI.PerkState().room_tiers.bonnie == 2
end)())
T("a safehouse with no data yet is not asked", (function()
  local cs = managers.custom_safehouse
  managers.custom_safehouse = { get_room_current_tier = function() error("not loaded") end }
  local ok = pcall(Perks.Tier, "german")
  managers.custom_safehouse = cs
  return ok
end)())

------------------------------------------------------------ rigs and backpacks

fresh()
set_tier("old_hoxton", 2)
PDTI.SetEquipment("rig", "general_rig")
PDTI.SetPerkChoice("general_rig", "old_hoxton")
T("Old Hoxton tier 2: general rig 4x6", size("rig") == "4x6", size("rig"))
set_tier("old_hoxton", 3)
T("tier 3: 5x6", size("rig") == "5x6", size("rig"))

set_tier("bodhi", 2)
PDTI.SetEquipment("backpack", "small_backpack")
PDTI.SetPerkChoice("small_backpack", "bodhi")
T("Bodhi tier 2: small backpack 5x3", size("backpack") == "5x3", size("backpack"))
T("  it keeps its speed", near(PDTI.GetEquipment().backpack_definition.speed_bonus, 0.25))
set_tier("bodhi", 3)
T("tier 3: 6x3", size("backpack") == "6x3", size("backpack"))

set_tier("sokol", 2)
PDTI.SetPerkChoice("small_backpack", "sokol")
T("Sokol tier 2: small backpack 5x2 again, speed 35%", size("backpack") == "5x2"
  and near(PDTI.GetEquipment().backpack_definition.speed_bonus, 0.35))
set_tier("sokol", 3)
T("Sokol tier 3: speed 45%", near(PDTI.GetEquipment().backpack_definition.speed_bonus, 0.45))

set_tier("dragan", 2)
PDTI.SetEquipment("backpack", "medium_backpack")
PDTI.SetPerkChoice("medium_backpack", "dragan")
T("Dragan tier 2: medium backpack 5x5, 25 kg", size("backpack") == "5x5"
  and PDTI.GetEquipment().backpack_definition.max_weight == 25)
set_tier("dragan", 3)
T("tier 3: 35 kg", PDTI.GetEquipment().backpack_definition.max_weight == 35)
T("the game's definition is not changed", PDTI.equipment.backpacks.medium_backpack.h == 4
  and PDTI.equipment.backpacks.medium_backpack.max_weight == 25)

set_tier("german", 2)
PDTI.SetEquipment("backpack", "large_backpack")
PDTI.SetPerkChoice("large_backpack", "german")
T("Wolf tier 2: 40% less slowdown", near(PDTI.Gear.PenaltyScale(), 0.6))
set_tier("german", 3)
T("tier 3: 50% less", near(PDTI.Gear.PenaltyScale(), 0.5))
T("  enemies still focus you 50% more", near(PDTI.Gear.Threat(), 1.5))
set_tier("livingroom", 2)
PDTI.SetPerkChoice("large_backpack", "livingroom")
T("living room tier 2: focus +25%, slowdown back to 30% less", near(PDTI.Gear.Threat(), 1.25)
  and near(PDTI.Gear.PenaltyScale(), 0.7))
set_tier("livingroom", 3)
T("tier 3: no extra focus", near(PDTI.Gear.Threat(), 1))

T("each backpack keeps its own pick", (function()
  PDTI.SetEquipment("backpack", "medium_backpack")
  return size("backpack") == "5x5" -- Dragan is still picked for the medium one
end)())

------------------------------------------------------------ choices on screen

fresh()
set_tier("russian", 3)
local c = Perks.Choices("medical_rig")
T("the medical rig shows Dallas and Sangres", #c == 2 and c[1].name == "Dallas" and c[2].name == "Sangres")
T("  Dallas at tier 3: unlocked", c[1].unlocked == true and c[1].text:find("Dallas %(tier 3%)") ~= nil, c[1].text)
Perks.OPTIONS.russian.ready = false
c = Perks.Choices("medical_rig")
T("  a bonus not made yet: not unlocked, says so", c[1].unlocked == false and c[1].text:find("not made yet") ~= nil)
Perks.OPTIONS.russian.ready = nil
set_tier("sokol", 2)
c = Perks.Choices("small_backpack")
T("  a tier 2 room: unlocked with its line", c[1].unlocked and c[1].text == "Sokol (tier 2): Speed bonus 25% -> 35%", c[1].text)
T("  a tier 1 room: from tier 2", not c[2].unlocked and c[2].text:find("from tier 2") ~= nil)
T("the room menu lines name the piece and mark the tier", (function()
  local lines = Perks.RoomLines("sokol", 2)
  return lines[1]:find("Small Backpack") ~= nil and lines[2]:sub(1, 2) == "> " and lines[3]:sub(1, 2) == "  "
end)())
T("a room with no bonus has no lines", #Perks.RoomLines("nowhere", 3) == 0)

------------------------------------------------------------ bonuses of their own

fresh()
local LQ = PDTI.LootQuality
T("quality chances without Bonnie: 80/17/3", (function()
  local ch = LQ.Chances()
  return near(ch[1], 0.80) and near(ch[2], 0.17) and near(ch[3], 0.03)
end)())
LQ.random = function() return 0.85 end
T("  a roll of 0.85 is High", LQ.Roll("gold").quality == 2)
set_tier("bonnie", 2)
T("Bonnie tier 2: 72/25/3", (function()
  local ch = LQ.Chances()
  return near(ch[1], 0.72) and near(ch[2], 0.25) and near(ch[3], 0.03)
end)())
LQ.random = function() return 0.96 end
T("  a roll of 0.96 is High (it was Exceptional)", LQ.Roll("gold").quality == 2)
set_tier("bonnie", 3)
T("Bonnie tier 3: 69/25/6", (function()
  local ch = LQ.Chances()
  return near(ch[1], 0.69) and near(ch[2], 0.25) and near(ch[3], 0.06)
end)())
T("  a roll of 0.96 is Exceptional", LQ.Roll("gold").quality == 3)
LQ.random = function() return 0 end

local Stash = PDTI.Stash
T("sell-now 50% without Scarface", Stash.SellNowPrice({ value = 1000 }) == 500)
set_tier("terry", 2)
T("Scarface tier 2: 65%", Stash.SellNowPrice({ value = 1000 }) == 650)
set_tier("terry", 3)
T("Scarface tier 3: 75%", Stash.SellNowPrice({ value = 1000 }) == 750)

T("stash 48 cells without the vault", Stash.Capacity() == 48)
set_tier("vault", 2)
T("vault tier 2: 4 bags more", Stash.Capacity() == 64)
set_tier("vault", 3)
T("vault tier 3: 8 bags more", Stash.Capacity() == 80)

T("Duke (0.45.0): insurance 30% and 10 min below tier 2", (function()
  set_tier("myh", 1); return Perks.InsuranceShare(0.3) == 0.3 and Perks.InsuranceDelay(600) == 600
end)())
T("  tier 2: 20%, still 10 min (0.45.1)", (function()
  set_tier("myh", 2); return Perks.InsuranceShare(0.3) == 0.2 and Perks.InsuranceDelay(600) == 600
end)())
T("  tier 3: 20% and 5 min", (function()
  set_tier("myh", 3); return Perks.InsuranceShare(0.3) == 0.2 and Perks.InsuranceDelay(600) == 300
end)())
T("  his room's lines", (function()
  local l = Perks.RoomLines("myh", 3)
  return l[1] == "Bonus: Insurance" and l[2] == "> Tier 2: Weapon insurance costs 20% (not 30%)"
    and l[3] == "> Tier 3: Also: a lost weapon is back in 5 minutes (not 10)"
end)())

------------------------------------------------------------ armour

fresh()
dofile(ROOT .. "lua/body.lua")
dofile(ROOT .. "lua/armour.lua")
local Armour = PDTI.Armour
armour_id = "level_6"
T("plates take 3 s without John Wick", Armour.PlateTime() == 3)
set_tier("jowi", 2)
T("  Wick's room at tier 2 but not picked: still 3 s", Armour.PlateTime() == 3)
PDTI.SetPerkChoice("heavy_armour", "jowi")
T("John Wick tier 2: 1.5 s", Armour.PlateTime() == 1.5)
set_tier("jowi", 3)
T("tier 3: 1 s", Armour.PlateTime() == 1)
T("Jiro not picked: firing stops a plate", Perks.PlateKeepsFiring() == false)
set_tier("dragon", 2)
PDTI.SetPerkChoice("heavy_armour", "dragon")
T("Jiro tier 2: firing does not stop a plate, not full speed", Perks.PlateKeepsFiring() and not Perks.PlateFullSpeed())
T("  and the plate time is 3 s again (Wick is not picked)", Armour.PlateTime() == 3)
set_tier("dragon", 3)
T("Jiro tier 3: full speed too", Perks.PlateKeepsFiring() and Perks.PlateFullSpeed())

-- Light armour: Sydney (regeneration) and Jimmy (half damage when broken).
fresh()
_G.PlayerManager = {
  body_armor_regen_multiplier = function() return 1 end,
  damage_reduction_skill_multiplier = function() return 0.9 end
}
Perks.InstallHooks()
local pm = {}
armour_id = "level_2"
T("regeneration as in the game without Sydney", near(PlayerManager.body_armor_regen_multiplier(pm), 1))
set_tier("sydney", 2)
PDTI.SetPerkChoice("light_armour", "sydney")
T("Sydney tier 2: 25% sooner", near(PlayerManager.body_armor_regen_multiplier(pm), 0.75))
set_tier("sydney", 3)
T("tier 3: 50% sooner", near(PlayerManager.body_armor_regen_multiplier(pm), 0.5))
armour_id = "level_6"
T("with heavy armour: nothing", near(PlayerManager.body_armor_regen_multiplier(pm), 1))
armour_id = "level_2"
T("the hooks are put on once", (function()
  local f = PlayerManager.body_armor_regen_multiplier
  Perks.InstallHooks()
  return PlayerManager.body_armor_regen_multiplier == f
end)())

set_tier("jimmy", 2)
PDTI.SetPerkChoice("light_armour", "jimmy")
local clock = 100
local real_time = PDTI.AppTime
PDTI.AppTime = function() return clock end
local armor = 50
local pd = { get_real_armor = function() return armor end }
Perks.Tick(pd)
T("whole armour: damage as in the game", near(PlayerManager.damage_reduction_skill_multiplier(pm, "bullet"), 0.9))
armor = 0
Perks.Tick(pd)
T("Jimmy: the armour breaks, half damage", near(PlayerManager.damage_reduction_skill_multiplier(pm, "bullet"), 0.45))
clock = 101.9
T("  still at 1.9 s", near(Perks.DamageMultiplier(), 0.5))
clock = 102.1
T("  over after 2 s", near(Perks.DamageMultiplier(), 1))
Perks.Tick(pd)
T("  staying broken does not start it again", near(Perks.DamageMultiplier(), 1))
armor = 30; Perks.Tick(pd); armor = 0
set_tier("jimmy", 3)
clock = 200
Perks.Tick(pd)
clock = 203.5
T("tier 3: still at 3.5 s", near(Perks.DamageMultiplier(), 0.5))
armour_id = "level_7"
armor = 30; Perks.Tick(pd); armor = 0; clock = 300; Perks.Tick(pd)
T("heavy armour breaking: nothing", near(Perks.DamageMultiplier(), 1))
PDTI.AppTime = real_time

------------------------------------------------------------ 0.32.0

-- Dallas and Sangres: the medical rig's self-revive.
do
  local Gear = PDTI.Gear
  local state_name = "bleed_out"
  local sent = {}
  local healed = 0
  _G.Message = { RevivePlayer = "revive_player" }
  managers.player.current_state = function() return state_name end
  managers.player.send_message = function(_, msg) sent[#sent + 1] = msg end
  managers.player.player_unit = function()
    return { character_damage = function() return { band_aid_health = function() healed = healed + 1 end } end }
  end
  local function count(id) return #PDTI.FindItems(function(_, i) return i.item_id == id end) end
  local function add(c, id) return PDTI.AddItemAuto(c, id, 1, nil, true) end

  fresh()
  set_tier("russian", 2)
  PDTI.SetEquipment("rig", "medical_rig")
  PDTI.SetPerkChoice("medical_rig", "russian")
  add("rig", "doctor_bag"); add("rig", "doctor_bag")
  Gear.OnHeistStart()
  Gear.Tick({ btn_jump_press = true })
  T("Dallas tier 2: up with a doctor bag", #sent == 1 and count("doctor_bag") == 1)
  Gear.Tick({ btn_jump_press = true })
  T("  once", #sent == 1)
  T("  placing a doctor bag gives it back", Gear.OnDoctorBagPlaced() == true and Gear.RevivesLeft() == 1)
  T("  not twice", Gear.OnDoctorBagPlaced() == false)
  Gear.Tick({ btn_jump_press = true })
  T("  up again", #sent == 2 and count("doctor_bag") == 0)
  set_tier("russian", 3)
  add("rig", "doctor_bag"); add("rig", "doctor_bag")
  Gear.OnHeistStart()
  Gear.Tick({ btn_jump_press = true }); Gear.Tick({ btn_jump_press = true }); Gear.Tick({ btn_jump_press = true })
  T("Dallas tier 3: twice per heist, a doctor bag each", #sent == 4 and count("doctor_bag") == 0)
  PDTI.SetPerkChoice("medical_rig", nil)
  Gear.OnHeistStart()
  add("rig", "doctor_bag")
  Gear.Tick({ btn_jump_press = true })
  T("no bonus: placing a bag gives nothing back", Gear.OnDoctorBagPlaced() == false and Gear.RevivesLeft() == 0)

  fresh()
  sent, healed = {}, 0
  set_tier("max", 2)
  PDTI.SetEquipment("rig", "medical_rig")
  PDTI.SetPerkChoice("medical_rig", "max")
  add("rig", "doctor_bag")
  Gear.OnHeistStart()
  Gear.Tick({ btn_jump_press = true })
  T("Sangres tier 2: a doctor bag does not get you up", #sent == 0 and count("doctor_bag") == 1)
  add("rig", "first_aid_kit")
  Gear.Tick({ btn_jump_press = true })
  T("  a first aid kit does", #sent == 1 and count("first_aid_kit") == 0 and count("doctor_bag") == 1)
  state_name = "standard"
  Gear.Tick({})
  T("  up: it heals as a kit does, once", healed == 1)
  Gear.Tick({})
  T("  (once)", healed == 1)
  state_name = "bleed_out"
  T("Sangres tier 2: a kit goes down at the usual speed", Perks.FakTimeFactor() == 1)
  set_tier("max", 3)
  T("Sangres tier 3: twice as fast", Perks.FakTimeFactor() == 0.5)
  PDTI.SetEquipment("rig", "general_rig")
  T("  only while the medical rig is worn", Perks.FakTimeFactor() == 1 and Perks.ReviveItem() == "doctor_bag")
  managers.player.player_unit = function() return nil end
end

-- Rust: ammo bags in the assault rig.
do
  fresh()
  set_tier("wild", 2)
  PDTI.SetEquipment("rig", "assault_rig")
  PDTI.SetPerkChoice("assault_rig", "wild")
  T("Rust tier 2: a bag from the rig has one more use", Perks.BagExtraUses("rig_2") == 1)
  T("  from the backpack: no", Perks.BagExtraUses("backpack") == 0 and Perks.BagExtraUses(nil) == 0)
  T("  no refill key at tier 2", Perks.RigRefillOn() == false and Perks.RigBagRefill() == false)
  PDTI.SetEquipment("rig", "general_rig")
  T("  another rig worn: nothing", Perks.BagExtraUses("rig") == 0)
  PDTI.SetEquipment("rig", "assault_rig")

  -- The refill key (tier 3).
  set_tier("wild", 3)
  local need = { 0.6, 0.7 }
  local gun = function(i)
    return { add_ammo_from_bag = function(_, available)
      local took = math.min(available, need[i]); need[i] = need[i] - took; return took end }
  end
  local unit = { inventory = function() return { available_selections = function()
    return { { unit = { base = function() return gun(1) end } }, { unit = { base = function() return gun(2) end } } }
  end } end }
  local real_unit = PDTI.PlayerUnit
  PDTI.PlayerUnit = function() return unit end
  T("tier 3: no bag in the rig, nothing", Perks.RigBagRefill() == false)
  PDTI.AddItemAuto("rig_2", "ammo_bag", 1, nil, true)
  T("  a bag in the rig refills both guns", Perks.RigBagRefill() == true and need[1] == 0 and need[2] == 0)
  local bag = PDTI.FindItems(function(_, i) return i.item_id == "ammo_bag" end)[1]
  T("  the bag keeps what is left (a full bag + Rust's one, less 1.3)", bag ~= nil
    and math.abs(bag.item.data.uses - (Perks.BagUses() - 1.3)) < 1e-6, bag and bag.item.data.uses)
  T("  full ammunition: nothing taken", Perks.RigBagRefill() == false
    and math.abs(PDTI.FindItems(function(_, i) return i.item_id == "ammo_bag" end)[1].item.data.uses - (Perks.BagUses() - 1.3)) < 1e-6)
  need = { 10, 10 }
  Perks.RigBagRefill()
  T("  a bag used to the end is gone", #PDTI.FindItems(function(_, i) return i.item_id == "ammo_bag" end) == 0)
  PDTI.PlayerUnit = real_unit

  -- The bag that appears gets the extra use.
  local ok = pcall(dofile, ROOT .. "lua/skills.lua")
  ok = ok and pcall(dofile, ROOT .. "lua/skills_ammo.lua")
  local AS = PDTI.AmmoSkills
  if ok and AS and AS.OnBagDeploy and AS.OnOwnBag then
    set_tier("wild", 2)
    local base = { _ammo_amount = 4, _set_visual_stage = function() end }
    AS.OnBagDeploy(nil, "rig_2")
    AS.OnOwnBag({}, base)
    T("a bag placed from the rig: 5 uses", base._ammo_amount == 5, base._ammo_amount)
    base = { _ammo_amount = 4, _set_visual_stage = function() end }
    AS.OnBagDeploy(nil, "backpack")
    AS.OnOwnBag({}, base)
    T("  from the backpack: 4", base._ammo_amount == 4)
    base = { _ammo_amount = 4, _set_visual_stage = function() end }
    AS.OnBagDeploy({ uses = 1 }, "rig_2")
    AS.OnOwnBag({}, base)
    T("  a 1-use bag from the rig: 2", base._ammo_amount == 2, base._ammo_amount)
  else
    T("the ammo skills load for the bag tests", false)
  end
end

-- Houston: the general rig's weight and concealment.
do
  fresh()
  dofile(ROOT .. "lua/skill_rules.lua")
  local Rules = PDTI.Rules
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.AddItemAuto("rig", "doctor_bag", 1, nil, true)
  PDTI.AddItemAuto("rig", "doctor_bag", 1, nil, true)
  local rig_kg = 0
  for _, e in ipairs(PDTI.FindItems(function(c) return c == "rig" end)) do rig_kg = rig_kg + PDTI.ItemWeight(e.item) end
  T("without Houston all the weight counts", Rules.HiddenWeight() == 0)
  set_tier("american", 2)
  PDTI.SetPerkChoice("general_rig", "american")
  T("Houston tier 2: half the rig's weight is hidden", math.abs(Rules.HiddenWeight() - rig_kg / 2) < 1e-6, Rules.HiddenWeight())
  set_tier("american", 3)
  T("tier 3: all of it", math.abs(Rules.HiddenWeight() - rig_kg) < 1e-6)
  local Carry = PDTI.Carry
  local real_lw, real_on = Carry.LoadWeight, Carry.enabled
  Carry.LoadWeight = function() return 15 + rig_kg end
  Carry.enabled = true
  T("  the concealment penalty does not count it", Rules.ConcealmentPenalty() == 0, Rules.ConcealmentPenalty())
  T("  a weight given to it is taken as it is", Rules.ConcealmentPenalty(15 + 3 * 3) == 3)
  Carry.LoadWeight, Carry.enabled = real_lw, real_on
  PDTI.SetEquipment("rig", "medical_rig")
  T("  another rig worn: nothing hidden", Rules.HiddenWeight() == 0)
end

-- Clover: loot slots next to the medium backpack.
do
  fresh()
  local Loot = PDTI.Loot
  PDTI.SetEquipment("backpack", "medium_backpack")
  T("no loot slots without Clover", size("loot_slot") == "0x0")
  set_tier("clover", 2)
  T("Clover tier 2 picked", PDTI.SetPerkChoice("medium_backpack", "clover") == true)
  T("  a 2x2 loot slot", size("loot_slot") == "2x2")
  T("  a magazine does not go in it", PDTI.AddItemAuto("loot_slot", "spare_magazine", 1, { capacity = 30 }, true) == false)
  T("  a loot bag goes there first", Loot.Add(1, { carry_id = "gold" }) == true
    and #PDTI.GetContainer("loot_slot").items == 1)
  set_tier("clover", 3)
  T("tier 3: 2x4, two bags", size("loot_slot") == "2x4" and Loot.Add(1, { carry_id = "gold" }) == true
    and #PDTI.GetContainer("loot_slot").items == 2)
  T("  the screen model has them", PDTI.GetInventoryViewModel().containers.loot_slot.height == 4)
  T("another backpack: no slots, the bags move into the backpack", PDTI.SetEquipment("backpack", "large_backpack") == true
    and size("loot_slot") == "0x0" and #PDTI.GetContainer("backpack").items == 2)
  PDTI.SetEquipment("backpack", "medium_backpack")
  Loot.Add(2, { carry_id = "gold" })
  T("the slots full and the rest in the backpack", #PDTI.GetContainer("loot_slot").items == 2)
  -- Fill everything else with bags.
  for _ = 1, 20 do Loot.Add(1, { carry_id = "gold" }) end
  local function bags() return #PDTI.FindItems(function(_, i) return i.item_id == "loot_bag" end) end
  local before = bags()
  local ok = PDTI.SetPerkChoice("medium_backpack", nil)
  T("no bonus with no room for the bags: refused, nothing lost", ok == false and bags() == before
    and size("loot_slot") == "2x4", tostring(ok) .. " " .. before .. " " .. bags())
end

-- Joy: hacks and the keycard.
do
  fresh()
  _G.TimerGui = {
    _start = function(self, timer) self._time_left = timer * (self._timer_multiplier or 1) end,
    set_timer_multiplier = function(self, m) self._timer_multiplier = m end
  }
  local removed = {}
  PlayerManager.remove_special = function(_, name) removed[#removed + 1] = name end
  Perks.InstallHooks()
  local function timer(base) return setmetatable({ _unit = { base = function() return base end } }, { __index = TimerGui }) end
  local hack = timer({})
  TimerGui._start(hack, 100)
  T("a hack without Joy: as in the game", hack._time_left == 100)
  set_tier("joy", 2)
  hack = timer({})
  TimerGui._start(hack, 100)
  T("Joy tier 2: a hack takes 75%", math.abs(hack._time_left - 75) < 1e-6)
  TimerGui.set_timer_multiplier(hack, 0.8)
  T("  a later multiplier keeps Joy's", math.abs(hack._timer_multiplier - 0.6) < 1e-6)
  TimerGui._start(hack, 100)
  T("  started again: not twice", math.abs(hack._time_left - 60) < 1e-6)
  local drill = timer({ is_drill = true })
  TimerGui._start(drill, 100)
  local saw = timer({ is_saw = true })
  TimerGui._start(saw, 100)
  T("  drills and saws: as in the game", drill._time_left == 100 and saw._time_left == 100)
  PlayerManager.remove_special({}, "bank_manager_key")
  T("  tier 2: a keycard is used up", #removed == 1)
  set_tier("joy", 3)
  PlayerManager.remove_special({}, "bank_manager_key")
  T("Joy tier 3: the first keycard is not used up", #removed == 1)
  PlayerManager.remove_special({}, "bank_manager_key")
  T("  the next one is", #removed == 2)
  PlayerManager.remove_special({}, "c4")
  T("  other items as in the game", #removed == 3)
  Perks.OnHeistStart()
  PlayerManager.remove_special({}, "bank_manager_key")
  T("  a new heist: once more", #removed == 3)
end

-- Jacket: melee.
do
  fresh()
  _G.PlayerStandard = { _get_melee_charge_lerp_value = function(_, t) return t end }
  _G.CopDamage = { damage_melee = function(_, a) a.result = { type = a.kill and "death" or "hurt" } return a.result end }
  local frac = { head = 1, body = 0.4, arm_l = 0.2, arm_r = 0.9, leg_l = 0, leg_r = 1 }
  local healed = {}
  local real_body = PDTI.Body
  PDTI.Body = {
    PARTS = { { id = "head" }, { id = "body" }, { id = "arm_l" }, { id = "arm_r" }, { id = "leg_l" }, { id = "leg_r" } },
    Enabled = function() return true end,
    Frac = function(id) return frac[id] end,
    IsBlack = function(id) return frac[id] <= 0 end,
    PartMax = function() return 10 end,
    HealPart = function(id, amount) healed[#healed + 1] = { id, amount }; frac[id] = frac[id] + amount / 10; return amount end
  }
  local me = {}
  local real_pu = PDTI.PlayerUnit
  PDTI.PlayerUnit = function() return me end
  Perks.InstallHooks()
  T("melee charge as in the game without Jacket", PlayerStandard._get_melee_charge_lerp_value({}, 0.4) == 0.4)
  CopDamage.damage_melee({}, { attacker_unit = me, kill = true })
  T("  a melee kill heals nothing without Jacket", #healed == 0)
  set_tier("jacket", 2)
  T("Jacket tier 2: the charge 50% faster", math.abs(PlayerStandard._get_melee_charge_lerp_value({}, 0.4) - 0.6) < 1e-9)
  T("  never past full", PlayerStandard._get_melee_charge_lerp_value({}, 0.9) == 1)
  CopDamage.damage_melee({}, { attacker_unit = me, kill = true })
  T("  tier 2: a kill heals nothing", #healed == 0)
  set_tier("jacket", 3)
  CopDamage.damage_melee({}, { attacker_unit = me, kill = false })
  T("Jacket tier 3: a hit that does not kill heals nothing", #healed == 0)
  CopDamage.damage_melee({}, { attacker_unit = {}, kill = true })
  T("  someone else's kill heals nothing", #healed == 0)
  CopDamage.damage_melee({}, { attacker_unit = me, kill = true })
  T("  your melee kill heals the most hurt part (not a black one) by 15%", #healed == 1
    and healed[1][1] == "arm_l" and math.abs(healed[1][2] - 1.5) < 1e-9, healed[1] and healed[1][1])
  CopDamage.damage_melee({}, { attacker_unit = me, kill = true })
  T("  the next kill: the most hurt part again", healed[2] and healed[2][1] == "arm_l")
  for k in pairs(frac) do if frac[k] > 0 then frac[k] = 1 end end
  T("  all full (or black): nothing to heal", Perks.OnMeleeKill() == 0 and #healed == 2)
  PDTI.Body, PDTI.PlayerUnit = real_body, real_pu
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
