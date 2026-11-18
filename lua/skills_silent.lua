-- Ghost, Silent Killer (SKILLS_REWORK_SPEC.md §7.3): the HP side and the HE
-- side.
--   Second Wind        basic: vanilla + Momentum (a sure crit: +10% speed for
--                      3 s); ace: a melee kill packs loose special rounds into
--                      the gun's own magazine
--   Optical Illusions  basic: HP always crits cloakers; ace: a crit kill can't
--                      be saved by a medic
--   The Professional   basic: HE stuns last 50% longer; ace: stunned enemies
--                      take +20% damage
--   Low Blow           basic: an HP hit on an arm or a leg heals your own a
--                      little; ace: a medic killed from behind makes the
--                      enemies around him sick
--   High Value Target  basic: HE blasts +30%; ace: after an HE sure crit,
--                      HE hits set enemies on fire for 2 s
--   Unseen Strike      basic: a crit kill on natural prey drops a round of
--                      that kind; ace: hits store special rounds for your next
--                      ammo box (taking damage clears them)
-- HE is the LMG's HE round. With the ammo system off the vanilla skills stay.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local SK = PDTI.SilentKiller or {}
PDTI.SilentKiller = SK

SK.MOMENTUM = 0.10
SK.MOMENTUM_TIME = 3
SK.STUN_TIME = 3
SK.STUN_MUL = 1.5
SK.STUNNED_DAMAGE = 1.2
SK.LIMB_HEAL = 0.02
SK.SICK_RANGE = 1000
SK.SICK_TIME = 4
SK.BLAST_MUL = 1.3
SK.IGNITE_WINDOW = 2
SK.FIRE_TIME = 3
SK.STORE_CAP = 20

-- momentum_until, ignite_until; stored[key|bullet] = { key, info, bullet, n }
SK.state = SK.state or { momentum_until = 0, ignite_until = 0, stored = {} }
local state = SK.state

local function log(message) Skills.log("silent: " .. tostring(message)) end

local now = PDTI.GameTime
SK.now = now

local hint = PDTI.Hint

local function A() return PDTI.Ammo end
local function ammo_on() return Skills.AmmoOn() end

local player_unit = PDTI.PlayerUnit

local function tweak_of(dmg_ext)
    local ok, name = pcall(function() return dmg_ext._unit:base()._tweak_table end)
    return ok and name or nil
end

local function is_civilian(dmg_ext)
    local name = tweak_of(dmg_ext)
    local ok, civ = pcall(function() return CopDamage.is_civilian(name) end)
    return ok and civ == true
end

function SK.IsCloaker(dmg_ext)
    local name = tweak_of(dmg_ext)
    return name == "spooc" or name == "shadow_spooc"
end

local function position(unit)
    local ok, p = pcall(function() return unit:position() end)
    return ok and p or nil
end

local function distance(a, b)
    local ok, d = pcall(function() return mvector3.distance(a, b) end)
    if ok and type(d) == "number" then return d end
    return math.huge
end

------------------------------------------------------------ the upgrades

local function on(id, step)
    return function() return ammo_on() and Skills.Step(id) >= (step or 1) end
end
Skills.Off("player", "team_damage_speed_multiplier_send", on("scavenger", 2))
Skills.Off("player", "camouflage_bonus", on("optic_illusions"))
Skills.Off("player", "silencer_concealment_penalty_decrease", on("optic_illusions"))
Skills.Off("player", "silencer_concealment_increase", on("optic_illusions"))
Skills.Off("weapon", "silencer_recoil_index_addend", on("silence_expert"))
Skills.Off("weapon", "silencer_enter_steelsight_speed_multiplier", on("silence_expert"))
Skills.Off("weapon", "silencer_spread_index_addend", on("silence_expert"))
Skills.Off("player", "detection_risk_add_crit_chance", on("backstab"))
Skills.Off("player", "marked_enemy_extra_damage", on("hitman"))
Skills.Off("player", "marked_inc_dmg_distance", on("hitman"))
Skills.Off("player", "unseen_increased_crit_chance", on("unseen_strike"))

------------------------------------------------------- crits and stuns

-- Optical Illusions basic: HP rounds crit cloakers wherever they hit.
local function hp_crit_any(dmg_ext)
    return ammo_on() and Skills.Basic("optic_illusions") and SK.IsCloaker(dmg_ext)
end

