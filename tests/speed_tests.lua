-- 0.9.0: loot bags, armour, weapons and throwables slow you down.
--   luajit tests/speed_tests.lua
local script = arg and arg[0] or "tests/speed_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_speed") .. "/")
ENV.install_game()
ENV.load_mod(ROOT, false)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Carry, Loadout = PDTI.Carry, PDTI.Loadout
-- The rig and backpack bonuses are tested in gear_tests.lua; here the
-- equipment changes nothing.
PDTI.Gear.SpeedBonus = function() return 0 end
PDTI.Gear.PenaltyScale = function() return 1 end

-- The game's bag classes (carrytweakdata.lua) and loot.
tweak_data.carry.types = {
  light = { move_speed_modifier = 1 }, medium = { move_speed_modifier = 0.75 },
  slightly_heavy = { move_speed_modifier = 0.6 }, heavy = { move_speed_modifier = 0.5 },
  slightly_very_heavy = { move_speed_modifier = 0.5 }, very_heavy = { move_speed_modifier = 0.25 },
  being = { move_speed_modifier = 0.5 }
}
tweak_data.carry.money.type = "medium"
tweak_data.carry.diamonds.type = "light"
tweak_data.carry.gold.type = "heavy"
tweak_data.carry.engine = { type = "very_heavy", bag_value = "engine" }
tweak_data.carry.painting = { type = "slightly_heavy", bag_value = "painting" }

-- The carry speed bonus every player has (the old Transporter skill).
local upgrades = { ["carry.movement_speed_multiplier"] = 1.5 }
local owned = {}
managers.player.upgrade_value = function(_, cat, name, default)
  local v = upgrades[cat .. "." .. name]
  if v == nil then return default end
  return v
end
managers.player.has_category_upgrade = function(_, cat, name) return owned[cat .. "." .. name] == true end

local function bags(list)
  PDTI.Reset()
  for _, id in ipairs(list) do PDTI.AddItemAuto("backpack", "loot_bag", 1, { carry_id = id }, true) end
end

------------------------------------------------------------------ loot

T("a bag's speed is the game's (heavy 0.5 x 1.5 = 75%)", near(Carry.BagSpeed("gold"), 0.75), Carry.BagSpeed("gold"))
T("medium bags are full speed, as the wiki says", near(Carry.BagSpeed("money"), 1), Carry.BagSpeed("money"))
T("very heavy is 37.5%", near(Carry.BagSpeed("engine"), 0.375), Carry.BagSpeed("engine"))

bags({ "diamonds" }); T("one light bag costs nothing", near(Carry.LootFactor(), 1), Carry.LootFactor())
bags({ "diamonds", "diamonds", "money" }); T("three light/medium bags: 15% for each after the first", near(Carry.LootFactor(), 0.7), Carry.LootFactor())
bags({ "gold" }); T("one heavy bag: 75%", near(Carry.LootFactor(), 0.75), Carry.LootFactor())
bags({ "gold", "gold" }); T("two heavy bags: 50%", near(Carry.LootFactor(), 0.5), Carry.LootFactor())
bags({ "painting" }); T("a slightly heavy bag: 90%", near(Carry.LootFactor(), 0.9), Carry.LootFactor())
bags({ "gold", "diamonds", "diamonds" }); T("heavy and light mix: 75% - 15%", near(Carry.LootFactor(), 0.6), Carry.LootFactor())
bags({ "engine", "engine" })
Carry.InvalidateCache()
T("you never stop completely", near(Carry.GetSpeedFactor(), Carry.FLOOR), Carry.GetSpeedFactor())
owned["carry.movement_penalty_nullifier"] = true
T("the skill that removes the bag penalty still works", near(Carry.LootFactor(), 1))
owned["carry.movement_penalty_nullifier"] = nil
upgrades["carry.movement_speed_multiplier"] = 1
bags({ "gold" })
T("without the carry bonus a heavy bag is 50%, like the code", near(Carry.LootFactor(), 0.5))
upgrades["carry.movement_speed_multiplier"] = 1.5
bags({ "diamonds", "diamonds", "diamonds", "diamonds" })
T("loot bags are not counted as kilograms in the load", near(Carry.LoadWeight(), 0), Carry.LoadWeight())

------------------------------------------------------- weapon weights

T("a pistol is lighter than an assault rifle at the same concealment",
  Loadout.WeaponWeight({ "pistol" }, 20) < Loadout.WeaponWeight({ "assault_rifle" }, 20))
T("better concealment is lighter", Loadout.WeaponWeight({ "assault_rifle" }, 25) < Loadout.WeaponWeight({ "assault_rifle" }, 10))
T("a concealable rifle is still heavier than a bulky pistol",
  Loadout.WeaponWeight({ "assault_rifle" }, 30) > Loadout.WeaponWeight({ "pistol" }, 0))
