-- 0.19.6: the game's other deployables as inventory items: trip mines, ECM
-- jammers, spy cameras (put on a wall), sentry guns (normal and suppressed),
-- the throwable case and the armor kit.
--   luajit tests/deployables_new_tests.lua
local script = arg and arg[0] or "tests/deployables_new_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_deploy_new") .. "/")
ENV.install_game()
ENV.load_mod(ROOT, true)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Dep = PDTI.Deployables
local function clear_inventory()
  for _, c in ipairs({ "rig", "pockets", "backpack" }) do
    for _, it in ipairs(PDTI.GetContainer(c).items) do PDTI.RemoveItem(c, it.instance_id) end
  end
end

-- The game's equipment data for the new kinds (as in EquipmentsTweakData).
local eq = tweak_data.equipments
eq.trip_mine = { icon = "equipment_trip_mine", dummy_unit = "dummy_trip", use_function_name = "use_trip_mine" }
eq.ecm_jammer = { icon = "equipment_ecm_jammer", dummy_unit = "dummy_ecm", use_function_name = "use_ecm_jammer" }
eq.spy_camera = { icon = "equipment_spy_camera", dummy_unit = "dummy_cam", use_function_name = "use_spy_camera" }
eq.sentry_gun = { icon = "equipment_sentry", unit = 1, dummy_unit = "dummy_sentry", use_function_name = "use_sentry_gun" }
eq.sentry_gun_silent = { icon = "equipment_sentry_silent", unit = 2, dummy_unit = "dummy_sentry",
  use_function_name = "use_sentry_gun" }
eq.grenade_crate = { icon = "equipment_grenade_crate", dummy_unit = "dummy_crate", use_function_name = "use_grenade_crate" }
eq.armor_kit = { icon = "equipment_armor_kit", use_function_name = "use_armor_kit" }

