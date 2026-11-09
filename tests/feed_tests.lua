-- 0.8.0: weapons that are loaded round by round, the pickup of a fraction of
-- a round, magazines that are never made out of loose rounds, the HUD that
-- follows the inventory, Ctrl+click and carrying more than one loot bag.
--   luajit tests/feed_tests.lua
local script = arg and arg[0] or "tests/feed_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_feed") .. "/")
_G.ModPath = ROOT
ENV.install_game()
ENV.load_mod(ROOT, false)
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo = PDTI.Ammo
T("the hooks are in place without NQR", Ammo.InstallHooks() == true)
T("the success line is logged", (function()
  for _, line in ipairs(ENV.logs) do
    if line:find("the ammunition hooks are in place", 1, true) then return true end
  end
  return false
end)())

local function fresh()
  PDTI.Reset()
  Ammo.Reset()
  Ammo.pickup_carry = {}
end

local function mags_of(key)
  return #PDTI.FindItems(function(_, item)
    return item.item_id == "spare_magazine" and item.data and item.data.queue_key == key
  end)
end

------------------------------------------------------ the pump shotgun

fresh()
local unit = ENV.make_unit()
local pump = ENV.make_weapon("test_pump", { "wpn_mag_test" }, 6, { _use_shotgun_reload = true })
pump.clip, pump.total, pump.ammo_max = 6, 48, 48
unit:set_weapon(pump)

T("a pump shotgun is loaded from the loose rounds", Ammo.FeedMode(pump) == "loose")
T("a pump shotgun is managed", not Ammo.SkipWeapon(pump), Ammo.SkipReason(pump))
local pkey = Ammo.Identify(pump).key
Ammo.SyncTotal(pump)
T("its reserve becomes loose shells", Ammo.LooseOfKey(pkey) == 42, Ammo.LooseOfKey(pkey))
T("it has no magazines", mags_of(pkey) == 0, mags_of(pkey))
T("its total is the tube and the loose shells", pump.total == 48, pump.total)

-- Fire the tube empty, then load shell by shell.
pump.clip, pump.total = 0, 42
Ammo.SyncTotal(pump)
T("firing does not give shells back", pump.total == 42, pump.total)
for _ = 1, 6 do NewRaycastWeaponBase.update_reloading(pump) end
T("six shells are loaded", pump.clip == 6, pump.clip)
T("the shells came out of the loose rounds", Ammo.LooseOfKey(pkey) == 36, Ammo.LooseOfKey(pkey))
T("the total stays honest", pump.total == 42, pump.total)

-- Shoot everything: the ammunition really runs out.
Ammo.ConsumeLooseKey(pkey, 36)
pump.clip, pump.total = 0, 0
Ammo.SyncTotal(pump)
NewRaycastWeaponBase.update_reloading(pump)
T("without loose shells nothing is loaded (no infinite ammo)", pump.clip == 0, pump.clip)
T("a pump shotgun without shells cannot reload", NewRaycastWeaponBase.can_reload(pump) == false)

-------------------------------------------- the double-barrelled shotgun

fresh()
local unit2 = ENV.make_unit()
local double = ENV.make_weapon("test_double", { "wpn_mag_test" }, 2)
double.clip, double.total, double.ammo_max = 2, 30, 30
unit2:set_weapon(double)
T("a double-barrelled shotgun is loaded from the loose rounds", Ammo.FeedMode(double) == "loose")
local dkey = Ammo.Identify(double).key
Ammo.SyncTotal(double)
T("it has no magazines", mags_of(dkey) == 0, mags_of(dkey))
double.clip, double.total = 0, 28
NewRaycastWeaponBase.on_reload(double)
T("the reload puts two shells in", double.clip == 2, double.clip)
T("the two shells left the loose rounds", Ammo.LooseOfKey(dkey) == 26, Ammo.LooseOfKey(dkey))
T("the double-barrel's total is honest", double.total == 28, double.total)

----------------------------------------- the grenade launcher pickup

fresh()
local unit3 = ENV.make_unit()
local gl = ENV.make_weapon("test_gl", { "wpn_mag_test" }, 1)
gl.clip, gl.total, gl.ammo_max = 1, 2, 6
gl._ammo_pickup = { 0.3, 0.3 }
unit3:set_weapon(gl)
T("a grenade launcher is loaded from the loose rounds", Ammo.FeedMode(gl) == "loose")
local gkey = Ammo.Identify(gl).key
Ammo.SyncTotal(gl)
local before = Ammo.LooseOfKey(gkey)
local picked, amount = RaycastWeaponBase.add_ammo(gl, 1)
T("a box that rolls less than a round is still picked up", picked == true, tostring(picked))
T("that box gives no grenade yet", amount == 0, amount)
for _ = 1, 3 do RaycastWeaponBase.add_ammo(gl, 1) end
T("four boxes add up to a grenade", Ammo.LooseOfKey(gkey) == before + 1, Ammo.LooseOfKey(gkey))
gl.ammo_max = gl.total
local full_picked = RaycastWeaponBase.add_ammo(gl, 1)
T("a full launcher leaves the box", full_picked == false, tostring(full_picked))

