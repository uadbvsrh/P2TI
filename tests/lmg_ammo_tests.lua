-- 0.21.0: LMG rounds. HE rounds (weak, a small blast on impact) and
-- penetrators (through armour, shields, enemies and walls; a violent kick
-- from the shoulder, tame on the bipod).
--   luajit tests/lmg_ammo_tests.lua
local script = arg and arg[0] or "tests/lmg_ammo_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_lmg") .. "/"
ENV.setup(ROOT, TMP)
_G.ModPath = ROOT
_G.Global = { multi_profile = { _current_profile = 1 } }
ENV.install_game()
ENV.install_menuui(false)
ENV.load_mod(ROOT, true)
PDTI._loaded = true
_G.Idstring = function(s) return "ids:" .. tostring(s) end

-- The game's bullet classes and its class() (a table whose fields fall back
-- to the base class).
_G.class = function(base)
  local c = {}
  return setmetatable(c, { __index = base })
end
_G.InstantBulletBase = {
  name = "InstantBulletBase",
  bullet_slotmask = function() return "mask:bullet" end,
  blank_slotmask = function() return "mask:blank" end
}
_G.InstantExplosiveBulletBase = setmetatable({
  name = "InstantExplosiveBulletBase", RANGE = 200, CURVE_POW = 0.5,
  EFFECT_PARAMS = { sound_event = "round_explode", feedback_range = 200, camera_shake_max_mul = 2 },
  bullet_slotmask = function() return "mask:explosive" end,
  blank_slotmask = function() return "mask:explosive_blank" end
}, { __index = _G.InstantBulletBase })

NewRaycastWeaponBase._get_current_damage = function(self, dmg_mul) return (self._damage or 10) * (dmg_mul or 1) end
NewRaycastWeaponBase.armor_piercing_chance = function(self) return self._armor_piercing_chance or 0.25 end
-- The game's crit roll: TEST_CRIT says whether it is a critical hit (x2).
_G.CopDamage = { roll_critical_hit = function(_, attack_data)
  if _G.TEST_CRIT then return true, attack_data.damage * 2 end
  return false, attack_data.damage
end }
dofile(ROOT .. "lua/ammo_hooks.lua")

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function near(a, b) return math.abs((a or -99) - b) < 1e-6 end

local Ammo = PDTI.Ammo
T("the hooks are in place", Ammo.InstallHooks() == true)

local function fresh(name, blueprint, capacity, extra)
  PDTI.Reset()
  Ammo.Reset()
  Ammo.OnHeistStart()
  PDTI.SetSessionOnly(true)
  local unit = ENV.make_unit()
  local wep = ENV.make_weapon(name, blueprint, capacity, extra)
  unit:set_weapon(wep)
  Ammo.EnsureSupply(wep)
  wep.clip = math.min(wep.clip > 0 and wep.clip or 999, wep:get_ammo_max_per_clip())
  Ammo.SyncTotal(wep)
  return wep, Ammo.Identify(wep)
end

local function lmg_extra()
  return { _damage = 10, _use_armor_piercing = true, _can_shoot_through_enemy = false,
    _can_shoot_through_shield = false, _can_shoot_through_wall = false,
    _bullet_class = _G.InstantBulletBase, _bullet_slotmask = "mask:bullet", _blank_slotmask = "mask:blank" }
end

----------------------------------------------------------- the family

do
  local w, info = fresh("test_smg", { "wpn_mag_small" }, 20, lmg_extra())
  T("an LMG has LMG rounds, without magazine sizes",
    info.family == "lmg" and info.typed == true and not info.sized and Ammo.AmmoCategory(info) == "lmg")
  T("an LMG takes standard, HE and penetrator rounds",
    table.concat(Ammo.BulletsFor(info), ",") == "standard,explosive,penetrator")
  T("the spawner's LMG row has the same rounds", Ammo.CATEGORY_BULLETS.lmg == Ammo.LMG_ORDER)
  T("an LMG takes no rifle bullets or shells",
    not Ammo.BulletAllowed(info, "ap") and not Ammo.BulletAllowed(info, "hollow") and not Ammo.BulletAllowed(info, "slug")
    and not Ammo.BulletAllowed(info, "he"))
  local ar = ENV.make_weapon("test_ar", { "wpn_no_part" }, 30)
  local ia = Ammo.Identify(ar)
  T("a rifle takes no LMG rounds", not Ammo.BulletAllowed(ia, "penetrator") and not Ammo.BulletAllowed(ia, "explosive"))
  T("the names", Ammo.BulletName("explosive", "lmg") == "HE round" and Ammo.BulletShort("penetrator", "lmg") == "PEN")
  T("the prices", Ammo.PRICES.round.explosive == 150 and Ammo.PRICES.round.penetrator == 220)
  T("the colours", PDTI.UI_BULLET_COLORS == nil or (PDTI.UI_BULLET_COLORS.explosive ~= nil and PDTI.UI_BULLET_COLORS.penetrator ~= nil))
  local max = w:get_ammo_max_per_clip()
  Ammo.SetLoaded(w, { bullet = "penetrator" })
  Ammo.ApplyLoaded(w)
  T("the LMG keeps the game's magazine size", w:get_ammo_max_per_clip() == max, w:get_ammo_max_per_clip())