-- A sure crit: Momentum, and Ignition after an HE one.
function SK.OnSureCrit(dmg_ext, attack_data, kind, turret)
    if not ammo_on() then return end
    if attack_data and attack_data.attacker_unit ~= nil and attack_data.attacker_unit ~= player_unit() then return end
    if Skills.Basic("scavenger") then state.momentum_until = now() + SK.MOMENTUM_TIME end
    if kind == "he" and Skills.Ace("hitman") then state.ignite_until = now() + SK.IGNITE_WINDOW end
end

function SK.MomentumOn()
    return ammo_on() and Skills.Basic("scavenger") and now() < (state.momentum_until or 0)
end

-- An HE round stunned this enemy.
function SK.OnHeStun(dmg_ext)
    local mul = (ammo_on() and Skills.Basic("silence_expert")) and SK.STUN_MUL or 1
    dmg_ext._pdti_stun_mul = mul
    dmg_ext._pdti_stunned_until = now() + SK.STUN_TIME * mul
end

function SK.Stunned(dmg_ext)
    return (tonumber(dmg_ext._pdti_stunned_until) or 0) > now()
end

------------------------------------------------------------- Low Blow

local ARM_BODIES = { "rag_LeftArm", "rag_RightArm", "rag_LeftForeArm", "rag_RightForeArm" }
local LEG_BODIES = { "rag_LeftUpLeg", "rag_RightUpLeg", "rag_LeftLeg", "rag_RightLeg" }

local function body_in(name, list)
    for _, b in ipairs(list) do
        local ok, id = pcall(Idstring, b)
        if ok and name == id then return true end
    end
    return false
end

-- "arm", "leg" or nil.
function SK.LimbOf(body)
    local ok, name = pcall(function() return body:name() end)
    if not ok or name == nil then return nil end
    if body_in(name, ARM_BODIES) then return "arm" end
    if body_in(name, LEG_BODIES) then return "leg" end
    return nil
end

-- Heals the more hurt of your two arms (or legs), not a black one.
function SK.HealLimb(limb)
    local Body = PDTI.Body
    if not (Body and Body.HealPart and Skills.BodyOn()) then return 0 end
    local ids = limb == "arm" and { "arm_l", "arm_r" } or { "leg_l", "leg_r" }
    local best, best_frac
    for _, id in ipairs(ids) do
        local max = Body.PartMax(id)
        if max > 0 and not Body.IsBlack(id) then
            local frac = Body.HP(id) / max
            if frac < 1 and (not best or frac < best_frac) then best, best_frac = id, frac end
        end
    end
    if not best then return 0 end
    return Body.HealPart(best, Body.PartMax(best) * SK.LIMB_HEAL)
end

-- Vanilla's backstab check: the attacker is behind the enemy.
function SK.FromBehind(enemy_unit, attacker_unit)
    local ok, behind = pcall(function()
        local dir = enemy_unit:position() - attacker_unit:position()
        mvector3.normalize(dir)
        return mvector3.dot(dir, enemy_unit:rotation():y()) >= 0
    end)
    return ok and behind == true
end

-- Every enemy within 10 m of pos is sick for 4 s (the ECM feedback stun).
function SK.SickAround(center_unit)
    local pos = position(center_unit)
    if not pos then return 0 end
    local pl = player_unit()
    local count = 0
    local ok, enemies = pcall(function() return managers.enemy:all_enemies() end)
    if not ok or type(enemies) ~= "table" then return 0 end
    for _, data in pairs(enemies) do
        local unit = data.unit
        local dmg = unit and unit ~= center_unit and unit.character_damage and unit:character_damage()
        local p = unit and position(unit)
        if dmg and p and not dmg._dead and not is_civilian(dmg) and distance(pos, p) <= SK.SICK_RANGE then
            dmg._pdti_vomit_until = now() + SK.SICK_TIME
            local done = pcall(function()
                dmg:damage_explosion({ variant = "stun", damage = 0, attacker_unit = pl, _pdti_own = true,
                    col_ray = { position = p, ray = math.UP or Vector3(0, 0, 1) } })
            end)
            if done then count = count + 1 end
        end
    end
    return count
end

------------------------------------------------------- Unseen Strike

local function store_add(info, bullet)
    local total = 0
    for _, e in pairs(state.stored) do total = total + e.n end
    if total >= SK.STORE_CAP then return false end
    local k = tostring(info.key) .. "|" .. tostring(bullet)
    local e = state.stored[k]
    if not e then
        e = { key = info.key, info = info, bullet = bullet, n = 0 }
        state.stored[k] = e
    end
    e.n = e.n + 1
    return true
end

