-- 0.11.0: rigs with sections, the new backpacks, what they do, and magazine
-- sizes by weapon type.
--   luajit tests/gear_tests.lua
local script = arg and arg[0] or "tests/gear_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_gear") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()
ENV.load_mod(ROOT, false)

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local function equip(rig, pack)
  PDTI.Reset()
  if rig then assert(PDTI.SetEquipment("rig", rig)) end
  if pack then assert(PDTI.SetEquipment("backpack", pack)) end
end
local function size(name) local i = PDTI.GetContainerInfo(name); return i.width .. "x" .. i.height end
local function add(name, id, data) return PDTI.AddItemAuto(name, id, 1, data, true) end

------------------------------------------------------------ the equipment

T("three rigs", #PDTI.GetEquipmentOptions("rig") == 3)
T("three backpacks, small to large", (function()
  local o = PDTI.GetEquipmentOptions("backpack")
  return #o == 3 and o[1].id == "small_backpack" and o[2].id == "medium_backpack" and o[3].id == "large_backpack"
end)())
T("a new inventory has the general rig and the medium backpack",
  PDTI.GetEquipment().rig == "general_rig" and PDTI.GetEquipment().backpack == "medium_backpack")

equip("medical_rig")
T("medical rig: 16 slots for kits and medic bags (8x2)", size("rig") == "8x2", size("rig"))
T("medical rig: two ammo pouches of 1x3", size("rig_2") == "1x3" and size("rig_3") == "1x3")
T("a first aid kit goes in the medical part", add("rig", "first_aid_kit") == true)
T("a medic bag goes in the medical part", add("rig", "doctor_bag") == true)
T("an ammo bag does not", add("rig", "ammo_bag") == false)
T("a magazine does not go in the medical part", add("rig", "spare_magazine", { capacity = 20 }) == false)
T("a magazine goes in a pouch", add("rig_2", "spare_magazine", { capacity = 30 }) == true)
T("loose rounds go in a pouch", add("rig_3", "loose_ammo") == true)
T("a first aid kit does not go in a pouch", add("rig_2", "first_aid_kit") == false)

equip("assault_rig")
T("assault rig: 21 slots for ammunition (7x3)", size("rig") == "7x3", size("rig"))
T("assault rig: 12 slots for ammo bags (6x2)", size("rig_2") == "6x2", size("rig_2"))
T("no third section", size("rig_3") == "0x0")
T("magazines in the ammunition part", add("rig", "spare_magazine", { capacity = 30 }) == true)
T("a first aid kit does not fit the assault rig", add("rig", "first_aid_kit") == false and add("rig_2", "first_aid_kit") == false)
T("two ammo bags in the bag part", add("rig_2", "ammo_bag") == true and add("rig_2", "ammo_bag") == true)
T("ammo bags in the rig are deployables to hand", PDTI.Deployables.Count("ammo_bag") == 2)
T("a magazine in the second section is to hand", (function()
  for _, n in ipairs(PDTI.Ammo.ACTIVE) do if n == "rig_2" then return true end end
end)())

equip("general_rig")
T("general rig: 18 slots for anything (3x6)", size("rig") == "3x6", size("rig"))
T("anything a rig holds goes in it", add("rig", "first_aid_kit") and add("rig", "ammo_bag") and add("rig", "spare_magazine", { capacity = 30 }))

equip(nil, "small_backpack");  T("small backpack: 10 slots", size("backpack") == "5x2", size("backpack"))
equip(nil, "medium_backpack"); T("medium backpack: 20 slots", size("backpack") == "5x4", size("backpack"))
equip(nil, "large_backpack");  T("large backpack: 30 slots", size("backpack") == "6x5", size("backpack"))

T("a first aid kit takes one slot", PDTI.GetItemDefinition("first_aid_kit").w == 1 and PDTI.GetItemDefinition("first_aid_kit").h == 1)

------------------------------------------------- changing the equipment

equip("general_rig", "large_backpack")
add("rig", "first_aid_kit"); add("rig", "ammo_bag")
T("a new rig: what does not fit moves elsewhere (the pockets first)", PDTI.SetEquipment("rig", "assault_rig") == true
  and PDTI.Deployables.Count("ammo_bag") == 1 and PDTI.GetContainer("pockets").items[1]
  and PDTI.GetContainer("pockets").items[1].item_id == "first_aid_kit")
T("the ammo bag went to the ammo bag part", PDTI.GetContainer("rig_2").items[1] and PDTI.GetContainer("rig_2").items[1].item_id == "ammo_bag")
T("the state stays valid", PDTI.ValidateState() == true)
managers.player.player_unit = function() return {} end
T("in a heist the equipment cannot be changed", PDTI.RequestEquip("rig", "general_rig") == false)
managers.player.player_unit = function() return nil end
T("in the menu it can", PDTI.RequestEquip("rig", "general_rig") == true)

------------------------------------------------------------ old saves

do
  local old = {
    schema_version = 6, next_id = 10,
    equipment = { backpack = "heavy_pack", rig = "medic_rig" },
    containers = {
      pockets = { items = {} },
      -- the medic rig was 4x3: the kit at 3,2 is outside the medical rig's 8x2 part
      rig = { items = { { instance_id = 1, item_id = "first_aid_kit", x = 3, y = 2, rotated = false, amount = 1 } } },
      -- the heavy pack was 8x6: the bag at 5,4 is outside the large backpack (6x5)
      backpack = { items = { { instance_id = 2, item_id = "doctor_bag", x = 5, y = 4, rotated = false, amount = 1 } } }
    }
  }
  local f = io.open(TMP .. "pdti_inventory.json", "w"); f:write(json.encode(old)); f:close()
  os.remove(TMP .. "pdti_inventory.json.bak")
  dofile(ROOT .. "lua/inventory.lua")
  local eq = PDTI.GetEquipment()
  T("old equipment is renamed", eq.rig == "medical_rig" and eq.backpack == "large_backpack", eq.rig .. "/" .. eq.backpack)
  local found = PDTI.FindItems(function(_, item) return item.item_id == "first_aid_kit" or item.item_id == "doctor_bag" end)
  T("items that no longer fit where they were are kept elsewhere", #found == 2, #found)
  T("and the state is valid", PDTI.ValidateState() == true)
end

------------------------------------------------------- magazine sizes

local function msize(cap, class, akimbo) local w, h = PDTI.MagazineSize(cap, class, akimbo); return w .. "x" .. h end
T("shotgun: 5 shells one slot", msize(5, "shotgun") == "1x1")
T("shotgun: 6 shells two slots", msize(6, "shotgun") == "1x2")
T("shotgun: 10 shells three in a line", msize(10, "shotgun") == "1x3")
T("shotgun: 20 shells a 2x2 square", msize(20, "shotgun") == "2x2")
T("rifle: 30 two slots, 60 three, 100 four", msize(30, "assault_rifle") == "1x2" and msize(60, "assault_rifle") == "1x3"
  and msize(100, "assault_rifle") == "2x2")
T("a 17-round pistol magazine takes one slot", msize(17, "pistol") == "1x1")
T("a 30-round pistol magazine takes two", msize(30, "pistol") == "1x2")
T("akimbo magazines are sized like a single gun's", msize(17, "pistol", true) == msize(17, "pistol") and msize(34, "pistol", true) == msize(34, "pistol"))
T("a 6-round revolver speedloader takes one slot", msize(6, "revolver") == "1x1")
T("a 10-round sniper magazine takes two", msize(10, "snp") == "1x2")
T("a 100-round LMG box takes three, 200 four", msize(100, "lmg") == "1x3" and msize(200, "lmg") == "2x2")
T("every type has its own steps", PDTI.MAGAZINE_STEPS.shotgun[1] ~= PDTI.MAGAZINE_STEPS.smg[1]
  and PDTI.MAGAZINE_STEPS.smg[1] ~= PDTI.MAGAZINE_STEPS.assault_rifle[1])

do
  tweak_data.weapon.factory.parts.wpn_mag_shell = { type = "magazine", stats = { CLIP_AMMO_MAX = 8 } }
  tweak_data.weapon.test_saiga = { AMMO_MAX = 40, categories = { "shotgun" } }
  local wep = ENV.make_weapon("test_saiga", { "wpn_mag_shell" }, 8)
  T("the size class comes from the weapon", PDTI.Ammo.SizeClass(wep) == "shotgun")
  local info = PDTI.Ammo.Identify(wep)
  equip("general_rig")
  local ok, made = PDTI.Ammo.AddMagazineKey(info.key, 8, info)
  local item = ok and PDTI.FindItem(made.container, made.instance_id)
  T("a shotgun magazine knows its type", item and item.data.mag_class == "shotgun")
  local cells = 0
  for _, row in ipairs(PDTI.GetOccupancyMap(made.container).cells) do
    for _, id in ipairs(row) do if id == made.instance_id then cells = cells + 1 end end
  end
  T("an 8-shell shotgun magazine takes two slots", cells == 2, cells)
end

------------------------------------------------------------ speed

local Carry = PDTI.Carry
equip("general_rig", "medium_backpack")
T("general rig: 25% faster", near(Carry.GetBreakdown().gear, 1.25), Carry.GetBreakdown().gear)
equip("general_rig", "small_backpack")
T("general rig and small backpack: 50% faster", near(Carry.GetBreakdown().gear, 1.5))
equip("assault_rig", "medium_backpack")
T("assault rig and medium backpack: no bonus", near(Carry.GetBreakdown().gear, 1))
local real_load = Carry.LoadFactor
Carry.LoadFactor = function() return 0.6 end
T("a medium backpack: the full load slowdown", near(Carry.GetBreakdown().load, 0.6))
equip("assault_rig", "large_backpack")
T("a large backpack: the load slows you 30% less", near(Carry.GetBreakdown().load, 1 - 0.4 * 0.7), Carry.GetBreakdown().load)
Carry.LoadFactor = real_load
local real_loot = Carry.LootFactor
Carry.LootFactor = function() return 0.5 end
T("a large backpack: the loot slows you 30% less", near(Carry.GetBreakdown().loot, 1 - 0.5 * 0.7))
Carry.LootFactor = real_loot

------------------------------------------------------- enemy focus

do
  _G.PlayerMovement = { _apply_attention_setting_modifications = function(self, setting)
    setting.weight_mul = (setting.weight_mul or 1) * 0.5 -- a camouflage skill
  end }
  T("the enemy focus hook goes in", PDTI.Gear.InstallHooks() == true)
  equip(nil, "large_backpack")
  local setting = {}
  PlayerMovement._apply_attention_setting_modifications({}, setting)
  T("large backpack: enemies focus you 50% more (skills still count)", near(setting.weight_mul, 0.5 * 1.5), setting.weight_mul)
  equip(nil, "medium_backpack")
  setting = {}
  PlayerMovement._apply_attention_setting_modifications({}, setting)
  T("other backpacks: as in the game", near(setting.weight_mul, 0.5))
  T("installing twice wraps once", PDTI.Gear.InstallHooks() == true and (function()
    local s = {}; equip(nil, "large_backpack"); PlayerMovement._apply_attention_setting_modifications({}, s)
    return near(s.weight_mul, 0.75)
  end)())
end

------------------------------------------------------- getting up

do
  local Gear = PDTI.Gear
  local state_name = "bleed_out"
  local sent, hints = {}, {}
  _G.Message = { RevivePlayer = "revive_player" }
  managers.player.current_state = function() return state_name end
  managers.player.send_message = function(_, msg) sent[#sent + 1] = msg end
  managers.hud = { show_hint = function(_, h) hints[#hints + 1] = h.text end }
  local function bags() return #PDTI.FindItems(function(_, i) return i.item_id == "doctor_bag" end) end

  equip("general_rig")
  add("rig", "doctor_bag")
  Gear.OnHeistStart()
  Gear.Tick({ btn_jump_press = true })
  T("without the medical rig SPACE does nothing", #sent == 0 and bags() == 1)

  equip("medical_rig")
  add("rig", "doctor_bag")
  Gear.OnHeistStart()
  Gear.Tick({})
  T("down with a medic bag: you are told to press SPACE", #hints == 1 and hints[1]:find("SPACE") ~= nil, hints[1])
  Gear.Tick({})
  T("told once", #hints == 1)
  Gear.Tick({ btn_jump_press = true })
  T("SPACE gets you up", sent[1] == "revive_player")
  T("the medic bag is used up", bags() == 0)
  add("rig", "doctor_bag")
  Gear.Tick({ btn_jump_press = true })
  T("only once per heist", #sent == 1 and bags() == 1)
  Gear.OnHeistStart()
  state_name = "standard"
  Gear.Tick({ btn_jump_press = true })
  T("standing, SPACE is a jump", #sent == 1 and bags() == 1)
  state_name = "bleed_out"
  Gear.Tick({ btn_jump_press = true })
  T("a new heist: once more", #sent == 2 and bags() == 0)
  PDTI.RemoveItem("rig", (PDTI.GetContainer("rig").items[1] or {}).instance_id or -1)
  Gear.OnHeistStart()
  Gear.Tick({ btn_jump_press = true })
  T("without a medic bag nothing happens", #sent == 2)
  managers.hud = nil
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