--------------------------------------------------------------- the bow

fresh()
local unit4 = ENV.make_unit()
local bow = ENV.make_weapon("test_bow", { "wpn_mag_test" }, 20, { _no_reload = true })
bow.ammo_max = 20
bow:set_ammo_total(20)
unit4:set_weapon(bow)
unit4.weapon = bow
local bkey = Ammo.Identify(bow).key
Ammo.SyncTotal(bow)
T("the arrows are loose rounds", Ammo.LooseOfKey(bkey) == 20, Ammo.LooseOfKey(bkey))
T("the bow is not counted twice", bow.total == 20, bow.total)
bow:set_ammo_total(19) -- an arrow is shot
Ammo.GameTick({ _state_data = {} }, 1, 0.016, false)
T("a shot arrow leaves the inventory", Ammo.LooseOfKey(bkey) == 19, Ammo.LooseOfKey(bkey))
T("the bow agrees", bow.total == 19, bow.total)
local arrow = RaycastWeaponBase.add_ammo(bow, 1, 1)
T("a picked up arrow comes back", arrow == true and Ammo.LooseOfKey(bkey) == 20, Ammo.LooseOfKey(bkey))
T("the bow shows it", bow.total == 20, bow.total)

------------------------------------------- magazines are real objects

fresh()
local unit5 = ENV.make_unit()
local rifle = ENV.make_weapon("test_rifle")
unit5:set_weapon(rifle)
Ammo.EnsureSupply(rifle)
local rkey = Ammo.Identify(rifle).key
-- Throw every spare magazine away.
for _, entry in ipairs(Ammo.AllMagazines(rkey)) do PDTI.RemoveItem(entry.container, entry.instance_id) end
rifle.clip = 10
Ammo.AddLooseKey(rkey, 50, Ammo.Identify(rifle))
local left = Ammo.FillMagazines(rifle, 50)
T("without magazines packing makes no new one", mags_of(rkey) == 0, mags_of(rkey))
T("the magazine in the gun is not packed", rifle.clip == 10, rifle.clip)
T("every round stays loose", Ammo.LooseOfKey(rkey) == 50 and left == 50, Ammo.LooseOfKey(rkey))
T("holding R has nothing to do", Ammo.NeedsFill(rifle) == false)
Ammo.StartJob(rifle)
for _ = 1, 20 do Ammo.Tick(1) end
T("holding R makes no new magazine either", mags_of(rkey) == 0, mags_of(rkey))
T("without a magazine to load there is no reload", NewRaycastWeaponBase.can_reload(rifle) == false)

-- An empty magazine goes back into the rig.
fresh()
local unit6 = ENV.make_unit()
local rifle2 = ENV.make_weapon("test_rifle")
unit6:set_weapon(rifle2)
Ammo.EnsureSupply(rifle2)
local r2 = Ammo.Identify(rifle2).key
rifle2.clip = 0
Ammo.SyncTotal(rifle2)
NewRaycastWeaponBase.on_reload(rifle2)
T("the empty magazine is kept", mags_of(r2) == 3, mags_of(r2))
T("a full one is loaded", rifle2.clip == 30, rifle2.clip)
local empties = 0
for _, m in ipairs(Ammo.Magazines(r2)) do if m.rounds == 0 then empties = empties + 1 end end
T("one of them is empty", empties == 1, empties)
-- Only empty magazines left: no reload.
for _, m in ipairs(Ammo.Magazines(r2)) do
  if m.rounds > 0 then Ammo.SetMagazineRounds(m.container, m.instance_id, 0) end
end
rifle2.clip = 5
T("empty magazines are not loaded", NewRaycastWeaponBase.can_reload(rifle2) == false)
-- Packing fills the empty magazines.
Ammo.AddLooseKey(r2, 20, Ammo.Identify(rifle2))
Ammo.FillMagazines(rifle2, 20)
T("loose rounds go into the empty magazines", Ammo.MagazineRounds(r2) == 20, Ammo.MagazineRounds(r2))

------------------------------------------- the HUD follows the inventory

