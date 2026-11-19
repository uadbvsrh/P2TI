-- 0.38.0: weapon parts as grid items (armory_parts.lua). Bought at the
-- market, fitted by dragging onto a weapon, taken off and sold through
-- Inspect, lost with a failed heist when carried.
--   luajit tests/parts_tests.lua
local script = arg and arg[0] or "tests/parts_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_parts") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

-- The game's weapons.
local W = tweak_data.weapon
W.amcar = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AMCAR", CLIP_AMMO_MAX = 20 }
W.new_m4 = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "CAR-4", CLIP_AMMO_MAX = 30 }
W.glock_17 = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "Chimano 88", CLIP_AMMO_MAX = 17 }
local FACTORY = { amcar = "wpn_fps_ass_amcar", new_m4 = "wpn_fps_ass_m4", glock_17 = "wpn_fps_pis_g17" }
local PRICE = { amcar = 10000, new_m4 = 40000, glock_17 = 5000 }

-- The game's parts: the factory's (type, forbids, unatainable) and the
-- black market's (drop value, DLC, achievement).
local FP = tweak_data.weapon.factory.parts
local MODS = {}
tweak_data.blackmarket = tweak_data.blackmarket or {}
tweak_data.blackmarket.weapon_mods = MODS
local function part(id, ptype, mod, extra)
  FP[id] = { type = ptype, name_id = id }
  for k, v in pairs(extra or {}) do FP[id][k] = v end
  if mod ~= false then MODS[id] = mod or { pc = 1 } end
end
for _, p in ipairs({ { "amcar_body", "lower_reciever" }, { "amcar_barrel", "barrel" }, { "amcar_stock", "stock" },
  { "amcar_irons", "sight" }, { "amcar_mag", "magazine" }, { "m4_body", "lower_reciever" }, { "g17_slide", "slide" },
  { "g17_mag", "magazine" } }) do
  part(p[1], p[2], { pc = 1 }) -- the weapons' own parts (standard issue)