end

----------------------------------------------------------- HE rounds

do
  local w = fresh("test_smg", { "wpn_mag_small" }, 20, lmg_extra())
  Ammo.SetLoaded(w, { bullet = "explosive" })
  Ammo.ApplyLoaded(w)
  T("HE: very low damage (x0.35)", near(NewRaycastWeaponBase._get_current_damage(w, 1), 3.5))
  local cls = w._bullet_class
  T("HE: the game's explosive bullet", cls ~= _G.InstantBulletBase and getmetatable(cls).__index == _G.InstantExplosiveBulletBase)
  T("HE: a small blast (60 cm against the game's 2 m)", cls.RANGE == 60 and _G.InstantExplosiveBulletBase.RANGE == 200)
  T("HE: a small shake, and the game's class unchanged",
    cls.EFFECT_PARAMS.feedback_range == 60 and cls.EFFECT_PARAMS.camera_shake_max_mul == 0.5
    and _G.InstantExplosiveBulletBase.EFFECT_PARAMS.feedback_range == 200)
  T("HE: the explosive bullet's hit masks", w._bullet_slotmask == "mask:explosive" and w._blank_slotmask == "mask:explosive_blank")
  T("HE: no armour piercing, through nothing",
    NewRaycastWeaponBase.armor_piercing_chance(w) == 0 and w._can_shoot_through_enemy == false
    and w._can_shoot_through_shield == false and w._can_shoot_through_wall == false)
  T("HE: one class per blast size", Ammo.ExplosiveClass(60) == cls)
  Ammo.SetLoaded(w, { bullet = "standard" })
  Ammo.ApplyLoaded(w)
  T("standard rounds again: the weapon's own bullet and masks",
    w._bullet_class == _G.InstantBulletBase and w._bullet_slotmask == "mask:bullet" and w._blank_slotmask == "mask:blank")
  T("and its own damage", near(NewRaycastWeaponBase._get_current_damage(w, 1), 10))
end

----------------------------------------------------------- penetrators

do
  local w = fresh("test_smg", { "wpn_mag_small" }, 20, lmg_extra())
  Ammo.SetLoaded(w, { bullet = "penetrator" })
  Ammo.ApplyLoaded(w)
  T("penetrator: x1.5 damage", near(NewRaycastWeaponBase._get_current_damage(w, 1), 15))
  T("penetrator: always pierces plates", NewRaycastWeaponBase.armor_piercing_chance(w) == 1)
  T("penetrator: through enemies, shields and walls",
    w._can_shoot_through_enemy == true and w._can_shoot_through_shield == true and w._can_shoot_through_wall == true)
  T("penetrator: an ordinary bullet", w._bullet_class == _G.InstantBulletBase)

  ENV.game.state = "standard"
  w._pdti_recoil_t = nil
  local first = Ammo.BulletRecoil(w)
  local last
  for _ = 1, 12 do last = Ammo.BulletRecoil(w) end
  T("from the shoulder: four times the kick", near(first, 4), first)
  T("and it climbs to twelve times while the trigger is held", near(last, 12), last)

  ENV.game.state = "bipod"
  w._pdti_recoil_t = nil
  local b1 = Ammo.BulletRecoil(w)
  local bn
  for _ = 1, 12 do bn = Ammo.BulletRecoil(w) end
  T("on the bipod: barely more than a standard round, and it does not climb", near(b1, 1.15) and near(bn, 1.15), bn)
  ENV.game.state = "standard"

  Ammo.SetLoaded(w, { bullet = "standard" })
  Ammo.ApplyLoaded(w)
  T("standard rounds again: the walls stop them", w._can_shoot_through_wall == false and w._can_shoot_through_enemy == false)
  w._pdti_recoil_t = nil
  T("and the standard kick", Ammo.BulletRecoil(w) == 1)