Ammo.GameTick({ _state_data = {} }, 1, 0.016, false)
Ammo.panel_dirty = false
local victim = Ammo.Magazines(r2)[1]
PDTI.RemoveItem(victim.container, victim.instance_id)
Ammo.GameTick({ _state_data = {} }, 2, 0.016, false)
T("throwing a magazine away updates the panel at once", Ammo.panel_dirty == true)
T("and the total", rifle2.total == rifle2.clip + Ammo.MagazineRounds(r2) + Ammo.LooseOfKey(r2), rifle2.total)

------------------------------------------- colours of the two weapons

local stack = PDTI.FindItems(function(_, item) return item.item_id == "loose_ammo" end)[1]
T("loose rounds know their weapon slot", stack == nil or stack.item.data.slot == "primary",
  stack and stack.item.data.slot)
local sec = ENV.make_weapon("test_smg", { "wpn_mag_small" }, 20, { _selection = 1 })
T("a secondary is a secondary", Ammo.SlotOf(sec) == "secondary", Ammo.SlotOf(sec))

------------------------------------------- starting magazines, spawns

-- A player with two guns: the inventory knows them by their slot.
local function two_gun_player(primary, secondary)
  local u = ENV.make_unit()
  local inv = {}
  function inv:available_selections()
    return { [1] = { unit = { base = function() return secondary end } },
             [2] = { unit = { base = function() return primary end } } }
  end
  function inv:unit_by_selection(i)
    local w = i == 2 and primary or secondary
    return { base = function() return w end }
  end
  function inv:equipped_unit() return { base = function() return primary end } end
  function u:inventory() return inv end
  primary._setup.user_unit, secondary._setup.user_unit = u, u
  return u
end

fresh()
local prim = ENV.make_weapon("test_rifle", { "wpn_mag_test" }, 30, { _selection = 2 })
local secw = ENV.make_weapon("test_smg", { "wpn_mag_small" }, 20, { _selection = 1 })
two_gun_player(prim, secw)
-- Fill the rig and the pockets so no magazine fits there.
for _, name in ipairs({ "rig", "pockets" }) do
  while PDTI.AddItemAuto(name, "spare_magazine", 1, { rounds = 0 }, true) do end
end
Ammo.EnsureAllSupplies()
local pk = Ammo.Identify(prim).key
local in_pack = #PDTI.FindItems(function(c, item)
  return c == "backpack" and item.item_id == "spare_magazine" and item.data.queue_key == pk
end)
T("with a full rig and pockets the starting magazines go into the backpack", in_pack == 3, in_pack)
T("that is logged", (function()
  for _, line in ipairs(ENV.logs) do if line:find("went into the backpack", 1, true) then return true end end
end)() == true)

fresh()
prim = ENV.make_weapon("test_rifle", { "wpn_mag_test" }, 30, { _selection = 2 })
secw = ENV.make_weapon("test_smg", { "wpn_mag_small" }, 20, { _selection = 1 })
two_gun_player(prim, secw)
Ammo.EnsureAllSupplies()
local first_rig = PDTI.GetContainer("rig").items[1]
T("the primary gets the first places in the rig", first_rig and first_rig.data.queue_key == Ammo.Identify(prim).key,
  first_rig and first_rig.data.queue_key)

-- The spawn buttons of the inventory screen.
local before_loose = Ammo.LooseOfKey(Ammo.Identify(secw).key)
local sok, srounds = Ammo.DevSpawnLoose("secondary")
T("loose rounds can be spawned for the secondary", sok == true and
  Ammo.LooseOfKey(Ammo.Identify(secw).key) == before_loose + 20, tostring(srounds))
