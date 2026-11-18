-- Enforcer, Ammo Specialist (SKILLS_REWORK_SPEC.md §4, R8).
--   Scavenger      basic: magazines on the floor are picked up from 1.5x as
--                  far, ammo bags are taken from 50% faster (boxes keep the
--                  game's 1.5x pickup area); ace: reload +15%
--   Bulletstorm    basic "Hot Swap": using an ammo bag reloads the gun at
--                  once; ace "Clean Swap": a reload within 3 m of your own
--                  ammo bag puts the old magazine back full
--   Spoils         (the Portable Saw slot) every 10th special you kill drops
--                  an item instead of ammo; ace "Trophy": a melee kill on a
--                  special always drops it
--   Extra Lead     basic: +2 uses per ammo bag; ace "Reserve Charge": your
--                  bag keeps one use for when you have no loaded magazine
--   Speed Loader   (the Saw Massacre slot) basic: packing 3x faster, tube
--                  shotguns load shells 25% faster; ace "Auto-load": 3 kills
--                  with one shot fill a magazine in the rig at once
--   Fully Loaded   basic "Ammo Pouch": a 2x2 grid for loose rounds; ace "On
--                  the Move": packing from the pouch keeps the gun in hand
--                  (you can sprint)
-- R8: with Bulletstorm or Extra Lead you can't pick up standard ammo boxes.
-- With the ammo system off the vanilla skills stay.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local AS = PDTI.AmmoSkills or {}
PDTI.AmmoSkills = AS

AS.PICKUP_RANGE_MUL = 1.5
AS.BAG_TAKE_SPEED = 1.5
AS.RELOAD_ACE = 0.15
AS.CLEAN_SWAP_RANGE = 300
AS.SPOILS_EVERY = 10
AS.PACK_SPEED = 3
AS.TUBE_SPEED = 0.25
AS.AUTOLOAD_KILLS = 3
AS.SHOT_WINDOW = 1
AS.RESERVE = 1
AS.ONE_USE_WINDOW = 5

-- specials: the counter of special kills; bags: your own ammo bags (units);
-- shot: the last shot of your gun.
AS.state = AS.state or { specials = 0, bags = {}, shot = nil, pending_uses = nil }
local state = AS.state

local function log(message) Skills.log("ammo: " .. tostring(message)) end

local now = PDTI.GameTime
AS.now = now

local hint = PDTI.Hint

local function ammo() return PDTI.Ammo end
local function ammo_on() return Skills.AmmoOn() end

local function player_unit()
    local A = ammo()
    if A and A.PlayerUnit then return A.PlayerUnit() end
    local ok, u = pcall(function() return managers.player:player_unit() end)
    return ok and u or nil
end

local function local_peer_id()
    local ok, id = pcall(function() return managers.network:session():local_peer():id() end)
    if ok and id ~= nil then return id end
    return 1
end

local function is_alive(unit)
    if unit == nil then return false end
    local f = rawget(_G, "alive")
    if type(f) == "function" then
        local ok, a = pcall(f, unit)
        return ok and a == true
    end
    return true
end

------------------------------------------------------------- the paths

function AS.BagPath()
    return ammo_on() and (Skills.Basic("ammo_reservoir") or Skills.Basic("ammo_2x"))
end

function AS.SpoilsOn()
    return ammo_on() and Skills.Basic("portable_saw")
end

-- Does the player have the ammo pouch? While the skills can't be read yet
-- (the save is loading) the pouch is kept, so nothing in it is lost.
function AS.PouchOwned()
    if not ammo_on() then return false end
    if Skills.Known and not Skills.Known() then return true end
    return Skills.Basic("bandoliers")
end
PDTI.PouchOwned = function() return AS.PouchOwned() end

------------------------------------------------------------ the upgrades

-- Scavenger ace replaces the extra ammo box drop.
Skills.Off("player", "double_drop", function() return ammo_on() and Skills.Ace("scavenging") end)

-- Bulletstorm: no no-ammo-cost window.
Skills.Level("player", "no_ammo_cost", function(level)
    if ammo_on() and Skills.Basic("ammo_reservoir") then return 0 end
    return nil
end)
Skills.Off("temporary", "no_ammo_cost", function() return ammo_on() and Skills.Basic("ammo_reservoir") end)
Skills.Off("temporary", "no_ammo_cost_buff", function() return ammo_on() and Skills.Basic("ammo_reservoir") end)

-- The saw is gone: its stat upgrades are off (it stays unlockable, so saved
-- loadouts keep working).
local function saw_off(id) return function() return ammo_on() and Skills.Basic(id) end end
Skills.Off("saw", "extra_ammo_multiplier", saw_off("portable_saw"))
Skills.Off("player", "saw_speed_multiplier", saw_off("portable_saw"))
Skills.Off("saw", "lock_damage_multiplier", saw_off("portable_saw"))
Skills.Off("saw", "enemy_slicer", saw_off("carbon_blade"))
Skills.Off("saw", "ignore_shields", saw_off("carbon_blade"))
Skills.Off("saw", "panic_when_kill", saw_off("carbon_blade"))

-- Extra Lead basic: +2 uses (the game's level 1). Its own vanilla upgrades
-- (one more bag, more ammo per bag) are what this replaces.
Skills.Level("ammo_bag", "ammo_increase", function(level)
    if ammo_on() and Skills.Basic("ammo_2x") then return math.max(tonumber(level) or 0, 1) end
    return nil
end)

-- Fully Loaded: the pouch replaces more ammo and the pickup bonus.
local function bandoliers_off() return ammo_on() and Skills.Basic("bandoliers") end
Skills.Off("player", "extra_ammo_multiplier", bandoliers_off)
Skills.Off("player", "pick_up_ammo_multiplier", bandoliers_off)
Skills.Off("player", "pick_up_ammo_multiplier_2", bandoliers_off)
Skills.Off("player", "regain_throwable_from_ammo", bandoliers_off)

------------------------------------------------------------ the bags

function AS.Mine(base)
    return base ~= nil and base._pdti_owner ~= nil and base._pdti_owner == local_peer_id()
end

local function bag_has_ammo(base)
    return base ~= nil and not base._empty and (tonumber(base._ammo_amount) or 0) > 0
end

local function prune_bags()
    local keep = {}
    for _, unit in ipairs(state.bags) do
        local ok, base = pcall(function() return unit:base() end)
        if is_alive(unit) and ok and bag_has_ammo(base) then keep[#keep + 1] = unit end
    end
    state.bags = keep
end

-- A bag of yours appeared.
function AS.OnOwnBag(unit, base)
    state.bags[#state.bags + 1] = unit
    local pending = state.pending_uses
    if pending and now() - pending.t <= AS.ONE_USE_WINDOW then
        state.pending_uses = nil
        local amount = tonumber(base._ammo_amount) or 0
        local uses = tonumber(pending.uses)
        if uses and amount > uses then
            base._ammo_amount = uses
            pcall(function()
                managers.network:session():send_to_peers_synched("sync_ammo_bag_ammo_taken", unit, amount - uses)
            end)
            pcall(function() base:_set_visual_stage() end)
        end
        -- Rust's room: one more use (yours; the other players' game keeps
        -- the bag's own count).
        local extra = tonumber(pending.extra) or 0
        if extra > 0 then
            base._ammo_amount = (tonumber(base._ammo_amount) or 0) + extra
            pcall(function() base:_set_visual_stage() end)
        end
    end
end

local function mark_owner(unit, peer_id)
    local ok, base = pcall(function() return unit:base() end)
    if not ok or not base then return end
    base._pdti_owner = peer_id
    if peer_id == local_peer_id() then AS.OnOwnBag(unit, base) end
end

-- A bag item is being placed (deployables.lua): with data.uses (fewer
-- uses), or from the rig with Rust's room (one more use).
function AS.OnBagDeploy(data, container)
    local uses = type(data) == "table" and tonumber(data.uses) or nil
    local perks = PDTI.Perks
    local extra = perks and perks.BagExtraUses and perks.BagExtraUses(container) or 0
    if uses or extra > 0 then
        state.pending_uses = { uses = uses, extra = extra, t = now() }
    else
        state.pending_uses = nil
    end
end

-- Within 3 m of one of your bags that still has ammo?
function AS.NearOwnBag(pos)
    prune_bags()
    if not pos then
        local pl = player_unit()
        local ok, p = pcall(function() return pl:position() end)
        if not ok then return false end
        pos = p
    end
    for _, unit in ipairs(state.bags) do
        local ok, d = pcall(function() return mvector3.distance(pos, unit:position()) end)
        if not ok then
            ok, d = pcall(function() return (pos - unit:position()):length() end)
        end
        if ok and type(d) == "number" and d <= AS.CLEAN_SWAP_RANGE then return true end
    end
    return false
end

-- Has the player a magazine with rounds for this weapon in the inventory?
function AS.HasLoadedMagazine(wep)
    local A = ammo()
    local info = wep and A.Identify(wep)
    if not info then return false end
    if info.loose_fed then return A.LooseOfKey(info.key) > 0 end
    return A.MagazineRounds(info.key) > 0
end

-- Reserve Charge: from your own bag, the last use stays until you have no
-- loaded magazine for the weapon in your hands.
function AS.ReserveHeld(base, unit)
    if not (ammo_on() and Skills.Ace("ammo_2x")) then return false end
    if unit == nil or unit ~= player_unit() or not AS.Mine(base) then return false end
    local wep = ammo().EquippedBase()
    return AS.HasLoadedMagazine(wep)
end

-- Hot Swap: the gun gets the fullest magazine at once.
function AS.InstantReload(wep)
    local A = ammo()
    if not wep or A.SkipWeapon(wep) or wep._issr_in_reload then return false end
    local info = A.Identify(wep)
    if not info or info.loose_fed or info.akimbo then return false end
    local clip = wep:get_ammo_remaining_in_clip()
    local chamber = A.ChamberOf(wep)
    local actual = math.max(0, clip - chamber)
    local loaded = A.LoadedSpec(wep)
    local cap = loaded and loaded.capacity or info.capacity
    if actual >= cap then return false end
    local nxt = A.NextMagazine(wep)
    if not nxt or nxt.rounds <= actual then return false end
    local taken
    if A.MustSwap(wep) then
        taken = A.SwapMagazine(wep, actual)
    else
        A.ReturnMagazine(wep, actual)
        taken = A.TakeMagazine(wep)
    end
    if not taken then return false end
    if info.typed then
        A.SetLoaded(wep, taken)
        if A.ApplyLoaded then A.ApplyLoaded(wep) end
    end
    wep._issr_mag_installed = taken
    wep._issr_no_mag = nil
    wep._issr_mag_gone = nil
    wep:set_ammo_remaining_in_clip((taken.rounds or 0) + math.min(chamber, clip))
    pcall(A.SyncTotal, wep)
    pcall(A.SyncGunSlot, wep)
    pcall(A.MarkPanelDirty)
    pcall(A.RefreshHud)
    return true
end

-- Clean Swap: the magazine that comes out goes back full.
local function eject_rounds(wep, rounds)
    if not (ammo_on() and Skills.Ace("ammo_reservoir")) then return rounds end
    local ok, mine = pcall(function()
        return wep._setup and wep._setup.user_unit == player_unit()
    end)
    if ok and mine == false then return rounds end
    if AS.NearOwnBag() then return 100000 end
    return rounds
end

local function make_AmmoBagBase_spawn(orig)
    return function(pos, rot, lvl, peer_id, bullet_storm_level, ...)
        local unit = orig(pos, rot, lvl, peer_id, bullet_storm_level, ...)
        if unit then pcall(mark_owner, unit, peer_id or local_peer_id()) end
        return unit
    end
end

local function make_AmmoBagBase_sync_setup(orig)
    return function(self, lvl, peer_id, bullet_storm_level, ...)
        local ret = orig(self, lvl, peer_id, bullet_storm_level, ...)
        pcall(mark_owner, self._unit, peer_id)
        return ret
    end
end

local function make_AmmoBagBase__take_ammo(orig)
    return function(self, unit, ...)
        if not AS.ReserveHeld(self, unit) then return orig(self, unit, ...) end
        local before = tonumber(self._ammo_amount) or 0
        local keep = AS.RESERVE
        if before <= keep then
            hint("Reserve charge: only when you have no loaded magazine")
            return 0
        end
        self._ammo_amount = before - keep
        local set_empty = rawget(self, "_set_empty")
        self._set_empty = function() end
        local ok, err = pcall(orig, self, unit, ...)
        self._set_empty = set_empty
        local after = math.max(0, tonumber(self._ammo_amount) or 0)
        self._ammo_amount = after + keep
        self._empty = nil
        if not ok then error(err, 0) end
        return math.max(0, before - self._ammo_amount)
    end
end

local function make_AmmoBagBase_take_ammo(orig)
    return function(self, unit, ...)
        local taken, bullet_storm = orig(self, unit, ...)
        if taken and unit ~= nil and unit == player_unit() and ammo_on() and Skills.Basic("ammo_reservoir") then
            pcall(AS.InstantReload, ammo().EquippedBase())
        end
        return taken, bullet_storm
    end
end

local function install_bag_hooks()
    Skills.wrap("AmmoBagBase", "spawn", make_AmmoBagBase_spawn, "ammo_skills")
    Skills.wrap("AmmoBagBase", "sync_setup", make_AmmoBagBase_sync_setup, "ammo_skills")
    -- Reserve Charge.
    Skills.wrap("AmmoBagBase", "_take_ammo", make_AmmoBagBase__take_ammo, "ammo_skills")
    -- Hot Swap.
    Skills.wrap("AmmoBagBase", "take_ammo", make_AmmoBagBase_take_ammo, "ammo_skills")
end

------------------------------------------------------------- the spoils

-- What a special drops, by its tweak table. Police snipers: nothing.
AS.SPOILS = {
    medic = { item = "first_aid_kit" },
    tank_medic = { item = "first_aid_kit" },
    shield = { item = "armor_kit" },
    phalanx_minion = { item = "armor_kit" },
    taser = { mag = "drum", bullet = "hollow", rounds = 75 },
    marshal_marksman = { mag = "standard", bullet = "ap", rounds = 30 },
    spooc = { item = "grenade" },
    shadow_spooc = { item = "grenade" },
    tank = { item = "ammo_bag", data = { uses = 1 } }
}
AS.SPOILS_NAMES = { first_aid_kit = "First Aid Kit", armor_kit = "Armour Plate", grenade = "Throwable",
    ammo_bag = "Ammo Bag (1 use)" }

-- "special" (counts, drops this), "sniper" (counts not, drops nothing), nil.
function AS.Classify(tweak_table)
    if type(tweak_table) ~= "string" then return nil end
    if tweak_table == "sniper" then return nil end
    local s = AS.SPOILS[tweak_table]
    if s then return s end
    if tweak_table:find("^tank") then return AS.SPOILS.tank end
    return nil
end

-- Called for every kill by the player: the drop, or nil.
function AS.OnSpecialKill(tweak_table, melee)
    if not AS.SpoilsOn() then return nil end
    local spoil = AS.Classify(tweak_table)
    if not spoil then return nil end
    if melee and Skills.Ace("portable_saw") then return spoil end
    state.specials = (state.specials or 0) + 1
    if state.specials >= AS.SPOILS_EVERY then
        state.specials = 0
        return spoil
    end
    return nil
end

-- The player's assault rifle or SMG (the gun in hand first).
local function rifle()
    local A = ammo()
    local found
    local function check(wep)
        if found or not wep then return end
        local info = A.Identify(wep)
        if info and info.typed and info.sized and info.family == "rifle" then found = wep end
    end
    pcall(check, A.EquippedBase())
    if not found and A.ForEachWeapon then A.ForEachWeapon(check) end
    return found
end

-- Puts a spoil into the inventory. Returns true, or false and why.
function AS.GiveSpoil(spoil)
    local A = ammo()
    if spoil.loose then
        -- Loose rounds of one supply and bullet (Unseen Strike).
        local l = spoil.loose
        local ok = A.AddLooseKey(l.key, l.rounds or 1, l.info, l.bullet)
        if not ok then return false, "no room for the rounds" end
        local wep = A.EquippedBase()
        if wep then pcall(A.SyncTotal, wep) end
        local def = A.BULLETS[A.BulletId(l.bullet)]
        return true, string.format("%d %s round(s)", l.rounds or 1, def and def.short or tostring(l.bullet))
    end
    if spoil.mag then
        local wep = rifle()
        if wep then
            local info = A.Identify(wep)
            local spec = { size = spoil.mag, bullet = spoil.bullet }
            local rounds = A.SpecCapacity(info.capacity, spoil.mag)
            local ok = A.AddMagazineKey(info.key, rounds, info, nil, spec)
            if not ok then ok = A.AddMagazineKey(info.key, rounds, info, { "backpack" }, spec) end
            if not ok then return false, "no room for the magazine" end
            pcall(A.SyncTotal, wep)
            pcall(A.MarkPanelDirty)
            return true, A.MAG_SIZES[spoil.mag].name .. " magazine (" .. A.BULLETS[spoil.bullet].short .. ")"
        end
        -- No assault rifle or SMG: the rounds, loose, for the gun in hand.
        local wep2 = A.EquippedBase()
        local info = wep2 and A.Identify(wep2)
        if not info then return false, "no gun for the rounds" end
        local ok = A.AddLooseKey(info.key, spoil.rounds, info, info.typed and spoil.bullet or nil)
        if not ok then return false, "no room for the rounds" end
        pcall(A.SyncTotal, wep2)
        return true, tostring(spoil.rounds) .. " loose rounds"
    end
    local data = spoil.data and { uses = spoil.data.uses } or nil
    for _, name in ipairs(A.STORAGE) do
        local ok = PDTI.AddItemAuto(name, spoil.item, 1, data, true)
        if ok then return true, AS.SPOILS_NAMES[spoil.item] or spoil.item end
    end
    return false, "no room for the " .. (AS.SPOILS_NAMES[spoil.item] or spoil.item)
end

-- The drop: an ammo box the player picks up as the spoil.
function AS.SpawnSpoil(position, rotation, spoil)
    local unit_name = tweak_data.pickups.ammo.unit
    local unit = safe_spawn_unit(unit_name, position, rotation)
    if not unit then return nil end
    pcall(function() unit:pickup()._pdti_spoils = spoil end)
    pcall(function() unit:contour():add("deployable_selected") end)
    return unit
end

-- Picking a spoil up (walking over the box).
function AS.PickupSpoil(clip, unit)
    if clip._picked_up then return false end
    local spoil = clip._pdti_spoils
    local ok, what = AS.GiveSpoil(spoil)
    if not ok then
        local t = now()
        if not clip._pdti_hint_t or t - clip._pdti_hint_t > 3 then
            clip._pdti_hint_t = t
            hint("Spoils: " .. tostring(what))
        end
        return false
    end
    clip._picked_up = true
    hint("Spoils: " .. tostring(what))
    pcall(function() unit:sound():play("pickup_ammo", nil, true) end)
    local consumed = pcall(function() clip:consume() end)
    if not consumed then pcall(function() clip._unit:set_slot(0) end) end
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    return true
end

-- Special rounds an ammo box carries for the player (Unseen Strike ace):
-- AS.box_extra = { has = fn() -> bool, give = fn() -> bool }.
function AS.BoxHasSpecial(clip)
    local extra = AS.box_extra
    if type(extra) ~= "table" or type(extra.has) ~= "function" then return false end
    local ok, has = pcall(extra.has)
    return ok and has == true
end

function AS.TakeBoxExtra()
    local extra = AS.box_extra
    if not AS.BoxHasSpecial() or type(extra.give) ~= "function" then return false end
    local ok, given = pcall(extra.give)
    return ok and given == true
end

local function standard_box(clip)
    return not (clip._pdti_spoils or clip._projectile_id or clip._weapon_category)
end

-- R8: the bag path can't take standard ammo boxes (the special rounds one
-- carries for you are taken, the box stays).
function AS.BoxRefused(clip, unit)
    if not AS.BagPath() then return false end
    if not standard_box(clip) then return false end
    if unit == nil or unit ~= player_unit() then return false end
    return true
end

------------------------------------------------------------ one shot

function AS.OnFire(weapon_unit)
    state.shot = { unit = weapon_unit, t = now(), kills = 0 }
end

-- The emptiest magazine of the weapon in the rig, filled from loose rounds.
function AS.AutoLoad(wep)
    local A = ammo()
    local info = wep and A.Identify(wep)
    if not info or info.loose_fed then return 0 end
    local target
    for _, entry in ipairs(A.Magazines(info.key)) do
        if PDTI.IsRigSection(entry.container) and A.EntryCapacity(info, entry) > entry.rounds then
            if not target or entry.rounds < target.rounds then target = entry end
        end
    end
    if not target then return 0 end
    local n = 0
    for _, stack in ipairs(A.LooseStacks(info.key)) do
        n = n + A.LoadAllInto(stack.instance_id, target.instance_id)
    end
    if n > 0 then
        hint(string.format("Auto-load: %d round(s) packed", n))
        pcall(A.SyncTotal, wep)
        pcall(A.MarkPanelDirty)
    end
    return n
end

function AS.OnShotKill(weapon_unit)
    if not (ammo_on() and Skills.Ace("carbon_blade")) then return false end
    local shot = state.shot
    if not shot or shot.done or shot.unit ~= weapon_unit then return false end
    if now() - shot.t > AS.SHOT_WINDOW then return false end
    shot.kills = shot.kills + 1
    if shot.kills < AS.AUTOLOAD_KILLS then return false end
    shot.done = true
    local ok, wep = pcall(function() return weapon_unit:base() end)
    if ok and wep then pcall(AS.AutoLoad, wep) end
    return true
end

local function make_CopDamage_die(orig)
    return function(self, attack_data, ...)
        pcall(function()
            if type(attack_data) ~= "table" or attack_data.attacker_unit == nil then return end
            if attack_data.attacker_unit ~= player_unit() then return end
            local tweak = self._unit and self._unit:base() and self._unit:base()._tweak_table
            local spoil = AS.OnSpecialKill(tweak, attack_data.variant == "melee")
            if spoil then self._pdti_spoils = spoil end
            if attack_data.weapon_unit then AS.OnShotKill(attack_data.weapon_unit) end
        end)
        return orig(self, attack_data, ...)
    end
end

local function make_CopDamage_drop_pickup(orig)
    return function(self, extra, ...)
        local spoil = self._pdti_spoils
        if not spoil or extra then return orig(self, extra, ...) end
        self._pdti_spoils = nil
        local ok, err = pcall(function()
            local tracker = self._unit:movement():nav_tracker()
            local position = tracker:lost() and tracker:field_position() or tracker:position()
            AS.SpawnSpoil(position, self._unit:rotation(), spoil)
        end)
        if not ok then
            log("the spoil could not be dropped: " .. tostring(err))
            return orig(self, extra, ...)
        end
    end
end

local function make_AmmoClip__pickup(orig)
    return function(self, unit, ...)
        if self._pdti_spoils then
            if unit == nil or unit ~= player_unit() then return false end
            return AS.PickupSpoil(self, unit)
        end
        if AS.BoxRefused(self, unit) then
            AS.TakeBoxExtra()
            return false
        end
        local picked = orig(self, unit, ...)
        if picked and unit ~= nil and unit == player_unit() and standard_box(self) then AS.TakeBoxExtra() end
        return picked
    end
end

local function make_NewRaycastWeaponBase_fire(orig)
    return function(self, ...)
        local result = orig(self, ...)
        pcall(function()
            if result and self._setup and self._setup.user_unit == player_unit() then AS.OnFire(self._unit) end
        end)
        return result
    end
end

local function install_kill_hooks()
    Skills.wrap("CopDamage", "die", make_CopDamage_die, "ammo_skills")
    Skills.wrap("CopDamage", "drop_pickup", make_CopDamage_drop_pickup, "ammo_skills")
    Skills.wrap("AmmoClip", "_pickup", make_AmmoClip__pickup, "ammo_skills")
    Skills.wrap("NewRaycastWeaponBase", "fire", make_NewRaycastWeaponBase_fire, "ammo_skills")
end

-------------------------------------------------------- speed and reload

function AS.ReloadMul(wep)
    if not ammo_on() then return 1 end
    local mul = 1
    if Skills.Ace("scavenging") then mul = mul * (1 + AS.RELOAD_ACE) end
    if Skills.Basic("carbon_blade") and wep and wep._use_shotgun_reload then mul = mul * (1 + AS.TUBE_SPEED) end
    return mul
end

local function make_NewRaycastWeaponBase_reload_speed_multiplier(orig)
    return function(self, ...)
        local value = orig(self, ...)
        if type(value) ~= "number" then return value end
        local mine = pcall(function()
            assert(self._setup and self._setup.user_unit == player_unit())
        end)
        if mine then return value * AS.ReloadMul(self) end
        return value
    end
end

local function make_BaseInteractionExt__get_timer(orig)
    return function(self, ...)
        local value = orig(self, ...)
        if type(value) == "number" and self.tweak_data == "ammo_bag" and ammo_on() and Skills.Basic("scavenging") then
            return value / AS.BAG_TAKE_SPEED
        end
        return value
    end
end

local function pickup_range_mul()
    if ammo_on() and Skills.Basic("scavenging") then return AS.PICKUP_RANGE_MUL end
    return 1
end
local function speed_loader_mul()
    if ammo_on() and Skills.Basic("carbon_blade") then return AS.PACK_SPEED end
    return 1
end

local function install_speed_hooks()
    Skills.wrap("NewRaycastWeaponBase", "reload_speed_multiplier", make_NewRaycastWeaponBase_reload_speed_multiplier, "ammo_skills")
    Skills.wrap("BaseInteractionExt", "_get_timer", make_BaseInteractionExt__get_timer, "scavenger")
    local A = ammo()
    if A then
        A.pickup_range_mul = pickup_range_mul
        A.round_speed_mods = A.round_speed_mods or {}
        A.round_speed_mods.speed_loader = speed_loader_mul
        A.eject_rounds = eject_rounds
    end
end

------------------------------------------------------------- the pouch

-- On the Move: packing from the pouch keeps the gun in hand.
function AS.PouchRounds(key)
    local A = ammo()
    local n = 0
    for _, stack in ipairs(A.LooseStacks(key)) do
        if stack.container == "pouch" then n = n + stack.rounds end
    end
    return n
end

function AS.PouchPackAllowed(st, wep)
    if not (ammo_on() and Skills.Ace("bandoliers")) then return false end
    local A = ammo()
    if not wep or A.SkipWeapon(wep) then return false end
    local info = A.Identify(wep)
    if not info or info.loose_fed then return false end
    if AS.PouchRounds(info.key) <= 0 then return false end
    if st then
        local sd = st._state_data or {}
        if sd.reload_expire_t or sd.in_steelsight then return false end
        if st._shooting then return false end
    end
    return A.NeedsFill(wep)
end
if PDTI.Ammo then PDTI.Ammo.PouchPackAllowed = function(st, wep) return AS.PouchPackAllowed(st, wep) end end

-- What is in the pouch without the skill goes to the backpack (or else
-- anywhere it fits; what fits nowhere is left behind).
function AS.TidyPouch()
    if AS.PouchOwned() then return 0 end
    local items = PDTI.FindItems(function(container) return container == "pouch" end)
    local moved = 0
    for _, entry in ipairs(items) do
        local item = entry.item
        local done = false
        for _, name in ipairs({ "backpack", "rig", "rig_2", "rig_3", "pockets" }) do
            local x, y, rotated = PDTI.FindFreeSpace(name, item, true)
            if x ~= nil then
                local ok = PDTI.MoveItem("pouch", item.instance_id, name, x, y, rotated)
                if ok then done = true break end
            end
        end
        if not done then
            PDTI.RemoveItem("pouch", item.instance_id, item.amount or 1)
            log("no room for what was in the ammo pouch: " .. tostring(item.amount) .. " round(s) left behind")
        end
        moved = moved + 1
    end
    return moved
end

------------------------------------------------------------ installing

function AS.OnHeistStart()
    state.specials = 0
    state.bags = {}
    state.shot = nil
    state.pending_uses = nil
    pcall(AS.TidyPouch)
end

Skills.OnInstall("ammo", function()
    install_bag_hooks()
    install_kill_hooks()
    install_speed_hooks()
end)

------------------------------------------------------------- the texts

Skills.Text("scavenging", "BASIC: ##$basic##\n"
    .. "Increases the ammo box pick up range by ##50%##. Magazines on the floor can be picked up from ##50%## "
    .. "farther, and you take ammo from ammo bags ##50%## faster.\n\n"
    .. "ACE: ##$pro##\n"
    .. "You reload ##15%## faster.")
Skills.Text("ammo_reservoir", "BASIC: ##$basic##\n"
    .. "Hot Swap: taking ammo from an ammo bag instantly reloads the weapon in your hands with your fullest "
    .. "magazine.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Clean Swap: reloading within ##3## meters of one of your ammo bags puts the magazine you take out back "
    .. "into your inventory ##full##.\n\n"
    .. "You can't pick up standard ammo boxes.")
Skills.Text("portable_saw", "BASIC: ##$basic##\n"
    .. "Every ##10th## special enemy you kill drops spoils instead of ammo: Medic - a First Aid Kit, Shield - an "
    .. "armour plate, Taser - a drum magazine of hollow points, Marshal sniper - a magazine of armour piercing "
    .. "rounds, Cloaker - a throwable, Bulldozer - an ammo bag with ##1## use. Snipers drop nothing.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Trophy: a special enemy killed in melee always drops its spoils.", "Spoils")
Skills.Text("ammo_2x", "BASIC: ##$basic##\n"
    .. "Your ammo bags have ##2## more uses.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Reserve Charge: your ammo bags keep ##1## use when they run dry. You can take it only when you have "
    .. "no loaded magazine left for the weapon in your hands.\n\n"
    .. "You can't pick up standard ammo boxes.")
Skills.Text("carbon_blade", "BASIC: ##$basic##\n"
    .. "You pack loose rounds into magazines ##3## times as fast, and load shells into a tube shotgun ##25%## "
    .. "faster.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Auto-load: killing ##3## enemies with one shot instantly packs the emptiest magazine in your rig from "
    .. "your loose rounds. HE blasts count; one shotgun shell is one shot.", "Speed Loader")
Skills.Text("bandoliers", "BASIC: ##$basic##\n"
    .. "Ammo Pouch: you get a ##2x2## pouch that holds only loose rounds. Rounds you pick up go there first.\n\n"
    .. "ACE: ##$pro##\n"
    .. "On the Move: packing magazines from the pouch keeps your weapon in your hands, so you can move at full "
    .. "speed and sprint while you pack. Shooting, aiming or reloading stops it.")
