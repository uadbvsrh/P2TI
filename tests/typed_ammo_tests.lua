-- 0.16.0: assault rifles and SMGs take magazines of four sizes and three
-- kinds of bullets. Reloads take magazines in grid order, and hollow points
-- make every hit on an arm or a leg a critical hit.
--   luajit tests/typed_ammo_tests.lua
local script = arg and arg[0] or "tests/typed_ammo_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_typed") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end
-- The game functions the bullets change.
NewRaycastWeaponBase._get_current_damage = function(self, dmg_mul) return (self._damage or 10) * (dmg_mul or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function(self) return self._armor_piercing_chance or 0.25 end
_G.CopDamage = { roll_critical_hit = function(_, attack_data) return false, attack_data.damage end }
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })
dofile(ROOT .. "lua/ammo_hud.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo, Plan = PDTI.Ammo, PDTI.Plan
T("the hooks are in place", Ammo.InstallHooks() == true)
T("the bullet hooks are in place", Ammo.hooks["NewRaycastWeaponBase._get_current_damage"] ~= nil
  and Ammo.hooks["NewRaycastWeaponBase.armor_piercing_chance"] ~= nil and Ammo.hooks["CopDamage.roll_critical_hit"] ~= nil)

local function fresh(name, capacity, extra)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon(name or "test_ar", { "wpn_no_part" }, capacity or 30, extra)
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  wep.clip = math.min(wep.clip > 0 and wep.clip or 999, wep:get_ammo_max_per_clip())
  Ammo.SyncTotal(wep)
  return wep, Ammo.Identify(wep)
end
local function clear_mags(key)
  for _, m in ipairs(Ammo.AllMagazines(key)) do PDTI.RemoveItem(m.container, m.instance_id) end
end
local function find_mag(key, fn)
  for _, m in ipairs(Ammo.AllMagazines(key)) do if fn(m) then return m end end
end

----------------------------------------------------------------- the scope

do
  local ar = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  local pistol = ENV.make_weapon("test_pistol", { "wpn_no_part" }, 15)
  local pump = ENV.make_weapon("test_pump", { "wpn_no_part" }, 6, { _use_shotgun_reload = true })
  local lmg = ENV.make_weapon("test_smg", { "wpn_mag_test" }, 30)
  local smg = ENV.make_weapon("test_akimbo_smg", { "wpn_no_part" }, 40)
  T("an assault rifle has sizes and bullets", Ammo.Typed(ar) == true and Ammo.Identify(ar).typed == true)
  T("an SMG too (akimbo as well)", Ammo.Typed(smg) == true and Ammo.Identify(smg).akimbo == true)
  T("a pistol, a shotgun and an LMG do not",
    not Ammo.Typed(pistol) and not Ammo.Typed(pump) and not Ammo.Typed(lmg) and not Ammo.Identify(pistol).typed)
  T("the base magazine is the weapon's own (CLIP_AMMO_MAX)", Ammo.Identify(ar).capacity == 30)
  T("akimbo: half of it per gun", Ammo.Identify(smg).capacity == 20)
  T("the supply does not depend on the clip size the mod sets",
    (function() local k = Ammo.Identify(ar).key; ar:set_ammo_max_per_clip(75); return Ammo.Identify(ar).key == k end)())
end

------------------------------------------------------------------ the sizes

T("compact, standard, extended, drum: 20/30/45/75 for 30",
  Ammo.SpecCapacity(30, "compact") == 20 and Ammo.SpecCapacity(30, "standard") == 30
  and Ammo.SpecCapacity(30, "extended") == 45 and Ammo.SpecCapacity(30, "drum") == 75)
do
  local cw, ch = PDTI.MagazineSize(20, "assault_rifle")
  local dw, dh = PDTI.MagazineSize(75, "assault_rifle")
  T("a drum takes more room than a compact magazine", dw * dh > cw * ch, cw .. "x" .. ch .. " vs " .. dw .. "x" .. dh)
  local light = PDTI.ItemWeight({ item_id = Ammo.MAGAZINE_ITEM, data = { capacity = 20, rounds = 20, mag_class = "assault_rifle" } })
  local heavy = PDTI.ItemWeight({ item_id = Ammo.MAGAZINE_ITEM, data = { capacity = 75, rounds = 75, mag_class = "assault_rifle" } })
  T("and weighs more", heavy > light)
end

-- Without a plan: standard magazines, the gun is a standard magazine even
-- with the game's extended magazine mod (45).
local wep, info = fresh("test_ar", 45)
local key = info.key
T("the game's magazine mod does not count: the clip maximum is 30", wep:get_ammo_max_per_clip() == 30, wep:get_ammo_max_per_clip())
T("and the clip holds no more", wep.clip <= 30, wep.clip)
local first = Ammo.Magazines(key)[1]
T("the starting magazines are standard magazines of standard bullets",
  first and first.size == "standard" and first.bullet == "standard" and first.capacity == 30)
T("their number follows the weapon's ammunition (150 / 30 - 1)", #Ammo.AllMagazines(key) == 4, #Ammo.AllMagazines(key))

-------------------------------------------------------- grid order, reload

clear_mags(key)
Ammo.AddMagazineKey(key, 45, info, { "rig" }, { size = "extended", bullet = "standard" })
Ammo.AddMagazineKey(key, 20, info, { "pockets" }, { size = "compact", bullet = "ap" })
local next_mag = Ammo.NextMagazine(wep)
T("the pockets come before the rig, whatever is fuller", next_mag and next_mag.container == "pockets" and next_mag.bullet == "ap")
T("a reload into a compact magazine is faster",
  near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1 / 0.85), NewRaycastWeaponBase.reload_speed_multiplier(wep))

wep.clip = 12
Ammo.SyncTotal(wep)
NewRaycastWeaponBase.on_reload(wep)
T("the reload loads the compact armour-piercing magazine", wep.clip == 20 and Ammo.CurrentBullet(wep) == "ap", wep.clip)
T("the clip maximum is its capacity", wep:get_ammo_max_per_clip() == 20)
local back = find_mag(key, function(m) return m.rounds == 12 end)
T("the old magazine went back as a standard magazine of standard bullets with its 12 rounds",
  back and back.size == "standard" and back.bullet == "standard" and back.capacity == 30)
T("the total is honest", wep.total == 20 + 45 + 12, wep.total)

-- The next one is the extended magazine (the returned one is in the rig too,
-- after it in grid order or before: grid order decides).
local n2 = Ammo.NextMagazine(wep)
T("a drum or an extended magazine is slower",
  n2 and near(NewRaycastWeaponBase.reload_speed_multiplier(wep), 1 / Ammo.MAG_SIZES[n2.size].reload))

----------------------------------------------------------------- the bullets

do
  local w = fresh("test_ar", 30, { _damage = 10, _use_armor_piercing = true, _can_shoot_through_enemy = false })
  T("standard bullets: the weapon's damage", near(NewRaycastWeaponBase._get_current_damage(w, 1), 10))
  T("and its armour piercing", near(NewRaycastWeaponBase.armor_piercing_chance(w), 0.25))
  Ammo.SetLoaded(w, { size = "standard", bullet = "hollow" })
  Ammo.ApplyLoaded(w)
  T("hollow points: x1.3 damage", near(NewRaycastWeaponBase._get_current_damage(w, 1), 13))
  T("never pierce armour plates", NewRaycastWeaponBase.armor_piercing_chance(w) == 0)
  T("ignore the armour-piercing skill and shoot through nothing",
    w._use_armor_piercing == false and w._can_shoot_through_enemy == false and w._can_shoot_through_shield == false)
  Ammo.SetLoaded(w, { size = "standard", bullet = "ap" })
  Ammo.ApplyLoaded(w)
  T("armour piercing: x0.85 damage", near(NewRaycastWeaponBase._get_current_damage(w, 1), 8.5))
  T("always pierce plates", NewRaycastWeaponBase.armor_piercing_chance(w) == 1)
  T("and shoot through enemies and shields", w._can_shoot_through_enemy == true and w._can_shoot_through_shield == true)
  Ammo.SetLoaded(w, { size = "standard", bullet = "standard" })
  Ammo.ApplyLoaded(w)
  T("standard bullets again: the weapon's own flags come back",
    w._can_shoot_through_enemy == false and w._use_armor_piercing == true and w._can_shoot_through_shield == nil)

  -- Not the player's: nothing changes.
  local bot = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _damage = 10 })
  bot._setup = { user_unit = { key = function() return "bot" end } }
  bot._pdti_loaded = { size = "standard", bullet = "hollow" }
  T("another unit's rifle keeps its damage", near(NewRaycastWeaponBase._get_current_damage(bot, 1), 10))
  local pistol = ENV.make_weapon("test_pistol", { "wpn_no_part" }, 15, { _damage = 10 })
  pistol._pdti_loaded = { size = "standard", bullet = "hollow" }
  T("a pistol keeps its damage", near(NewRaycastWeaponBase._get_current_damage(pistol, 1), 10))

  -- The limbs: hollow points make every hit a critical hit.
  local function hit(body, weapon)
    local cop = { _char_tweak = { headshot_dmg_mul = 4 }, _health = 100,
      can_be_critical = function(self) return self.critable ~= false end }
    local attack = { attacker_unit = ENV.game.unit, damage = 10,
      weapon_unit = { base = function() return weapon end },
      col_ray = { body = { name = function() return Idstring(body) end } } }
    return cop, attack
  end
  Ammo.SetLoaded(w, { size = "standard", bullet = "hollow" })
  local cop, attack = hit("rag_LeftArm", w)
  local crit, dmg = CopDamage.roll_critical_hit(cop, attack)
  T("hollow point in the arm: a critical hit with the headshot multiplier", crit == true and dmg == 40, tostring(crit) .. " " .. tostring(dmg))
  cop, attack = hit("rag_RightUpLeg", w)
  T("and in the leg", (CopDamage.roll_critical_hit(cop, attack)) == true)
  cop, attack = hit("Spine", w)
  T("the body: the game's own roll", (CopDamage.roll_critical_hit(cop, attack)) == false)
  cop, attack = hit("rag_LeftArm", w)
  cop.critable = false
  T("an enemy that takes no critical hits takes none", (CopDamage.roll_critical_hit(cop, attack)) == false)
  cop, attack = hit("rag_LeftArm", w)
  cop._char_tweak.critical_hits = { damage_mul = 2 }
  local _, d2 = CopDamage.roll_critical_hit(cop, attack)
  T("the enemy's critical multiplier comes first", d2 == 20, d2)
  Ammo.SetLoaded(w, { size = "standard", bullet = "ap" })
  cop, attack = hit("rag_LeftArm", w)
  T("armour piercing in the arm: no forced critical hit", (CopDamage.roll_critical_hit(cop, attack)) == false)
  Ammo.SetLoaded(w, { size = "standard", bullet = "standard" })
  cop, attack = hit("rag_LeftArm", w)
  T("standard bullets: none either", (CopDamage.roll_critical_hit(cop, attack)) == false)
