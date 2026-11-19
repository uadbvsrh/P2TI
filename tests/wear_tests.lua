-- 0.47.0: weapon condition (armory_wear.lua). A weapon wears with every
-- round fired in a heist (rifles 100% -> 50% in 2,500 rounds, pistols and
-- snipers 3,500, LMGs 1,500, the minigun 1,000). Below 50% a shot may jam it
-- (up to 1 in 10 at 0%); a jammed gun does not start shooting until the
-- Clear Jam key racks it (1 s). Repaired at home for 20% of the built price
-- at 0%; a worn gun sells for less; the free weapons never wear.
--   luajit tests/wear_tests.lua
local script = arg and arg[0] or "tests/wear_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_wear") .. "/"
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
local A, P, H, I, WR = PDTI.Armory, PDTI.Parts, PDTI.HotMod, PDTI.Insurance, PDTI.Wear

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


-- The wear's clock and dice.
local clock = 100
WR.Now = function() return clock end
local roll = 0.99
WR.random = function() return roll end
local function wfresh()
  fresh()
  WR.ResetLive()
  WR.hint_t = nil
  clock, roll = 100, 0.99
end
local function cond_of(uid) local _, _, d = weapon(uid); return d and WR.Cond(d) end
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 1e-6 end

-- The game's weapon classes: fire, may it start shooting, the player's
-- trigger. (A base fires while it has rounds.)
_G.NewRaycastWeaponBase = {
  fire = function(self) if (self.rounds or 1) <= 0 then return nil end self.rounds = (self.rounds or 1000) - 1; return { hit = true } end,
  start_shooting_allowed = function() return true end
}
local trigger_seen = 0
_G.PlayerStandard = { _check_action_primary_attack = function() trigger_seen = trigger_seen + 1; return true end }
T("the hooks go in", WR.InstallHooks() == true)
T("  once (installing again changes nothing)", (function()
  local f = NewRaycastWeaponBase.fire; WR.InstallHooks(); return NewRaycastWeaponBase.fire == f end)())
local function gun_base(uid)
  local b = { _pdti_uid = uid, rounds = 100000, stopped = 0, clicks = 0 }
  b.stop_shooting = function(s) s.stopped = s.stopped + 1 end
  b.dryfire = function(s) s.clicks = s.clicks + 1 end
  return b
end
local function shoot(b, n) for _ = 1, n do NewRaycastWeaponBase.fire(b) end end

------------------------------------------------------------ the numbers

do
  W.test_mini = { categories = { "minigun" } }
  W.test_snp = { categories = { "snp" } }
  T("rounds to 50%: rifles 2,500", WR.Rounds("amcar") == 2500)
  T("  pistols 3,500 (akimbo pistols too)", WR.Rounds("glock_17") == 3500 and WR.Rounds("test_akimbo") == 3500)
  T("  snipers 3,500", WR.Rounds("test_snp") == 3500)
  T("  LMGs 1,500", WR.Rounds("test_smg") == 1500)
  T("  the minigun 1,000", WR.Rounds("test_mini") == 1000)
  T("  shotguns and unknown weapons 2,500", WR.Rounds("test_pump") == 2500 and WR.Rounds("nothing") == 2500)
  T("per round: 50 / rounds", near(WR.PerRound("amcar"), 0.02) and near(WR.PerRound("test_mini"), 0.05))
  T("jams: none at 100% or 50%", WR.JamChance(100) == 0 and WR.JamChance(50) == 0)
  T("  just below 50%: a little", WR.JamChance(49) > 0 and WR.JamChance(49) < 0.01)
  T("  25%: 1 in 20", near(WR.JamChance(25), 0.05))
  T("  0%: 1 in 10", near(WR.JamChance(0), 0.1))
  T("  out of range is clamped", near(WR.JamChance(-5), 0.1) and WR.JamChance(150) == 0)
  T("the text", WR.JamText(80) == "no jams" and WR.JamText(25) == "jams about 1 shot in 20"
    and WR.JamText(0) == "jams about 1 shot in 10")
  T("no data: 100%", WR.Cond(nil) == 100 and WR.Cond({}) == 100 and WR.Cond({ cond = "x" }) == 100)
  T("a stored condition", WR.Cond({ cond = 42.5 }) == 42.5 and WR.Cond({ cond = 0 / 0 }) == 100)
  T("a free weapon is always 100%", WR.Cond({ free = true, cond = 10 }) == 100)
