-- 0.18.9: the options page (Options > Mod Options > Tactical Inventory) and
-- the saving of the settings.
--   luajit tests/options_tests.lua
local script = arg and arg[0] or "tests/options_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_options") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
ENV.load_mod(ROOT, false)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo = PDTI.Ammo
local function read(file)
  local f = io.open(TMP .. file, "r")
  if not f then return nil end
  local raw = f:read("*all")
  f:close()
  return json.decode(raw)
end

-- 1. saving: every key into its own file, nothing else
local defaults = {}
for k, v in pairs(Ammo.settings) do defaults[k] = v end
Ammo.settings.drop_mode = 2
Ammo.settings.round_interval = 0.4
Ammo.settings.heavy_armour = false
Ammo.settings.ui_scale = 0.9
Ammo.settings.not_a_setting = "x"
T("the settings are saved", Ammo.SaveSettings() == true)
local a, b = read("issr_settings.txt"), read("issr_reload_settings.txt")
T("both files are written", type(a) == "table" and type(b) == "table")
local misplaced = {}
for _, entry in ipairs(Ammo.SETTING_FILES) do
  local data = read(entry.file)
  local keys = {}
  for _, key in ipairs(entry.keys) do
    keys[key] = true
    if data[key] ~= Ammo.settings[key] then misplaced[#misplaced + 1] = entry.file .. ":" .. key end
  end
  for key in pairs(data) do
    if not keys[key] then misplaced[#misplaced + 1] = entry.file .. " has " .. key end
  end
end
T("every key is in its own file with its value, and only those", #misplaced == 0, table.concat(misplaced, ", "))
T("the drop mode is in the first file", a.drop_mode == 2 and b.drop_mode == nil)
T("the armour, the loading time and the screen size in the second", b.heavy_armour == false
  and b.round_interval == 0.4 and b.ui_scale == 0.9 and a.heavy_armour == nil)
T("a key that is not a setting is not written", a.not_a_setting == nil and b.not_a_setting == nil)

-- 2. loading them back
for k, v in pairs(defaults) do Ammo.settings[k] = v end
Ammo.settings.not_a_setting = nil
Ammo.LoadSettings()
T("what was saved is read back", Ammo.settings.drop_mode == 2 and Ammo.settings.round_interval == 0.4
  and Ammo.settings.heavy_armour == false and Ammo.settings.ui_scale == 0.9)
for k, v in pairs(defaults) do Ammo.settings[k] = v end

-- 3. the page: without BLT's MenuHelper it only logs
_G.Hooks, _G.MenuHelper = nil, nil
PDTI._options_menu = nil
dofile(ROOT .. "lua/options_menu.lua")
local Options = PDTI.Options
T("without MenuHelper the file loads and logs", Options ~= nil and (function()
  for _, l in ipairs(ENV.logs) do if l:find("MenuHelper is not available", 1, true) then return true end end
end)() == true)

-- 4. with a mocked BLT
local hooks = {}
_G.Hooks = { Add = function(_, name, id, fn) hooks[name] = fn end }
local added, built, menu_items = {}, {}, {}
local function add(kind) return function(_, p) p.kind = kind; added[#added + 1] = p end end
_G.MenuHelper = {
  NewMenu = function(_, id) built.new = id end,
  BuildMenu = function(_, id) built.build = id; return { id = id } end,
  AddMenuItem = function(_, parent, id, title) menu_items[#menu_items + 1] = { parent = parent, id = id, title = title } end,
  AddToggle = add("toggle"), AddSlider = add("slider"), AddMultipleChoice = add("choice"), AddButton = add("button")
}
_G.MenuCallbackHandler = {}
PDTI._options_menu = nil
dofile(ROOT .. "lua/options_menu.lua")
Options = PDTI.Options
T("the hooks of BLT are added", hooks.LocalizationManagerPostInit and hooks.MenuManagerSetupCustomMenus
  and hooks.MenuManagerPopulateCustomMenus and hooks.MenuManagerBuildCustomMenus)
hooks.MenuManagerSetupCustomMenus()
hooks.MenuManagerPopulateCustomMenus()
local nodes = { blt_options = { name = "blt" } }
hooks.MenuManagerBuildCustomMenus(nil, nodes)
T("the page is made and put in Mod Options", built.new == Options.MENU_ID and nodes[Options.MENU_ID] ~= nil
  and menu_items[1] and menu_items[1].parent == nodes.blt_options)

local by_id, settings_count = {}, 0
for _, p in ipairs(added) do by_id[p.id] = p end
local missing, unknown = {}, {}
for _, entry in ipairs(Options.LIST) do
  if entry.key then
    settings_count = settings_count + 1
    local p = by_id["pdti_opt_" .. entry.key]
    if not p or p.kind ~= entry.kind then missing[#missing + 1] = entry.key end
    if Ammo.settings[entry.key] == nil then unknown[#unknown + 1] = entry.key end
  end
end
T("every setting has its item", #missing == 0 and settings_count >= 17, table.concat(missing, ","))
T("the ISSR leftovers are gone (extra magazines, most ammunition)", by_id.pdti_opt_max_extra_mags == nil
  and by_id.pdti_opt_ammo_max == nil and Ammo.settings.max_extra_mags == nil and Ammo.settings.ammo_max == nil)
T("every item is a real setting", #unknown == 0, table.concat(unknown, ","))
local saved_keys = {}
for _, entry in ipairs(Ammo.SETTING_FILES) do for _, k in ipairs(entry.keys) do saved_keys[k] = true end end
local unsaved = {}
for _, entry in ipairs(Options.LIST) do
  if entry.key and not saved_keys[entry.key] then unsaved[#unsaved + 1] = entry.key end
end
T("every item is saved in a file", #unsaved == 0, table.concat(unsaved, ","))
T("the items are in the list's order", by_id.pdti_opt_enabled.priority > by_id.pdti_opt_pad_bottom.priority)
T("a toggle shows the setting", by_id.pdti_opt_heavy_armour.value == true)
T("the drop mode shows its choice (menu from 1)", by_id.pdti_opt_drop_mode.value == Ammo.settings.drop_mode + 1
  and #by_id.pdti_opt_drop_mode.items == 3)

local strings = {}
hooks.LocalizationManagerPostInit({ add_localized_strings = function(_, s) strings = s end })
local no_text = {}
for _, p in ipairs(added) do
  if not strings[p.title] or not strings[p.desc] then no_text[#no_text + 1] = p.id end
  for _, c in ipairs(p.items or {}) do if not strings[c] then no_text[#no_text + 1] = c end end
end
T("every item has its text", #no_text == 0 and strings.pdti_options_title ~= nil, table.concat(no_text, ","))

-- 5. the callbacks change the setting and save it
local function item(v) return { value = function() return v end } end
local hud = 0
local real_refresh = Ammo.RefreshHud
Ammo.RefreshHud = function() hud = hud + 1 end
MenuCallbackHandler.pdti_options_heavy_armour(nil, item("off"))
T("a toggle turns a setting off", Ammo.settings.heavy_armour == false
  and read("issr_reload_settings.txt").heavy_armour == false)
MenuCallbackHandler.pdti_options_heavy_armour(nil, item("on"))
T("and on", Ammo.settings.heavy_armour == true and read("issr_reload_settings.txt").heavy_armour == true)
MenuCallbackHandler.pdti_options_drop_mode(nil, item(1))
T("the first choice is 'never' (0)", Ammo.settings.drop_mode == 0 and read("issr_settings.txt").drop_mode == 0)
MenuCallbackHandler.pdti_options_max_boxes(nil, item(3.4))
T("a whole-number slider is rounded", Ammo.settings.max_boxes == 3)
MenuCallbackHandler.pdti_options_ui_scale(nil, item(9))
T("a slider stays in its range", Ammo.settings.ui_scale == 1.5)
-- Dragged with the mouse a slider gives any value: it is snapped to its step
-- and the slider is set back to what was stored.
local shown
local dragged = { value = function() return 6.5 end, set_value = function(_, v) shown = v end }
MenuCallbackHandler.pdti_options_max_boxes(nil, dragged)
T("a dragged whole-number slider stores a whole number", Ammo.settings.max_boxes == 7 and shown == 7, shown)
MenuCallbackHandler.pdti_options_round_interval(nil, { value = function() return 0.4371 end,
  set_value = function(_, v) shown = v end })
T("a decimal slider snaps to its step", math.abs(Ammo.settings.round_interval - 0.45) < 1e-9
  and shown == Ammo.settings.round_interval, Ammo.settings.round_interval)
T("whole-number sliders show no decimals", by_id.pdti_opt_max_boxes.display_precision == 0
  and by_id.pdti_opt_font_size.display_precision == 0 and by_id.pdti_opt_round_interval.display_precision == 2)
local before = hud
MenuCallbackHandler.pdti_options_font_size(nil, item(24))
T("a HUD setting redraws the HUD", Ammo.settings.font_size == 24 and hud == before + 1)
MenuCallbackHandler.pdti_options_round_interval(nil, item(0.3))
T("other settings do not", hud == before + 1 and Ammo.settings.round_interval == 0.3)
Ammo.RefreshHud = real_refresh

-- 6. the screen size is used when the screen opens
ENV.install_menuui(false)
dofile(ROOT .. "lua/ui_beardlib.lua")
local function width()
  PDTI.SetUIOpen(true)
  local w = ENV.menus[#ENV.menus].children[1].pw
  PDTI.SetUIOpen(false)
  return w
end
Ammo.settings.ui_scale = 1
local normal = width()
Ammo.settings.ui_scale = 0.8
local smaller = width()
T("a smaller screen size makes the windows smaller", smaller < normal, normal .. " / " .. smaller)
Ammo.settings.ui_scale = 1

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
