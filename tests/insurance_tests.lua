-- 0.45.0: weapon insurance (armory_insurance.lua). Insured at home for 30%
-- of the built price, it lasts until the weapon is lost; then the weapon is
-- back in the locker 10 real minutes after the heist ended. A change at home
-- cancels it and pays it back. Duke's room makes it cheaper and faster.
--   luajit tests/insurance_tests.lua
local script = arg and arg[0] or "tests/insurance_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_insurance") .. "/"
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
local A, P, H, I = PDTI.Armory, PDTI.Parts, PDTI.HotMod, PDTI.Insurance

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
managers.dlc = { is_dlc_unlocked = function() return false end }
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
local function tick() I.ResetTick(); return I.Tick() end

-------------------------------------------------------------- insuring

do
  fresh()
  local uid = gun(false)
  local c, iid, d = weapon(uid)
  T("the price: 30% of the weapon and the parts on it (the game's prices)", I.Price(d) == 3300, I.Price(d))
  local ok, msg = I.Insure(c, iid)
  T("insured: paid now", ok and money == 1000000 - 10000 - 1000 - 3300 and I.Policy(uid).paid == 3300, msg)
  T("  you are told how it works", msg == "Insured the AMCAR for " .. Money(3300)
    .. ": lost, it is back in your locker 10 min after the heist", msg)
  T("  for this build", I.Policy(uid).bp == d.blueprint and has(A.SplitBlueprint(I.Policy(uid).bp), "s_red"))
  T("  not twice", select(2, I.Insure(c, iid)) == "it is insured already" and money == 1000000 - 14300)
  local fc, fiid = weapon(A.HandItem("secondaries").data.uid)
  T("a free weapon: no insurance (it is given again)", select(2, I.Insure(fc, fiid)) ==
    "a free weapon is given again: it needs no insurance")
  T("only weapons", select(2, I.Insurable({ item_id = P.ITEM_ID, data = { uid = 5 } })) == "only weapons are insured")
  local _, g = A.Buy("glock_17")
  local gc, gid = weapon(g.uid)
  money = 100
  T("not enough money: nothing paid", select(2, I.Insure(gc, gid)) == "not enough money (" .. Money(1500) .. ")"
    and money == 100 and I.Policy(g.uid) == nil)
  money = 1000000
  PDTI.session_only = true
  T("not in a heist", select(2, I.Insure(gc, gid)) == "insurance is bought at home (the menu or the safehouse)")
  PDTI.session_only = false
  A.Reset()
  T("kept (the armory's file)", A._Data().policies[tostring(uid)] ~= nil and A._Data().policies[tostring(uid)].paid == 3300)
  local s = A._Sanitize({ next_uid = 2, policies = { ["0"] = { paid = 1, bp = "" }, x = { paid = 1, bp = "" },
      ["5"] = { bp = 3, paid = 1 }, ["6"] = { bp = "a" }, ["7"] = { paid = -10, bp = "a", name = "AMCAR" } },
    returns = { { data = { uid = 0, weapon_id = "amcar", factory_id = "f" }, due = 1 },
      { data = { uid = 9, weapon_id = "amcar", factory_id = "f", gun_set = 1, junk = {} }, due = 5, name = "AMCAR" },
      { data = { uid = 3, weapon_id = "amcar" }, due = 1 }, { data = { uid = 4, weapon_id = "amcar", factory_id = "f" } }, 7 },
    ended_at = 99 })
  local keys = {}
  for k in pairs(s.policies) do keys[#keys + 1] = k end
  T("  broken entries dropped", #keys == 1 and s.policies["7"].paid == 0 and #s.returns == 1 and s.returns[1].due == 5
    and s.returns[1].data.gun_set == 1 and s.returns[1].data.junk == nil and s.next_uid == 10 and s.ended_at == 99,
    #keys .. "/" .. #s.returns)
  T("  a new file has none", next(A._Sanitize(nil).policies) == nil and #A._Sanitize(nil).returns == 0)
end

---------------------------------------------------------- a failed heist

do
  fresh()
  local uid = gun(true)
  local _, _, before = weapon(uid)
  local plain = gun(false)
  heist()
  now = T0 + 30 -- the heist ends
  to_menu(false, function() now = T0 + 90 end) -- (the end screen: a minute)
  local d = A._Data()
  T("a failed heist: both weapons are gone at the menu", weapon(uid) == nil and weapon(plain) == nil)
  T("  the insured one is on its way back: 10 min after the heist ended", #d.returns == 1
    and d.returns[1].due == T0 + 30 + 600 and I.Policy(uid) == nil, d.returns[1] and d.returns[1].due - T0)
  T("  the screen's line: the clock time", I.ReturnLines()[1] == "Insurance: the AMCAR is back at "
    .. os.date("%H:%M", T0 + 630), I.ReturnLines()[1])
  T("  the uninsured one is lost as before", #weapons_of("amcar") == 0)
  now = T0 + 629
  T("  9:59 later: not yet", tick() == 0 and #weapons_of("amcar") == 0)
  hints = {}
  now = T0 + 630
  T("  10:00: in the locker", tick() == 1 and #weapons_of("amcar") == 1 and weapons_of("amcar")[1].container == "locker")
  local back = weapons_of("amcar")[1].data
  T("  with the build insured, a new uid, no magazine", back.blueprint == before.blueprint and back.uid ~= uid
    and back.gun_set == 1 and back.gun_n == 0 and not back.free, back.blueprint)
  T("  not insured any more (the insurance is used up)", I.Policy(back.uid) == nil and next(A._Data().policies) == nil)
  T("  you are told", hints[#hints] == "Insurance: your AMCAR is back in your locker", hints[#hints])
  T("  nothing on its way any more", #I.ReturnLines() == 0 and tick() == 0)
  A.Reset(); PDTI.LoadProfile()
  T("  saved (both files)", #weapons_of("amcar") == 1 and #A._Data().returns == 0)
  local uids = {}
  for _, w in ipairs(A.Weapons()) do uids[#uids + 1] = w.data.uid end
  local _, fresh_one = A.Buy("glock_17")
  T("  the next new weapon gets a uid of its own", not has(uids, fresh_one.uid))
end

------------------------------------------------------ the other losses

do -- the game quit in the heist: found at the next menu
  fresh()
  local uid = gun(true)
  heist()
  now = T0 + 100
  to_menu(nil)
  T("an abandoned heist: the weapon is on its way back from when it was found", weapon(uid) == nil
    and #A._Data().returns == 1 and A._Data().returns[1].due == T0 + 700)
end

do -- won, but left on the ground (Pick Up Weapons: an enemy's gun taken)
  fresh()
  local uid = gun(true)
  heist()
  A._dropped = { { data = { uid = uid } } }
  to_menu(true)
  T("won, the insured weapon left on the ground: it comes back", weapon(uid) == nil and #A._Data().returns == 1
    and I.Policy(uid) == nil)
end

do -- won, but thrown away in the heist
  fresh()
  local uid = gun(true)
  heist()
  local c, iid = weapon(uid)
  PDTI.RemoveItem(c, iid)
  to_menu(true)
  T("won, the insured weapon thrown away: it comes back once", weapon(uid) == nil and #A._Data().returns == 1)
  now = T0 + 600
  tick(); tick()
  T("  (one weapon)", #weapons_of("amcar") == 1)
end

do -- won with it: the insurance stays
  fresh()
  local uid = gun(true)
  heist()
  to_menu(true)
  T("a won heist keeps the weapon and its insurance", weapon(uid) ~= nil and I.Policy(uid) ~= nil
    and #A._Data().returns == 0)
  heist()
  to_menu(false)
  T("  a later loss still brings it back", #A._Data().returns == 1)
end

------------------------------------------------------ waiting, the places

do -- a full locker
  fresh()
  gun(true)
  heist()
  to_menu(false)
  local fillers = {}
  while true do
    local dd = A.MakeData("amcar", nil, A.NewUid())
    if not PDTI.AddItemAuto("locker", A.ITEM_ID, 1, dd, true) then break end
    fillers[#fillers + 1] = dd.uid
  end
  now = T0 + 600
  local had = #weapons_of("amcar")
  T("a full locker: it waits", tick() == 0 and #weapons_of("amcar") == had and #A._Data().returns == 1)
  T("  the screen says why", I.ReturnLines()[1] == "Insurance: the AMCAR is back, but your locker has no room for it",
    I.ReturnLines()[1])
  T("  logged once", logged("no room in the locker for the AMCAR back from the insurance"))
  local n = #ENV.logs
  now = now + 1; I.Tick()
  T("  (not every second)", #ENV.logs == n)
  local c, iid = weapon(fillers[1])
  PDTI.RemoveItem(c, iid)
  now = now + 1
  T("  room again: it comes", I.Tick() == 1 and #A._Data().returns == 0 and #weapons_of("amcar") == had)
end

do -- due while you are in a heist
  fresh()
  gun(true)
  heist()
  to_menu(false)
  heist()
  now = T0 + 700
  T("due in a heist: it waits for home", I.Tick() == 0 and #A._Data().returns == 1)
  to_menu(true)
  T("  the menu after it: in the locker", #A._Data().returns == 0 and #weapons_of("amcar") == 1)
end

do -- the safehouse: the tick brings it
  fresh()
  gun(true)
  heist()
  to_menu(false)
  managers.job = { current_job_id = function() return "chill" end }
  now = T0 + 600
  T("the safehouse: the tick brings it", I.Tick() == 1 and #weapons_of("amcar") == 1)
  local real, looks = I.Deliver, 0
  I.Deliver = function() looks = looks + 1; return 0 end
  A._Data().returns = { { data = A.MakeData("amcar", nil, A.NewUid()), due = now + 5, name = "AMCAR" } }
  I.Tick(); I.Tick()
  now = now + 1
  I.Tick()
  I.Deliver = real
  T("  once a second at most", looks == 1, looks)
  A._Data().returns = {}
  managers.job = nil
end

------------------------------------------------- cancelled, paid back

do
  fresh()
  local uid = gun(true)
  P.Buy("amcar", "b_supp")
  local after_buy = money
  hints = {}
  fit_home("b_supp", uid)
  T("a part fitted at home: the insurance is cancelled and paid back", I.Policy(uid) == nil and money == after_buy + 3300,
    money - after_buy)
  T("  said, with the new price", I.Note(uid) == "Insurance of the AMCAR cancelled: its build changed (" .. Money(3300)
    .. " back). Insure it again for " .. Money(3600) .. "." and hints[#hints] == I.Note(uid), I.Note(uid))
  local c, iid = weapon(uid)
  I.Insure(c, iid)
  T("  insured again: the note is gone", I.Policy(uid).paid == 3600 and I.Note(uid) == nil)
  local before = money
  P.TakeOff(c, iid, "b_supp")
  T("a part taken off at home: cancelled and paid back", I.Policy(uid) == nil and money == before + 3600)
  I.Insure(weapon(uid))
  local before2 = money
  T("Cancel: paid back", select(2, I.CancelItem(weapon(uid))) == "The AMCAR is not insured any more: " .. Money(3300)
    .. " back" and money == before2 + 3300 and I.Policy(uid) == nil)
  T("  nothing to cancel", select(2, I.CancelItem(weapon(uid))) == "it is not insured")
  I.Insure(weapon(uid))
  local before3 = money
  local sale = P.SellPrice(PDTI.FindItem(weapon(uid)))
  local ok, msg = P.Sell(weapon(uid))
  T("sold: the insurance paid back too, and said", ok and money == before3 + sale + 3300
    and msg:find("(its insurance: " .. Money(3300) .. " back)", 1, true) ~= nil and next(A._Data().policies) == nil, msg)
  local uid2 = gun(true)
  local before4 = money
  local c2, iid2 = weapon(uid2)
  PDTI.RemoveItem(c2, iid2) -- thrown away at home
  now = now + 1
  T("thrown away at home: paid back within a second", I.Tick() == 0 and money == before4 + 3300
    and next(A._Data().policies) == nil)
  local uid3 = gun(true)
  local before5 = money
  local c3, iid3 = weapon(uid3)
  PDTI.RemoveItem(c3, iid3)
  A.OnMenu()
  T("  and at the menu", money == before5 + 3300 and next(A._Data().policies) == nil)
  T("  (nothing to sweep: none)", I.Sweep() == 0)
  local uid4 = gun(true)
  local c4, iid4 = weapon(uid4)
  A._Data().after.gone = { uid4 }
  PDTI.RemoveItem(c4, iid4)
  local before6 = money
  T("a weapon a won heist lost, not taken out yet: not paid back (it is claimed then)", I.Sweep() == 0
    and money == before6 and I.Policy(uid4) ~= nil)
  A._Data().after.gone = {}
  I.Cancel(uid4)
  local uid5 = gun(true)
  local c5, iid5, d5 = weapon(uid5)
  T("the same build set again: still insured", I.OnBuildChanged(d5, d5.blueprint) == nil and I.Policy(uid5) ~= nil)
  PDTI.EditItems({ update = { { container = c5, instance_id = iid5, data = { blueprint = "amcar_body,amcar_mag" } } } })
  local before7 = money
  T("a build changed some other way: the sweep pays it back, with the note", I.Sweep() == 1 and money == before7 + 3300
    and tostring(I.Note(uid5)):find("its build changed", 1, true) ~= nil)
end

do -- the briefing: the heist has begun (not yet in it)
  fresh()
  gun(true)
  heist()
  to_menu(false)
  A.OnHeistStart()
  now = T0 + 700
  T("the briefing (the heist begun): nothing comes yet", tick() == 0 and #A._Data().returns == 1)
  A._Data().in_heist = false
  T("  (home again: it comes)", tick() == 1)
end

do -- a template applied
  fresh()
  local uid = gun(false)
  local Tm = PDTI.Templates
  local okt, t = Tm.Save((select(3, weapon(uid))))
  local c, iid = weapon(uid)
  P.TakeOff(c, iid, "s_red")
  I.Insure(weapon(uid))
  local before = money
  local id = type(t) == "table" and t.id or t
  Tm.Apply(id, weapon(uid))
  T("a build template applied at home: cancelled and paid back", okt
    and has(A.SplitBlueprint((select(3, weapon(uid))).blueprint), "s_red")
    and I.Policy(uid) == nil and money == before + 3000, money - before)
end

do -- a part fitted in a heist
  fresh()
  local uid = gun(true)
  P.Buy("amcar", "b_supp")
  move((part_items("b_supp")[1]).item.data.uid, "backpack")
  heist()
  local pc, pid = where_part("b_supp")
  local wc, wid = weapon(uid)
  H.Fit(pc, pid, wc, wid)
  for _ = 1, 10 do H.Tick(1, {}) end
  T("a part fitted in a heist: still insured there", has(A.SplitBlueprint((select(3, weapon(uid))).blueprint), "b_supp")
    and I.Policy(uid) ~= nil)
  local before = money
  to_menu(true)
  T("  home after the win: cancelled and paid back (the build changed)", I.Policy(uid) == nil and money == before + 3300
    and has(A.SplitBlueprint((select(3, weapon(uid))).blueprint), "b_supp"))
end

do -- lost with a build that is not the insured one (never at home): paid back
  fresh()
  local uid = gun(true)
  local other = { uid = uid, weapon_id = "amcar", blueprint = "amcar_body" }
  local before = money
  T("lost with another build: nothing comes back, the price does", I.Claim(other, T0) == false
    and #A._Data().returns == 0 and money == before + 3300 and I.Policy(uid) == nil)
  T("an uninsured weapon: no claim", I.Claim({ uid = 999, blueprint = "" }, T0) == false)
end

---------------------------------------------------------------- the screen

do
  fresh()
  ENV.install_menuui(false)
  local function windows() return ENV.menus[#ENV.menus].children end
  local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
  local uid = gun(true)
  -- In PRI: the free AMCAR to the locker, this one in its place.
  move(A.HandItem("primaries").data.uid, "locker")
  move(uid, "hand_primary")
  T("the screen opens", PDTI.ToggleUI() == true)
  named("pdti_shop"):find("shop_tab_locker"):click()
  local function marks(item)
    local n = 0
    for _, r in ipairs(item and item.rects or {}) do if r.params.name == "pdti_ins_mark" then n = n + 1 end end
    return n
  end
  local box = windows()[1]:find("weapon_box_primary")
  T("an insured weapon in PRI: the blue mark", box ~= nil and marks(box) == 1)
  T("  not the free Chimano in SEC", marks(windows()[1]:find("weapon_box_secondary")) == 0)
  move(uid, "locker")
  PDTI.RedrawUI()
  local c, iid = weapon(uid)
  local it = PDTI.FindItem(c, iid)
  local iw = PDTI.ItemSize(it, it.rotated == true, c)
  local shop = named("pdti_shop")
  local corner = shop:find(string.format("cell_locker_%d_%d", it.x + iw - 1, it.y))
  local first = shop:find(string.format("cell_locker_%d_%d", it.x, it.y))
  T("in the locker: the mark on its top-right cell only", marks(corner) == 1 and (iw == 1 or marks(first) == 0), iw)
  PDTI._UIInspect(c, it.x, it.y)
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  T("its view: insured, and the Cancel button", shop:find("inspect_insured").params.text ==
    "Insured: lost, it is back in your locker 10 min after the heist."
    and shop:find("inspect_uninsure").params.text == "Cancel insurance (" .. Money(3300) .. " back)"
    and shop:find("inspect_insure") == nil)
  local before = money
  shop:find("inspect_uninsure"):click()
  shop = named("pdti_shop")
  T("  Cancel: paid back, said", money == before + 3300 and shop:find("inspect_status").params.text ==
    "The AMCAR is not insured any more: " .. Money(3300) .. " back")
  T("  now the Insure button", shop:find("inspect_insure").params.text == "Insure for " .. Money(3300)
    .. " (back 10 min after a loss)" and shop:find("inspect_insured") == nil)
  shop:find("inspect_insure"):click()
  T("  a click insures it", I.Policy(uid) ~= nil and named("pdti_shop"):find("inspect_insured") ~= nil)
  named("pdti_shop"):find("inspect_close"):click()
  local fc, fid = weapon(A.HandItem("secondaries").data.uid)
  local fitem = PDTI.FindItem(fc, fid)
  PDTI._UIInspect(fc, fitem.x or 0, fitem.y or 0)
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  T("a free weapon's view: no insurance, said", shop:find("inspect_insure_free") ~= nil and shop:find("inspect_insure") == nil)
  shop:find("inspect_close"):click()
  -- Fitted at home: the note in the view.
  P.Buy("amcar", "b_supp")
  fit_home("b_supp", uid)
  c, iid = weapon(uid)
  it = PDTI.FindItem(c, iid)
  PDTI._UIInspect(c, it.x, it.y)
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  T("  after a change: the note above Insure", shop:find("inspect_insure_note") ~= nil
    and shop:find("inspect_insure_note").params.text:find("cancelled: its build changed", 1, true) ~= nil)
  -- Many parts, insured: the view fits 720p.
  local many = { "amcar_body", "amcar_barrel", "amcar_stock", "amcar_irons", "amcar_mag" }
  for i = 1, 17 do many[#many + 1] = "z_extra_" .. i end
  PDTI.EditItems({ update = { { container = c, instance_id = iid, data = { blueprint = A.JoinBlueprint(many) } } } })
  I.Insure(c, iid)
  PDTI.RedrawUI()
  local h = named("pdti_shop").ph
  T("  22 parts, insured: the view fits 720p", named("pdti_shop"):find("inspect_uninsure") ~= nil and h <= 720, h)
  named("pdti_shop"):find("inspect_close"):click()
  -- On its way back: the Locker tab and the market say when.
  move(uid, "backpack")
  heist()
  to_menu(false)
  PDTI.RedrawUI()
  named("pdti_shop"):find("shop_tab_locker"):click()
  local l = named("pdti_shop"):find("locker_return_1")
  T("on its way back: the Locker tab says when", l ~= nil and l.params.text == "Insurance: the AMCAR is back at "
    .. os.date("%H:%M", T0 + 600), l and l.params.text)
  T("  the locker still fits 720p", named("pdti_shop").ph <= 720, named("pdti_shop").ph)
  PDTI.SetUIOpen(false)
  T("the market opens", PDTI.OpenMarket() == true)
  named("pdti_shop"):find("market_tab_weapons"):click()
  local ml = named("pdti_shop"):find("wmarket_return_1")
  T("  its Weapons tab too", ml ~= nil and l ~= nil and ml.params.text == l.params.text)
  now = T0 + 600
  T("  it comes while the screen is open: drawn again", I.Tick() == 1 and named("pdti_shop"):find("wmarket_return_1") == nil)
  PDTI.SetUIOpen(false)
  T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
end

-- (Last: the inventory save remembers the rooms' tiers.)
------------------------------------------------------------------ Duke

do
  fresh()
  tiers.myh = 2
  local uid = gun(false)
  local c, iid, d = weapon(uid)
  T("Duke tier 2: insurance costs 20% (0.45.1)", I.Price(d) == 2200 and I.DelayText() == "10 min")
  I.Insure(c, iid)
  T("  paid so", I.Policy(uid).paid == 2200)
  heist()
  to_menu(false)
  T("  back 10 min after the heist, as without Duke", A._Data().returns[1].due == T0 + 600)
  tiers.myh = 3
  local uid3 = gun(false)
  local c3, iid3, d3 = weapon(uid3)
  T("Duke tier 3: still 20%, and back in 5 min", I.Price(d3) == 2200 and I.Delay() == 300 and I.DelayText() == "5 min")
  I.Insure(c3, iid3)
  heist()
  to_menu(false)
  T("  back 5 min after the heist", A._Data().returns[2] and A._Data().returns[2].due == T0 + 300)
  T("  (seconds when not whole minutes)", I.DelayText(90) == "90 s")
end

------------------------------------------------------------------ Houston (0.53.0)

do
  fresh()
  local open, insured = I.Weapons()
  T("Houston's lists: the free weapons in neither", #open == 0 and #insured == 0)
  T("  nothing to insure: Insure all says so", select(2, I.InsureAll()) == "no weapon to insure")
  -- (The pistol first: the list is in price order, not the order owned.)
  A._Data().stock.bought = {}
  local _, g = A.Buy("glock_17")
  local a = gun(false)
  local b = gun(false)
  -- (Named to sort before the AMCAR: price, not name, comes first.)
  do local gc, gi = weapon(g.uid); PDTI.EditItems({ update = { { container = gc, instance_id = gi, data = { name = "AA pistol" } } } }) end
  g = select(3, weapon(g.uid))
  local c, iid = weapon(b)
  I.Insure(c, iid)
  T("  one insured alone: written at once", (function() A.Reset(); return I.Policy(b) ~= nil end)())
  open, insured = I.Weapons()
  local pa, pg = I.Price(select(3, weapon(a))), I.Price(g)
  T("  not insured: dearest first, then by name; insured: by name", #open == 2 and open[1].data.uid == a
    and open[1].price == pa and pa > pg and open[2].data.uid == g.uid and open[2].price == pg
    and #insured == 1 and insured[1].data.uid == b)
  PDTI.session_only = true
  T("Insure all: not in a heist", select(2, I.InsureAll()) == "insurance is bought at home (the menu or the safehouse)",
    select(2, I.InsureAll()))
  PDTI.session_only = false
  money = pa + pg - 1
  T("  not enough money: nothing insured, the total said", select(2, I.InsureAll()) == "not enough money ("
    .. Money(pa + pg) .. ")" and money == pa + pg - 1 and I.Policy(a) == nil and I.Policy(g.uid) == nil)
  money = 10000
  local ok, msg = I.InsureAll()
  T("  insured: one payment, every weapon", ok and money == 10000 - pa - pg and I.Policy(a).paid == pa
    and I.Policy(g.uid).paid == pg and #(I.Weapons()) == 0)
  T("  said and logged", msg == "Insured 2 weapon(s) for " .. Money(pa + pg) .. ": lost, each is back in your locker "
    .. I.DelayText() .. " after the heist" and logged("insured 2 weapon(s) for " .. (pa + pg)), msg)
  T("  saved", (function() A.Reset(); return I.Policy(a) ~= nil and I.Policy(g.uid) ~= nil end)())
  local _, ins = I.Weapons()
  T("  the insured by name", #ins == 3 and ins[1].data.name == "AA pistol" and ins[3].data.name == "AMCAR",
    ins[1].data.name .. " / " .. tostring(ins[3].data.name))
  T("  its build kept for the claim", I.Policy(a).bp == select(3, weapon(a)).blueprint)
end

do
  fresh()
  local Home = PDTI.Safehouse
  local saved_cs = managers.custom_safehouse
  tweak_data.safehouse = { rooms = { { room_id = "american", name_id = "menu_american", tier_max = 3 },
    { room_id = "wild", name_id = "menu_wild", tier_max = 3 } } }
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
    for _, bt in ipairs(x.button_list) do if bt.text:sub(1, #prefix) == prefix then return bt end end
  end
  local function count(x, prefix)
    local n = 0
    for _, bt in ipairs(x.button_list) do if bt.text:sub(1, #prefix) == prefix then n = n + 1 end end
    return n
  end
  T("Houston's menu opens", Home.ShowRoomMenu("american") == true)
  local m = dialogs[#dialogs]
  T("  only free weapons: none insured, no buttons", m.text:find("None of your weapons is insured.", 1, true) ~= nil
    and button(m, "Insure") == nil and m.text:find("Not insured", 1, true) == nil)
  local uids = {}
  for i = 1, 6 do uids[i] = gun(false) end
  A._Data().stock.bought = {}
  local _, g = A.Buy("glock_17")
  local pa, pg = I.Price(select(3, weapon(uids[1]))), I.Price(g)
  Home.ShowRoomMenu("american")
  m = dialogs[#dialogs]
  T("  the uninsured named, 5 and the rest counted", m.text:find("Not insured: AMCAR, AMCAR, AMCAR, AMCAR, AMCAR and 2 more. "
    .. "Lost, an insured weapon is back in your locker " .. I.DelayText() .. " after the heist.", 1, true) ~= nil, m.text)
  T("  Insure all with the total", button(m, "Insure all").text == "Insure all (" .. Money(6 * pa + pg) .. ")",
    button(m, "Insure all").text)
  T("  one button per weapon, at most 5, dearest first", count(m, "Insure the ") == 5
    and m.button_list[2].text == "Insure the AMCAR (" .. Money(pa) .. ")")
  T("  the room's own lines stay", m.text:find("Tier 1 of 3", 1, true) ~= nil)
  hints = {}
  m.button_list[2].callback_func()
  T("a weapon's button insures it, the hint says so", #(I.Weapons()) == 6
    and hints[#hints]:find("Insured the AMCAR for " .. Money(pa), 1, true) == 1, hints[#hints])
  Home.ShowRoomMenu("american")
  m = dialogs[#dialogs]
  T("  the menu again: the insured named", m.text:find("Insured: AMCAR.", 1, true) ~= nil, m.text)
  -- One insured weapon lost: it is on its way back.
  A._Data().returns = { { data = A.MakeData("amcar", nil, A.NewUid()), due = now + 300, name = "AMCAR" } }
  Home.ShowRoomMenu("american")
  T("  a weapon on its way back: its line", dialogs[#dialogs].text:find("Insurance: the AMCAR is back at "
    .. os.date("%H:%M", now + 300), 1, true) ~= nil)
  A._Data().returns = {}
  button(dialogs[#dialogs], "Insure all").callback_func()
  T("Insure all from the menu: every one, the hint", #(I.Weapons()) == 0
    and hints[#hints]:find("Insured 6 weapon(s) for", 1, true) == 1, hints[#hints])
  Home.ShowRoomMenu("american")
  T("  all insured: no buttons, no 'not insured' line", button(dialogs[#dialogs], "Insure") == nil
    and dialogs[#dialogs].text:find("Not insured", 1, true) == nil
    and dialogs[#dialogs].text:find("and 2 more.", 1, true) ~= nil)
  Home.ShowRoomMenu("wild")
  T("not in another room", dialogs[#dialogs].text:find("insured", 1, true) == nil)
  local enabled = A.Enabled
  A.Enabled = function() return false end
  Home.ShowRoomMenu("american")
  T("the armory off: nothing about insurance", button(dialogs[#dialogs], "Insure") == nil
    and dialogs[#dialogs].text:find("insured", 1, true) == nil)
  A.Enabled = enabled
  managers.custom_safehouse = saved_cs
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