end

------------------------------------------------------------------ mixed loads

T("a load is kept as a string in the save", Ammo.LoadString({ { "ap", 10 }, { "hollow", 20 } }) == "ap:10,hollow:20"
  and #Ammo.ParseLoad("ap:10,hollow:20") == 2 and Ammo.ParseLoad("ap:10,ap:5")[1][2] == 15)
T("an unknown bullet in a save is ignored", #Ammo.ParseLoad("ap:10,laser:5") == 1)

------------------------------------------------------------------ filling

do
  local w, i = fresh("test_ar", 30)
  local k = i.key
  clear_mags(k)
  Ammo.AddMagazineKey(k, 5, i, { "rig" }, { size = "standard", bullet = "hollow" })
  Ammo.AddMagazineKey(k, 0, i, { "rig" }, { size = "compact", bullet = "ap" })
  Ammo.AddLooseKey(k, 10, i, "hollow")
  Ammo.AddLooseKey(k, 50, i, "standard")
  T("the loose rounds are kept by bullet", Ammo.LooseOfKey(k, "hollow") == 10 and Ammo.LooseOfKey(k, "standard") == 50)
  Ammo.FillMagazines(w, 999)
  local hp = find_mag(k, function(m) return m.size == "standard" end)
  local other = find_mag(k, function(m) return m.size == "compact" end)
  T("a magazine takes its own bullets first, then others on top",
    hp and hp.rounds == 30 and Ammo.LoadString(hp.load) == "standard:15,hollow:15", hp and Ammo.LoadString(hp.load))
  T("its top bullets are the ones fired first", hp and hp.bullet == "standard")
  T("an empty magazine takes any bullets", other and other.rounds == 20 and other.bullet == "standard",
    other and (other.rounds .. " " .. tostring(other.bullet)))
  T("the rounds left the right stacks", Ammo.LooseOfKey(k, "hollow") == 0 and Ammo.LooseOfKey(k, "standard") == 15,
    Ammo.LooseOfKey(k, "standard"))

  -- Round by round (holding R): the magazine's own kind first.
  clear_mags(k)
  for _, st in ipairs(Ammo.LooseStacks(k)) do PDTI.RemoveItem(st.container, st.instance_id) end
  Ammo.AddMagazineKey(k, 1, i, { "rig" }, { size = "compact", bullet = "ap" })
  Ammo.AddLooseKey(k, 3, i, "standard")
  Ammo.AddLooseKey(k, 3, i, "ap")
  T("a magazine with room needs a fill", Ammo.NeedsFill(w) == true)
  Ammo.StartJob(w)
  for _ = 1, 10 do Ammo.Tick(1) end
  local ap = find_mag(k, function(m) return m.size == "compact" end)
  T("holding R packs its own kind first, then the others on top",
    ap and ap.rounds == 7 and Ammo.LoadString(ap.load) == "standard:3,ap:4", ap and Ammo.LoadString(ap.load))
  T("and every loose round went in", Ammo.LooseOfKey(k) == 0)

  -- An ammo pickup: standard rounds.
  Ammo.AddLoose(w, 7)
  T("picked-up ammunition is standard rounds", Ammo.LooseOfKey(k, "standard") == 7)
end

---------------------------------------------- a mixed magazine in the gun

do
  local w, i = fresh("test_ar", 30, { _damage = 10 })
  local k = i.key
  clear_mags(k)
  Ammo.AddMagazineKey(k, 30, i, { "pockets" }, { size = "standard", load = "ap:2,hollow:28" })
  local m = Ammo.Magazines(k)[1]
  T("a magazine of two kinds", m and m.rounds == 30 and m.bullet == "ap" and #m.load == 2)
  w.clip = 0
  Ammo.SyncTotal(w)
  NewRaycastWeaponBase.on_reload(w)
  T("it goes in with its load", w.clip == 30 and Ammo.CurrentBullet(w) == "ap")
  local function shoot()
    w.clip = w.clip - 1
    return NewRaycastWeaponBase._get_current_damage(w, 1)
  end
  T("the first shot is armour piercing", near(shoot(), 8.5) and NewRaycastWeaponBase.armor_piercing_chance(w) == 1)
  T("the second too", near(shoot(), 8.5))
  T("then the hollow points", near(shoot(), 13) and NewRaycastWeaponBase.armor_piercing_chance(w) == 0
    and w._can_shoot_through_enemy == false)
  T("the HUD colours the parts of the magazine", (function()
    local segs = Ammo.HudSegments({ rounds = 30, load = { { "ap", 10 }, { "hollow", 20 } } })
    return #segs == 2 and segs[1].bullet == "hollow" and segs[1].rounds == 20 and segs[2].bullet == "ap"
  end)())
  -- Out of the gun: it keeps what is left.
  Ammo.AddMagazineKey(k, 20, i, { "pockets" }, { size = "compact", bullet = "standard" })
  NewRaycastWeaponBase.on_reload(w)
  local back = find_mag(k, function(mm) return mm.rounds == 27 end)
  T("the magazine taken out keeps its 27 hollow points", back and Ammo.LoadString(back.load) == "hollow:27",
    back and Ammo.LoadString(back.load))
end

------------------------------------------------------------------ akimbo SMG

do
  local w, i = fresh("test_akimbo_smg", 40, { _damage = 10 })
  local k = i.key
  T("akimbo SMG: two standard magazines of 20, clip maximum 40", w:get_ammo_max_per_clip() == 40)
  clear_mags(k)
  Ammo.AddMagazineKey(k, 13, i, { "pockets" }, { size = "compact", bullet = "hollow" })
  Ammo.AddMagazineKey(k, 50, i, { "rig" }, { size = "drum", bullet = "ap" })
  w.clip = 10
  w._pdti_pair = { 5, 5 }
  Ammo.SyncTotal(w)
  NewRaycastWeaponBase.on_reload(w)
  local specs = Ammo.PairSpecs(w)
  local bullets = { specs[1].bullet, specs[2].bullet }
  table.sort(bullets)
  T("each gun has its own magazine's bullets", bullets[1] == "ap" and bullets[2] == "hollow", table.concat(bullets, ","))
  T("the clip maximum is both magazines (13 + 50)", w:get_ammo_max_per_clip() == 63 and w.clip == 63, w.clip)
  local pair = Ammo.AkimboPair(w)
  T("the pair keeps each magazine's rounds", (pair[1] == 13 and pair[2] == 50) or (pair[1] == 50 and pair[2] == 13),
    pair[1] .. "," .. pair[2])
  T("the next shot is from the fuller magazine: armour piercing", Ammo.CurrentBullet(w) == "ap")
  -- Shots come from the fuller gun: 37 armour-piercing rounds, then the
  -- guns take turns.
  local dmg
  for _ = 1, 37 do
    w.clip = w.clip - 1
    dmg = NewRaycastWeaponBase._get_current_damage(w, 1)
  end
  T("the armour-piercing gun fires while it is fuller", near(dmg, 8.5) and w._can_shoot_through_enemy == true, dmg)
  w.clip = w.clip - 1
  dmg = NewRaycastWeaponBase._get_current_damage(w, 1)
  local p2 = Ammo.AkimboPair(w)
  T("then a shot from the hollow-point gun, as the shot is fired",
    near(dmg, 13) and w._can_shoot_through_enemy == false and w._can_shoot_through_shield == false,
    dmg .. " " .. p2[1] .. "," .. p2[2])
  local olds = 0
  for _, m in ipairs(Ammo.AllMagazines(k)) do
    if m.rounds == 5 and m.size == "standard" and m.capacity == 20 then olds = olds + 1 end
  end
  T("the two old magazines went back with their 5 rounds each", olds == 2, olds)
end

--------------------------------------------------------- the weapon's slot

do
  local w, i = fresh("test_ar", 30)
  local k = i.key
  clear_mags(k)
  Ammo.AddMagazineKey(k, 30, i, { "pockets" }, { size = "standard", bullet = "standard" })
  local ok = Ammo.AddMagazineKey(k, 20, i, { "gun_primary" }, { size = "compact", bullet = "ap" })
  T("a magazine of the weapon goes into its slot", ok == true)
  T("only one", Ammo.AddMagazineKey(k, 20, i, { "gun_primary" }, { size = "compact", bullet = "ap" }) == false)
  T("loose rounds do not", PDTI.AddItemAuto("gun_primary", Ammo.LOOSE_ITEM, 10,
    Ammo.LooseData(k, i, "ap"), true) == false)
  T("the other weapon's slot takes none of it",
    Ammo.AddMagazineKey(k, 20, i, { "gun_secondary" }, { size = "compact", bullet = "ap" }) == false)
  local n = Ammo.NextMagazine(w)
  T("the magazine in the weapon's slot is the next one loaded", n and n.container == "gun_primary" and n.bullet == "ap")
  w.clip = 10
  Ammo.SyncTotal(w)
  NewRaycastWeaponBase.on_reload(w)
  T("the reload takes it", w.clip == 20 and Ammo.CurrentBullet(w) == "ap" and #PDTI.GetContainerInfo("gun_primary").items == 0)
  T("its magazine counts in the weight", (function()
    local before = PDTI.GetTotalWeight()
    Ammo.AddMagazineKey(k, 20, i, { "gun_primary" }, { size = "compact", bullet = "ap" })
    return PDTI.GetTotalWeight() > before
  end)())
  local gi = PDTI.GetContainerInfo("gun_primary").items[1]
  T("Ctrl+click takes it out to hand", PDTI.UIQuickTransfer("gun_primary", gi.instance_id) == true
    and #PDTI.GetContainerInfo("gun_primary").items == 0)
end

-------------------------------------------------- the plan: the user's example

local menu_weapons = { primary = { weapon_id = "test_ar", blueprint = { "wpn_no_part" } },
  secondary = { weapon_id = "test_pistol", blueprint = { "wpn_no_part" } } }
_G.managers.blackmarket = {
  equipped_primary = function() return menu_weapons.primary end,
  equipped_secondary = function() return menu_weapons.secondary end
}
tweak_data.weapon.test_pistol.CLIP_AMMO_MAX = 15

local function in_menu()
  PDTI.SetSessionOnly(false)
  ENV.game.unit = nil
end
local function start_heist()
  PDTI.LoadProfile()
  PDTI.SetSessionOnly(true)
  Ammo.OnHeistStart()
end
local function gun_items(slot) return PDTI.GetContainerInfo("gun_" .. slot).items end

PDTI.Reset()
Ammo.Reset()
in_menu()
T("the primary is typed in the menu", Plan.Info("primary").typed == true and Plan.Info("secondary").typed == nil)
Plan.Refresh()
T("a new plan puts a magazine in each weapon's slot", #gun_items("primary") == 1 and #gun_items("secondary") == 1)

-- The drum of hollow points: chosen and dragged into the weapon's slot.
PDTI.RemoveItem("gun_primary", gun_items("primary")[1].instance_id)
for _, e in ipairs(Plan.Magazines("primary")) do PDTI.RemoveItem(e.container, e.item.instance_id) end
T("the size of the next magazine", Plan.SetSpec("primary", "pick_size", "drum"))
T("an unknown size is refused", Plan.SetSpec("primary", "pick_size", "huge") == false)
Plan.SetPickCount("primary", "standard", 0)
for _ = 1, 20 do Plan.ChangePickCount("primary", "hollow", true) end
T("hollow points up to full: 75", Plan.PickCount("primary", "hollow") == 75 and Plan.PickSpec("primary").rounds == 75,
  Plan.PickCount("primary", "hollow"))
T("no more than full", Plan.ChangePickCount("primary", "ap", true) == false)
Plan.Add("mag:primary")
local drum_item = Plan.Magazines("primary")[1]
T("a drum of 75 hollow points", drum_item and drum_item.item.data.capacity == 75 and drum_item.item.data.rounds == 75
  and drum_item.item.data.bullet == "hollow")
T("dragged into the weapon's slot", PDTI.RequestMove(drum_item.container, drum_item.item.instance_id, "gun_primary", 0, 0, false) == true)

-- The rig: compact magazines, 10 armour piercing on top of 10 hollow points.
Plan.SetSpec("primary", "pick_size", "compact")
Plan.SetPickCount("primary", "hollow", 0)
Plan.SetPickCount("primary", "ap", 10)
Plan.SetPickCount("primary", "hollow", 10)
local pick = Plan.PickSpec("primary")
T("the chosen load: 10 AP on top, 10 HP below", Ammo.LoadString(pick.load) == "ap:10,hollow:10" and pick.rounds == 20,
  Ammo.LoadString(pick.load))
Plan.FlipPick("primary")
T("Flip turns it over", Ammo.LoadString(Plan.PickSpec("primary").load) == "hollow:10,ap:10")
Plan.FlipPick("primary")
for _ = 1, 4 do Plan.Add("mag:primary") end
local pm = Plan.Magazines("primary")
T("four compact magazines of that load", #pm == 4 and pm[1].item.data.size == "compact"
  and pm[1].item.data.load == "ap:10,hollow:10" and pm[1].item.data.rounds == 20, #pm)
T("the grid shows the top bullets and that there are more", (function()
  return Ammo.LoadTag(Ammo.LoadOf(pm[1].item.data)) == "AP+"
end)())
-- Fewer rounds than the magazine takes.
Plan.SetPickCount("primary", "hollow", 0)
Plan.Add("mag:primary")
local part = nil
for _, e in ipairs(Plan.Magazines("primary")) do if e.item.data.rounds == 10 then part = e end end
T("a magazine can be packed with fewer rounds", part ~= nil and part.item.data.load == "ap:10")
Plan.Remove("mag:primary")
T("removing takes the chosen kind first", #Plan.Magazines("primary") == 4)
Plan.SetPickCount("primary", "hollow", 10)
Plan.Add("loose:primary:hollow")
T("loose hollow points come by the magazine", Plan.Count("loose:primary:hollow") == 30 and Plan.Count("loose:primary:ap") == 0)
Plan.Add("loose:primary:ap")
Plan.Remove("loose:primary:ap")
T("and go by bullet", Plan.Count("loose:primary:ap") == 0 and Plan.Count("loose:primary:hollow") == 30)
Plan.Refresh()
T("the menu's refresh keeps the loads", #Plan.Magazines("primary") == 4
  and Plan.Magazines("primary")[1].item.data.load == "ap:10,hollow:10" and #gun_items("primary") == 1)
PDTI.LoadProfile()
T("the plan is saved with the profile", #gun_items("primary") == 1 and gun_items("primary")[1].data.size == "drum"
  and PDTI.GetPlanSlot("primary").pick_load == "ap:10,hollow:10")

local function heist_rifle()
  local unit = ENV.make_unit()
  local rifle = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _selection = 2, _damage = 10 })
  unit:set_weapon(rifle)
  rifle.clip = 30
  Ammo.EnsureSupply(rifle)
  Ammo.SyncTotal(rifle)
  return rifle
end

start_heist()
local rifle = heist_rifle()
local rk = Ammo.Identify(rifle).key
T("the heist starts with the drum of hollow points in the gun: 75 rounds",
  rifle.clip == 75 and rifle:get_ammo_max_per_clip() == 75 and Ammo.CurrentBullet(rifle) == "hollow", rifle.clip)
T("the weapon's slot is empty now: the magazine is in the gun", #gun_items("primary") == 0)
local rm = Ammo.Magazines(rk)
T("and four compact magazines, 10 AP on 10 HP", #rm == 4 and rm[1].bullet == "ap" and rm[1].capacity == 20
  and rm[1].rounds == 20 and Ammo.LoadString(rm[1].load) == "ap:10,hollow:10", #rm)
T("the hollow points are the weapon's", Ammo.LooseOfKey(rk, "hollow") == 30)
T("the total counts all of it", rifle.total == 75 + 80 + 30, rifle.total)
T("the HUD shows the loaded magazine", (function()
  local rows = Ammo.HudRows()
  return rows and rows.spec == "D/HP" and rows.capacity == 75
end)())
rifle.clip = 3
Ammo.SyncTotal(rifle)
NewRaycastWeaponBase.on_reload(rifle)
T("the first reload takes a compact magazine, armour piercing on top",
  rifle.clip == 20 and Ammo.CurrentBullet(rifle) == "ap" and rifle:get_ammo_max_per_clip() == 20)
local drum = find_mag(rk, function(m) return m.size == "drum" end)
T("the drum goes into the inventory with its 3 hollow points", drum and drum.rounds == 3 and drum.bullet == "hollow")
T("no magazine is lost", #Ammo.AllMagazines(rk) == 4)

-- The next heist: everything as chosen.
in_menu()
PDTI.LoadProfile()
start_heist()
rifle = heist_rifle()
rk = Ammo.Identify(rifle).key
T("the next heist: the drum of hollow points is back in the gun", rifle.clip == 75 and Ammo.CurrentBullet(rifle) == "hollow")
T("and the four magazines are full", #Ammo.Magazines(rk) == 4 and Ammo.MagazineRounds(rk) == 80)

--------------------------------------------------------------------- the UI

PDTI.LoadProfile()
in_menu()
PDTI.SetEquipment("backpack", "large_backpack")
PDTI.SetEquipment("rig", "general_rig")
_G.PDTI.Loadout.Get = function()
  return { { slot = "primary", name = "Test AR", weight = 3.4 }, { slot = "secondary", name = "Test pistol", weight = 1.1 },
    { slot = "throwable", name = "Frag", amount = 3, weight = 1.2 }, { slot = "armour", name = "Suit", weight = 0 } }
end
T("the inventory opens in the menu", PDTI.ToggleUI() == true)
local function windows() return ENV.menus[#ENV.menus].children end
local left, right = windows()[1], windows()[2]
T("each weapon is a box with its weight", left:find("weapon_box_primary") ~= nil
  and tostring(left:find("weapon_box_primary").params.text):find("3.4 kg") ~= nil and left:find("weapon_box_secondary") ~= nil)
T("next to its magazine slot", left:find("cell_gun_primary_0_0") ~= nil and left:find("cell_gun_secondary_1_0") ~= nil)
T("the throwable and the armour stay lines", left:find("loadout_line_3") ~= nil and left:find("loadout_line_1") == nil)
T("the drum in the slot shows its bullets", tostring(left:find("cell_gun_primary_0_0").params.text) == "75 HP")
T("the size buttons for the magazines you add", right:find("bring_pick_size_primary_compact") ~= nil
  and right:find("bring_gun_size_primary_drum") == nil)
T("the rounds of each bullet", right:find("bring_pick_plus_primary_hollow") ~= nil
  and right:find("bring_pick_count_primary_ap").params.text == "AP 10")
T("loose rounds by bullet", right:find("bring_plus_loose_primary_hollow") ~= nil and right:find("bring_plus_loose_primary") == nil)
T("the pistol keeps its plain rows", right:find("bring_plus_loose_secondary") ~= nil and right:find("bring_pick_size_secondary_drum") == nil)
right:find("bring_pick_size_primary_extended"):click()
T("a click chooses the size", PDTI.GetPlanSlot("primary").pick_size == "extended")
right = windows()[2]
right:find("bring_pick_plus_primary_standard"):click()
T("+ adds standard rounds to the load", Plan.PickCount("primary", "standard") == 5)
right = windows()[2]
right:find("bring_pick_flip_primary"):click()
T("Flip in the menu", Ammo.LoadTop(Plan.PickSpec("primary").load) == "standard")
right = windows()[2]
right:find("bring_plus_mag_primary"):click()
local last = nil
for _, e in ipairs(Plan.Magazines("primary")) do if e.item.data.size == "extended" then last = e end end
T("+ adds a magazine of the chosen kind", last ~= nil and last.item.data.load == "standard:5,hollow:10,ap:10",
  last and last.item.data.load)
left, right = windows()[1], windows()[2]
T("the windows stay within the screen", left.ph <= 620 and right.ph <= 620 and left.pw + right.pw <= 640,
  left.pw .. "x" .. left.ph .. " + " .. right.pw .. "x" .. right.ph)
local function overlaps(win)
  local list, bad = {}, {}
  for _, c in ipairs(win.children) do
    local pos = c.params.position
    if type(pos) == "table" then list[#list + 1] = { name = c.params.name, x = pos[1], y = pos[2], w = c.pw, h = c.ph } end
  end
  for a = 1, #list do
    local A = list[a]
    if A.x + A.w > win.pw + 0.5 then bad[#bad + 1] = "outside: " .. A.name end
    for b = a + 1, #list do
      local B = list[b]
      if A.x < B.x + B.w and B.x < A.x + A.w and A.y < B.y + B.h and B.y < A.y + A.h then
        bad[#bad + 1] = A.name .. "/" .. B.name
      end
    end
  end
  return bad
end
local bad = overlaps(right)
T("nothing overlaps in the bring list", #bad == 0, table.concat(bad, "; "):sub(1, 300))
bad = overlaps(left)
T("nothing overlaps in the loadout", #bad == 0, table.concat(bad, "; "):sub(1, 300))
-- The colours: standard keeps the weapon's, hollow points red, AP green.
local cell = left:find("cell_gun_primary_0_0")
local red = PDTI.UI_BULLET_COLORS.hollow
T("hollow points are red", cell and type(cell.params.background_color) == "table"
  and math.abs((cell.params.background_color[1] or 0) - red[1]) < 0.01, cell and tostring(cell.params.background_color[1]))
PDTI.SetUIOpen(false)

-- Changing to a weapon without sizes: the magazines become plain ones.
in_menu()
PDTI.LoadProfile()
menu_weapons.primary = { weapon_id = "test_rifle", blueprint = { "wpn_no_part" } }
tweak_data.weapon.test_rifle.CLIP_AMMO_MAX = 30
Plan.Refresh()
local plain = Plan.Magazines("primary")[1]
T("another weapon type: the magazines lose their size and bullets",
  plain and plain.item.data.size == nil and plain.item.data.bullet == nil and plain.item.data.load == nil
  and plain.item.data.capacity == 30)
PDTI.LoadProfile()
menu_weapons.primary = { weapon_id = "test_ar", blueprint = { "wpn_no_part" } }


-- A plan of 0.16.0 (no magazine in the weapon's slot): the older "Gun"
-- choice goes into the slot once; emptied later, it stays empty.
in_menu()
PDTI.LoadProfile()
for _, slot in ipairs({ "primary", "secondary" }) do
  for _, e in ipairs(Plan.GunMagazines(slot)) do PDTI.RemoveItem(e.container, e.item.instance_id) end
  PDTI.SetPlanSlot(slot, "gun_filled", "0")
end
PDTI.SetPlanSlot("primary", "gun_size", "extended")
PDTI.SetPlanSlot("primary", "gun_bullet", "ap")
Plan.Refresh()
local g = gun_items("primary")[1]
T("an older plan: the gun's magazine appears in the weapon's slot", g and g.data.size == "extended"
  and g.data.bullet == "ap" and g.data.rounds == 45 and #gun_items("secondary") == 1)
PDTI.RemoveItem("gun_primary", g.instance_id)
Plan.Refresh()
T("only once", #gun_items("primary") == 0)

-------------------------------------------------------- the dev spawner

PDTI.SetSessionOnly(true)
start_heist()
rifle = heist_rifle()
rk = Ammo.Identify(rifle).key
local before = 0
for _, m in ipairs(Ammo.AllMagazines(rk)) do if m.bullet == "hollow" and m.size == "standard" then before = before + 1 end end
local inv = ENV.game.unit:inventory()
inv.unit_by_selection = function(_, index)
  if index == 2 then return { base = function() return rifle end } end
  return nil
end
T("the spawner makes a hollow-point magazine", Ammo.DevSpawnMagazine("primary", "hollow") == true)
local after_n = 0
for _, m in ipairs(Ammo.AllMagazines(rk)) do if m.bullet == "hollow" and m.size == "standard" then after_n = after_n + 1 end end
T("a full one", after_n == before + 1)
local hp_before = Ammo.LooseOfKey(rk, "hollow")
T("and loose armour-piercing rounds", Ammo.DevSpawnLoose("primary", "ap") == true and Ammo.LooseOfKey(rk, "ap") >= 30
  and Ammo.LooseOfKey(rk, "hollow") == hp_before)
PDTI.SetEquipment("backpack", "large_backpack")
T("the inventory opens in the heist", PDTI.ToggleUI() == true)
right = windows()[2]
right:find("spawn_bullet_hollow"):click()
right = windows()[2]
T("the spawner's bullet buttons choose", right:find("spawn_mag_primary").params.text == "PRI magazine HP",
  right:find("spawn_mag_primary").params.text)
local c0 = 0
for _, m in ipairs(Ammo.AllMagazines(rk)) do if m.bullet == "hollow" then c0 = c0 + 1 end end
right:find("spawn_mag_primary"):click()
local c1 = 0
for _, m in ipairs(Ammo.AllMagazines(rk)) do if m.bullet == "hollow" then c1 = c1 + 1 end end
T("and the spawn button gives that kind", c1 == c0 + 1)
right = windows()[2]
T("the heist windows stay within the screen", windows()[1].ph <= 620 and right.ph <= 620,
  windows()[1].ph .. " / " .. right.ph)
bad = overlaps(right)
T("nothing overlaps in the spawner", #bad == 0, table.concat(bad, "; "):sub(1, 300))
PDTI.SetUIOpen(false)

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