T("akimbo pistols weigh twice", near(Loadout.WeaponWeight({ "akimbo", "pistol" }, 20), 2 * Loadout.WeaponWeight({ "pistol" }, 20)))
T("an unknown category gets a default weight", Loadout.WeaponWeight({ "space_gun" }, 15) > 0)

------------------------------------------------------------ the loadout

tweak_data.weapon.amcar = { name_id = "AMCAR", categories = { "assault_rifle" } }
tweak_data.weapon.glock_17 = { name_id = "Chimano 88", categories = { "pistol" } }
tweak_data.blackmarket = {
  projectiles = { frag = { name_id = "Frag" }, chico_injector = { name_id = "Injector", ability = true } },
  armors = { level_7 = { name_id = "ICTV", upgrade_level = 7 }, level_1 = { name_id = "Suit", upgrade_level = 1 } }
}
local ARMOUR_MOVE = { 1.05, 1.025, 1, 0.95, 0.75, 0.65, 0.575 }
local armour_id, grenade_id, grenades = "level_7", "frag", 3
managers.blackmarket = {
  equipped_primary = function() return { weapon_id = "amcar" } end,
  equipped_secondary = function() return { weapon_id = "glock_17" } end,
  calculate_weapon_concealment = function(_, cat) return cat == "primaries" and 21 or 30 end,
  equipped_grenade = function() return grenade_id, grenades end,
  equipped_armor = function() return armour_id end
}
managers.player.body_armor_value = function(_, cat, level, default)
  if cat ~= "movement" then return default end
  return ARMOUR_MOVE[level or tweak_data.blackmarket.armors[armour_id].upgrade_level]
end
managers.player.mod_movement_penalty = function(_, v) return v end

PDTI.Reset()
local slots = {}
for _, e in ipairs(Loadout.Get()) do slots[e.slot] = e end
T("the loadout has four slots", slots.primary and slots.secondary and slots.throwable and slots.armour)
T("the primary is the AMCAR", slots.primary.name == "AMCAR")
T("the primary weighs by its category and concealment", near(slots.primary.weight, Loadout.WeaponWeight({ "assault_rifle" }, 21)))
T("the throwables weigh per piece", near(slots.throwable.weight, 1.2), slots.throwable.weight)
T("the armour weighs something", slots.armour.weight == 15)
T("the armour slows by the game's own value", near(slots.armour.penalty, 0.425), slots.armour.penalty)
T("the armour is not counted twice in the load", near(Carry.LoadWeight(), slots.primary.weight + slots.secondary.weight + 1.2), Carry.LoadWeight())
grenade_id = "chico_injector"
T("a perk deck ability weighs nothing", near(Loadout.Get()[3].weight, 0))
grenade_id = "frag"
armour_id = "level_1"
T("a suit gives no slowdown (its bonus stays the game's)", near(Carry.ArmourFactor(), 1))
armour_id = "level_7"

-------------------------------------------------------- the game's speed

-- the game: armour is part of movement_speed_multiplier
_G.PlayerManager = {
  movement_speed_multiplier = function(self, speed_state, bonus, level, health)
    local armour = self:mod_movement_penalty(self:body_armor_value("movement", level, 1))
    return 1 + armour - 1
  end
}
setmetatable(managers.player, { __index = PlayerManager })
managers.player.player_unit = function() return ENV.game.unit end
ENV.game.unit = {}
_G.PlayerStandard._get_max_walk_speed = function() return 100 end
_G.PlayerCarry = setmetatable({ _get_max_walk_speed = function(self) return PlayerStandard._get_max_walk_speed(self) * 0.5 end },
  { __index = PlayerStandard })
PlayerCarry.super = PlayerStandard
T("the speed hooks go in", Carry.InstallHooks() == true)

PDTI.Reset()
Carry.InvalidateCache()
local m = PlayerManager.movement_speed_multiplier(managers.player, "walk")
T("with an ICTV and nothing else you are exactly as fast as in the game", near(m, 0.575), m)
bags({ "gold", "gold" })
m = PlayerManager.movement_speed_multiplier(managers.player, "walk")
T("two heavy bags on top: 57.5% x 50%", near(m, 0.575 * 0.5), m)
local preview = PlayerManager.movement_speed_multiplier(managers.player, nil, nil, 7)
T("the menu's armour preview stays the game's", near(preview, 0.575), preview)

ENV.game.carry_id = "gold"
T("the bag in your hands is not slowed a second time", PlayerCarry._get_max_walk_speed({}) == 100)
ENV.game.carry_id = "person"
T("a body bag keeps the game's slowdown", PlayerCarry._get_max_walk_speed({}) == 50)
ENV.game.carry_id = nil

Carry.enabled = false
T("switched off: the game's speed", near(PlayerManager.movement_speed_multiplier(managers.player, "walk"), 0.575))
Carry.enabled = true

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