end

------------------------------------------------------------ wearing

do
  wfresh()
  local uid = gun(false)
  local b = gun_base(uid)
  shoot(b, 10)
  T("at home (the menu) nothing wears", cond_of(uid) == 100 and next(WR.live) == nil)
  heist()
  shoot(b, 100)
  T("in a heist: 100 rifle rounds take 2%", near(cond_of(uid), 98), cond_of(uid))
  T("  the first shot wrote the file, the rest wait", A._Data().wear[tostring(uid)] ~= nil
    and near(A._Data().wear[tostring(uid)], 99.98), A._Data().wear[tostring(uid)])
  clock = clock + 30
  shoot(b, 1)
  T("  30 s later the next shot writes it", near(A._Data().wear[tostring(uid)], 97.98), A._Data().wear[tostring(uid)])
  local empty = gun_base(uid); empty.rounds = 0
  shoot(empty, 5)
  T("  a shot the game did not fire does not wear", near(cond_of(uid), 97.98))
  local free = gun_base(A.HandItem("secondaries").data.uid)
  shoot(free, 50)
  T("  the free Chimano never wears", WR.live[A.HandItem("secondaries").data.uid] == nil)
  shoot(gun_base(nil), 5)
  shoot(gun_base(9999), 5)
  T("  a gun that is not yours never wears", next(WR.live) == uid and next(WR.live, uid) == nil)
  local second = { parent_weapon = { base = function() return b end }, rounds = 10 }
  shoot(second, 10)
  T("  an akimbo second gun wears its pair", near(cond_of(uid), 97.78), cond_of(uid))
  to_menu(true)
  T("won: the wear is on the weapon at the menu", near(cond_of(uid), 97.78) and next(A._Data().wear) == nil,
    cond_of(uid))
  T("  and it stays after loading again", (function() PDTI.LoadProfile(); return near(cond_of(uid), 97.78) end)())
  T("  nothing left in this heist's memory", next(WR.live) == nil)
end

do
  wfresh()
  local uid = gun(false)
  heist()
  shoot(gun_base(uid), 250)
  to_menu(nil)
  T("the game quit in a heist: the wear written is kept (the weapon is lost)", cond_of(uid) == nil
    and next(A._Data().wear) == nil)
  wfresh()
  uid = gun(true)
  heist()
  shoot(gun_base(uid), 250)
  to_menu(false)
  local r = A._Data().returns[1]
  T("failed, insured: it comes back as worn as it was lost (95%)", r ~= nil and near(r.data.cond, 95),
    r and r.data.cond)
  now = T0 + 600
  tick()
  local back = A.Weapons()
  local got
  for _, w in ipairs(back) do if w.data.weapon_id == "amcar" and not w.data.free then got = w.data end end
  T("  in the locker at 95%", got ~= nil and near(WR.Cond(got), 95), got and got.cond)
end

do
  wfresh()
  local uid = gun(false)
  heist()
  shoot(gun_base(uid), 500)
  WR.Flush()
  -- The next day of the heist: the inventory is the plan again.
  PDTI.LoadProfile()
  heist()
  T("the next day of a heist goes on from the wear written", near(WR.live[uid], 90), WR.live[uid])
  shoot(gun_base(uid), 500)
  to_menu(true)
  T("  two days: 80%", near(cond_of(uid), 80), cond_of(uid))
end

do
  wfresh()
  managers.job = { current_job_id = function() return "chill" end }
  local uid = gun(false)
  shoot(gun_base(uid), 100)
  T("nothing wears in the safehouse", next(WR.live) == nil and cond_of(uid) == 100)
  managers.job = nil
end

------------------------------------------------------------ the file

