-- 0.39.0: hot modding (armory_hotmod.lua). Weapon parts are changed in a
-- heist too, in time (by the part's kind); an action or going down stops
-- it. A won heist keeps what it changed, a failed one loses what you
-- carried (a part fitted or thrown away in it too).
--   luajit tests/hotmod_tests.lua
local script = arg and arg[0] or "tests/hotmod_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_hotmod") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

-- The game's weapons and parts.
local W = tweak_data.weapon
W.amcar = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AMCAR", CLIP_AMMO_MAX = 20 }
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
  { "s_red", "sight" }, { "b_supp", "barrel_ext" }, { "gd_laser", "gadget" }, { "pm_ext", "magazine" },
  { "u_up", "upper_reciever" } }) do
  part(p[1], p[2])
end
local PARTS_BY = {
  wpn_fps_ass_amcar = {
    lower_reciever = { "amcar_body" }, barrel = { "amcar_barrel" }, stock = { "amcar_stock" },
    sight = { "amcar_irons", "s_red" }, barrel_ext = { "b_supp" }, gadget = { "gd_laser" },
    magazine = { "amcar_mag" }, upper_reciever = { "u_up" }
  },
  wpn_fps_pis_g17 = { slide = { "g17_slide" }, magazine = { "g17_mag", "pm_ext" }, barrel_ext = { "b_supp" } }
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
dofile(ROOT .. "lua/ammo_hooks.lua") -- (what stops a change: Ammo.ActionPressed)
dofile(ROOT .. "lua/body.lua") -- (the health window in a heist)
local A, P, H = PDTI.Armory, PDTI.Parts, PDTI.HotMod

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
  _calculate_weapon_concealment = function() return 30 end
}
managers.localization = { text = function(_, id) return id end }
managers.dlc = { is_dlc_unlocked = function() return false end }
_G.Global = _G.Global or {}
Global.blackmarket_manager = { crafted_items = { primaries = {}, secondaries = {} } }
local crafted = Global.blackmarket_manager.crafted_items
ENV.game.unit = nil -- the menu: no player
PDTI.Market.Today = function() return "2026-11-18" end
A.FactorRoll = function() return 0.5 end
A.StockRoll = function() return 0.99 end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

