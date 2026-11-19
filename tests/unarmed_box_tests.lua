-- 0.44.0: into a heist with no weapon, then an enemy's gun picked up (the
-- Pick Up Weapons mod): ammo boxes give it loose rounds. The armory, the
-- ammunition system and the skills together, on the game's own way a box is
-- picked up. A box that stays on the floor says why in the log.
--   luajit tests/unarmed_box_tests.lua
local script = arg and arg[0] or "tests/unarmed_box_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
ENV.setup(ROOT, (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_unarmed_box") .. "/")
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 }, game_settings = { single_player = true } }
ENV.install_game()

-- The game's weapons and their parts.
local W = tweak_data.weapon
W.amcar = { AMMO_MAX = 120, CLIP_AMMO_MAX = 20, categories = { "assault_rifle" }, use_data = { selection_index = 2 },
  name_id = "AMCAR", AMMO_PICKUP = { 3, 6 } }
W.glock_17 = { AMMO_MAX = 90, CLIP_AMMO_MAX = 17, categories = { "pistol" }, use_data = { selection_index = 1 },
  name_id = "Chimano", AMMO_PICKUP = { 3, 6 } }
W.new_mp5 = { AMMO_MAX = 150, CLIP_AMMO_MAX = 30, categories = { "smg" }, use_data = { selection_index = 1 },
  name_id = "Compact-5", AMMO_PICKUP = { 3, 6 } }
W.new_m4 = { AMMO_MAX = 150, CLIP_AMMO_MAX = 30, categories = { "assault_rifle" }, use_data = { selection_index = 2 },
  name_id = "CAR-4", AMMO_PICKUP = { 4, 8 } }
local FACTORY = { amcar = "wpn_fps_ass_amcar", glock_17 = "wpn_fps_pis_g17", new_mp5 = "wpn_fps_smg_mp5",
  new_m4 = "wpn_fps_ass_m4" }
local WEAPON_OF = {}
for id, f in pairs(FACTORY) do WEAPON_OF[f] = id end
local FP = tweak_data.weapon.factory.parts
local DEFAULT = {}
for id, f in pairs(FACTORY) do
  FP[f .. "_mag"] = { type = "magazine", stats = { CLIP_AMMO_MAX = W[id].CLIP_AMMO_MAX, mag_amount = 3 } }
  DEFAULT[f] = { f .. "_mag" }
end
managers.weapon_factory = {
  get_factory_id_by_weapon_id = function(_, id) return FACTORY[id] end,
  get_default_blueprint_by_factory_id = function(_, f) return DEFAULT[f] end
}
managers.hud.set_ammo_amount = function() end
local hints = {}
managers.hud.show_hint = function(_, h) hints[#hints + 1] = h.text end

-- The game's classes, before the mod hooks them: a weapon spawned into a
-- selection (the one there is deleted), and the game's box pickup (its loop
-- over your guns, the one in hand first).
_G.PlayerInventory.add_unit_by_factory_name = function(self, f, equip)
  self:_spawn(f)
  if equip then self.eq = W[WEAPON_OF[f]].use_data.selection_index end
end
_G.AmmoClip = { _pickup = function(self, unit)
  if self._picked_up then return end
  local picked = false
  local inv = unit:inventory()
  for _, i in ipairs({ inv.eq, inv.eq == 1 and 2 or 1 }) do
    local sel = inv.sel[i]
    if sel then
      local ok = sel.unit:base():add_ammo(1, self._ammo_count)
      picked = ok or picked
    end
  end
  if picked then self._picked_up = true; return true end
  return false
end }

ENV.load_mod(ROOT, false)
PDTI._loaded = true
dofile(ROOT .. "lua/ammo_hooks.lua")
dofile(ROOT .. "lua/skills.lua")
dofile(ROOT .. "lua/skills_ammo.lua")
_G.Idstring = function(s) return "ids:" .. tostring(s) end

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function logged(text)
  for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then return true end end
  return false
end

local Ammo, A, Skills = PDTI.Ammo, PDTI.Armory, PDTI.Skills
A.Enabled = function() return true end
local steps = {}
Skills.Basic = function(id) return steps[id] ~= nil end
T("the ammunition hooks are in place", Ammo.InstallHooks() == true)
pcall(A.InstallHooks)
Skills.Install()
T("the ammo skills' hooks are in place", Skills.failed == nil or Skills.failed.ammo == nil)

-- The player: two selections, a weapon unit in each.
local function new_player()
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.AmmoSkills.OnHeistStart()
  Ammo.box_reasons = {}
  PDTI.SetEquipment("rig", "general_rig")
  PDTI.SetEquipment("backpack", "small_backpack")
  -- A weapon of yours in the locker: the armory is in use; both hands empty.
  PDTI.AddItemAuto("locker", A.ITEM_ID, 1, A.MakeData("new_m4", nil, 77), true)
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  unit.character_damage = function() return { dead = function() return false end } end
  local inv = { sel = {}, eq = 2 }
  function inv:_spawn(f)
    local id = WEAPON_OF[f]
    local s = W[id].use_data.selection_index
    local base = ENV.make_weapon(id, DEFAULT[f], W[id].CLIP_AMMO_MAX, { _factory_id = f, _selection = s,
      _ammo_pickup = W[id].AMMO_PICKUP, ammo_max = W[id].AMMO_MAX, total = W[id].AMMO_MAX, clip = W[id].CLIP_AMMO_MAX,
      _picked_up_weapon_data = rawget(_G, "PickUpWeapons") and PickUpWeapons._picked_up_weapon_data })
    base.set_visibility_state = function() end
    base.set_slot = function() end
    setmetatable(base, { __index = RaycastWeaponBase })
    local u = { f = f }
    u.base = function() return base end
    u.visible = function() return false end
    if self.sel[s] then self.sel[s].unit.deleted = true end
    self.sel[s] = { unit = u }
    return u
  end
  function inv:available_selections() return self.sel end
  function inv:equipped_selection() return self.eq end
  function inv:equip_selection(i) self.eq = i; return true end
  function inv:remove_selection(i) self.sel[i] = nil end
  function inv:equipped_unit() return self.sel[self.eq] and self.sel[self.eq].unit end
  inv.add_unit_by_factory_name = function(...) return PlayerInventory.add_unit_by_factory_name(...) end
  function unit:inventory() return inv end
  -- The game spawns you with its default weapons (the hands are empty).
  inv:_spawn("wpn_fps_ass_amcar")
  inv:_spawn("wpn_fps_pis_g17")
  return unit, inv