function SK.Stored()
    local total = 0
    for _, e in pairs(state.stored) do total = total + e.n end
    return total
end

function SK.GiveStored()
    local given = 0
    for k, e in pairs(state.stored) do
        if e.n > 0 and A().AddLooseKey(e.key, e.n, e.info, e.bullet) then
            given = given + e.n
            state.stored[k] = nil
        end
    end
    if given > 0 then
        hint(string.format("Unseen Strike: %d special round(s)", given))
        local wep = A().EquippedBase()
        if wep then pcall(A().SyncTotal, wep) end
    end
    return given > 0
end

-- Damage got through: the stored rounds are lost.
function SK.OnDamageTaken()
    state.stored = {}
end

-- Trophy Ammo: one round of the bullet that killed natural prey.
function SK.DropRound(dmg_ext, info, bullet)
    local AS = PDTI.AmmoSkills
    if not (AS and AS.SpawnSpoil) then return false end
    local unit = dmg_ext._unit
    local pos = position(unit)
    if not pos then return false end
    local rot = nil
    pcall(function() rot = unit:rotation() end)
    local spoil = { loose = { key = info.key, info = info, bullet = bullet, rounds = 1 } }
    local ok, spawned = pcall(AS.SpawnSpoil, pos, rot, spoil)
    return ok and spawned ~= nil
end

------------------------------------------------------- Second Wind ace

-- Packs loose rounds of the gun's current (special) bullet into the gun.
function SK.PackGun(wep)
    local Ammo = A()
    local info = wep and Ammo.Identify(wep)
    if not info or not info.typed or info.akimbo then return 0 end
    local bullet = Ammo.BulletId(Ammo.CurrentBullet(wep))
    if bullet == "standard" then return 0 end
    local clip = wep:get_ammo_remaining_in_clip()
    local chamber = Ammo.ChamberOf(wep)
    local cap
    if info.loose_fed then
        cap = wep:get_ammo_max_per_clip() - chamber
    else
        local spec = Ammo.LoadedSpec(wep)
        cap = spec and spec.capacity or info.capacity
    end
    local room = cap - math.max(0, clip - chamber)
    local n = math.min(room, Ammo.LooseOfKey(info.key, bullet))
    if n <= 0 then return 0 end
    wep:set_ammo_remaining_in_clip(clip + n)
    Ammo.PushLoaded(wep, bullet, n)
    Ammo.ConsumeLooseKey(info.key, n, bullet)
    local installed = wep._issr_mag_installed
    if type(installed) == "table" then installed.rounds = (installed.rounds or 0) + n end
    pcall(Ammo.SyncTotal, wep)
    pcall(Ammo.MarkPanelDirty)
    hint(string.format("Second Wind: %d round(s) loaded", n))
    return n
end

------------------------------------------------------------ the hits

local function fire_dot()
    local ok, v = pcall(function()
        return tweak_data.weapon.factory.parts.wpn_fps_upg_a_dragons_breath.custom_stats.fire_dot_data.dot_damage
    end)
    return ok and tonumber(v) or 1
end

function SK.Ignite(dmg_ext, attack_data)
    local unit = dmg_ext._unit
    local ok = pcall(function()
        managers.fire:add_doted_enemy(unit, now(), attack_data.weapon_unit, SK.FIRE_TIME, fire_dot(),
            attack_data.attacker_unit, false)
    end)
    return ok
end

-- What was fired: the weapon base (typed) and its bullet, or the HE blast.
local function shot_of(attack_data, kind)
    local Ammo = A()
    local weapon = attack_data.weapon_unit
    if not weapon then return nil end
    local ok, base = pcall(function() return weapon:base() end)
    if not ok or not base then return nil end
    if kind == "explosion" then
        local blast = Ammo.he_blast
        if blast and (blast.weapon == nil or blast.weapon == weapon) then return base, "explosive", true end
        return nil
    end
    if kind ~= "bullet" then return nil end
    local typed = Ammo.TypedBase and Ammo.TypedBase(base)
    if not typed then return nil end
    return typed, Ammo.BulletId(Ammo.FiredBullet(typed))
end