-- The player in a heist: the guns the game made at spawn, and its state.
local pstate = "standard"
local inv
local function unit(f) local b = { _factory_id = f }; return { base = function() return b end } end
local function new_player()
  inv = { sel = { [2] = { unit = unit("wpn_fps_ass_amcar") }, [1] = { unit = unit("wpn_fps_pis_g17") } }, eq = 2, added = {} }
  function inv:available_selections() return self.sel end
  function inv:equipped_selection() return self.eq end
  function inv:equip_selection(i) self.eq = i; return true end
  function inv:add_unit_by_factory_name(f, equip, instant, list)
    self.sel[f == "wpn_fps_pis_g17" and 1 or 2] = { unit = unit(f) }
    self.added[#self.added + 1] = { f = f, bp = list }
  end
  local player = { inventory = function() return inv end }
  managers.player = { player_unit = function() return player end, current_state = function() return pstate end }
  return player
end

local function fresh()
  if H.Active() then H.Stop() end
  managers.player, managers.job = nil, nil
  pstate = "standard"
  os.remove(TMP .. "pdti_armory.json")
  A.Reset()
  PDTI.Reset()
  PDTI.session_only = false
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetEquipment("rig", "general_rig")
  A.IssueFree() -- the AMCAR in PRI, the Chimano in SEC
  return A.HandItem("primaries").data
end
-- Where an item (a weapon or a part) is, by its uid.
local function where(uid)
  local e = PDTI.FindItems(function(_, it) return type(it.data) == "table" and it.data.uid == uid end)[1]
  if e then return e.container, e.item end
end
local function weapon(uid)
  for _, w in ipairs(A.Weapons()) do if w.data.uid == uid then return w.container, w.instance_id, w.data end end
end
local function part_items(part_id)
  return PDTI.FindItems(function(_, it) return it.item_id == P.ITEM_ID and it.data.part_id == part_id end)
end
local function where_part(part_id)
  local e = part_items(part_id)[1]
  if e then return e.container, e.item.instance_id end
end
local function part_uid(part_id) local e = part_items(part_id)[1]; return e and e.item.data.uid end
local function bp(uid) local _, _, d = weapon(uid); return A.SplitBlueprint(d.blueprint) end
local function move(uid, to)
  local c, it = where(uid)
  local x, y, rot = PDTI.FindFreeSpace(to, it, true)
  return PDTI.MoveItem(c, it.instance_id, to, x, y, rot)
end
-- Bought into the locker, then carried (packed) when to is given.
local function buy(part_id, to, weapon_id)
  local okb, whyb = P.Buy(weapon_id or "amcar", part_id)
  if not okb then print("(buy " .. part_id .. ": " .. tostring(whyb) .. ")") end
  local uid = part_uid(part_id)
  if to then move(uid, to) end
  return uid
end
local function hfit(part_id, uid)
  local pc, pid = where_part(part_id)
  local wc, wid = weapon(uid)
  return H.Fit(pc, pid, wc, wid)
end
-- Fitted at once (at home).
local function fit_home(part_id, uid)
  local pc, pid = where_part(part_id)
  local wc, wid = weapon(uid)
  return P.Fit(pc, pid, wc, wid)
end
local function hoff(uid, part_id, to, x, y, rot)
  local wc, wid = weapon(uid)
  return H.TakeOff(wc, wid, part_id, to, x, y, rot)
end
local function tick(s, input) return H.Tick(s, input or {}) end
-- A heist begins (the briefing over, the player in).
local function heist()
  A.OnHeistStart()
  PDTI.session_only = true
  return A.OnSpawn(new_player())
end
-- The heist ends (nil: the game was quit) and the game loads the menu
-- (from the files: a heist writes no inventory). before: done in the menu
-- before the armory's turn.
local function to_menu(success, before)
  if success ~= nil then A.OnMissionEnd(success) end
  if H.Active() then H.Stop() end
  A.Reset()
  managers.player = nil
  PDTI.session_only = false
  PDTI.LoadProfile()
  if before then before() end
  A.OnMenu()
end
local function status() return tostring(PDTI.UIGetStatusText()) end

------------------------------------------------------------------ the times

T("by the part's kind: a muzzle 2 s, a sight 3, a stock 4, a barrel 8, a receiver 10, anything else 4",
  H.Time("barrel_ext") == 2 and H.Time("gadget") == 2 and H.Time("sight") == 3 and H.Time("stock") == 4
  and H.Time("barrel") == 8 and H.Time("upper_reciever") == 10 and H.Time("lower_reciever") == 10
  and H.Time("ammo") == 4 and H.Time(nil) == 4)

-------------------------------------------------------------------- at home

do
  local am = fresh()
  buy("s_red")
  local ok = hfit("s_red", am.uid)
  T("the menu: a part goes on at once", ok and has(bp(am.uid), "s_red") and H.Active() == nil)
  managers.job = { current_job_id = function() return "chill" end }
  A.OnSpawn(new_player())
  T("(the safehouse: not a heist)", A.InHeist() == false)
  T("  no note of what you carry (it is home)", not A._Data().taken_set)
  buy("b_supp", "backpack")
  local okh = hfit("b_supp", am.uid)
  T("the safehouse: at once too, the gun in your hands made again with it", okh and H.Active() == nil
    and has(bp(am.uid), "b_supp") and #inv.added == 1 and has(inv.added[1].bp, "b_supp"), #inv.added)
  local okt = hoff(am.uid, "b_supp")
  T("  taken off at once", okt and not has(bp(am.uid), "b_supp") and #part_items("b_supp") == 1 and H.Active() == nil)
end

------------------------------------------------------------- in a heist

local am = fresh()
local red = buy("s_red", "backpack")
local supp = buy("b_supp", "backpack")
local laser = buy("gd_laser", "backpack")
buy("pm_ext", "backpack", "glock_17")
fit_home("pm_ext", A.HandItem("secondaries").data.uid)
buy("pm_ext", "backpack", "glock_17")
local up = buy("u_up") -- (left in the locker)
local _, spare = A.Buy("amcar")
move(spare.uid, "backpack")
local spare_uid = spare.uid
local _, pistol = A.Buy("glock_17") -- (left in the locker)
T("(a heist begins: the guns the game made are your slots')", heist() == false and #inv.added == 0)
local d = A._Data()
T("what you carry at the spawn is noted: the weapons and parts out of the locker, and their builds", d.taken_set
  and has(d.taken, am.uid) and has(d.taken, red) and has(d.taken, spare_uid) and not has(d.taken, up)
  and d.taken_bp[tostring(am.uid)] == am.blueprint)
local ok1, text1 = hfit("s_red", am.uid)
T("a sight onto the AMCAR in PRI: it takes 3 s, and says what stops it", ok1
  and tostring(text1):find("Fitting the s_red: 3 s", 1, true) ~= nil
  and tostring(text1):find("shooting, aiming, reloading or switching stops it", 1, true) ~= nil, text1)
T("  nothing changes yet", not has(bp(am.uid), "s_red") and where(red) == "backpack" and H.Active().progress == 0
  and H.Active().kind == "fit" and H.Active().weapon_uid == am.uid and H.Active().ptype == "sight")
local ok2, why2 = hfit("b_supp", am.uid)
T("one change at a time", ok2 == false and tostring(why2):find("wait: the s_red is being fitted", 1, true) ~= nil, why2)
local okt2, whyt2 = hoff(am.uid, "amcar_irons")
T("  nothing comes off meanwhile either", okt2 == false
  and tostring(whyt2):find("wait: the s_red is being fitted", 1, true) ~= nil and H.Active().part_id == "s_red", whyt2)
T("a second in: a third of the way, not on yet", tick(1) == true and math.abs(H.Active().progress - 1 / 3) < 0.01
  and not has(bp(am.uid), "s_red"))
T("  nearly there: still not", tick(1.9) == true and not has(bp(am.uid), "s_red"))
tick(0.2)
T("the time is up: on the AMCAR, its item gone", H.Active() == nil and has(bp(am.uid), "s_red") and where(red) == nil)
T("  the gun in your hands is made again with it", #inv.added == 1 and has(inv.added[1].bp, "s_red"), #inv.added)
T("  the status says so", status():find("s_red", 1, true) ~= nil, status())
local okm, whym = hfit("pm_ext", A.HandItem("secondaries").data.uid)
T("a magazine is not changed in a heist (the Chimano's)", okm == false
  and tostring(whym):find("magazines are changed at home", 1, true) ~= nil and H.Active() == nil, whym)
local okmo, whymo = hoff(A.HandItem("secondaries").data.uid, "pm_ext")
T("  nor taken off", okmo == false and tostring(whymo):find("magazines are changed at home", 1, true) ~= nil
  and H.Active() == nil, whymo)
local oku, whyu = hfit("u_up", am.uid)
T("nor a part in the locker (it stays at home)", oku == false
  and tostring(whyu):find("the locker stays at home", 1, true) ~= nil, whyu)
local okp, whyp = hfit("b_supp", pistol.uid)
T("  nor onto a weapon in the locker", okp == false and tostring(whyp):find("the locker stays at home", 1, true) ~= nil, whyp)
local okq, whyq = hoff(pistol.uid, "g17_slide")
T("  nor off one", okq == false and tostring(whyq):find("the locker stays at home", 1, true) ~= nil, whyq)
local okl, whyl = P.Sell(where_part("gd_laser"))
T("nothing is sold in a heist", okl == false and where(laser) == "backpack", whyl)

-- Stopped: an action, going down. Not while the screen is open.
hfit("b_supp", am.uid)
T("shooting stops it: nothing changes, its time is lost", tick(0.5, { btn_primary_attack_press = true }) == false
  and H.Active() == nil and not has(bp(am.uid), "b_supp") and where(supp) == "backpack")
T("  the status says so", status():find("Stopped: the b_supp is not fitted", 1, true) ~= nil, status())
hfit("b_supp", am.uid)
T("  so does switching weapons", tick(0.5, { btn_switch_weapon_press = true }) == false and H.Active() == nil)
hfit("b_supp", am.uid)
T("moving does not", tick(0.5, { btn_jump_press = true, move = true }) == true and H.Active() ~= nil)
pstate = "carry"
T("  nor carrying a bag", tick(0.1) == true and H.Active() ~= nil)
pstate = nil
T("  nor a state the game does not tell", tick(0.1) == true and H.Active() ~= nil)
pstate = "standard"
H.Stop()
do
  local real = { open = PDTI.IsUIOpen, drag = PDTI.UIIsDragging, redraw = PDTI.RedrawUI }
  local redraws = 0
  PDTI.IsUIOpen = function() return true end
  PDTI.RedrawUI = function() redraws = redraws + 1 end
  PDTI.UIIsDragging = function() return true end
  hoff(am.uid, "s_red") -- (3 s)
  local before_r = redraws
  tick(1.1)
  T("the screen open, something dragged: not drawn again (its preview stays)", redraws == before_r)
  PDTI.UIIsDragging = function() return false end
  tick(0.2)
  T("  nothing dragged: drawn again only when a second passes", redraws == before_r)
  tick(0.8)
  T("  (then it is)", redraws == before_r + 1 and H.Active() ~= nil and has(bp(am.uid), "s_red"))
  PDTI.IsUIOpen, PDTI.UIIsDragging, PDTI.RedrawUI = real.open, real.drag, real.redraw
  H.Stop()
end
hfit("b_supp", am.uid)
local real_open = PDTI.IsUIOpen
PDTI.IsUIOpen = function() return true end
T("with the screen open (the game gets no input) a click goes on", tick(0.5, { btn_primary_attack_press = true }) == true
  and H.Active() ~= nil)
PDTI.IsUIOpen = real_open
pstate = "bleed_out"
T("going down stops it", tick(0.1) == false and H.Active() == nil and not has(bp(am.uid), "b_supp"))
local okd, whyd = hfit("b_supp", am.uid)
T("  down, none starts", okd == false and tostring(whyd):find("not while you are down", 1, true) ~= nil
  and H.Active() == nil, whyd)
local okdo, whydo = hoff(am.uid, "s_red")
T("  nothing comes off either", okdo == false and tostring(whydo):find("not while you are down", 1, true) ~= nil
  and H.Active() == nil, whydo)
pstate = "mask_off"
T("before the mask is on: it goes on", hfit("b_supp", am.uid) == true and tick(2.1) == true and has(bp(am.uid), "b_supp"))
pstate = "standard"
T("  (made again with it)", #inv.added == 2 and has(inv.added[2].bp, "b_supp"))
local okk, whyk = hoff(am.uid, "b_supp", "locker", 0, 0, false)
T("nothing comes off into the locker", okk == false and tostring(whyk):find("the locker stays at home", 1, true) ~= nil
  and H.Active() == nil, whyk)

-- Taken off: to a cell, or next to the weapon.
local ref = { item_id = P.ITEM_ID, data = P.MakeData("b_supp") }
local fx, fy = PDTI.FindFreeSpace("backpack", ref, false)
local okb = PDTI.AddItem("backpack", "bandage", fx, fy, false, 1)
local okc, whyc = hoff(am.uid, "b_supp", "backpack", fx, fy, false)
T("taken off onto a taken cell: refused at once", okb and okc == false and H.Active() == nil and has(bp(am.uid), "b_supp"), whyc)
local function clear_cell() PDTI.RemoveItem("backpack", PDTI.GetOccupancyMap("backpack").cells[fy + 1][fx + 1]) end
clear_cell()
local oko, texto = hoff(am.uid, "b_supp", "backpack", fx, fy, false)
T("taken off onto a free cell: 2 s", oko and tostring(texto):find("Taking off the b_supp: 2 s", 1, true) ~= nil
  and H.Active().kind == "off", texto)
PDTI.AddItem("backpack", "bandage", fx, fy, false, 1)
T("  its cell taken meanwhile: it comes off next to the weapon", tick(2.1) == true and not has(bp(am.uid), "b_supp")
  and #part_items("b_supp") == 1)
local bc, bi = where(part_uid("b_supp"))
T("  (not on that cell, and not in the locker)", bc ~= "locker" and not (bc == "backpack" and bi.x == fx and bi.y == fy))
T("  the gun made again without it", #inv.added == 3 and not has(inv.added[3].bp, "b_supp"))
clear_cell()
hfit("b_supp", am.uid)
tick(2.1)
hoff(am.uid, "b_supp", "backpack", fx, fy, false)
tick(2.1)
local bc2, bi2 = where(part_uid("b_supp"))
T("taken off onto a free cell: there", bc2 == "backpack" and bi2.x == fx and bi2.y == fy and bi2.rotated ~= true)
hfit("b_supp", am.uid)
tick(2.1)
local tx, ty
for y = 0, 9 do
  for x = 0, 9 do
    if not tx and PDTI.CanPlace("rig", ref, x, y, true) and not PDTI.CanPlace("rig", ref, x, y, false) then tx, ty = x, y end
  end
end
if not tx then tx, ty = PDTI.FindFreeSpace("rig", ref, false) end
local okrot = hoff(am.uid, "b_supp", "rig", tx, ty, true)
tick(2.1)
local rc3, ri3 = where(part_uid("b_supp"))
T("taken off onto a cell turned: there, turned", okrot and rc3 == "rig" and ri3.x == tx and ri3.y == ty
  and ri3.rotated == true)
local okr = hoff(am.uid, "s_red")
T("the sight taken off, no cell: next to the weapon (never the locker)", okr and tick(3.1) == true
  and part_uid("s_red") ~= nil and where(part_uid("s_red")) ~= "locker" and not has(bp(am.uid), "s_red"))

-- Moved or gone meanwhile.
hfit("gd_laser", am.uid)
move(laser, "rig")
T("a part moved meanwhile (into the rig): still fitted", tick(2.1) == true and has(bp(am.uid), "gd_laser")
  and where(laser) == nil)
hfit("b_supp", am.uid)
local sc, si = where(part_uid("b_supp"))
PDTI.RemoveItem(sc, si.instance_id)
T("a part thrown away meanwhile: not fitted, says why", tick(2.1) == false and not has(bp(am.uid), "b_supp")
  and status():find("The b_supp is not fitted: the part is gone", 1, true) ~= nil, status())
local before = #inv.added
hfit("s_red", spare_uid)
T("a weapon packed in the backpack is modded too", tick(3.1) == true and has(bp(spare_uid), "s_red")
  and #inv.added == before)
local okw = hoff(spare_uid, "s_red")
local wc, wi = where(spare_uid)
PDTI.RemoveItem(wc, wi.instance_id)
T("a weapon thrown away meanwhile: nothing comes off", okw and tick(3.1) == false and part_uid("s_red") == nil
  and status():find("the weapon is gone", 1, true) ~= nil, status())

---------------------------------------------------------------- death

do
  local a = fresh()
  local r = buy("s_red", "backpack")
  local s = buy("b_supp", "backpack")
  local kept = buy("gd_laser") -- (in the locker)
  heist()
  hfit("s_red", a.uid)
  tick(3.1)
  local c, it = where(s)
  PDTI.RemoveItem(c, it.instance_id)
  T("(in the heist: the sight on the AMCAR, the suppressor thrown away)", has(bp(a.uid), "s_red") and where(s) == nil)
  to_menu(false)
  T("a failed heist: the AMCAR you carried is lost, the sight fitted to it there too", weapon(a.uid) == nil
    and where(r) == nil)
  T("  the part thrown away there too", where(s) == nil)
  T("  the locker's kept", where(kept) == "locker")
  T("  nothing is noted for the next heist", not A._Data().taken_set and #A._Data().taken == 0
    and #A._Data().after.builds + #A._Data().after.gone + #A._Data().after.parts == 0)
end
do
  local a = fresh()
  buy("b_supp")
  fit_home("b_supp", a.uid)
  heist()
  hoff(a.uid, "b_supp")
  tick(2.1)
  T("(in the heist: the suppressor taken off, a part again)", #part_items("b_supp") == 1)
  to_menu(false)
  T("a failed heist: a part taken off there is no item (it went with its weapon)", #part_items("b_supp") == 0
    and weapon(a.uid) == nil)
end
do
  local a = fresh()
  local r = buy("s_red", "backpack")
  heist()
  hfit("s_red", a.uid)
  tick(3.1)
  to_menu(nil)
  T("a heist left unfinished (the game quit): the sight fitted there is lost with its weapon", where(r) == nil
    and weapon(a.uid) == nil)
end

------------------------------------------------------------------- a win

do
  local a = fresh()
  local r = buy("s_red", "backpack")
  buy("b_supp")
  fit_home("b_supp", a.uid)
  local l = buy("gd_laser", "backpack")
  local stay = buy("u_up", "backpack")
  local home = buy("pm_ext", nil, "glock_17")
  heist()
  local _, picked = PDTI.AddItemAuto("rig", "weapon", 1, A.MakeData("amcar", nil, 777), true)
  T("(a weapon that came in the heist, in the rig)", picked ~= nil)
  hfit("s_red", a.uid)
  tick(3.1)
  local ref2 = { item_id = P.ITEM_ID, data = P.MakeData("b_supp") }
  local x, y = PDTI.FindFreeSpace("rig", ref2, false)
  hoff(a.uid, "b_supp", "rig", x, y, false)
  tick(2.1)
  local s_new = part_uid("b_supp")
  local lc, li = where(l)
  PDTI.RemoveItem(lc, li.instance_id)
  local blueprint = A.HandItem("primaries").data.blueprint
  A.OnMissionEnd(true)
  local after = A._Data().after
  T("won: what the heist changed is noted (the build, the sight and the laser gone, the suppressor taken off)",
    #after.builds == 1 and after.builds[1].uid == a.uid and after.builds[1].blueprint == blueprint
    and has(after.gone, r) and has(after.gone, l) and #after.gone == 2
    and #after.parts == 1 and after.parts[1].data.uid == s_new and after.parts[1].at == "rig")
  to_menu()
  T("  at the menu the AMCAR keeps the sight fitted there, the suppressor is off", has(bp(a.uid), "s_red")
    and not has(bp(a.uid), "b_supp") and A.HandItem("primaries").data.blueprint == blueprint)
  T("  its weight is the new build's", A.HandItem("primaries").data.weight
    == A.Weight("amcar", "wpn_fps_ass_amcar", A.SplitBlueprint(blueprint)))
  T("  the sight's item is gone (it is on the gun)", where(r) == nil and #part_items("s_red") == 0)
  T("  the suppressor taken off is yours, where it was", where(s_new) == "rig" and #part_items("b_supp") == 1)
  T("  the laser thrown away is lost", where(l) == nil)
  T("  the rest as it was (a part carried, one in the locker)", where(stay) == "backpack" and where(home) == "locker"
    and #part_items("u_up") == 1 and #part_items("pm_ext") == 1)
  T("  the game's weapon follows", crafted.primaries[1] ~= nil and has(crafted.primaries[1].blueprint, "s_red"),
    crafted.primaries[1] and table.concat(crafted.primaries[1].blueprint or {}, ","))
  T("  nothing is left to do", #A._Data().after.builds + #A._Data().after.gone + #A._Data().after.parts == 0)
  T("  a new uid is not the suppressor's", A._Data().next_uid > s_new)
end
-- No room for a part taken off: the locker, else it waits.
local function fill(c)
  for n = 0, 299 do
    if not PDTI.AddItemAuto(c, P.ITEM_ID, 1, P.MakeData("s_red", "amcar", 90000 + n), false) then break end
  end
end
local function filler(c)
  for _, e in ipairs(PDTI.FindItems(function(name, it)
    return name == c and it.item_id == P.ITEM_ID and (tonumber(it.data.uid) or 0) >= 90000
  end)) do
    PDTI.RemoveItem(e.container, e.item.instance_id)
  end
end
do
  local a = fresh()
  buy("b_supp")
  fit_home("b_supp", a.uid)
  heist()
  hoff(a.uid, "b_supp")
  tick(2.1)
  local s_new = part_uid("b_supp")
  local at = where(s_new)
  to_menu(true, function() fill(at) end)
  T("won, no room where the part taken off was: the locker", where(s_new) == "locker", where(s_new))
end
do
  local a = fresh()
  buy("b_supp")
  fit_home("b_supp", a.uid)
  heist()
  hoff(a.uid, "b_supp")
  tick(2.1)
  local s_new = part_uid("b_supp")
  local at = where(s_new)
  to_menu(true, function() fill(at); fill("locker") end)
  T("  no room in the locker either: it waits", where(s_new) == nil and #A._Data().after.parts == 1
    and not has(bp(a.uid), "b_supp"))
  A.Reset()
  T("  (noted in the file)", #A._Data().after.parts == 1 and A._Data().after.parts[1].data.uid == s_new
    and A._Data().after.parts[1].data.part_id == "b_supp")
  filler("locker")
  A.OnMenu()
  T("  the next menu, with room: there", where(s_new) == "locker" and #A._Data().after.parts == 0)
end
-- A heist of days: the next day begins with what the day before changed.
do
  local a = fresh()
  local r = buy("s_red", "backpack")
  heist()
  hfit("s_red", a.uid)
  tick(3.1)
  A.OnMissionEnd(true)
  A.Reset()
  managers.player = nil
  PDTI.session_only = false
  PDTI.LoadProfile()
  T("(the next day loads the files: the sight not on yet)", not has(bp(a.uid), "s_red") and where(r) == "backpack")
  heist()
  T("the next day begins with it on, its item gone", has(bp(a.uid), "s_red") and where(r) == nil
    and #A._Data().after.builds == 0 and #A._Data().after.gone == 0)
  T("  the game's weapon follows (before the spawn)", crafted.primaries[1] ~= nil
    and has(crafted.primaries[1].blueprint, "s_red"))
  T("  what you carry is noted again", A._Data().taken_set and has(A._Data().taken, a.uid) and not has(A._Data().taken, r)
    and A._Data().taken_bp[tostring(a.uid)] == A.HandItem("primaries").data.blueprint)
  to_menu(false)
  T("  lost on the next day: the weapon with it", weapon(a.uid) == nil)
end
-- Won with nothing noted (no spawn): nothing is changed.
do
  fresh()
  local r = buy("s_red", "backpack")
  A.OnHeistStart()
  PDTI.session_only = true
  A.OnMissionEnd(true)
  T("won with nothing noted (no spawn): nothing to do", #A._Data().after.parts + #A._Data().after.gone
    + #A._Data().after.builds == 0)
  to_menu()
  T("  the part carried is there, once", where(r) == "backpack" and #part_items("s_red") == 1)
end
-- Nothing noted: nothing written.
do
  fresh()
  local real_save, saves = A.Save, 0
  A.Save = function(...) saves = saves + 1; return real_save(...) end
  T("nothing a won heist changed: nothing done, nothing written", H.ApplyWin() == 0 and saves == 0)
  A.Save = real_save
end
-- A part noted as taken off that is there already (the inventory was written,
-- the armory file not): not twice.
do
  fresh()
  local s2 = buy("b_supp", "backpack")
  A._Data().after.parts = { { data = P.MakeData("b_supp", "amcar", s2), at = "backpack" } }
  A.OnMenu()
  T("a part noted as taken off that is there already: not twice", #part_items("b_supp") == 1
    and #A._Data().after.parts == 0)
end
-- A note a crash left: the next heist notes anew.
do
  local a = fresh()
  local d0 = A._Data()
  d0.taken, d0.taken_set = { 999 }, true
  A.Save()
  heist()
  T("a note a crash left: the next heist notes anew", not has(A._Data().taken, 999) and has(A._Data().taken, a.uid))
end
-- A respawn (back from custody) keeps the first note.
do
  local a = fresh()
  local r = buy("s_red", "backpack")
  heist()
  hfit("s_red", a.uid)
  tick(3.1)
  A.OnSpawn(new_player())
  T("back from custody: what you carried at the first spawn is still the note", has(A._Data().taken, r))
end
-- The file: what is not right is left out.
do
  fresh()
  local f = io.open(TMP .. "pdti_armory.json", "w")
  f:write(json.encode({ next_uid = 2, taken = { 5, "x", -1 }, taken_set = true, taken_bp = { ["5"] = "a,b", x = "c", ["6"] = 3 },
    after = { builds = { { uid = "x" }, { uid = 5, blueprint = "a,b" }, { uid = 6 } }, gone = { 3, "y" },
      parts = { { data = { uid = 50, part_id = "b_supp", w = "1", h = 2, name = 4 }, at = 5 }, { data = { uid = 51 } } } } }))
  f:close()
  A.Reset()
  local x = A._Data()
  T("a file read: only the right entries", #x.taken == 1 and x.taken[1] == 5 and x.taken_set == true
    and x.taken_bp["5"] == "a,b" and x.taken_bp["6"] == nil and x.taken_bp.x == nil
    and #x.after.builds == 1 and x.after.builds[1].uid == 5 and #x.after.gone == 1 and x.after.gone[1] == 3
    and #x.after.parts == 1 and x.after.parts[1].at == "locker" and x.after.parts[1].data.w == 1
    and x.after.parts[1].data.name == nil)
  T("  a new uid stays above a waiting part's", x.next_uid == 51, x.next_uid)
end

-------------------------------------------------------------- the screen

do
  local a = fresh()
  buy("s_red", "backpack")
  buy("gd_laser")
  fit_home("gd_laser", a.uid) -- (a part of yours on it: its slot can be dragged out)
  local upper = buy("u_up", "backpack")
  heist()
  ENV.install_menuui(false)
  local function named(n)
    for _, w in ipairs(ENV.menus[#ENV.menus].children) do if w.params.name == n then return w end end
  end
  local function shop_has(name) local s = named("pdti_shop"); return s ~= nil and s:find(name) ~= nil end
  local function right_press(target)
    local saved_hit, saved_id = PDTI._UIHit, rawget(_G, "Idstring")
    PDTI._UIHit = function() return target end
    _G.Idstring = function(v) return v end
    local r = ENV.menus[#ENV.menus].params.pre_mouse_press("1", 1, 1)
    PDTI._UIHit, _G.Idstring = saved_hit, saved_id
    return r
  end
  local function texts()
    local out = {}
    for i = 1, 40 do
      local s = named("pdti_shop")
      local r = s and s:find("inspect_slot_" .. i)
      if not r then break end
      out[i] = tostring(r.params.text)
    end
    return out
  end
  local function health() local h = named("pdti_health"); return h ~= nil and h:find("health_hint_fak") ~= nil end
  T("(the screen opens in the heist)", PDTI.ToggleUI() == true and PDTI.InHeist())
  T("  the health window is there", health())
  T("  the middle window has nothing (no market in a heist)", not shop_has("inspect_label")
    and not shop_has("shop_tab_locker"))
  T("a right click on the AMCAR in PRI: its view", right_press({ container = "hand_primary", x = 0, y = 0 }) == false
    and shop_has("inspect_slot_1") and shop_has("inspect_label"))
  T("  nothing is sold here", not shop_has("inspect_sell"))
  T("  the health window gives it the middle", not health())
  T("  it says a change takes time there", shop_has("inspect_heist_help")
    and tostring(named("pdti_shop"):find("inspect_heist_help").params.text):find("takes time", 1, true) ~= nil)
  local rows = table.concat(texts(), "|")
  T("  the magazine's slot: changed at home", rows:find("Magazine\nstandard (at home)", 1, true) ~= nil, rows)
  -- The screen's ways: a part let go on the weapon, on its slot; Ctrl+click,
  -- a slot dragged out: in time.
  local rc, ri = where(part_uid("s_red"))
  PDTI.UIDragStart(rc, ri.x, ri.y)
  local okf, howf = PDTI.UIDragDrop({ container = "hand_primary", x = 0, y = 0 })
  T("a part let go on the AMCAR: it goes on in time", okf == true and howf == "fit" and H.Active() ~= nil
    and H.Active().kind == "fit" and not has(bp(a.uid), "s_red") and where(part_uid("s_red")) == rc
    and status():find("Fitting the s_red", 1, true) ~= nil, status())
  tick(1.5)
  rows = table.concat(texts(), "|")
  T("  its slot says how far", rows:find("Sight\nFitting... 50%", 1, true) ~= nil, rows)
  local _, extra = PDTI.AddItemAuto("backpack", P.ITEM_ID, 1, P.MakeData("b_supp", "amcar", 778), true)
  PDTI.UIDragStart("backpack", extra.x, extra.y)
  local pv = PDTI.UIDragPreview("hand_primary", 0, 0)
  T("  another part over the weapon meanwhile: it waits", pv and pv.valid == false
    and tostring(pv.reason):find("wait", 1, true) ~= nil, pv and pv.reason)
  local okw2 = PDTI.UIDragDrop({ container = "hand_primary", x = 0, y = 0 })
  T("  let go there: it stays where it was", okw2 == false and H.Active().part_id == "s_red" and where(778) == "backpack")
  local sight
  for i = 1, 20 do
    local h = PDTI._UISlotHit(i)
    if h and h.mod_slot.ptype == "sight" then sight = h.mod_slot end
  end
  local function slot_of(ptype)
    for i = 1, 20 do
      local h = PDTI._UISlotHit(i)
      if h and h.mod_slot.ptype == ptype then return h.mod_slot end
    end
  end
  local okg, whyg = PDTI.UISlotDragStart(slot_of("gadget"))
  T("  your laser's slot is not dragged out meanwhile", okg == false and PDTI.UIGetSlotDrag() == nil
    and tostring(whyg):find("wait", 1, true) ~= nil, whyg)
  local uc, ui = where(upper)
  PDTI.UIDragStart(uc, ui.x, ui.y)
  local sp = PDTI.UISlotPreview(slot_of("upper_reciever"))
  T("  a part over its empty slot meanwhile: it waits", sp ~= nil and sp.valid == false
    and tostring(sp.reason):find("wait", 1, true) ~= nil, sp and sp.reason)
  PDTI.UICancelHeld()
  tick(2)
  rows = table.concat(texts(), "|")
  T("  done: the slot shows the part", rows:find("Sight\ns_red", 1, true) ~= nil, rows)
  for i = 1, 20 do
    local h = PDTI._UISlotHit(i)
    if h and h.mod_slot.ptype == "sight" then sight = h.mod_slot end
  end
  PDTI.UISlotTakeOff(sight)
  T("Ctrl+click on its slot: it comes off in time", H.Active() ~= nil and H.Active().kind == "off" and has(bp(a.uid), "s_red"))
  tick(3.1)
  T("  then it is off", not has(bp(a.uid), "s_red") and part_uid("s_red") ~= nil)
  rc, ri = where(part_uid("s_red"))
  PDTI.UIDragStart(rc, ri.x, ri.y)
  local oks = PDTI.UIDragDrop({ mod_slot = sight })
  T("a part let go on its slot: in time", oks == true and H.Active() ~= nil and H.Active().kind == "fit")
  tick(3.1)
  for i = 1, 20 do
    local h = PDTI._UISlotHit(i)
    if h and h.mod_slot.ptype == "sight" then sight = h.mod_slot end
  end
  local cref = { item_id = P.ITEM_ID, data = P.MakeData("s_red") }
  local cx, cy = PDTI.FindFreeSpace("rig", cref, false)
  PDTI.UISlotDragStart(sight)
  local okd2 = PDTI.UIDragDrop({ container = "rig", x = cx, y = cy })
  T("its slot dragged out onto a cell: in time, then there", okd2 == true and H.Active() ~= nil
    and H.Active().kind == "off" and has(bp(a.uid), "s_red"))
  tick(3.1)
  local sc2, si2 = where(part_uid("s_red"))
  T("  (there)", sc2 == "rig" and si2.x == cx and si2.y == cy)
  -- A change on the AMCAR does not show on another weapon's view.
  rc, ri = where(778)
  PDTI.UIDragStart(rc, ri.x, ri.y)
  PDTI.UIDragDrop({ container = "hand_primary", x = 0, y = 0 })
  right_press({ container = "hand_secondary", x = 0, y = 0 })
  rows = table.concat(texts(), "|")
  T("the Chimano's view while a muzzle goes on the AMCAR: not its change", H.Active() ~= nil
    and rows:find("Muzzle", 1, true) ~= nil and rows:find("Fitting", 1, true) == nil, rows)
  H.Stop()
  named("pdti_shop"):find("inspect_close"):click()
  T("closed: the middle window has nothing again", not shop_has("inspect_label"))
  T("  the health window is back", health())
  right_press({ container = "hand_primary", x = 0, y = 0 })
  local wc2, wi2 = weapon(a.uid)
  PDTI.RemoveItem(wc2, wi2)
  PDTI.RedrawUI()
  T("the weapon looked at is gone: no market in its place", not shop_has("inspect_label")
    and not shop_has("shop_tab_locker") and not shop_has("bring_label"))
  local _, band = PDTI.AddItemAuto("pockets", "bandage", 1, nil, true)
  T("the locker is not looked into, nor a bandage", PDTI._UIInspect("locker", 0, 0) == false
    and right_press({ container = "pockets", x = band.x, y = band.y }) == nil)
  PDTI.ToggleUI()
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