end
local function box() return setmetatable({}, { __index = AmmoClip }) end
-- Pick Up Weapons: an enemy's gun into its selection.
local function pick_up(inv, weapon_id)
  _G.PickUpWeapons = { _picked_up_weapon_data = { is_npc = true, weapon_id = weapon_id, factory_id = FACTORY[weapon_id],
    ammo = { total = 0.3, clip = 0.5 } } }
  PlayerInventory.add_unit_by_factory_name(inv, FACTORY[weapon_id], true, false, nil)
  PickUpWeapons._picked_up_weapon_data = nil
end

do
  local unit, inv = new_player()
  T("into the heist with no weapon: the stand-in", A.OnSpawn(unit) and A.IsStandIn(inv.sel[1].unit)
    and inv.sel[2] == nil)
  T("  a box stays on the floor (no gun to take it)", AmmoClip._pickup(box(), unit) == false)
  T("  and the log says why", logged("an ammo box stayed on the floor: glock_17: no weapon in your hands"))
  local n = #ENV.logs
  AmmoClip._pickup(box(), unit)
  T("  once (not for every box, nor every frame)", #ENV.logs == n)
  local real_reason, reads = Ammo.BoxLeftReason, 0
  Ammo.BoxLeftReason = function(...) reads = reads + 1; return real_reason(...) end
  local same = box()
  for _ = 1, 5 do AmmoClip._pickup(same, unit) end
  Ammo.BoxLeftReason = real_reason
  T("  a box you stand on is read once, not every frame", reads == 1, reads)

  pick_up(inv, "new_mp5")
  local smg = inv.sel[1].unit:base()
  local info = Ammo.Identify(smg)
  T("an enemy's Compact-5 picked up: in your hands, yours, managed", not A.IsStandIn(inv.sel[1].unit)
    and A.HandItem("secondaries").data.weapon_id == "new_mp5" and info ~= nil and Ammo.SkipReason(smg) == nil)
  T("  a box now gives it loose rounds", AmmoClip._pickup(box(), unit) == true and Ammo.LooseOfKey(info.key) >= 3,
    Ammo.LooseOfKey(info.key))
  local had = Ammo.LooseOfKey(info.key)
  AmmoClip._pickup(box(), unit)
  T("  and the next one more", Ammo.LooseOfKey(info.key) > had)

  pick_up(inv, "new_m4")
  local rifle = inv.sel[2].unit:base()
  local rinfo = Ammo.Identify(rifle)
  T("then an enemy's CAR-4: both in your hands", inv.sel[1] and inv.sel[2] and rinfo ~= nil
    and A.HandItem("primaries").data.weapon_id == "new_m4")
  T("  a box gives the one in hand loose rounds", AmmoClip._pickup(box(), unit) == true
    and Ammo.LooseOfKey(rinfo.key) >= 4, Ammo.LooseOfKey(rinfo.key))
end

do -- Bulletstorm: a box stays, the hint says why.
  local unit, inv = new_player()
  A.OnSpawn(unit)
  pick_up(inv, "new_mp5")
  steps = { ammo_reservoir = 1 }
  hints = {}
  T("Bulletstorm: a standard box stays, even with a gun", AmmoClip._pickup(box(), unit) == false)
  T("  the hint says why", hints[1] and hints[1]:find("Bulletstorm", 1, true) ~= nil, hints[1])
  steps = {}
end

do -- A gun at the box limit: by design, nothing logged.
  local unit, inv = new_player()
  A.OnSpawn(unit)
  pick_up(inv, "new_mp5")
  local smg = inv.sel[1].unit:base()
  local info = Ammo.Identify(smg)
  Ammo.AddLooseKey(info.key, Ammo.BoxLimit(), info)
  local n = #ENV.logs
  T("a gun at the box limit: the box stays", AmmoClip._pickup(box(), unit) == false)
  T("  (by design: not logged)", #ENV.logs == n)
end

do -- The reason, read for each gun.
  local unit, inv = new_player()
  A.OnSpawn(unit)
  pick_up(inv, "new_mp5")
  local why = Ammo.BoxLeftReason(unit)
  T("a box's reason: each gun's room and pickup", why:find("new_mp5: room", 1, true) ~= nil
    and why:find("pickup 3-6", 1, true) ~= nil, why)
  inv.sel[1].unit:base()._setup = {}
  T("  a gun that is not the player's: said", Ammo.BoxLeftReason(unit):find("not the player's weapon", 1, true) ~= nil,
    Ammo.BoxLeftReason(unit))
  inv.sel = {}
  T("  no gun at all", Ammo.BoxLeftReason(unit) == "no gun")
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
