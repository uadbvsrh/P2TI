-- 0.41.0: gun build templates (armory_templates.lua). A build you saved, to
-- put on another weapon: the parts stay yours, so a template is a recipe,
-- not a copy of the parts.
--   luajit tests/template_tests.lua
local script = arg and arg[0] or "tests/template_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_templates") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

-- The game's weapons.
local W = tweak_data.weapon
W.amcar = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AMCAR", CLIP_AMMO_MAX = 20 }
W.new_m4 = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "CAR-4", CLIP_AMMO_MAX = 30 }
W.glock_17 = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "Chimano 88", CLIP_AMMO_MAX = 17 }
local FACTORY = { amcar = "wpn_fps_ass_amcar", new_m4 = "wpn_fps_ass_m4", glock_17 = "wpn_fps_pis_g17" }
local PRICE = { amcar = 10000, new_m4 = 40000, glock_17 = 5000 }

-- The game's parts: the factory's (type, forbids) and the black market's.
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
  { "amcar_irons", "sight" }, { "amcar_mag", "magazine" }, { "m4_body", "lower_reciever" }, { "g17_mag", "magazine" } }) do
  part(p[1], p[2], { pc = 1 })
end
part("s_holo", "sight")
part("s_red", "sight")
part("g_vert", "vertical_grip")
part("st_folding", "stock", { pc = 1 }, { forbids = { "g_vert" } })
part("b_supp", "barrel_ext")
part("gd_laser", "gadget")
part("x_skin", "custom", false)
local PARTS_BY = {
  wpn_fps_ass_amcar = {
    lower_reciever = { "amcar_body" }, barrel = { "amcar_barrel" },
    stock = { "amcar_stock", "st_folding" }, sight = { "amcar_irons", "s_holo", "s_red" },
    barrel_ext = { "b_supp" }, vertical_grip = { "g_vert" }, gadget = { "gd_laser" },
    magazine = { "amcar_mag" }, custom = { "x_skin" }
  },
  wpn_fps_ass_m4 = { lower_reciever = { "m4_body" }, sight = { "s_holo", "s_red" } },
  wpn_fps_pis_g17 = { magazine = { "g17_mag" } }
}
local DEFAULT = {
  wpn_fps_ass_amcar = { "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" },
  wpn_fps_ass_m4 = { "m4_body" },
  wpn_fps_pis_g17 = { "g17_mag" }
}
local function copy(t) local o = {}; for i, v in ipairs(t or {}) do o[i] = v end; return o end
local function has(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end; return false end
local function forbidden(bp)
  local f = {}
  for _, p in ipairs(bp) do for _, x in ipairs(FP[p] and FP[p].forbids or {}) do f[x] = p end end
  return f
end
local function drop_forbidden(bp)
  local f = forbidden(bp)
  for i = #bp, 1, -1 do if f[bp[i]] then table.remove(bp, i) end end
end
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
      return false
    end
    if not has(PARTS_BY[f] and PARTS_BY[f][t], p) then return false end
    for i, x in ipairs(bp) do if FP[x] and FP[x].type == t then table.remove(bp, i) break end end
    bp[#bp + 1] = p
    drop_forbidden(bp)
    return true
  end
}

ENV.load_mod(ROOT, true)
local A, P, Tpl = PDTI.Armory, PDTI.Parts, PDTI.Templates

local money = 1000000
managers.money = {
  total = function() return money end,
  deduct_from_total = function(_, v) money = money - v end,
  add_to_total = function(_, v) money = money + v end,
  add_to_spending = function(_, v) money = money + v end,
  get_payouts = function() return {} end,
  get_weapon_price_modified = function(_, id) return PRICE[id] end,
  get_weapon_modify_price = function() return 1000 end
}
managers.blackmarket = {
  weapon_unlocked = function() return true end,
  _calculate_weapon_concealment = function() return 30 end
}
managers.localization = { text = function(_, id) return id end }
managers.dlc = { is_dlc_unlocked = function() return true end }
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
local function fresh()
  os.remove(TMP .. "pdti_armory.json")
  os.remove(TMP .. "pdti_templates.json")
  A.Reset()
  Tpl.Reset()
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
-- The weapon's data as it is now (a fit replaces it).
local function wdata(uid) local _, _, d = weapon(uid); return d end
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

------------------------------------------------------------ saving a build

fresh()
local am = A.HandItem("primaries").data
T("no templates yet", Tpl.Count() == 0 and #Tpl.All() == 0)
local ok, why = Tpl.Save(am)
T("a weapon without parts of yours: nothing to save", ok == false and tostring(why):find("no parts", 1, true) ~= nil, why)

buy("amcar", "s_holo")
buy("amcar", "g_vert")
fit("s_holo", am.uid)
fit("g_vert", am.uid)
T("the AMCAR's build", has(bp(am.uid), "s_holo") and has(bp(am.uid), "g_vert"))
local saved, t, msg = Tpl.Save(wdata(am.uid))
T("the build saved as a template", saved == true and t ~= nil and #t.parts == 2
  and has(t.parts, "s_holo") and has(t.parts, "g_vert"), msg)
T("  its name: the weapon's name and 'build'", t.name == "AMCAR build", t.name)
T("  the weapon it was made from", t.weapon_id == "amcar", t.weapon_id)
T("  it is in the list", Tpl.Count() == 1 and Tpl.All()[1] == t)
T("  found by its id", Tpl.Find(t.id) == t and Tpl.Find(9999) == nil)
T("  described", tostring(Tpl.Describe(t)):find("AMCAR build", 1, true) ~= nil
  and tostring(Tpl.Describe(t)):find("2 part(s)", 1, true) ~= nil, Tpl.Describe(t))

local saved2, t2 = Tpl.Save(wdata(am.uid))
T("a second template: its name gets a number", saved2 == true and t2.name == "AMCAR build 2", t2 and t2.name)
T("  both are there", Tpl.Count() == 2)
local okdel, delmsg = Tpl.Delete(t2.id)
T("a template thrown away", okdel == true and Tpl.Count() == 1 and Tpl.Find(t2.id) == nil, delmsg)
T("  one that is not there: nothing happens", select(1, Tpl.Delete(9999)) == false)

---------------------------------------------------------- applying a build

-- The same weapon again: the parts are on it already.
local same, samemsg = Tpl.Apply(t.id, "hand_primary", (function()
  for _, w in ipairs(A.Weapons()) do if w.data.uid == am.uid then return w.instance_id end end
end)())
T("a template on the weapon it was made from: nothing to do", same == false
  and tostring(samemsg):find("already", 1, true) ~= nil, samemsg)

-- The parts off, the template on: they go back.
take_off(am.uid, "s_holo")
take_off(am.uid, "g_vert")
T("the AMCAR's build empty again", not has(bp(am.uid), "s_holo") and not has(bp(am.uid), "g_vert"))
T("the parts are items again", #part_items("s_holo") == 1 and #part_items("g_vert") == 1)
local wc, wid = weapon(am.uid)
local applied, apmsg = Tpl.Apply(t.id, wc, wid)
T("the template applied: the parts are on it again", applied == true and has(bp(am.uid), "s_holo")
  and has(bp(am.uid), "g_vert"), apmsg)
T("  and they are not items any more", #part_items("s_holo") == 0 and #part_items("g_vert") == 0)

-- Another weapon of the same kind: the parts it takes go on it.
local _, m4 = A.Buy("new_m4")
local mc, mid = weapon(m4.uid)
T("the CAR-4 bought", mc == "locker" and mid ~= nil)
take_off(am.uid, "s_holo")
take_off(am.uid, "g_vert")
local applied2, apmsg2 = Tpl.Apply(t.id, mc, mid)
T("the template on another CAR-4: the sight goes on it", applied2 == true and has(bp(m4.uid), "s_holo"), apmsg2)
T("  the grip it does not take is left out", not has(bp(m4.uid), "g_vert")
  and tostring(apmsg2):find("not fitted", 1, true) ~= nil, apmsg2)
T("  and it says why", tostring(apmsg2):find("does not take it", 1, true) ~= nil, apmsg2)
T("  the grip is still an item", #part_items("g_vert") == 1)
T("  the AMCAR's own parts are untouched", not has(bp(am.uid), "s_holo"))

-- A part you do not own.
buy("amcar", "s_red")
fit("s_red", am.uid)
local t2b = { id = 99, name = "test", weapon_id = "amcar", parts = { "s_red", "b_supp" } }
local d = Tpl._Data()
d.templates[#d.templates + 1] = t2b
take_off(am.uid, "s_red")
local wc0, wid0 = weapon(am.uid)
local applied3, apmsg3 = Tpl.Apply(99, wc0, wid0)
T("a part you do not own: it is left out", applied3 == true and tostring(apmsg3):find("you do not own it", 1, true) ~= nil, apmsg3)
T("  the part you do own is on the weapon", has(bp(am.uid), "s_red"))

-- The parts that come off become items again.
local _, m4b = A.Buy("new_m4")
local mc2, mid2 = weapon(m4b.uid)
buy("amcar", "s_holo")
buy("amcar", "s_red")
fit("s_holo", m4b.uid)
T("the CAR-4 has the sight", has(bp(m4b.uid), "s_holo"))
-- A template with another sight: the one on the weapon comes off.
local t3 = { id = 100, name = "other", weapon_id = "amcar", parts = { "s_red" } }
d.templates[#d.templates + 1] = t3
local applied4, apmsg4 = Tpl.Apply(100, mc2, mid2)
T("another sight on the weapon: the one on it comes off", applied4 == true and has(bp(m4b.uid), "s_red")
  and not has(bp(m4b.uid), "s_holo"), apmsg4)
T("  and it is an item again", #part_items("s_holo") == 1)

-- A part the game's rules do not allow with another one: the other comes off.
buy("amcar", "st_folding")
fit("g_vert", am.uid)
T("the vertical grip on the AMCAR", has(bp(am.uid), "g_vert"))
local tf = { id = 200, name = "folding", weapon_id = "amcar", parts = { "st_folding" } }
d.templates[#d.templates + 1] = tf
local applied6, apmsg6 = Tpl.Apply(200, wc0, wid0)
T("a stock that forbids the vertical grip: the grip comes off", applied6 == true
  and has(bp(am.uid), "st_folding") and not has(bp(am.uid), "g_vert"), apmsg6)
T("  and it is an item again", #part_items("g_vert") == 1)

-- In a heist a build is changed at home.
PDTI.session_only = true
local applied5, apmsg5 = Tpl.Apply(t.id, mc2, mid2)
T("in a heist: a build is changed at home", applied5 == false
  and tostring(apmsg5):find("at home", 1, true) ~= nil, apmsg5)
PDTI.session_only = false

----------------------------------------------------------------- the file

fresh()
local amf = A.HandItem("primaries").data
buy("amcar", "s_holo")
fit("s_holo", amf.uid)
local savedf = Tpl.Save(wdata(amf.uid))
T("the templates are written", savedf == true and Tpl.Count() == 1)
local f = io.open(TMP .. "pdti_templates.json", "r")
local text = f and f:read("*a") or ""
if f then f:close() end
T("  in their own file", text:find("s_holo", 1, true) ~= nil and text:find("AMCAR build", 1, true) ~= nil, text)
Tpl.Reset()
T("  and read back", Tpl.Count() == 1 and Tpl.All()[1].parts[1] == "s_holo")
T("  a template without parts is left out", (function()
  local d2 = Tpl._Data()
  d2.templates[#d2.templates + 1] = { id = 5, name = "empty", parts = {} }
  Tpl.Store()
  Tpl.Reset()
  return Tpl.Count() == 1
end)())
local broken = io.open(TMP .. "pdti_templates.json", "w")
broken:write("{not json")
broken:close()
Tpl.Reset()
T("  a broken file is ignored", Tpl.Count() == 0)
os.remove(TMP .. "pdti_templates.json")
Tpl.Reset()
T("  no file: no templates", Tpl.Count() == 0)

-------------------------------------------------------------- the screen

;(function()
  fresh()
  local amx = A.HandItem("primaries").data
  buy("amcar", "s_holo")
  fit("s_holo", amx.uid)
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
  shift_click("weapon_box_primary")
  local shop = named("pdti_shop")
  T("the weapon's view: the templates are there", shop:find("templates_label") ~= nil
    and shop:find("template_save") ~= nil and shop:find("templates_none") ~= nil)
  shop:find("template_save"):click()
  shop = named("pdti_shop")
  T("  the build saved: the template is in the list", Tpl.Count() == 1
    and shop:find("template_line_1") ~= nil and shop:find("template_apply_1") ~= nil
    and shop:find("template_delete_1") ~= nil)
  T("  the status says so", shop:find("inspect_status") ~= nil
    and tostring(shop:find("inspect_status").params.text):find("Saved", 1, true) ~= nil)
  -- Take the sight off and put the template back on with the button.
  local wc, wid = weapon(amx.uid)
  P.TakeOff(wc, wid, "s_holo")
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  shop:find("template_apply_1"):click()
  shop = named("pdti_shop")
  T("  the template applied with the button", has(bp(amx.uid), "s_holo")
    and tostring(shop:find("inspect_status").params.text):find("part(s) on the AMCAR", 1, true) ~= nil,
    shop:find("inspect_status") and shop:find("inspect_status").params.text)
  shop:find("template_delete_1"):click()
  shop = named("pdti_shop")
  T("  the template thrown away with the button", Tpl.Count() == 0 and shop:find("templates_none") ~= nil)
  T("  no MenuUI parameter that is not documented", #ENV.violations == 0, table.concat(ENV.violations, ", "))
end)()

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