-- A hit of the player that the game worked out.
function SK.OnHit(dmg_ext, attack_data, kind, killed, turret)
    if not ammo_on() then return end
    local Ammo = A()
    local base, bullet, he = shot_of(attack_data, kind)
    local civilian = not turret and is_civilian(dmg_ext)

    -- Surefire / Body Expertise.
    if kind == "bullet" and base and (bullet == "ap" or bullet == "penetrator") and not civilian then
        local Barrier = PDTI.Barrier
        if Barrier and Barrier.OnApHit then
            local head = false
            pcall(function() head = dmg_ext:is_head(attack_data.col_ray.body) == true end)
            Barrier.OnApHit(head, base)
        end
    end

    -- Low Blow basic.
    if kind == "bullet" and bullet == "hollow" and not civilian and not turret and Skills.Basic("backstab") then
        local limb = attack_data.col_ray and SK.LimbOf(attack_data.col_ray.body)
        if limb then SK.HealLimb(limb) end
    end

    -- High Value Target ace.
    if he and not killed and not civilian and not turret and now() < (state.ignite_until or 0) and Skills.Ace("hitman") then
        SK.Ignite(dmg_ext, attack_data)
    end

    -- Unseen Strike ace: special hits are stored.
    if base and bullet and bullet ~= "standard" and not civilian and Skills.Ace("unseen_strike") then
        local info = Ammo.Identify(base)
        if info then store_add(info, bullet) end
    end

    if not killed then return end

    -- Unseen Strike basic: natural prey.
    if attack_data.critical_hit and base and Skills.Basic("unseen_strike") then
        local prey = (bullet == "hollow" and SK.IsCloaker(dmg_ext))
            or (bullet == "explosive" and (turret or Ammo.IsDozer(dmg_ext)))
        local info = prey and Ammo.Identify(base)
        if info then SK.DropRound(dmg_ext, info, bullet) end
    end

    -- Low Blow ace.
    if not turret and tweak_of(dmg_ext) == "medic" and Skills.Ace("backstab")
        and SK.FromBehind(dmg_ext._unit, attack_data.attacker_unit) then
        SK.SickAround(dmg_ext._unit)
    end

    -- Second Wind ace.
    if kind == "melee" and Skills.Ace("scavenger") then
        pcall(SK.PackGun, Ammo.EquippedBase())
    end
end

local function observe(kind, turret)
    return function(orig)
        return function(self, attack_data, ...)
            if type(attack_data) ~= "table" or attack_data._pdti_own then return orig(self, attack_data, ...) end
            local mine = attack_data.attacker_unit ~= nil and attack_data.attacker_unit == player_unit()
            -- The Professional ace: stunned enemies take more damage.
            if not turret and not attack_data._pdti_stun_bonus and type(attack_data.damage) == "number"
                and ammo_on() and Skills.Ace("silence_expert") and SK.Stunned(self) then
                attack_data._pdti_stun_bonus = true
                attack_data.damage = attack_data.damage * SK.STUNNED_DAMAGE
            end
            local alive_before = not self._dead
            local before = self._pdti_attack
            self._pdti_attack = attack_data
            local ok, result = pcall(orig, self, attack_data, ...)
            self._pdti_attack = before
            if not ok then error(result, 0) end
            if mine and alive_before and attack_data.variant ~= "stun" and (result ~= nil or attack_data.result ~= nil) then
                local killed = self._dead == true
                local ok2, err = pcall(SK.OnHit, self, attack_data, kind, killed, turret)
                if not ok2 then log("a hit failed: " .. tostring(err)) end
            end
            return result
        end
    end
end

-- install() runs every frame: what it hands out is built once.
local function blast_mul()
    if ammo_on() and Skills.Basic("hitman") then return SK.BLAST_MUL end
    return 1
end
local OBSERVED = { { "damage_bullet", "bullet" }, { "damage_explosion", "explosion" },
    { "damage_fire", "fire" }, { "damage_melee", "melee" } }
local observers = {}
local function observer(kind, turret)
    local key = kind .. (turret and "#turret" or "")
    local make = observers[key]
    if not make then
        make = observe(kind, turret)
        observers[key] = make
    end
    return make
end
local box_extra = {
    has = function() return ammo_on() and Skills.Ace("unseen_strike") and SK.Stored() > 0 end,
    give = function() return SK.GiveStored() end
}

local function make_CopDamage_check_medic_heal(orig)
    return function(self, ...)
        local a = self._pdti_attack
        if a and a.critical_hit and a.attacker_unit ~= nil and a.attacker_unit == player_unit()
            and ammo_on() and Skills.Ace("optic_illusions") then
            return false
        end
        return orig(self, ...)
    end
end

