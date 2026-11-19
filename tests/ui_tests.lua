-- Offline tests for the inventory screen logic and its BeardLib renderer.
--   texlua tests/ui_tests.lua
-- The renderer runs against a FAKE MenuUI that rejects any parameter not in the
-- BeardLib docs. This proves the interaction logic and parameter names; it does
-- NOT prove how the real MenuUI lays things out. That needs an in-game check.
local script = arg and arg[0] or "tests/ui_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_ui") .. "/")
ENV.load_mod(ROOT, true)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
-- The screen has two windows (left and right). The tests look at both as
-- one: window() finds an item in either.
local function windows() return ENV.menus[#ENV.menus].children end
local function window()
  local all = {}
  for _, w in ipairs(windows()) do for _, c in ipairs(w.children) do all[#all + 1] = c end end
  return {
    children = all,
    find = function(_, name) for _, c in ipairs(all) do if c.params.name == name then return c end end end
  }
end
local function cells(win, prefix)
  local n = 0
  for _, c in ipairs(win.children) do
    if c.params.name and c.params.name:find("^cell_" .. prefix .. "_%d+_%d+$") then n = n + 1 end
  end
  return n
end
local function status(win) local s = win:find("status"); return s and s.params.text end
local function trigger(key)
  for _, t in ipairs(ENV.triggers) do if t.key == key then return t end end
end

-- 1. BeardLib missing: fails soft
ENV.remove_menuui()
T("UI unavailable without BeardLib", PDTI.IsUIAvailable() == false)
T("ToggleUI without BeardLib returns false, no error", PDTI.ToggleUI() == false and PDTI.IsUIOpen() == false)

-- 2. open with the fake MenuUI
ENV.install_menuui(false)
T("UI available with MenuUI", PDTI.IsUIAvailable() == true)
-- The large backpack (6x5) and the general rig (3x6).
PDTI.SetEquipment("backpack", "large_backpack")
PDTI.SetEquipment("rig", "general_rig")
local _, bag = PDTI.AddItemAuto("backpack", "doctor_bag", 1, nil, true)
local _, band = PDTI.AddItemAuto("pockets", "bandage", 2, nil, true)
T("ToggleUI opens", PDTI.ToggleUI() == true and PDTI.IsUIOpen() == true)
local win = window()
T("menu enabled on open", ENV.menus[1]:Enabled())
T("pockets grid 2x2 = 4 cells", cells(win, "pockets") == 4, cells(win, "pockets"))
T("rig grid 3x6 = 18 cells", cells(win, "rig") == 18, cells(win, "rig"))
T("the general rig has one section", cells(win, "rig_2") == 0)
T("backpack grid 6x5 = 30 cells", cells(win, "backpack") == 30, cells(win, "backpack"))
T("no supply button for ammunition items", window():find("supply_spare_magazine") == nil
  and window():find("supply_loose_ammo") == nil)
T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
T("no full-screen background (it is drawn white)", ENV.menus[#ENV.menus].params.background_blur == nil
  and ENV.menus[#ENV.menus].params.background_color == nil)
local function named(n)
  for _, w in ipairs(windows()) do if w.params.name == n then return w end end
end
T("in the menu three windows: one at each edge, what you bring in the middle", #windows() == 3
  and windows()[1].params.position == "LeftCentery" and windows()[2].params.position == "RightCentery"
  and named("pdti_shop") and named("pdti_shop").params.position == "Center")
for _, w in ipairs(windows()) do
  T("window " .. w.params.name .. " resized to content", w.pw >= 250 and w.ph > 150, w.pw .. "x" .. w.ph)
end
T("the pockets, the rig and the loadout are on the left",
  windows()[1]:find("cell_pockets_0_0") and windows()[1]:find("cell_rig_0_0") and windows()[1]:find("loadout_none"))
T("the backpack is on the right, what you bring in the middle",
  windows()[2]:find("cell_backpack_0_0") and windows()[2]:find("bring_label") == nil
  and named("pdti_shop"):find("bring_label") and named("pdti_shop"):find("bring_plus_first_aid_kit")
  and named("pdti_shop"):find("bring_plus_trip_mine") and window():find("supplies_label") == nil)
do
  -- The items are two to a row.
  local a, b = named("pdti_shop"):find("bring_plus_first_aid_kit"), named("pdti_shop"):find("bring_plus_doctor_bag")
  T("two items share a row", a and b and a.params.position[2] == b.params.position[2]
    and b.params.position[1] > a.params.position[1])
  local rows = {}
  for _, c in ipairs(named("pdti_shop").children) do
    local n = c.params.name or ""
    if n:find("^bring_plus_") and not n:find("mag_") and not n:find("loose_") then rows[c.params.position[2]] = true end
  end
  local items, nrows = #PDTI.Plan.Items(), 0
  for _ in pairs(rows) do nrows = nrows + 1 end
  T("so the items take half the rows", nrows == math.ceil(items / 2), nrows .. " rows for " .. items)
  T("no window is taller than the screen (the large backpack, every item)",
    windows()[1].ph <= 720 and windows()[2].ph <= 720 and named("pdti_shop").ph <= 720,
    windows()[1].ph .. "/" .. windows()[2].ph .. "/" .. named("pdti_shop").ph)
  T("the three windows fit side by side", windows()[1].pw + windows()[2].pw + named("pdti_shop").pw <= 1240)
  -- A screen too low for the windows: everything is drawn smaller.
  local menu = ENV.menus[#ENV.menus]
  local cell_before = windows()[2]:find("cell_backpack_0_0").pw
  menu._panel = { h = function() return 450 end }
  PDTI.RedrawUI()
  local tallest = math.max(windows()[1].ph, windows()[2].ph, named("pdti_shop").ph)
  T("a screen too low: the windows are drawn smaller to fit", windows()[2]:find("cell_backpack_0_0").pw < cell_before
    and (tallest <= 450 or windows()[2]:find("cell_backpack_0_0").pw == math.floor(36 * 0.6 + 0.5) - 2), tallest)
  menu._panel = nil
  PDTI.SetUIOpen(false)
  PDTI.SetUIOpen(true)
  T("opened again, the normal size", windows()[2]:find("cell_backpack_0_0").pw == cell_before)
end
do
  local kits = #PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" end)
  named("pdti_shop"):find("bring_plus_first_aid_kit"):click()
  local after_plus = #PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" end)
  named("pdti_shop"):find("bring_minus_first_aid_kit"):click()
  local after_minus = #PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" end)
  T("+ and - in the bring list add and remove one", after_plus == kits + 1 and after_minus == kits, kits .. "/" .. after_plus .. "/" .. after_minus)
end
T("item label drawn at its origin cell", win:find(string.format("cell_backpack_%d_%d", bag.x, bag.y)).params.text:find("Doctor") ~= nil)
T("R, Esc and the deployable key triggers registered",
  trigger("r") ~= nil and trigger("esc") ~= nil and trigger("g") ~= nil, #ENV.triggers)

-- 2b. layout: positions must be applied, nothing may overlap or leave the window
local function rects(w)
  local out = {}
  for _, c in ipairs(w.children) do
    local pos = c.params.position
    if type(pos) == "table" then out[#out + 1] = { name = c.params.name, x = pos[1], y = pos[2], w = c.pw, h = c.ph } end
  end
  return out
end
local function layout_problems(w)
  local list, bad = rects(w), {}
  for i, a in ipairs(list) do
    if a.x < 0 or a.y < 0 or a.x + a.w > w.pw + 0.5 or a.y + a.h > w.ph + 0.5 then bad[#bad + 1] = "outside window: " .. a.name end
    for j = i + 1, #list do
      local b = list[j]
      if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then
        bad[#bad + 1] = "overlap: " .. a.name .. " / " .. b.name
      end
    end
  end
  return bad
end
local function all_problems()
  local out = {}
  for _, w in ipairs(windows()) do for _, p in ipairs(layout_problems(w)) do out[#out + 1] = w.params.name .. ": " .. p end end
  return out
end
T("items were aligned after building (auto_align is off)",
  (windows()[1].align_calls or 0) >= 1 and windows()[1].dirty == false and windows()[2].dirty == false)
local lp = all_problems()
T("no overlapping or out-of-window items", #lp == 0, table.concat(lp, "; "):sub(1, 300))
-- The two side windows leave the middle of a 1280x720 screen for what you
-- bring (in a heist, for the health), and each fits the height (680: the
-- weapon slots' row is drawn here as in the game, 0.37.0).
T("the side windows leave the middle of the screen",
  windows()[1].pw + windows()[2].pw <= 640 and windows()[1].ph <= 680 and windows()[2].ph <= 680,
  windows()[1].pw .. "x" .. windows()[1].ph .. " + " .. windows()[2].pw .. "x" .. windows()[2].ph)

-- 3. pick up and place
win:find(string.format("cell_backpack_%d_%d", bag.x, bag.y)):click()
T("click on item picks it up", PDTI.UIGetHeld() and PDTI.UIGetHeld().instance_id == bag.instance_id)
T("status line describes held item", (status(window()) or ""):find("Holding: Doctor Bag") ~= nil, status(window()))
local fx, fy = PDTI.FindFreeSpace("backpack", "doctor_bag", false)
window():find("cell_backpack_5_4"):click() -- 3x2 item cannot fit at 5,4
local item = PDTI.FindItem("backpack", bag.instance_id)
T("invalid placement leaves inventory unchanged", item.x == bag.x and item.y == bag.y)
T("invalid placement keeps item held and explains why", PDTI.UIGetHeld() ~= nil and (status(window()) or ""):find("%[") ~= nil, status(window()))
window():find("cell_backpack_0_3"):click()
item = PDTI.FindItem("backpack", bag.instance_id)
T("valid placement moves the item", item.x == 0 and item.y == 3 and PDTI.UIGetHeld() == nil, item.x .. "," .. item.y)
T("moved label redrawn at new origin", window():find("cell_backpack_0_3").params.text:find("Doctor") ~= nil)
T("state valid after UI move", PDTI.ValidateState() == true)

-- 4. rotate
window():find("cell_backpack_0_3"):click()
window():find("btn_rotate"):click()
T("rotate button flips held item", PDTI.UIGetHeld().rotated == true)
trigger("r").clbk()
T("R key trigger flips held item back", PDTI.UIGetHeld().rotated == false)
window():find("btn_rotate"):click()
window():find("cell_backpack_3_0"):click()
item = PDTI.FindItem("backpack", bag.instance_id)
T("rotated item placed with swapped footprint", item.rotated == true and item.x == 3 and item.y == 0)
local map = PDTI.GetOccupancyMap("backpack")
T("rotated footprint is 2 wide x 3 tall", map.cells[1][4] == bag.instance_id and map.cells[3][5] == bag.instance_id and map.cells[1][6] == false)

-- 5. cancel hold, cross-container move
window():find("cell_backpack_3_0"):click()
window():find("btn_cancel"):click()
T("cancel clears held item without changes", PDTI.UIGetHeld() == nil and PDTI.FindItem("backpack", bag.instance_id).x == 3)
window():find("cell_pockets_0_0"):click()
T("pockets item picked up", PDTI.UIGetHeld() ~= nil and PDTI.UIGetHeld().container == "pockets")
window():find("cell_rig_2_5"):click()
T("pockets item moved to rig", PDTI.FindItem("rig", band.instance_id) ~= nil and PDTI.FindItem("pockets", band.instance_id) == nil)

-- 6. failed save during a UI move
window():find("cell_rig_2_5"):click()
json.encode = function() error("injected") end
window():find("cell_rig_0_0"):click()
json.encode = ENV.real_encode
T("failed save during UI move changes nothing", PDTI.FindItem("rig", band.instance_id).x == 2 and PDTI.FindItem("rig", band.instance_id).y == 5)
window():find("btn_cancel"):click()

-- 7. choosing the equipment (in the menu)
PDTI.AddItemAuto("backpack", "first_aid_kit", 1, nil, true)
T("three rigs and three backpacks to choose from",
  window():find("equip_rig_medical_rig") and window():find("equip_rig_assault_rig") and window():find("equip_rig_general_rig")
  and window():find("equip_backpack_small_backpack") and window():find("equip_backpack_medium_backpack")
  and window():find("equip_backpack_large_backpack"))
T("the chosen one is marked and described", window():find("equip_rig_general_rig").params.text:find("^> ")
  and window():find("equip_rig_info").params.text:find("25%% faster"))
T("in the menu the deployables are not shown", window():find("deploy_label") == nil)
window():find("equip_backpack_medium_backpack"):click()
T("a click changes the backpack", PDTI.GetEquipment().backpack == "medium_backpack", PDTI.GetEquipment().backpack)
T("everything is still there", PDTI.FindItem("backpack", bag.instance_id) ~= nil and PDTI.ValidateState() == true)
window():find("equip_rig_medical_rig"):click()
T("the medical rig has three sections", cells(window(), "rig_2") == 3 and cells(window(), "rig_3") == 3 and cells(window(), "rig") == 16)
window():find("equip_rig_general_rig"):click()
window():find("equip_backpack_large_backpack"):click()
T("back to the general rig and the large backpack", PDTI.GetEquipment().rig == "general_rig"
  and PDTI.GetEquipment().backpack == "large_backpack" and PDTI.ValidateState() == true)

-- 8. auto arrange from the UI
window():find("btn_arrange_pack"):click()
T("arrange button leaves state valid", PDTI.ValidateState() == true)

-- 9. close
PDTI.UIPickUp("backpack", bag.instance_id)
local layout_before = #PDTI.GetContainer("backpack").items
window():find("btn_close"):click()
T("close disables menu, clears held, removes the screen key triggers",
  PDTI.IsUIOpen() == false and not ENV.menus[1]:Enabled() and PDTI.UIGetHeld() == nil
  and trigger("r") == nil and trigger("esc") == nil)
T("the deployable key stays registered after closing", trigger("g") ~= nil)
T("close does not alter inventory", #PDTI.GetContainer("backpack").items == layout_before)
T("reopen works and reuses the same MenuUI", PDTI.ToggleUI() == true and #ENV.menus == 1)

-- 9b. supplies, discard, magazines, input blocking, Escape
local function supply_count() local n = 0 for _, c in ipairs(window().children) do if c.params.name and c.params.name:find("^supply_") then n = n + 1 end end return n end
local defs = 0 for _, d in pairs(PDTI.GetItemDefinitions()) do if d.deployable and not d.ammo_managed and not d.no_supply then defs = defs + 1 end end
-- The test spawner is shown in a heist (the briefing counts).
PDTI.SetSessionOnly(true)
PDTI.RedrawUI()
T("in a heist the spawner takes the place of the bring list", window():find("supplies_label") ~= nil and window():find("bring_label") == nil)
T("one spawn button per deployable (items without an effect are not offered)", supply_count() == defs and defs == 11, supply_count() .. " vs " .. defs)
T("no spawn button for items without an effect", window():find("supply_ecm_battery") == nil and window():find("supply_grenade") == nil)
T("spawn buttons for the ammunition of both guns", window():find("spawn_loose_primary") ~= nil and window():find("spawn_mag_secondary") ~= nil)

PDTI.SelectContainer("rig")
local rig_before = #PDTI.GetContainer("rig").items
window():find("supply_first_aid_kit"):click()
T("supply goes to the selected container when allowed", #PDTI.GetContainer("rig").items == rig_before + 1)
T("status reports where it went", (status(window()) or ""):find("Added First Aid Kit to rig") ~= nil, status(window()))
do -- the kit is bigger than a battery: make room for the magazine checks below
  local items = PDTI.GetContainer("rig").items
  PDTI.RemoveItem("rig", items[#items].instance_id)
end
PDTI.SetEquipment("rig", "assault_rig") -- no room for a doctor bag in this rig
PDTI.SelectContainer("rig")
window():find("supply_doctor_bag"):click()
T("supply falls back to another container when selected disallows it", PDTI.FindItem("backpack", bag.instance_id) ~= nil and (status(window()) or ""):find("Doctor Bag") ~= nil, status(window()))
local n_fill = 0
while PDTI.AddItemAuto("backpack", "doctor_bag", 1, nil, true) and n_fill < 50 do n_fill = n_fill + 1 end
local count_before = #PDTI.GetContainer("backpack").items
window():find("supply_doctor_bag"):click()
T("no room: nothing added and reason shown", #PDTI.GetContainer("backpack").items == count_before and (status(window()) or ""):find("Cannot add") ~= nil, status(window()))
local held_item = PDTI.GetContainer("backpack").items[1]
PDTI.UIPickUp("backpack", held_item.instance_id)
window():find("btn_discard"):click()
T("discard removes the held item", PDTI.FindItem("backpack", held_item.instance_id) == nil and PDTI.UIGetHeld() == nil)
window():find("btn_discard"):click()
T("discard with nothing held changes nothing and explains", (status(window()) or ""):find("Pick up") ~= nil)
T("state valid after supplies/discard", PDTI.ValidateState() == true)

window():find("btn_cancel"):click()
T("the backpack side no longer lists the ammunition", window():find("ammo_label") == nil
  and window():find("loose_line_1") == nil and window():find("mag_line_1") == nil)
-- Ctrl+click on a loose spawn button: a full stack.
do
  local saved_input = rawget(_G, "Input")
  local ammo = PDTI.Ammo
  local got = {}
  local saved = ammo.DevSpawnLoose
  ammo.DevSpawnLoose = function(slot, bullet, rounds) got = { slot, rounds } return true, rounds or 30 end
  local btn = window():find("spawn_loose_primary")
  if btn then btn:click() end
  T("a click on loose spawns a magazine's worth", btn ~= nil and got[1] == "primary" and got[2] == nil, tostring(got[2]))
  _G.Input = { keyboard = function() return { down = function() return true end } end }
  _G.Idstring = _G.Idstring or function(v) return v end
  btn = window():find("spawn_loose_primary")
  if btn then btn:click() end
  _G.Input = saved_input
  T("Ctrl+click on loose spawns a full stack", got[2] == ammo.MAX_STACK, tostring(got[2]))
  ammo.DevSpawnLoose = saved
end

-- 9c. the health window: every body part, its colour and its HP
dofile(ROOT .. "lua/body.lua")
local Body = PDTI.Body
Body.OnHeistStart()
PDTI.RedrawUI()
local function hwin()
  for _, w in ipairs(windows()) do if w.params.name == "pdti_health" then return w end end
end
local function part(id) return hwin() and hwin():find("health_part_" .. id) end
T("in a heist a window shows the health", hwin() ~= nil and hwin().params.position == "CenterBottom")
T("and the middle window of the menu is empty and folded away", named("pdti_shop") and #named("pdti_shop").children == 0
  and named("pdti_shop").pw == 1 and named("pdti_shop").ph == 1)
T("a box for every part", part("head") and part("body") and part("arm_l") and part("arm_r")
  and part("leg_l") and part("leg_r"))
T("each with its HP and its maximum", part("head").params.text == "HEAD\n18 / 18"
  and part("body").params.text == "BODY\n81 / 81", part("head").params.text .. " " .. part("body").params.text)
T("the total on top", hwin():find("health_label").params.text == "Health  230 / 230", hwin():find("health_label").params.text)
local green = part("arm_l").params.background_color
Body.Damage(1.5, "arm_l", 23)     -- 31 of 31 -> 16
Body.EFFECTS.spread_damage, Body.spread_saved = 0, Body.EFFECTS.spread_damage
Body.Damage(9, "leg_r", 23)       -- black
Body.EFFECTS.spread_damage = Body.spread_saved
PDTI.RedrawUI()
T("a hurt part shows what is left", part("arm_l").params.text == "L ARM\n16 / 31", part("arm_l").params.text)
T("and changes colour", part("arm_l").params.background_color ~= nil
  and table.concat(part("arm_l").params.background_color, ",") ~= table.concat(green, ","))
T("a black part shows 0, in black", part("leg_r").params.text == "R LEG\n0 / 34"
  and part("leg_r").params.background_color[1] < 0.2, part("leg_r").params.text)
T("what the black parts do is listed", (hwin():find("health_effect_1").params.text or ""):find("no sprinting") ~= nil,
  hwin():find("health_effect_1").params.text)
T("and how to heal them", hwin():find("health_hint_medic") ~= nil)
local hp = layout_problems(hwin())
T("the health window is laid out cleanly", #hp == 0, table.concat(hp, "; "))
T("only documented MenuUI parameters in it", #ENV.violations == 0, table.concat(ENV.violations, ","))
Body.OnHeistStart()

PDTI.SetSessionOnly(false) -- back in the menu
PDTI.RedrawUI()
T("back in the menu the health window is empty", #hwin().children == 0)
T("and what you bring is back in the middle", named("pdti_shop"):find("bring_label") ~= nil
  and named("pdti_shop").pw > 1)

-- input blocking with a fake player controller
local ctrl = { on = true }
function ctrl:enabled() return self.on end
function ctrl:set_enabled(v) self.on = v end
local unit = { base = function() return { controller = function() return ctrl end } end }
_G.alive = function(u) return u ~= nil end
_G.managers = { player = { player_unit = function() return unit end } }
PDTI.SetUIOpen(false)
PDTI.SetUIOpen(true)
T("game controller disabled while screen is open", ctrl.on == false)
trigger("esc").clbk() -- Esc
T("Esc closes the screen", PDTI.IsUIOpen() == false)
T("Esc restores game input", ctrl.on == true)
T("Esc removes the screen key triggers", trigger("r") == nil and trigger("esc") == nil)
ctrl.on = false -- game had input disabled already (cutscene, downed...)
PDTI.SetUIOpen(true); PDTI.SetUIOpen(false)
T("input that was already disabled is not force-enabled on close", ctrl.on == false)
ctrl.on = true
_G.managers = { player = { player_unit = function() return nil end } }
T("opens without a player unit (main menu)", PDTI.SetUIOpen(true) == true)
PDTI.SetUIOpen(false)
unit = { base = function() return {} end }
_G.managers = { player = { player_unit = function() return unit end } }
T("opens when the player has no controller accessor", PDTI.SetUIOpen(true) == true)
PDTI.SetUIOpen(false)
_G.managers, _G.alive = nil, nil

do
  PDTI.SetUIOpen(true)
  local w3 = windows()[2]
  window():find("btn_cancel"):click()
  T("window stays aligned after redraws", w3.dirty == false and (w3.align_calls or 0) > 1)
  local lp2 = all_problems()
  T("layout still clean after many interactions", #lp2 == 0, table.concat(lp2, "; "):sub(1, 300))
  -- other equipment sizes
  local bad = {}
  T("a change that leaves no room for something is refused",
    PDTI.SetEquipment("rig", "assault_rig") and PDTI.SetEquipment("backpack", "small_backpack") == false)
  PDTI.Reset()
  for _, rig in ipairs({ "medical_rig", "assault_rig", "general_rig" }) do
    for _, pack in ipairs({ "small_backpack", "medium_backpack", "large_backpack" }) do
      window():find("equip_rig_" .. rig):click()
      window():find("equip_backpack_" .. pack):click()
      local lp3 = all_problems()
      local l, r = windows()[1], windows()[2]
      if PDTI.GetEquipment().rig ~= rig or PDTI.GetEquipment().backpack ~= pack then
        bad[#bad + 1] = rig .. "+" .. pack .. ": not equipped (" .. tostring(status(window())) .. ")"
      elseif #lp3 > 0 or l.pw + r.pw > 640 or l.ph > 680 or r.ph > 680 then
        bad[#bad + 1] = rig .. "+" .. pack .. ": " .. l.pw .. "x" .. l.ph .. " " .. r.pw .. "x" .. r.ph
          .. " " .. table.concat(lp3, "; "):sub(1, 200)
      end
    end
  end
  T("layout clean for all nine rig and backpack combinations", #bad == 0, table.concat(bad, " | "))

  -- 0.31.0: the room bonuses, every room at tier 3 (the tiers seen before
  -- count without the safehouse), the biggest options, heavy armour.
  local real_armour = PDTI.Perks.ArmourPiece
  PDTI.Perks.ArmourPiece = function() return "heavy_armour" end
  PDTI.Reset()
  local all3 = {}
  for room in pairs(PDTI.Perks.ROOMS) do all3[room] = 3 end
  PDTI.NoteRoomTiers(all3)
  window():find("equip_tab_perks"):click()
  T("the Room bonuses tab opens", PDTI._EquipTab() == "perks" and window():find("perk_general_rig_old_hoxton") ~= nil)
  T("  it shows the armour's options too", window():find("perk_heavy_armour_jowi") ~= nil)
  window():find("perk_general_rig_old_hoxton"):click()
  T("  a click picks Old Hoxton: general rig 5x6", PDTI.GetContainerInfo("rig").width == 5)
  T("  the line says what it does", (window():find("perk_general_rig_info").params.text or ""):find("Old Hoxton III") ~= nil,
    window():find("perk_general_rig_info").params.text)
  PDTI.Perks.OPTIONS.american.ready = false
  window():find("perk_general_rig_american"):click()
  T("  a bonus not made yet is refused, with why", PDTI.GetContainerInfo("rig").width == 5
    and (status(window()) or ""):find("not made yet") ~= nil, status(window()))
  PDTI.Perks.OPTIONS.american.ready = nil
  window():find("perk_general_rig_none"):click()
  T("  No bonus: back to 3x6", PDTI.GetContainerInfo("rig").width == 3)
  PDTI.SetPerkChoice("assault_rig", "spanish")
  PDTI.SetPerkChoice("general_rig", "old_hoxton")
  PDTI.SetPerkChoice("small_backpack", "bodhi")
  PDTI.SetPerkChoice("medium_backpack", "dragan")
  PDTI.SetPerkChoice("heavy_armour", "jowi")
  local bad2 = {}
  for _, tab in ipairs({ "gear", "perks" }) do
    for _, rig in ipairs({ "medical_rig", "assault_rig", "general_rig" }) do
      for _, pack in ipairs({ "small_backpack", "medium_backpack", "large_backpack" }) do
        PDTI.SetEquipment("rig", rig)
        PDTI.SetEquipment("backpack", pack)
        window():find("equip_tab_" .. tab):click()
        local lp4 = all_problems()
        local l, r = windows()[1], windows()[2]
        if #lp4 > 0 or l.pw + r.pw > 640 or l.ph > 680 or r.ph > 680 then
          bad2[#bad2 + 1] = tab .. " " .. rig .. "+" .. pack .. ": " .. l.pw .. "x" .. l.ph .. " " .. r.pw .. "x" .. r.ph
            .. " " .. table.concat(lp4, "; "):sub(1, 200)
        end
      end
    end
  end
  T("layout clean with the biggest room bonuses, both tabs", #bad2 == 0, table.concat(bad2, " | "))
  -- Clover's loot slots (2x4) next to the medium backpack.
  PDTI.SetEquipment("backpack", "medium_backpack")
  PDTI.SetPerkChoice("medium_backpack", "clover")
  local bad3 = {}
  for _, rig in ipairs({ "medical_rig", "assault_rig", "general_rig" }) do
    PDTI.SetEquipment("rig", rig)
    window():find("equip_tab_gear"):click()
    local lp5 = all_problems()
    local l, r = windows()[1], windows()[2]
    if #lp5 > 0 or l.ph > 680 or r.ph > 680 or not window():find("cell_loot_slot_1_3") then
      bad3[#bad3 + 1] = rig .. ": " .. l.ph .. " " .. r.ph .. " " .. table.concat(lp5, "; "):sub(1, 200)
    end
  end
  T("Clover's loot slots: drawn next to the backpack, layout clean", #bad3 == 0, table.concat(bad3, " | "))
  window():find("equip_tab_gear"):click()
  PDTI.Perks.ArmourPiece = real_armour
  PDTI.Reset()
end

-- 10. window not ready yet (deferred create_items)
PDTI.SetUIOpen(false)
ENV.install_menuui(true)
-- reload renderer so it forgets the previous menu
dofile(ROOT .. "lua/ui_beardlib.lua")
T("opening before MenuUI is ready fails softly", PDTI.ToggleUI() == false and PDTI.IsUIOpen() == false)
ENV.menus[#ENV.menus]:finish()
T("opening succeeds once MenuUI finished initializing", PDTI.ToggleUI() == true)

-- 11. a failing callback must not escape into the game
local w2 = window()
local real_rotate = PDTI.UIRotateHeld
PDTI.UIRotateHeld = function() error("boom") end
local ok_click = pcall(function() w2:find("btn_rotate"):click() end)
PDTI.UIRotateHeld = real_rotate
local logged = false
for _, l in ipairs(ENV.logs) do if l:find("callback error") and l:find("boom") then logged = true end end
T("callback error is contained and logged", ok_click == true and logged)

-- 12. a second click without moving the mouse: after every redraw the menu
-- is told on its next update where the mouse is, so the new button under it
-- is highlighted (MenuUI only takes a click on the highlighted item).
do
  local menu = ENV.menus[#ENV.menus]
  local saved = rawget(_G, "managers")
  _G.managers = _G.managers or {}
  local had_pointer = managers.mouse_pointer
  managers.mouse_pointer = { _mouse = { world_position = function() return 123, 45 end } }
  menu.next_update, menu.moved = {}, 0
  window():find("btn_rotate"):click()
  T("a redraw asks for the mouse on the next update", #(menu.next_update or {}) >= 1)
  menu:update()
  T("which moves the mouse to where it is", (menu.moved or 0) >= 1 and menu.moved_at[1] == 123 and menu.moved_at[2] == 45)
  PDTI.SetUIOpen(false)
  menu.next_update, menu.moved = {}, 0
  PDTI._UIRehighlight()
  T("nothing is asked while the screen is closed", #menu.next_update == 0)
  PDTI.SetUIOpen(true)
  managers.mouse_pointer = had_pointer
  _G.managers = saved
end

-- 13. text that is too wide for its box gets a smaller font
do
  local fit = PDTI._UIFitFont
  T("short text keeps its font", fit("30/30", 40, 30, 11) == 11)
  T("a long line gets smaller", fit("Combined Tactical Vest", 60, nil, 13) < 13)
  T("never below 8", fit(string.rep("W", 80), 30, 20, 13) == 8)
  T("two lines must fit the height", fit("30\nHP+", 100, 18, 13) < 13 and fit("30\nHP+", 100, 40, 13) == 13)
  local small = 0
  for _, c in ipairs(window().children) do
    local fs, t = c.params.font_size, c.params.text
    if c.params.name and c.params.name:find("^cell_") and t and t ~= "" then
      for part in (t .. "\n"):gmatch("(.-)\n") do
        if #part * fs * 0.55 > c.pw - 4 + 0.01 and fs > 8 then small = small + 1 end
      end
    end
  end
  T("every cell label fits its cell", small == 0, small)
end

-- 0.29.0: in the menu the middle window has tabs; captured loot comes first.
do
  local Stash = PDTI.Stash
  PDTI.SetUIOpen(false)
  local d = Stash._Data()
  d.pending = {
    { id = 1, carry_id = "gold", quality = 2, mods = "light", value = 20000 },
    { id = 2, carry_id = "money", quality = 1, mods = "", value = 12000 }
  }
  d.next_id = 3
  PDTI.SetUIOpen(true)
  local shop = named("pdti_shop")
  T("captured loot waiting: its tab opens first", shop:find("cap_keep_1") and shop:find("cap_sell_2")
    and shop:find("bring_label") == nil)
  T("the tab names how many wait", shop:find("shop_tab_captured").params.text == "Captured (2)")
  T("a High quality bag is coloured, a Standard one is not", shop:find("cap_line_1").params.foreground ~= nil
    and shop:find("cap_line_2").params.foreground == nil)
  T("its modifier is named", shop:find("cap_line_1").params.text:find("Light", 1, true) ~= nil,
    shop:find("cap_line_1").params.text)
  shop:find("cap_keep_1"):click()
  shop = named("pdti_shop")
  T("Stash: the bag moves to the stash", #Stash.Bags() == 1 and #Stash.Pending() == 1 and shop:find("cap_keep_1") == nil)
  shop:find("shop_tab_stash"):click()
  shop = named("pdti_shop")
  T("the stash tab lists it with a sell button", shop:find("stash_sell_1") ~= nil and shop:find("cap_keep_2") == nil)
  for i = 2, 12 do d.bags[i] = { id = 100 + i, carry_id = "gold", quality = 1, mods = "", value = 1 } end
  PDTI.RedrawUI()
  T("a full stash still fits the screen", named("pdti_shop").ph <= 720, named("pdti_shop").ph)
  named("pdti_shop"):find("shop_tab_captured"):click()
  named("pdti_shop"):find("cap_keep_2"):click()
  T("a full stash: the bag waits and the reason is shown", #Stash.Pending() == 1
    and tostring(status(window())):find("full") ~= nil, status(window()))
  named("pdti_shop"):find("shop_tab_bring"):click()
  T("the bring list is a tab away", named("pdti_shop"):find("bring_label") ~= nil)
  T("only documented MenuUI parameters used (stash)", #ENV.violations == 0, table.concat(ENV.violations, ","))
  d.bags, d.pending = {}, {}

  -- 0.33.1: the market opens through Scarface, not from the inventory.
  local M = PDTI.Market
  local real_today = M.Today
  M.Today = function() return "2026-11-17" end
  T("the inventory has no market tab", named("pdti_shop"):find("shop_tab_market") == nil
    and named("pdti_shop"):find("shop_tab_stash") ~= nil)
  -- The game's bag values: 14 loot types (more than fit the list at once).
  local had_td = rawget(_G, "tweak_data")
  _G.tweak_data = had_td or {}
  local real_carry, real_mm = tweak_data.carry, tweak_data.money_manager
  tweak_data.carry = { small_loot = { ring = true }, ring = { type = "light", bag_value = "gold" },
    car = { type = "heavy", bag_value = "gold", is_vehicle = true } }
  tweak_data.money_manager = { bag_values = { gold = 2875, money = 1500, meth = 13000 } }
  for i = 1, 12 do tweak_data.carry["loot" .. i] = { type = "medium", bag_value = i % 2 == 0 and "money" or "meth" } end
  tweak_data.carry.gold = { type = "heavy", bag_value = "gold" }
  tweak_data.carry.money = { type = "medium", bag_value = "money" }
  T("the market opens on its own", PDTI.OpenMarket() == true and PDTI.IsMarketOpen())
  local left_w = windows()[1]
  local plist = left_w:find("market_prices")
  T("  the prices: every loot type in a list that scrolls (not vehicles, not small loot)", plist ~= nil
    and #plist.children == 14 and plist.params.scrollbar == true and plist:find("market_price_car") == nil
    and plist:find("market_price_ring") == nil, plist and #plist.children)
  local grow = plist:find("market_price_gold")
  T("  a row: name, now, real", grow ~= nil and grow.params.text:find("now $2.9k", 1, true) ~= nil
    and grow.params.text:find("real $2.9k", 1, true) ~= nil, grow and grow.params.text)
  T("  the graph: 7 bars, the last is today", left_w:find("market_graph_bar_7") ~= nil and left_w:find("market_graph_bar_8") == nil
    and left_w:find("market_graph_day_7").params.text == "Today")
  local order = {}
  for i, c in ipairs(plist.children) do order[i] = tostring(c.params.name):gsub("^market_price_", "") end
  T("  dearest today first (0.44.1): the meth, then gold, then the money", order[1] == "loot1" and order[6] == "loot9"
    and order[7] == "gold" and order[8] == "loot10" and order[14] == "money", table.concat(order, ","))
  T("  at first the graph shows the first type", left_w:find("market_graph_title").params.text:find("loot1", 1, true) ~= nil,
    left_w:find("market_graph_title").params.text)
  plist:find("market_price_money"):click()
  T("  a click on a row shows its graph", left_w:find("market_graph_title").params.text:find("money", 1, true) ~= nil
    and left_w:find("market_graph_bar_1") ~= nil and #left_w:find("market_prices").children == 14,
    left_w:find("market_graph_title").params.text)
  -- A redraw (health, ammunition) keeps the list as it is: still scrolled.
  local builds = PDTI._UIPriceBuilds
  local same_list = left_w:find("market_prices")
  PDTI.RedrawUI(); PDTI.RedrawUI()
  T("  a redraw keeps the price list (it stays scrolled)", PDTI._UIPriceBuilds == builds
    and left_w:find("market_prices") == same_list and #same_list.children == 14
    and left_w:find("market_graph_bar_7") ~= nil and left_w:find("market_prices_label") ~= nil)
  local glp2 = layout_problems(left_w)
  T("  after it nothing is doubled or overlaps", #glp2 == 0, table.concat(glp2, "; "))
  tweak_data.carry.loot99 = { type = "light", bag_value = "gold" }
  PDTI.RedrawUI()
  T("  new rows: the list is made again", PDTI._UIPriceBuilds == builds + 1 and #left_w:find("market_prices").children == 15
    and #layout_problems(left_w) == 0)
  tweak_data.carry.loot99 = nil
  PDTI.RedrawUI()
  -- Scarface's dialog closing turns the controls on: off again next frame.
  local ctl = { on = false }
  function ctl:enabled() return self.on end
  function ctl:set_enabled(v) self.on = v end
  PDTI._UIInputBlock({ controller = ctl, was_enabled = false })
  T("  controls already off: nothing to do", PDTI.UIKeepInputBlocked() == false and ctl.on == false)
  ctl.on = true
  T("  turned on by something else: off again", PDTI.UIKeepInputBlocked() == true and ctl.on == false
    and PDTI._UIInputBlock().was_enabled == true)
  local glp = layout_problems(left_w)
  T("  the prices window: nothing overlaps", #glp == 0, table.concat(glp, "; "))
  shop = named("pdti_shop")
  T("  the inventory is not shown: prices on the left, the right empty, no tabs", windows()[2].pw <= 1
    and windows()[1]:find("market_prices") ~= nil and windows()[1]:find("cell_pockets_0_0") == nil
    and shop:find("shop_tab_stash") == nil and shop:find("market_close") ~= nil)
  T("the market: three offers with Accept buttons, no contracts yet", shop:find("market_accept_3") ~= nil
    and shop:find("market_accept_4") == nil and shop:find("market_active_none") ~= nil)
  local offer = M.Offers()[1]
  T("  an offer says what it asks and pays", shop:find("market_offer_1").params.text:find("pays x", 1, true) ~= nil,
    shop:find("market_offer_1").params.text)
  shop:find("market_accept_1"):click()
  shop = named("pdti_shop")
  T("Accept: it becomes your contract", #M.Active() == 1 and shop:find("market_deliver_1") ~= nil
    and shop:find("market_accept_3") == nil)
  shop:find("market_deliver_1"):click()
  T("  Deliver without the bags: refused, the reason shown in the market", #M.Active() == 1
    and named("pdti_shop"):find("market_status") ~= nil
    and named("pdti_shop"):find("market_status").params.text:find("bags it needs") ~= nil)
  for i = 1, offer.count do d.bags[i] = { id = 300 + i, carry_id = offer.carry_id, quality = 3, mods = "", value = 1000 } end
  PDTI.RedrawUI()
  named("pdti_shop"):find("market_deliver_1"):click()
  T("  with them: delivered, the bags are gone", #M.Active() == 0 and #Stash.Bags() == 0)
  for i = 1, 2 do M.Accept(M.Offers()[1].key) end
  for i = 1, 12 do d.bags[i] = { id = 400 + i, carry_id = "gold", quality = 3, mods = "light,runner", value = 123456 } end
  M._State().high_rolls = 1
  PDTI.RedrawUI()
  local ws = all_problems and all_problems() or {}
  local tiny = {}
  for _, ch in ipairs(named("pdti_shop").children) do
    local nm = ch.params.name or ""
    if nm:find("^market_") and (ch.params.font_size or 99) < 11 then tiny[#tiny + 1] = nm .. "=" .. ch.params.font_size end
  end
  T("the market's lines stay readable (font 11 or more)", #tiny == 0, table.concat(tiny, " "))
  T("a busy market fits the screen", named("pdti_shop").ph <= 720 and #ws == 0, named("pdti_shop").ph .. " " .. table.concat(ws, "; "))
  T("only documented MenuUI parameters used (market)", #ENV.violations == 0, table.concat(ENV.violations, ","))
  -- 0.36.0: the weapons market (a tab of Scarface's market).
  do
    local A = PDTI.Armory
    local had_m = rawget(_G, "managers")
    _G.managers = had_m or {}
    local saved = {}
    for _, k in ipairs({ "money", "weapon_factory", "blackmarket", "localization" }) do saved[k] = managers[k] end
    local cash = 100000
    managers.money = { total = function() return cash end, deduct_from_total = function(_, v) cash = cash - v end,
      get_weapon_price_modified = function(_, id) return id == "pistol_a" and 5000 or 20000 end,
      get_weapon_modify_price = function() return 0 end }
    managers.weapon_factory = { get_factory_id_by_weapon_id = function(_, id) return "f_" .. id end,
      get_default_blueprint_by_factory_id = function(_, f) return { f .. "_body" } end }
    managers.blackmarket = { weapon_unlocked = function() return true end,
      _calculate_weapon_concealment = function() return 20 end }
    managers.localization = { text = function(_, id) return id end }
    local real_weapon = tweak_data.weapon
    tweak_data.weapon = {}
    for i = 1, 12 do
      tweak_data.weapon["rifle_" .. i] = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "Rifle " .. i }
    end
    tweak_data.weapon.pistol_a = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "Pistol A" }
    -- 0.42.0: more kinds, for the market's pages.
    tweak_data.weapon.shotgun_p = { use_data = { selection_index = 2 }, categories = { "shotgun" }, name_id = "Shotgun P" }
    tweak_data.weapon.lmg_p = { use_data = { selection_index = 2 }, categories = { "lmg", "smg" }, name_id = "LMG P" }
    tweak_data.weapon.akimbo_p = { use_data = { selection_index = 2 }, categories = { "akimbo", "pistol" }, name_id = "Akimbo P" }
    tweak_data.weapon.bow_p = { use_data = { selection_index = 2 }, categories = { "bow" }, name_id = "Bow P" }
    tweak_data.weapon.smg_s = { use_data = { selection_index = 1 }, categories = { "smg" }, name_id = "SMG S" }
    tweak_data.weapon.shotgun_s = { use_data = { selection_index = 1 }, categories = { "shotgun" }, name_id = "Shotgun S" }
    -- (a modded weapon may name akimbo second)
    tweak_data.weapon.akimbo_q = { use_data = { selection_index = 2 }, categories = { "smg", "akimbo" }, name_id = "Akimbo Q" }
    local real_fr, real_sr = A.FactorRoll, A.StockRoll
    A.FactorRoll = function() return 0.5 end
    A.StockRoll = function() return 0.3 end
    A.Reset()
    os.remove((os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_ui") .. "/pdti_armory.json")
    A.Reset()
    named("pdti_shop"):find("market_tab_weapons"):click()
    local lw = windows()[1]
    local wl = lw:find("wmarket_prices")
    local function txt(win, name) local it = win:find(name); return it and tostring(it.params.text) end
    T("the Weapons tab: a page for primaries and one for secondaries, the loot prices gone",
      txt(lw, "wmarket_page_primaries") == "Primary (17)" and txt(lw, "wmarket_page_secondaries") == "Secondary (3)"
      and lw:find("market_prices") == nil, txt(lw, "wmarket_page_primaries"))
    T("  Primary first, its first type: the 12 rifles in a list that scrolls", wl ~= nil and #wl.children == 12
      and wl.params.scrollbar == true and wl:find("wmarket_price_rifle_1") ~= nil
      and txt(lw, "wmarket_prices_label") == "Assault rifles  (12)", wl and #wl.children)
    T("  a button for each type it has, in order: rifles, shotguns, LMGs, akimbo, special (none for pistols)",
      txt(lw, "wmarket_type_assault_rifle") == "Rifles" and txt(lw, "wmarket_type_shotgun") == "Shotguns"
      and txt(lw, "wmarket_type_lmg") == "LMGs" and txt(lw, "wmarket_type_akimbo") == "Akimbo"
      and txt(lw, "wmarket_type_special") == "Special" and lw:find("wmarket_type_pistol") == nil
      and lw:find("wmarket_type_snp") == nil
      and lw:find("wmarket_type_lmg").params.position[1] > lw:find("wmarket_type_shotgun").params.position[1]
      and lw:find("wmarket_type_special").params.position[2] > lw:find("wmarket_type_akimbo").params.position[2])
    T("  the middle shows the first rifle", txt(named("pdti_shop"), "wmarket_pick"):find("Rifle 1", 1, true) ~= nil,
      txt(named("pdti_shop"), "wmarket_pick"))
    lw:find("wmarket_type_special"):click()
    lw = windows()[1]
    T("Special: the bow alone, picked", #lw:find("wmarket_prices").children == 1
      and lw:find("wmarket_prices"):find("wmarket_price_bow_p") ~= nil and txt(lw, "wmarket_prices_label") == "Special  (1)"
      and txt(named("pdti_shop"), "wmarket_pick"):find("Bow P", 1, true) ~= nil, txt(named("pdti_shop"), "wmarket_pick"))
    lw:find("wmarket_type_akimbo"):click()
    lw = windows()[1]
    T("  Akimbo: the akimbo weapons (not with the pistols or SMGs), akimbo named first or not",
      #lw:find("wmarket_prices").children == 2 and lw:find("wmarket_prices"):find("wmarket_price_akimbo_p") ~= nil
      and lw:find("wmarket_prices"):find("wmarket_price_akimbo_q") ~= nil and lw:find("wmarket_type_smg") == nil)
    lw:find("wmarket_type_shotgun"):click()
    windows()[1]:find("wmarket_page_secondaries"):click()
    T("  from Shotguns to the Secondary page: its first type (pistols), not its shotguns",
      txt(windows()[1], "wmarket_prices_label") == "Pistols  (1)", txt(windows()[1], "wmarket_prices_label"))
    windows()[1]:find("wmarket_page_primaries"):click()
    windows()[1]:find("wmarket_type_lmg"):click()
    lw = windows()[1]
    T("  LMGs: the LMG (an LMG the game also calls an SMG)", lw:find("wmarket_prices"):find("wmarket_price_lmg_p") ~= nil
      and #lw:find("wmarket_prices").children == 1)
    lw:find("wmarket_page_secondaries"):click()
    lw = windows()[1]
    T("the Secondary page: pistols, shotguns, SMGs; the pistol picked", txt(lw, "wmarket_type_pistol") == "Pistols"
      and txt(lw, "wmarket_type_smg") == "SMGs" and txt(lw, "wmarket_type_shotgun") == "Shotguns"
      and lw:find("wmarket_type_pistol").params.position[1] < lw:find("wmarket_type_smg").params.position[1]
      and lw:find("wmarket_type_smg").params.position[1] < lw:find("wmarket_type_shotgun").params.position[1]
      and lw:find("wmarket_type_assault_rifle") == nil
      and lw:find("wmarket_page_secondaries").params.background_color ~= lw:find("wmarket_page_primaries").params.background_color
      and txt(named("pdti_shop"), "wmarket_pick"):find("Pistol A", 1, true) ~= nil, txt(named("pdti_shop"), "wmarket_pick"))
    lw:find("wmarket_type_smg"):click()
    T("  SMGs: the SMG", windows()[1]:find("wmarket_prices"):find("wmarket_price_smg_s") ~= nil
      and txt(named("pdti_shop"), "wmarket_pick"):find("SMG S", 1, true) ~= nil)
    windows()[1]:find("wmarket_page_primaries"):click()
    T("  back to Primary: its first type again", txt(windows()[1], "wmarket_prices_label") == "Assault rifles  (12)"
      and txt(named("pdti_shop"), "wmarket_pick"):find("Rifle 1", 1, true) ~= nil)
    windows()[1]:find("wmarket_page_secondaries"):click()
    lw = windows()[1]
    wl = lw:find("wmarket_prices")
    local prow = wl:find("wmarket_price_pistol_a")
    T("  a row: name, today, normal, how many for sale", prow ~= nil and prow.params.text:find("Pistol A", 1, true) ~= nil
      and prow.params.text:find("1 for sale", 1, true) ~= nil and prow.params.text:find("normal $5.0k", 1, true) ~= nil,
      prow and prow.params.text)
    prow:click()
    local shop2 = named("pdti_shop")
    T("  a click picks it: its price and a Buy button", shop2:find("wmarket_pick").params.text:find("Pistol A", 1, true) ~= nil
      and shop2:find("wmarket_buy") ~= nil, shop2:find("wmarket_pick").params.text)
    T("  the list stays (not made again)", windows()[1]:find("wmarket_prices") == wl)
    shop2:find("wmarket_buy"):click()
    T("Buy: the weapon is yours, paid", #A.Weapons() == 1 and cash == 95000, cash)
    T("  none left today", named("pdti_shop"):find("wmarket_stock").params.text:find("None", 1, true) ~= nil)
    named("pdti_shop"):find("wmarket_buy"):click()
    T("  again: refused, the reason shown", #A.Weapons() == 1 and named("pdti_shop"):find("market_status") ~= nil)
    local wlp = layout_problems(windows()[1])
    T("  the weapons window: nothing overlaps", #wlp == 0, table.concat(wlp, "; "))
    named("pdti_shop"):find("market_tab_loot"):click()
    T("back to Loot: the loot prices again, the weapons list gone", windows()[1]:find("market_prices") ~= nil
      and windows()[1]:find("wmarket_prices") == nil)
    -- 0.37.0: your weapons are grid items: the inventory's Locker tab.
    local had_global = rawget(_G, "Global")
    _G.Global = had_global or {}
    local had_bm = Global.blackmarket_manager
    Global.blackmarket_manager = { crafted_items = { primaries = {}, secondaries = {} } }
    tweak_data.weapon.amcar = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AMCAR" }
    PDTI.SetUIOpen(false)
    PDTI.SetUIOpen(true)
    local shop3 = named("pdti_shop")
    T("the inventory's Locker tab names how many weapons you own", shop3:find("shop_tab_locker") ~= nil
      and shop3:find("shop_tab_locker").params.text == "Locker (2)" and shop3:find("shop_tab_weapons") == nil)
    shop3:find("shop_tab_locker"):click()
    shop3 = named("pdti_shop")
    T("  the 12x20 locker, 8 rows shown (the weapon slots are not here)", shop3:find("cell_locker_11_7") ~= nil
      and shop3:find("cell_locker_11_8") == nil and shop3:find("cell_locker_12_0") == nil
      and shop3:find("cell_hand_primary_0_0") == nil and PDTI.LOCKER.h == 20)
    T("  it says which rows", shop3:find("locker_rows").params.text == "Rows 1-8 of 20 (the mouse wheel scrolls)")
    -- 0.51.0: the locker scrolls.
    shop3:find("locker_down"):click()
    shop3 = named("pdti_shop")
    T("  Down: two rows on, drawn in the same place", shop3:find("cell_locker_0_0") == nil
      and shop3:find("cell_locker_0_9") ~= nil and shop3:find("cell_locker_0_10") == nil
      and shop3:find("cell_locker_0_2").params.position[2] == named("pdti_shop"):find("cell_locker_0_2").params.position[2]
      and shop3:find("locker_rows").params.text == "Rows 3-10 of 20 (the mouse wheel scrolls)")
    local first_y = shop3:find("cell_locker_0_2").params.position[2]
    for _ = 1, 10 do shop3:find("locker_down"):click(); shop3 = named("pdti_shop") end
    T("  not past the end", shop3:find("locker_rows").params.text == "Rows 13-20 of 20 (the mouse wheel scrolls)"
      and shop3:find("cell_locker_11_19") ~= nil and shop3:find("cell_locker_0_12").params.position[2] == first_y)
    shop3:find("locker_up"):click()
    shop3 = named("pdti_shop")
    T("  Up", shop3:find("locker_rows").params.text == "Rows 11-18 of 20 (the mouse wheel scrolls)")
    -- The mouse wheel over the locker.
    _G.Idstring = function(s) return s end
    local hit = PDTI._UIHit
    PDTI._UIHit = function() return { container = "locker", x = 0, y = 12 } end
    T("  the wheel up over it: two rows back, the press taken", PDTI._UIMousePressed("mouse wheel up", 1, 1) == false
      and named("pdti_shop"):find("locker_rows").params.text == "Rows 9-16 of 20 (the mouse wheel scrolls)")
    T("  the wheel down", PDTI._UIMousePressed("mouse wheel down", 1, 1) == false
      and named("pdti_shop"):find("locker_rows").params.text == "Rows 11-18 of 20 (the mouse wheel scrolls)")
    -- Dragging the pistol: the wheel scrolls, and the preview is under the mouse again.
    PDTI.UIDragStart("locker", 0, 0)
    PDTI._UIMousePressed("mouse wheel up", 1, 1)
    local tinted = 0
    for _, c in ipairs(named("pdti_shop").children) do tinted = tinted + #(c.rects or {}) end
    T("  while dragging: scrolled, the preview drawn again", PDTI.UIIsDragging()
      and named("pdti_shop"):find("locker_rows").params.text == "Rows 9-16 of 20 (the mouse wheel scrolls)" and tinted > 0, tinted)
    PDTI.UIResetInteraction()
    PDTI._UIMousePressed("mouse wheel down", 1, 1)
    PDTI._UIHit = function() return { container = "backpack", x = 0, y = 0 } end
    T("  not over the locker: left to the game", PDTI._UIMousePressed("mouse wheel up", 1, 1) == nil
      and named("pdti_shop"):find("locker_rows").params.text == "Rows 11-18 of 20 (the mouse wheel scrolls)")
    PDTI._UIHit = function() return "window" end
    T("  over no cell: left to the game", PDTI._UIMousePressed("mouse wheel down", 1, 1) == nil)
    PDTI._UIHit = hit
    _G.Idstring = nil
    T("  without the game's ids the wheel is no wheel", PDTI._UIMousePressed("mouse wheel up", 1, 1) ~= false)
    for _ = 1, 10 do PDTI.UILockerScroll(-2) end
    T("  not before the start", select(1, PDTI.UILockerScroll(-2)) == 0)
    shop3 = named("pdti_shop")
    PDTI.RedrawUI()
    shop3 = named("pdti_shop")
    T("  the bought pistol is in the locker, named", shop3:find("cell_locker_0_0").params.text:find("Pistol", 1, true) ~= nil,
      shop3:find("cell_locker_0_0").params.text)
    local function slot_text(s) return tostring(window():find("weapon_box_" .. s).params.text) end
    T("no primary owned: the free AMCAR is a real weapon in PRI; SEC is empty (the pistol is in the locker)",
      slot_text("primary"):find("PRI AMCAR", 1, true) ~= nil and PDTI.Armory.HandItem("primaries").data.free == true
      and slot_text("secondary"):find("SEC empty", 1, true) ~= nil, slot_text("primary") .. " / " .. slot_text("secondary"))
    -- The AMCAR dragged off PRI into the backpack, and back onto PRI.
    local amcar = PDTI.Armory.HandItem("primaries")
    local bx, by = PDTI.FindFreeSpace("backpack", amcar, false)
    PDTI.UIDragStart("hand_primary", 0, 0)
    PDTI.UIDragDrop({ container = "backpack", x = bx, y = by })
    PDTI.RedrawUI()
    T("PRI's AMCAR dragged into the backpack: it is there at its 4x2, PRI empty, no second one given",
      PDTI.FindItem("backpack", amcar.instance_id) ~= nil and PDTI.GetOccupancyMap("backpack").cells[by + 2][bx + 4]
      == amcar.instance_id and slot_text("primary"):find("PRI empty", 1, true) ~= nil and #PDTI.Armory.Weapons() == 2,
      slot_text("primary"))
    T("  both slots empty: no weapon in either",
      slot_text("primary"):find("no weapon", 1, true) ~= nil and slot_text("secondary"):find("no weapon", 1, true) ~= nil,
      slot_text("primary") .. " / " .. slot_text("secondary"))
    PDTI.UIDragStart("backpack", bx + 2, by + 1) -- grabbed by a middle cell
    PDTI.UIDragDrop({ container = "hand_primary", x = 0, y = 0 })
    PDTI.RedrawUI()
    T("  and from the backpack back onto PRI", PDTI.FindItem("hand_primary", amcar.instance_id) ~= nil
      and slot_text("primary"):find("PRI AMCAR", 1, true) ~= nil)
    -- Drag the pistol from the locker onto SEC.
    local function locker_pistol()
      for _, e in ipairs(PDTI.FindItems(function(c, it)
        return it.item_id == "weapon" and it.data.weapon_id == "pistol_a" end)) do return e end
    end
    local lp0 = locker_pistol()
    PDTI.UIDragStart("locker", lp0.item.x + 1, lp0.item.y) -- grabbed by its second cell
    local pv = PDTI.UIDragPreview("hand_primary", 0, 0)
    T("dragging the pistol over PRI: red (a secondary)", pv and pv.valid == false and pv.container == "hand_primary"
      and pv.w == 1 and pv.h == 1, pv and pv.reason)
    pv = PDTI.UIDragPreview("hand_secondary", 0, 0)
    T("  over SEC: green, the whole slot", pv and pv.valid == true and pv.x == 0 and pv.y == 0 and pv.w == 1 and pv.h == 1)
    PDTI._UIShowPreview({ container = "hand_secondary", x = 0, y = 0 })
    local sec_box = window():find("weapon_box_secondary")
    T("  the SEC box itself lights up green under the mouse", #(sec_box.rects or {}) == 1
      and sec_box.rects[1].params.color ~= nil and #(window():find("weapon_box_primary").rects or {}) == 0)
    PDTI.UIDragDrop({ container = "hand_secondary", x = 0, y = 0 })
    PDTI.RedrawUI()
    T("  dropped: the pistol is in SEC, shown there", locker_pistol().container == "hand_secondary"
      and slot_text("secondary"):find("Pistol A", 1, true) ~= nil and slot_text("secondary"):find("empty", 1, true) == nil,
      slot_text("secondary"))
    T("  the game's secondary is it now (the screen syncs as it redraws)",
      Global.blackmarket_manager.crafted_items.secondaries[1].weapon_id == "pistol_a"
      and Global.blackmarket_manager.crafted_items.primaries[1].weapon_id == "amcar")
    -- Off the slot into the backpack (its own size there), and back by clicks.
    PDTI.UIDragStart("hand_secondary", 0, 0)
    PDTI.UIDragDrop({ container = "backpack", x = 0, y = 0 })
    local bp = locker_pistol()
    T("dragged off SEC into the backpack: a 2x1 pistol there again", bp.container == "backpack"
      and PDTI.GetOccupancyMap("backpack").cells[1][2] == bp.item.instance_id)
    PDTI.RedrawUI()
    T("  SEC is empty: no weapon there (you own a secondary, so none is given)",
      slot_text("secondary"):find("SEC empty\nno weapon", 1, true) ~= nil and #PDTI.Armory.Weapons() == 2,
      slot_text("secondary"))
    window():find("cell_backpack_0_0"):click()
    window():find("weapon_box_secondary"):click()
    T("click it, click SEC: in the slot", locker_pistol().container == "hand_secondary")
    window():find("weapon_box_secondary"):click()
    window():find("weapon_box_primary"):click()
    T("  a secondary does not go onto PRI", locker_pistol().container == "hand_secondary")
    PDTI.UICancelHeld()
    local applied, real_apply = 0, PDTI.Armory.ApplyHands
    PDTI.Armory.ApplyHands = function() applied = applied + 1; return false end
    PDTI.RedrawUI()
    PDTI.Armory.ApplyHands = real_apply
    T("every redraw lets the weapons in hand follow the slots (a heist, the safehouse)", applied == 1)
    local saved_input = rawget(_G, "Input")
    _G.Input = { keyboard = function() return { down = function() return true end } end }
    _G.Idstring = _G.Idstring or function(v) return v end
    window():find("weapon_box_secondary"):click()
    _G.Input = saved_input
    T("Ctrl+click on SEC: back to the locker", locker_pistol().container == "locker"
      and PDTI.UIGetStatusText() == "Moved Pistol A to the locker", PDTI.UIGetStatusText())
    PDTI.UIQuickTransfer("locker", locker_pistol().item.instance_id)
    T("  Ctrl+click in the locker: onto SEC", locker_pistol().container == "hand_secondary"
      and PDTI.UIGetStatusText() == "Moved Pistol A to the secondary slot", PDTI.UIGetStatusText())
    PDTI.RedrawUI()
    local lp = layout_problems(named("pdti_shop"))
    local lpl = layout_problems(windows()[1])
    T("  the Locker tab and the left window: nothing overlaps (no price graph left from the market), they fit the screen",
      #lp == 0 and #lpl == 0 and windows()[1]:find("market_graph_title") == nil
      and named("pdti_shop").ph <= 720 and windows()[1].ph <= 720,
      table.concat(lp, "; ") .. table.concat(lpl, "; ") .. " " .. tostring(named("pdti_shop").ph))
    T("only documented MenuUI parameters used (locker)", #ENV.violations == 0, table.concat(ENV.violations, ","))
    named("pdti_shop"):find("shop_tab_bring"):click()
    PDTI.SetUIOpen(false)
    PDTI.OpenMarket()
    A.FactorRoll, A.StockRoll = real_fr, real_sr
    tweak_data.weapon = real_weapon
    for k, v in pairs(saved) do managers[k] = v end
    if not had_m then _G.managers = nil end
    for _, e in ipairs(PDTI.FindItems(function(_, it) return it.item_id == "weapon" end)) do
      PDTI.RemoveItem(e.container, e.item.instance_id)
    end
    Global.blackmarket_manager = had_bm
    if not had_global then _G.Global = nil end
  end

  named("pdti_shop"):find("market_close"):click()
  T("Close: the screen is closed", not PDTI.IsUIOpen() and not PDTI.IsMarketOpen())
  T("  and the controls are on again", ctl.on == true and PDTI._UIInputBlock() == nil)
  T("  closed: nothing is kept off", PDTI.UIKeepInputBlocked() == false)
  T("  the price list is gone", windows()[1]:find("market_prices") == nil)
  PDTI.SetUIOpen(true)
  T("the inventory after it is the inventory again", not PDTI.IsMarketOpen() and windows()[1].pw > 1
    and named("pdti_shop"):find("market_accept_1") == nil and named("pdti_shop"):find("shop_tab_bring") ~= nil)
  named("pdti_shop"):find("shop_tab_bring"):click()
  d.bags, d.pending = {}, {}
  M._State().active, M._State().high_rolls = {}, 0
  M.Today = real_today
  tweak_data.carry, tweak_data.money_manager = real_carry, real_mm
  if not had_td then _G.tweak_data = nil end
end

-- 0.29.1: the end screen's captured loot window.
do
  local Stash = PDTI.Stash
  PDTI.SetUIOpen(false)
  local d = Stash._Data()
  d.bags, d.pending = {}, {}
  for i = 1, 3 do
    d.pending[i] = { id = 200 + i, carry_id = "gold", quality = i == 1 and 3 or 1, mods = i == 1 and "padded" or "",
      value = 1000 * i }
  end
  local menus_before = #ENV.menus
  T("BeardLib still making the window: try again", PDTI.SetCaptureOpen(true) == "wait" and not PDTI.IsCaptureOpen())
  ENV.menus[#ENV.menus]:finish()
  T("the captured loot window opens", PDTI.SetCaptureOpen(true) == true and PDTI.IsCaptureOpen())
  local menu = ENV.menus[#ENV.menus]
  local win = menu.children[1]
  T("its own window, in the middle", #ENV.menus == menus_before + 1 and win.params.name == "pdti_capture"
    and win.params.position == "Center")
  T("enabled over the end screen", menu:Enabled())
  T("every bag has Stash and Sell", win:find("cap_keep_201") and win:find("cap_sell_202") and win:find("cap_keep_203"))
  T("and says what to do", win:find("cap_space").params.text:find("Decide for every bag", 1, true) ~= nil)
  T("no inventory screen behind it", PDTI.IsUIOpen() == false)
  win:find("cap_sell_201"):click()
  T("Sell: the bag is gone from the window", win:find("cap_sell_201") == nil and win:find("cap_keep_202") ~= nil)
  T("the inventory screen stays closed", PDTI.IsUIOpen() == false)
  for i = 1, 12 do d.bags[i] = { id = 300 + i, carry_id = "gold", quality = 1, mods = "", value = 1 } end
  win:find("cap_keep_202"):click()
  T("a full stash: the reason is shown in the window", win:find("cap_status") ~= nil
    and win:find("cap_status").params.text:find("full", 1, true) ~= nil)
  d.bags = {}
  win:find("cap_keep_all"):click()
  T("the last bags chosen: the window closes", PDTI.IsCaptureOpen() == false and not menu:Enabled()
    and #Stash.Pending() == 0)
  for i = 1, 40 do d.pending[i] = { id = 400 + i, carry_id = "gold", quality = 1, mods = "", value = 1 } end
  PDTI.SetCaptureOpen(true)
  T("40 bags: drawn smaller to fit the screen", win.ph <= 720, win.ph)
  win:find("cap_sell_all"):click()
  T("sell all now closes it", PDTI.IsCaptureOpen() == false and #Stash.Pending() == 0)
  T("its keys are gone once it is closed", #PDTI._CaptureTriggers() == 0)
  d.pending = { { id = 500, carry_id = "gold", quality = 1, mods = "", value = 1 },
    { id = 501, carry_id = "gold", quality = 1, mods = "", value = 1 } }
  PDTI.SetCaptureOpen(true)
  local function key(k) for _, t in ipairs(PDTI._CaptureTriggers()) do if t.key == k then return t end end end
  T("S and X work without the mouse", key("s") ~= nil and key("x") ~= nil)
  local stashed_before = #Stash.Bags()
  key("s").clbk()
  T("S: everything that fits is stashed, the window closes", #Stash.Pending() == 0
    and #Stash.Bags() == stashed_before + 2 and PDTI.IsCaptureOpen() == false, #Stash.Pending() .. "/" .. #Stash.Bags() .. "/" .. tostring(PDTI.IsCaptureOpen()))
  d.bags = {}
  for i = 1, 12 do d.bags[i] = { id = 600 + i, carry_id = "gold", quality = 1, mods = "", value = 1 } end
  d.pending = { { id = 700, carry_id = "gold", quality = 1, mods = "", value = 1 } }
  PDTI.SetCaptureOpen(true)
  key("s").clbk()
  T("S with a full stash: still open, the reason shown", PDTI.IsCaptureOpen() and #Stash.Pending() == 1)
  key("x").clbk()
  T("X: sold, closed", PDTI.IsCaptureOpen() == false and #Stash.Pending() == 0)
  T("only documented MenuUI parameters used (end screen)", #ENV.violations == 0, table.concat(ENV.violations, ","))
  d.bags, d.pending = {}, {}
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
