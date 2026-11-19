-- 0.49.0: weapon skins (armory_skins.lua). Your weapons wear the skins and
-- colours you own in the game; Sydney (her room in the safehouse) changes
-- them. Any number of guns can wear one skin; a legendary skin brings its own
-- parts (free, the gun locked); a skin sold comes off at the menu.
--   luajit tests/skins_tests.lua
local script = arg and arg[0] or "tests/skins_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_skins") .. "/"
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
  { "s_red", "sight" }, { "b_supp", "barrel_ext" }, { "gd_laser", "gadget" } }) do
  part(p[1], p[2])
end
-- A legendary skin's own barrel: no part for sale.
FP.leg_barrel = { type = "barrel", name_id = "leg_barrel" }
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
dofile(ROOT .. "lua/ammo_hooks.lua") -- (what stops a change in a heist: Ammo.ActionPressed)
dofile(ROOT .. "lua/body.lua") -- (the health window in a heist)
local A, P, H, I, S = PDTI.Armory, PDTI.Parts, PDTI.HotMod, PDTI.Insurance, PDTI.WeaponSkins

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
-- The game's skins: two for the AMCAR (one legendary), one for the Chimano,
-- two weapon colours (one unlocked), one unlockable skin.
local LEG_BP = { "amcar_body", "leg_barrel", "amcar_stock", "amcar_irons", "amcar_mag" }
tweak_data.blackmarket.weapon_skins = {
  amcar_red = { name_id = "Red Rum", weapon_id = "amcar", rarity = "rare" },
  amcar_gold = { name_id = "Gold Rush", weapon_id = "amcar", rarity = "legendary", locked = true,
    default_blueprint = LEG_BP },
  g17_blue = { name_id = "Blue Steel", weapon_id = "glock_17" },
  color_pink = { name_id = "Pink", is_a_color_skin = true, use_blacklist = true, weapon_ids = { "glock_17" } },
  color_grey = { name_id = "Grey", is_a_color_skin = true, use_blacklist = true },
  amcar_free = { name_id = "Achiever", weapon_id = "amcar", is_a_unlockable = true }
}
tweak_data.blackmarket.weapon_color_pattern_scale_default = 2
-- Your Steam copies: two of the Red Rum (the StatBoost one is the best), one
-- Gold Rush, one Blue Steel, and a mask (not a skin).
local TRADABLE
local function own_all()
  TRADABLE = {
    ["101"] = { entry = "amcar_red", quality = "mint", bonus = false, category = "weapon_skins" },
    ["102"] = { entry = "amcar_red", quality = "worn", bonus = true, category = "weapon_skins" },
    ["103"] = { entry = "amcar_red", quality = "poor", bonus = false, category = "weapon_skins" },
    ["201"] = { entry = "amcar_gold", quality = "fine", bonus = false, category = "weapon_skins" },
    ["301"] = { entry = "g17_blue", quality = "mint", bonus = false, category = "weapon_skins" },
    ["401"] = { entry = "amcar_red", quality = "mint", category = "masks" }
  }
