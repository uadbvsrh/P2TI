-- 0.40.0: pictures of weapons and parts (ui_pictures.lua, drawn by
-- ui_beardlib.lua): the game's own icons in the grid's cells, in a weapon's
-- view, its slot boxes and the market. A texture is asked of the game once
-- and drawn when it came; the screen gives them back when it closes.
--   luajit tests/pictures_tests.lua
local script = arg and arg[0] or "tests/pictures_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_pictures") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

-- The game's weapons and parts.
local W = tweak_data.weapon
W.amcar = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AMCAR Carbine", CLIP_AMMO_MAX = 20 }
W.glock_17 = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "Chimano 88", CLIP_AMMO_MAX = 17 }
local FACTORY = { amcar = "wpn_fps_ass_amcar", glock_17 = "wpn_fps_pis_g17" }
local PRICE = { amcar = 10000, glock_17 = 5000 }
local FP = tweak_data.weapon.factory.parts
local MODS = {}
tweak_data.blackmarket = tweak_data.blackmarket or {}
tweak_data.blackmarket.weapon_mods = MODS
local function part(id, ptype) FP[id] = { type = ptype, name_id = id }; MODS[id] = { pc = 1 } end
for _, p in ipairs({ { "amcar_body", "lower_reciever" }, { "amcar_barrel", "barrel" }, { "amcar_stock", "stock" },
  { "amcar_irons", "sight" }, { "amcar_mag", "magazine" }, { "g17_slide", "slide" }, { "g17_mag", "magazine" },
  { "s_red", "sight" }, { "b_supp", "barrel_ext" }, { "gd_laser", "gadget" } }) do
  part(p[1], p[2])
