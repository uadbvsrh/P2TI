-- 0.36.0: the armory. Weapons bought at the game's prices changed per day,
-- only as many as are for sale; a failed or left heist loses the weapons you
-- brought; there is no restart.
-- 0.37.0: every weapon is a grid item (the locker, the hand slots, packed in
-- the backpack); the game's weapon slots mirror your hands.
--   luajit tests/armory_tests.lua
local script = arg and arg[0] or "tests/armory_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_armory") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

-- The game's weapons (only what the mod reads).
local W = tweak_data.weapon
W.amcar = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AMCAR" }
W.new_m4 = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "CAR-4" }
W.glock_17 = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "Chimano 88" }
W.five_seven = { use_data = { selection_index = 1 }, categories = { "pistol" }, name_id = "5/7 AP" }
W.locked_gun = { use_data = { selection_index = 2 }, categories = { "snp" }, name_id = "Locked" }
W.m4_npc = { categories = { "assault_rifle" } } -- an enemy's: not for sale
local FACTORY = { amcar = "wpn_fps_ass_amcar", new_m4 = "wpn_fps_ass_m4", glock_17 = "wpn_fps_pis_g17",
  five_seven = "wpn_fps_pis_lemming", locked_gun = "wpn_fps_snp_locked" }
local PRICE = { amcar = 10000, new_m4 = 40000, glock_17 = 5000, five_seven = 30000, locked_gun = 90000 }

-- The game's classes the armory hooks (they exist before the mod loads).
local calls = {}
local locked_ids = { locked_gun = true }
_G.BlackMarketManager = {
  weapon_unlocked = function(_, id) return not locked_ids[id] end,
  _calculate_weapon_concealment = function() return 30 end,
  -- the game's equipped weapons: slot 1 of its lists
  equipped_primary = function() return Global.blackmarket_manager.crafted_items.primaries[1] end,
  equipped_secondary = function() return Global.blackmarket_manager.crafted_items.secondaries[1] end,
  _update_menu_scene_primary = function() calls.scene_primary = (calls.scene_primary or 0) + 1 end,
  _update_menu_scene_secondary = function() calls.scene_secondary = (calls.scene_secondary or 0) + 1 end,
  -- the game reads its save: its own weapon slots again
  load = function(_, d) Global.blackmarket_manager = d.blackmarket end
}
_G.MenuCallbackHandler = {
  singleplayer_restart = function() return true end,
  _restart_level_visible = function() return true end,
  restart_game = function() calls.restart_game = true end,
  restart_level = function() calls.restart_level = true end,
  _update_outfit_information = function() calls.outfit = (calls.outfit or 0) + 1 end
}
_G.VoteManager = { restart = function() calls.vote = true end, restart_auto = function() calls.vote_auto = true end }
_G.MissionEndState = {
  at_enter = function() end,
  _continue_blocked = function() return false end,
  _shut_down_network = function() calls.shut = "mission" end,
  _load_start_menu = function() calls.menu = "mission" end
}
_G.GameOverState = {
  _shut_down_network = function() calls.shut = "gameover" end,
  _load_start_menu = function() calls.menu = "gameover" end,
  continue = function() calls.continue = "lobby" end
}
_G.BlackMarketGui = {
  buy_weapon_callback = function() calls.gui_buy = true end,
  choose_weapon_mods_callback = function() calls.gui_mod = true end,
  sell_item_callback = function(_, d) calls.gui_sell = d.category end
}
_G.LootManager = { get_secured_bonus_bags_value = function() return 0 end,
  get_secured_mandatory_bags_value = function() return 0 end }
_G.ElementCarry = { on_executed = function() end }
_G.HUDStageEndScreen = { update = function() end }

ENV.load_mod(ROOT, false)
local A, Stash = PDTI.Armory, PDTI.Stash
Stash.InstallHooks()