end
own_all()
local UNLOCKED = { color_pink = true, amcar_free = true }
local tradable_fails = false
managers.blackmarket = {
  weapon_unlocked = function() return true end,
  _calculate_weapon_concealment = function() return 30 end,
  get_inventory_tradable = function()
    if tradable_fails then error("no Steam") end
    return TRADABLE
  end,
  has_item = function(_, gv, cat, id) return gv == "normal" and cat == "weapon_skins" and UNLOCKED[id] == true end,
  -- (The game's own check.)
  weapon_cosmetics_type_check = function(_, weapon_id, id)
    local ws = tweak_data.blackmarket.weapon_skins[id]
    local found = false
    if ws then
      local listed = false
      for _, w in ipairs(ws.weapon_ids or {}) do if w == weapon_id then listed = true end end
      found = (not ws.weapon_ids or listed) and ws.weapon_id and ws.weapon_id == weapon_id
      if ws.use_blacklist then found = not found end
    end
    return found and true or false
  end
}
managers.localization = { text = function(_, id) return id end }
managers.dlc = { is_dlc_unlocked = function() return false end, dlc_to_global_value = function() return "normal" end }
-- Duke's room (the game's safehouse tiers).
local tiers = {}
managers.custom_safehouse = { _global = { rooms = {} }, get_room_current_tier = function(_, r) return tiers[r] end }
_G.Global = _G.Global or {}
Global.blackmarket_manager = { crafted_items = { primaries = {}, secondaries = {} } }
ENV.game.unit = nil -- the menu: no player
PDTI.Market.Today = function() return "2026-11-19" end
A.FactorRoll = function() return 0.5 end
A.StockRoll = function() return 0.99 end
local hints = {}
PDTI.Hint = function(text) hints[#hints + 1] = text end
-- Real time.
local T0 = 1795000000
local now = T0
I.Now = function() return now end
local Money = PDTI.Ammo.Money

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function logged(text)
  for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then return true end end
  return false
end

-- The player in a heist: the guns the game made at spawn.
local function unit(f) local b = { _factory_id = f }; return { base = function() return b end } end
local function new_player()
  local inv = { sel = { [2] = { unit = unit("wpn_fps_ass_amcar") }, [1] = { unit = unit("wpn_fps_pis_g17") } }, eq = 2 }
  function inv:available_selections() return self.sel end
  function inv:equipped_selection() return self.eq end
  function inv:equip_selection(i) self.eq = i; return true end
  function inv:add_unit_by_factory_name(f) self.sel[f == "wpn_fps_pis_g17" and 1 or 2] = { unit = unit(f) } end
  local player = { inventory = function() return inv end }
  managers.player = { player_unit = function() return player end, current_state = function() return "standard" end }
  return player
end

local function fresh()
  if H.Active() then H.Stop() end
  managers.player, managers.job = nil, nil
  os.remove(TMP .. "pdti_armory.json")
  A.Reset()
  PDTI.Reset()
  PDTI.session_only = false
  PDTI.SetEquipment("backpack", "large_backpack")
  PDTI.SetEquipment("rig", "general_rig")
  A.IssueFree() -- the AMCAR in PRI, the Chimano in SEC
  money, now, tiers, hints = 1000000, T0, {}, {}
  I.notes = {}
  I.ResetTick()
end
local function weapon(uid)
  for _, w in ipairs(A.Weapons()) do if w.data.uid == uid then return w.container, w.instance_id, w.data end end
end
local function weapons_of(weapon_id)
  local out = {}
  for _, w in ipairs(A.Weapons()) do if w.data.weapon_id == weapon_id and not w.data.free then out[#out + 1] = w end end
  return out
end
local function part_items(part_id)
  return PDTI.FindItems(function(_, it) return it.item_id == P.ITEM_ID and it.data.part_id == part_id end)
end
local function where_part(part_id)
  local e = part_items(part_id)[1]
  if e then return e.container, e.item.instance_id end
end
local function move(uid, to)
  local e = PDTI.FindItems(function(_, it) return type(it.data) == "table" and it.data.uid == uid end)[1]
  local x, y, rot = PDTI.FindFreeSpace(to, e.item, true)
  return PDTI.MoveItem(e.container, e.item.instance_id, to, x, y, rot)
end
local function fit_home(part_id, uid)
  local pc, pid = where_part(part_id)
  local wc, wid = weapon(uid)
  return P.Fit(pc, pid, wc, wid)
end
-- A bought AMCAR (not the free one), with a red dot, packed in the backpack;
-- insured when asked.
local function gun(insure)
  A._Data().stock.bought = {} -- (at most 3 of a kind are sold a day)
  local _, d = A.Buy("amcar")
  P.Buy("amcar", "s_red")
  fit_home("s_red", d.uid)
  move(d.uid, "backpack")
  if insure then
    local c, iid = weapon(d.uid)
    I.Insure(c, iid)
  end
  return d.uid
end
local function heist()
  A.OnHeistStart()
  PDTI.session_only = true
  return A.OnSpawn(new_player())
end
-- The heist ends (nil: the game was quit) and the game loads the menu from
-- the files (a heist writes no inventory).
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
local function hand(cat)
  local it = A.HandItem(cat)
  return it and it.data
end
local function at(uid) local c, iid = weapon(uid); return c, iid end
local function data(uid) return select(3, weapon(uid)) end

-------------------------------------------------------------- what you own

do
  fresh()
  local list = S.Owned("amcar")
  local ids = {}
  for i, e in ipairs(list) do ids[i] = e.id end
  T("the AMCAR's skins: by name, one row each (the unlockable and the colour too)",
    table.concat(ids, ",") == "amcar_free,amcar_gold,color_pink,amcar_red", table.concat(ids, ","))
  local red = list[4]
  T("  your best copy: the StatBoost one first", red.iid == "102" and red.bonus == true and red.quality == "worn")
  T("  the legendary skin is marked, locked", list[2].legendary and list[2].locked and not red.legendary)
  T("  a colour: the first colour, no copy of its own", list[3].color == 1 and list[3].iid == "color_pink")
  T("  an unlockable is owned when the game says so", list[1].iid == "amcar_free")
  T("  no grey: a colour you have not unlocked", #list == 4)
  T("the Chimano's: its own and the colour", #S.Owned("glock_17") == 2 and S.Owned("glock_17")[1].id == "g17_blue")
  T("labels", S.Label(red) == "Red Rum (Well-Used, StatBoost)" and S.Label(list[2]) == "Gold Rush (Lightly-Marked, legendary)"
    and S.Label(list[3]) == "Pink (colour)" and S.Label(nil) == "none", S.Label(red))
  TRADABLE["104"] = { entry = "amcar_red", quality = "mint", bonus = true, category = "weapon_skins" }
  T("  a better StatBoost copy wins", S.Owned("amcar")[4].iid == "104")
  TRADABLE["104"] = nil
  tradable_fails = true
  T("no Steam inventory: only what the game unlocked", #S.Owned("amcar") == 2)
  tradable_fails = false
end

-------------------------------------------------------------- a plain skin

do
  fresh()
  local d = hand("primaries")
  local c, iid = at(d.uid)
  local bp = d.blueprint
  local ok, msg = S.Apply(c, iid, "amcar_red")
  T("the AMCAR in your hands wears the Red Rum", ok and msg == "The AMCAR wears Red Rum (Well-Used, StatBoost)", msg)
  d = hand("primaries")
  T("  kept on the weapon: the best copy", d.skin_id == "amcar_red" and d.skin_iid == "102" and d.skin_quality == "worn"
    and d.skin_bonus == true and d.blueprint == bp)
  local slot = Global.blackmarket_manager.crafted_items.primaries[1]
  T("  the game's slot wears it", slot.cosmetics and slot.cosmetics.id == "amcar_red"
    and slot.cosmetics.instance_id == "102" and slot.cosmetics.bonus == true and slot.cosmetics.quality == "worn")
  T("  not locked", not slot.customize_locked)
  T("  the price: no change", A.BuildPrice(d) == 10000)
  T("again: no", select(2, S.Apply(c, iid, "amcar_red")) == "it wears that skin already")
  T("one you do not own: no", select(2, S.Apply(c, iid, "g17_blue")) == "you do not own that skin for the AMCAR")
  T("not a weapon", (function()
    local _, pd = P.Buy("amcar", "b_supp")
    local pc, pid = where_part("b_supp")
    return pc ~= nil and select(2, S.Apply(pc, pid, "amcar_red")) == "no such weapon"
      and select(2, S.Remove(pc, pid)) == "no such weapon"
  end)())
  T("no such weapon", select(2, S.Apply("locker", 999, "amcar_red")) == "no such weapon"
    and select(2, S.Remove("locker", 999)) == "no such weapon")
  -- Any number of guns.
  A._Data().stock.bought = {}
  local _, other = A.Buy("amcar")
  local oc, oiid = at(other.uid)
  T("any number of guns wear one skin", S.Apply(oc, oiid, "amcar_red") == true and data(other.uid).skin_id == "amcar_red"
    and hand("primaries").skin_id == "amcar_red")
  T("  a fitted part stays on with a plain skin", (function()
    P.Buy("amcar", "s_red"); fit_home("s_red", other.uid)
    S.Apply(oc, oiid, "color_pink")
    return data(other.uid).blueprint:find("s_red", 1, true) ~= nil and data(other.uid).skin_id == "color_pink"
  end)())
  T("a colour: its index and the game's pattern", A.Cosmetics(data(other.uid)).color_index == 1
    and A.Cosmetics(data(other.uid)).pattern_scale == 2 and A.Cosmetics(d).pattern_scale == nil)
  ok, msg = S.Remove(c, iid)
  d = hand("primaries")
  T("removed: none", ok and msg == "The AMCAR wears no skin now" and not S.Of(d) and A.Cosmetics(d) == nil
    and Global.blackmarket_manager.crafted_items.primaries[1].cosmetics == nil)
  T("  again: no", select(2, S.Remove(c, iid)) == "it wears no skin")
  T("  the other keeps its part", (function()
    S.Remove(oc, oiid)
    return data(other.uid).blueprint:find("s_red", 1, true) ~= nil
  end)())
  T("  logged", logged("amcar_red on the amcar") and logged("the skin off the amcar"))
end

-------------------------------------------------------------- legendary

do
  fresh()
  local uid = gun(false)
  local c, iid, d = weapon(uid)
  T("a bought AMCAR with a red dot, in the backpack", c == "backpack" and d.blueprint:find("s_red", 1, true) ~= nil)
  T("  priced with its part", A.BuildPrice(d) == 11000)
  -- No room for the red dot: nothing changes.
  local place = P.PlaceOff
  P.PlaceOff = function() return false, "no room for the Red dot that comes off" end
  local ok, msg = S.Apply(c, iid, "amcar_gold")
  P.PlaceOff = place
  T("no room for your parts: nothing changes, it says why", not ok and msg == "no room for the Red dot that comes off"
    and data(uid).skin_id == nil and data(uid).blueprint == d.blueprint)
  ok, msg = S.Apply(c, iid, "amcar_gold")
  d = data(uid)
  T("the Gold Rush: its own parts", ok and d.blueprint == A.JoinBlueprint(LEG_BP) and d.skin_id == "amcar_gold", msg)
  T("  said: your part came off", msg == "The AMCAR wears Gold Rush (Lightly-Marked, legendary); 1 part(s) came off", msg)
  T("  the red dot is an item again, next to it", #part_items("s_red") == 1 and part_items("s_red")[1].container == "backpack")
  T("  its parts are free", A.BuildPrice(d) == 10000 and P.SellPrice(PDTI.FindItem(c, iid)) == P.SellPrice({
    item_id = A.ITEM_ID, data = A.MakeData("amcar", nil, 1) }))
  T("  locked: no part goes on", select(2, P.CanFit({ part_id = "b_supp" }, d))
    == "the Gold Rush skin locks the AMCAR: Sydney takes it off")
  T("  nor a build", select(2, P.ApplyBuild(c, iid, { "b_supp" })) == "the Gold Rush skin locks the AMCAR: Sydney takes it off")
  T("  a fit is refused", fit_home("s_red", uid) == false and #part_items("s_red") == 1)
  T("  in your hands: locked in the game's screens too", (function()
    move(hand("primaries").uid, "locker")
    move(uid, "hand_primary")
    A.SyncEquipped()
    local slot = Global.blackmarket_manager.crafted_items.primaries[1]
    return slot.customize_locked == true and slot.locked_name == true and slot.cosmetics.id == "amcar_gold"
  end)())
  c, iid = at(uid)
  -- Another plain skin: the legendary parts go, the weapon's own come back.
  ok = S.Apply(c, iid, "amcar_red")
  d = data(uid)
  T("a plain skin over it: the weapon's own parts", ok and d.blueprint == A.JoinBlueprint(DEFAULT.wpn_fps_ass_amcar)
    and d.skin_id == "amcar_red" and #part_items("s_red") == 1)
  S.Apply(c, iid, "amcar_gold")
  S.Remove(c, iid)
  d = data(uid)
  T("removed: the weapon's own parts, unlocked", d.blueprint == A.JoinBlueprint(DEFAULT.wpn_fps_ass_amcar)
    and S.LockReason(d) == nil and P.CanFit({ part_id = "b_supp" }, d) == true)
end

do
  fresh()
  -- A legendary skin with a part you fitted: it comes back on removal? No:
  -- your parts came off; the ones fitted after... (the gun is locked).
  local uid = gun(false)
  local c, iid = at(uid)
  local d = data(uid)
  local new, off = S._NewBuild(d, nil)
  T("no skin, none coming: the parts stay as they are", new == nil and #off == 0)
  new, off = S._NewBuild(d, "amcar_gold")
  T("  a legendary coming: your parts come off", #off == 1 and off[1] == "s_red" and new[2] == "leg_barrel")
  -- An unlocked legendary skin (no lock): what you fitted next to it stays
  -- when it goes.
  tweak_data.blackmarket.weapon_skins.amcar_gold.locked = nil
  S.Apply(c, iid, "amcar_gold")
  P.Buy("amcar", "b_supp")
  T("  a legendary skin without a lock takes parts", fit_home("b_supp", uid) == true)
  d = data(uid)
  T("  its own parts free, yours priced", (function()
    local d2 = data(uid)
    return A.BuildPrice(d2) == 11000
  end)())
  T("  sold: its own parts free even if the game sold them", (function()
    local item = PDTI.FindItem(c, iid)
    local plain = P.SellPrice(item)
    MODS.leg_barrel = { pc = 1 }
    local same = P.SellPrice(item) == plain
    MODS.leg_barrel = nil
    local bare = { item_id = A.ITEM_ID, data = {} }
    for k, v in pairs(item.data) do bare.data[k] = v end
    bare.data.blueprint, bare.data.skin_id = A.JoinBlueprint(DEFAULT.wpn_fps_ass_amcar), false
    return same and plain > P.SellPrice(bare)
  end)())
  S.Remove(c, iid)
  d = data(uid)
  T("  removed: the weapon's own, and the part fitted beside it", d.blueprint
    == A.JoinBlueprint({ "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag", "b_supp" }), d.blueprint)
  tweak_data.blackmarket.weapon_skins.amcar_gold.locked = true
end

-------------------------------------------------------------- at home only

do
  fresh()
  local d = hand("primaries")
  local c, iid = at(d.uid)
  S.Apply(c, iid, "amcar_red")
  heist()
  T("in a heist: no change", select(2, S.Apply(c, iid, "color_pink")) == "skins are changed at home (Sydney, in the safehouse)"
    and select(2, S.Remove(c, iid)) == "skins are changed at home (Sydney, in the safehouse)")
  TRADABLE["101"], TRADABLE["102"], TRADABLE["103"] = nil, nil, nil
  T("  no sweep either", S.Sweep() == 0 and hand("primaries").skin_id == "amcar_red")
  own_all()
  to_menu(true)
  local enabled = A.Enabled
  A.Enabled = function() return false end
  T("the armory off: no skins", select(2, S.Apply(c, iid, "color_pink")) == "the armory is off (restoration-mod or no stash)"
    and S.Sweep() == 0)
  A.Enabled = enabled
end

-------------------------------------------------------------- in your hands

do
  fresh()
  -- The safehouse: the gun you hold is made again with its skin.
  local args = {}
  local function u(f, uid, key) local b = { _factory_id = f, _pdti_uid = uid, _pdti_bp = key }; return { base = function() return b end } end
  local d = hand("primaries")
  local inv = { sel = { [2] = { unit = u("wpn_fps_ass_amcar", d.uid, A.BuildKey(d)) },
    [1] = { unit = u("wpn_fps_pis_g17", hand("secondaries").uid, A.BuildKey(hand("secondaries"))) } }, eq = 2 }
  function inv:available_selections() return self.sel end
  function inv:equipped_selection() return self.eq end
  function inv:equip_selection(i) self.eq = i; return true end
  function inv:add_unit_by_factory_name(f, equip, instant, bp, cosmetics)
    args[#args + 1] = { f = f, bp = bp, cosmetics = cosmetics }
    self.sel[f == "wpn_fps_pis_g17" and 1 or 2] = { unit = u(f) }
  end
  local player = { inventory = function() return inv end }
  managers.player = { player_unit = function() return player end, current_state = function() return "standard" end }
  managers.job = { current_job_id = function() return "chill" end } -- the safehouse
  T("the same build and skin: not made again", A.ApplyHands(player) == false and #args == 0)
  local c, iid = at(d.uid)
  S.Apply(c, iid, "amcar_red")
  T("a skin: the gun made again, wearing it", #args == 1 and args[1].f == "wpn_fps_ass_amcar"
    and args[1].cosmetics and args[1].cosmetics.id == "amcar_red" and args[1].cosmetics.instance_id == "102")
  T("  the build key knows the skin", A.BuildKey(hand("primaries")) == hand("primaries").blueprint .. "#amcar_red:")
  local sec = hand("secondaries")
  c, iid = at(sec.uid)
  S.Apply(c, iid, "color_pink")
  T("  a colour: its index", #args == 2 and args[2].cosmetics.color_index == 1
    and A.BuildKey(hand("secondaries")):find("#color_pink:1", 1, true) ~= nil)
  S.Remove(c, iid)
  T("  removed: made again, no skin", #args == 3 and args[3].cosmetics == nil)
  managers.player, managers.job = nil, nil
end

-------------------------------------------------------------- a skin sold

do
  fresh()
  local d = hand("primaries")
  local c, iid = at(d.uid)
  S.Apply(c, iid, "amcar_gold")
  local sec = hand("secondaries")
  local sc, siid = at(sec.uid)
  S.Apply(sc, siid, "color_pink")
  A._Data().stock.bought = {}
  local _, other = A.Buy("amcar")
  local oc, oiid = at(other.uid)
  S.Apply(oc, oiid, "amcar_free")
  tradable_fails = true
  T("no Steam inventory: nothing comes off", S.Sweep() == 0 and hand("primaries").skin_id == "amcar_gold")
  tradable_fails = false
  T("all owned: nothing comes off", S.Sweep() == 0)
  TRADABLE["201"] = nil
  T("the Gold Rush sold: it comes off at the menu", (function() to_menu(); return true end)()
    and hand("primaries").skin_id ~= "amcar_gold"
    and hand("primaries").blueprint == A.JoinBlueprint(DEFAULT.wpn_fps_ass_amcar)
    and Global.blackmarket_manager.crafted_items.primaries[1].cosmetics == nil)
  T("  logged", logged("you no longer own the amcar_gold"))
  T("  the colour and the unlockable stay (the game says you have them)", hand("secondaries").skin_id == "color_pink"
    and data(other.uid).skin_id == "amcar_free")
  UNLOCKED.color_pink = nil
  T("  a colour no longer unlocked comes off", S.Sweep() == 1 and hand("secondaries").skin_id ~= "color_pink")
  UNLOCKED.color_pink = true
  tweak_data.blackmarket.weapon_skins.amcar_free.dlc = "pd2_clan"
  T("  an unlockable of a DLC you do not own comes off", S.Sweep() == 1 and not S.Of(data(other.uid)))
  tweak_data.blackmarket.weapon_skins.amcar_free.dlc = nil
  own_all()
end

-------------------------------------------------------------- the files

do
  fresh()
  local uid = gun(true)
  local c, iid = at(uid)
  -- (Insured with a skin on: the change cancels it, as any change does.)
  S.Apply(c, iid, "amcar_red")
  I.Insure(c, iid)
  local d = data(uid)
  T("insured with its skin on", I.Policy(uid) ~= nil)
  local ok = I.Claim(d, now)
  local back = A._Data().returns[1]
  T("lost and insured: it comes back with its skin", ok and back and back.data.skin_id == "amcar_red"
    and back.data.skin_iid == "102" and back.data.skin_bonus == true and back.data.skin_quality == "worn")
  back.data.skin_color = 3
  A._Data().captured = { { data = { uid = 77, weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar", blueprint = "",
    skin_id = "color_pink", skin_iid = "color_pink", skin_quality = "mint", skin_bonus = "yes", skin_color = 1 }, at = "backpack" },
    { data = { uid = 78, weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar", blueprint = "",
    skin_id = "amcar_red", skin_iid = "102", skin_quality = "worn", skin_bonus = true }, at = "backpack" } }
  A.Save()
  A.Reset()
  local r, cap = A._Data().returns[1].data, A._Data().captured[1].data
  T("the file keeps the skins of what comes back", r.skin_id == "amcar_red" and r.skin_iid == "102" and r.skin_bonus == true
    and r.skin_color == 3)
  T("  and of what you captured (only true is a StatBoost)", cap.skin_id == "color_pink" and cap.skin_color == 1
    and cap.skin_bonus == nil and A._Data().captured[2].data.skin_bonus == true)
end

-------------------------------------------------------------- Sydney

do
  fresh()
  local Home = PDTI.Safehouse
  tweak_data.safehouse = { rooms = { { room_id = "sydney", name_id = "menu_sydney", tier_max = 3 },
    { room_id = "russian", name_id = "menu_russian", tier_max = 3 } } }
  managers.custom_safehouse = {
    _global = { rooms = {} },
    get_room_current_tier = function() return 1 end, get_room_max_tier = function() return 3 end,
    get_next_tier_unlocked = function() return 2 end, get_upgrade_cost = function() return 0 end,
    can_afford_room_tier = function() return false end, coins = function() return 0 end,
    purchase_room_tier = function() end, set_room_tier = function() end
  }
  local dialogs = {}
  managers.system_menu = { is_active = function() return false end, show = function(_, x) dialogs[#dialogs + 1] = x end }
  local function button(x, prefix)
    for _, b in ipairs(x.button_list) do if b.text:sub(1, #prefix) == prefix then return b end end
  end
  T("Sydney's menu opens", Home.ShowRoomMenu("sydney") == true)
  local skins = button(dialogs[#dialogs], "Weapon skins")
  T("  Weapon skins", skins ~= nil)
  Home.ShowRoomMenu("russian")
  T("  not in another room", button(dialogs[#dialogs], "Weapon skins") == nil)
  -- The screen.
  ENV.install_menuui(false)
  local function windows() return ENV.menus[#ENV.menus].children end
  local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
  skins.callback_func()
  T("the skins screen opens", PDTI.IsUIOpen() and logged("the skins are open (Sydney)"))
  local shop = named("pdti_shop")
  T("  your weapons, those in your hands first", shop:find("skins_weapon_1") ~= nil
    and shop:find("skins_weapon_1").params.text == "AMCAR (PRI): none"
    and shop:find("skins_weapon_2").params.text == "Chimano 88 (SEC): none", shop:find("skins_weapon_1") and shop:find("skins_weapon_1").params.text)
  T("  the side windows are empty", named("pdti_left").pw <= 1 and named("pdti_right").pw <= 1)
  shop:find("skins_weapon_1"):click()
  shop = named("pdti_shop")
  T("  the AMCAR: its skins", shop:find("skins_weapon").params.text == "AMCAR: none"
    and shop:find("skins_skin_4").params.text == "Red Rum (Well-Used, StatBoost)" and shop:find("skins_remove") == nil)
  shop:find("skins_skin_4"):click()
  shop = named("pdti_shop")
  T("  a click: worn, said", hand("primaries").skin_id == "amcar_red"
    and shop:find("skins_status").params.text == "The AMCAR wears Red Rum (Well-Used, StatBoost)"
    and shop:find("skins_skin_4").params.text == "Red Rum (Well-Used, StatBoost)  - on it")
  T("  fits 720p", shop.ph <= 720, shop.ph)
  shop:find("skins_remove"):click()
  shop = named("pdti_shop")
  T("  Remove", hand("primaries").skin_id ~= "amcar_red" and shop:find("skins_status").params.text == "The AMCAR wears no skin now")
  local saved_t, saved_u = TRADABLE, UNLOCKED
  TRADABLE, UNLOCKED = {}, {}
  PDTI.RedrawUI()
  T("  none owned: said", named("pdti_shop"):find("skins_none").params.text == "You own no skins for the AMCAR.")
  TRADABLE, UNLOCKED = saved_t, saved_u
  shop = named("pdti_shop")
  shop:find("skins_back"):click()
  shop = named("pdti_shop")
  T("  Back: your weapons", shop:find("skins_weapon_1") ~= nil and shop:find("skins_status") == nil)
  -- Pages.
  for _ = 1, 10 do A._Data().stock.bought = {}; A.Buy("glock_17") end
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  T("  many weapons: pages", shop:find("skins_wpage_next") ~= nil and shop:find("skins_wpage_prev") == nil
    and shop:find("skins_weapon_10") == nil and shop:find("skins_wpage_at").params.text == "Page 1 of 2")
  T("    fits 720p", shop.ph <= 720, shop.ph)
  shop:find("skins_wpage_next"):click()
  shop = named("pdti_shop")
  T("    the next page", shop:find("skins_wpage_prev") ~= nil and shop:find("skins_wpage_next") == nil
    and shop:find("skins_weapon_1") ~= nil and shop:find("skins_weapon_4") == nil)
  shop:find("skins_wpage_prev"):click()
  T("    and back", named("pdti_shop"):find("skins_wpage_at").params.text == "Page 1 of 2")
  shop = named("pdti_shop")
  shop:find("skins_close"):click()
  T("Close: shut, the mode gone", not PDTI.IsUIOpen())
  T("  the inventory screen opens as it was", PDTI.ToggleUI() == true and named("pdti_shop"):find("skins_label") == nil)
  PDTI.SetUIOpen(false)
  -- The weapon view says what it wears.
  local d = hand("primaries")
  local c, iid = at(d.uid)
  S.Apply(c, iid, "amcar_red")
  T("the armory off: Sydney has no button", (function()
    local enabled = A.Enabled
    A.Enabled = function() return false end
    Home.ShowRoomMenu("sydney")
    local none = button(dialogs[#dialogs], "Weapon skins") == nil and PDTI.OpenSkins() == false
    A.Enabled = enabled
    return none
  end)())
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