end

----------------------------------------------------------- mixed loads

do
  local w = fresh("test_smg", { "wpn_mag_small" }, 20, lmg_extra())
  Ammo.SetLoaded(w, { load = "explosive:2,penetrator:1,standard:17" })
  Ammo.ApplyLoaded(w)
  local seen = {}
  for i = 1, 4 do
    w.clip = w.clip - 1  -- the game takes the round before the shot
    local dmg = NewRaycastWeaponBase._get_current_damage(w, 1)
    seen[i] = string.format("%.1f", dmg)
  end
  T("a mixed belt fires its rounds in order (HE, HE, PEN, STD)",
    table.concat(seen, " ") == "3.5 3.5 15.0 10.0", table.concat(seen, " "))
  T("and the HUD tag shows the top round", Ammo.LoadTag(Ammo.ParseLoad("explosive:2,standard:3")) == "HE+")
end

------------------------------------------------- HE critical hits (0.21.2)

do
  local w = fresh("test_smg", { "wpn_mag_small" }, 20, lmg_extra())
  -- What the enemies and turrets were given.
  CopDamage.damage_explosion = function(self, a)
    -- vanilla rolls here too: it must not crit a second time
    -- (the current game passes the damage as the second argument)
    local c, d = self:roll_critical_hit(a, a.damage)
    self.got, self.crit, self.vanilla_crit = d, a.critical_hit, c
  end
  _G.SentryGunDamage = { damage_explosion = function(self, a) self.got, self.crit = a.damage, a.critical_hit end }
  T("the HE crit hooks go in", Ammo.InstallHooks() == true and Ammo.hooks["CopDamage.damage_explosion"] ~= nil
    and Ammo.hooks["SentryGunDamage.damage_explosion"] ~= nil)
  local function enemy(tweak_table, char_tweak)
    return setmetatable({ _unit = { base = function() return { _tweak_table = tweak_table } end },
      _char_tweak = char_tweak or { critical_hits = { damage_mul = 2 } } }, { __index = CopDamage })
  end
  local function turret() return setmetatable({ _char_tweak = {} }, { __index = SentryGunDamage }) end
  -- The game's explosive bullet: the blast damages what is in range.
  local targets = {}
  InstantExplosiveBulletBase.on_collision_server = function(_, _, _, damage, user, weapon)
    for _, t in ipairs(targets) do
      -- (the explosion manager always gives the unit's position as col_ray)
      t:damage_explosion({ damage = damage, attacker_unit = user, weapon_unit = weapon, variant = "explosion",
        col_ray = { position = {}, ray = {} } })
    end
    return "blast"
  end
  local cls = Ammo.ExplosiveClass(60)
  local player = Ammo.PlayerUnit()
  local function blast(list, user)
    targets = list
    return cls:on_collision_server({}, {}, 10, user or player, w)
  end

  local swat, dozer, mini, tagged, sentry = enemy("swat"), enemy("tank"), enemy("tank_mini"),
    enemy("boss", { tags = { "tank" }, critical_hits = { damage_mul = 3 } }), turret()
  _G.TEST_CRIT = false
  local r = blast({ swat, dozer, mini, tagged, sentry })
  T("the blast is the game's own (its result comes back)", r == "blast")
  T("without a crit roll an HE blast hits a cop normally", swat.got == 10 and not swat.crit, swat.got)
  T("and the game does not roll a second time", swat.vanilla_crit == false)
  -- 0.21.5: x4 on bulldozers and turrets, then the crit (x2, or their own).
  T("a bulldozer is always crit, and takes four times the damage", dozer.got == 80 and dozer.crit == true
    and mini.got == 80, dozer.got)
  T("any bulldozer (by its tag), with its own crit multiplier", tagged.got == 120 and tagged.crit == true, tagged.got)
  T("a turret is always crit, four times the damage", sentry.got == 80 and sentry.crit == true, sentry.got)
  T("an HE round hits a bulldozer harder than a standard round (x2.8)", dozer.got / 10 * 0.35 > 2.5)
  -- The player's crit chance (skills): the blast rolls it like a bullet.
  -- TEST_CRIT makes the game's own roll crit too: it must not run again.
  _G.TEST_CRIT = true
  managers.player.critical_hit_chance = function() return 0.5 end
  Ammo.crit_roll = function() return 0.1 end
  swat = enemy("swat")
  blast({ swat })
  T("the HE blast can crit, by the player's crit chance", swat.got == 20 and swat.crit == true, swat.got)
  T("crit once, not twice", swat.vanilla_crit == false)
  Ammo.crit_roll = function() return 0.9 end
  swat = enemy("swat")
  blast({ swat })
  T("a failed roll is no crit", swat.got == 10 and not swat.crit, swat.got)
  -- 0.21.4: the game's roll_critical_hit needs the damage as its second
  -- argument in the current game; called without it, it crashed the game.
  -- The HE crit does not call it at all.
  Ammo.crit_roll = function() return 0.1 end
  local strict = enemy("swat")
  strict.roll_critical_hit = function(_, a, damage)
    if damage == nil then strict.bad_call = true end
    return false, damage * 1  -- the game's arithmetic on its damage argument
  end
  local ok_blast = pcall(blast, { strict })
  T("the game's crit roll is never called without the damage (it crashed the game)", ok_blast
    and strict.bad_call == nil and strict.crit == true, tostring(strict.got))
  local no_crit_weapon = enemy("swat")
  no_crit_weapon.can_be_critical = function() return false end
  blast({ no_crit_weapon })
  T("a weapon that cannot crit with explosions does not", not no_crit_weapon.crit and no_crit_weapon.got == 10)
  managers.player.critical_hit_chance = function() return 0 end
  local none = enemy("swat")
  blast({ none })
  T("without crit chance no crit", not none.crit and none.got == 10)
  managers.player.critical_hit_chance = nil
  Ammo.crit_roll = function() return math.random() end
  _G.TEST_CRIT = false
  T("after the blast nothing is marked", Ammo.he_blast == nil)
  -- Not an HE round's blast: a grenade, or another player.
  local d2 = enemy("tank")
  d2:damage_explosion({ damage = 10, attacker_unit = player, weapon_unit = w, variant = "explosion" })
  T("another explosion (a grenade) is left to the game", d2.got == 10 and not d2.crit, d2.got)
  local d3 = enemy("tank")
  blast({ d3 }, {})
  T("someone else's HE round is left to the game", d3.got == 10 and not d3.crit, d3.got)
  -- 0.21.3: HE rounds stun. A hit enemy who lives may be dazed (the game's
  -- stun_hit, the concussion grenade's stun).
  local function stunnable(name, dead)
    local e = enemy(name)
    e._dead = dead
    e.stun_hit = function(self, a) self.stunned = a end
    return e
  end
  _G.CopDamage.is_civilian = function(t) return t == "civilian" end
  local roll = 0.1
  Ammo.stun_roll = function() return roll end
  local cop, dead, civ, doz, tur = stunnable("swat"), stunnable("swat", true), stunnable("civilian"),
    stunnable("tank"), turret()
  tur.stun_hit = function(self) self.stunned = true end
  blast({ cop, dead, civ, doz, tur })
  T("an HE blast can stun the enemy it hits", cop.stunned ~= nil and cop.stunned.variant == "explosion"
    and cop.stunned.col_ray ~= nil)
  T("with the blast's position", cop.stunned and cop.stunned.col_ray.position ~= nil)
  T("not a dead one, a civilian, a bulldozer or a turret", dead.stunned == nil and civ.stunned == nil
    and doz.stunned == nil and tur.stunned == nil)
  roll = 0.99
  local always = stunnable("swat")
  blast({ always })
  T("every HE blast stuns (a concussion round)", always.stunned ~= nil and Ammo.BULLETS.explosive.stun_chance == 1)
  T("and stays weak against people", always.got == 10 and not always.crit)
  local other = stunnable("swat")
  roll = 0
  other:damage_explosion({ damage = 10, attacker_unit = player, weapon_unit = w, variant = "explosion",
    col_ray = { position = {} } })
  T("other explosions do not stun", other.stunned == nil)
  Ammo.stun_roll = function() return math.random() end
  -- An error in the blast clears the mark and is passed on.
  InstantExplosiveBulletBase.on_collision_server = function() error("boom") end
  local ok = pcall(blast, { enemy("swat") })
  T("an error in the blast clears the mark", not ok and Ammo.he_blast == nil)
end

print(string.format("\n%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
