-- 0.12.0: drag and drop, the order magazines are filled in, and the weight
-- of ammunition.
--   luajit tests/drag_tests.lua
local script = arg and arg[0] or "tests/drag_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_drag") .. "/")
_G.ModPath = ROOT
ENV.install_game()
ENV.load_mod(ROOT, false)
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end
local Ammo = PDTI.Ammo
Ammo.InstallHooks()

local function fresh()
  PDTI.Reset()
  Ammo.Reset()
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon("test_rifle")
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  return wep, Ammo.Identify(wep).key
end
local function set_rounds(key, list)
  for i, m in ipairs(Ammo.Magazines(key)) do Ammo.SetMagazineRounds(m.container, m.instance_id, list[i]) end
end
local function rounds_by_id(key)
  local out = {}
  for _, m in ipairs(Ammo.Magazines(key)) do out[m.instance_id] = m.rounds end
  return out
end

------------------------------------------------ filling the magazines

local wep, key = fresh()
local ids = {}
for i, m in ipairs(Ammo.Magazines(key)) do ids[i] = m.instance_id end
set_rounds(key, { 10, 25, 5 })
local start = rounds_by_id(key)
-- the 25 is the closest to full
local fullest, middle, emptiest
for id, r in pairs(start) do
  if r == 25 then fullest = id elseif r == 10 then middle = id else emptiest = id end
end
Ammo.AddLooseKey(key, 30, Ammo.Identify(wep))
Ammo.StartJob(wep)
Ammo.Tick(1)
local r = rounds_by_id(key)
T("the first round goes into the magazine closest to full", r[fullest] == 26 and r[middle] == 10 and r[emptiest] == 5,
  r[fullest] .. "/" .. r[middle] .. "/" .. r[emptiest])
for _ = 1, 4 do Ammo.Tick(1) end
r = rounds_by_id(key)
T("it is filled up first", r[fullest] == 30 and r[middle] == 10 and r[emptiest] == 5)
Ammo.Tick(1)
r = rounds_by_id(key)
T("then the next closest to full", r[middle] == 11 and r[emptiest] == 5, r[middle] .. "/" .. r[emptiest])
Ammo.StopJob()

wep, key = fresh()
set_rounds(key, { 10, 25, 5 })
start = rounds_by_id(key)
for id, v in pairs(start) do
  if v == 25 then fullest = id elseif v == 10 then middle = id else emptiest = id end
end
Ammo.AddLooseKey(key, 30, Ammo.Identify(wep))
Ammo.FillMagazines(wep, 30)
r = rounds_by_id(key)
T("packing many at once: one magazine after the other (30, 30, 10)",
  r[fullest] == 30 and r[middle] == 30 and r[emptiest] == 10, r[fullest] .. "/" .. r[middle] .. "/" .. r[emptiest])

------------------------------------------------------------ the weight

do
  wep, key = fresh()
  local m = Ammo.Magazines(key)[1]
  local item = PDTI.FindItem(m.container, m.instance_id)
  local full = PDTI.ItemWeight(item)
  T("a full 30-round magazine: the magazine and 30 rounds", near(full, PDTI.MagazineEmptyWeight(30) + 30 * PDTI.RoundWeight(nil)), full)
  local rig_before = PDTI.GetContainerInfo(m.container).weight
  Ammo.SetMagazineRounds(m.container, m.instance_id, 0)
  local empty = PDTI.ItemWeight(PDTI.FindItem(m.container, m.instance_id))
  T("an empty magazine is lighter", empty < full and near(empty, PDTI.MagazineEmptyWeight(30)), empty)
  T("the rig gets lighter when the magazine is emptied", PDTI.GetContainerInfo(m.container).weight < rig_before)
  T("the load counts it", (function()
    local a = PDTI.Carry.LoadWeight()
    Ammo.SetMagazineRounds(m.container, m.instance_id, 30)
    return PDTI.Carry.LoadWeight() > a
  end)())
  T("a bigger magazine weighs more empty", PDTI.MagazineEmptyWeight(100) > PDTI.MagazineEmptyWeight(30))
  T("a shotgun shell weighs more than a pistol round", PDTI.RoundWeight("shotgun") > PDTI.RoundWeight("pistol"))
  PDTI.Reset()
  PDTI.AddItemAuto("backpack", "loose_ammo", 100, { queue_key = "S", mag_class = "shotgun" }, true)
  PDTI.AddItemAuto("backpack", "loose_ammo", 100, { queue_key = "P", mag_class = "pistol" }, true)
  local items = PDTI.GetContainer("backpack").items
  T("loose rounds weigh by their weapon type",
    near(PDTI.ItemWeight(items[1]), 100 * PDTI.RoundWeight("shotgun")) and near(PDTI.ItemWeight(items[2]), 100 * PDTI.RoundWeight("pistol")))
  T("the backpack weighs both", near(PDTI.GetContainerInfo("backpack").weight, 100 * (PDTI.RoundWeight("shotgun") + PDTI.RoundWeight("pistol"))))
  T("the loose rounds of a weapon know its type", (function()
    tweak_data.weapon.test_pump2 = { AMMO_MAX = 48, categories = { "shotgun" } }
    local pump = ENV.make_weapon("test_pump2", { "wpn_mag_test" }, 6, { _use_shotgun_reload = true })
    return Ammo.Identify(pump).mag_class == "shotgun"
  end)())