local function make_CopActionHurt_init(orig)
    return function(self, action_desc, ...)
        local result = orig(self, action_desc, ...)
        pcall(function()
            local hurt = type(action_desc) == "table" and action_desc.hurt_type
            local dmg = self._unit and self._unit:character_damage()
            if not dmg then return end
            local t = now()
            if hurt == "concussion" and (tonumber(dmg._pdti_stun_mul) or 1) ~= 1 then
                self._sick_time = t + SK.STUN_TIME * dmg._pdti_stun_mul
                dmg._pdti_stunned_until = self._sick_time
            elseif hurt == "hurt_sick" and (tonumber(dmg._pdti_vomit_until) or 0) > t then
                self._sick_time = dmg._pdti_vomit_until
            end
        end)
        return result
    end
end

local function make_PlayerManager_movement_speed_multiplier(orig)
    return function(self, ...)
        local value = orig(self, ...)
        if type(value) == "number" and SK.MomentumOn() then return value + SK.MOMENTUM end
        return value
    end
end

local function install()
    local Ammo = A()
    if Ammo then
        Ammo.hp_crit_any = hp_crit_any
        Ammo.on_sure_crit = SK.OnSureCrit
        Ammo.on_he_stun = SK.OnHeStun
        Ammo.blast_mul = blast_mul
    end
    for _, k in ipairs(OBSERVED) do
        Skills.wrap("CopDamage", k[1], observer(k[2], false), "silent")
    end
    Skills.wrap("SentryGunDamage", "damage_bullet", observer("bullet", true), "silent")
    Skills.wrap("SentryGunDamage", "damage_explosion", observer("explosion", true), "silent")
    -- Optical Illusions ace: a crit kill can't be saved by a medic.
    Skills.wrap("CopDamage", "check_medic_heal", make_CopDamage_check_medic_heal, "silent")
    -- The Professional basic (longer concussion) and Low Blow ace (sickness).
    Skills.wrap("CopActionHurt", "init", make_CopActionHurt_init, "silent")
    -- Momentum.
    Skills.wrap("PlayerManager", "movement_speed_multiplier", make_PlayerManager_movement_speed_multiplier, "silent")
    -- Unseen Strike ace: the next ammo box.
    local AS = PDTI.AmmoSkills
    if AS then
        AS.box_extra = box_extra
    end
end

function SK.OnHeistStart()
    state.momentum_until = 0
    state.ignite_until = 0
    state.stored = {}
end

Skills.OnInstall("silent", install)

------------------------------------------------------------- the texts

Skills.Text("scavenger", "BASIC: ##$basic##\n"
    .. "When your armor breaks, you gain ##30%## movement speed for ##5## seconds.\n"
    .. "Momentum: every sure critical hit (hollow points on a limb or a Cloaker, HE on a Bulldozer or a "
    .. "turret) gives you ##10%## movement speed for ##3## seconds.\n\n"
    .. "ACE: ##$pro##\n"
    .. "A melee kill packs loose rounds of the same special kind as your weapon's magazine into it, until it "
    .. "is full or you have none left.")
Skills.Text("optic_illusions", "BASIC: ##$basic##\n"
    .. "Hollow point rounds always critically hit Cloakers, wherever they hit.\n\n"
    .. "ACE: ##$pro##\n"
    .. "An enemy you kill with a critical hit can't be saved by a Medic.")
Skills.Text("silence_expert", "BASIC: ##$basic##\n"
    .. "Concussive: the stun of your HE rounds lasts ##50%## longer.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Stunned enemies take ##20%## more damage from every source.")
Skills.Text("backstab", "BASIC: ##$basic##\n"
    .. "Hitting an enemy's arm or leg with hollow points heals your own more hurt arm or leg by ##2%## of its "
    .. "health, unless it is black.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Killing a Medic from behind makes every enemy within ##10## meters of him sick for ##4## seconds: they "
    .. "stand still and can't shoot.")
Skills.Text("hitman", "BASIC: ##$basic##\n"
    .. "Shrapnel: the blast of your HE rounds is ##30%## larger.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Ignition: after an HE critical hit on a Bulldozer or a turret, every enemy you hit with HE in the next "
    .. "##2## seconds is set on fire for ##3## seconds.")
Skills.Text("unseen_strike", "BASIC: ##$basic##\n"
    .. "Trophy Ammo: killing natural prey with a critical hit (a Bulldozer or a turret with HE, a Cloaker with "
    .. "hollow points) drops ##1## round of that kind.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Every hit you deal with special rounds adds ##1## round of that kind to the next ammo box you pick up, "
    .. "up to ##20##. Taking damage clears them. Bulletstorm and Extra Lead can take these rounds.")