local spawned = PDTI.FindItems(function(_, item)
  return item.item_id == "loose_ammo" and item.data.queue_key == Ammo.Identify(secw).key
end)[1]
T("they are tagged as secondary", spawned and spawned.item.data.slot == "secondary")
local mags_before = #Ammo.AllMagazines(Ammo.Identify(prim).key)
local mok = Ammo.DevSpawnMagazine("primary")
local all = Ammo.AllMagazines(Ammo.Identify(prim).key)
T("a full magazine can be spawned for the primary", mok == true and #all == mags_before + 1)
T("the spawned magazine is full", (function()
  for _, m in ipairs(all) do if m.rounds ~= 30 then return false end end return true end)())

-- A single-shot weapon has no magazine.
local single = ENV.make_weapon("test_pistol", { "wpn_mag_test" }, 1)
T("a single-shot weapon is loaded from the loose rounds", Ammo.FeedMode(single) == "loose")

------------------------------------------------------------ Ctrl+click

fresh()
local ok_add, mag = PDTI.AddItemAuto("rig", "spare_magazine", 1, { rounds = 1 }, true)
local moved, where = PDTI.UIQuickTransfer("rig", mag.instance_id)
T("Ctrl+click moves a rig item into the backpack", moved and where == "backpack", tostring(where))
moved, where = PDTI.UIQuickTransfer("backpack", mag.instance_id)
T("Ctrl+click moves a backpack item into the pockets first", moved and where == "pockets", tostring(where))
-- Fill the pockets: the next one goes to the rig.
local _, m2 = PDTI.AddItemAuto("backpack", "spare_magazine", 1, { rounds = 1 }, true)
while PDTI.FindFreeSpace("pockets", "spare_magazine", true) do
  PDTI.AddItemAuto("pockets", "spare_magazine", 1, { rounds = 1 }, true)
end
moved, where = PDTI.UIQuickTransfer("backpack", m2.instance_id)
T("with full pockets it goes into the rig", moved and where == "rig", tostring(where))
moved, where = PDTI.UIQuickTransfer("pockets", mag.instance_id)
T("Ctrl+click moves a pocket item into the backpack", moved and where == "backpack", tostring(where))

------------------------------------------------------- many loot bags

fresh()
local Loot = PDTI.Loot
local function bag_items()
  return PDTI.FindItems(function(_, item) return item.item_id == "loot_bag" end)
end
ENV.game.carry_id = nil
ENV.game.registered = {}
T("the carry hooks are in place", Loot.InstallHooks() == true)
local gold = { _carry_id = "gold", _unit = { carry_data = function() return { is_attached_to_zipline_unit = function() return false end } end } }
CarryInteractionExt.interact(gold)
Loot.Tick()
T("the first bag is carried", ENV.game.carry_id == "gold" and #bag_items() == 1)

local money = { _carry_id = "money", _unit = gold._unit }
T("a second bag can be picked up", CarryInteractionExt._interact_blocked(money) == false)
CarryInteractionExt.interact(money)
Loot.Tick()
T("you carry the new bag", ENV.game.carry_id == "money", ENV.game.carry_id)
T("the old bag is in the inventory", #bag_items() == 2 and Loot.StoredCount() == 1, #bag_items())
T("the game registers one carried bag", #ENV.game.registered == 1, #ENV.game.registered)

-- Throw the bag: the stored one comes into your hands.
managers.player:drop_carry()
Loot.Tick()
T("the thrown bag left the inventory", #bag_items() == 1, #bag_items())
T("the stored bag comes into your hands", ENV.game.carry_id == "gold", ENV.game.carry_id)
T("the game knows about it", #ENV.game.registered == 1, #ENV.game.registered)

-- Stash it from the inventory screen; hands are free.
T("the carried bag can be stashed", Loot.StashCarried() == true)
Loot.Tick()
T("the stashed bag is not pulled back", ENV.game.carry_id == nil, ENV.game.carry_id)
T("it is still in the inventory", Loot.StoredCount() == 1)

-- Drop it with Discard held.
local stored = bag_items()[1]
T("a stored bag can be dropped", Loot.DropItem(stored.container, stored.item.instance_id) == true)
Loot.Tick()
T("it lies in the world now", ENV.game.thrown[#ENV.game.thrown] == "gold" and #bag_items() == 0)
T("nothing else is pulled out", ENV.game.carry_id == nil)

-- As the client of another host only one bag, as in the game.
ENV.game.client = true
CarryInteractionExt.interact(gold)
Loot.Tick()
T("as a client a second bag is blocked", CarryInteractionExt._interact_blocked(money) == true)
ENV.game.client = false

------------------------------------------- loading a magazine is silent

fresh()
local unit7 = ENV.make_unit()
local plays = 0
unit7.sound = function() return { play = function() plays = plays + 1 end } end
local rifle3 = ENV.make_weapon("test_rifle")
unit7:set_weapon(rifle3)
Ammo.EnsureSupply(rifle3)
local r3 = Ammo.Identify(rifle3).key
local first = Ammo.Magazines(r3)[1]
Ammo.SetMagazineRounds(first.container, first.instance_id, 0)
Ammo.AddLooseKey(r3, 10, Ammo.Identify(rifle3))
Ammo.StartJob(rifle3)
for _ = 1, 20 do Ammo.Tick(1) end
T("holding R loads rounds into the magazine", Ammo.LooseOfKey(r3) < 10, Ammo.LooseOfKey(r3))
T("without a sound for every round", plays == 0, plays)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