end

------------------------------------------------------- drag and drop

ENV.install_menuui(false)
dofile(ROOT .. "lua/ui_beardlib.lua")
PDTI.Reset()
PDTI.SetEquipment("backpack", "large_backpack")
local _, bag = PDTI.AddItemAuto("backpack", "doctor_bag", 1, nil, true) -- 3x2 at 0,0
PDTI.SetUIOpen(true)
local menu = ENV.menus[#ENV.menus]
T("the screen takes the mouse first", type(menu.params.pre_mouse_press) == "function"
  and type(menu.params.pre_mouse_move) == "function" and type(menu.params.pre_mouse_release) == "function")

-- The mouse: the test says what is under it.
local under = "outside"
PDTI._UIHit = function() return under end
local function cell(c, x, y) return { container = c, x = x, y = y } end
local function press(target) under = target; return menu.params.pre_mouse_press("0", 1, 1) end
local function move(target) under = target; return menu.params.pre_mouse_move(1, 1) end
local function release(target) under = target; return menu.params.pre_mouse_release("0", 1, 1) end
local function at(id) local i = PDTI.FindItem("backpack", id) or PDTI.FindItem("rig", id); return i and (i.x .. "," .. i.y) end
local function preview_cells()
  local n = 0
  for _, w in ipairs(menu.children) do for _, c in ipairs(w.children) do n = n + #(c.rects or {}) end end
  return n
end

T("a press on an item grabs it (the cell's click is swallowed)", press(cell("backpack", 1, 1)) == false and PDTI.UIIsDragging())
move(cell("backpack", 2, 3))
local p = PDTI.UIDragPreview("backpack", 2, 3)
T("the preview: grabbed by its cell 1,1, so it starts at 1,2", p.x == 1 and p.y == 2 and p.w == 3 and p.h == 2, p.x .. "," .. p.y)
T("it fits there", p.valid == true)
T("the six cells it would take are tinted", preview_cells() == 6, preview_cells())
move(cell("backpack", 5, 4))
p = PDTI.UIDragPreview("backpack", 5, 4)
T("over the edge it does not fit", p.valid == false)
T("the cells inside the grid are still shown (2x2 of the 3x2)", preview_cells() == 4, preview_cells())
release(cell("backpack", 2, 3))
T("let go: it goes there", at(bag.instance_id) == "1,2", at(bag.instance_id))
T("nothing is held after a drop", not PDTI.UIIsDragging() and PDTI.UIGetHeld() == nil)
T("the preview is gone", preview_cells() == 0)

press(cell("backpack", 1, 2))
release(cell("backpack", 5, 4))
T("let go where it does not fit: it stays", at(bag.instance_id) == "1,2")
press(cell("backpack", 1, 2))
release("window")
T("let go in the window, not on a cell: it stays", at(bag.instance_id) == "1,2" and PDTI.UIGetHeld() == nil)
press(cell("backpack", 1, 2))
release(cell("backpack", 1, 2))
T("a click without moving changes nothing", at(bag.instance_id) == "1,2")

-- turning while dragging
press(cell("backpack", 3, 3)) -- the right end of the bag
PDTI.UIRotateHeld()
p = PDTI.UIDragPreview("backpack", 4, 3)
-- grabbed 2 right, 1 down; turned that is 1 right, 2 down
T("turned: 2 wide, 3 tall, the grab point turns with it", p.w == 2 and p.h == 3 and p.x == 3 and p.y == 1 and p.valid,
  p.x .. "," .. p.y)
release(cell("backpack", 4, 3))
local item = PDTI.FindItem("backpack", bag.instance_id)
T("and it is placed turned", item.rotated == true)

-- to another container
local _, kit = PDTI.AddItemAuto("backpack", "first_aid_kit", 1, nil, true)
press(cell("backpack", kit.x, kit.y))
release(cell("rig", 0, 0))
T("dragged into the rig", PDTI.FindItem("rig", kit.instance_id) ~= nil)

-- out of the inventory
press(cell("rig", 0, 0))
release("outside")
T("let go outside the inventory: discarded", PDTI.FindItem("rig", kit.instance_id) == nil)

local dropped = 0
PDTI.Loot.DropItem = function(c, id) dropped = dropped + 1; PDTI.RemoveItem(c, id); return true end
local _, lb = PDTI.AddItemAuto("backpack", "loot_bag", 1, { carry_id = "gold" }, true)
press(cell("backpack", lb.x, lb.y))
release("outside")
T("a loot bag let go outside is thrown", dropped == 1)

-- Ctrl: the quick transfer, no drag
_G.Input = { keyboard = function() return { down = function() return true end } end }
_G.Idstring = function(s) return s end
local _, band = PDTI.AddItemAuto("backpack", "bandage", 1, nil, true)
press(cell("backpack", band.x, band.y))
T("Ctrl and a press: straight to the pockets", PDTI.FindItem("pockets", band.instance_id) ~= nil and not PDTI.UIIsDragging())
_G.Input = nil
T("other mouse buttons are left alone", menu.params.pre_mouse_press("1", 1, 1) == nil)
_G.Idstring = nil
T("a press outside the cells is left to the buttons", press("window") == nil)
T("moving without dragging is left alone", move(cell("backpack", 0, 0)) == nil)
T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
T("the state stays valid", PDTI.ValidateState() == true)
PDTI.SetUIOpen(false)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
