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
T("two windows, one at each edge", #windows() == 2 and windows()[1].params.position == "LeftCentery"
  and windows()[2].params.position == "RightCentery")
for _, w in ipairs(windows()) do
  T("window " .. w.params.name .. " resized to content", w.pw >= 250 and w.ph > 200, w.pw .. "x" .. w.ph)
end
T("the pockets, the rig and the loadout are on the left",
  windows()[1]:find("cell_pockets_0_0") and windows()[1]:find("cell_rig_0_0") and windows()[1]:find("loadout_none"))
T("the backpack and, in the menu, what you bring are on the right",
  windows()[2]:find("cell_backpack_0_0") and windows()[2]:find("bring_label") and windows()[2]:find("bring_plus_first_aid_kit")
  and windows()[2]:find("supplies_label") == nil)
do
  local kits = #PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" end)
  windows()[2]:find("bring_plus_first_aid_kit"):click()
  local after_plus = #PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" end)
  windows()[2]:find("bring_minus_first_aid_kit"):click()
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
-- The middle of a 1280x720 screen stays free: the two windows together
-- leave at least half of the width, and each fits the height.
T("the windows leave the middle of the screen free",
  windows()[1].pw + windows()[2].pw <= 640 and windows()[1].ph <= 620 and windows()[2].ph <= 620,
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
T("one spawn button per deployable (items without an effect are not offered)", supply_count() == defs and defs == 4, supply_count() .. " vs " .. defs)
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

local function mag_text()
  local out = {}
  for _, c in ipairs(window().children) do if c.params.name and c.params.name:find("^mag_line_") then out[#out + 1] = c.params.text end end
  return table.concat(out, "|")
end
window():find("btn_cancel"):click()
T("magazine panel says when there are none", mag_text():find("No magazines") ~= nil, mag_text())
PDTI.AddItemAuto("rig", "spare_magazine", 1,
  { queue_key = "RIFLE|wpn_mag_test", rounds = 30, capacity = 30, caliber = "RIFLE" })
PDTI.AddItemAuto("rig", "spare_magazine", 1,
  { queue_key = "RIFLE|wpn_mag_test", rounds = 12, capacity = 30, caliber = "RIFLE" })
window():find("btn_cancel"):click()
T("magazine panel shows the magazines that are to hand",
  mag_text():find("RIFLE") and mag_text():find("30/12"), mag_text())

-- 9c. the health window: every body part, its colour and its HP
dofile(ROOT .. "lua/body.lua")
local Body = PDTI.Body
Body.OnHeistStart()
PDTI.RedrawUI()
local function hwin()
  for _, w in ipairs(windows()) do if w.params.name == "pdti_health" then return w end end
end
local function part(id) return hwin() and hwin():find("health_part_" .. id) end
T("in a heist a third window shows the health", #windows() == 3 and hwin() ~= nil
  and hwin().params.position == "CenterBottom")
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
      elseif #lp3 > 0 or l.pw + r.pw > 640 or l.ph > 620 or r.ph > 620 then
        bad[#bad + 1] = rig .. "+" .. pack .. ": " .. l.pw .. "x" .. l.ph .. " " .. r.pw .. "x" .. r.ph
          .. " " .. table.concat(lp3, "; "):sub(1, 200)
      end
    end
  end
  T("layout clean for all nine rig and backpack combinations", #bad == 0, table.concat(bad, " | "))
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

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