do
  local d = A._Sanitize({ wear = { ["5"] = 42.25, ["6"] = 150, ["7"] = -3, ["0"] = 10, x = 5, ["8"] = "y" } })
  T("the file: wear by uid, clamped, nonsense dropped", d.wear["5"] == 42.25 and d.wear["6"] == 100
    and d.wear["7"] == 0 and d.wear["0"] == nil and d.wear.x == nil and d.wear["8"] == nil)
  T("  none: empty", next(A._Sanitize({}).wear) == nil and next(A._Sanitize(nil).wear) == nil)
  local c = A._Sanitize({ captured = { { data = { uid = 3, weapon_id = "amcar", factory_id = "f", cond = 61 } } },
    returns = { { data = { uid = 4, weapon_id = "amcar", factory_id = "f", cond = 33 }, due = 1 } } })
  T("  a captured or returning weapon keeps its condition", c.captured[1].data.cond == 61 and c.returns[1].data.cond == 33)
end

------------------------------------------------------------ jams

do
  wfresh()
  local uid = gun(false)
  heist()
  local b = gun_base(uid)
  roll = 0
  WR.live[uid] = 50.03
  shoot(b, 1)
  T("at 50% or above it never jams, even with the worst roll", not WR.jammed[uid])
  shoot(b, 1)
  T("below 50% the roll jams it", WR.jammed[uid] == true and WR.IsJammed(b))
  T("  the automatic fire stops", b.stopped == 1)
  T("  the hint names the key", hints[#hints] == WR.JAM_HINT)
  T("  the file is written at once", near(A._Data().wear[tostring(uid)], 49.99), A._Data().wear[tostring(uid)])
  T("a jammed gun may not start shooting", NewRaycastWeaponBase.start_shooting_allowed(b) == false)
  T("  another gun still may", NewRaycastWeaponBase.start_shooting_allowed(gun_base(A.HandItem("secondaries").data.uid)) == true)
  local ps = { _equipped_unit = { base = function() return b end } }
  local seen = trigger_seen
  PlayerStandard._check_action_primary_attack(ps, 1, { btn_primary_attack_press = true })
  T("  the trigger pressed: a click, the game's own check still runs", b.clicks == 1 and trigger_seen == seen + 1)
  PlayerStandard._check_action_primary_attack(ps, 1, { btn_primary_attack_state = true })
  T("  held: no more clicks", b.clicks == 1)
  -- Clearing.
  PDTI.Ammo.EquippedBase = function() return b end
  T("Clear Jam starts", WR.StartClear() == true and hints[#hints] == "Clearing the jam...")
  T("  pressed again: nothing new", WR.StartClear() == false)
  clock = clock + 0.5
  T("  half a second: still jammed", WR.Tick() == false and WR.IsJammed(b))
  clock = clock + 0.5
  T("  1 s: cleared", WR.Tick() == true and not WR.IsJammed(b) and hints[#hints] == "Jam cleared")
  T("  it may shoot again", NewRaycastWeaponBase.start_shooting_allowed(b) == true)
  T("  no clear in progress: the tick does nothing", WR.Tick() == false)
  WR.hint_t = nil
  T("Clear Jam on a gun that is fine: said", WR.StartClear() == false and hints[#hints] == "Your gun is not jammed")
  -- Switching weapons stops the clear.
  WR.jammed[uid] = true
  WR.hint_t = nil
  WR.StartClear()
  local other = gun_base(A.HandItem("secondaries").data.uid)
  PDTI.Ammo.EquippedBase = function() return other end
  clock = clock + 5
  T("switching weapons stops the clear", WR.Tick() == false and WR.IsJammed(b) and WR.clearing == nil
    and hints[#hints] == "Clearing the jam stopped: the gun is still jammed")
  -- Reloading stops it too.
  PDTI.Ammo.EquippedBase = function() return b end
  WR.hint_t = nil
  WR.StartClear()
  local st = { _is_reloading = function() return true end }
  local saved = managers.player
  managers.player = { player_unit = function() return { movement = function() return { current_state = function() return st end } end } end }
  T("reloading stops it", WR.Tick() == false and WR.IsJammed(b) and WR.clearing == nil)
  managers.player = saved
  -- A jam does not jam again, and is not saved.
  roll = 0
  local n = b.stopped
  shoot(b, 1)
  T("a jammed gun (fired some other way) does not jam twice", b.stopped == n)
  to_menu(true)
  T("back home: no jam left", next(WR.jammed) == nil)
  PDTI.Ammo.EquippedBase = nil
  T("the hint waits 2 s between repeats", (function()
    hints = {}; WR.hint_t = nil; clock = 200
    PDTI.Hint = function(t) hints[#hints + 1] = t end
    WR.StartClear(); WR.StartClear(); clock = 202.5; WR.StartClear()
    return #hints == 2 end)())
end

------------------------------------------------------------ repair and sale

do
  wfresh()
  local uid = gun(false)
  local c, iid, d = weapon(uid)
  T("a new weapon needs no repair", WR.RepairPrice(d) == 0 and select(2, WR.Repair(c, iid)) == "it is in full condition")
  local full_sale = P.SellPrice(PDTI.FindItem(c, iid))
  PDTI.EditItems({ update = { { container = c, instance_id = iid, data = { cond = 50 } } } })
  c, iid, d = weapon(uid)
  T("repair at 50%: 10% of the built price (11,000)", WR.RepairPrice(d) == 1100, WR.RepairPrice(d))
  PDTI.EditItems({ update = { { container = c, instance_id = iid, data = { cond = 0 } } } })
  c, iid, d = weapon(uid)
  T("  at 0%: 20%", WR.RepairPrice(d) == 2200)
  local zero_sale = P.SellPrice(PDTI.FindItem(c, iid))
  T("a gun at 0% sells for half", math.abs(zero_sale * 2 - full_sale) <= 1, zero_sale .. " / " .. full_sale)
  PDTI.session_only = true
  T("no repair in a heist", select(2, WR.Repair(c, iid)) == "weapons are repaired at home (the menu or the safehouse)")
  PDTI.session_only = false
  money = 100
  T("not enough money: said", select(2, WR.Repair(c, iid)) == "not enough money (" .. Money(2200) .. ")"
    and cond_of(uid) == 0)
  money = 10000
  local ok, msg = WR.Repair(c, iid)
  T("repaired: paid, 100%", ok and money == 7800 and cond_of(uid) == 100 and msg == "Repaired the AMCAR for "
    .. Money(2200) .. ": 100%", msg)
  local fc, fid = weapon(A.HandItem("secondaries").data.uid)
  T("a free weapon: no repair", select(2, WR.Repair(fc, fid)) == "a free weapon never wears"
    and WR.RepairPrice(A.HandItem("secondaries").data) == 0)
  T("no such weapon", select(2, WR.Repair("locker", 99999)) == "no weapon")
end

------------------------------------------------------------ Rust (0.50.0)

local function set_cond(uid, v)
  local c, iid = weapon(uid)
  PDTI.EditItems({ update = { { container = c, instance_id = iid, data = { cond = v } } } })
end

do
  wfresh()
  T("nothing worn: an empty list, Repair all says so", #WR.Worn() == 0
    and select(2, WR.RepairAll()) == "your weapons are in full condition")
  local a, b = gun(false), gun(false)
  A._Data().stock.bought = {}
  local _, g = A.Buy("glock_17")
  set_cond(a, 50); set_cond(b, 20); set_cond(g.uid, 20)
  local worn = WR.Worn()
  T("worn: worst first, then by name; free and full ones left out", #worn == 3 and worn[1].data.uid == b
    and worn[2].data.uid == g.uid and worn[3].data.uid == a, #worn)
  T("  with their condition and price", worn[1].cond == 20 and worn[1].price == 1760 and worn[2].price == 800
    and worn[3].price == 1100, worn[1].price .. " " .. worn[2].price .. " " .. worn[3].price)
  PDTI.session_only = true
  T("Repair all: not in a heist", select(2, WR.RepairAll()) == "weapons are repaired at home (the menu or the safehouse)")
  PDTI.session_only = false
  money = 3000
  T("  not enough money: nothing repaired, the total said", select(2, WR.RepairAll())
    == "not enough money (" .. Money(3660) .. ")" and money == 3000 and cond_of(a) == 50 and cond_of(b) == 20)
  money = 10000
  local ok, msg = WR.RepairAll()
  T("  repaired: one payment, every weapon 100%", ok and money == 10000 - 3660 and cond_of(a) == 100
    and cond_of(b) == 100 and cond_of(g.uid) == 100 and #WR.Worn() == 0)
  T("  said and logged", msg == "Repaired 3 weapon(s) for " .. Money(3660) .. ": 100%" and logged("repaired 3 weapon(s) for 3660"))
  local enabled = A.Enabled
  A.Enabled = function() return false end
  T("  the armory off: no", select(2, WR.RepairAll()) == "the armory is off (restoration-mod or no stash)")
  A.Enabled = enabled
end

do
  wfresh()
  local Home = PDTI.Safehouse
  local saved_cs = managers.custom_safehouse
  tweak_data.safehouse = { rooms = { { room_id = "wild", name_id = "menu_wild", tier_max = 3 },
    { room_id = "russian", name_id = "menu_russian", tier_max = 3 } } }
  managers.custom_safehouse = {
    _global = { rooms = {} },
    get_room_current_tier = function() return 1 end, get_room_max_tier = function() return 3 end,
    get_next_tier_unlocked = function() return 2 end, get_upgrade_cost = function() return 0 end,
    can_afford_room_tier = function() return false end, coins = function() return 0 end,
    purchase_room_tier = function() end, set_room_tier = function() end
  }
  managers.localization = managers.localization or { text = function(_, id) return id end }
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
  T("Rust's menu opens", Home.ShowRoomMenu("wild") == true)
  local m = dialogs[#dialogs]
  T("  nothing worn: said, no repair buttons", m.text:find("Your weapons are in full condition.", 1, true) ~= nil
    and button(m, "Repair") == nil)
  local uids = {}
  for i = 1, 6 do uids[i] = gun(false); set_cond(uids[i], 10 * i) end
  money = 1000000
  Home.ShowRoomMenu("wild")
  m = dialogs[#dialogs]
  T("  the worn line: worst first, 5 named and the rest counted", m.text:find("Worn: AMCAR 10%, AMCAR 20%, AMCAR 30%, "
    .. "AMCAR 40%, AMCAR 50% and 1 more", 1, true) ~= nil, m.text)
  local all = button(m, "Repair all")
  local total = 0
  for _, w in ipairs(WR.Worn()) do total = total + w.price end
  T("  Repair all with the total", all ~= nil and all.text == "Repair all (" .. Money(total) .. ")", all and all.text)
  T("  one button per weapon, at most 5, worst first", count(m, "Repair the ") == 5
    and m.button_list[2].text == "Repair the AMCAR, 10% (" .. Money(1980) .. ")", m.button_list[2].text)
  T("  the room's own lines stay", m.text:find("Tier 1 of 3", 1, true) ~= nil)
  hints = {}
  PDTI.Hint = function(t) hints[#hints + 1] = t end
  m.button_list[2].callback_func()
  T("a weapon's button repairs it, the hint says so", cond_of(uids[1]) == 100 and cond_of(uids[2]) == 20
    and hints[#hints] == "Repaired the AMCAR for " .. Money(1980) .. ": 100%", hints[#hints])
  Home.ShowRoomMenu("wild")
  T("  the menu again: 5 worn, none more", dialogs[#dialogs].text:find("AMCAR 60%", 1, true) ~= nil
    and dialogs[#dialogs].text:find("more", 1, true) == nil)
  button(dialogs[#dialogs], "Repair all").callback_func()
  T("Repair all repairs every one, the hint says so", #WR.Worn() == 0
    and hints[#hints]:find("Repaired 5 weapon(s) for", 1, true) == 1, hints[#hints])
  set_cond(uids[1], 10)
  Home.ShowRoomMenu("russian")
  T("not in another room", button(dialogs[#dialogs], "Repair") == nil
    and dialogs[#dialogs].text:find("Worn:", 1, true) == nil)
  local enabled = A.Enabled
  A.Enabled = function() return false end
  Home.ShowRoomMenu("wild")
  T("the armory off: nothing about repairs", button(dialogs[#dialogs], "Repair") == nil
    and dialogs[#dialogs].text:find("Worn:", 1, true) == nil
    and dialogs[#dialogs].text:find("full condition", 1, true) == nil)
  A.Enabled = enabled
  managers.custom_safehouse = saved_cs
end

------------------------------------------------------------ the screen

do
  wfresh()
  ENV.install_menuui(false)
  local function windows() return ENV.menus[#ENV.menus].children end
  local function named(n) for _, w in ipairs(windows()) do if w.params.name == n then return w end end end
  local function bars(item)
    local n, w = 0, nil
    for _, r in ipairs(item and item.rects or {}) do
      if r.params.name == "pdti_wear_bar" then n = n + 1; w = r.params.w end
    end
    return n, w
  end
  local uid = gun(false)
  move(A.HandItem("primaries").data.uid, "locker")
  move(uid, "hand_primary")
  T("the screen opens", PDTI.ToggleUI() == true)
  T("a weapon at 100%: no bar", bars(windows()[1]:find("weapon_box_primary")) == 0)
  local c, iid = weapon(uid)
  PDTI.EditItems({ update = { { container = c, instance_id = iid, data = { cond = 40 } } } })
  PDTI.RedrawUI()
  local box = windows()[1]:find("weapon_box_primary")
  local n, bw = bars(box)
  T("worn, in PRI: the bar", n == 1)
  T("  as long as its condition", bw ~= nil and bw < box.params.w * 0.5, bw)
  T("  the free Chimano in SEC: none", bars(windows()[1]:find("weapon_box_secondary")) == 0)
  move(uid, "locker")
  named("pdti_shop"):find("shop_tab_locker"):click()
  c, iid = weapon(uid)
  local it = PDTI.FindItem(c, iid)
  local shop = named("pdti_shop")
  T("in the locker: the bar on its first cell only", bars(shop:find(string.format("cell_locker_%d_%d", it.x, it.y))) == 1
    and bars(shop:find(string.format("cell_locker_%d_%d", it.x + 1, it.y))) == 0)
  PDTI._UIInspect(c, it.x, it.y)
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  T("its view: the condition and the jams", shop:find("inspect_condition") ~= nil
    and shop:find("inspect_condition").params.text == "Condition 40%: jams about 1 shot in 50.",
    shop:find("inspect_condition") and shop:find("inspect_condition").params.text)
  T("  the Repair button", shop:find("inspect_repair") ~= nil and shop:find("inspect_repair").params.text
    == "Repair for " .. Money(1320) .. " (to 100%)")
  T("  the view fits 720p", shop.ph <= 720, shop.ph)
  local before = money
  shop:find("inspect_repair"):click()
  shop = named("pdti_shop")
  T("  a click repairs it", money == before - 1320 and cond_of(uid) == 100
    and shop:find("inspect_status").params.text == "Repaired the AMCAR for " .. Money(1320) .. ": 100%")
  T("  now no Repair button", shop:find("inspect_repair") == nil)
  shop:find("inspect_close"):click()
  local fc, fid = weapon(A.HandItem("secondaries").data.uid)
  local fitem = PDTI.FindItem(fc, fid)
  PDTI._UIInspect(fc, fitem.x or 0, fitem.y or 0)
  PDTI.RedrawUI()
  shop = named("pdti_shop")
  T("a free weapon's view: no condition, no repair", shop:find("inspect_condition") == nil and shop:find("inspect_repair") == nil)
  PDTI.SetUIOpen(false)
  T("only documented MenuUI parameters used", #ENV.violations == 0, table.concat(ENV.violations, ","))
end


------------------------------------------------------------ edges (mutation check)

do
  wfresh()
  local uid = gun(false)
  heist()
  local b = gun_base(uid)
  shoot(b, 1)
  A.Reset()
  T("the wear is in the file on disk", A._Data().wear[tostring(uid)] ~= nil)
  T("  a flush with nothing new writes nothing", WR.Flush() == false)
  shoot(b, 1)
  T("  with something new it writes", WR.Flush() == true and WR.Flush() == false)
  T("  what it knows of a gun is kept (looked up once)", WR.known[uid] and WR.known[uid].weapon_id == "amcar")
  shoot(gun_base(9999), 1)
  T("  not yours: known as not", WR.known[9999] == false)
  local real = PDTI.FindItems
  local looks = 0
  PDTI.FindItems = function(...) looks = looks + 1; return real(...) end
  shoot(b, 3); shoot(gun_base(9999), 3)
  PDTI.FindItems = real
  T("  so no lookups per shot", looks == 0, looks)
  T("the game's fire result goes through", type(NewRaycastWeaponBase.fire(b)) == "table")
  -- A jam right after another hint: still said.
  roll = 0
  WR.live[uid] = 10
  hints = {}
  PDTI.Hint = function(t) hints[#hints + 1] = t end
  WR.hint_t = clock
  shoot(b, 1)
  T("a jam is said even right after another hint", hints[#hints] == "Your gun jammed: press Clear Jam (a key in the mod's key binds)")
  -- The trigger on the jammed gun, the hint again (after 2 s).
  clock = clock + 3
  hints = {}
  PlayerStandard._check_action_primary_attack({ _equipped_unit = { base = function() return b end } }, 1,
    { btn_primary_attack_press = true })
  T("  the trigger pressed on it: the hint", hints[1] == WR.JAM_HINT)
  -- An akimbo second gun jams: the pair stops.
  WR.jammed = {}
  local before = b.stopped
  shoot({ parent_weapon = { base = function() return b end }, rounds = 5 }, 1)
  T("an akimbo second gun jams: the pair's fire stops", b.stopped == before + 1 and WR.IsJammed(b))
  PDTI.Ammo.EquippedBase = function() return b end
  WR.StartClear()
  -- The next day: no jam, no clear in progress, the first shot writes.
  WR.Flush()
  PDTI.LoadProfile()
  heist()
  T("the next day starts with no jam and no clear", next(WR.jammed) == nil and WR.clearing == nil)
  roll = 0.99
  shoot(b, 1)
  T("  its first shot writes the file", WR.dirty == false)
  PDTI.Ammo.EquippedBase = nil
  to_menu(true)
  T("back home: the heist's memory is empty", next(WR.live) == nil and next(WR.known) == nil)
end

do
  wfresh()
  local uid = gun(false)
  local d = A._Data()
  d.wear = { [tostring(uid)] = 70, ["777"] = 40 }
  T("not final: the weapons there get their wear, a weapon to come waits", WR.Apply(false) == 1
    and near(cond_of(uid), 70) and d.wear["777"] == 40 and d.wear[tostring(uid)] == nil)
  A.Reset()
  T("  (written)", A._Data().wear["777"] == 40)
  d = A._Data()
  T("  final: what is not there is dropped", WR.Apply(true) == 0 and next(d.wear) == nil)
  -- A clear stopped right after it started: said at once.
  WR.jammed = { [uid] = true }
  local jb = gun_base(uid)
  PDTI.Ammo.EquippedBase = function() return jb end
  WR.hint_t = nil
  WR.StartClear()
  PDTI.Ammo.EquippedBase = function() return nil end
  clock = clock + 0.3
  WR.Tick()
  T("a clear stopped at once is said at once", hints[#hints] == "Clearing the jam stopped: the gun is still jammed")
  PDTI.Ammo.EquippedBase = nil
  WR.jammed = {}
  local c, iid = weapon(uid)
  local on = A.Enabled
  A.Enabled = function() return false end
  T("the armory off: no repair", select(2, WR.Repair(c, iid)) == "the armory is off (restoration-mod or no stash)")
  WR.live[uid] = 1
  PDTI.session_only = true
  local b = gun_base(uid)
  shoot(b, 10)
  T("  and no wear", WR.live[uid] == 1)
  PDTI.session_only = false
  A.Enabled = on
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
