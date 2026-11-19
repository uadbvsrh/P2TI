-- 0.30.0: the safehouse as your base. In the safehouse the mod behaves as in
-- the menu (everything is saved, the whole screen opens, the heist systems
-- leave the inventory alone), the game goes there when it starts and after a
-- job finished offline, and the probe logs where you stand.
--   luajit tests/safehouse_tests.lua
local script = arg and arg[0] or "tests/safehouse_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_safehouse") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 }, game_settings = { single_player = false } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
dofile(ROOT .. "lua/armour.lua")
PDTI._loaded = true

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo, Plan, Loot, Dep, Home = PDTI.Ammo, PDTI.Plan, PDTI.Loot, PDTI.Deployables, PDTI.Safehouse
tweak_data.weapon.test_rifle.CLIP_AMMO_MAX = 30
tweak_data.weapon.test_pistol.CLIP_AMMO_MAX = 15
managers.blackmarket = {
  equipped_primary = function() return { weapon_id = "test_rifle", blueprint = {} } end,
  equipped_secondary = function() return { weapon_id = "test_pistol", blueprint = {} } end
}
local job_id = nil
managers.job = { current_job_id = function() return job_id end }
local function logged(text)
  for _, line in ipairs(ENV.logs) do if tostring(line):find(text, 1, true) then return true end end
  return false
end

------------------------------------------------------------ where you are

T("no job: not the safehouse", PDTI.InSafehouse() == false)
job_id = "chill"
T("the job \"chill\" is the safehouse", PDTI.InSafehouse() == true)
job_id = "chill_combat"
T("the safehouse raid is a heist", PDTI.InSafehouse() == false)
job_id = "branchbank"
T("a heist is not the safehouse", PDTI.InSafehouse() == false)
job_id = "chill"
_G.restoration = {}
T("with restoration-mod the safehouse stays a heist", PDTI.InSafehouse() == false and Home.Enabled() == false)
_G.restoration = nil
local jm = managers.job
managers.job = nil
T("no job manager: not the safehouse, no error", PDTI.InSafehouse() == false)
managers.job = jm

-------------------------------------------------- the safehouse is the menu

-- The level loads, then the player spawns and the game's input runs.
PDTI.Reset()
PDTI.SetSessionOnly(false)
ENV.game.unit = nil
local registered
_G.Hooks = { PostHook = function(_, _, _, _, cb) registered = cb end }
_G.GameSetup = {}
_G.PDTI_HEIST_START_HOOKED = nil
dofile(ROOT .. "lua/heist_start.lua")
_G.PlayerStandard._get_input = function() return {} end
dofile(ROOT .. "lua/hooks_game.lua")

