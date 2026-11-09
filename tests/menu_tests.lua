-- 0.15.0: the Deployable slot of the game's loadout opens the inventory (main
-- menu and briefing), the briefing counts as the menu, and loose rounds come
-- in stacks of at most 100.
--   luajit tests/menu_tests.lua
local script = arg and arg[0] or "tests/menu_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_menu") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
PDTI._loaded = true

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo, Plan = PDTI.Ammo, PDTI.Plan
tweak_data.weapon.test_rifle.CLIP_AMMO_MAX = 30
tweak_data.weapon.test_pistol.CLIP_AMMO_MAX = 15
_G.managers = _G.managers or {}
managers.blackmarket = {
  equipped_primary = function() return { weapon_id = "test_rifle", blueprint = {} } end,
  equipped_secondary = function() return { weapon_id = "test_pistol", blueprint = {} } end
}

---------------------------------------------- the game's Deployable slot

local vanilla = { inventory = 0, briefing = {}, old = {} }
_G.PlayerInventoryGui = { open_deployable_menu = function() vanilla.inventory = vanilla.inventory + 1 end }
_G.NewLoadoutTab = { open_node = function(_, node) vanilla.briefing[#vanilla.briefing + 1] = node end }
_G.LoadoutItem = { open_node = function(_, node) vanilla.old[#vanilla.old + 1] = node end }
dofile(ROOT .. "lua/hooks_menu.lua")
local hooked = PlayerInventoryGui.open_deployable_menu
dofile(ROOT .. "lua/hooks_menu.lua")
T("the hooks go in once", PlayerInventoryGui.open_deployable_menu == hooked)

PlayerInventoryGui.open_deployable_menu({})
T("main menu: the Deployable slot opens the tactical inventory", PDTI.IsUIOpen() == true)
T("and not the game's deployable menu", vanilla.inventory == 0)
local right = ENV.menus[#ENV.menus].children[2]
T("the inventory shows the rig and the backpack choice and the bring list",
  right:find("bring_label") ~= nil and ENV.menus[#ENV.menus].children[1]:find("equip_rig_general_rig") ~= nil)
PDTI.SetUIOpen(false)

NewLoadoutTab.open_node({}, 6)
T("briefing: the deployable item opens the tactical inventory", PDTI.IsUIOpen() == true and #vanilla.briefing == 0)
PDTI.SetUIOpen(false)
NewLoadoutTab.open_node({}, 1)
T("briefing: the other items open the game's menus", vanilla.briefing[1] == 1 and PDTI.IsUIOpen() == false)
LoadoutItem.open_node({}, 5)
T("the older briefing loadout: the deployable opens the inventory", PDTI.IsUIOpen() == true and #vanilla.old == 0)
PDTI.SetUIOpen(false)
LoadoutItem.open_node({}, 2)
T("and its other items stay the game's", vanilla.old[1] == 2)

-- Without BeardLib the game's menu opens as before.
local available = PDTI.IsUIAvailable
PDTI.IsUIAvailable = function() return false end
PlayerInventoryGui.open_deployable_menu({})
T("without BeardLib the game's deployable menu opens", vanilla.inventory == 1 and PDTI.IsUIOpen() == false)
PDTI.IsUIAvailable = available

local mod = io.open(ROOT .. "mod.txt"):read("*a")
T("mod.txt hooks the Inventory screen and the briefing",
  mod:find('"lib/managers/menu/playerinventorygui"') and mod:find('"lib/managers/menu/missionbriefinggui"'))
T("the I key does not open the inventory in the main menu", mod:find('"run_in_menu" : false') ~= nil)

-------------------------------------------- the briefing is the menu

PDTI.Reset()
PDTI.SetSessionOnly(false)
ENV.game.unit = nil
-- The heist has loaded (GameSetup.init_finalize), the player has not spawned.
local registered
_G.Hooks = { PostHook = function(_, _, fn, _, cb) registered = cb end }
_G.GameSetup = {}
_G.PDTI_HEIST_START_HOOKED = nil
dofile(ROOT .. "lua/heist_start.lua")
registered()
T("the briefing is not the heist yet", PDTI.session_only ~= true and PDTI.InHeist() == false)
T("in the briefing the rig can be changed", PDTI.RequestEquip("rig", "medical_rig") == true)
T("and what you bring", Plan.Add("first_aid_kit") == true)
PDTI.LoadProfile()
T("changes in the briefing are saved", PDTI.GetEquipment().rig == "medical_rig" and Plan.Count("first_aid_kit") == 1)

-- The player spawns: the game's input function runs.
_G.PlayerStandard._get_input = function() return {} end
dofile(ROOT .. "lua/hooks_game.lua")
PlayerStandard._get_input({}, 1, 0.016, false)
T("when the player spawns nothing is saved any more", PDTI.session_only == true and PDTI.InHeist() == true)
local fak = PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" end)[1]
PDTI.RemoveItem(fak.container, fak.item.instance_id)
PDTI.LoadProfile()
T("so what is used in the heist comes back", Plan.Count("first_aid_kit") == 1)
T("a heist cannot change the rig", PDTI.RequestEquip("rig", "general_rig") == false)

-- A weapon bound before the first input frame still stops the saving.
PDTI.SetSessionOnly(false)
Plan.Bind({}, { slot = "primary", key = "k", capacity = 30 })
T("binding a weapon's ammunition means the heist has started", PDTI.session_only == true)
PDTI.SetSessionOnly(false)

--------------------------------------------------- stacks of 100

PDTI.Reset()
T("a loose stack holds at most 100 rounds", PDTI.items.loose_ammo.max_stack == 100 and Ammo.MAX_STACK == 100)
local info = { caliber = "X", pid = "x", mag_class = "assault_rifle" }
Ammo.AddLooseKey("k|x", 250, info)
local sizes = {}
for _, s in ipairs(Ammo.LooseStacks("k|x")) do sizes[#sizes + 1] = s.rounds end
table.sort(sizes)
T("250 rounds: two full stacks and one of 50", table.concat(sizes, ",") == "50,100,100", table.concat(sizes, ","))
Ammo.AddLooseKey("k|x", 60, info)
sizes = {}
for _, s in ipairs(Ammo.LooseStacks("k|x")) do sizes[#sizes + 1] = s.rounds end
table.sort(sizes)
T("more rounds fill the open stack first, then start a new one", table.concat(sizes, ",") == "10,100,100,100", table.concat(sizes, ","))

PDTI.Reset()
for _ = 1, 4 do Plan.Add("loose:primary") end
T("the menu's loose rounds are in stacks of 100 too", Plan.LooseRounds("primary") == 120 and #Plan.LooseStacks("primary") == 2)

-- An older save with a stack of 250: it becomes stacks of 100.
do
  local old = {
    schema_version = 7, next_id = 5,
    equipment = { backpack = "large_backpack", rig = "general_rig" },
    containers = { pockets = { items = {} }, rig = { items = {} }, rig_2 = { items = {} }, rig_3 = { items = {} },
      backpack = { items = { { instance_id = 3, item_id = "loose_ammo", x = 0, y = 0, rotated = false, amount = 250,
        data = { queue_key = "q", mag_class = "pistol" } } } } }
  }
  local f = io.open(TMP .. "pdti_inventory.json", "w"); f:write(json.encode(old)); f:close()
  os.remove(TMP .. "pdti_inventory.json.bak")
  PDTI.LoadProfile(1)
  local total, n, ids = 0, 0, {}
  for _, entry in ipairs(PDTI.FindItems(function(_, item) return item.item_id == "loose_ammo" end)) do
    total = total + entry.item.amount
    n = n + 1
    ids[entry.item.instance_id] = true
  end
  T("an old stack of 250 is kept as 100 + 100 + 50", total == 250 and n == 3, total .. " in " .. n)
  T("each with its own id", ids[3] and ids[5] and ids[6])
  T("and the state is valid", PDTI.ValidateState() == true)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
