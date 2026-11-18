-- 0.37.0: the mod's own progress save (slot 86, its own file names) and the
-- start dialog on a new save (fresh, or level 100 with coins and money).
--   luajit tests/save_slot_tests.lua
local script = arg and arg[0] or "tests/save_slot_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_save_slot") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

------------------------------------------------- the slot (the game's hook)

local platform = "WIN32"
_G.Idstring = function(s) return "ids:" .. s end
_G.SystemInfo = { platform = function() return Idstring(platform) end }
local function hook_run()
  _G.SavefileManager = { PROGRESS_SLOT = 98, BACKUP_SLOT = 98, SETTING_SLOT = 0 }
  _G.PDTI_SAVE_SLOT_SET, _G.PDTI_SEPARATE_SAVE = nil, nil
  local had = rawget(_G, "PDTI")
  _G.PDTI = nil -- the hook runs before the mod's parts
  dofile(ROOT .. "lua/save_slot.lua")
  _G.PDTI = had
end
hook_run()
T("Windows (and Proton): progress and its backup in slot 86", SavefileManager.PROGRESS_SLOT == 86
  and SavefileManager.BACKUP_SLOT == 86 and PDTI_SEPARATE_SAVE == true)
T("  the settings slot stays the game's", SavefileManager.SETTING_SLOT == 0)
SavefileManager.PROGRESS_SLOT = 98
dofile(ROOT .. "lua/save_slot.lua")
T("  once per load (the part run later changes nothing)", SavefileManager.PROGRESS_SLOT == 98)
platform = "X360"
hook_run()
T("not Windows: the game's own slot", SavefileManager.PROGRESS_SLOT == 98 and PDTI_SEPARATE_SAVE == false)
_G.SavefileManager, _G.PDTI_SAVE_SLOT_SET, _G.PDTI_SEPARATE_SAVE = nil, nil, nil
_G.SystemInfo, _G.Idstring = nil, nil

----------------------------------------------------------- the start dialog

ENV.load_mod(ROOT, false)
local S = PDTI.SaveSlot
T("the start part is loaded with the mod", S ~= nil and S.OnMenu ~= nil and S.SLOT == 86)

-- The game's levels: 1000 points a level; coins, money, the save.
local exp = { level = 0, rank = 0, cur = 0, calls = 0 }
local function fake_experience()
  return {
    current_level = function() return exp.level end,
    current_rank = function() return exp.rank end,
    next_level_data_points = function() return 1000 end,
    next_level_data_current_points = function() return exp.cur end,
    add_points = function(_, points, present, debug)
      exp.calls = exp.calls + 1
      exp.debug = debug
      exp.cur = exp.cur + points
      while exp.cur >= 1000 and exp.level < 100 do exp.cur = exp.cur - 1000; exp.level = exp.level + 1 end
    end
  }
end
local got = {}
managers.experience = fake_experience()
managers.custom_safehouse = { add_coins_ingore_locked = function(_, n) got.coins = (got.coins or 0) + n end }
managers.money = {
  _add_to_total = function(_, n, params) got.spending = n; got.no_offshore = params and params.no_offshore end,
  add_to_offshore = function(_, n) got.offshore = n end
}
managers.savefile = { save_progress = function() got.saved = true end }
local shown = {}
managers.system_menu = { show = function(_, d) shown[#shown + 1] = d end }
local MARK = TMP .. "pdti_save_start.json"
os.remove(MARK)

_G.PDTI_SEPARATE_SAVE = false
T("on the game's own save: no dialog", S.OnMenu() == false and #shown == 0)
_G.PDTI_SEPARATE_SAVE = true
T("a new save of the mod's own: the start dialog", S.OnMenu() == true and #shown == 1
  and #shown[1].button_list == 2 and shown[1].text:find("level 100", 1, true) ~= nil
  and shown[1].text:find("120 Continental coins", 1, true) ~= nil)
T("  not twice while it is open", S.OnMenu() == false and #shown == 1)
shown[1].button_list[1].callback_func()
T("level 100: levelled the game's way, one level at a time", exp.level == 100 and exp.calls == 100 and exp.debug == true
  and exp.cur == 0, exp.level .. " " .. exp.calls)
T("  120 coins, $100,000 spending (none of it offshore) and $100,000 offshore", got.coins == 120
  and got.spending == 100000 and got.no_offshore == true and got.offshore == 100000)
T("  the game saves it", got.saved == true)
T("  written down: never asked again", io.open(MARK, "r") ~= nil and S.Started())
S._asked = nil
T("  (another menu: nothing)", S.OnMenu() == false and #shown == 1)

-- Start fresh: nothing given.
os.remove(MARK); S._asked = nil
exp.level, exp.cur, exp.calls = 0, 0, 0
got = {}
S.OnMenu()
shown[#shown].button_list[2].callback_func()
T("start fresh: level 0, nothing given, written down", exp.level == 0 and got.coins == nil and got.spending == nil
  and S.Started())
local f = io.open(MARK, "r"); local text = f:read("*a"); f:close()
T("  the choice is in the file", text:find('"start":"fresh"', 1, true) ~= nil, text)

-- A save already played (the file deleted): no dialog, just written down.
os.remove(MARK); S._asked = nil
exp.level = 37
local n = #shown
T("a save already played: no dialog", S.OnMenu() == false and #shown == n and S.Started())
os.remove(MARK); S._asked = nil
exp.level, exp.rank = 0, 2
T("  an infamous one at level 0 neither", S.OnMenu() == false and #shown == n)
os.remove(MARK); S._asked = nil
exp.rank = 0
managers.experience = nil
T("the game's progress not read yet: wait (no dialog, nothing written)", S.OnMenu() == false and not S.Started())
managers.experience = fake_experience()
-- The level 100 start failing on the way: logged, still written down.
os.remove(MARK); S._asked = nil
exp.level = 0
managers.experience.next_level_data_points = function() error("broken") end
S.OnMenu()
shown[#shown].button_list[1].callback_func()
T("a failing level-up: no error out of the dialog, written down", S.Started())
_G.PDTI_SEPARATE_SAVE = nil

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
