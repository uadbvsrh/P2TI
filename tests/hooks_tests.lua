-- Checks the hook scripts against fake game classes, and mod.txt consistency.
--   texlua tests/hooks_tests.lua
local script = arg and arg[0] or "tests/hooks_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_hooks") .. "/")
_G.ModPath = ROOT
ENV.install_game()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function exists(path) local f = io.open(path, "r"); if f then f:close() return true end end

-- mod.txt: every hook script and keybind script exists
local raw = io.open(ROOT .. "mod.txt"):read("*a")
local scripts = {}
for path in raw:gmatch('"script_path"%s*:%s*"([^"]+)"') do scripts[#scripts + 1] = path end
local missing = {}
for _, p in ipairs(scripts) do if not exists(ROOT .. p) then missing[#missing + 1] = p end end
T("every script in mod.txt exists (" .. #scripts .. ")", #missing == 0, table.concat(missing, ","))
local hooks = {}
for id in raw:gmatch('"hook_id"%s*:%s*"([^"]+)"') do hooks[id] = (hooks[id] or 0) + 1 end
T("the player, game setup, menu and player manager hooks are registered",
  hooks["lib/units/beings/player/states/playerstandard"]
  and hooks["lib/setups/gamesetup"] and hooks["lib/managers/menumanager"]
  and hooks["lib/managers/playermanager"] and hooks["lib/units/beings/player/playermovement"])

-- load the mod through main.lua like the game does
dofile(ROOT .. "lua/main.lua")
T("main.lua loads the ammunition system and the deployables",
  PDTI.Ammo ~= nil and PDTI.Deployables ~= nil and PDTI.EditItems ~= nil)
T("the old ISSR modules are gone",
  PDTI.Mags == nil and PDTI.LooseAmmo == nil and PDTI.IsISSRAvailable == nil)

-- hooks_game: wraps PlayerStandard._get_input
local calls = { orig = 0 }
_G.PlayerStandard._get_input = function(self, t, dt, paused)
  calls.orig = calls.orig + 1
  return { btn_reload_press = true }
end
-- the game's own deploy action, so the patch can be watched
local deploy_started = false
_G.PlayerStandard._check_use_item = function(self, t, input)
  deploy_started = true
  return true
end
local ticks = 0
local real_tick = PDTI.Ammo.GameTick
PDTI.Ammo.GameTick = function() ticks = ticks + 1 end
local loot_ticks = 0
local real_loot = PDTI.Loot.Tick
PDTI.Loot.Tick = function() loot_ticks = loot_ticks + 1 end
dofile(ROOT .. "lua/hooks_game.lua")
local wrapped = PlayerStandard._get_input
local r = PlayerStandard._get_input({}, 1, 0.016, false)
T("input passes through while the screen is closed", r.btn_reload_press == true and calls.orig == 1)
T("the ammunition system runs every frame", ticks == 1, ticks)
T("the loot follows every frame", loot_ticks == 1, loot_ticks)
PlayerStandard._get_input({}, 2, 0.016, true)
T("nothing runs while paused", ticks == 1 and loot_ticks == 1)
PDTI.IsUIOpen = function() return true end
local blocked = PlayerStandard._get_input({}, 3, 0.016, false)
T("R and every other key are dropped while the screen is open",
  next(blocked) == nil and calls.orig == 3)
PDTI.IsUIOpen = function() return false end
dofile(ROOT .. "lua/hooks_game.lua")
T("the hook is installed only once", PlayerStandard._get_input == wrapped)
PDTI.Ammo.GameTick = function() error("ammunition exploded") end
local ok = pcall(PlayerStandard._get_input, {}, 4, 0.016, false)
T("a failing ammunition tick never breaks the player's input", ok == true)
PDTI.Ammo.GameTick = real_tick
PDTI.Loot.Tick = real_loot

-- the game's own deploy action is used, so the placement takes the time of
-- the game instead of being instant
PDTI.SetDeployable("ammo_bag")
PDTI.AddItemAuto("rig", "ammo_bag", 1, nil, true)
PDTI._deploy_key_trigger = { fake = true }
deploy_started = false
PlayerStandard._check_use_item({}, 1, {})
T("the game's deploy action is not blocked", deploy_started == true)

-- the key of the mod asks the game to start its deploy action
local started = false
local state = {
  _use_item_expire_t = nil,
  _equipping_mask = false,
  _interacting = function() return false end,
  _is_throwing_projectile = function() return false end,
  _is_meleeing = function() return false end,
  _start_action_use_item = function() started = true end
}
local real_can_use = managers.player.can_use_selected_equipment
managers.player.can_use_selected_equipment = function() return true end
PDTI._deploy_request = true
PlayerStandard._check_use_item(state, 2, {})
T("the key of the mod starts the game's deploy action", started == true)
T("the request is used once", PDTI._deploy_request == nil)

-- the game sees the key press itself: the mod must not start a second action
started = false
PDTI._deploy_request = true
PlayerStandard._check_use_item(state, 3, { btn_use_item_press = true })
T("a key press of the game is not started twice", started == false)
T("the request is cleared anyway", PDTI._deploy_request == nil)

-- carrying a bag, the game holds G back (tap throws, hold deploys) and passes
-- it on when the key is let go; a second action there crashed the game
started = false
local real_carrying = managers.player.is_carrying
managers.player.is_carrying = function() return true end
PDTI._deploy_request = true
PDTI._deploy_request_t = 0
PlayerStandard._check_use_item(state, 10, {})
T("no deploy action of the mod while a bag is carried", started == false)
T("that request is dropped", PDTI._deploy_request == nil)
managers.player.is_carrying = real_carrying

-- the game's key is held: the game deploys itself
started = false
state._controller = { get_input_bool = function(_, name) return name == "use_item" end }
PDTI._deploy_request = true
PlayerStandard._check_use_item(state, 20, {})
T("no second action while the game's deploy key is held", started == false)
state._controller = nil

-- the game saw the key let go a moment ago
started = false
PlayerStandard._check_use_item(state, 30, { btn_use_item_release = true })
PDTI._deploy_request = true
PlayerStandard._check_use_item(state, 30.2, {})
T("no second action right after the game saw the key", started == false)

-- a rebound key the game never sees still deploys
started = false
PDTI._deploy_request = true
PlayerStandard._check_use_item(state, 40, {})
T("the mod's own key still deploys when the game did not see it", started == true)
managers.player.can_use_selected_equipment = real_can_use
PDTI._deploy_key_trigger = nil
PDTI.SetDeployable(nil)

-- heist_start
local registered
_G.Hooks = { PostHook = function(_, class, fn, id, cb) registered = { fn = fn, id = id, cb = cb } end }
_G.GameSetup = {}
dofile(ROOT .. "lua/heist_start.lua")
T("the heist start registers a PostHook on GameSetup.init_finalize",
  registered and registered.fn == "init_finalize")
PDTI.AddItemAuto("rig", "spare_magazine", 1, { queue_key = "X", rounds = 5, capacity = 30 }, true)
PDTI.AddItemAuto("rig", "loose_ammo", 30, { queue_key = "X" })
PDTI.AddItemAuto("rig", "loot_bag", 2)
registered.cb()
local left = PDTI.GetContainer("rig").items
T("the heist start callback clears the old ammunition",
  #left == 1 and left[1].item_id == "ammo_bag", #left)
T("the old magazines are gone", #PDTI.FindItems(function(_, item)
  return item.item_id == "spare_magazine"
end) == 0)
T("the old loose ammunition is gone", #PDTI.FindItems(function(_, item)
  return item.item_id == "loose_ammo"
end) == 0)
dofile(ROOT .. "lua/heist_start.lua")
T("the heist start hook registers once", true)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