end
part("s_holo", "sight")
part("s_red", "sight")
part("s_dlc", "sight", { pc = 1, dlc = "gage_pack" })
part("s_owned", "sight", { pc = 1, dlcs = { "owned_dlc" } })
part("s_hidden", "sight", { pc = 1 }, { unatainable = true })
part("s_ach", "sight", { pc = 1, is_a_unlockable = true })
part("s_nodrop", "sight", {})
part("s_infamous", "sight", { pc = 1, infamous = true })
part("b_supp", "barrel_ext")
part("st_tactical", "stock")
part("st_folding", "stock", nil, { forbids = { "g_vert" } })
part("g_vert", "vertical_grip")
part("gd_laser", "gadget", { pcs = { 10, 20 } })
part("m_ext", "magazine")
part("a_slug", "ammo")
part("x_skin", "custom", false) -- put on by a skin: no item
part("pm_ext", "magazine")
part("s_skin", "sight", { pc = 1, is_a_unlockable = true }) -- a skin's sight: no item
local PARTS_BY = {
  wpn_fps_ass_amcar = {
    lower_reciever = { "amcar_body" }, barrel = { "amcar_barrel" },
    stock = { "amcar_stock", "st_tactical", "st_folding" },
    sight = { "amcar_irons", "s_holo", "s_red", "s_dlc", "s_owned", "s_hidden", "s_ach", "s_nodrop", "s_infamous", "s_skin" },
    barrel_ext = { "b_supp" }, vertical_grip = { "g_vert" }, gadget = { "gd_laser" },
    magazine = { "amcar_mag", "m_ext" }, ammo = { "a_slug" }, custom = { "x_skin" }
  },
  wpn_fps_ass_m4 = { lower_reciever = { "m4_body" }, sight = { "s_holo", "s_red" } },
  wpn_fps_pis_g17 = { slide = { "g17_slide" }, magazine = { "g17_mag", "pm_ext" }, barrel_ext = { "b_supp" } }
}
local DEFAULT = {
  wpn_fps_ass_amcar = { "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" },
  wpn_fps_ass_m4 = { "m4_body" },
  wpn_fps_pis_g17 = { "g17_slide", "g17_mag" }
}
local function copy(t) local o = {}; for i, v in ipairs(t or {}) do o[i] = v end; return o end
local function has(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
local function forbidden(bp)
  local f = {}
  for _, p in ipairs(bp) do for _, x in ipairs(FP[p] and FP[p].forbids or {}) do f[x] = p end end
  return f
end
local function drop_forbidden(bp)
  local f = forbidden(bp)
  for i = #bp, 1, -1 do if f[bp[i]] then table.remove(bp, i) end end
end
-- The game's rules (weaponfactorymanager.lua): a part replaces the one of its
-- type, then what the new build forbids goes; removing only deletes.
managers.weapon_factory = {
  get_factory_id_by_weapon_id = function(_, id) return FACTORY[id] end,
  get_default_blueprint_by_factory_id = function(_, f) return copy(DEFAULT[f]) end,
  get_parts_from_weapon_id = function(_, id) return PARTS_BY[FACTORY[id]] end,
  can_add_part = function(_, f, p, bp)
    local nb = copy(bp)
    nb[#nb + 1] = p
    return forbidden(nb)[p]
  end,
  change_part_blueprint_only = function(_, f, p, bp, remove)
    local t = FP[p] and FP[p].type
    if not t then return false end
    if remove then
      for i, x in ipairs(bp) do if x == p then table.remove(bp, i) break end end
      drop_forbidden(bp)
      return false -- (the game's returns nothing useful here)
    end
    if not has(PARTS_BY[f] and PARTS_BY[f][t], p) then return false end
    for i, x in ipairs(bp) do if FP[x] and FP[x].type == t then table.remove(bp, i) break end end
    bp[#bp + 1] = p
    drop_forbidden(bp)
    return true
  end
}

ENV.load_mod(ROOT, true)
local A, P, Plan = PDTI.Armory, PDTI.Parts, PDTI.Plan

local money, deducts = 1000000, 0
managers.money = {
  total = function() return money end,
  deduct_from_total = function(_, v) money = money - v; deducts = deducts + 1 end,
  add_to_total = function(_, v) money = money + v end,
  add_to_spending = function(_, v) money = money + v end,
  get_payouts = function() return {} end,
  get_weapon_price_modified = function(_, id) return PRICE[id] end,
  -- by the part, the weapon's kind and the global value
  get_weapon_modify_price = function(_, wid, pid, gv)
    local v = pid == "b_supp" and 3000 or 1000
    if gv == "infamous" then v = v * 5 end
    if wid == "glock_17" then v = v / 2 end
    return v
  end
}
managers.blackmarket = {
  weapon_unlocked = function() return true end,
  -- a tactical stock is heavy: less concealment
  _calculate_weapon_concealment = function(_, w) return has(w.blueprint, "st_tactical") and 15 or 30 end
}
managers.localization = { text = function(_, id) return id end }
managers.dlc = { is_dlc_unlocked = function(_, d) return d == "owned_dlc" end }
_G.Global = _G.Global or {}
Global.blackmarket_manager = { crafted_items = { primaries = {}, secondaries = {} } }
local crafted = Global.blackmarket_manager.crafted_items
ENV.game.unit = nil -- the menu: no player
PDTI.Market.Today = function() return "2026-11-18" end
local factor_roll = {}
A.FactorRoll = function(id) return factor_roll[id] or 0.5 end
A.StockRoll = function() return 0.99 end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function fresh()
  os.remove(TMP .. "pdti_armory.json")
  A.Reset()
  PDTI.Reset()
  money = 1000000
  PDTI.session_only = false
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetEquipment("rig", "general_rig")
  A.IssueFree() -- the AMCAR in PRI, the Chimano in SEC
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
local function bp(uid) local _, _, d = weapon(uid); return A.SplitBlueprint(d.blueprint) end
local function fit(part_id, uid)
  local pc, pid = where_part(part_id)
  local wc, wid = weapon(uid)
  return P.Fit(pc, pid, wc, wid)
end
local function take_off(uid, part_id)
  local wc, wid = weapon(uid)
  return P.TakeOff(wc, wid, part_id)
end
local function buy(weapon_id, part_id) return P.Buy(weapon_id, part_id) end
-- Fills every place a part can go.
local function fill_all()
  local n = 0
  for _, c in ipairs(P.PLACES) do
    for _ = 1, 1000 do
      if not PDTI.AddItemAuto(c, P.ITEM_ID, 1, P.MakeData("s_red", "amcar", 9000 + n), false) then break end
      n = n + 1
    end
  end
  return n
end
local function clear_filler()
  for _, e in ipairs(PDTI.FindItems(function(_, it) return it.item_id == P.ITEM_ID and (tonumber(it.data.uid) or 0) >= 9000 end)) do
    PDTI.RemoveItem(e.container, e.item.instance_id)
  end
end

------------------------------------------------------------- the market

fresh()
local amcar = A.HandItem("primaries").data
local glock = A.HandItem("secondaries").data
local rows = P.ForWeapon("amcar")
local ids = {}
for _, r in ipairs(rows) do ids[r.part_id] = r end
T("the AMCAR's parts for sale", ids.s_holo and ids.s_red and ids.s_owned and ids.s_infamous and ids.b_supp
  and ids.st_tactical and ids.st_folding and ids.g_vert and ids.gd_laser, #rows)
T("  not its own parts", not ids.amcar_irons and not ids.amcar_stock)
T("  not a DLC part you don't own, but one you do (its DLC's)", not ids.s_dlc and ids.s_owned.global_value == "owned_dlc")
T("  not a hidden part, an achievement's, one that never drops", not ids.s_hidden and not ids.s_ach and not ids.s_nodrop)
T("  not an ammunition part (shells are the ammunition system's)", not ids.a_slug)
T("  not a magazine part: an assault rifle's magazines are PDTI's sizes", not ids.m_ext)
T("  not a part with no item (a skin's)", not ids.x_skin)
local sorted = true
for i = 2, #rows do
  local a, b = rows[i - 1], rows[i]
  if a.ptype > b.ptype or (a.ptype == b.ptype and a.today > b.today) then sorted = false end
end
T("  by type, then price", sorted)
local g17 = {}
for _, r in ipairs(P.ForWeapon("glock_17")) do g17[r.part_id] = r end
T("a pistol's magazine part is sold (its size is the game's)", g17.pm_ext ~= nil)
T("a part's price is the game's for that weapon", ids.b_supp.normal == 3000 and g17.b_supp.normal == 1500
  and ids.s_infamous.normal == 5000, g17.b_supp.normal)
factor_roll.s_holo = 5 / 6
T("  changed by the day, each part its own", P.Price("amcar", "s_holo") == 1200 and P.Price("amcar", "s_red") == 1000,
  P.Price("amcar", "s_holo"))
factor_roll.s_holo = nil
T("a part's size and weight by its type", P.MakeData("b_supp").w == 2 and P.MakeData("g_vert").weight == 0.4
  and P.MakeData("m_ext").h == 2 and P.MakeData("s_holo").weight == 0.3 and P.MakeData("x_skin").w == 1)
local before = money
local ok, d = buy("amcar", "b_supp")
local lc = where_part("b_supp")
T("Buy: the part is in the locker, paid", ok and lc == "locker" and money == before - 3000, money)
T("  its data: its type, size, weight, the weapon it was bought for, its own uid",
  d.ptype == "barrel_ext" and d.w == 2 and d.h == 1 and d.weight == 0.5 and d.for_weapon == "amcar"
  and (tonumber(d.uid) or 0) > 0 and d.uid ~= amcar.uid)
T("  it weighs", PDTI.ItemWeight(part_items("b_supp")[1].item) == 0.5)
T("not for sale for this weapon: refused", buy("amcar", "pm_ext") == false and buy("amcar", "s_dlc") == false)
money = 10
local okm, whym = buy("amcar", "s_red")
T("  not enough money: refused", okm == false and whym:find("money") ~= nil and #part_items("s_red") == 0)
money = 1000000
PDTI.session_only = true
local okh, whyh = buy("amcar", "s_red")
T("  in a heist the market is closed", okh == false and whyh:find("heist") ~= nil)
PDTI.session_only = false
for i = 1, 1000 do
  if not PDTI.AddItemAuto("locker", P.ITEM_ID, 1, P.MakeData("s_red", "amcar", 9000 + i), false) then break end
end
before = money
local n_deducts = deducts
local okf, whyf = buy("amcar", "s_holo")
T("  a full locker: refused before paying", okf == false and whyf:find("full") ~= nil and money == before
  and deducts == n_deducts)
clear_filler()
do
  -- The locker had room, then the part could not be put in: paid back.
  local real_add = PDTI.AddItemAuto
  PDTI.AddItemAuto = function() return false, "no free space" end
  before = money
  local okx = buy("amcar", "s_holo")
  PDTI.AddItemAuto = real_add
  T("  a part that could not be put in after all: paid back", okx == false and money == before, money - before)
end

------------------------------------------------------------------ fitting

fresh()
amcar = A.HandItem("primaries").data
buy("amcar", "s_holo")
local okfit, msg = fit("s_holo", amcar.uid)
local b1 = bp(amcar.uid)
T("a part onto the AMCAR in PRI: fitted, the part item gone", okfit and has(b1, "s_holo") and #part_items("s_holo") == 0, msg)
T("  its own sight just goes (no item)", not has(b1, "amcar_irons") and #part_items("amcar_irons") == 0)
T("  the game's weapon (its slot) has it", crafted.primaries[1] and has(crafted.primaries[1].blueprint, "s_holo"))
T("  said so", tostring(msg):find("s_holo", 1, true) ~= nil and tostring(msg):find("AMCAR", 1, true) ~= nil, msg)
buy("amcar", "s_red")
local okr, msgr = fit("s_red", amcar.uid)
T("another sight: the first comes off as an item (into the locker: PRI holds only the weapon)", okr
  and has(bp(amcar.uid), "s_red") and not has(bp(amcar.uid), "s_holo") and where_part("s_holo") == "locker", msgr)
T("  said so", tostring(msgr):find("off: s_holo", 1, true) ~= nil, msgr)
local okd, whyd = fit("s_holo", glock.uid)
T("a part the weapon does not take: refused", okd == false and tostring(whyd):find("does not fit", 1, true) ~= nil
  and where_part("s_holo") == "locker", whyd)
buy("amcar", "s_infamous")
local _, m4x = A.Buy("new_m4")
local okin, whyin = fit("s_infamous", m4x.uid)
T("  a sight the CAR-4 does not list (it takes other sights): refused", okin == false
  and tostring(whyin):find("does not fit", 1, true) ~= nil, whyin)
PDTI.RemoveItem(where_part("s_infamous"))
PDTI.RemoveItem(weapon(m4x.uid))
buy("amcar", "s_red")
local oka, whya = fit("s_red", amcar.uid)
T("a part it has already: refused", oka == false and tostring(whya):find("already", 1, true) ~= nil, whya)
PDTI.RemoveItem(where_part("s_red"))
buy("amcar", "g_vert")
fit("g_vert", amcar.uid)
buy("amcar", "st_folding")
local okfo, msgfo = fit("st_folding", amcar.uid)
local b2 = bp(amcar.uid)
T("a stock that does not go with the grip: the grip comes off", okfo and has(b2, "st_folding")
  and not has(b2, "g_vert") and #part_items("g_vert") == 1, msgfo)
T("  its own stock just goes", not has(b2, "amcar_stock") and #part_items("amcar_stock") == 0)
local okb, whyb = fit("g_vert", amcar.uid)
T("then the grip is refused: the stock is in the way", okb == false
  and tostring(whyb):find("take the st_folding off", 1, true) ~= nil, whyb)
local light = PDTI.ItemWeight(A.HandItem("primaries"))
buy("amcar", "st_tactical")
fit("st_tactical", amcar.uid)
T("a heavier part: the weapon weighs more (its concealment)", PDTI.ItemWeight(A.HandItem("primaries")) > light,
  PDTI.ItemWeight(A.HandItem("primaries")) .. " vs " .. light)
-- No room for all that comes off: nothing changes. (The tactical stock and
-- the grip on, the folding stock pushes both off; only one fits where the
-- folding stock was.)
fit("g_vert", amcar.uid)
buy("amcar", "st_folding")
local fc = where_part("st_folding")
local n_folding = #part_items("st_folding")
local fit_before = A.HandItem("primaries").data.blueprint
local parts_before = #part_items("st_tactical") + #part_items("g_vert")
fill_all()
local okn, whyn = fit("st_folding", amcar.uid)
T("no room for all that comes off: refused, nothing changes", okn == false and tostring(whyn):find("no room", 1, true) ~= nil
  and A.HandItem("primaries").data.blueprint == fit_before and where_part("st_folding") == fc
  and #part_items("st_folding") == n_folding, whyn)
T("  (none of them came off)", #part_items("st_tactical") + #part_items("g_vert") == parts_before)
clear_filler()
PDTI.session_only = true
local okhh = P.CanFit(P.MakeData("s_holo"), A.HandItem("primaries").data)
local okhm, whyhm = P.CanFit(P.MakeData("pm_ext"), A.HandItem("secondaries").data)
T("in a heist a sight can be changed (timed: armory_hotmod.lua), a magazine not", okhh == true and okhm == false
  and tostring(whyhm):find("magazines are changed at home", 1, true) ~= nil, whyhm)
PDTI.session_only = false
T("a part onto a weapon in the locker: no game slot changes", (function()
  local _, m4 = A.Buy("new_m4")
  local slot_before = crafted.primaries[1].blueprint
  local okm4 = fit("s_holo", m4.uid)
  return okm4 and has(bp(m4.uid), "s_holo") and crafted.primaries[1].blueprint == slot_before
end)())

-- A pistol's magazine part: the magazine it keeps takes the new size (the
-- size the game told for that build).
do
  local gc, gid = weapon(glock.uid)
  local x, y, rot = PDTI.FindFreeSpace("locker", PDTI.FindItem(gc, gid), true)
  PDTI.MoveItem(gc, gid, "locker", x, y, rot)
  gc, gid = weapon(glock.uid)
  PDTI.EditItems({ update = { { container = gc, instance_id = gid, data = { gun_set = 1, gun_n = 1, gun1_rounds = 17 } } } })
  Plan.RememberWeapon({ _name_id = "glock_17", _blueprint = { "g17_slide", "pm_ext" } }, { capacity = 33, mag_class = "pistol" })
  buy("glock_17", "pm_ext")
  local okp = fit("pm_ext", glock.uid)
  local _, _, gd = weapon(glock.uid)
  T("a pistol's extended magazine: the magazine it keeps is the new size", okp and gd.gun1_rounds == 33, gd.gun1_rounds)
  T("  (only a weapon that keeps one)", Plan.ReshapeStored(amcar.uid) == false)
end

------------------------------------------------------------ the weapon view

do
  T("a slot's name: the game's type named, an unknown one from its id", P.TypeName("barrel_ext") == "Muzzle"
    and P.TypeName("rail_mount") == "Rail mount", P.TypeName("rail_mount"))
  FP.zz_custom = { type = "custom" }
  FP.aa_extra = { type = "extra" }
  FP.mm_rail = { type = "rail_mount" }
  local list = P.OnWeapon({ weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar",
    blueprint = "mm_rail,aa_extra,zz_custom,amcar_mag,amcar_irons" })
  local order = {}
  for i, f in ipairs(list) do order[i] = f.part_id end
  T("every part on it: the known slots first in their order, the rest by slot name",
    table.concat(order, ",") == "amcar_irons,amcar_mag,zz_custom,aa_extra,mm_rail", table.concat(order, ","))
  local plain = A.MakeData("amcar", nil, 1)
  local st = {}
  for i, s in ipairs(P.Slots(plain)) do st[i] = s.ptype .. ":" .. tostring(s.part_id) end
  T("its slots: one for each part on it, an empty one for each kind for sale, in the same order", table.concat(st, ",")
    == "sight:amcar_irons,barrel:amcar_barrel,barrel_ext:nil,lower_reciever:amcar_body,vertical_grip:nil,"
    .. "stock:amcar_stock,magazine:amcar_mag,gadget:nil", table.concat(st, ","))
  T("  an empty slot is its kind alone", (function()
    for _, s in ipairs(P.Slots(plain)) do
      if s.ptype == "gadget" then return s.part_id == nil and s.removable == nil and s.standard == nil end
    end
  end)())
  T("  (no weapon: no slots)", #P.Slots(nil) == 0)
  -- An empty slot that sorts last but comes first of the empty ones: the
  -- game's sort may hold it up against itself (it has no part).
  part("bo_boost", "bonus")
  W.test_b = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "Boosted", CLIP_AMMO_MAX = 10 }
  FACTORY.test_b, PRICE.test_b = "wpn_test_b", 1000
  part("fg_rail", "foregrip")
  part("gr_pro", "grip")
  PARTS_BY.wpn_test_b = { sight = { "amcar_irons" }, bonus = { "bo_boost" }, foregrip = { "fg_rail" }, grip = { "gr_pro" } }
  DEFAULT.wpn_test_b = { "amcar_irons" }
  local ok_sort, slots_b = pcall(P.Slots, A.MakeData("test_b", nil, 2))
  local sb = {}
  for i, s in ipairs(ok_sort and slots_b or {}) do sb[i] = s.ptype end
  T("  empty slots sort among themselves too", ok_sort and table.concat(sb, ",") == "sight,foregrip,grip,bonus",
    ok_sort and table.concat(sb, ",") or slots_b)
end

-------------------------------------------------------------- taking off

fresh()
amcar = A.HandItem("primaries").data
buy("amcar", "s_red")
fit("s_red", amcar.uid)
local okt, msgt = take_off(amcar.uid, "s_red")
T("a sight taken off: its own comes back, the part into the locker", okt and has(bp(amcar.uid), "amcar_irons")
  and not has(bp(amcar.uid), "s_red") and where_part("s_red") == "locker", msgt)
T("  said so", tostring(msgt):find("s_red", 1, true) ~= nil, msgt)
buy("amcar", "gd_laser")
fit("gd_laser", amcar.uid)
T("a laser (the weapon has none of its own): it just comes off", take_off(amcar.uid, "gd_laser")
  and not has(bp(amcar.uid), "gd_laser") and where_part("gd_laser") == "locker")
local okown, whyown = take_off(amcar.uid, "amcar_body")
T("the weapon's own part does not come off", okown == false and tostring(whyown):find("own part", 1, true) ~= nil, whyown)
T("a part not on it: refused", take_off(amcar.uid, "s_holo") == false)
do
  local wc, wid = weapon(amcar.uid)
  PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = {
    blueprint = A.JoinBlueprint({ "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag", "x_skin" }) } } } })
end
local fitted = P.Fitted(A.HandItem("primaries").data)
T("Inspect's list: the parts beyond its own (a skin's part stays on)", #fitted == 1 and fitted[1].part_id == "x_skin"
  and fitted[1].removable == false)
do
  -- A sight that is no item (a skin's) replaced: it just goes.
  local wc, wid = weapon(amcar.uid)
  PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = {
    blueprint = A.JoinBlueprint({ "amcar_body", "amcar_barrel", "amcar_stock", "s_skin", "amcar_mag", "x_skin" }) } } } })
  buy("amcar", "s_red")
  local okss = fit("s_red", amcar.uid)
  T("a sight that is no item replaced: it just goes", okss and has(bp(amcar.uid), "s_red") and #part_items("s_skin") == 0)
  take_off(amcar.uid, "s_red")
  PDTI.RemoveItem(where_part("s_red"))
end
local oks, whys = take_off(amcar.uid, "x_skin")
T("  it does not come off", oks == false and tostring(whys):find("comes with", 1, true) ~= nil, whys)
buy("amcar", "b_supp")
fit("b_supp", amcar.uid)
fill_all()
local okn2, whyn2 = take_off(amcar.uid, "b_supp")
T("no room for the part: it stays on", okn2 == false and has(bp(amcar.uid), "b_supp"), whyn2)
clear_filler()
do
  -- A weapon in the backpack: what comes off stays next to it.
  local _, m4 = A.Buy("new_m4")
  local mc, mid = weapon(m4.uid)
  local x, y, rot = PDTI.FindFreeSpace("backpack", PDTI.FindItem(mc, mid), true)
  PDTI.MoveItem(mc, mid, "backpack", x, y, rot)
  buy("new_m4", "s_holo")
  fit("s_holo", m4.uid)
  take_off(m4.uid, "s_holo")
  T("off a weapon in the backpack: the part stays in the backpack", where_part("s_holo") == "backpack")
end

------------------------------------------- out of its slot (0.38.2)

fresh()
amcar = A.HandItem("primaries").data
buy("amcar", "b_supp")
fit("b_supp", amcar.uid)
do
  local wc, wid = weapon(amcar.uid)
  local okto, msgto = P.TakeOff(wc, wid, "b_supp", "backpack", 3, 2, true)
  local e = part_items("b_supp")[1]
  T("taken off onto a cell: the part is there, turned as it was dragged", okto and e and e.container == "backpack"
    and e.item.x == 3 and e.item.y == 2 and e.item.rotated == true and not has(bp(amcar.uid), "b_supp"), msgto)
  T("  said so", tostring(msgto):find("Off the AMCAR: b_supp", 1, true) ~= nil, msgto)
  fit("b_supp", amcar.uid)
  PDTI.AddItem("backpack", "bandage", 5, 0, false, 1)
  local items_before = #PDTI.GetContainerInfo("backpack").items
  local okocc, whyocc = P.TakeOff(wc, wid, "b_supp", "backpack", 4, 0, false)
  T("  onto a taken cell: it stays on, nothing added", okocc == false and has(bp(amcar.uid), "b_supp")
    and #PDTI.GetContainerInfo("backpack").items == items_before and #part_items("b_supp") == 0, whyocc)
  T("  not into the pockets", P.TakeOff(wc, wid, "b_supp", "pockets", 0, 0, false) == false and has(bp(amcar.uid), "b_supp"))
  T("  not into a weapon slot", P.TakeOff(wc, wid, "b_supp", "hand_secondary", 0, 0, false) == false
    and has(bp(amcar.uid), "b_supp"))
end
do
  -- A weapon whose own grip does not go with a laser: the laser comes off
  -- with the grip that let it on, next to the weapon.
  W.test_w = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "Tester", CLIP_AMMO_MAX = 30 }
  FACTORY.test_w, PRICE.test_w = "wpn_test", 1000
  part("t_grip_std", "grip", { pc = 1 }, { forbids = { "t_laser" } })
  part("t_grip_pro", "grip")
  part("t_laser", "gadget")
  PARTS_BY.wpn_test = { grip = { "t_grip_std", "t_grip_pro" }, gadget = { "t_laser" } }
  DEFAULT.wpn_test = { "t_grip_std" }
  local _, tw = PDTI.AddItemAuto("locker", "weapon", 1, A.MakeData("test_w", { "t_grip_pro", "t_laser" }, 7777), true)
  local okt2, msgt2 = P.TakeOff("locker", tw.instance_id, "t_grip_pro", "backpack", 0, 4, false)
  local g, l = part_items("t_grip_pro")[1], part_items("t_laser")[1]
  T("out of its slot: the other part that comes off goes next to the weapon", okt2 and g and g.container == "backpack"
    and g.item.x == 0 and g.item.y == 4 and l and l.container == "locker"
    and A.SplitBlueprint(PDTI.FindItem("locker", tw.instance_id).data.blueprint)[1] == "t_grip_std", msgt2)
  PDTI.RemoveItem(g.container, g.item.instance_id)
  PDTI.RemoveItem(l.container, l.item.instance_id)
  PDTI.EditItems({ update = { { container = "locker", instance_id = tw.instance_id, data = { blueprint = "t_grip_pro,t_laser" } } } })
  fill_all()
  clear_filler()
  -- Everything full but one backpack cell: no room for the laser.
  fill_all()
  local free_c = PDTI.FindItems(function(c, it) return c == "backpack" and it.item_id == P.ITEM_ID end)[1].item
  PDTI.RemoveItem("backpack", free_c.instance_id)
  local okt3, whyt3 = P.TakeOff("locker", tw.instance_id, "t_grip_pro", "backpack", free_c.x, free_c.y, false)
  T("  no room for it: nothing comes off, the cell stays free", okt3 == false
    and PDTI.FindItem("locker", tw.instance_id).data.blueprint == "t_grip_pro,t_laser" and #part_items("t_grip_pro") == 0
    and PDTI.CanPlace("backpack", P.ITEM_ID, free_c.x, free_c.y, false) == true, whyt3)
  clear_filler()
  PDTI.RemoveItem("locker", tw.instance_id)
end
do
  -- The screen's slot drag (ui_interaction.lua), without the screen.
  local wc, wid = weapon(amcar.uid)
  T("(a bandage at 5,0 of the backpack)", PDTI.FindItems(function(c, it) return c == "backpack" and it.item_id == "bandage"
    and it.x == 5 and it.y == 0 end)[1] ~= nil)
  local muzzle = { container = wc, instance_id = wid, ptype = "barrel_ext", part_id = "b_supp" }
  T("a press on your part's slot: it is dragged out (nothing is held)", PDTI.UISlotDragStart(muzzle) == true
    and PDTI.UIIsDragging() and PDTI.UIGetHeld() == nil and PDTI.UIGetSlotDrag().part_id == "b_supp")
  T("  the status says so", tostring(PDTI.UIGetStatusText()):find("Taking off: b_supp", 1, true) ~= nil, PDTI.UIGetStatusText())
  local pv = PDTI.UIDragPreview("backpack", 1, 1)
  T("  over a free cell: green, its size, from that cell", pv and pv.valid == true and pv.x == 1 and pv.y == 1
    and pv.w == 2 and pv.h == 1)
  PDTI.UIRotateHeld()
  pv = PDTI.UIDragPreview("backpack", 1, 1)
  T("  turned", pv and pv.w == 1 and pv.h == 2 and PDTI.UIGetSlotDrag().rotated == true)
  PDTI.UIRotateHeld()
  pv = PDTI.UIDragPreview("backpack", 4, 0)
  T("  over a taken cell: red", pv and pv.valid == false)
  T("  not into the pockets", PDTI.UIDragPreview("pockets", 0, 0).valid == false)
  T("let go outside the inventory: it stays on (never thrown away)", PDTI.UIDragDrop("outside") == false
    and has(bp(amcar.uid), "b_supp") and not PDTI.UIIsDragging())
  PDTI.UISlotDragStart(muzzle)
  T("  in the window: stays on", PDTI.UIDragDrop("window") == false and has(bp(amcar.uid), "b_supp"))
  PDTI.UISlotDragStart(muzzle)
  T("  on a slot: stays on", PDTI.UIDragDrop({ mod_slot = muzzle }) == false and has(bp(amcar.uid), "b_supp"))
  PDTI.UISlotDragStart(muzzle)
  local okd = PDTI.UIDragDrop({ container = "backpack", x = 4, y = 0 })
  T("  on a taken cell: stays on, and why", okd == false and has(bp(amcar.uid), "b_supp")
    and tostring(PDTI.UIGetStatus()):find("b_supp stays on", 1, true) ~= nil, PDTI.UIGetStatus())
  PDTI.UISlotDragStart(muzzle)
  okd = PDTI.UIDragDrop({ container = "backpack", x = 1, y = 1 })
  local e = part_items("b_supp")[1]
  T("  on a free cell: off, there", okd and e and e.container == "backpack" and e.item.x == 1 and e.item.y == 1
    and not has(bp(amcar.uid), "b_supp") and not PDTI.UIIsDragging()
    and tostring(PDTI.UIGetStatus()):find("Off the AMCAR", 1, true) ~= nil, PDTI.UIGetStatus())
  local sight = { container = wc, instance_id = wid, ptype = "sight", part_id = "amcar_irons" }
  T("the weapon's own part: not dragged, and why", PDTI.UISlotDragStart(sight) == false and not PDTI.UIIsDragging()
    and tostring(PDTI.UIGetStatus()):find("own part", 1, true) ~= nil, PDTI.UIGetStatus())
  local gadget = { container = wc, instance_id = wid, ptype = "gadget" }
  T("an empty slot: nothing to drag", PDTI.UISlotDragStart(gadget) == false
    and tostring(PDTI.UIGetStatus()):find("Gadget slot is empty", 1, true) ~= nil, PDTI.UIGetStatus())
  T("  a gone weapon: nothing", PDTI.UISlotDragStart({ container = "locker", instance_id = -5, ptype = "sight", part_id = "s_red" })
    == false)

  -- A part dragged onto a slot: fitted (its own kind only).
  local function drag_part(part_id)
    local c, id = where_part(part_id)
    local it = PDTI.FindItem(c, id)
    PDTI.UIDragStart(c, it.x, it.y)
    return c, id
  end
  drag_part("b_supp")
  local sp = PDTI.UISlotPreview(muzzle)
  T("a part over its slot: green", sp and sp.valid == true)
  sp = PDTI.UISlotPreview(sight)
  T("  over another slot: red, and where it goes", sp and sp.valid == false
    and tostring(sp.reason):find("goes in the Muzzle slot", 1, true) ~= nil, sp and sp.reason)
  local bc, bid = where_part("b_supp")
  T("  over a gone weapon's slot: nothing", PDTI.UISlotPreview({ container = "locker", instance_id = -5, ptype = "barrel_ext" }) == nil)
  T("  let go there: it stays where it was", PDTI.UIDragDrop({ mod_slot = sight }) == false
    and PDTI.FindItem(bc, bid) ~= nil and not has(bp(amcar.uid), "b_supp")
    and tostring(PDTI.UIGetStatus()):find("b_supp stays where it was: it goes in the Muzzle slot", 1, true) ~= nil,
    PDTI.UIGetStatus())
  drag_part("b_supp")
  T("  let go on its slot: fitted", PDTI.UIDragDrop({ mod_slot = muzzle }) == true and has(bp(amcar.uid), "b_supp")
    and #part_items("b_supp") == 0 and tostring(PDTI.UIGetStatus()):find("is on the AMCAR", 1, true) ~= nil,
    PDTI.UIGetStatus())
  buy("amcar", "st_folding")
  fit("st_folding", amcar.uid)
  buy("amcar", "g_vert")
  drag_part("g_vert")
  local vgrip = { container = wc, instance_id = wid, ptype = "vertical_grip" }
  sp = PDTI.UISlotPreview(vgrip)
  T("  a part a fitted one does not go with: red, and which", sp and sp.valid == false
    and tostring(sp.reason):find("take the st_folding off", 1, true) ~= nil, sp and sp.reason)
  PDTI.UIDragDrop({ mod_slot = vgrip })
  T("  let go there: it stays where it was", #part_items("g_vert") == 1 and not has(bp(amcar.uid), "g_vert"))
  local _, band = PDTI.AddItemAuto("pockets", "bandage", 1, nil, true)
  PDTI.UIDragStart("pockets", band.x, band.y)
  sp = PDTI.UISlotPreview(muzzle)
  T("not a part over a slot: red", sp and sp.valid == false and tostring(sp.reason):find("only a weapon part", 1, true) ~= nil)
  T("  let go there: it stays", PDTI.UIDragDrop({ mod_slot = muzzle }) == false and PDTI.FindItem("pockets", band.instance_id) ~= nil)
  T("nothing dragged: no slot preview", PDTI.UISlotPreview(muzzle) == nil)
  PDTI.UISlotDragStart(muzzle)
  T("  nor for a part out of its slot", PDTI.UISlotPreview(muzzle) == nil)
  PDTI.UICancelHeld()
  T("  (cancelled: nothing dragged)", not PDTI.UIIsDragging())

  -- Ctrl+click: off, next to the weapon.
  local okc, msgc = PDTI.UISlotTakeOff(muzzle)
  T("Ctrl+click on your part's slot: it comes off next to the weapon (PRI: the locker)", okc
    and where_part("b_supp") == "locker" and not has(bp(amcar.uid), "b_supp"), msgc)
  okc, msgc = PDTI.UISlotTakeOff(sight)
  T("  on the weapon's own: stays on, and why", okc == false and tostring(msgc):find("amcar_irons stays on", 1, true) ~= nil, msgc)
  local oke, msge = PDTI.UISlotTakeOff(gadget)
  T("  on an empty slot: nothing", oke == false and msge == "Nothing to take off there", msge)
  local stock = { container = wc, instance_id = wid, ptype = "stock", part_id = "st_folding" }
  PDTI.UIPickUp("pockets", band.instance_id)
  T("  with an item held: not until it is placed", PDTI.UISlotTakeOff(stock) == false and has(bp(amcar.uid), "st_folding"))
  PDTI.UICancelHeld()
  PDTI.UISlotDragStart(stock)
  T("  nor while a part is dragged out", PDTI.UIGetSlotDrag() ~= nil and PDTI.UISlotTakeOff(stock) == false
    and has(bp(amcar.uid), "st_folding"))
  PDTI.UICancelHeld()
  PDTI.UIPickUp("pockets", band.instance_id)
  PDTI.UISlotDragStart(stock)
  T("picking a part out of its slot lets go of a held item", PDTI.UIGetHeld() == nil and PDTI.UIGetSlotDrag() ~= nil)
  PDTI.UIPickUp("pockets", band.instance_id)
  T("  and picking up an item ends the slot drag", PDTI.UIGetSlotDrag() == nil and PDTI.UIGetHeld() ~= nil)
  PDTI.UISlotDragStart(stock)
  PDTI.UIResetInteraction()
  T("  (closing the screen ends it)", PDTI.UIGetSlotDrag() == nil and not PDTI.UIIsDragging())
  PDTI.RemoveItem("pockets", band.instance_id)
end

-------------------------------------- the gun in your hands (0.38.3)

do
  fresh()
  local am = A.HandItem("primaries").data
  -- The safehouse: a player holding the slots' weapons, made by the game at spawn.
  local real_job, real_player = managers.job, managers.player
  managers.job = { current_job_id = function() return "chill" end }
  local function unit(f) local b = { _factory_id = f }; return { base = function() return b end } end
  local inv = { sel = { [2] = { unit = unit("wpn_fps_ass_amcar") }, [1] = { unit = unit("wpn_fps_pis_g17") } }, eq = 2, added = {} }
  function inv:available_selections() return self.sel end
  function inv:equipped_selection() return self.eq end
  function inv:equip_selection(i) self.eq = i; return true end
  function inv:add_unit_by_factory_name(f, equip, instant, list)
    self.sel[f == "wpn_fps_pis_g17" and 1 or 2] = { unit = unit(f) }
    self.added[#self.added + 1] = { f = f, bp = list }
  end
  local player = { inventory = function() return inv end }
  managers.player = { player_unit = function() return player end }
  T("(the safehouse: not a heist)", A.InHeist() == false and PDTI.InHeist() == false)
  T("the safehouse: the guns the game made at spawn are your slots' (nothing made again)", A.ApplyHands() == false
    and #inv.added == 0)
  T("  they know their builds now", inv.sel[2].unit.base()._pdti_bp == A.HandItem("primaries").data.blueprint
    and inv.sel[1].unit.base()._pdti_bp == A.HandItem("secondaries").data.blueprint)
  buy("amcar", "s_red")
  local okf = fit("s_red", am.uid)
  T("a sight fitted to the AMCAR in PRI: the gun in your hands is made again with it, at once", okf
    and #inv.added == 1 and inv.added[1].f == "wpn_fps_ass_amcar" and has(inv.added[1].bp, "s_red"), #inv.added)
  T("  and knows its build", inv.sel[2].unit.base()._pdti_bp == A.HandItem("primaries").data.blueprint)
  T("  nothing again", A.ApplyHands() == false and #inv.added == 1)
  take_off(am.uid, "s_red")
  T("taken off: made again without it, its own sight back", #inv.added == 2 and not has(inv.added[2].bp, "s_red")
    and has(inv.added[2].bp, "amcar_irons"))
  T("  the pistol in SEC is never made again", (function()
    for _, a in ipairs(inv.added) do if a.f == "wpn_fps_pis_g17" then return false end end
    return true
  end)())
  local _, m4 = A.Buy("new_m4")
  buy("new_m4", "s_holo")
  fit("s_holo", m4.uid)
  T("a weapon in the locker changed: nothing in your hands made again", #inv.added == 2 and has(bp(m4.uid), "s_holo"))
  -- A heist (0.39.0): a part changed there makes the gun again too; one
  -- the game made (a picked-up one) is taken as it is.
  managers.job = nil
  PDTI.session_only = true
  do
    local wc, wid = weapon(am.uid)
    PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = { blueprint = A.JoinBlueprint({
      "amcar_body", "amcar_barrel", "amcar_stock", "s_red", "amcar_mag" }) } } } })
  end
  T("in a heist: a gun this mod made with another build is made again (a part changed in the heist)",
    A.ApplyHands() == true and #inv.added == 3 and has(inv.added[3].bp, "s_red"))
  inv.sel[2] = { unit = unit("wpn_fps_ass_amcar") } -- (one the game made: a picked-up one)
  do
    local wc, wid = weapon(am.uid)
    PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = { blueprint = A.JoinBlueprint({
      "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" }) } } } })
  end
  T("  one the game made is taken as it is (and learns its build)", A.ApplyHands() == false and #inv.added == 3
    and inv.sel[2].unit.base()._pdti_bp == A.HandItem("primaries").data.blueprint)
  PDTI.session_only = false
  managers.job, managers.player = real_job, real_player
end

------------------------------------------------------------------ selling

fresh()
amcar = A.HandItem("primaries").data
local okfree, whyfree = P.Sell(weapon(amcar.uid))
T("a free weapon is not sold", okfree == false and tostring(whyfree):find("free", 1, true) ~= nil and weapon(amcar.uid) ~= nil)
local _, m4 = A.Buy("new_m4")
buy("new_m4", "s_holo")
fit("s_holo", m4.uid)
local m4c, m4i = weapon(m4.uid)
local want = math.floor((40000 + 1000) * 0.5 + 0.5)
T("a weapon's price: half of today's, its parts with it", P.SellPrice(PDTI.FindItem(m4c, m4i)) == want,
  P.SellPrice(PDTI.FindItem(m4c, m4i)))
before = money
local oksell, msgsell = P.Sell(m4c, m4i)
T("  sold: paid, gone", oksell and money == before + want and weapon(m4.uid) == nil, msgsell)
buy("amcar", "b_supp")
before = money
local okps = P.Sell(where_part("b_supp"))
T("a part sold: half of today's price", okps and money == before + 1500 and #part_items("b_supp") == 0, money - before)
PDTI.session_only = true
T("in a heist nothing is sold", P.Sell(weapon(amcar.uid)) == false)
PDTI.session_only = false
-- A weapon's loaded magazine is paid back (as the Bring list pays one back).
do
  PDTI.SetAmmoPlanned(true)
  PDTI.SetPlanPaid(100000)
  local _, g2 = A.Buy("glock_17")
  local gc, gid = weapon(g2.uid)
  PDTI.EditItems({ update = { { container = gc, instance_id = gid, data = { gun_set = 1, gun_n = 1, gun1_rounds = 17 } } } })
  before = money
  local paid = PDTI.PlanPaid()
  local okg = P.Sell(gc, gid)
  local back = money - before - math.floor(5000 * 0.5 + 0.5)
  T("a weapon with its magazine: the magazine paid back too", okg and back > 0 and PDTI.PlanPaid() == paid - back, back)
  -- In your hands: its magazine is in the slot's box, and goes too.
  local _, m5 = A.Buy("new_m4")
  local ac, aid = weapon(amcar.uid)
  local x, y, rot = PDTI.FindFreeSpace("locker", PDTI.FindItem(ac, aid), true)
  PDTI.MoveItem(ac, aid, "locker", x, y, rot)
  local mc, mid = weapon(m5.uid)
  PDTI.MoveItem(mc, mid, "hand_primary", 0, 0, false)
  A.SyncEquipped()
  T("  (the game's slot: the CAR-4 in PRI)", crafted.primaries[1].weapon_id == "new_m4")
  local box = PDTI.GetContainerInfo("gun_primary").items
  T("  (the CAR-4 in PRI has its magazine in the box)", #box == 1 and box[1].data.weapon_uid == m5.uid)
  before = money
  local okh2 = P.Sell(weapon(m5.uid))
  T("  sold from your hands: its box magazine goes and is paid back", okh2 and money - before > 20000
    and #PDTI.GetContainerInfo("gun_primary").items == 0, money - before)
  T("  (sold for what it was worth)", okh2
    and #PDTI.GetContainerInfo("gun_primary").items == 0 and money - before > 20000, money - before)
  T("  the game's slot follows (the AMCAR, its default, again)", crafted.primaries[1] and crafted.primaries[1].weapon_id == "amcar")
  PDTI.SetAmmoPlanned(false)
end

------------------------------------------------------------------- death

fresh()
buy("amcar", "s_red")
buy("amcar", "b_supp")
do
  local c, id = where_part("b_supp")
  local x, y, rot = PDTI.FindFreeSpace("backpack", PDTI.FindItem(c, id), true)
  PDTI.MoveItem(c, id, "backpack", x, y, rot)
end
A.OnHeistStart()
local carried = part_items("b_supp")[1].item.data.uid
T("a heist: the parts you carry are brought", has(A._Data().brought, carried))
A.OnMissionEnd(false)
A.OnMenu()
T("a failed heist: the parts you carried are lost, the locker's kept", #part_items("b_supp") == 0
  and #part_items("s_red") == 1)
fresh()
buy("amcar", "b_supp")
do
  local c, id = where_part("b_supp")
  local x, y, rot = PDTI.FindFreeSpace("backpack", PDTI.FindItem(c, id), true)
  PDTI.MoveItem(c, id, "backpack", x, y, rot)
end
A.OnHeistStart()
A.OnMissionEnd(true)
A.OnMenu()
T("a won heist: they are kept", #part_items("b_supp") == 1)

-------------------------------------------------------------- the screen

;(function()
  fresh()
  local am = A.HandItem("primaries").data
  buy("amcar", "s_holo")
  local pc, pid = where_part("s_holo")
  local item = PDTI.FindItem(pc, pid)
  -- Dragging a part over a weapon: the weapon lights up.
  PDTI.UIDragStart(pc, item.x, item.y)
  local pv = PDTI.UIDragPreview("hand_primary", 0, 0)
  T("a part dragged over the AMCAR in PRI: PRI lights up, it fits", pv and pv.fit == true and pv.valid == true
    and pv.x == 0 and pv.y == 0 and pv.w == 1 and pv.h == 1)
  local pg = PDTI.UIDragPreview("hand_secondary", 0, 0)
  T("  over the Chimano: red, and why", pg and pg.fit and pg.valid == false
    and tostring(pg.reason):find("does not fit", 1, true) ~= nil, pg and pg.reason)
  local okdrop = PDTI.UIDragDrop({ container = "hand_primary", x = 0, y = 0 })
  T("let go on the AMCAR: fitted", okdrop and has(bp(am.uid), "s_holo") and #part_items("s_holo") == 0)
  T("  the status says so", tostring(PDTI.UIGetStatusText()):find("s_holo", 1, true) ~= nil, PDTI.UIGetStatusText())
  local _, m4 = A.Buy("new_m4")
  buy("amcar", "st_tactical")
  local rc, rid = where_part("st_tactical")
  local ri = PDTI.FindItem(rc, rid)
  local mc, mid = weapon(m4.uid)
  local mi = PDTI.FindItem(mc, mid)
  PDTI.UIDragStart(rc, ri.x, ri.y)
  local pm = PDTI.UIDragPreview(mc, mi.x + 1, mi.y)
  T("over a weapon in the locker: all of it lights up", pm and pm.fit and pm.x == mi.x and pm.y == mi.y
    and pm.w == 4 and pm.h == 2 and pm.valid == false)
  local okno = PDTI.UIDragDrop({ container = mc, x = mi.x + 1, y = mi.y })
  T("  let go there: it stays where it was", okno == false and PDTI.FindItem(rc, rid) ~= nil)
  T("  the status names the part and why", tostring(PDTI.UIGetStatusText()):find("st_tactical stays", 1, true) ~= nil
    and tostring(PDTI.UIGetStatusText()):find("does not fit", 1, true) ~= nil, PDTI.UIGetStatusText())
  buy("amcar", "gd_laser")
  local lc2, lid2 = where_part("gd_laser")
  local li = PDTI.FindItem(lc2, lid2)
  PDTI.UIDragStart(rc, ri.x, ri.y)
  local pp = PDTI.UIDragPreview(lc2, li.x, li.y)
  T("a part over another part: no fitting, just no room", pp and not pp.fit and pp.valid == false)
  PDTI.UICancelHeld()
  local _, band = PDTI.AddItemAuto("pockets", "bandage", 1, nil, true)
  T("Inspect is not opened for other things", band ~= nil and PDTI._UIInspect("pockets", band.x, band.y) == false)
  PDTI.session_only = true
  T("  nor in a heist for one in the locker (it stays at home)", mc == "locker" and PDTI._UIInspect(mc, mi.x, mi.y) == false)
  PDTI.session_only = false
  T("which of your weapons a part fits", table.concat(P.FitsYours("s_red"), ",") == "AMCAR,CAR-4",
    table.concat(P.FitsYours("s_red"), ","))

  -- The screen: the part's cell, Inspect, the market's parts.
  ENV.install_menuui(false)
  local function windows() return ENV.menus[#ENV.menus].children end
  local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
  local function shift_click(name)
    local real_input, real_id = rawget(_G, "Input"), rawget(_G, "Idstring")
    _G.Idstring = function(v) return v end
    _G.Input = { keyboard = function() return { down = function(_, k) return k == "left shift" end } end }
    for _, w in ipairs(windows()) do
      local c = w:find(name)
      if c then c:click() break end
    end
    _G.Input, _G.Idstring = real_input, real_id
  end
  T("the screen opens", PDTI.ToggleUI() == true)
  named("pdti_shop"):find("shop_tab_locker"):click()
  local cell = named("pdti_shop"):find(string.format("cell_%s_%d_%d", rc, ri.x, ri.y))
  T("a part's cell: its type, then its name", cell ~= nil and cell.params.text == "Stock\nst_tac.", cell and cell.params.text)
  local mcell = string.format("cell_%s_%d_%d", mc, mi.x, mi.y)
  shift_click(mcell)
  local shop = named("pdti_shop")
  T("Shift+click on a weapon: Inspect shows it", shop:find("inspect_label") ~= nil
    and shop:find("inspect_label").params.text:find("CAR-4", 1, true) ~= nil and PDTI.FindItem(mc, mid) ~= nil)
  T("  nothing was picked up", PDTI.UIGetHeld() == nil)
  named("pdti_shop"):find("inspect_close"):click()
  PDTI.UIPickUp(rc, rid)
  shift_click(mcell)
  T("  an item held before is let go (it stays where it was)", PDTI.UIGetHeld() == nil and PDTI.FindItem(rc, rid) ~= nil)
  -- The right mouse button (the game's "1"): the weapon view.
  local function right_press(target)
    local saved_hit, saved_id = PDTI._UIHit, rawget(_G, "Idstring")
    PDTI._UIHit = function() return target end
    _G.Idstring = function(v) return v end
    local r = ENV.menus[#ENV.menus].params.pre_mouse_press("1", 1, 1)
    PDTI._UIHit, _G.Idstring = saved_hit, saved_id
    return r
  end
  -- A colour (the tests' Color is its numbers).
  local function col(c) return type(c) == "table" and table.concat(c, ",") or tostring(c) end
  -- The weapon's slots: a box for each (inspect_slot_<i>).
  local function texts()
    local out = {}
    for i = 1, 40 do
      local r = named("pdti_shop"):find("inspect_slot_" .. i)
      if not r then break end
      out[i] = tostring(r.params.text)
    end
    return out
  end
  local rows = texts()
  T("  its slots, each a box: the CAR-4's own part, its empty sight slot", table.concat(rows, "|")
    == "Sight\nempty|Lower receiver\nstandard", table.concat(rows, "|"))
  T("  no Take off buttons", named("pdti_shop"):find("inspect_off_1") == nil)
  T("  the help says how", tostring(named("pdti_shop"):find("inspect_slots_help").params.text):find("Ctrl+click", 1, true) ~= nil)
  T("  its weight and concealment", tostring(named("pdti_shop"):find("inspect_weight").params.text):find("concealment 30", 1, true) ~= nil,
    named("pdti_shop"):find("inspect_weight").params.text)
  T("  and its price", tostring(shop:find("inspect_sell").params.text):find("Sell for", 1, true) ~= nil)
  shop:find("inspect_close"):click()
  T("Close: the tab again", named("pdti_shop"):find("inspect_label") == nil
    and named("pdti_shop"):find("locker_grid_label") ~= nil)
  buy("new_m4", "s_red")
  fit("s_red", m4.uid)
  shift_click(mcell)
  shop = named("pdti_shop")
  T("  a fitted part is in its slot", table.concat(texts(), "|") == "Sight\ns_red|Lower receiver\nstandard",
    table.concat(texts(), "|"))
  T("  its slots around the picture: the sight on top of it, the lower receiver under it", (function()
    local one, two = shop:find("inspect_slot_1").params, shop:find("inspect_slot_2").params
    local top_label = shop:find("inspect_slots_top").params
    local bottom_label = shop:find("inspect_slots_bottom").params
    local help = shop:find("inspect_slots_help").params
    return one.position[2] >= top_label.position[2] and one.position[2] < bottom_label.position[2]
      and two.position[2] >= bottom_label.position[2]
      and help.position[2] >= bottom_label.position[2]
  end)())
  T("  your part's box has a part's colour, the weapon's own is grey", (function()
    local mine, own = shop:find("inspect_slot_1").params.background_color, shop:find("inspect_slot_2").params.background_color
    return mine ~= nil and own ~= nil and col(mine) ~= col(own)
  end)())
  T("  the count", tostring(shop:find("inspect_parts_label").params.text) == "Slots  (2; 1 part(s) of yours)",
    shop:find("inspect_parts_label").params.text)
  local function with_ctrl(fn)
    local real_input, real_id = rawget(_G, "Input"), rawget(_G, "Idstring")
    _G.Idstring = function(v) return v end
    _G.Input = { keyboard = function() return { down = function(_, k) return k == "left ctrl" end } end }
    local r = fn()
    _G.Input, _G.Idstring = real_input, real_id
    return r
  end
  shop:find("inspect_slot_2"):click()
  T("a click on a slot: nothing comes off, the status says how", has(bp(m4.uid), "s_red")
    and tostring(PDTI.UIGetStatusText()):find("Drag it out of its slot", 1, true) ~= nil, PDTI.UIGetStatusText())
  with_ctrl(function() named("pdti_shop"):find("inspect_slot_1"):click() end)
  T("Ctrl+click on the sight's slot: it comes off (an item again), the slot empty", not has(bp(m4.uid), "s_red")
    and #part_items("s_red") == 1 and tostring(named("pdti_shop"):find("inspect_slot_1").params.text) == "Sight\nempty")
  T("  the view says so", named("pdti_shop"):find("inspect_status") ~= nil
    and tostring(named("pdti_shop"):find("inspect_status").params.text):find("Off the CAR-4", 1, true) ~= nil)
  -- The mouse: a press on a slot drags its part out; let go on a cell, it is there.
  local menu = ENV.menus[#ENV.menus]
  local function mouse(kind, target, ctrl)
    local saved_hit, saved_id, saved_input = PDTI._UIHit, rawget(_G, "Idstring"), rawget(_G, "Input")
    PDTI._UIHit = function() return target end
    _G.Idstring = function(v) return v end
    _G.Input = { keyboard = function() return { down = function(_, k) return ctrl and k == "left ctrl" end } end }
    local r
    if kind == "press" then r = menu.params.pre_mouse_press("0", 1, 1)
    elseif kind == "move" then r = menu.params.pre_mouse_move(1, 1)
    else r = menu.params.pre_mouse_release("0", 1, 1) end
    PDTI._UIHit, _G.Idstring, _G.Input = saved_hit, saved_id, saved_input
    return r
  end
  fit("s_red", m4.uid)
  PDTI.RedrawUI()
  local lifted_before = named("pdti_shop"):find("inspect_slot_1").params.background_color
  local own_before = named("pdti_shop"):find("inspect_slot_2").params.background_color
  T("(the sight on it again)", tostring(named("pdti_shop"):find("inspect_slot_1").params.text) == "Sight\ns_red")
  local pr = mouse("press", PDTI._UISlotHit(1))
  T("a press on the sight's slot: it is dragged out (the click is swallowed)", pr == false
    and PDTI.UIGetSlotDrag() ~= nil and PDTI.UIGetSlotDrag().part_id == "s_red")
  T("  its box shows it lifted, the others as they were", col(named("pdti_shop"):find("inspect_slot_1").params.background_color)
    ~= col(lifted_before) and col(named("pdti_shop"):find("inspect_slot_2").params.background_color) == col(own_before))
  local free_x, free_y = PDTI.FindFreeSpace("locker", { item_id = P.ITEM_ID, data = P.MakeData("s_red") }, false)
  mouse("release", { container = "locker", x = free_x, y = free_y })
  local sr = part_items("s_red")[1]
  T("  let go on a free locker cell: off, there", sr and sr.container == "locker" and sr.item.x == free_x
    and sr.item.y == free_y and not has(bp(m4.uid), "s_red") and not PDTI.UIIsDragging())
  T("  the view says so", tostring(named("pdti_shop"):find("inspect_status").params.text):find("Off the CAR-4", 1, true) ~= nil)
  -- A part dragged over its slot lights the slot up; let go there, it is fitted.
  mouse("press", { container = "locker", x = free_x, y = free_y })
  mouse("move", PDTI._UISlotHit(1))
  local lit = named("pdti_shop"):find("inspect_slot_1").rects
  T("the sight dragged over its slot: the slot lights up green", lit ~= nil and #lit == 1
    and col(lit[1].params.color) == col(Color(0.25, 0.85, 0.35)))
  mouse("move", PDTI._UISlotHit(2))
  lit = named("pdti_shop"):find("inspect_slot_2").rects
  T("  over another slot: red", lit ~= nil and #lit == 1 and col(lit[1].params.color) == col(Color(0.9, 0.25, 0.2))
    and #(named("pdti_shop"):find("inspect_slot_1").rects or {}) == 0)
  mouse("release", PDTI._UISlotHit(1))
  T("  let go on its slot: fitted", has(bp(m4.uid), "s_red") and #part_items("s_red") == 0
    and tostring(named("pdti_shop"):find("inspect_slot_1").params.text) == "Sight\ns_red")
  T("  the view says so", tostring(named("pdti_shop"):find("inspect_status").params.text):find("is on the CAR-4", 1, true) ~= nil)
  mouse("press", PDTI._UISlotHit(1), true)
  T("Ctrl and a press on the slot: off, nothing dragged", not has(bp(m4.uid), "s_red") and #part_items("s_red") == 1
    and not PDTI.UIIsDragging())
  T("a right press on a slot: left alone", right_press(PDTI._UISlotHit(1)) == nil and named("pdti_shop"):find("inspect_label") ~= nil)
  mouse("press", PDTI._UISlotHit(2))
  T("a press on the weapon's own part: not dragged, the view says why", not PDTI.UIIsDragging()
    and tostring(named("pdti_shop"):find("inspect_status").params.text):find("own part", 1, true) ~= nil)
  T("  (a slot's hit: none past the last)", PDTI._UISlotHit(3) == nil)
  -- Let go over the middle window, not on a cell: it stays (it is the inventory too).
  do
    local real_hit = PDTI._UIHit
    local mid = named("pdti_shop")
    mid.MouseInside = function() return true end
    T("the middle window is the inventory: let go there, an item stays", real_hit(1, 1) == "window")
    mid.MouseInside = nil
    T("  (outside every window: outside)", real_hit(1, 1) == "outside")
    local box = named("pdti_shop"):find("inspect_slot_1")
    box.MouseInside = function() return true end
    local h = real_hit(1, 1)
    T("the mouse over a slot's box: that slot", type(h) == "table" and h.mod_slot ~= nil and h.mod_slot.ptype == "sight"
      and h.container == nil)
    box.MouseInside = nil
  end
  local before_sell = money
  named("pdti_shop"):find("inspect_sell"):click()
  T("Sell, once: it asks again, nothing sold", weapon(m4.uid) ~= nil and money == before_sell
    and tostring(named("pdti_shop"):find("inspect_sell").params.text):find("again", 1, true) ~= nil)
  named("pdti_shop"):find("inspect_sell"):click()
  T("  twice: sold, Inspect closed", weapon(m4.uid) == nil and money > before_sell
    and named("pdti_shop"):find("inspect_label") == nil)
  do
    local wc, wid = weapon(am.uid)
    PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = {
      blueprint = A.JoinBlueprint({ "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag", "x_skin" }) } } } })
  end
  FP.amcar_irons.name_id = "Iron Sights"
  shift_click("weapon_box_primary")
  T("the free AMCAR: no price", tostring(named("pdti_shop"):find("inspect_sell").params.text):find("nothing", 1, true) ~= nil)
  rows = texts()
  T("  an empty slot's box is darker than one with the weapon's own part", (function()
    local empty, own = named("pdti_shop"):find("inspect_slot_3").params.background_color,
      named("pdti_shop"):find("inspect_slot_4").params.background_color
    return own[1] + own[2] + own[3] > empty[1] + empty[2] + empty[3]
  end)())
  T("  every slot, in order: the ones on top of the weapon first, then the ones under it", table.concat(rows, "|")
    == "Sight\nIron Sights|Gadget\nempty|Vertical grip\nempty|Stock\nstandard|Magazine\nstandard"
    .. "|Custom\nx_skin (fixed)|Muzzle\nempty|Barrel\nstandard|Lower receiver\nstandard", table.concat(rows, "|"))
  T("  the count", tostring(named("pdti_shop"):find("inspect_parts_label").params.text) == "Slots  (9; 0 part(s) of yours)",
    named("pdti_shop"):find("inspect_parts_label").params.text)
  FP.amcar_irons.name_id = "amcar_irons"
  named("pdti_shop"):find("inspect_close"):click()
  do
    -- A weapon with many parts (the game's have up to about 20): the view fits 720p.
    local wc, wid = weapon(am.uid)
    local many = { "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" }
    for i = 1, 17 do many[#many + 1] = "z_extra_" .. i end
    PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = { blueprint = A.JoinBlueprint(many) } } } })
    shift_click("weapon_box_primary")
    local h = named("pdti_shop").ph
    T("a weapon with 22 parts: 25 slots, the view fits 720p", named("pdti_shop"):find("inspect_slot_25") ~= nil
      and named("pdti_shop"):find("inspect_slot_26") == nil and h <= 720, h)
    named("pdti_shop"):find("inspect_close"):click()
    PDTI.EditItems({ update = { { container = wc, instance_id = wid, data = {
      blueprint = A.JoinBlueprint({ "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag", "x_skin" }) } } } })
    shift_click("weapon_box_primary")
  end
  -- A press with Shift (the drag's own path): Inspect, no drag.
  named("pdti_shop"):find("inspect_close"):click()
  local real_hit = PDTI._UIHit
  PDTI._UIHit = function() return { container = "hand_primary", x = 0, y = 0 } end
  local real_input, real_id = rawget(_G, "Input"), rawget(_G, "Idstring")
  _G.Idstring = function(v) return v end
  _G.Input = { keyboard = function() return { down = function(_, k) return k == "left shift" end } end }
  ENV.menus[#ENV.menus].params.pre_mouse_press("0", 1, 1)
  _G.Input, _G.Idstring = real_input, real_id
  PDTI._UIHit = real_hit
  T("a press with Shift: Inspect, nothing dragged", not PDTI.UIIsDragging()
    and named("pdti_shop"):find("inspect_label") ~= nil)
  named("pdti_shop"):find("inspect_close"):click()
  local rp = right_press({ container = "hand_primary", x = 0, y = 0 })
  T("a right click on the AMCAR in PRI: its view, every part on it", rp == false
    and tostring(named("pdti_shop"):find("inspect_label").params.text):find("AMCAR", 1, true) ~= nil
    and named("pdti_shop"):find("inspect_slot_1") ~= nil and not PDTI.UIIsDragging() and PDTI.UIGetHeld() == nil)
  named("pdti_shop"):find("inspect_close"):click()
  local pr2c, pr2i = where_part("s_red")
  local pr2 = PDTI.FindItem(pr2c, pr2i)
  T("  on a part: the part's view", right_press({ container = pr2c, x = pr2.x, y = pr2.y }) == false
    and named("pdti_shop"):find("inspect_part_fits") ~= nil)
  named("pdti_shop"):find("inspect_close"):click()
  local _, band2 = PDTI.AddItemAuto("pockets", "bandage", 1, nil, true)
  T("  on anything else: left alone", right_press({ container = "pockets", x = band2.x, y = band2.y }) == nil
    and named("pdti_shop"):find("inspect_label") == nil and PDTI.UIGetHeld() == nil)
  T("  outside the cells: left alone", right_press("window") == nil)
  PDTI.UIDragStart(pr2c, pr2.x, pr2.y)
  T("  while dragging: left alone (the drag goes on)", right_press({ container = "hand_primary", x = 0, y = 0 }) == nil
    and PDTI.UIIsDragging() and named("pdti_shop"):find("inspect_label") == nil)
  PDTI.UIDragDrop("window")
  T("  the left button still picks up", (function()
    local saved_hit, saved_id = PDTI._UIHit, rawget(_G, "Idstring")
    PDTI._UIHit = function() return { container = pr2c, x = pr2.x, y = pr2.y } end
    _G.Idstring = function(v) return v end
    ENV.menus[#ENV.menus].params.pre_mouse_press("0", 1, 1)
    PDTI._UIHit, _G.Idstring = saved_hit, saved_id
    local dragging = PDTI.UIIsDragging()
    PDTI.UIDragDrop("window")
    return dragging and named("pdti_shop"):find("inspect_label") == nil
  end)())
  local rc2, rid2 = where_part("s_red")
  local r2 = PDTI.FindItem(rc2, rid2)
  shift_click(string.format("cell_%s_%d_%d", rc2, r2.x, r2.y))
  shop = named("pdti_shop")
  T("Shift+click on a part: what it is, which of your weapons it fits", shop:find("inspect_part_fits") ~= nil
    and tostring(shop:find("inspect_part_fits").params.text):find("AMCAR", 1, true) ~= nil, shop:find("inspect_part_fits")
    and shop:find("inspect_part_fits").params.text)
  PDTI.SetUIOpen(false)
  T("the market: a weapon's parts in a list", PDTI.OpenMarket() == true)
  named("pdti_shop"):find("market_tab_weapons"):click()
  windows()[1]:find("wmarket_prices"):find("wmarket_price_amcar"):click()
  local list = named("pdti_shop"):find("wmarket_parts")
  T("  under the AMCAR: its parts, each a row", list ~= nil and list:find("wmarket_part_b_supp") ~= nil
    and list:find("wmarket_part_a_slug") == nil, list and #list.children)
  list:find("wmarket_part_b_supp"):click()
  local buy_btn = named("pdti_shop"):find("wmarket_buy_part")
  T("  a click picks one: its Buy button", buy_btn ~= nil and tostring(buy_btn.params.text):find("b_supp", 1, true) ~= nil)
  T("  the list stays (not made again)", named("pdti_shop"):find("wmarket_parts") == list)
  local n_supp = #part_items("b_supp")
  buy_btn:click()
  T("Buy part: into the locker", #part_items("b_supp") == n_supp + 1)
  named("pdti_shop"):find("market_tab_loot"):click()
  T("the Loot tab: the parts list goes", named("pdti_shop"):find("wmarket_parts") == nil)
  T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
  PDTI.SetUIOpen(false)
end)()

-- 0.44.0: a dragged part marks green every weapon of yours that takes it.
;(function()
  fresh() -- the AMCAR in PRI, the Chimano in SEC
  A.Buy("new_m4") -- (the locker)
  buy("amcar", "s_red") -- the AMCAR and the CAR-4 take it
  buy("amcar", "b_supp") -- the AMCAR and the Chimano take it
  local function windows() return ENV.menus[#ENV.menus].children end
  local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
  T("the screen opens", PDTI.ToggleUI() == true)
  named("pdti_shop"):find("shop_tab_locker"):click()
  -- Which weapons the drawn cells with a mark belong to (their names).
  local function marked()
    local names, n = {}, 0
    local function walk(node)
      for _, c in ipairs(node.children or {}) do
        local cname = tostring(c.params and c.params.name or "")
        local cn, x, y = cname:match("^cell_(.+)_(%d+)_(%d+)$")
        local slot = cname:match("^weapon_box_(%a+)$") -- PRI, SEC: one cell
        if slot then cn, x, y = "hand_" .. slot, "0", "0" end
        for _, r in ipairs(c.rects or {}) do
          if r.params.name == "pdti_fit_mark" and cn then
            n = n + 1
            local id = PDTI.GetOccupancyMap(cn).cells[tonumber(y) + 1][tonumber(x) + 1]
            local it = id and PDTI.FindItem(cn, id)
            names[it and it.data and it.data.name or "?"] = true
          end
        end
        walk(c)
      end
    end
    for _, w in ipairs(windows()) do walk(w) end
    local list = {}
    for k in pairs(names) do list[#list + 1] = k end
    table.sort(list)
    return table.concat(list, ","), n
  end
  local menu = ENV.menus[#ENV.menus].params
  local real_hit = PDTI._UIHit
  PDTI._UIHit = function() return "window" end
  T("nothing held: no marks", PDTI.UIFitWeapons() == nil and select(2, marked()) == 0)
  local function drag(part_id)
    local c, id = where_part(part_id)
    local it = PDTI.FindItem(c, id)
    PDTI.UIDragStart(c, it.x, it.y)
    menu.pre_mouse_move(5, 5)
  end
  drag("s_red")
  local fits = PDTI.UIFitWeapons()
  local _, _, amcar = weapon(A.HandItem("primaries").data.uid)
  T("a sight held: the weapons that take it, wherever they are", fits ~= nil and fits.hand_primary ~= nil
    and fits.locker ~= nil and fits.hand_secondary == nil and amcar.weapon_id == "amcar")
  local names, n = marked()
  T("  marked green: the AMCAR (PRI) and the CAR-4 (locker), every cell of each, not the Chimano",
    names == "AMCAR,CAR-4" and n >= 9, names .. " " .. n)
  menu.pre_mouse_move(6, 6)
  T("  the mouse moves: marked once, not again on top", select(2, marked()) == n, select(2, marked()))
  menu.pre_mouse_release("0", 6, 6)
  T("  let go (in the window): the marks go, the part stays", select(2, marked()) == 0 and #part_items("s_red") == 1)
  drag("b_supp")
  T("a muzzle held: the AMCAR and the Chimano", (marked()) == "AMCAR,Chimano 88", (marked()))
  menu.pre_mouse_release("0", 6, 6)
  fit("s_red", amcar.uid)
  buy("amcar", "s_holo")
  drag("s_holo")
  T("  a weapon that has one of its kind on already: still marked", (marked()) == "AMCAR,CAR-4", (marked()))
  menu.pre_mouse_release("0", 6, 6)
  local _, band = PDTI.AddItemAuto("pockets", "bandage", 1, nil, true)
  PDTI.UIDragStart("pockets", band.x, band.y)
  menu.pre_mouse_move(5, 5)
  T("not a part held: no marks", PDTI.UIFitWeapons() == nil and select(2, marked()) == 0)
  menu.pre_mouse_release("0", 6, 6)
  T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
  PDTI._UIHit = real_hit
  PDTI.SetUIOpen(false)
end)()

-- 0.44.0: the game's own weapon mods (its drops) move into the locker.
;(function()
  fresh()
  local inv = { normal = { weapon_mods = { s_holo = 2, b_supp = 1, a_slug = 3, no_such_part = 1, x_skin = 1 } },
    gage_pack = { weapon_mods = { s_dlc = 1 } } }
  local saves = 0
  managers.savefile = { save_progress = function() saves = saves + 1 end }
  local bm = managers.blackmarket
  bm.get_inventory_category = function(_, cat)
    local t = {}
    for gv, cats in pairs(inv) do
      for id, n in pairs(cats[cat] or {}) do t[#t + 1] = { id = id, global_value = gv, amount = n } end
    end
    return t
  end
  bm.remove_item = function(_, gv, cat, id)
    local c = inv[gv] and inv[gv][cat]
    if not c or not c[id] or not MODS[id] then return false end
    c[id] = c[id] - 1
    if c[id] <= 0 then c[id] = nil end
    return true
  end
  bm.add_to_inventory = function(_, gv, cat, id)
    inv[gv] = inv[gv] or {}
    inv[gv][cat] = inv[gv][cat] or {}
    inv[gv][cat][id] = (inv[gv][cat][id] or 0) + 1
  end
  local function logged(text)
    for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then return true end end
    return false
  end
  local real_hint = PDTI.Hint
  local hints = {}
  PDTI.Hint = function(t) hints[#hints + 1] = t end
  _G.PDTI_SEPARATE_SAVE = nil
  T("the game's own save (not the mod's): its mods stay, said once", P.ImportGameMods() == 0
    and inv.normal.weapon_mods.s_holo == 2 and #part_items("s_holo") == 0 and logged("stay in its inventory"))
  _G.PDTI_SEPARATE_SAVE = true
  PDTI.session_only = true
  T("  in a heist: nothing", P.ImportGameMods() == 0 and inv.normal.weapon_mods.s_holo == 2)
  PDTI.session_only = false
  local moved, waiting = P.ImportGameMods()
  T("the mod's own save: every mod a part item in the locker", moved == 4 and waiting == 0
    and #part_items("s_holo") == 2 and #part_items("b_supp") == 1 and #part_items("s_dlc") == 1
    and where_part("s_holo") == "locker", moved .. "/" .. tostring(waiting))
  local dlc = part_items("s_dlc")[1].item.data
  T("  each its own item, with its global value, a uid and its size", dlc.global_value == "gage_pack" and dlc.uid ~= nil
    and part_items("s_holo")[1].item.data.uid ~= part_items("s_holo")[2].item.data.uid and dlc.ptype == "sight")
  T("  gone from the game's inventory (never counted twice)", inv.normal.weapon_mods.s_holo == nil
    and inv.normal.weapon_mods.b_supp == nil and inv.gage_pack.weapon_mods.s_dlc == nil)
  T("  ammunition and what has no part (or no black market entry) stay the game's, not waiting",
    inv.normal.weapon_mods.a_slug == 3 and inv.normal.weapon_mods.no_such_part == 1
    and inv.normal.weapon_mods.x_skin == 1 and #part_items("a_slug") == 0 and not logged("wait in its inventory"))
  T("  the game's progress saved once, told", saves == 1 and logged("4 weapon mod(s) from the game moved")
    and tostring(hints[#hints]):find("4 weapon mod(s)", 1, true) ~= nil)
  T("again: nothing more, no save", P.ImportGameMods() == 0 and saves == 1 and #part_items("s_holo") == 2)
  -- A drop after a heist: the next menu.
  inv.normal.weapon_mods.st_tactical = 1
  T("a new drop: moved at the next menu", A.OnMenu() and #part_items("st_tactical") == 1
    and inv.normal.weapon_mods.st_tactical == nil and saves == 2)
  -- No room: they wait in the game's inventory.
  local filler = 0
  while PDTI.AddItemAuto("locker", P.ITEM_ID, 1, P.MakeData("g_vert", nil, 5000 + filler), true) do filler = filler + 1 end
  while PDTI.AddItemAuto("locker", P.ITEM_ID, 1, P.MakeData("s_red", nil, 7000 + filler), true) do filler = filler + 1 end
  inv.normal.weapon_mods.s_holo = 2
  inv.normal.weapon_mods.g_vert = 1
  moved, waiting = P.ImportGameMods()
  T("the locker full: they wait in the game's inventory, told", moved == 0 and waiting == 3
    and inv.normal.weapon_mods.s_holo == 2 and inv.normal.weapon_mods.g_vert == 1 and saves == 2
    and logged("3 weapon mod(s) from the game wait") and tostring(hints[#hints]):find("wait", 1, true) ~= nil,
    moved .. "/" .. tostring(waiting))
  local e = part_items("s_red")[1]
  PDTI.RemoveItem(e.container, e.item.instance_id)
  moved, waiting = P.ImportGameMods()
  T("  one small place: a sight goes in, a big grip still waits", moved == 1 and waiting == 2
    and inv.normal.weapon_mods.s_holo == 1 and inv.normal.weapon_mods.g_vert == 1, moved .. "/" .. tostring(waiting))
  T("  the hint says what came in (the wait is in the log)", tostring(hints[#hints]):find("1 weapon mod(s) you got are in", 1, true)
    ~= nil, hints[#hints])
  -- The locker refuses it after all: back to the game's inventory.
  local e2 = part_items("g_vert")[1]
  PDTI.RemoveItem(e2.container, e2.item.instance_id)
  local real_add = PDTI.AddItemAuto
  PDTI.AddItemAuto = function() return false, "no" end
  moved = P.ImportGameMods()
  PDTI.AddItemAuto = real_add
  T("  refused after it left the game's inventory: given back", moved == 0 and inv.normal.weapon_mods.s_holo == 1)
  PDTI.Hint = real_hint
  _G.PDTI_SEPARATE_SAVE = nil
end)()

print(string.format("\n%d passed, %d failed", pass, fail))
