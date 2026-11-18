-- 0.20.0: shotguns take the game's own ammunition types, shell by shell.
-- Rifle bullets and shotgun shells never mix; shotgun magazines and tubes
-- hold mixed loads; each shot gets the game's own values for its shell.
--   luajit tests/shell_tests.lua
local script = arg and arg[0] or "tests/shell_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_shells") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
dofile(ROOT .. "lua/shells.lua")
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end

-- The game's ammo parts (custom_stats as the game has them, simplified) and
-- a shotgun whose part list has every shell but the tombstone slug.
local parts = tweak_data.weapon.factory.parts
parts.wpn_fps_upg_a_custom = { type = "ammo", custom_stats = { rays = 6, damage_near_mul = 1.2 }, stats = { damage = 3 } }
parts.wpn_fps_upg_a_custom_free = { type = "ammo", custom_stats = { rays = 6, damage_near_mul = 1.2 }, stats = { damage = 3 } }
parts.wpn_fps_upg_a_piercing = { type = "ammo", custom_stats = { armor_piercing_add = 1 }, stats = { damage = -2 } }
parts.wpn_fps_upg_a_slug = { type = "ammo", custom_stats = { rays = 1, armor_piercing_add = 1, can_shoot_through_shield = true }, stats = { damage = 4 } }
parts.wpn_fps_upg_a_rip = { type = "ammo", custom_stats = { bullet_class = "PoisonBulletBase" } }
parts.wpn_fps_upg_a_dragons_breath = { type = "ammo", custom_stats = { rays = 12, bullet_class = "FlameBulletBase",
  fire_dot_data = { dot_damage = 1 } }, stats = { damage = -5 } }
parts.wpn_fps_upg_a_explosive = { type = "ammo", custom_stats = { rays = 1, bullet_class = "InstantExplosiveBulletBase" },
  stats = { total_ammo_mod = -5 } }
parts.wpn_fps_shot_test_barrel = { type = "barrel", stats = { damage = 1 } }
tweak_data.weapon.factory.wpn_fps_shot_test = { uses = { "wpn_fps_shot_test_barrel", "wpn_fps_upg_a_custom",
  "wpn_fps_upg_a_piercing", "wpn_fps_upg_a_slug", "wpn_fps_upg_a_dragons_breath", "wpn_fps_upg_a_explosive" } }
tweak_data.weapon.test_saiga = { AMMO_MAX = 70, CLIP_AMMO_MAX = 7, categories = { "shotgun" } }