end
MODS.s_red.texture_bundle_folder = "gage_pack" -- (a DLC's part)
FP.gd_laser.name_id = "Laser Module XL" -- (long: its box's text has to make room)
local PARTS_BY = {
  wpn_fps_ass_amcar = {
    lower_reciever = { "amcar_body" }, barrel = { "amcar_barrel" }, stock = { "amcar_stock" },
    sight = { "amcar_irons", "s_red" }, barrel_ext = { "b_supp" }, gadget = { "gd_laser" }, magazine = { "amcar_mag" }
  },
  wpn_fps_pis_g17 = { slide = { "g17_slide" }, magazine = { "g17_mag" }, barrel_ext = { "b_supp" } }
}
local DEFAULT = {
  wpn_fps_ass_amcar = { "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" },
  wpn_fps_pis_g17 = { "g17_slide", "g17_mag" }
}
local function copy(t) local o = {}; for i, v in ipairs(t or {}) do o[i] = v end; return o end
local function has(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
managers.weapon_factory = {
  get_factory_id_by_weapon_id = function(_, id) return FACTORY[id] end,
  get_default_blueprint_by_factory_id = function(_, f) return copy(DEFAULT[f]) end,
  get_parts_from_weapon_id = function(_, id) return PARTS_BY[FACTORY[id]] end,
  can_add_part = function() return nil end,
  change_part_blueprint_only = function(_, f, p, bp, remove)
    local t = FP[p] and FP[p].type
    if not t then return false end
    if remove then
      for i, x in ipairs(bp) do if x == p then table.remove(bp, i) break end end
      return false
    end
    if not has(PARTS_BY[f] and PARTS_BY[f][t], p) then return false end
    for i, x in ipairs(bp) do if FP[x] and FP[x].type == t then table.remove(bp, i) break end end
    bp[#bp + 1] = p
    return true
  end
}

ENV.load_mod(ROOT, true)
local A, P, Pic = PDTI.Armory, PDTI.Parts, PDTI.Pictures

-- The game's pictures: the paths it has, their sizes.
local WEP = "guis/textures/pd2/blackmarket/icons/weapons/"
local MOD = "guis/textures/pd2/blackmarket/icons/mods/"
local DLC_RED = "guis/dlcs/gage_pack/textures/pd2/blackmarket/icons/mods/s_red"
-- (No Chimano; the AMCAR's own barrel has one, but a standard part shows none.)
local TEX = { [WEP .. "amcar"] = true, [MOD .. "gd_laser"] = true, [DLC_RED] = true, [MOD .. "amcar_barrel"] = true }
ENV.texture_sizes[WEP .. "amcar"] = { 512, 256 }
ENV.texture_sizes[MOD .. "gd_laser"] = { 256, 128 }
ENV.texture_sizes[DLC_RED] = { 256, 128 }
ENV.texture_sizes[MOD .. "amcar_barrel"] = { 256, 128 }
local has_calls = 0
_G.Idstring = function(v) return v end
local function game_db()
  return { has = function(_, kind, path) has_calls = has_calls + 1; return kind == "texture" and TEX[path] == true end }
end
_G.DB = game_db()

managers.money = {
  total = function() return 1000000 end,
  deduct_from_total = function() end,
  add_to_total = function() end,
  add_to_spending = function() end,
  get_payouts = function() return {} end,
  get_weapon_price_modified = function(_, id) return PRICE[id] end,
  get_weapon_modify_price = function() return 1000 end
}
managers.blackmarket = {
  weapon_unlocked = function() return true end,
  _calculate_weapon_concealment = function() return 30 end,
  get_weapon_icon_path = function(_, id) return WEP .. id, nil end
}
managers.localization = { text = function(_, id) return id end }
managers.dlc = { is_dlc_unlocked = function() return false end }
_G.Global = _G.Global or {}
Global.blackmarket_manager = { crafted_items = { primaries = {}, secondaries = {} } }
ENV.game.unit = nil -- the menu: no player
PDTI.Market.Today = function() return "2026-11-18" end
A.FactorRoll = function() return 0.5 end
A.StockRoll = function() return 0.99 end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((tonumber(a) or 1e9) - (tonumber(b) or -1e9)) < 0.01 end

-- The game's texture loader (menu_component): it loads a texture when the
-- test says (arrive), or at once (instant: the game had it).
local requests, released, pending = {}, {}, {}
local instant = false
local function install_loader()
  managers.menu_component = {
    request_texture = function(_, path, clbk)
      requests[#requests + 1] = path
      if instant then clbk(path) else pending[#pending + 1] = { path = path, clbk = clbk } end
      return #requests
    end,
    unretrieve_texture = function(_, path, index) released[#released + 1] = path .. "#" .. tostring(index) end
  }
end
local function arrive()
  local list = pending
  pending = {}
  for _, p in ipairs(list) do p.clbk(p.path) end
  return #list
end
local function fresh_loader()
  Pic._Reset()
  requests, released, pending = {}, {}, {}
  instant = false
  install_loader()
end
local function count_logs(text)
  local n = 0
  for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then n = n + 1 end end
  return n
end

------------------------------------------------------------------ the paths

Pic._Reset()
managers.menu_component = nil
T("a weapon's picture: the game's own path", Pic.WeaponPath("amcar") == WEP .. "amcar", Pic.WeaponPath("amcar"))
local calls = has_calls
Pic.WeaponPath("amcar")
T("  looked up once", has_calls == calls)
T("a weapon the game has no picture for: none", Pic.WeaponPath("glock_17") == nil)
calls = has_calls
Pic.WeaponPath("glock_17")
T("  not looked up again", has_calls == calls)
T("  said once in the log, with the path tried", count_logs("no picture for weapon glock_17 at " .. WEP .. "glock_17") == 1)
T("a part's picture: from its DLC's folder", Pic.PartPath("s_red") == DLC_RED, Pic.PartPath("s_red"))
T("  or the game's own", Pic.PartPath("gd_laser") == MOD .. "gd_laser", Pic.PartPath("gd_laser"))
T("a part with none (or unknown): none", Pic.PartPath("b_supp") == nil and Pic.PartPath("zz_nothing") == nil)
calls = has_calls
Pic.PartPath("zz_nothing")
T("  not looked up again; said once", has_calls == calls and count_logs("no picture for part zz_nothing at " .. MOD .. "zz_nothing") == 1)
T("no id: none", Pic.WeaponPath(nil) == nil and Pic.PartPath(5) == nil)
local wpn_item = { item_id = "weapon", data = { weapon_id = "amcar" } }
local part_item = { item_id = "weapon_part", data = { part_id = "gd_laser" } }
T("an item's picture: a weapon's, a part's", Pic.ItemPath(wpn_item) == WEP .. "amcar" and Pic.ItemPath(part_item) == MOD .. "gd_laser")
T("  anything else has none", Pic.ItemPath({ item_id = "bandage", data = {} }) == nil and Pic.ItemPath({ item_id = "weapon" }) == nil
  and Pic.ItemPath(nil) == nil)
T("pictures are on by default", PDTI.Ammo.settings.item_pictures == true and Pic.Enabled() == true)
PDTI.Ammo.settings.item_pictures = false
T("the setting off: no pictures", Pic.Enabled() == false and Pic.ItemPath(wpn_item) == nil)
PDTI.Ammo.settings.item_pictures = true
_G.DB = nil
Pic._Reset()
T("without the game's files (no DB): none, no error", Pic.WeaponPath("amcar") == nil)
_G.DB = game_db()
Pic._Reset()
local real_icon = managers.blackmarket.get_weapon_icon_path
managers.blackmarket.get_weapon_icon_path = function() error("broken") end
T("the game's function failing: none, no error", Pic.WeaponPath("amcar") == nil)
managers.blackmarket.get_weapon_icon_path = real_icon
Pic._Reset()

---------------------------------------------------------------- the loading

local P1, P2, P3 = WEP .. "amcar", MOD .. "gd_laser", DLC_RED
managers.menu_component = nil
T("without the game's loader: drawn at once", Pic.Ready(P1) == true)
fresh_loader()
T("asked the first time: the game loads it, not drawn yet", Pic.Ready(P1) == false and #requests == 1)
T("  asked again meanwhile: asked of the game once", Pic.Ready(P1) == false and #requests == 1)
T("  it came: drawn", arrive() == 1 and Pic.Ready(P1) == true and #requests == 1)
instant = true
T("one the game already had (it comes at once): drawn at once", Pic.Ready(P2) == true and #requests == 2)
instant = false
managers.menu_component.request_texture = function() error("broken") end
T("the loader failing: drawn at once", Pic.Ready(P3) == true)
install_loader()
T("no path: nothing", Pic.Ready(nil) == false)
T("given back: each texture asked for, with its index", Pic.ReleaseAll() == 2 and table.concat(released, ",")
  == P1 .. "#1," .. P2 .. "#2", table.concat(released, ","))
T("  asked again after", Pic.Ready(P1) == false and #requests == 3)
fresh_loader()

--------------------------------------------------------------- the geometry

local CW, CH, G = 36, 32, 2
local function inside(s)
  return s.x >= -0.01 and s.y >= -0.01 and s.x + s.w <= CW - G + 0.01 and s.y + s.h <= CH - G + 0.01
end
local rifle = Pic.Slices(512, 256, 4, 2, CW, CH, G, false, 2)
T("a 4x2 rifle: a piece in each of its 8 cells", #rifle == 8, #rifle)
local all_in, in_tex, ratio = true, true, true
for _, s in ipairs(rifle) do
  if not inside(s) then all_in = false end
  local r = s.rect
  if r[1] < -0.01 or r[2] < -0.01 or r[1] + r[3] > 512.01 or r[2] + r[4] > 256.01 then in_tex = false end
  if not near(r[3] / s.w, r[4] / s.h) then ratio = false end
end
T("  each inside its cell", all_in)
T("  and inside the picture", in_tex)
T("  its shape kept (the same scale both ways)", ratio)
local by = {}
for _, s in ipairs(rifle) do by[s.cx .. "_" .. s.cy] = s end
-- 142 x 62 less 2 each side: 138 x 58; 512x256 shown 116 x 58, from x 13.
T("  centred: the same room left and right", near(by["0_0"].x, 13) and near(3 * CW + by["3_0"].x + by["3_0"].w, 4 * CW - G - 13),
  by["0_0"].x)
T("  the pieces follow on (only the gaps between cells are cut out)", near(by["1_0"].rect[1],
  by["0_0"].rect[1] + by["0_0"].rect[3] + G * 512 / 116) and near(by["0_1"].rect[2], by["0_0"].rect[2] + by["0_0"].rect[4] + G * 512 / 116))
T("  from the picture's left to its right", near(by["0_0"].rect[1], 0) and near(by["3_1"].rect[1] + by["3_1"].rect[3], 512)
  and near(by["3_1"].rect[2] + by["3_1"].rect[4], 256))
T("  not turned", by["0_0"].rotation == 0)
local turned = Pic.Slices(512, 256, 2, 4, CW, CH, G, true, 2)
local same, centre = true, true
for _, s in ipairs(turned) do
  if s.rotation ~= 90 or s.rect ~= nil or not near(s.w, turned[1].w) or not near(s.h, turned[1].h) then same = false end
  -- (Its centre, in the item: the item's centre, 70 x 126 / 2.)
  if not near(s.cx * CW + s.x + s.w / 2, 35) or not near(s.cy * CH + s.y + s.h / 2, 63) then centre = false end
end
T("a turned rifle (2x4): each of its 8 cells has the whole picture, turned", #turned == 8 and same, #turned)
T("  each centred on the item's centre (whichever way the game turns it, they meet)", centre)
T("  the picture's unturned size, its shape kept: long side along the item", near(turned[1].w, 2 * turned[1].h)
  and turned[1].w <= 4 * CH - G - 4 + 0.01 and turned[1].h <= 2 * CW - G - 4 + 0.01, turned[1].w .. "x" .. turned[1].h)
local one = Pic.Slices(512, 256, 1, 1, 34, 30, 0, false, 0)
T("one cell: the whole picture in it", #one == 1 and near(one[1].rect[1], 0) and near(one[1].rect[3], 512)
  and near(one[1].rect[4], 256) and near(one[1].w, 34) and near(one[1].h, 17) and near(one[1].y, 6.5))
local square = Pic.Slices(256, 256, 4, 1, CW, CH, G, false, 2)
T("a square picture on a 4x1 item: only the two middle cells it reaches", #square == 2 and square[1].cx == 1
  and square[2].cx == 2 and square[1].w > 0.5 and square[2].w > 0.5, #square)
T("no picture size: nothing", #Pic.Slices(0, 256, 2, 2, CW, CH, G, false, 2) == 0 and #Pic.Slices(512, 256, 0, 1, CW, CH, G) == 0)

----------------------------------------------------------------- the screen

local function fresh()
  managers.player, managers.job = nil, nil
  os.remove(TMP .. "pdti_armory.json")
  A.Reset()
  PDTI.Reset()
  PDTI.session_only = false
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetEquipment("rig", "general_rig")
  A.IssueFree() -- the AMCAR in PRI, the Chimano in SEC
  return A.HandItem("primaries").data
end
local function weapon(uid)
  for _, w in ipairs(A.Weapons()) do if w.data.uid == uid then return w.container, w.instance_id, w.data end end
end
local function part_cell(part_id)
  local e = PDTI.FindItems(function(_, it) return it.item_id == P.ITEM_ID and it.data.part_id == part_id end)[1]
  return e.container, e.item
end

local pri = fresh()
P.Buy("amcar", "gd_laser")
do
  local pc, pit = part_cell("gd_laser")
  local wc, wid = weapon(pri.uid)
  P.Fit(pc, pit.instance_id, wc, wid) -- (a laser of yours on the AMCAR in PRI)
end
P.Buy("amcar", "s_red")
A.Buy("amcar")
local locker_amcar
for _, w in ipairs(A.Weapons()) do if w.container == "locker" then locker_amcar = w end end
local _, bandage = PDTI.AddItemAuto("pockets", "bandage", 1, nil, true)
fresh_loader()
ENV.install_menuui(false)
-- (MenuUI is made when the screen first opens.)
local function menu() return ENV.menus[#ENV.menus] end
local function windows() return menu().children end
local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
local function find(name)
  for _, w in ipairs(windows()) do
    local c = w:find(name)
    if c then return c end
  end
end
local function pics(item)
  local out = {}
  for _, b in ipairs(item and item.bitmaps or {}) do if b.params.name == "pdti_pic" then out[#out + 1] = b end end
  return out
end
local function cell(c, x, y) return find(string.format("cell_%s_%d_%d", c, x, y)) end
local function cells_of(c, it)
  local w, h = PDTI.ItemSize(it, it.rotated == true, c)
  local out = {}
  for y = it.y, it.y + h - 1 do for x = it.x, it.x + w - 1 do out[#out + 1] = cell(c, x, y) end end
  return out
end
-- Every picture on the screen.
local function all_pics()
  local n = 0
  for _, w in ipairs(windows()) do
    for _, c in ipairs(w.children) do n = n + #pics(c) end
  end
  return n
end
local function updates() return #(menu().next_update or {}) end
local function shift_click(name)
  local real_input = rawget(_G, "Input")
  _G.Input = { keyboard = function() return { down = function(_, k) return k == "left shift" end } end }
  local c = find(name)
  if c then c:click() end
  _G.Input = real_input
  return c ~= nil
end
local function right_press(target)
  local saved_hit = PDTI._UIHit
  PDTI._UIHit = function() return target end
  local r = menu().params.pre_mouse_press("1", 1, 1)
  PDTI._UIHit = saved_hit
  return r
end

T("(the screen opens in the menu)", PDTI.ToggleUI() == true)
named("pdti_shop"):find("shop_tab_locker"):click()
local lit = PDTI.FindItem("locker", locker_amcar.instance_id)
local lcells = cells_of("locker", lit)
T("the pictures asked of the game: not drawn before they come (the old look)", #requests >= 1 and #pics(lcells[1]) == 0
  and lcells[1].params.text_align == "center", #requests)
local before = updates()
local came = arrive()
T("  they came: one redraw on the next update, for all of them", came >= 2 and updates() == before + 1, came .. " " .. updates())
menu():update()
lcells = cells_of("locker", lit)
local whole, right_tex, layered = true, true, true
for _, c in ipairs(lcells) do
  local p = pics(c)
  if #p ~= 1 then whole = false end
  if p[1] and p[1].params.texture ~= WEP .. "amcar" then right_tex = false end
  if p[1] and (p[1].params.layer ~= 3 or c.title.layer ~= 5) then layered = false end
end
T("an AMCAR in the locker: its picture across all its " .. #lcells .. " cells", #lcells >= 2 and whole, #lcells)
T("  the weapon's own picture", right_tex)
T("  over the cell's colour, under its text", layered)
T("  its name in the top-left corner", lcells[1].params.text_align == "left" and lcells[1].params.text_vertical == "top"
  and tostring(lcells[1].params.text):find("AMCAR", 1, true) ~= nil, lcells[1].params.text)
-- The longest line of a box's text, at its font, fits left of its picture.
local function clear_of(box, pic)
  local longest = 0
  for l in (tostring(box.params.text) .. "\n"):gmatch("(.-)\n") do longest = math.max(longest, #l) end
  return longest * box.params.font_size * 0.55 <= pic.params.x - 4, longest .. "*" .. box.params.font_size
end
local pbox = find("weapon_box_primary")
local pp = pics(pbox)[1]
-- (The box is 72 x 30, its name and weight fill it: the picture goes behind.)
T("the AMCAR in PRI: its whole picture in its box, centred", pp ~= nil and #pics(pbox) == 1
  and near(pp.params.texture_rect[1], 0) and near(pp.params.texture_rect[3], 512) and near(pp.params.texture_rect[4], 256)
  and pp.params.rotation == nil and near(pp.params.w, 52) and near(pp.params.h, 26)
  and near(pp.params.x, (pbox.pw - 52) / 2) and near(pp.params.y, 2),
  pp and (pp.params.x .. "," .. pp.params.y .. " " .. pp.params.w .. "x" .. pp.params.h .. " / " .. pbox.pw))
T("  faint, under its name and weight (in the middle, as before)", pp ~= nil and pp.params.alpha < 1
  and pbox.title.layer > pp.params.layer and pbox.params.text_align == "center"
  and tostring(pbox.params.text):find("AMCAR", 1, true) ~= nil, pbox.params.text)
T("the windows' own panels: no picture left (the size is read and the bitmap removed)", (function()
  for _, w in ipairs(windows()) do if #(w.bitmaps or {}) > 0 then return false end end
  return true
end)())
local sbox = find("weapon_box_secondary")
T("the Chimano in SEC (no picture in the game): the old look", sbox ~= nil and #pics(sbox) == 0 and sbox.params.text_align == "center")
local bcell = cell("pockets", bandage.x, bandage.y)
T("a bandage: no picture, its name in the middle", bcell ~= nil and #pics(bcell) == 0 and bcell.params.text_align == "center"
  and bcell.title.layer == 3)
local rc, rit = part_cell("s_red")
local rcells = cells_of(rc, rit)
T("a part in the locker: its own picture (a DLC's)", #rcells >= 1 and #pics(rcells[1]) == 1
  and pics(rcells[1])[1].params.texture == DLC_RED and rcells[1].params.text_align == "left")

-- A part held over the AMCAR: the green/red tint still above the picture.
PDTI.UIDragStart(rc, rit.x, rit.y)
PDTI._UIShowPreview({ container = "locker", x = lit.x, y = lit.y })
lcells = cells_of("locker", lit)
local tint = lcells[1].rects and lcells[1].rects[#lcells[1].rects]
T("a part over it: the drop preview above the picture", tint ~= nil and tint.params.name == "pdti_preview"
  and tint.params.layer > pics(lcells[1])[1].params.layer)
local cb = updates()
PDTI.Pictures.Ready("guis/some/other") -- (a texture asked for while dragging...)
arrive()
T("  a picture that comes while dragging waits for the drop (no redraw)", updates() == cb + 1 and (function()
  local first = lcells[1]
  menu():update()
  return cells_of("locker", lit)[1] == first
end)())
PDTI.UICancelHeld()
PDTI.RedrawUI()

-- Each texture's size is read once (a hidden bitmap, removed).
local probes = ENV.probes
PDTI.RedrawUI()
PDTI.RedrawUI()
T("each picture's size read once, not at every redraw", ENV.probes == probes and probes >= 2, probes .. " " .. ENV.probes)
-- Textures the game already had come at once, while the screen is drawn:
-- drawn then, with no redraw more.
do
  local before_plain = updates()
  PDTI.RedrawUI()
  local plain = updates() - before_plain
  Pic._Reset()
  instant = true
  local before_instant = updates()
  PDTI.RedrawUI()
  instant = false
  T("pictures the game already had: drawn at once, no redraw more for them", updates() - before_instant == plain
    and #pics(cells_of("locker", lit)[1]) == 1, plain .. " " .. (updates() - before_instant))
end
-- MenuUI dropped the redraw it was to do (closed meanwhile): the next
-- pictures still bring one.
do
  Pic.Ready("guis/one/more")
  arrive() -- (a redraw waits for the next update)
  PDTI.SetUIOpen(false)
  requests, released = {}, {} -- (counted from here)
  menu().next_update = {} -- (dropped)
  PDTI.ToggleUI()
  named("pdti_shop"):find("shop_tab_locker"):click()
  local before_drop = updates()
  arrive()
  T("a redraw dropped while closed: the pictures after it still bring one", updates() > before_drop, updates() - before_drop)
  menu():update()
end

-- Turned in the locker: the picture turns with it.
do
  local spot
  for y = 0, 30 do
    for x = 0, 12 do
      if not spot and PDTI.CanPlace("locker", lit, x, y, true) then spot = { x, y } end
    end
  end
  local moved = spot and PDTI.MoveItem("locker", lit.instance_id, "locker", spot[1], spot[2], true)
  PDTI.RedrawUI()
  local t = PDTI.FindItem("locker", lit.instance_id)
  local tcells = t and cells_of("locker", t) or {}
  local all_turned, meet = #tcells >= 2, true
  local cx, cy
  for _, c in ipairs(tcells) do
    local p = pics(c)[1]
    if not p or p.params.rotation ~= 90 or p.params.texture_rect ~= nil then all_turned = false
    else
      -- (Its centre on the screen: the cell's place plus the piece's.)
      local px = c.params.position[1] + p.params.x + p.params.w / 2
      local py = c.params.position[2] + p.params.y + p.params.h / 2
      if cx and (not near(px, cx) or not near(py, cy)) then meet = false end
      cx, cy = px, py
    end
  end
  T("an AMCAR turned in the locker: its picture turned in each cell", moved and t.rotated == true and all_turned, #tcells)
  T("  the pieces meet (one centre)", meet)
end

-- The weapon view.
T("a right click on the AMCAR in PRI: its view", right_press({ container = "hand_primary", x = 0, y = 0 }) == false
  and named("pdti_shop"):find("inspect_label") ~= nil)
local shop = named("pdti_shop")
local big = shop:find("inspect_picture")
local bp1 = big and pics(big)[1]
-- The slots of the weapon view, in the bands (the first ones on top of the
-- weapon, the last ones under it).
local function slot_boxes()
  local out = {}
  for i = 1, 40 do
    local s = named("pdti_shop"):find("inspect_slot_" .. i)
    if not s then break end
    out[#out + 1] = s
  end
  return out
end
T("  its picture in the middle of the view: the slots on top of it above, the ones under it below", bp1 ~= nil
  and bp1.params.texture == WEP .. "amcar"
  and big.params.position[2] > shop:find("inspect_label").params.position[2]
  and shop:find("inspect_weight").params.position[2] <= big.params.position[2]
  and (function()
    local boxes = slot_boxes()
    local top, bottom = boxes[1], boxes[#boxes]
    return top and bottom and top.params.position[2] + top.ph <= big.params.position[2]
      and bottom.params.position[2] >= big.params.position[2] + big.ph
  end)())
T("  120 high, centred, its shape kept", big ~= nil and big.ph == 120 and near(bp1.params.h, 120) and near(bp1.params.w, 240)
  and near(bp1.params.x, (big.pw - 240) / 2), bp1 and (bp1.params.w .. "x" .. bp1.params.h))
local function slot_box(prefix)
  for i = 1, 40 do
    local s = shop:find("inspect_slot_" .. i)
    if not s then break end
    if tostring(s.params.text):find(prefix, 1, true) == 1 then return s end
  end
end
local gbox = slot_box("Gadget")
T("  the laser's slot box: not yet (the game loads it)", gbox ~= nil and #pics(gbox) == 0)
arrive()
menu():update()
shop = named("pdti_shop")
gbox = slot_box("Gadget")
local gp = gbox and pics(gbox)[1]
T("  then its picture, on the right of its box", gp ~= nil and gp.params.texture == MOD .. "gd_laser"
  and gp.params.x + gp.params.w <= gbox.pw - 1 and gp.params.x > gbox.pw / 2 and gbox.params.text_align == "left",
  gp and (gp.params.x .. "+" .. gp.params.w .. " / " .. tostring(gbox.pw)))
T("  the text kept clear of it", gp ~= nil and gbox.params.font_size < 11 and clear_of(gbox, gp), gbox and gbox.params.text)
T("  a standard part's box and an empty one: none", #pics(slot_box("Barrel")) == 0 and #pics(slot_box("Muzzle")) == 0
  and slot_box("Barrel").params.text_align == "center")
shop:find("inspect_close"):click()

-- A part's view.
T("Shift+click on a part: its view, its picture", shift_click(string.format("cell_%s_%d_%d", rc, rit.x, rit.y))
  and named("pdti_shop"):find("inspect_picture") ~= nil
  and pics(named("pdti_shop"):find("inspect_picture"))[1].params.texture == DLC_RED)
named("pdti_shop"):find("inspect_close"):click()

-- The Chimano's view: no picture, no gap.
right_press({ container = "hand_secondary", x = 0, y = 0 })
shop = named("pdti_shop")
T("the Chimano's view: no picture, nothing left for it", shop:find("inspect_picture") == nil
  and shop:find("inspect_weight").params.position[2] == shop:find("inspect_label").params.position[2] + 20)
shop:find("inspect_close"):click()

-- 22 parts: the view still fits 720p with its picture.
do
  local wc, wid = weapon(pri.uid)
  local many = { "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" }
  for i = 1, 17 do many[#many + 1] = "z_extra_" .. i end
  PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = { blueprint = A.JoinBlueprint(many) } } } })
  right_press({ container = "hand_primary", x = 0, y = 0 })
  shop = named("pdti_shop")
  T("a weapon with 22 parts: with its picture the view fits 720p", shop:find("inspect_picture") ~= nil
    and shop:find("inspect_slot_22") ~= nil and shop.ph <= 720, shop.ph)
  shop:find("inspect_close"):click()
end

-- Closing gives the textures back.
local asked = #requests
local shown, pics_then = all_pics(), nil
local real_unretrieve = managers.menu_component.unretrieve_texture
managers.menu_component.unretrieve_texture = function(...)
  if pics_then == nil then pics_then = all_pics() end
  return real_unretrieve(...)
end
PDTI.SetUIOpen(false)
managers.menu_component.unretrieve_texture = real_unretrieve
T("closing: every texture given back", asked >= 3 and #released == asked, #released .. "/" .. asked)
T("  the pictures went first (the hidden screen keeps none of a texture given back)", shown > 0 and pics_then == 0
  and all_pics() == 0, shown .. " " .. tostring(pics_then))
T("  the next opening asks again", PDTI.ToggleUI() == true and #requests > asked)
arrive()
menu():update()
PDTI.SetUIOpen(false)

-- The market's Weapons tab: the weapon picked.
T("the market opens", PDTI.OpenMarket() == true)
named("pdti_shop"):find("market_tab_weapons"):click()
windows()[1]:find("wmarket_prices"):find("wmarket_price_amcar"):click()
arrive()
menu():update()
shop = named("pdti_shop")
local mp = shop:find("wmarket_picture")
T("  the AMCAR picked: its picture above Buy", mp ~= nil and #pics(mp) == 1 and pics(mp)[1].params.texture == WEP .. "amcar"
  and shop:find("wmarket_buy").params.position[2] >= mp.params.position[2] + mp.ph)
windows()[1]:find("wmarket_page_secondaries"):click()
windows()[1]:find("wmarket_prices"):find("wmarket_price_glock_17"):click()
shop = named("pdti_shop")
T("  the Chimano (none): Buy right under its stock", shop:find("wmarket_picture") == nil
  and shop:find("wmarket_buy").params.position[2] == shop:find("wmarket_stock").params.position[2] + 16 + 2)
PDTI.SetUIOpen(false)

-- Names on pictures off (0.40.1): the pictures alone.
T("names on pictures: on by default", PDTI.Ammo.settings.item_picture_names == true and Pic.ShowNames() == true)
PDTI.Ammo.settings.item_picture_names = false
PDTI.ToggleUI()
named("pdti_shop"):find("shop_tab_locker"):click()
arrive()
menu():update()
do
  local ncells = cells_of("locker", PDTI.FindItem("locker", lit.instance_id))
  T("names off: the AMCAR in the locker, its picture alone", #pics(ncells[1]) == 1 and ncells[1].params.text == "",
    ncells[1].params.text)
  local nrc, nrit = part_cell("s_red")
  local rcell = cell(nrc, nrit.x, nrit.y)
  T("  a part too", #pics(rcell) == 1 and rcell.params.text == "", rcell.params.text)
  local npbox = find("weapon_box_primary")
  local npp = pics(npbox)[1]
  T("  PRI: the picture alone, at full strength", npp ~= nil and npbox.params.text == "" and npp.params.alpha == nil,
    npbox.params.text)
  T("  a bandage (no picture) keeps its name", cell("pockets", bandage.x, bandage.y).params.text ~= "")
  T("  the Chimano (no picture) keeps its name and weight", tostring(find("weapon_box_secondary").params.text):find("Chimano", 1, true) ~= nil)
  right_press({ container = "hand_primary", x = 0, y = 0 })
  local nshop = named("pdti_shop")
  T("  the weapon view keeps its text", tostring(nshop:find("inspect_label").params.text):find("AMCAR", 1, true) ~= nil
    and nshop:find("inspect_slot_1") ~= nil and nshop:find("inspect_slot_1").params.text ~= "")
end
PDTI.SetUIOpen(false)
PDTI.Ammo.settings.item_picture_names = true
T("  saved with the others", (function()
  for _, f in ipairs(PDTI.Ammo.SETTING_FILES) do if has(f.keys, "item_picture_names") then return true end end
  return false
end)())

-- The setting off: today's look.
PDTI.Ammo.settings.item_pictures = false
PDTI.ToggleUI()
named("pdti_shop"):find("shop_tab_locker"):click()
arrive()
menu():update()
right_press({ container = "hand_primary", x = 0, y = 0 })
arrive()
menu():update()
T("the setting off: no pictures anywhere", all_pics() == 0 and named("pdti_shop"):find("inspect_picture") == nil
  and find("weapon_box_primary").params.text_align == "center")
PDTI.SetUIOpen(false)
PDTI.OpenMarket()
named("pdti_shop"):find("market_tab_weapons"):click()
T("  (the market keeps the page you were on)", windows()[1]:find("wmarket_page_secondaries").params.background_color
  ~= windows()[1]:find("wmarket_page_primaries").params.background_color
  and windows()[1]:find("wmarket_prices"):find("wmarket_price_glock_17") ~= nil)
windows()[1]:find("wmarket_page_primaries"):click()
windows()[1]:find("wmarket_prices"):find("wmarket_price_amcar"):click()
arrive()
menu():update()
T("  nor in the market", named("pdti_shop"):find("wmarket_buy") ~= nil and named("pdti_shop"):find("wmarket_picture") == nil
  and all_pics() == 0)
PDTI.SetUIOpen(false)
PDTI.Ammo.settings.item_pictures = true
T("the setting is saved with the others", (function()
  for _, f in ipairs(PDTI.Ammo.SETTING_FILES) do if has(f.keys, "item_pictures") then return true end end
  return false
end)())

T("no undocumented MenuUI parameters", #ENV.violations == 0, table.concat(ENV.violations, ", "))

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