local money, deducted = 100000, 0
managers.money = {
  total = function() return money end,
  deduct_from_total = function(_, v) money = money - v; deducted = deducted + 1 end,
  add_to_total = function(_, v) money = money + v end,
  get_payouts = function() return {} end,
  get_weapon_price_modified = function(_, id) return PRICE[id] end,
  get_weapon_modify_price = function() return 1000 end
}
managers.weapon_factory = {
  get_factory_id_by_weapon_id = function(_, id) return FACTORY[id] end,
  get_default_blueprint_by_factory_id = function(_, f) return { f .. "_body", f .. "_barrel" } end
}
managers.blackmarket = setmetatable({}, { __index = BlackMarketManager })
local told = {}
managers.system_menu = { show = function(_, d) told[#told + 1] = d.text end }
managers.localization = { text = function(_, id) return id end }
local job = "branchbank"
managers.job = { current_job_id = function() return job end, on_last_stage = function() return true end }
managers.loot = setmetatable({ _global = { secured = {} } }, { __index = LootManager })
ENV.game.unit = nil -- the menu: no player
PDTI.session_only = false
_G.Global = _G.Global or {}
Global.blackmarket_manager = { crafted_items = {
  primaries = { { weapon_id = "new_m4", factory_id = "wpn_fps_ass_m4", blueprint = { "x" }, equipped = true },
    { weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar", blueprint = {} } },
  secondaries = { { weapon_id = "glock_17", factory_id = "wpn_fps_pis_g17", blueprint = {}, equipped = true } }
} }
local crafted = Global.blackmarket_manager.crafted_items

local M = PDTI.Market
local day = "2026-11-17"
M.Today = function() return day end
local factor_roll, stock_roll = {}, {}
A.FactorRoll = function(id) return factor_roll[id] or 0.5 end
A.StockRoll = function(id) return stock_roll[id] or 0.99 end

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
  job = "branchbank"
end
local function where(uid)
  for _, w in ipairs(A.Weapons()) do if w.data.uid == uid then return w.container, w.instance_id end end
  return nil
end
local function move(uid, to, x, y)
  local c, id = where(uid)
  return PDTI.MoveItem(c, id, to, x or 0, y or 0, false)
end

------------------------------------------------------------- the market

fresh()
local rows = A.Catalog()
local ids = {}
for i, r in ipairs(rows) do ids[i] = r.weapon_id end
T("the catalog: every weapon you may have (not locked, not an enemy's)", #rows == 4
  and not table.concat(ids, ","):find("locked") and not table.concat(ids, ","):find("npc"), table.concat(ids, ","))
T("  primaries first, then by name", rows[1].category == "primaries" and rows[3].category == "secondaries"
  and rows[1].name == "AMCAR" and rows[2].name == "CAR-4", rows[1].name)
factor_roll.five_seven, stock_roll.five_seven = 5 / 6, 0.3
local r57
for _, r in ipairs(A.Catalog()) do if r.weapon_id == "five_seven" then r57 = r end end
T("the 5/7 today: dearer than its normal price", r57.normal == 30000 and r57.today == 36000, r57.today)
T("  and 1 for sale", r57.stock == 1, r57.stock)
T("  its change is shown", A.FactorText("five_seven") == "+20%", A.FactorText("five_seven"))
T("  a normal price: no change shown", A.FactorText("amcar") == "", A.FactorText("amcar"))
factor_roll.glock_17 = 0
T("the cheapest a day can make it: 30% off", A.TodayPrice("glock_17") == 3500, A.TodayPrice("glock_17"))
factor_roll.glock_17 = 1
T("the dearest: 30% on", A.TodayPrice("glock_17") == 6500, A.TodayPrice("glock_17"))
stock_roll.new_m4 = 0.1
T("some weapons are not for sale on a day", A.Stock("new_m4") == 0)
stock_roll.amcar = 0.99
T("at most 3 for sale", A.Stock("amcar") == 3)

local ok, wd = A.Buy("five_seven")
T("buying: a weapon item in the locker, as the game builds it", ok and wd and where(wd.uid) == "locker"
  and wd.factory_id == "wpn_fps_pis_lemming" and wd.blueprint == "wpn_fps_pis_lemming_body,wpn_fps_pis_lemming_barrel"
  and wd.category == "secondaries" and wd.name == "5/7 AP", tostring(wd and wd.blueprint))
local item = PDTI.FindItem("locker", select(2, where(wd.uid)))
T("  a pistol takes 2x1 and weighs what the loadout says", item.data.w == 2 and item.data.h == 1
  and PDTI.ItemWeight(item) == PDTI.Loadout.WeaponWeight({ "pistol" }, 30), PDTI.ItemWeight(item))
T("  you pay today's price", money == 1000000 - 36000, money)
T("  none left today", A.Stock("five_seven") == 0)
local ok2, why2 = A.Buy("five_seven")
T("  the next one: none for sale", not ok2 and tostring(why2):find("none for sale") ~= nil, why2)
day = "2026-11-18"
T("a new day: new stock", A.Stock("five_seven") == 1)
day = "2026-11-17"
money = 100
local before = A.Stock("amcar")
local ok3, why3 = A.Buy("amcar")
T("not enough money: refused, nothing taken, the stock stays", not ok3 and money == 100 and A.Stock("amcar") == before
  and tostring(why3):find("money") ~= nil and #A.Weapons() == 1, why3)
money = 100000
T("a locked weapon cannot be bought", not A.Buy("locked_gun"))
T("  nor an enemy's", not A.Buy("m4_npc"))
PDTI.session_only = true
local ok4, why4 = A.Buy("amcar")
T("in a heist the market is closed", not ok4 and tostring(why4):find("heist") ~= nil, why4)
PDTI.session_only = false
-- A full locker: refused before any money is taken.
local real_find = PDTI.FindFreeSpace
PDTI.FindFreeSpace = function(c, ...) if c == "locker" then return nil, "no free space" end return real_find(c, ...) end
local m0, d0 = money, deducted
local ok5, why5 = A.Buy("amcar")
T("a full locker: refused before paying (nothing taken, nothing given back)", not ok5 and money == m0 and deducted == d0
  and tostring(why5):find("locker is full") ~= nil, why5)
PDTI.FindFreeSpace = real_find

-- Sizes by class (the first matching category).
W.t_smg = { categories = { "smg" } }; W.t_shot = { categories = { "shotgun" } }; W.t_snp = { categories = { "snp" } }
W.t_lmg = { categories = { "lmg" } }; W.t_mini = { categories = { "minigun" } }; W.t_odd = { categories = { "bow" } }
local function size(id) local w, h = A.Size(id); return w .. "x" .. h end
T("sizes: SMG 3x2, shotgun 4x2, sniper and LMG 5x2, the minigun 5x2 (a hand), anything else 4x2",
  size("t_smg") == "3x2" and size("t_shot") == "4x2" and size("t_snp") == "5x2" and size("t_lmg") == "5x2"
  and size("t_mini") == "5x2" and size("t_odd") == "4x2" and size("new_m4") == "4x2", size("t_mini"))
for _, id in ipairs({ "t_smg", "t_shot", "t_snp", "t_lmg", "t_mini", "t_odd" }) do W[id] = nil end

------------------------------------------------------------- the files

A.Reset()
T("the armory file keeps today's purchases", A.Stock("five_seven") == 0
  and io.open(TMP .. "pdti_armory.json", "r") ~= nil)
local s = A._Sanitize({ next_uid = 7, brought = { 3, 3, "x", 4 }, lost = { 0, 5 }, in_heist = true })
T("a broken file made safe: uid lists unique and positive", #s.brought == 2 and #s.lost == 1 and s.in_heist
  and s.next_uid == 7)
local f = io.open(TMP .. "pdti_armory.json", "w"); f:write("{not json"); f:close()
A.Reset()
T("an unreadable file: an empty armory, no error", A._Data().next_uid == 1)
_G.PDTI_SEPARATE_SAVE = true
T("on the mod's own save the files have their own names", A.FileName(2) == "pdti_save_armory_profile2.json"
  and PDTI.ProfileFile(1) == "pdti_save_inventory_profile1.json"
  and PDTI.SaveFileName("stash", 3) == "pdti_save_stash_profile3.json")
_G.PDTI_SEPARATE_SAVE = false
T("  on the game's save the old names", A.FileName(2) == "pdti_armory_profile2.json"
  and PDTI.ProfileFile(1) == "pdti_inventory.json")
_G.PDTI_SEPARATE_SAVE = nil

------------------------------------------------ hands and the game's slots

fresh()
stock_roll.new_m4, stock_roll.five_seven = 0.99, 0.99
T("you own no weapons: the free AMCAR goes into PRI as a real weapon, and the game gets it", A.SyncEquipped()
  and A.HandItem("primaries") ~= nil and A.HandItem("primaries").data.weapon_id == "amcar"
  and A.HandItem("primaries").data.free == true and #crafted.primaries == 1
  and crafted.primaries[1].weapon_id == "amcar" and crafted.primaries[1].equipped
  and crafted.primaries[1].blueprint[1] == "wpn_fps_ass_amcar_body")
T("  and the Chimano 88 into SEC", A.HandItem("secondaries").data.weapon_id == "glock_17"
  and crafted.secondaries[1].weapon_id == "glock_17" and #A.Weapons() == 2)
T("  the menu scene and the outfit are told", (calls.scene_primary or 0) >= 1 and (calls.outfit or 0) >= 1)
local outfit_before = calls.outfit
T("  nothing changed: nothing written again", A.SyncEquipped() == false and calls.outfit == outfit_before)
crafted.primaries[1].equipped = nil
T("  a slot not equipped is written again", A.SyncEquipped() and crafted.primaries[1].equipped == true)
crafted.primaries[1].weapon_id = "new_m4"
T("  another weapon with the same parts too", A.SyncEquipped() and crafted.primaries[1].weapon_id == "amcar")
crafted.secondaries[1].factory_id = "wpn_other"
T("  another factory too", A.SyncEquipped() and crafted.secondaries[1].factory_id == "wpn_fps_pis_g17")
local free_pri, free_sec = A.HandItem("primaries").data.uid, A.HandItem("secondaries").data.uid
T("the free AMCAR is a real item: dragged off PRI into the backpack", move(free_pri, "backpack")
  and where(free_pri) == "backpack")
T("  you own a primary (packed): no second free one, PRI stays empty", A.IssueFree() == 0
  and A.HandItem("primaries") == nil and #A.Weapons() == 2)
A.SyncEquipped()
T("  the game still gets an AMCAR for the empty slot (it needs a weapon there)", crafted.primaries[1].weapon_id == "amcar")
move(free_pri, "locker", 8, 8)
move(free_sec, "locker", 6, 8)
local _, m4 = A.Buy("new_m4")
local _, pistol = A.Buy("five_seven")
T("a primary goes into the primary hand", move(m4.uid, "hand_primary") and where(m4.uid) == "hand_primary")
T("  a 4x2 rifle takes the one cell of the weapon slot", PDTI.GetContainerInfo("hand_primary").width == 1
  and PDTI.GetContainerInfo("hand_primary").height == 1
  and PDTI.GetOccupancyMap("hand_primary").cells[1][1] == select(2, where(m4.uid)))
local okw, whyw = move(pistol.uid, "hand_primary")
T("  a secondary does not", not okw and tostring(whyw):find("only a primary") ~= nil, whyw)
T("  it goes into the secondary hand", move(pistol.uid, "hand_secondary"))
local _, m4b = A.Buy("new_m4")
local okb, whyb = move(m4b.uid, "hand_primary")
T("  one weapon to a hand", not okb and tostring(whyb):find("already holds") ~= nil, whyb)
A.SyncEquipped()
T("the game's slots are your hands (slot 1 only)", #crafted.primaries == 1 and crafted.primaries[1].weapon_id == "new_m4"
  and crafted.primaries[1].blueprint[2] == "wpn_fps_ass_m4_barrel" and crafted.secondaries[1].weapon_id == "five_seven"
  and crafted.primaries[2] == nil)
T("  the game's equipped weapon is yours", managers.blackmarket:equipped_primary().weapon_id == "new_m4"
  and A.Build("primaries").weapon_id == "new_m4")
locked_ids.new_m4 = true
move(m4.uid, "locker", 0, 4)
local okl, whyl = move(m4b.uid, "hand_primary")
T("a weapon the game has not unlocked for you is refused in a hand", not okl
  and tostring(whyl):find("not unlocked") ~= nil, whyl)
locked_ids.new_m4 = nil
move(m4.uid, "hand_primary")
PDTI.session_only = true
local keep = crafted.primaries[1]
crafted.primaries[1] = { weapon_id = "heist_gun", factory_id = "x", blueprint = {}, equipped = true }
T("in a heist the game's slots are not touched", A.SyncEquipped() == false
  and crafted.primaries[1].weapon_id == "heist_gun")
crafted.primaries[1] = keep
local okh, whyh = move(m4.uid, "locker", 0, 6)
T("  the locker stays at home", not okh and tostring(whyh):find("locker stays at home during a heist", 1, true) ~= nil, whyh)
local cc, cid = where(m4.uid)
local okc, whyc = PDTI.CanMoveItem(cc, cid, "locker", 0, 6, false)
T("  the screen's drag preview says so too", not okc and tostring(whyc):find("during a heist") ~= nil, whyc)
local w0 = PDTI.GetTotalWeight() -- (the planned magazines)
local function loadout()
  local out = {}
  for _, e in ipairs(PDTI.Loadout.Get()) do out[e.slot] = e end
  return out
end
local m4_weight = PDTI.FindItem(where(m4.uid)).data.weight
T("  the weapons in your slots weigh as the loadout says (the primary: your slot's weapon), not in the grid",
  loadout().primary and loadout().primary.name == "CAR-4" and loadout().primary.weight == m4_weight)
T("in a heist a slot's weapon goes into the backpack", move(m4.uid, "backpack") and where(m4.uid) == "backpack")
T("  there it weighs in the grid, and the loadout has no primary (counted once)", loadout().primary == nil
  and loadout().secondary ~= nil and math.abs(PDTI.GetTotalWeight() - w0 - m4_weight) < 1e-6,
  PDTI.GetTotalWeight() - w0)
local okl2, whyl2 = move(pistol.uid, "backpack", 0, 3)
T("  the last weapon too: no weapon in your hands", okl2 and where(pistol.uid) == "backpack", whyl2)
move(pistol.uid, "hand_secondary")
T("  the backpack's weapon back into its slot", move(m4.uid, "hand_primary") and where(m4.uid) == "hand_primary")
PDTI.session_only = false
local okm, whym = move(pistol.uid, "backpack", 0, 3)
T("  (in the menu a slot may be emptied: planning)", okm, whym)
move(pistol.uid, "hand_secondary")
T("packing a spare weapon: into the backpack, where it weighs", move(m4b.uid, "backpack")
  and PDTI.GetTotalWeight() > 0)
move(m4.uid, "locker", 0, 6)
local lmap = PDTI.GetOccupancyMap("locker")
local m4id = select(2, where(m4.uid))
T("off the slot into the locker: its own 4x2 again", lmap.cells[7][1] == m4id and lmap.cells[8][4] == m4id
  and lmap.cells[7][5] ~= m4id)
move(m4.uid, "hand_primary")
locked_ids.new_m4 = true
A.Reset(); PDTI.LoadProfile()
locked_ids.new_m4 = nil
T("the weapons stay where they were (the inventory's file; a hand's weapon is not checked while reading)", where(m4.uid) == "hand_primary"
  and where(m4b.uid) == "backpack" and where(pistol.uid) == "hand_secondary")
-- The game reads its save (its own slots): they follow the hands again.
managers.blackmarket:load({ blackmarket = { crafted_items = { primaries = { { weapon_id = "amcar",
  factory_id = "wpn_fps_ass_amcar", blueprint = {}, equipped = true } }, secondaries = {} } } })
crafted = Global.blackmarket_manager.crafted_items
T("the game read its save: its slots follow your hands again", crafted.primaries[1].weapon_id == "new_m4"
  and crafted.secondaries[1].weapon_id == "five_seven")
PDTI.session_only = true
local ensured, real_ensure = 0, PDTI.EnsureProfile
PDTI.EnsureProfile = function(...) ensured = ensured + 1; return real_ensure(...) end
managers.blackmarket:load({ blackmarket = { crafted_items = { primaries = {}, secondaries = {} } } })
PDTI.EnsureProfile = real_ensure
T("  (not in a heist, where the plan is not even read)", next(Global.blackmarket_manager.crafted_items.primaries) == nil
  and ensured == 0)
PDTI.session_only = false
managers.blackmarket:load({ blackmarket = { crafted_items = { primaries = {}, secondaries = {} } } })
crafted = Global.blackmarket_manager.crafted_items
-- Ctrl+click: the locker's weapon to its hand, a hand's weapon back.
move(pistol.uid, "locker", 6, 0)
local pc, pid = where(pistol.uid)
T("Ctrl+click in the locker: the weapon goes to its hand", PDTI.UIQuickTransfer(pc, pid) and where(pistol.uid) == "hand_secondary")
pc, pid = where(pistol.uid)
T("  and back to the locker", PDTI.UIQuickTransfer(pc, pid) and where(pistol.uid) == "locker")

------------------------------------------- the weapons in the player's hands

-- A player: the game's weapon selections (2 the primary, 1 the secondary).
local real_world = rawget(_G, "World")
_G.World = { delete_unit = function(_, u) u.deleted = true end }
managers.hud = managers.hud or {}
managers.hud.set_ammo_amount = function(_, sel) calls.hud_cleared = sel end
local SEC_FACTORIES = { wpn_fps_pis_g17 = true, wpn_fps_pis_lemming = true }
local touched_deleted = 0 -- the game crashes on a deleted unit's base
local function weapon_unit(f)
  local u = { f = f }
  local base = { _factory_id = f, clip = 30, total = 90, shown = true,
    set_slot = function(_, unit, slot) unit.slot = slot end,
    set_ammo_remaining_in_clip = function(self, v) self.clip = v end,
    set_ammo_total = function(self, v) self.total = v end,
    set_visibility_state = function(self, v) self.shown = v end }
  u.visible = function() return base.shown end
  u.base = function()
    if u.deleted then touched_deleted = touched_deleted + 1 end
    return base
  end
  return u
end
local function fake_player(prim, sec, equipped)
  local inv = { sel = {}, eq = equipped or 2, added = {} }
  if prim then inv.sel[2] = { unit = weapon_unit(prim) } end
  if sec then inv.sel[1] = { unit = weapon_unit(sec) } end
  function inv:available_selections() return self.sel end
  function inv:equipped_selection() return self.eq end
  function inv:equip_selection(i) self.eq = i; return true end
  function inv:remove_selection(i) self.sel[i] = nil; if self.eq == i then self.eq = nil end end
  function inv:add_unit_by_factory_name(f, equip, instant, bp)
    self.sel[SEC_FACTORIES[f] and 1 or 2] = { unit = weapon_unit(f) }
    self.added[#self.added + 1] = { f = f, equip = equip, bp = bp }
  end
  return { inventory = function() return inv end }, inv
end

fresh()
local _, hm4 = A.Buy("new_m4")
local _, hp = A.Buy("five_seven")
move(hm4.uid, "hand_primary"); move(hp.uid, "hand_secondary")
PDTI.session_only = true
local player, inv = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_lemming")
T("a heist begins with your slots' weapons in hand: nothing to change", A.OnSpawn(player) == false
  and inv.sel[2] and inv.sel[1] and #inv.added == 0)
local old_primary = inv.sel[2].unit
local MAG = PDTI.Ammo.MAGAZINE_ITEM
PDTI.AddItem("gun_primary", MAG, 0, 0, false, 1, { slot = "primary", queue_key = "car4", rounds = 30, in_gun = true })
PDTI.AddItem("gun_secondary", MAG, 0, 0, false, 1, { slot = "secondary", queue_key = "57", rounds = 20, in_gun = true })
move(hm4.uid, "backpack")
T("the primary dragged into the backpack: out of your hands (you cannot switch to it)", A.ApplyHands(player)
  and inv.sel[2] == nil and old_primary.slot == 0 and old_primary.deleted == true and calls.hud_cleared == 2)
T("  you held it: the secondary is in your hands now", inv.eq == 1)
T("  its magazine went with it (out of PRI's magazine slot; SEC's stays)",
  #PDTI.GetContainerInfo("gun_primary").items == 0 and #PDTI.GetContainerInfo("gun_secondary").items == 1)
move(hm4.uid, "hand_primary")
T("dragged back into PRI: in your hands again, built as it is", A.ApplyHands(player) and inv.sel[2] ~= nil
  and inv.added[1].f == "wpn_fps_ass_m4" and inv.added[1].equip == false
  and inv.added[1].bp[2] == "wpn_fps_ass_m4_barrel")
T("  nothing changed: nothing done again", A.ApplyHands(player) == false and #inv.added == 1)
PDTI.session_only = false
move(hp.uid, "backpack", 0, 3)
PDTI.session_only = true
local p2, inv2 = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_g17", 1)
PDTI.AddItem("gun_secondary", MAG, 0, 0, false, 1, { slot = "secondary", queue_key = "g17", rounds = 17, in_gun = true })
T("a heist begun with SEC empty: no secondary in your hands", A.OnSpawn(p2) and inv2.sel[1] == nil
  and inv2.sel[2] ~= nil and inv2.eq == 2)
T("  its magazine out of SEC's magazine slot", #PDTI.GetContainerInfo("gun_secondary").items == 0)
PDTI.session_only = false
move(hm4.uid, "locker", 0, 4)
PDTI.session_only = true
local p3, inv3 = fake_player("wpn_fps_ass_amcar", "wpn_fps_pis_g17")
local stand = inv3.sel[1].unit
PDTI.AddItem("gun_secondary", MAG, 0, 0, false, 1, { slot = "secondary", queue_key = "g17", rounds = 17, in_gun = true })
T("both slots empty: no weapon in your hands (the pistol stays as the game's stand-in, no grid item)", A.OnSpawn(p3)
  and inv3.sel[2] == nil and inv3.sel[1] and inv3.sel[1].unit == stand and A.IsStandIn(stand) and inv3.eq == 1
  and #inv3.added == 0 and A.HandItem("secondaries") == nil and #A.Weapons() == 2)
local sb = stand.base()
T("  it is hidden and empty, its HUD ammo cleared, its magazine out of the slot", sb.shown == false and sb.clip == 0
  and sb.total == 0 and calls.hud_cleared == 1 and #PDTI.GetContainerInfo("gun_secondary").items == 0)
T("  Pick Up Weapons will not drop it as a pickup (it drops only your own weapons)",
  sb._picked_up_weapon_data.is_npc == true and sb._picked_up_weapon_data.ammo.total == 0)
T("  nothing more to do the next time", A.ApplyHands(p3) == false)
PDTI.session_only = false
move(hm4.uid, "hand_primary")
PDTI.session_only = true
T("a weapon into a slot: in your hands, the stand-in gone", A.ApplyHands(p3) and inv3.sel[2] ~= nil
  and inv3.sel[1] == nil and inv3.eq == 2 and stand.deleted == true)
PDTI.session_only = false
move(hm4.uid, "locker", 0, 4)
local p4, inv4 = fake_player("wpn_fps_ass_amcar", "wpn_fps_pis_g17")
T("  in the safehouse too: no weapon in your hands", A.ApplyHands(p4) and inv4.sel[2] == nil
  and A.IsStandIn(inv4.sel[1].unit))
local _, real_g17 = A.Buy("glock_17")
move(real_g17.uid, "hand_secondary")
T("a real Chimano 88 into SEC: put in, not mistaken for the stand-in", A.ApplyHands(p4)
  and inv4.added[1] and inv4.added[1].f == "wpn_fps_pis_g17" and not A.IsStandIn(inv4.sel[1].unit))
move(real_g17.uid, "locker", 6, 4)
PDTI.session_only = true
local p7, inv7 = fake_player("wpn_fps_ass_amcar", nil, 2)
T("only a primary in your hands: a Chimano 88 stand-in instead (a heavy gun would slow you)", A.ApplyHands(p7)
  and inv7.added[1].f == "wpn_fps_pis_g17" and inv7.sel[2] == nil and A.IsStandIn(inv7.sel[1].unit) and inv7.eq == 1)
FACTORY.glock_17 = nil
local p8, inv8 = fake_player("wpn_fps_ass_amcar", nil, 2)
T("  no Chimano to be had: the primary is the stand-in", A.ApplyHands(p8) and #inv8.added == 0
  and A.IsStandIn(inv8.sel[2].unit) and inv8.sel[2].unit.base().shown == false)
FACTORY.glock_17 = "wpn_fps_pis_g17"
PDTI.session_only = false
move(hm4.uid, "hand_primary")
PDTI.session_only = true
local p5, inv5 = fake_player(nil, "wpn_fps_pis_g17", 1)
T("the primary goes in first, then the secondary out", A.ApplyHands(p5)
  and inv5.sel[2] ~= nil and inv5.sel[1] == nil and inv5.eq == 2)
local p6, inv6 = fake_player(nil, "wpn_fps_pis_g17", 1)
inv6.add_unit_by_factory_name = function() error("cannot spawn") end
T("a weapon the game cannot spawn: the one you hold stays", A.ApplyHands(p6) == false
  and inv6.sel[1] ~= nil and inv6.eq == 1)
T("no player: nothing", A.ApplyHands({ inventory = function() return nil end }) == false)
PDTI.session_only = false
_G.World = real_world

------------------------------------ picked-up weapons (the Pick Up Weapons mod)

W.ak74 = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "AK" }
FACTORY.ak74 = "wpn_fps_ass_74"
locked_ids.ak74 = true -- not unlocked in the game
-- The game's class: Pick Up Weapons calls it with its data set while it runs.
local real_pi = rawget(_G, "PlayerInventory")
_G.PlayerInventory = {
  add_unit_by_factory_name = function(self, f, equip, instant, bp)
    local u = weapon_unit(f)
    u.base()._blueprint = bp or { f .. "_built" } -- the game builds its default
    -- Pick Up Weapons marks the weapon it builds (its assemble hook)
    u.base()._picked_up_weapon_data = rawget(_G, "PickUpWeapons") and PickUpWeapons._picked_up_weapon_data
    local sel = SEC_FACTORIES[f] and 1 or 2
    if self.sel[sel] then self.sel[sel].unit.deleted = true end -- the game deletes the weapon replaced
    self.sel[sel] = { unit = u }
    if equip then self.eq = sel end
  end
}
local plain_add = PlayerInventory.add_unit_by_factory_name
A.OnSpawn({ inventory = function() return nil end })
T("the pickup hook is put in place when a player spawns", PlayerInventory.add_unit_by_factory_name ~= plain_add)
_G.PickUpWeapons = {}
local AK_BP = { "wpn_fps_ass_74_body", "wpn_fps_ass_74_b_standard" }
local function pick(inv, data, mark_enemy) -- the mod's interaction
  if mark_enemy and inv.sel[2] then inv.sel[2].unit.base()._picked_up_weapon_data = { is_npc = true } end
  PickUpWeapons._picked_up_weapon_data = data
  PlayerInventory.add_unit_by_factory_name(inv, data.factory_id, true, false, data.blueprint)
  PickUpWeapons._picked_up_weapon_data = nil
end
local function enemy_ak() return { is_npc = true, weapon_id = "ak74", factory_id = "wpn_fps_ass_74", blueprint = AK_BP } end

fresh()
local _, pm4 = A.Buy("new_m4")
local _, pp = A.Buy("five_seven")
move(pm4.uid, "hand_primary"); move(pp.uid, "hand_secondary")
A.OnHeistStart()
PDTI.session_only = true
local pplayer, pinv = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_lemming")
PlayerInventory.add_unit_by_factory_name(pinv, "wpn_fps_ass_amcar", true, false, nil)
T("a weapon given without Pick Up Weapons' data: your slots stay", A.HandItem("primaries").data.uid == pm4.uid)
pinv.sel[2] = { unit = weapon_unit("wpn_fps_ass_m4") }
PDTI.session_only = false
pick(pinv, enemy_ak())
T("  nor outside a heist", A.HandItem("primaries").data.uid == pm4.uid)
pinv.sel[2] = { unit = weapon_unit("wpn_fps_ass_m4") }
PDTI.session_only = true
local redraws, real_redraw = 0, PDTI.RedrawUI
PDTI.RedrawUI = function() redraws = redraws + 1 end
pick(pinv, enemy_ak())
PDTI.RedrawUI = real_redraw
T("  (a pickup redraws the screen)", redraws == 1)
local ak = A.HandItem("primaries") and A.HandItem("primaries").data
T("an enemy's AK picked up: it is your primary slot's weapon (not unlocked: it is in your hands)", ak
  and ak.weapon_id == "ak74" and ak.picked == true and ak.blueprint == "wpn_fps_ass_74_body,wpn_fps_ass_74_b_standard"
  and ak.uid > pp.uid)
T("  your CAR-4 lies on the ground: out of the grid", where(pm4.uid) == nil and #A._dropped == 1)
T("  the hands match the slot: nothing to change", A.ApplyHands(pplayer) == false)
T("  the loadout's primary is the AK", PDTI.Loadout.Get()[1].name == "AK")
T("the AK into the backpack: out of your hands", move(ak.uid, "backpack") and A.ApplyHands(pplayer)
  and pinv.sel[2] == nil)
pick(pinv, { weapon_id = "new_m4", factory_id = "wpn_fps_ass_m4",
  blueprint = { "wpn_fps_ass_m4_barrel", "wpn_fps_ass_m4_body" } })
local back = A.HandItem("primaries") and A.HandItem("primaries").data
T("your CAR-4 picked up again: the same item in PRI", back and back.uid == pm4.uid and back.picked == nil
  and #A._dropped == 0)
MissionEndState.at_enter({ _success = true })
A.OnMissionEnd(true)
T("won (told twice): nothing left on the ground, the AK you carry is noted as yours, once", #A._Data().lost == 0
  and #A._Data().captured == 1 and A._Data().captured[1].data.uid == ak.uid and A._Data().captured[1].at == "backpack")
A.Reset()
T("  noted in the file (the game reloads between the heist and the menu)", #A._Data().captured == 1
  and A._Data().captured[1].data.weapon_id == "ak74" and A._Data().captured[1].data.picked == nil)
PDTI.session_only = false
PDTI.LoadProfile()
T("at the menu the AK is in the locker (it was packed), your weapons as they were", A.OnMenu()
  and where(ak.uid) == "locker" and where(pm4.uid) == "hand_primary" and where(pp.uid) == "hand_secondary"
  and #A._Data().captured == 0)

-- Won with the enemy's weapon in your slot: yours, left on the ground, is lost.
fresh()
locked_ids.ak74 = nil
local _, qm4 = A.Buy("new_m4")
local _, qp = A.Buy("five_seven")
move(qm4.uid, "hand_primary"); move(qp.uid, "hand_secondary")
A.OnHeistStart()
PDTI.session_only = true
local _, qinv = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_lemming")
pick(qinv, enemy_ak())
local qak = A.HandItem("primaries").data
pick(qinv, { is_npc = true, weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar" }, true)
local qam = A.HandItem("primaries").data
T("an enemy's weapon swapped for another: it is gone (that mod drops only yours)", qam.weapon_id == "amcar"
  and qam.picked == true and #A._dropped == 1 and where(qak.uid) == nil)
T("  its parts are the ones the game built", qam.blueprint == "wpn_fps_ass_amcar_built", qam.blueprint)
MissionEndState.at_enter({ _success = true })
T("won: your CAR-4 left on the ground is lost, the AMCAR in your slot is yours", #A._Data().lost == 1
  and A._Data().lost[1] == qm4.uid and #A._Data().captured == 1 and A._Data().captured[1].at == "hand_primary")
PDTI.session_only = false
PDTI.LoadProfile()
A.OnMenu()
T("  at the menu: the AMCAR in PRI, the CAR-4 gone", where(qam.uid) == "hand_primary" and where(qm4.uid) == nil
  and A.HandItem("primaries").data.picked == nil)

-- Failed: what you left on the ground is lost too; nothing picked up is kept.
fresh()
local _, fm4 = A.Buy("new_m4")
local _, fp = A.Buy("five_seven")
move(fm4.uid, "hand_primary"); move(fp.uid, "hand_secondary")
A.OnHeistStart()
PDTI.session_only = true
local _, finv = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_lemming")
pick(finv, enemy_ak())
local fak = A.HandItem("primaries").data
pick(finv, { is_npc = true, weapon_id = "new_m4", factory_id = "wpn_fps_ass_m4" }, true)
local enemy_m4 = A.HandItem("primaries").data
T("an enemy's CAR-4 is a new weapon, not yours from the ground", enemy_m4.uid ~= fm4.uid and enemy_m4.picked == true
  and #A._dropped == 1)
A._Data().captured = { { data = A.MakeData("amcar", nil, 950), at = "locker" } } -- won on day 1
MissionEndState.at_enter({ _success = false })
PDTI.session_only = false
PDTI.LoadProfile()
A.OnMenu()
T("failed: your CAR-4 on the ground and your pistol lost, nothing picked up kept (day 1's neither)",
  where(fm4.uid) == nil and where(fp.uid) == nil and where(fak.uid) == nil and where(950) == nil
  and A.HandItem("primaries").data.free == true)

-- Two of your CAR-4s on the ground: the one picked up is told by its parts
-- (or by its kind when the game built it a little differently).
fresh()
PDTI.SetEquipment("backpack", "large_backpack")
local _, d1 = A.Buy("new_m4")
local _, dp = A.Buy("five_seven")
move(d1.uid, "hand_primary"); move(dp.uid, "hand_secondary")
local long = A.MakeData("new_m4", { "wpn_fps_ass_m4_body", "wpn_fps_upg_long" }, 960)
PDTI.AddItemAuto("backpack", A.ITEM_ID, 1, long, true)
A._dropped = { { data = { uid = 1 } } }
A.OnHeistStart()
T("a heist starts with nothing on the ground", #A._dropped == 0)
PDTI.session_only = true
local dplayer, dinv = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_lemming")
pick(dinv, enemy_ak())
local dak = A.HandItem("primaries").data
local function pack(uid)
  local c, i = where(uid)
  local x, y, rot = PDTI.FindFreeSpace("backpack", PDTI.FindItem(c, i), true)
  return x ~= nil and PDTI.MoveItem(c, i, "backpack", x, y, rot)
end
T("  (the AK packed, the long-barrel CAR-4 into PRI)", pack(dak.uid) and A.ApplyHands(dplayer)
  and move(960, "hand_primary") and A.ApplyHands(dplayer))
pick(dinv, { is_npc = true, weapon_id = "amcar", factory_id = "wpn_fps_ass_amcar" })
T("  (both on the ground)", #A._dropped == 2)
pick(dinv, { weapon_id = "new_m4", factory_id = "wpn_fps_ass_m4", blueprint = { "wpn_fps_upg_long", "wpn_fps_ass_m4_body" } })
T("the long-barrel one picked up: that item", A.HandItem("primaries").data.uid == 960 and #A._dropped == 1)
pick(dinv, { weapon_id = "new_m4", factory_id = "wpn_fps_ass_m4", blueprint = { "wpn_fps_ass_m4_body", "x" } })
T("  the other, built a little differently: still yours", A.HandItem("primaries").data.uid == d1.uid
  and #A._dropped == 1)
dinv.sel[2] = nil -- (its weapon could not be put in your hands)
pick(dinv, enemy_ak())
T("a slot's weapon that was not in your hands is not on the ground", #A._dropped == 1 and where(d1.uid) == nil)
MissionEndState.at_enter({ _success = true })
T("  so it is not lost (the menu inventory still has it)", #A._Data().lost == 1 and A._Data().lost[1] ~= d1.uid)

-- A weapon with no factory of its own in the game's list: the unit's.
W.mystery = { use_data = { selection_index = 2 }, categories = { "assault_rifle" }, name_id = "Mystery" }
fresh()
A.IssueFree()
PDTI.session_only = true
local mplayer, minv = fake_player("wpn_fps_ass_amcar", "wpn_fps_pis_g17")
pick(minv, { is_npc = true, weapon_id = "mystery", factory_id = "wpn_fps_mystery" })
T("a picked weapon keeps the factory it was built with", A.HandItem("primaries").data.factory_id == "wpn_fps_mystery"
  and A.ApplyHands(mplayer) == false)
local bare = { sel = { [2] = { unit = weapon_unit("wpn_fps_ass_amcar") } } }
function bare:available_selections() return self.sel end
A.OnPickup(bare, { is_npc = true, weapon_id = "amcar" }, nil, 2)
T("no pickup ever touched the weapon the game deleted (a crash in the game)", touched_deleted == 0, touched_deleted)
T("a picked weapon with no parts known: the game's default parts", A.HandItem("primaries").data.blueprint
  == "wpn_fps_ass_amcar_body,wpn_fps_ass_amcar_barrel", A.HandItem("primaries").data.blueprint)
W.mystery = nil
-- A selection whose weapon is already gone: not read at all.
local real_alive = _G.alive
_G.alive = function(u) return u ~= nil and not u.deleted end
local _, ginv = fake_player("wpn_fps_ass_amcar", "wpn_fps_pis_g17")
ginv.sel[2].unit.deleted = true
local dropped_before = #A._dropped
pick(ginv, enemy_ak())
_G.alive = real_alive
T("  nor a weapon already gone from the selection (and it is not on the ground)", touched_deleted == 0
  and #A._dropped == dropped_before, touched_deleted)

-- No grid weapons (the armory not set up): Pick Up Weapons alone.
fresh()
PDTI.session_only = true
local _, ninv = fake_player("wpn_fps_ass_amcar", "wpn_fps_pis_g17")
pick(ninv, enemy_ak())
T("with no weapons of yours in the grid a pickup adds none", #A.Weapons() == 0)

-- No weapon in your hands, then a rifle picked up: the stand-in leaves at once.
fresh()
A.Buy("five_seven") -- (in the locker)
PDTI.session_only = true
local uplayer, uinv = fake_player("wpn_fps_ass_amcar", "wpn_fps_pis_g17")
A.ApplyHands(uplayer)
local ustand = uinv.sel[1].unit
pick(uinv, enemy_ak())
T("no weapon in your hands, an enemy's AK picked up: it is in your hands, the stand-in gone", A.IsStandIn(ustand)
  and uinv.sel[1] == nil and uinv.sel[2] and uinv.sel[2].unit.f == "wpn_fps_ass_74" and uinv.eq == 2
  and A.HandItem("primaries").data.weapon_id == "ak74")

-- Left (or quit) in a heist: nothing won.
fresh()
A.IssueFree()
A.OnHeistStart()
A._Data().captured = { { data = A.MakeData("amcar", nil, 970), at = "locker" } }
A.Save()
T("a heist left after a won day: nothing picked up is kept", A.OnMenu() and where(970) == nil)

-- A won AK that does not fit anywhere waits; an AK the game has not unlocked
-- goes to the locker even if it was in your slot.
fresh()
locked_ids.ak74 = true
A._Data().captured = { { data = A.MakeData("ak74", nil, 900), at = "hand_primary" } }
T("a won weapon not unlocked: into the locker, not the slot", A.ApplyCaptured() == 1 and where(900) == "locker")
A._Data().captured = { { data = A.MakeData("ak74", nil, 900), at = "locker" } }
T("  one already in the inventory is not added twice", A.ApplyCaptured() == 0 and #A.Weapons() == 1
  and #A._Data().captured == 0)
locked_ids.ak74 = nil
A._Data().captured = { { data = A.MakeData("ak74", nil, 902), at = "backpack" } }
T("  one that was packed: the locker, even with PRI empty", A.ApplyCaptured() == 1 and where(902) == "locker")
locked_ids.ak74 = true
for i = 1, 40 do PDTI.AddItemAuto("locker", A.ITEM_ID, 1, A.MakeData("amcar", nil, 1000 + i), true) end
A._Data().captured = { { data = A.MakeData("ak74", nil, 901), at = "locker" } }
T("  no room in the locker: it waits for the next menu", A.ApplyCaptured() == 0 and #A._Data().captured == 1)
T("the file keeps only whole won weapons", #A._Sanitize({ captured = { { data = { uid = 5 } }, "x",
  { data = { uid = 6, weapon_id = "amcar", factory_id = "f", w = "4" }, at = 3 } } }).captured == 1
  and A._Sanitize({ captured = { { data = { uid = 6, weapon_id = "amcar", factory_id = "f", w = "4" } } } })
  .captured[1].data.w == 4
  and A._Sanitize({ captured = { { data = { uid = 6, weapon_id = "amcar", factory_id = "f", w = "4" } } } })
  .captured[1].at == "locker")
locked_ids.ak74 = nil
_G.PlayerInventory, _G.PickUpWeapons = real_pi, nil
PDTI.session_only = false

---------------------------------------- no weapon in your hands (the stand-in)

local acted = {}
_G.PlayerStandard = {
  update = function(self, t)
    -- the game shows the weapon in hand again once its timer ran out
    self._equipped_visibility_timer = t
    self._equipped_unit:base():set_visibility_state(true)
  end
}
for _, fn in ipairs(A.NO_WEAPON_ACTIONS) do
  PlayerStandard[fn] = function() acted[fn] = true; return "did" end
end
PlayerStandard._check_action_steelsight = function() acted.steelsight = true end
PlayerStandard._check_action_melee = function() acted.melee = true; return "melee" end
_G.RaycastWeaponBase = { add_ammo = function() return true, 5 end, add_ammo_from_bag = function() return 0.4 end }
A.InstallHooks()
local stand_unit = weapon_unit("wpn_fps_pis_g17")
stand_unit.base()._pdti_unarmed = true
local state = setmetatable({ _equipped_unit = stand_unit, _state_data = { in_steelsight = true },
  _end_action_steelsight = function(st) st._state_data.in_steelsight = false end }, { __index = PlayerStandard })
local all_blocked = true
for _, fn in ipairs(A.NO_WEAPON_ACTIONS) do
  if state[fn](state, 1, {}) ~= nil or acted[fn] then all_blocked = false end
end
T("no weapon in your hands: no firing, reloading, fire mode, gadget, inspecting, bipod or underbarrel", all_blocked)
state:_check_action_steelsight(1, {})
T("  no aiming (and aiming ends)", not acted.steelsight and state._state_data.in_steelsight == false)
T("  melee still works", PlayerStandard._check_action_melee(state, 1, {}) == "melee")
state:update(2, 0.016)
T("  the stand-in stays hidden after the game's update", stand_unit.base().shown == false
  and state._equipped_visibility_timer == nil)
T("  ammunition boxes and bags give it nothing", select(2, RaycastWeaponBase.add_ammo(stand_unit.base(), 1)) == 0
  and RaycastWeaponBase.add_ammo_from_bag(stand_unit.base(), 1) == 0)
local gun_unit = weapon_unit("wpn_fps_ass_m4")
state._equipped_unit = gun_unit
local all_run = true
for _, fn in ipairs(A.NO_WEAPON_ACTIONS) do
  if state[fn](state, 1, {}) ~= "did" then all_run = false end
end
state:update(3, 0.016)
T("a real weapon in hand: all of it as the game does it", all_run and gun_unit.base().shown == true
  and select(2, RaycastWeaponBase.add_ammo(gun_unit.base(), 1)) == 5)
local real_alive2 = _G.alive
_G.alive = function(u) return u ~= nil and not u.deleted end
stand_unit.deleted = true
state._equipped_unit = stand_unit
local touched_before = touched_deleted
local gone_ran = state[A.NO_WEAPON_ACTIONS[1]](state, 1, {}) == "did"
_G.alive = real_alive2
T("  a weapon already gone from your hands is not read (a crash in the game)", gone_ran
  and touched_deleted == touched_before)
_G.PlayerStandard, _G.RaycastWeaponBase = nil, nil

------------------------------------------------------------------ death

fresh()
PDTI.session_only = true
T("in a heist no free weapon is given", A.IssueFree() == 0 and #A.Weapons() == 0)
PDTI.session_only = false
local gave = A.IssueFree()
local top = math.max(A.HandItem("primaries").data.uid, A.HandItem("secondaries").data.uid)
A.Reset()
T("the free weapons' numbers are saved (a later weapon never gets the same one)", gave == 2
  and A._Data().next_uid > top, A._Data().next_uid .. " " .. top)
fresh()
local real_glock = W.glock_17
W.glock_17 = nil
T("a free weapon the game does not know: not given (the AMCAR is)", A.IssueFree() == 1
  and A.HandItem("primaries") ~= nil and #A.Weapons() == 1)
W.glock_17 = real_glock

-- Free weapons come on a new save and after a loss, not after you threw
-- your own away: an empty slot is yours to keep.
fresh()
A.IssueFree()
local gone = A.HandItem("secondaries")
PDTI.RemoveItem("hand_secondary", gone.instance_id) -- dropped outside the screen
T("your only secondary thrown away: no free one comes back (SEC stays empty)", A.IssueFree() == 0
  and A.HandItem("secondaries") == nil and A.SyncEquipped() ~= nil and A.HandItem("secondaries") == nil)
A.Reset()
T("  (noted in the file)", A.IssueFree() == 0)
T("an armory file from before: no free weapons owed", A._Sanitize({ next_uid = 3 }).free_due == false
  and A._Sanitize(nil).free_due == true)

fresh()
stock_roll.glock_17, stock_roll.amcar = 0.99, 0.99
local _, p1 = A.Buy("five_seven")
local _, r1 = A.Buy("new_m4")
local _, spare = A.Buy("glock_17")
local _, home = A.Buy("amcar")
move(p1.uid, "hand_secondary"); move(r1.uid, "hand_primary"); move(spare.uid, "backpack")
T("a heist starts: marked, with the weapons you bring (not the locker's)", A.OnHeistStart()
  and A._Data().in_heist == true and #A._Data().brought == 3)
MissionEndState.at_enter({ _success = true })
T("won: everything kept, the mark gone", #A.Weapons() == 4 and A._Data().in_heist == false and A.OnMenu()
  and #A.Weapons() == 4)
A.OnHeistStart()
do -- packed in the briefing, after the heist began
  local hc, hid = where(home.uid)
  local bx, by, brot = PDTI.FindFreeSpace("backpack", PDTI.FindItem(hc, hid), true)
  PDTI.MoveItem(hc, hid, "backpack", bx, by, brot)
end
MissionEndState.at_enter({ _success = false })
T("failed: noted (with what you packed in the briefing), the menu inventory untouched until the menu",
  #A._Data().lost == 4 and #A.Weapons() == 4)
move(home.uid, "locker", 0, 4)
A._Data().lost = { p1.uid, r1.uid, spare.uid }
A.OnMenu()
T("at the menu: the weapons in hand and packed are gone (no secondary left: the free Chimano 88 in SEC)",
  #A.Weapons() == 2 and where(home.uid) == "locker" and #A._Data().lost == 0
  and A.HandItem("secondaries").data.free == true and A.HandItem("primaries") == nil)
T("  the game's slots: the defaults again", crafted.primaries[1].weapon_id == "amcar"
  and crafted.secondaries[1].weapon_id == "glock_17")
A.Reset(); PDTI.LoadProfile()
T("  lost for good (both files saved)", #A.Weapons() == 2)
move(home.uid, "hand_primary")
money = 1000000
local _, packed_late = A.Buy("glock_17")
A.OnHeistStart()
do -- packed in the briefing, after the heist began
  local hc, hid = where(packed_late.uid)
  local bx, by, brot = PDTI.FindFreeSpace("backpack", PDTI.FindItem(hc, hid), true)
  PDTI.MoveItem(hc, hid, "backpack", bx, by, brot)
end
A.Reset() -- the game quit in the heist
T("the menu after a heist left unfinished: its weapons are lost, the free ones given again",
  A.OnMenu() and #A.Weapons() == 2 and where(home.uid) == nil and where(packed_late.uid) == nil
  and A.HandItem("primaries").data.free == true
  and A.HandItem("secondaries").data.free == true and A._Data().in_heist == false)
local again = A.HandItem("primaries").data
A.OnMenu()
T("  a menu without a left heist loses nothing (and gives nothing)", where(again.uid) == "hand_primary"
  and #A.Weapons() == 2)
job = "chill"
T("the safehouse is not a heist: no mark", A.OnHeistStart() == false and A._Data().in_heist == false)
MissionEndState.at_enter({ _success = false })
A.OnMenu()
T("  nor a loss there", where(again.uid) == "hand_primary")
job = "branchbank"
T("a build's worth: the weapon and the parts it has beyond its own", A.BuildPrice({ weapon_id = "new_m4",
  factory_id = "wpn_fps_ass_m4", blueprint = "wpn_fps_ass_m4_body,wpn_fps_ass_m4_barrel,scope,grip" })
  == 40000 + 2000)

--------------------------------------------------- the game's weapon screen

local gui = setmetatable({}, { __index = BlackMarketGui })
BlackMarketGui.buy_weapon_callback(gui, { category = "primaries", name = "amcar" })
BlackMarketGui.choose_weapon_mods_callback(gui, { category = "primaries" })
BlackMarketGui.sell_item_callback(gui, { category = "primaries" })
T("the game's weapon screen: no buying, modding or selling weapons, you are told why", not calls.gui_buy
  and not calls.gui_mod and calls.gui_sell == nil and #told == 3 and told[1]:find("grid items", 1, true) ~= nil)
BlackMarketGui.sell_item_callback(gui, { category = "masks" })
T("  a mask still sells", calls.gui_sell == "masks")

------------------------------------------------------------- no restart

T("no restart in the pause menu", MenuCallbackHandler:singleplayer_restart() == false
  and MenuCallbackHandler:_restart_level_visible() == false)
MenuCallbackHandler:restart_game(); MenuCallbackHandler:restart_level(); VoteManager:restart(); VoteManager:restart_auto()
T("  restart and its votes do nothing", not calls.restart_game and not calls.restart_level and not calls.vote and not calls.vote_auto)
local state = { gsm = function(self) return self end, change_state_by_name = function(self, n) self.went = n end,
  _continue_blocked = function() return false end }
GameOverState.continue(state)
T("the fail screen does not retry the day: it leaves the job", state.went == "empty" and calls.continue == nil)
GameOverState._shut_down_network(state); GameOverState._load_start_menu(state)
T("  the network closes and the menu loads (as for a professional job)", calls.shut == "mission" and calls.menu == "mission")
_G.restoration = {}
T("with restoration-mod the game's restart", MenuCallbackHandler:singleplayer_restart() == true)
GameOverState.continue(state)
T("  and its retry", calls.continue == "lobby")
T("  and the game's weapons (no sync)", A.SyncEquipped() == false)
fresh()
T("  no free weapons given either", A.IssueFree() == 0 and #A.Weapons() == 0)
_G.restoration = nil

---------------------------- the magazine in a weapon goes with it (0.37.7)
-- (A function of its own: the file has nearly 200 locals.)

;(function()
fresh()
A.IssueFree()
PDTI.SetAmmoPlanned(true)
local P, MAGI = PDTI.Plan, PDTI.Ammo.MAGAZINE_ITEM
local function box(slot) return PDTI.GetContainerInfo("gun_" .. slot).items end
local function wdata(uid) local c, i = where(uid); return c and PDTI.FindItem(c, i).data end
local function wweight(uid) local c, i = where(uid); return PDTI.ItemWeight(PDTI.FindItem(c, i)) end
local function to_locker(uid)
  local c, i = where(uid)
  local x, y, rot = PDTI.FindFreeSpace("locker", PDTI.FindItem(c, i), true)
  return x ~= nil and PDTI.MoveItem(c, i, "locker", x, y, rot)
end
local function out_of_box(slot)
  local it = box(slot)[1]
  for _, name in ipairs({ "rig", "pockets", "backpack" }) do
    local x, y, rot = PDTI.FindFreeSpace(name, it, true)
    if x and PDTI.MoveItem("gun_" .. slot, it.instance_id, name, x, y, rot) then return name, it.instance_id end
  end
  return nil
end
local amcar = A.HandItem("primaries").data
P.Refresh()
T("a new weapon comes with its magazine: full, in PRI's box, the AMCAR's", #box("primary") == 1
  and box("primary")[1].data.weapon_uid == amcar.uid and P.KindOf(box("primary")[1].data) == "amcar"
  and box("primary")[1].data.rounds == 30 and wdata(amcar.uid).gun_set == 1, #box("primary"))
T("  SEC's pistol too", #box("secondary") == 1 and P.KindOf(box("secondary")[1].data) == "glock_17")
local light = wweight(amcar.uid)
to_locker(amcar.uid)
P.Refresh()
T("the AMCAR into the locker: its magazine goes with it (PRI's box is empty)", #box("primary") == 0
  and wdata(amcar.uid).gun_n == 1 and wdata(amcar.uid).gun1_rounds == 30)
T("  and weighs with it", wweight(amcar.uid) > light, wweight(amcar.uid) - light)
T("  an empty slot: no weapon, so no magazine goes into its box",
  (PDTI.AddItem("gun_primary", MAGI, 0, 0, false, 1, { plan_weapon = "amcar", rounds = 30, capacity = 30 })) == false)
local _, m4 = A.Buy("new_m4")
move(m4.uid, "hand_primary")
P.Refresh()
T("the CAR-4 into PRI: its own magazine (a new weapon's, full)", #box("primary") == 1
  and box("primary")[1].data.weapon_uid == m4.uid and P.KindOf(box("primary")[1].data) == "new_m4")
local okw, whyw = PDTI.AddItem("gun_primary", MAGI, 1, 0, false, 1, { plan_weapon = "amcar", rounds = 30, capacity = 30 })
T("  an AMCAR magazine does not go into the CAR-4's box", okw == false
  and tostring(whyw):find("this weapon", 1, true) ~= nil, whyw)
do
  local c, i = where(amcar.uid)
  PDTI.EditItems({ update = { { container = c, instance_id = i,
    data = { gun1_rounds = 17, gun1_bullet = "ap", gun1_load = "ap:17" } } } })
end
to_locker(m4.uid)
move(amcar.uid, "hand_primary")
P.Refresh()
local back = box("primary")[1]
T("the AMCAR back into PRI: the same magazine (17 AP) in its box again", back and back.data.weapon_uid == amcar.uid
  and back.data.rounds == 17 and back.data.bullet == "ap" and wdata(amcar.uid).gun_n == 0
  and wweight(amcar.uid) == light, back and back.data.rounds)
T("  the CAR-4 took its own along", wdata(m4.uid).gun_n == 1)
local where_mag, mag_id = out_of_box("primary")
P.Refresh()
T("its magazine taken out by hand: the box stays empty (no free one)", where_mag ~= nil and #box("primary") == 0
  and wdata(amcar.uid).gun_set == 1, where_mag)
local spare = PDTI.FindItem(where_mag, mag_id)
T("  the magazine you took is the AMCAR's, of no weapon now", spare and P.KindOf(spare.data) == "amcar"
  and (tonumber(spare.data.weapon_uid) or 0) == 0)
PDTI.MoveItem(where_mag, mag_id, "gun_primary", 0, 0, false)
P.Refresh()
T("  put back into the box: the AMCAR's again", box("primary")[1] and box("primary")[1].data.weapon_uid == amcar.uid)
local _, a2 = A.Buy("amcar")
to_locker(amcar.uid)
move(a2.uid, "hand_primary")
P.Refresh()
T("two AMCARs: each its own magazine (the first's went with it, the second's is new)",
  wdata(amcar.uid).gun_n == 1 and #box("primary") == 1 and box("primary")[1].data.weapon_uid == a2.uid)
do
  local c, i = where(a2.uid)
  PDTI.RemoveItem(c, i) -- dropped outside the windows
end
P.Refresh()
T("a weapon thrown away: its magazine went with it", #box("primary") == 0)

-- A save from before: the magazines left in the boxes are no weapon's, and
-- your hands are empty (the user's own save).
fresh()
A.IssueFree()
PDTI.SetAmmoPlanned(true)
local la, lc = A.HandItem("primaries").data, A.HandItem("secondaries").data
PDTI.AddItem("gun_primary", MAGI, 0, 0, false, 1, { plan_slot = "primary", slot = "primary", queue_key = "plan:primary",
  pid = "amcar", rounds = 20, capacity = 20, size = "standard", bullet = "standard", mag_class = "assault_rifle" })
PDTI.AddItem("gun_secondary", MAGI, 0, 0, false, 1, { plan_slot = "secondary", slot = "secondary",
  queue_key = "plan:secondary", pid = "glock_17", rounds = 17, capacity = 17, mag_class = "pistol" })
to_locker(la.uid)
to_locker(lc.uid)
P.Refresh()
T("an older save: magazines left in the boxes with empty hands go into their weapons", #box("primary") == 0
  and #box("secondary") == 0 and wdata(la.uid).gun_n == 1 and wdata(lc.uid).gun_n == 1)
move(la.uid, "hand_primary")
P.Refresh()
T("  the AMCAR into PRI: that magazine is in its box, the AMCAR's", #box("primary") == 1
  and box("primary")[1].data.weapon_uid == la.uid and box("primary")[1].data.plan_weapon == "amcar")

-- In a heist the armory hands each gun over: read before the game deletes
-- the unit it replaces, loaded after it spawns a weapon (the ammunition
-- system's part: gun_slot_tests.lua).
do
  local real_gs, real_lg = PDTI.Ammo.GunState, PDTI.Ammo.LoadGun
  local read, loaded = {}, {}
  PDTI.Ammo.GunState = function(b)
    read[#read + 1] = b
    return { gun_set = 1, gun_n = 1, gun1_rounds = b.rounds_left or 0, gun_in = 0 }
  end
  PDTI.Ammo.LoadGun = function(b, d) loaded[#loaded + 1] = { base = b, d = d }; return true end
  local real_w = rawget(_G, "World")
  _G.World = { delete_unit = function(_, u) u.deleted = true end }
  fresh()
  local _, h1 = A.Buy("new_m4")
  local _, h2 = A.Buy("new_m4")
  local _, hs = A.Buy("five_seven")
  move(h1.uid, "hand_primary")
  move(hs.uid, "hand_secondary")
  pack(h2.uid)
  PDTI.session_only = true
  local hp, hinv = fake_player("wpn_fps_ass_m4", "wpn_fps_pis_lemming")
  A.OnSpawn(hp)
  T("a heist's weapons are your items (each unit knows its item)", hinv.sel[2].unit.base()._pdti_uid == h1.uid
    and hinv.sel[1].unit.base()._pdti_uid == hs.uid)
  local first = hinv.sel[2].unit
  local first_base = first.base()
  first_base.rounds_left = 12
  pack(h1.uid)
  move(h2.uid, "hand_primary")
  A.ApplyHands(hp)
  T("the same model swapped in a heist: the CAR-4 in hand is replaced, not taken for the other",
    #hinv.added == 1 and hinv.added[1].f == "wpn_fps_ass_m4" and hinv.sel[2].unit ~= first)
  T("  the one that left was read before the game deleted it; its item keeps it", read[#read] == first_base
    and wdata(h1.uid).gun1_rounds == 12)
  local second_base = hinv.sel[2].unit.base()
  T("  the one put in is loaded from its own item, and knows it", loaded[#loaded] and loaded[#loaded].d.uid == h2.uid
    and second_base._pdti_uid == h2.uid)
  T("  then its item holds nothing (all of it is in the gun)", wdata(h2.uid).gun_in == 1 and wdata(h2.uid).gun_n == 0)
  second_base.rounds_left = 5
  pack(h2.uid)
  A.ApplyHands(hp)
  T("taken out of your hands: its gun is read into its item", read[#read] == second_base
    and wdata(h2.uid).gun1_rounds == 5 and hinv.sel[2] == nil)
  local pistol_base = hinv.sel[1].unit.base()
  pistol_base.rounds_left = 9
  pack(hs.uid)
  A.ApplyHands(hp)
  T("no weapon in your hands: the pistol's gun is read before its unit becomes the stand-in",
    read[#read] == pistol_base and wdata(hs.uid).gun1_rounds == 9 and pistol_base._pdti_unarmed == true
    and pistol_base._pdti_uid == nil)
  local n_read = #read
  A.ApplyHands(hp)
  T("  the stand-in is never read again", #read == n_read)
  PDTI.Ammo.GunState, PDTI.Ammo.LoadGun = real_gs, real_lg
  _G.World = real_w
  PDTI.session_only = false
end
end)()

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