-- Like the game's NewRaycastWeaponBase + ShotgunBase:_update_stats_values:
-- the blueprint's ammo part sets the ammo data, rays, bullet class, damage.
local stats_calls = 0
local function update_stats(self, disallow_replenish)
  stats_calls = stats_calls + 1
  local ammo = {}
  local damage = 10
  for _, p in ipairs(self._blueprint) do
    local part = parts[p]
    if part and part.type == "ammo" then
      for k, v in pairs(part.custom_stats or {}) do ammo[k] = v end
    end
    if part and part.stats and part.stats.damage then damage = damage + part.stats.damage end
  end
  self._ammo_data = ammo
  self._rays = ammo.rays or 9
  self._bullet_class = ammo.bullet_class or "InstantBulletBase"
  self._armor_piercing_chance = math.min(1, ammo.armor_piercing_add or 0)
  self._can_shoot_through_shield = ammo.can_shoot_through_shield or false
  self._damage_near = 1000 * (ammo.damage_near_mul or 1)
  self._current_stats = { damage = damage }
  self._extra_ammo = 0
  -- the ammunition count is the game's (never touched by the shells)
  self._total_ammo_mod = (parts.wpn_fps_upg_a_explosive and self._blueprint[#self._blueprint] == "wpn_fps_upg_a_explosive") and -5 or 0
  if not disallow_replenish then self._replenished = (self._replenished or 0) + 1 end
end
NewRaycastWeaponBase._get_current_damage = function(self, dmg_mul)
  return (self._current_stats and self._current_stats.damage or 10) * (dmg_mul or 1)
end
NewRaycastWeaponBase.armor_piercing_chance = function(self) return self._armor_piercing_chance or 0 end
_G.CopDamage = { roll_critical_hit = function(_, attack_data) return false, attack_data.damage end }
dofile(ROOT .. "lua/ammo_hooks.lua")
_G.Color = _G.Color or setmetatable({}, { __call = function(_, ...) return { ... } end })
dofile(ROOT .. "lua/ammo_hud.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end

local Ammo, Plan, Shells = PDTI.Ammo, PDTI.Plan, PDTI.Shells
T("the hooks are in place", Ammo.InstallHooks() == true)
T("the shells module is loaded", type(Shells) == "table" and type(Shells.Apply) == "function")

local function shotgun(name, capacity, extra)
  extra = extra or {}
  extra._factory_id = extra._factory_id or "wpn_fps_shot_test"
  extra._update_stats_values = update_stats
  local w = ENV.make_weapon(name, { "wpn_fps_shot_test_barrel" }, capacity, extra)
  update_stats(w, true)
  return w
end

local function fresh(w)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  w._setup = { user_unit = unit }
  unit:set_weapon(w)
  Ammo.EnsureSupply(w)
  return w, Ammo.Identify(w)
end

local function shoot(w)
  w.clip = w.clip - 1
  return NewRaycastWeaponBase._get_current_damage(w, 1)
end

----------------------------------------------------------- the families

do
  local ar = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  local pump = shotgun("test_pump", 6, { _use_shotgun_reload = true })
  local saiga = shotgun("test_saiga", 7, { _blueprint = { "wpn_mag_test" } })
  local ia, ip, is = Ammo.Identify(ar), Ammo.Identify(pump), Ammo.Identify(saiga)
  T("an assault rifle is of the rifle family, with sizes", ia.family == "rifle" and ia.sized == true)
  T("a pump shotgun is of the shell family, loaded shell by shell",
    ip.family == "shell" and ip.typed == true and ip.loose_fed == true and not ip.sized)
  T("a box-magazine shotgun is of the shell family without sizes",
    is.family == "shell" and is.typed == true and not is.loose_fed and not is.sized)
  T("the box-magazine shotgun keeps the game's magazine size", is.capacity == 30, is.capacity)
  local list = table.concat(Ammo.BulletsFor(ip), ",")
  T("a shotgun takes the shells its part list has (no tombstone here)",
    list == "standard,custom,flechette,slug,dragon,he", list)
  T("a rifle takes the rifle bullets", table.concat(Ammo.BulletsFor(ia), ",") == "standard,hollow,ap")
  T("a shotgun cannot take armour-piercing rifle rounds", not Ammo.BulletAllowed(ip, "ap") and not Ammo.BulletAllowed(ip, "hollow"))
  T("a rifle cannot take slugs", not Ammo.BulletAllowed(ia, "slug") and not Ammo.BulletAllowed(ia, "dragon"))
  T("a load made for a rifle becomes buckshot in a shotgun",
    Ammo.LoadString(Ammo.FilterLoad(ip, Ammo.ParseLoad("ap:2,slug:3"))) == "standard:2,slug:3")
  T("standard shells are called buckshot", Ammo.BulletName("standard", "shell") == "Buckshot"
    and Ammo.BulletShort("standard", "rifle") == "STD")
  T("a missing ammo part is not offered", (function()
    local saved = parts.wpn_fps_upg_a_piercing
    parts.wpn_fps_upg_a_piercing = nil
    Ammo.ResetShellCache()
    local l = table.concat(Ammo.ShellsAccepted("wpn_fps_shot_test"), ",")
    parts.wpn_fps_upg_a_piercing = saved
    Ammo.ResetShellCache()
    return not l:find("flechette")
  end)())
end

----------------------------------------------------------- the profiles

do
  local w = fresh(shotgun("test_saiga", 7, { _blueprint = { "wpn_fps_shot_test_barrel", "wpn_fps_upg_a_slug" } }))
  local real = w._blueprint
  local profiles = Shells.Capture(w)
  T("the profiles are captured", profiles ~= nil and profiles.profiles.slug ~= nil)
  local p = profiles.profiles
  T("buckshot: the gun without its ammo mod", p.standard._rays == 9 and p.standard._current_stats.damage == 11)
  T("slug: the game's own values for the slug", p.slug._rays == 1 and p.slug._armor_piercing_chance == 1
    and p.slug._can_shoot_through_shield == true and p.slug._current_stats.damage == 15)
  T("dragon's breath: its bullet class and fire data", p.dragon._bullet_class == "FlameBulletBase"
    and p.dragon._ammo_data.fire_dot_data ~= nil and p.dragon._rays == 12)
  T("HE: the explosive bullet class", p.he._bullet_class == "InstantExplosiveBulletBase")
  T("the real blueprint is back", w._blueprint == real and #real == 2)
  T("capturing never refills the gun", w._replenished == nil)
  T("the ammunition count is never part of a profile", profiles.keys._total_ammo_mod == nil and profiles.keys._extra_ammo == nil)

  local mod_before = w._total_ammo_mod
  Shells.Apply(w, "dragon")
  T("applying a shell sets its values", w._rays == 12 and w._bullet_class == "FlameBulletBase" and Shells.Current(w) == "dragon")
  T("applying never changes the ammunition count", w._total_ammo_mod == mod_before)
  Shells.Apply(w, "standard")
  T("back to buckshot", w._rays == 9 and w._bullet_class == "InstantBulletBase" and w._ammo_data.fire_dot_data == nil)
  w._current_stats.damage = 999
  Shells.Apply(w, "standard")
  T("a profile's tables are copies (the game changing one never changes the profile)",
    w._current_stats.damage == 11)
  local calls = stats_calls
  Shells.Apply(w, "slug")
  T("applying again does not capture again", stats_calls == calls)
  update_stats(w, true)
  Shells.Apply(w, "slug")
  T("the game working the gun out again makes a new capture", stats_calls > calls + 1 and w._rays == 1)
  T("a shell the gun does not take is buckshot", Shells.Apply(w, "tombstone") and Shells.Current(w) == "standard")
  local ar = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30, { _update_stats_values = update_stats })
  T("a rifle has no shell profiles", not Shells.Apply(ar, "slug"))
end

---------------------------------------------- a box magazine of mixed shells

do
  local w, info = fresh(shotgun("test_saiga", 8, { _blueprint = { "wpn_fps_shot_test_barrel", "wpn_mag_test" } }))
  Ammo.SetLoaded(w, { bullet = "standard", load = "slug:2,standard:6" })
  w.max_clip = 8
  w.clip = 8
  Ammo.ApplyLoaded(w)
  T("the top shell is set before the first shot", Shells.Current(w) == "slug" and w._rays == 1)
  local d1 = shoot(w)
  T("the first shot is a slug, with the slug's damage", Shells.Current(w) == "slug" and d1 == 15, d1)
  shoot(w)
  T("the second shot is a slug", Shells.Current(w) == "slug")
  local d3 = shoot(w)
  T("then buckshot", Shells.Current(w) == "standard" and w._rays == 9 and d3 == 11, d3)
  T("the magazine's load follows the shots", Ammo.LoadString(Ammo.LoadedSpec(w).load) == "standard:5")

  -- A magazine item of the shotgun keeps its shells.
  local ok = Ammo.AddMagazineKey(info.key, 7, info, nil, { bullet = "standard", load = "he:1,dragon:2" })
  local mag = nil
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do
    if m.load and Ammo.LoadTop(m.load) == "he" then mag = m end
  end
  T("a shotgun magazine item knows its shells", ok and mag and Ammo.LoadString(mag.load) == "he:1,dragon:2,standard:4",
    mag and Ammo.LoadString(mag.load or {}))
  T("a shotgun magazine has no size", mag and mag.size == nil)
  T("a rifle bullet never goes into a shotgun magazine", (function()
    Ammo.AddMagazineKey(info.key, 2, info, nil, { bullet = "ap", load = "ap:2" })
    for _, m in ipairs(Ammo.AllMagazines(info.key)) do
      for _, part in ipairs(m.load or {}) do if part[1] == "ap" then return false end end
    end
    return true
  end)())
  T("a shotgun magazine is priced by its shells",
    Ammo.MagazinePrice({ rounds = 3, capacity = 7, bullet = "slug", load = "slug:2,he:1" }) == 1000 + 2 * 150 + 250)

  -- Dragging rifle rounds onto a shotgun magazine: different supplies.
  local ar = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  local rinfo = Ammo.Identify(ar)
  local loose = { item_id = Ammo.LOOSE_ITEM, amount = 10, data = Ammo.LooseData(rinfo.key, rinfo, "ap") }
  local shotmag = { item_id = Ammo.MAGAZINE_ITEM, data = { queue_key = info.key, rounds = 0, capacity = 7 } }
  T("rifle rounds do not fit a shotgun magazine", not Ammo.CanLoadInto(loose, shotmag))
  T("loose shells of a rifle bullet are refused", (function()
    local d = Ammo.LooseData(info.key, info, "hollow")
    return d.bullet == "standard" and d.family == "shell"
  end)())

  -- Loading loose slugs onto the top of a shotgun magazine.
  Ammo.AddLooseKey(info.key, 3, info, "slug")
  local stack = Ammo.LooseStacks(info.key, "slug")[1]
  local target = nil
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do if m.rounds < m.capacity then target = m end end
  local loaded = target and Ammo.LoadAllInto(stack.instance_id, target.instance_id)
  local after = nil
  for _, m in ipairs(Ammo.AllMagazines(info.key)) do if m.instance_id == target.instance_id then after = m end end
  T("loose slugs go on top of a shotgun magazine", loaded and after and Ammo.LoadTop(after.load) == "slug",
    after and Ammo.LoadString(after.load or {}))
end

------------------------------------------------- a tube, shell by shell

do
  local w, info = fresh(shotgun("test_pump", 6, { _use_shotgun_reload = true }))
  w.clip = 0
  for _, s in ipairs(Ammo.LooseStacks(info.key)) do PDTI.RemoveItem(s.container, s.instance_id) end
  Ammo.AddLooseKey(info.key, 4, info, "standard")
  Ammo.AddLooseKey(info.key, 2, info, "slug")
  T("the wheel offers the shells you carry", table.concat(Ammo.ShellChoices(w), ",") == "standard,slug")
  T("without a choice the first kind loads", Ammo.NextShell(w) == "standard")
  Ammo.LoadShells(w, 0, 4)
  T("four buckshot shells went in", w.clip == 4 and Ammo.LooseOfKey(info.key, "standard") == 0)
  T("the wheel goes round to the slugs", Ammo.CycleShell(w, 1) == "slug" and Ammo.NextShell(w) == "slug")
  Ammo.LoadShells(w, 4, 1)
  T("the slug went in on top", w.clip == 5 and Ammo.LoadString(Ammo.LoadedSpec(w).load) == "slug:1,standard:4",
    Ammo.LoadString(Ammo.LoadedSpec(w).load))
  shoot(w)
  T("the last shell loaded is fired first", Shells.Current(w) == "slug" and w._rays == 1)
  shoot(w)
  T("then the buckshot under it", Shells.Current(w) == "standard" and w._rays == 9)

  -- The chosen kind runs out: the reload goes on with the next kind.
  Ammo.selection[info.key] = "slug"
  Ammo.AddLooseKey(info.key, 2, info, "dragon")
  local before = w.clip
  local n, used = Ammo.LoadShells(w, before, 2)
  T("the last slug, then the next kind", n == 2 and used[1][1] == "slug" and used[2][1] == "dragon",
    used[1] and used[1][1])
  T("the tube's top is the dragon's breath", Ammo.LoadTop(Ammo.LoadedSpec(w).load) == "dragon")
  T("no shells: nothing loads", (function()
    for _, s in ipairs(Ammo.LooseStacks(info.key)) do PDTI.RemoveItem(s.container, s.instance_id) end
    local c = w.clip
    local k = Ammo.LoadShells(w, c, 1)
    return k == 0 and w.clip == c
  end)())

  -- The game's reload (one shell per call) takes the chosen kind.
  w.clip = 0
  Ammo.SetLoaded(w, { bullet = "standard" })
  Ammo.AddLooseKey(info.key, 3, info, "standard")
  Ammo.AddLooseKey(info.key, 1, info, "he")
  Ammo.selection[info.key] = "he"
  Ammo.SyncTotal(w)
  NewRaycastWeaponBase.on_reload(w)
  T("a reload of the game takes the chosen shells first",
    Ammo.LoadTop(Ammo.LoadedSpec(w).load) == "standard" and Ammo.LooseOfKey(info.key, "he") == 0 and w.clip == 4,
    Ammo.LoadString(Ammo.LoadedSpec(w).load) .. " clip " .. w.clip)
  T("the HUD shows the tube's shells", (function()
    local rows = Ammo.HudRows and Ammo.HudRows() or nil
    return rows == nil or rows.installed.load ~= nil
  end)())
end

------------------------------------------------------------- the menu

do
  local menu_weapons = { primary = { weapon_id = "test_saiga", blueprint = { "wpn_mag_test" } },
    secondary = { weapon_id = "test_pump", blueprint = { "wpn_no_part" } } }
  _G.managers.blackmarket = {
    equipped_primary = function() return menu_weapons.primary end,
    equipped_secondary = function() return menu_weapons.secondary end
  }
  _G.managers.weapon_factory = { get_factory_id_by_weapon_id = function() return "wpn_fps_shot_test" end }
  tweak_data.weapon.test_pump.CLIP_AMMO_MAX = 6
  tweak_data.weapon.test_pump.use_shotgun_reload = true
  PDTI.Reset()
  Ammo.Reset()
  PDTI.SetSessionOnly(false)
  ENV.game.unit = nil
  local pi, si = Plan.Info("primary"), Plan.Info("secondary")
  T("the menu knows the shotguns' shells", pi.family == "shell" and si.family == "shell" and si.loose_fed == true)
  T("the menu refuses rifle rounds for a shotgun", select(2, Plan.SetPickCount("primary", "ap", 3)) ==
    "these rounds do not fit this weapon")
  Plan.ClearPick("primary", "standard")
  T("the menu takes slugs for the shotgun magazine", Plan.SetPickCount("primary", "slug", 3) == true)
  local pick = Plan.PickSpec("primary")
  T("the +Mag has no size and the game's capacity", pick.size == nil and pick.capacity == pi.capacity and Plan.PickCount("primary", "slug") == 3,
    tostring(pick.size) .. " " .. pick.capacity)
  local rows = Plan.Rows()
  local kinds = {}
  for _, r in ipairs(rows) do kinds[#kinds + 1] = r.kind end
  local joined = table.concat(kinds, " ")
  T("the plan lists the shotgun's shells", joined:find("loose:primary:slug", 1, true) ~= nil
    and joined:find("loose:secondary:dragon", 1, true) ~= nil and not joined:find("loose:primary:ap", 1, true), joined)
  T("the pump has no magazine row", not joined:find("mag:secondary", 1, true))
  local heads = 0
  for _, r in ipairs(rows) do if r.kind == "cat:shell" then heads = heads + 1 end end
  T("the shells are under one Shotgun heading", heads == 1 and joined:find("cat:shell", 1, true) <
    joined:find("loose:primary:slug", 1, true) and not joined:find("cat:rifle", 1, true), joined)
  T("the categories have names", Ammo.CATEGORY_NAMES.shell == "Shotgun" and Ammo.CATEGORY_NAMES.rifle == "AR/SMG"
    and Ammo.CATEGORY_NAMES.lmg == "LMG")
  T("LMGs take LMG rounds", table.concat(Ammo.CATEGORY_BULLETS.lmg, ",") == "standard,explosive,penetrator")
  T("a shell is priced as a shell", Plan.AddPrice("loose:secondary:he") == 6 * 250)
  T("adding loose rifle rounds to a shotgun is refused", select(2, Plan.Add("loose:secondary:hollow")) ==
    "these rounds do not fit this weapon")
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