-- The player's equipment object: what was checked and placed, with what.
local PE = { calls = {} }
function PE:valid_shape_placement(id, data)
  self.calls[#self.calls + 1] = "shape:" .. tostring(id) .. (data and "+data" or "")
  self.dummy = data ~= nil or self.dummy
  return self.valid ~= false and {}
end
function PE:valid_look_at_placement(data)
  self.calls[#self.calls + 1] = "look" .. (data and "+data" or "")
  self.dummy = data ~= nil or self.dummy
  return self.valid ~= false and {}
end
local function placer(name)
  PE[name] = function(self, selected_index, unit_index)
    self.calls[#self.calls + 1] = name .. ":" .. tostring(selected_index) .. ":" .. tostring(unit_index)
    if name == "use_sentry_gun" and self.client then
      self._sentrygun_placement_requested = true
      return false
    end
    if name == "use_armor_kit" then return true, function() self.calls[#self.calls + 1] = "armor_redirect" end end
    return self.dummy == true
  end
end
for _, n in ipairs({ "use_trip_mine", "use_ecm_jammer", "use_spy_camera", "use_sentry_gun", "use_grenade_crate",
  "use_armor_kit" }) do placer(n) end
local unit = { equipment = function() return PE end }
_G.alive = function(u) return u ~= nil end
local slots = { selections = {}, selected_index = 1 }
local hints = {}
_G.managers = { player = { player_unit = function() return unit end, _equipment = slots },
  hud = { show_hint = function(_, p) hints[#hints + 1] = p.text end } }

------------------------------------------------------------- the items

local new = { "trip_mine", "ecm_jammer", "spy_camera", "sentry_gun", "sentry_gun_silent", "grenade_crate", "armor_bag" }
local missing = {}
for _, id in ipairs(new) do
  local def = PDTI.GetItemDefinition(id)
  if not (def and def.deployable and Dep.Method(id) and PDTI.Ammo.PRICES.item[id]) then missing[#missing + 1] = id end
end
T("every deployable of the game is an item with a placement function and a price", #missing == 0,
  table.concat(missing, ","))
T("the armor kit is not the armour plate", Dep.EquipmentId("armor_bag") == "armor_kit"
  and not PDTI.GetItemDefinition("armor_kit").deployable)
local plan = {}
for _, id in ipairs(PDTI.Plan.Items()) do plan[id] = true end
local not_in_plan = {}
for _, id in ipairs(new) do if not plan[id] then not_in_plan[#not_in_plan + 1] = id end end
T("all of them can be brought in the menu", #not_in_plan == 0, table.concat(not_in_plan, ","))
eq.spy_camera = nil
plan = {}
for _, id in ipairs(PDTI.Plan.Items()) do plan[id] = true end
T("one the game does not have is not offered", plan.spy_camera == nil and plan.trip_mine == true)
eq.spy_camera = { icon = "equipment_spy_camera", dummy_unit = "dummy_cam", use_function_name = "use_spy_camera" }

------------------------------------------------------------ placing them

local function place(id)
  clear_inventory()
  PE.calls, PE.dummy = {}, false
  PDTI.AddItemAuto(id == "trip_mine" and "pockets" or "rig", id, 1, nil, true)
  PDTI.SetDeployable(id)
  local ok = Dep.Place(PE)
  return ok, Dep.Count(id)
end

local ok, left = place("trip_mine")
T("a trip mine is checked on the wall in front, with its data", PE.calls[1] == "look+data", PE.calls[1])
T("and placed and taken out of the inventory", ok == true and left == 0 and PE.calls[2]:find("use_trip_mine") == 1)
ok, left = place("ecm_jammer")
T("an ECM jammer is placed on a wall", ok == true and left == 0 and PE.calls[1] == "look+data")
ok, left = place("spy_camera")
T("a spy camera too", ok == true and left == 0 and PE.calls[1] == "look+data")
ok, left = place("grenade_crate")
T("a throwable case is put down like a bag", ok == true and left == 0 and PE.calls[1] == "shape:grenade_crate+data")
ok, left = place("sentry_gun")
T("a sentry gun gets the game's slot and unit 1", ok == true and left == 0
  and PE.calls[2] == "use_sentry_gun:1:1", PE.calls[2])
ok, left = place("sentry_gun_silent")
T("the suppressed sentry gun unit 2", ok == true and left == 0 and PE.calls[2] == "use_sentry_gun:1:2", PE.calls[2])
ok, left = place("armor_bag")
T("the armor kit needs no spot and is used", ok == true and left == 0 and PE.calls[1] == "use_armor_kit:1:nil",
  PE.calls[1])

-- The game's placement check for the inventory's item (the placement model).
local PM = {
  _equipment = slots,
  selected_equipment = function() return nil end,
  can_use_selected_equipment = function() return false end,
  use_selected_equipment = function() return nil end,
  check_equipment_placement_valid = function() return false end,
  add_sentry_gun = function() end,
  from_server_equipment_place_result = function(self, idx)
    local e = self._equipment.selections[idx]
    if e then e.amount[1] = e.amount[1] - 1 end
  end
}
_G.PlayerManager = PM
dofile(ROOT .. "lua/hooks_player_manager.lua")
clear_inventory()
PDTI.AddItemAuto("pockets", "trip_mine", 1, nil, true)
PDTI.SetDeployable("trip_mine")
PE.calls = {}
T("the game's check for a trip mine is the wall check", PM.check_equipment_placement_valid(PM, unit, "trip_mine") == true
  and PE.calls[1] == "look+data", PE.calls[1])
PE.valid = false
T("and says no where it does not fit", PM.check_equipment_placement_valid(PM, unit, "trip_mine") == false)
PE.valid = nil
clear_inventory()
PDTI.AddItemAuto("rig", "armor_bag", 1, nil, true)
PDTI.SetDeployable("armor_bag")
PE.valid = false
T("the armor kit is always valid", PM.check_equipment_placement_valid(PM, unit, "armor_kit") == true)
PE.valid = nil

-- A client asks the host for the sentry gun: the item goes when it is placed.
clear_inventory()
PDTI.AddItemAuto("rig", "sentry_gun", 1, nil, true)
PDTI.SetDeployable("sentry_gun")
PE.calls, PE.dummy, PE.client = {}, false, true
ok = Dep.Place(PE)
T("a client's sentry gun is asked for, not taken out yet", ok == false and Dep.Count("sentry_gun") == 1
  and Dep.pending_sentry == "sentry_gun")
local game_count = { 1 }
slots.selections[1] = { equipment = "ammo_bag", amount = game_count }
PM.from_server_equipment_place_result(PM, 1, unit, { id = function() return 7 end })
T("the host placed it: the item is taken out, the game's count is left", Dep.Count("sentry_gun") == 0
  and Dep.pending_sentry == nil and game_count[1] == 1)
PE.client, PE._sentrygun_placement_requested = nil, nil
slots.selections[1] = nil

----------------------------------------------------- the sentry gun's ammo, pickup

_G.PlayerEquipment = { _sentry_gun_ammo_cost = function(self) self.cost_taken = true end }
_G.SentryGunBase = { on_interaction = function(self) self.picked = true end }
Dep._game_hooks_done = nil
T("the game hooks go in", Dep.InstallGameHooks() == true)
local pe = setmetatable({}, { __index = PlayerEquipment })
PlayerEquipment._sentry_gun_ammo_cost(pe, 1)
T("a sentry gun costs no ammunition while the ammunition system runs", pe.cost_taken == nil)
PDTI.Ammo.settings.enabled = false
PlayerEquipment._sentry_gun_ammo_cost(pe, 1)
T("with it off the game's cost applies", pe.cost_taken == true)
PDTI.Ammo.settings.enabled = true

clear_inventory()
local game_sentries = 0
PM._pdti_original.add_sentry_gun = function(_, n) game_sentries = game_sentries + n end
PM._pdti_deploy_patched = nil
dofile(ROOT .. "lua/hooks_player_manager.lua")
PM.add_sentry_gun(PM, 1, "sentry_gun_silent")
T("a picked-up sentry gun goes back into the inventory", PDTI.FindItems(function(_, it)
  return it.item_id == "sentry_gun_silent" end)[1] ~= nil and game_sentries == 0)
T("and a hint says where", hints[#hints] and hints[#hints]:find("Suppressed Sentry Gun") ~= nil, hints[#hints])

-- No room: the pickup is refused, the sentry stays where it is.
for _, c in ipairs({ "rig", "rig_2", "rig_3", "pockets", "backpack" }) do
  while PDTI.AddItemAuto(c, "bandage", 1, nil, true) do end
end
local sentry = setmetatable({ get_type = function() return "sentry_gun" end }, { __index = SentryGunBase })
SentryGunBase.on_interaction(sentry)
T("with no room a sentry gun is not picked up", sentry.picked == nil and hints[#hints]:find("No room") ~= nil,
  hints[#hints])
clear_inventory()
SentryGunBase.on_interaction(sentry)
T("with room it is", sentry.picked == true)
local other = setmetatable({ get_type = function() return "mod_turret" end }, { __index = SentryGunBase })
SentryGunBase.on_interaction(other)
T("another mod's turret is left to the game", other.picked == true)

-- 0.29.2: a trip mine from the inventory as a shaped charge on a safe. The
-- game asks has_deployable_left and takes one with remove_equipment.
do
  local game_removed = 0
  local SM = {
    _equipment = { selections = {}, selected_index = 1 },
    selected_equipment = function() return nil end,
    has_deployable_left = function(self, equipment, slot)
      for _, e in ipairs(self._equipment.selections) do
        if e.equipment == equipment then return e.amount[slot or 1] > 0 end
      end
      return false
    end,
    has_equipment = function(self, equipment)
      for _, e in ipairs(self._equipment.selections) do if e.equipment == equipment then return true end end
      return false
    end,
    remove_equipment = function(self, equipment, slot)
      -- the game's own code indexes the entry it finds (an error without it)
      for _, e in ipairs(self._equipment.selections) do
        if e.equipment == equipment then e.amount[slot or 1] = e.amount[slot or 1] - 1; game_removed = game_removed + 1 end
      end
    end
  }
  _G.PlayerManager = SM
  dofile(ROOT .. "lua/hooks_player_manager.lua")
  local saved = managers.player._equipment
  managers.player._equipment = SM._equipment
  local function mines() return #PDTI.FindItems(function(_, it) return it.item_id == "trip_mine" end) end
  clear_inventory()
  T("no trip mine anywhere: the safe cannot take one", SM.has_deployable_left(SM, "trip_mine", 1) == false)
  T("taking one then does nothing (the game's code would fail)", (function()
    SM.remove_equipment(SM, "trip_mine", 1); return game_removed == 0 end)())
  PDTI.AddItemAuto("pockets", "trip_mine", 1, nil, true)
  T("a trip mine in the pockets counts for the safe", SM.has_deployable_left(SM, "trip_mine", 1) == true)
  SM.remove_equipment(SM, "trip_mine", 1)
  T("setting the charge takes it out of the inventory", mines() == 0 and game_removed == 0, mines())
  PDTI.AddItemAuto("backpack", "trip_mine", 1, nil, true)
  T("one in the backpack is not to hand", SM.has_deployable_left(SM, "trip_mine", 1) == false)
  clear_inventory()
  SM._equipment.selections[1] = { equipment = "trip_mine", amount = { 2 } }
  PDTI.AddItemAuto("pockets", "trip_mine", 1, nil, true)
  SM.remove_equipment(SM, "trip_mine", 1)
  T("the game's own trip mines are used first", game_removed == 1 and mines() == 1
    and SM._equipment.selections[1].amount[1] == 1)
  SM._equipment.selections[1].amount[1] = 0
  SM.remove_equipment(SM, "trip_mine", 1)
  T("then the inventory's", game_removed == 1 and mines() == 0)
  T("another deployable is not touched", SM.has_deployable_left(SM, "ecm_jammer", 1) == false)
  managers.player._equipment = saved
  clear_inventory()
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