job_id = "chill"
T("what you bring is chosen before the safehouse", Plan.Add("first_aid_kit") == true and Plan.Count("first_aid_kit") == 1)
PDTI.AddItemAuto("rig", "spare_magazine", 1, { queue_key = "X", rounds = 5, capacity = 30 }, true)
local restock_before = Plan.restock
registered()
T("loading the safehouse clears nothing", Plan.Count("first_aid_kit") == 1
  and #PDTI.FindItems(function(_, item) return item.item_id == "spare_magazine" end) == 1)
T("and starts no restock bill", Plan.restock == restock_before)
PDTI.RemoveItem("rig", PDTI.FindItems(function(_, item) return item.item_id == "spare_magazine" end)[1].item.instance_id)

ENV.make_unit()
PlayerStandard._get_input({}, 1, 0.016, false)
T("spawned in the safehouse: still saved, still the menu", PDTI.session_only ~= true and PDTI.InHeist() == false)
T("the rig can be changed in the safehouse", PDTI.RequestEquip("rig", "medical_rig") == true)
T("and what you bring", Plan.Add("first_aid_kit") == true and Plan.Count("first_aid_kit") == 2)
PDTI.LoadProfile()
T("what you change in the safehouse is saved", PDTI.GetEquipment().rig == "medical_rig" and Plan.Count("first_aid_kit") == 2)

-- The heist systems leave the inventory alone.
local wep = ENV.make_weapon("test_rifle")
ENV.game.unit:set_weapon(wep)
T("the ammunition system is off in the safehouse", Ammo.On() == false and Ammo.SkipReason(wep) == "the safehouse")
T("a weapon does not take the plan's magazines", Plan.Bind(wep, { slot = "primary", key = "K" }) == false
  and PDTI.session_only ~= true)
ENV.game.carry_id = "gold"
Loot.Tick()
T("nothing you carry becomes an item", #PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end) == 0)
ENV.game.carry_id = nil
PDTI.AddItemAuto("pockets", "trip_mine", 1, nil, true)
PDTI.SetDeployable("trip_mine")
local placements = 0
local equipment = { use_trip_mine = function() placements = placements + 1; return true end }
local function mines() return #PDTI.FindItems(function(_, item) return item.item_id == "trip_mine" end) end
T("no deployable of the inventory is placed or used", Dep.Manages() == false and Dep.BlocksGame() == false
  and Dep.Place(equipment) == false and placements == 0 and mines() == 1 and Dep.ItemToHandFor("trip_mine") == nil,
  placements .. "/" .. mines())
T("the pick you made stays", (function() Dep.OnHeistStart(); return PDTI.GetDeployable() == "trip_mine" end)())
T("no deployable line on the HUD", PDTI.DeployHud.Text() == nil)
local ok_plate, why_plate = PDTI.Armour.StartPlate()
T("no armour plate is used", ok_plate == false and why_plate == "Not in the safehouse", why_plate)
Ammo.settings.enabled = false
T("switched off is still \"mod disabled\"", Ammo.SkipReason(wep) == "mod disabled")
Ammo.settings.enabled = true

-- The whole screen opens with the inventory key.
T("the inventory key opens the screen", PDTI.ToggleUI() == true and PDTI.IsUIOpen() == true)
local shop
for _, w in ipairs(ENV.menus[#ENV.menus].children) do if w.params.name == "pdti_shop" then shop = w end end
T("it is the menu's screen: bring list, captured loot and stash", shop ~= nil and shop:find("shop_tab_bring") ~= nil
  and shop:find("shop_tab_captured") ~= nil and shop:find("shop_tab_stash") ~= nil and shop:find("bring_label") ~= nil)
T("with the rig and backpack choice", ENV.menus[#ENV.menus].children[1]:find("equip_rig_general_rig") ~= nil)
PDTI.SetUIOpen(false)

-- Arriving in the safehouse: one hint about the inventory key.
local hints = {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end
Home.Reset()
for _ = 1, 30 do Home.GameTick(0.1) end
T("no hint in the first seconds", #hints == 0)
for _ = 1, 20 do Home.GameTick(0.1) end
T("then one hint: what the inventory key opens here", #hints == 1 and hints[1]:find("inventory key", 1, true) ~= nil,
  hints[1])
for _ = 1, 100 do Home.GameTick(0.1) end
T("only once", #hints == 1)
Home.Reset()
PDTI.Stash._Data().pending = { { id = 1, carry_id = "gold", quality = 1, mods = "", value = 1 },
  { id = 2, carry_id = "gold", quality = 1, mods = "", value = 1 } }
for _ = 1, 50 do Home.GameTick(0.1) end
T("captured bags waiting are named in it", hints[2] ~= nil and hints[2]:find("2 captured bag", 1, true) ~= nil, hints[2])
PDTI.Stash._Data().pending = {}
Home.Reset()
job_id = "branchbank"
for _ = 1, 100 do Home.GameTick(0.1) end
T("no such hint in a heist", #hints == 2)

-- A heist is as before.
job_id = "branchbank"
T("in a heist the ammunition system runs", Ammo.On() == true and Ammo.SkipReason(wep) ~= "the safehouse")
T("and the deployables are the inventory's", Dep.Manages() == true and Dep.ItemToHandFor("trip_mine") == "trip_mine")
T("a trip mine is placed and taken out of the inventory", Dep.Place(equipment) == true and placements == 1 and mines() == 0)
local spawns, real_spawn = {}, PDTI.Armory.OnSpawn
PDTI.Armory.OnSpawn = function(unit) spawns[#spawns + 1] = unit end
local unit_a, unit_b = { name = "a" }, { name = "b" }
PlayerStandard._get_input({ _unit = unit_a }, 2, 0.016, false)
T("spawned in a heist: nothing is saved any more", PDTI.session_only == true and PDTI.InHeist() == true)
T("  the weapons follow the slots once the player is there", #spawns == 1 and spawns[1] == unit_a)
PlayerStandard._get_input({ _unit = unit_a }, 2.1, 0.016, false)
PlayerStandard._get_input({ _unit = unit_b }, 2.2, 0.016, false)
T("  once per player unit (again after custody)", #spawns == 2 and spawns[2] == unit_b)
PDTI.Armory.OnSpawn = real_spawn
T("the rig cannot be changed in a heist", PDTI.RequestEquip("rig", "general_rig") == false)
job_id = "chill_combat"
T("the safehouse raid: a heist too", PDTI.InHeist() == true and Ammo.On() == true)
PDTI.SetSessionOnly(false)
PDTI.SetDeployable(nil)

---------------------------------------------------- the way to the safehouse

local went = {}
_G.MenuCallbackHandler = {
  play_single_player = function() went[#went + 1] = "single"; Global.game_settings.single_player = true end,
  start_single_player_job = function(_, data) went[#went + 1] = data.job_id .. ":" .. data.difficulty end
}
local dialog, saving, node, session = false, false, "main", nil
managers.system_menu = { is_active = function() return dialog end }
managers.savefile = { is_active = function() return saving end }
managers.menu = { active_menu = function()
  return { id = "menu_main", logic = { selected_node = function() return { parameters = function() return { name = node } end } end } }
end }
managers.network = { session = function() return session end }
-- The black screen over the menu.
local covers, cover_seq = {}, 0
local plain_color = _G.Color
_G.Color = setmetatable({ black = "black" }, { __call = function(_, ...) return plain_color(...) end })
managers.overlay_effect = {
  play_effect = function(_, data) cover_seq = cover_seq + 1; covers[cover_seq] = data; return cover_seq end,
  stop_effect = function(_, id) covers[id] = nil end
}
local function covered() return next(covers) ~= nil end
local function boot()
  Global.pdti_home = nil
  Global.load_start_menu_lobby, Global.load_crime_net, Global.boot_invite, Global.exe_argument_level = nil, nil, nil, nil
  Global.game_settings.single_player = false
  Home.pending = nil
  Home.Cover(false)
  covers = {}
  went = {}
  dialog, saving, node, session = false, false, "main", nil
  job_id = nil
end
local function tick(seconds, step)
  step = step or 0.1
  for _ = 1, math.floor(seconds / step + 0.5) do Home.MenuTick(step) end
end

boot()
T("the game starts: the safehouse is planned", Home.OnMenuMain(false) == true and Home.pending ~= nil)
T("a black screen over the menu at once", covered() and covers[cover_seq].color == "black" and covers[cover_seq].fade_in == 0)
Home.MenuTick(0)
T("at once: the game's own way into the safehouse", went[1] == "single" and went[2] == "chill:normal", table.concat(went, ","))
T("the black screen stays for the loading", covered())
T("the safehouse's briefing will be passed", Global.pdti_home.skip_briefing == true)
T("once", (function() tick(2); return #went == 2 end)())
T("the second time in the menu you stay there", Home.OnMenuMain(false) == false and Home.pending == nil)

boot()
Ammo.settings.safehouse_home = false
T("the option off: the menu as before", Home.OnMenuMain(false) == false and Home.pending == nil)
Ammo.settings.safehouse_home = true
T("switching it on later does not send you off from the menu", Home.OnMenuMain(false) == false)

boot()
T("an invite at start: the menu", Home.OnMenuMain(true) == false and logged("you were invited"))
boot()
Global.exe_argument_level = "branchbank"
T("a level asked for at start: the menu", Home.OnMenuMain(false) == false)
boot()
Global.load_start_menu_lobby = true
T("a lobby: the menu", Home.OnMenuMain(false) == false)

-- Dialogs, the save and the player going elsewhere.
boot()
Home.OnMenuMain(false)
dialog = true
tick(5)
T("a dialog is open: it waits", #went == 0 and Home.pending ~= nil)
T("no black screen over the dialog", not covered())
dialog = false
tick(0.2)
T("the dialog closed: it goes", #went == 2)
boot()
Home.OnMenuMain(false)
saving = true
tick(3)
T("the save is busy: it waits", #went == 0 and Home.pending ~= nil)
tick(Home.GIVE_UP)
T("busy for too long: you stay in the menu", #went == 0 and Home.pending == nil and logged("busy for too long"))
T("the menu is shown again", not covered())
boot()
Home.OnMenuMain(false)
node = "options"
tick(2)
T("you opened another page first: you stay there", #went == 0 and Home.pending == nil and logged("\"options\""))
T("and you see it", not covered())

-- After a job.
boot()
Home.OnLevelStart()
T("a level loaded: the game is past its start", Home.OnMenuMain(false) == false)
boot()
Home.OnLevelStart()
job_id = "branchbank"
Global.game_settings.single_player = true
Home.OnMissionEnd()
job_id = nil
T("an offline job ended: back to the safehouse", Home.OnMenuMain(false) == true)
tick(1.2)
T("it goes", went[2] == "chill:normal")
boot()
Home.OnLevelStart()
job_id = "branchbank"
Global.game_settings.single_player = false
Home.OnMissionEnd()
job_id = nil
T("a job with a crew ended: the menu or the lobby as usual", Home.OnMenuMain(false) == false)
boot()
Home.OnLevelStart()
T("a job left before its end: the menu", Home.OnMenuMain(false) == false)
boot()
Home.OnLevelStart()
job_id = "chill"
Global.game_settings.single_player = true
Home.OnMissionEnd()
job_id = nil
Global.load_crime_net = true
T("leaving the safehouse: Crime.net as usual", Home.OnMenuMain(false) == false)
boot()
Home.OnLevelStart()
job_id = "branchbank"
Global.game_settings.single_player = true
Home.OnMissionEnd()
Home.OnLevelStart()
job_id = nil
T("the next day of a job starts: nothing has ended yet", Home.OnMenuMain(false) == false)
boot()
session = {}
T("online at start: the menu", Home.OnMenuMain(false) == false and logged("you are online"))
boot()
_G.MenuCallbackHandler.start_single_player_job = function() error("no such job") end
Home.OnMenuMain(false)
tick(1.2)
T("the game cannot start it: logged, no error, the menu", Home.pending == nil and logged("could not be started"))
T("the menu is shown again (no black screen)", not covered() and Global.pdti_home.skip_briefing == nil)
boot()
Ammo.settings.safehouse_home = false
Home.OnMenuMain(false)
T("the option off: no black screen", not covered())
Ammo.settings.safehouse_home = true

-- The hooks on the game's classes.
boot()
local seen = { enter = 0, update = 0 }
_G.MenuMainState = {
  at_enter = function(self, old) seen.enter = seen.enter + 1; Global.boot_invite = nil; return "entered" end,
  update = function(self, t, dt) seen.update = seen.update + 1 end
}
_G.MissionEndState = { at_enter = function(self) seen.ended = true end }
went = {}
_G.MenuCallbackHandler = {
  play_single_player = function() went[#went + 1] = "single" end,
  start_single_player_job = function(_, data) went[#went + 1] = data.job_id end
}
T("the menu hooks go in", Home.InstallMenuHooks() == true)
local hooked_enter = MenuMainState.at_enter
dofile(ROOT .. "lua/hooks_home.lua")
T("once (hooks_home.lua and main.lua may both ask)", MenuMainState.at_enter == hooked_enter)
local armory_menu, real_on_menu = 0, PDTI.Armory.OnMenu
PDTI.Armory.OnMenu = function() armory_menu = armory_menu + 1 end
local start_menu, real_start = 0, PDTI.SaveSlot.OnMenu
PDTI.SaveSlot.OnMenu = function() start_menu = start_menu + 1 end
T("the game's own code still runs, and you go in that same frame",
  MenuMainState.at_enter({}, {}) == "entered" and seen.enter == 1 and Home.pending == nil and went[2] == "chill",
  table.concat(went, ","))
T("  the armory looks at the menu too (a heist left unfinished is lost)", armory_menu == 1)
T("  and the mod's own save its start dialog", start_menu == 1)
PDTI.Armory.OnMenu = real_on_menu
PDTI.SaveSlot.OnMenu = real_start
boot()
went = {}
dialog = true
MenuMainState.at_enter({}, {})
T("a dialog at the menu: it waits", Home.pending ~= nil and #went == 0)
dialog = false
local ins_ticks, real_ins = 0, PDTI.Insurance.Tick
PDTI.Insurance.Tick = function() ins_ticks = ins_ticks + 1 end
for _ = 1, 3 do MenuMainState.update({}, 0, 0.1) end
T("the menu's update takes you there once it is closed", seen.update == 3 and went[2] == "chill", table.concat(went, ","))
T("  and looks at insured weapons coming back, every frame (0.45.0)", ins_ticks == 3, ins_ticks)
Home.pending = nil
MenuMainState.update({}, 0, 0.1)
T("  also with no trip waiting", ins_ticks == 4 and seen.update == 4)
PDTI.Insurance.Tick = real_ins
boot()
Global.boot_invite = { lobby = 1 }
MenuMainState.at_enter({}, {})
T("an invite is seen before the game uses it up", Home.pending == nil and Global.boot_invite == nil)
-- The weapon racks are the game's again.
local armory = { game_menu = 0 }
_G.AccessWeaponMenuInteractionExt = { interact = function(self, player) armory.game_menu = armory.game_menu + 1; return true end }
_G.CivilianHeisterInteractionExt = { interact = function(self, player) self.answered = (self.answered or 0) + 1; return true end }
local game_interacts = 0
_G.PlayerCivilian = { _check_action_interact = function(self, t, input) game_interacts = game_interacts + 1; return "game" end }
T("the end screen, heister and room hooks go in", Home.InstallGameHooks() == true)
job_id = "chill"
PDTI.SetUIOpen(false)
AccessWeaponMenuInteractionExt.interact({}, {})
T("the weapon racks: the game's weapon menu", armory.game_menu == 1 and not PDTI.IsUIOpen())
job_id = nil
boot()
Home.OnLevelStart()
job_id = "branchbank"
Global.game_settings.single_player = true
MissionEndState.at_enter({})
T("the end screen remembers the job ended", seen.ended == true and Global.pdti_home.after_job == true)
-- A raid on the safehouse is waiting: the game's raid contract opens.
local raided, opened_nodes = false, {}
managers.custom_safehouse = { is_being_raided = function() return raided end }
managers.menu.open_node = function(_, name) opened_nodes[#opened_nodes + 1] = name end
local raid = { played = 0, ignored = 0 }
went = {}
_G.MenuCallbackHandler = {
  play_single_player = function() went[#went + 1] = "single"; Global.game_settings.single_player = true end,
  start_single_player_job = function(_, data) went[#went + 1] = data.job_id end,
  play_chill_combat = function(self, item)
    raid.played = raid.played + 1
    raid.offline = Global.game_settings.single_player == true
  end,
  ignore_chill_combat = function(self, item) raid.ignored = raid.ignored + 1; raided = false end
}
T("the raid contract's hooks go in", Home.InstallRaidHooks() == true)
local function start_with_raid()
  boot()
  opened_nodes, went = {}, {}
  raided = true
  Home.OnMenuMain(false)
  Home.MenuTick(0)
end
start_with_raid()
T("a raid is waiting: the raid contract opens, not the safehouse", opened_nodes[1] == "crimenet_contract_chill"
  and #went == 0 and Home.pending == nil and Home.raid_offered == true and logged("under attack"))
T("the menu is not hidden under it", not covered())
MenuCallbackHandler.play_chill_combat(MenuCallbackHandler, {})
T("Defend: offline first, then the game's own raid start", raid.played == 1 and raid.offline == true
  and went[1] == "single" and Home.raid_offered == nil and logged("defending the safehouse"))
T("the raid's briefing is not passed", Global.pdti_home.skip_briefing == nil)
start_with_raid()
MenuCallbackHandler.ignore_chill_combat(MenuCallbackHandler, {})
T("Ignore: the game's own ignore", raid.ignored == 1 and Home.pending ~= nil and covered())
raided = true -- even if the game still said so, it is not asked again
Home.MenuTick(0)
T("then on to the safehouse", went[2] == "chill" and #opened_nodes == 1, table.concat(went, ","))
start_with_raid()
Home.OnMenuMain(false) -- back to the main menu (Back), the next time in the menu
T("Back: you stay in the menu", Home.pending == nil and Home.raid_offered == nil and #went == 0)
boot()
raid.played = 0
went = {}
Global.game_settings.single_player = false
MenuCallbackHandler.play_chill_combat(MenuCallbackHandler, {})
T("the raid from the game's own menus: untouched", raid.played == 1 and #went == 0)
MenuCallbackHandler.ignore_chill_combat(MenuCallbackHandler, {})
T("Ignore in the game's own menus: you stay where you are", Home.pending == nil and not covered())
boot()
raided = false
opened_nodes, went = {}, {}
Home.OnMenuMain(false)
Home.MenuTick(0)
T("no raid: the safehouse as before", #opened_nodes == 0 and went[2] == "chill")
start_with_raid()
T("the option off: no raid contract either", (function()
  boot(); opened_nodes = {}; raided = true
  Ammo.settings.safehouse_home = false
  local planned = Home.OnMenuMain(false)
  Ammo.settings.safehouse_home = true
  return planned == false and #opened_nodes == 0 end)())
boot()
opened_nodes, went = {}, {}
raided = true
managers.menu.open_node = function() error("no such node") end
Home.OnMenuMain(false)
Home.MenuTick(0)
T("the contract cannot open: the safehouse instead", went[2] == "chill" and logged("could not be shown"))
managers.menu.open_node = nil
raided = false

-- The rooms: talking to a room's heister opens the room's menu.
_G.tweak_data = _G.tweak_data or {}
tweak_data.safehouse = { rooms = {
  { room_id = "german", name_id = "menu_german", help_id = "menu_cs_help_wolf", tier_max = 3 },
  { room_id = "russian", name_id = "menu_russian", help_id = "menu_cs_help_dallas", tier_max = 3 },
  { room_id = "spanish", name_id = "menu_spanish", help_id = "menu_cs_help_chains", tier_max = 3 },
  { room_id = "ecp", name_id = "menu_ecp", help_id = "menu_cs_help_ecp", tier_max = 3 },
  { room_id = "terry", name_id = "menu_terry", help_id = "menu_cs_help_terry", tier_max = 3 },
  { room_id = "myh", name_id = "menu_myh", help_id = "menu_cs_help_myh", tier_max = 3 }
} }
_G.CriminalsManager = { convert_new_to_old_character_workname = function(w)
  return ({ hoxton = "american", wolf = "german", dallas = "russian", chains = "spanish" })[w] or w end }
local coins, tiers, unlocked, bought = 30, { german = 1, russian = 3, ecp = 1, spanish = 3, terry = 3, myh = 1 },
  { german = 1, russian = 3, ecp = 1, spanish = 3, terry = 3, myh = 1 }, {}
local PRICES = { 0, 12, 24 }
managers.custom_safehouse = {
  get_room_current_tier = function(_, r) return tiers[r] end,
  get_room_max_tier = function() return 3 end,
  get_next_tier_unlocked = function(_, r) return unlocked[r] + 1 end,
  get_upgrade_cost = function(_, r, t) return PRICES[t] end,
  can_afford_room_tier = function(_, r, t) return PRICES[t] <= coins end,
  purchase_room_tier = function(_, r, t) bought[#bought + 1] = r .. ":" .. t; unlocked[r] = t; coins = coins - PRICES[t] end,
  set_room_tier = function(_, r, t) tiers[r] = t end,
  coins = function() return coins end
}
managers.localization = { text = function(_, id) return ({ menu_german = "Wolf's workshop", menu_cs_help_wolf_2 = "more tools" })[id] or id end }
local dialogs, saves = {}, 0
managers.system_menu = { is_active = function() return false end, show = function(_, d) dialogs[#dialogs + 1] = d end }
managers.savefile = { is_active = function() return false end, save_progress = function() saves = saves + 1 end }
local function button(d, prefix)
  for _, b in ipairs(d.button_list) do if b.text:sub(1, #prefix) == prefix then return b end end
end
job_id = "chill"
T("a heister's room: the game's own mapping", Home.RoomOfHeister({ character = "wolf" }) == "german"
  and Home.RoomOfHeister({ tweak_data = "talk_to_heister_dallas" }) == "russian"
  and Home.RoomOfHeister({ character = "ecp_female" }) == "ecp" and Home.RoomOfHeister({ character = "butler" }) == nil)
local wolf = setmetatable({ character = "wolf" }, { __index = CivilianHeisterInteractionExt })
CivilianHeisterInteractionExt.interact(wolf, {})
local d = dialogs[#dialogs]
T("talking to Wolf: he answers, then his room's menu", wolf.answered == 1 and d and d.title == "Wolf's workshop"
  and d.text:find("Tier 1 of 3", 1, true) and d.text:find("coins: 30", 1, true) and d.text:find("more tools", 1, true))
T("Upgrade, Close (no own action in Wolf's room)", button(d, "Upgrade to tier 2 (12 coins)") and #d.button_list == 2
  and d.button_list[#d.button_list].cancel_button == true)
button(d, "Upgrade").callback_func()
T("Upgrade: the game's own purchase, saved", bought[1] == "german:2" and tiers.german == 2 and coins == 18 and saves == 1
  and logged("upgraded to tier 2") and hints[#hints] and hints[#hints]:find("tier 2", 1, true))
CivilianHeisterInteractionExt.interact(wolf, {})
d = dialogs[#dialogs]
T("tier 3 costs more than you have: no Upgrade button, said why", not button(d, "Upgrade") and d.text:find("not enough coins", 1, true)
  and Home.UpgradeRoom("german") == false and bought[2] == nil)
-- Chains' room: "Menu inventory" leaves for the main menu's inventory.
local left = 0
MenuCallbackHandler._dialog_end_game_yes = function() left = left + 1 end
local chains = setmetatable({ character = "chains" }, { __index = CivilianHeisterInteractionExt })
CivilianHeisterInteractionExt.interact(chains, {})
d = dialogs[#dialogs]
T("Chains' room at its top tier: Menu inventory and Close", d.title == "menu_spanish" and #d.button_list == 2
  and button(d, "Menu inventory"))
button(d, "Menu inventory").callback_func()
T("Menu inventory: the game's own way out, marked for the way back", left == 1 and Global.pdti_home.to_inventory == true
  and logged("leaving for the menu inventory"))
Global.pdti_home.to_inventory = nil
PDTI.SetUIOpen(false)
-- 0.43.0: Duke's room, the game's Story Line (offline).
local was_single = Global.game_settings.single_player
Global.game_settings.single_player = true
local duke = setmetatable({ character = "myh" }, { __index = CivilianHeisterInteractionExt })
CivilianHeisterInteractionExt.interact(duke, {})
d = dialogs[#dialogs]
T("Duke's room: Story Line first (picked), then Upgrade and Close", d.title == "menu_myh" and #d.button_list == 3
  and d.button_list[1].text:find("^Story Line") and d.focus_button == 1 and button(d, "Upgrade to tier 2")
  and d.button_list[3].cancel_button == true)
button(d, "Story Line").callback_func()
T("  Story Line: the game's own way out, marked for the way back", left == 2 and Global.pdti_home.to_story == true
  and Global.pdti_home.to_inventory == nil and logged("leaving for the Story Line"))
Global.pdti_home.to_story = nil
CivilianHeisterInteractionExt.interact(chains, {})
T("  no other room has it", not button(dialogs[#dialogs], "Story Line") and #dialogs[#dialogs].button_list == 2)
Global.game_settings.single_player = false
CivilianHeisterInteractionExt.interact(duke, {})
T("  online: no Story Line, it stays the game's", not button(dialogs[#dialogs], "Story Line")
  and Home.ToStoryLine() == false and Global.pdti_home.to_story == nil and left == 2)
Global.game_settings.single_player = was_single
PDTI.SetUIOpen(false)
local dallas = setmetatable({ character = "dallas" }, { __index = CivilianHeisterInteractionExt })
CivilianHeisterInteractionExt.interact(dallas, {})
d = dialogs[#dialogs]
T("a room at its top tier, no own action: Close only", d.title == "menu_russian" and #d.button_list == 1
  and d.text:find("top tier", 1, true))
-- Scarface runs the market.
local opened = 0
local real_open = PDTI.OpenMarket
PDTI.OpenMarket = function() opened = opened + 1; return true end
local terry = setmetatable({ character = "terry" }, { __index = CivilianHeisterInteractionExt })
CivilianHeisterInteractionExt.interact(terry, {})
d = dialogs[#dialogs]
T("Scarface's room: Market and Close", d.title == "menu_terry" and #d.button_list == 2 and button(d, "Market"))
button(d, "Market").callback_func()
T("  Market opens the market", opened == 1 and logged("the market is open (Scarface)"))
T("  no other room has it", not button(dialogs[#dialogs - 1], "Market"))
local real_enabled = PDTI.Market.Enabled
PDTI.Market.Enabled = function() return false end
CivilianHeisterInteractionExt.interact(terry, {})
T("  the loot system off: no Market button", not button(dialogs[#dialogs], "Market"))
PDTI.Market.Enabled, PDTI.OpenMarket = real_enabled, real_open
local n = #dialogs
local daily = setmetatable({ character = "wolf", is_daily_contractor = function() return true end,
  is_daily_accepted = function() return false end }, { __index = CivilianHeisterInteractionExt })
CivilianHeisterInteractionExt.interact(daily, {})
T("taking the daily side job: the game's talk alone", #dialogs == n and daily.answered == 1)
T("and you are told to talk again", logged("took the daily side job") and hints[#hints]:find("Talk to them again", 1, true))
local function heister_unit(ext, pos)
  local u = {}
  function u:position() return pos end
  function u:interaction() return ext end
  return u
end
managers.interaction = { _interactive_units = {
  heister_unit({ character = "wolf", _active = true }, { x = 10, y = 20, z = 0 }),
  heister_unit({ tweak_data = "talk_to_heister_dallas", _active = false }, { x = 1, y = 2, z = 3 }),
  heister_unit({ tweak_data = "access_weapon_primary" }, { x = 0, y = 0, z = 0 }),
  heister_unit({ character = "butler", _active = true }, { x = 5, y = 5, z = 5 })
} }
T("the heisters here are listed with their rooms", Home.LogHeisters() == 3
  and logged("heisters here: butler (no room) at (5, 5, 5); dallas (russian) at (1, 2, 3) off; wolf (german) at (10, 20, 0)"))
managers.interaction = { _interactive_units = {} }
Home.LogHeisters()
T("none found is said too", logged("heisters here: none found"))

-- Chains' room: interact (aiming at nothing) inside it leaves for the menu inventory.
local here = { x = 0, y = 0, z = 0 }
ENV.make_unit()
ENV.game.unit.position = function() return here end
local active = nil
managers.interaction = { _interactive_units = {
  heister_unit({ character = "wolf", _active = true }, { x = 954, y = -1765, z = -400 }),
  heister_unit({ character = "chains", _active = true }, { x = 1650, y = -1674, z = 0 })
}, active_unit = function() return active end }
managers.localization = { text = function(_, id) return ({ menu_spanish = "Chains' room" })[id] or id end }
local exits = 0
MenuCallbackHandler._dialog_end_game_yes = function() exits = exits + 1 end
job_id = "chill"
Home.zone_at, Home.zones_found, Home.in_room, Home.zone_wait = nil, nil, nil, nil
Home.hinted = true
here = { x = 1000, y = -1765, z = -400 }
Home.GameTick(0.3)
T("the room is where its heister stands", Home.zones_found == true and Home.zone_at.spanish.x == 1650
  and logged("the room spanish is around (1650, -1674, 0)"))
T("Wolf's room downstairs is not Chains' (a floor between)", Home.in_room == nil)
local press = { btn_interact_press = true }
T("interact downstairs: the game's", PlayerCivilian._check_action_interact({}, 0, press) == "game" and exits == 0)
here = { x = 1950, y = -1974, z = 20 } -- out of his usual spot's reach: where he stands counts
local before = #hints
Home.GameTick(0.3)
T("walking into Chains' room: a hint says what to do", Home.in_room == "spanish" and #hints == before + 1
  and hints[#hints]:find("Chains' room: press interact", 1, true))
Home.GameTick(0.3)
T("once per entry", #hints == before + 1)
game_interacts = 0
T("interact there, aiming at nothing: off to the menu inventory", PlayerCivilian._check_action_interact({}, 0, press) == false
  and exits == 1 and game_interacts == 0 and Global.pdti_home.to_inventory == true and logged("the room spanish: to the menu inventory"))
Global.pdti_home.to_inventory = nil
active = {}
T("aiming at something usable: the game's interaction", PlayerCivilian._check_action_interact({}, 0, press) == "game" and exits == 1)
active = nil
T("no key pressed: the game's", PlayerCivilian._check_action_interact({}, 0, {}) == "game" and exits == 1)
PDTI.SetUIOpen(true)
T("the mod's screen open: the game's", PlayerCivilian._check_action_interact({}, 0, press) == "game" and exits == 1)
PDTI.SetUIOpen(false)
job_id = "chill_combat"
T("not in the raid", PlayerCivilian._check_action_interact({}, 0, press) == "game" and exits == 1)
job_id = "chill"
here = { x = 3000, y = -1674, z = 0 }
Home.GameTick(0.3)
T("walking out: no room", Home.in_room == nil)
T("outside the room: the game's", PlayerCivilian._check_action_interact({}, 0, press) == "game")
Home.ROOM_ZONES.test_room = { at = { x = 3000, y = -1674, z = 0 }, radius = 300, height = 250 }
Home.zones_found = true
T("a room without an action: the game's", PlayerCivilian._check_action_interact({}, 0, press) == "game" and exits == 1)
Home.ROOM_ZONES.test_room = nil
managers.interaction._interactive_units = {}
Home.zone_at, Home.zones_found = nil, nil
here = { x = 650, y = -1674, z = 0 }
Home.GameTick(0.3)
T("Chains not found: his usual spot", Home.in_room == "spanish" and Home.zones_found == nil)
MenuCallbackHandler._dialog_end_game_yes = function() error("no way out") end
T("the game cannot leave: logged, no mark left", Home.ToMenuInventory() == false and Global.pdti_home.to_inventory == nil
  and logged("could not leave the safehouse"))
MenuCallbackHandler._dialog_end_game_yes = nil
job_id = nil
Home.hinted = nil

-- In the main menu after leaving for the inventory.
local nodes_opened = {}
went = {}
_G.MenuCallbackHandler = {
  play_single_player = function() went[#went + 1] = "single" end,
  start_single_player_job = function(_, data) went[#went + 1] = data.job_id end
}
local function inventory_trip()
  boot()
  nodes_opened, went = {}, {}
  Global.pdti_home = { booted = true, to_inventory = true }
  managers.menu.open_node = function(_, name) nodes_opened[#nodes_opened + 1] = name; node = name end
end
inventory_trip()
T("back in the menu: the trip is planned", Home.OnMenuMain(false) == true and Global.pdti_home.to_inventory == nil
  and not covered())
Home.MenuTick(0)
T("not in the menu's first frame", #nodes_opened == 0 and #went == 0)
Home.MenuTick(0.6)
T("then the inventory page opens", nodes_opened[1] == "inventory" and #went == 0 and logged("(try 1)"))
node = "blackmarket"
for _ = 1, 50 do Home.MenuTick(1) end
managers.system_menu.is_active = function() return true end
for _ = 1, 40 do Home.MenuTick(1) end
managers.system_menu.is_active = function() return false end
T("in the inventory and its pages: no time limit, no trip", #went == 0 and Home.pending ~= nil
  and logged("in the menu's \"blackmarket\" page"))
node = "main"
Home.MenuTick(0.1)
T("back to the menu's first page: the safehouse", went[2] == "chill" and Home.pending == nil
  and Global.pdti_home.skip_briefing == true)
-- The page does not open (the menu stays on its first page).
inventory_trip()
managers.menu.open_node = function(_, name) nodes_opened[#nodes_opened + 1] = name end
Home.OnMenuMain(false)
Home.MenuTick(0.6)
Home.MenuTick(0.1)
T("still on the first page: not back to the safehouse", #went == 0 and #nodes_opened == 1)
Home.MenuTick(2)
T("tried again once", #nodes_opened == 2 and logged("(try 2)"))
for _ = 1, 10 do Home.MenuTick(1) end
T("then you stay in the menu, told to open it yourself", #nodes_opened == 2 and #went == 0 and Home.pending ~= nil
  and logged("did not open: open it yourself"))
local told = 0
for _, line in ipairs(ENV.logs) do if line:find("did not open: open it yourself", 1, true) then told = told + 1 end end
T("told once", told == 1)
node = "inventory"
Home.MenuTick(0.1)
node = "main"
Home.MenuTick(0.1)
T("you opened it and came back: the safehouse", went[2] == "chill")
inventory_trip()
Ammo.settings.safehouse_home = false
T("with the option off too (the trip was yours)", Home.OnMenuMain(false) == true)
Ammo.settings.safehouse_home = true
inventory_trip()
managers.system_menu.is_active = function() return dialog end
dialog = true
Home.OnMenuMain(false)
Home.MenuTick(1)
T("a dialog first: it waits", #nodes_opened == 0)
dialog = false
Home.MenuTick(0.1)
T("then the inventory", nodes_opened[1] == "inventory")
inventory_trip()
managers.menu.open_node = function() error("no such page") end
Home.OnMenuMain(false)
Home.MenuTick(0.6)
T("the page cannot open: logged, you stay in the menu", #went == 0 and logged("could not open: "))
-- 0.43.0: back in the menu after leaving for Duke's Story Line.
local function chills()
  local n = 0
  for _, w in ipairs(went) do if w == "chill" then n = n + 1 end end
  return n
end
local function story_trip()
  inventory_trip()
  Global.pdti_home = { booted = true, to_story = true }
end
story_trip()
T("back from Duke: the Story Line trip is planned", Home.OnMenuMain(false) == true and Global.pdti_home.to_story == nil
  and Home.pending ~= nil and Home.pending.node == "story_missions" and not covered()
  and logged("the Story Line: back to the safehouse when you return"))
Home.MenuTick(0)
T("  not in the menu's first frame", #nodes_opened == 0 and #went == 0)
Home.MenuTick(0.6)
T("  then the Story Line page opens, offline first", nodes_opened[1] == "story_missions" and went[1] == "single"
  and #went == 1 and logged("opening the menu's \"story_missions\" page (try 1)"))
node = "crimenet_contract_singleplayer"
for _ = 1, 40 do Home.MenuTick(1) end
T("  on the Story Line and a heist's contract: no trip, no time limit", #went == 1 and Home.pending ~= nil
  and logged("in the menu's \"crimenet_contract_singleplayer\" page"))
node = "main"
Home.MenuTick(0.1)
T("  back to the menu's first page: the safehouse", chills() == 1 and Home.pending == nil
  and Global.pdti_home.skip_briefing == true and logged("loading the safehouse (back from the Story Line)"))
story_trip()
managers.menu.open_node = function(_, name) nodes_opened[#nodes_opened + 1] = name end
Home.OnMenuMain(false)
Home.MenuTick(0.6)
Home.MenuTick(2)
for _ = 1, 10 do Home.MenuTick(1) end
T("  the page does not open: tried twice, then you are told", #nodes_opened == 2 and chills() == 0
  and Home.pending ~= nil and logged("the Story Line page did not open: open it yourself")
  and hints[#hints] and hints[#hints]:find("Open the Story Line yourself", 1, true))
story_trip()
managers.menu.open_node = function() error("no such page") end
Home.OnMenuMain(false)
Home.MenuTick(0.6)
T("  the page cannot open: logged, you stay in the menu", chills() == 0
  and logged("the Story Line page could not open: ") and logged("no such page"))
story_trip()
Ammo.settings.safehouse_home = false
T("  with the option off too (the trip was yours)", Home.OnMenuMain(false) == true and Home.pending.node == "story_missions")
Ammo.settings.safehouse_home = true
Home.pending = nil
-- 0.31.1: the laptop takes you to the Contract Broker.
local exits2 = 0
local base_interacts = 0
_G.BaseInteractionExt = { interact = function() base_interacts = base_interacts + 1; return true end }
_G.UseInteractionExt = setmetatable({}, { __index = BaseInteractionExt })
Home.InstallGameHooks()
local laptop = setmetatable({ tweak_data = "exit_to_crimenet" }, { __index = UseInteractionExt })
local door = setmetatable({ tweak_data = "open_door" }, { __index = BaseInteractionExt })
boot()
MenuCallbackHandler._dialog_end_game_yes = function() exits2 = exits2 + 1 end
job_id = "chill"
Global.game_settings.single_player = true
Home.seen_tweaks = {}
T("the laptop: you leave for crime.net, the game's exit does not run", laptop:interact({}) == true
  and exits2 == 1 and base_interacts == 0 and Global.pdti_home.to_broker == true and Global.load_crime_net == true
  and logged("leaving for the Contract Broker"))
T("  its name is logged once", logged("used in the safehouse: exit_to_crimenet"))
door:interact({})
door:interact({})
local door_logs = 0
for _, line in ipairs(ENV.logs) do if line:find("used in the safehouse: open_door", 1, true) then door_logs = door_logs + 1 end end
T("anything else is the game's, logged once by name", base_interacts == 2 and exits2 == 1 and door_logs == 1)
Global.pdti_home.to_broker, Global.load_crime_net = nil, nil
Global.game_settings.single_player = false
laptop:interact({})
T("with a crew: the game's own exit", exits2 == 1 and base_interacts == 3 and Global.pdti_home.to_broker == nil)
Global.game_settings.single_player = true
job_id = "branchbank"
laptop:interact({})
T("not in the safehouse: the game's", exits2 == 1 and base_interacts == 4)
job_id = "chill"
MenuCallbackHandler._dialog_end_game_yes = function() error("no way out") end
T("the game cannot leave: the game's exit runs, no marks left", laptop:interact({}) == true and base_interacts == 5
  and Global.pdti_home.to_broker == nil and Global.load_crime_net == nil and logged("could not leave the safehouse"))
MenuCallbackHandler._dialog_end_game_yes = nil
T("  the game's functions missing: the game's exit", laptop:interact({}) == true and base_interacts == 6)
job_id = nil

-- In the menu after the laptop: the game has opened crime.net itself.
local function broker_trip()
  boot()
  nodes_opened, went = {}, {}
  Global.pdti_home = { booted = true, to_broker = true }
  Global.game_settings.single_player = true
  node = "crimenet_single_player"
  managers.menu.open_node = function(_, name) nodes_opened[#nodes_opened + 1] = name; node = name end
end
broker_trip()
T("back in the menu: the broker trip is planned", Home.OnMenuMain(false) == true and Global.pdti_home.to_broker == nil
  and Home.pending ~= nil and Home.pending.broker == true and not covered())
Home.MenuTick(0)
T("not in crime.net's first frame", #nodes_opened == 0)
Home.MenuTick(0.6)
T("then the Contract Broker opens", nodes_opened[1] == "contract_broker" and #went == 0 and logged("opening the Contract Broker"))
node = "crimenet_single_player"
for _ = 1, 50 do Home.MenuTick(1) end
T("back out of the broker to crime.net: it is not opened again, no time limit", #nodes_opened == 1 and #went == 0
  and Home.pending ~= nil)
node = "main"
Home.MenuTick(0.1)
T("out of crime.net to the menu's first page: the safehouse", went[2] == "chill" and Home.pending == nil
  and Global.pdti_home.skip_briefing == true)
broker_trip()
Ammo.settings.safehouse_home = false
T("with the option off too (the trip was yours)", Home.OnMenuMain(false) == true)
Ammo.settings.safehouse_home = true
-- crime.net did not come up: it is opened once, then you are told.
broker_trip()
node = "main"
managers.menu.open_node = function(_, name) nodes_opened[#nodes_opened + 1] = name end
Home.OnMenuMain(false)
Home.MenuTick(1)
T("on the first page, waiting for crime.net", #nodes_opened == 0 and #went == 0)
Home.MenuTick(1.5)
T("then crime.net is opened the game's way", nodes_opened[1] == "crimenet_single_player" and went[1] == "single")
for _ = 1, 10 do Home.MenuTick(1) end
T("still nothing: you stay, told to open it yourself", #nodes_opened == 1 and Home.pending ~= nil
  and logged("crime.net did not open: open it yourself"))
local told2 = 0
for _, line in ipairs(ENV.logs) do if line:find("crime.net did not open", 1, true) then told2 = told2 + 1 end end
T("  told once", told2 == 1)
node = "crimenet_single_player"
Home.MenuTick(0.1)
node = "main"
Home.MenuTick(0.1)
T("you opened it and came back: the safehouse", went[#went] == "chill")
-- A dialog first.
broker_trip()
managers.system_menu.is_active = function() return dialog end
dialog = true
Home.OnMenuMain(false)
Home.MenuTick(5)
T("a dialog first: it waits", #nodes_opened == 0)
dialog = false
Home.MenuTick(0.1)
Home.MenuTick(0.6)
T("then the broker", nodes_opened[1] == "contract_broker")
broker_trip()
dialog = true
Home.OnMenuMain(false)
for _ = 1, 31 do Home.MenuTick(1) end
T("a dialog for too long before crime.net: you stay", Home.pending == nil and #went == 0 and #nodes_opened == 0)
dialog = false
-- The broker page cannot open: you are on crime.net, the way back works.
broker_trip()
managers.menu.open_node = function() error("no such page") end
Home.OnMenuMain(false)
Home.MenuTick(0)
Home.MenuTick(0.6)
T("the broker cannot open: logged, you stay on crime.net", #went == 0 and logged("the Contract Broker could not open"))
node = "main"
Home.MenuTick(0.1)
T("  leaving crime.net still takes you home", went[2] == "chill")
managers.menu.open_node = nil

managers.menu.open_node = nil
node = "main"
boot()
job_id = "chill_combat"
CivilianHeisterInteractionExt.interact(wolf, {})
T("not in the raid", #dialogs == n)
job_id = "chill"
CivilianHeisterInteractionExt.interact(setmetatable({ character = "butler" }, { __index = CivilianHeisterInteractionExt }), {})
T("a heister without a room: logged, no menu", #dialogs == n and logged("a heister without a room: butler"))
managers.custom_safehouse = nil
CivilianHeisterInteractionExt.interact(wolf, {})
T("no safehouse data: no menu, no error", #dialogs == n)
job_id = nil

local mod = io.open(ROOT .. "mod.txt"):read("*a")
T("mod.txt hooks the main menu's state", mod:find('"lib/states/menumainstate"', 1, true) ~= nil
  and mod:find('"lua/hooks_home.lua"', 1, true) ~= nil)
T("mod.txt hooks the briefing's state", mod:find('"lib/states/ingamewaitingforplayers"', 1, true) ~= nil)

-- The safehouse's briefing: ready is pressed for you, Bain's intro skipped.
local brief = { ready = 0, intro = 0, skips = 0, circle = 0, updates = 0 }
_G.IngameWaitingForPlayersState = {
  at_enter = function(self) brief.entered = true end,
  update = function(self, t, dt) brief.updates = brief.updates + 1 end,
  start_game_intro = function(self)
    if self._starting_game_intro then return end
    self._starting_game_intro = true
    brief.intro = brief.intro + 1
  end,
  _skip = function(self) self._skipped = true; brief.skips = brief.skips + 1 end
}
IngameWaitingForPlayersState.__index = IngameWaitingForPlayersState
local function new_briefing() return setmetatable({}, IngameWaitingForPlayersState) end
managers.menu_component = { on_ready_pressed_mission_briefing_gui = function(_, r) if r then brief.ready = brief.ready + 1 end end }
managers.hud = managers.hud or {}
managers.hud.blackscreen_skip_circle_done = function() brief.circle = brief.circle + 1 end
T("the briefing hooks go in", Home.InstallBriefingHooks() == true)
local hooked_brief = IngameWaitingForPlayersState.update
dofile(ROOT .. "lua/hooks_home.lua")
T("once", IngameWaitingForPlayersState.update == hooked_brief)

local function trip_to_safehouse()
  boot()
  Home.OnMenuMain(false)
  Home.MenuTick(0)
  job_id = "chill"
  Global.game_settings.single_player = true
end
trip_to_safehouse()
local st = new_briefing()
IngameWaitingForPlayersState.at_enter(st)
T("the safehouse the mod sent you to: the briefing is passed", st._pdti_auto == true and brief.entered
  and Global.pdti_home.skip_briefing == nil and logged("ready is pressed for you"))
IngameWaitingForPlayersState.update(st, 0, 0.1)
T("ready, as the button does it, and the start", brief.ready == 1 and brief.intro == 1 and brief.updates == 1)
IngameWaitingForPlayersState.update(st, 0, 0.1)
T("the start once", brief.intro == 1 and brief.ready == 1)
st._audio_started = true
IngameWaitingForPlayersState.update(st, 0, 0.1)
T("the intro is not skipped before the game allows it", brief.skips == 0)
st._skip_promt_shown = true
IngameWaitingForPlayersState.update(st, 0, 0.1)
T("then Bain's intro is skipped", brief.skips == 1 and brief.circle == 1 and st._pdti_auto == nil)
IngameWaitingForPlayersState.update(st, 0, 0.1)
T("once", brief.skips == 1)

-- Not passed: you went there yourself, a heist, a crew, the option off.
local function briefing_after(setup)
  brief.ready, brief.intro = 0, 0
  local s2 = new_briefing()
  setup()
  IngameWaitingForPlayersState.at_enter(s2)
  IngameWaitingForPlayersState.update(s2, 0, 0.1)
  return s2._pdti_auto == nil and brief.ready == 0 and brief.intro == 0
end
T("the safehouse entered by yourself: the briefing as usual", briefing_after(function()
  boot(); job_id = "chill"; Global.game_settings.single_player = true end))
T("a heist's briefing: as usual", briefing_after(function()
  trip_to_safehouse(); job_id = "branchbank" end))
T("with a crew: as usual", briefing_after(function()
  trip_to_safehouse(); Global.game_settings.single_player = false end))
T("the option off: as usual", briefing_after(function()
  trip_to_safehouse(); Ammo.settings.safehouse_home = false end))
Ammo.settings.safehouse_home = true
T("the mark is used up by the first briefing", (function()
  trip_to_safehouse(); job_id = "branchbank"
  IngameWaitingForPlayersState.at_enter(new_briefing())
  return Global.pdti_home.skip_briefing == nil end)())
trip_to_safehouse()
local broken = new_briefing()
IngameWaitingForPlayersState.at_enter(broken)
broken.start_game_intro = function() error("boom") end
IngameWaitingForPlayersState.update(broken, 0, 0.1)
T("a failure: logged, you press ready yourself", broken._pdti_auto == nil and logged("press ready yourself"))
job_id = nil

-- The option is saved with the settings.
T("\"Start in the safehouse\" is on unless you switch it off", Ammo.settings.safehouse_home == true)
local saved_key = false
for _, f in ipairs(Ammo.SETTING_FILES) do for _, k in ipairs(f.keys) do if k == "safehouse_home" then saved_key = true end end end
T("and is saved with the settings", saved_key)

------------------------------------------------------------------ the probe

local function vec(x, y, z) return { x = x, y = y, z = z } end
local function thing(tweak, id, pos, active)
  local u = {}
  function u:position() return pos end
  function u:interaction() return { tweak_data = tweak, _active = active } end
  function u:unit_data() return { unit_id = id } end
  function u:name() return { key = function() return "k" .. id end } end
  return u
end
ENV.make_unit()
ENV.game.unit.position = function() return vec(100, 200, 0) end
managers.interaction = { _interactive_units = {
  thing("far_thing", 3, vec(5000, 200, 0), true),
  thing("vault_door", 1, vec(400, 200, 0), true),
  thing("laptop", 2, vec(100, 300, 0), false)
} }
job_id = "branchbank"
T("no probe in a heist", Home.Probe() == false)
job_id = "chill"
ENV.logs = {}
_G.log = function(m) ENV.logs[#ENV.logs + 1] = m end
local ran, count = Home.Probe()
T("the probe finds what is near, not what is far", ran == true and count == 2, count)
T("it logs where you stand", logged("you stand at (100, 200, 0)"))
local first, second
for i, line in ipairs(ENV.logs) do
  if line:find("tweak=laptop", 1, true) then first = i end
  if line:find("tweak=vault_door", 1, true) then second = i end
end
T("nearest first, with the distance, the unit's id and its place", first and second and first < second
  and logged("1.0 m  tweak=laptop  unit_id=2  at (100, 300, 0)") and logged("3.0 m  tweak=vault_door  unit_id=1"))
T("a switched-off one is marked", logged("tweak=laptop  unit_id=2  at (100, 300, 0)  name=k2  (off)"))
managers.interaction._interactive_units = {}
ENV.logs = {}
Home.Probe()
T("nothing near is said too", logged("nothing to use within 6 m"))
ENV.logs = {}
PDTI.SetUIOpen(true)
T("opening the inventory screen in the safehouse runs the probe", logged("you stand at"))
PDTI.SetUIOpen(false)
Home.PROBE = false
T("the probe can be switched off", Home.Probe() == false)
Home.PROBE = true

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
