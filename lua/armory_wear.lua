-- Weapon condition (0.47.0). A weapon of yours wears with every round it
-- fires in a heist: from 100% down. Below 50% a shot may jam the gun, more
-- often as it drops (1 shot in 10 at 0%); it never breaks for good. A jammed
-- gun does not fire (the trigger clicks, no round is used) until the Clear
-- Jam key racks it (about 1 s; switching weapons or reloading stops that).
-- At home the weapon's view repairs it: 20% of its built price for a gun
-- worn down to 0%, less for less wear. A worn gun sells for less.
--
-- The free AMCAR / Chimano 88 never wear, and nothing wears in the safehouse.
-- The rounds a class takes to go from 100% to 50% are in Wear.ROUNDS.
--
-- The condition is the weapon item's data.cond (missing: 100). A heist never
-- writes the inventory, so the wear of a heist goes into the armory's file
-- (armory.lua: wear, by uid), which is written at once; at the menu it goes
-- onto the weapons (before a loss is taken out, so an insured weapon comes
-- back at the condition it was lost at).
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Armory then return end

local Armory = PDTI.Armory
local Wear = PDTI.Wear or {}
PDTI.Wear = Wear

local log = PDTI.Logger("PDTI WEAR")

-- Rounds from 100% to 50%, by the weapon's first matching category.
Wear.ROUNDS = { { "minigun", 1000 }, { "lmg", 1500 }, { "snp", 3500 }, { "pistol", 3500 } }
Wear.DEFAULT_ROUNDS = 2500
Wear.JAM_FROM = 50        -- no jams at or above this condition
Wear.JAM_MAX = 0.1        -- the chance a shot jams at 0%
Wear.CLEAR_TIME = 1       -- seconds to clear a jam
Wear.REPAIR_SHARE = 0.2   -- of the built price, for a gun worn to 0%
Wear.FLUSH_EVERY = 30     -- seconds between writes of the wear in a heist
Wear.HINT_EVERY = 2       -- seconds between "jammed" hints

-- (Tests replace these.)
Wear.random = function() return math.random() end
Wear.Now = function() return PDTI.AppTime() end

-- In this heist: the condition of each weapon that fired (by uid), the
-- jammed ones, what is known of each uid (false: not one of your weapons).
Wear.live, Wear.jammed, Wear.known = Wear.live or {}, Wear.jammed or {}, Wear.known or {}
Wear.dirty, Wear.last_flush, Wear.clearing, Wear.hint_t = false, nil, nil, nil

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function clamp(v)
    v = tonumber(v) or 100
    if v ~= v then return 100 end
    return math.max(0, math.min(100, v))
end

local function uid_of(d) return type(d) == "table" and math.floor(tonumber(d.uid) or 0) or 0 end

function Wear.Enabled() return Armory.Enabled() end

------------------------------------------------------------ the numbers

-- Rounds from 100% to 50% for a weapon.
function Wear.Rounds(weapon_id)
    local t = rawget(_G, "tweak_data") and tweak_data.weapon and tweak_data.weapon[weapon_id]
    local cats = type(t) == "table" and type(t.categories) == "table" and t.categories or {}
    for _, e in ipairs(Wear.ROUNDS) do
        for _, c in ipairs(cats) do
            if c == e[1] then return e[2] end
        end
    end
    return Wear.DEFAULT_ROUNDS
end

-- The condition lost per round fired.
function Wear.PerRound(weapon_id) return 50 / Wear.Rounds(weapon_id) end

-- A weapon's condition now (d: a weapon item's data), 0..100.
function Wear.Cond(d)
    if type(d) ~= "table" or d.free then return 100 end
    local live = Wear.live[uid_of(d)]
    if live then return clamp(live) end
    return clamp(d.cond)
end

-- The chance a shot jams at this condition.
function Wear.JamChance(cond)
    cond = clamp(cond)
    if cond >= Wear.JAM_FROM then return 0 end
    return Wear.JAM_MAX * (Wear.JAM_FROM - cond) / Wear.JAM_FROM
end

-- "no jams" / "jams about 1 shot in 25".
function Wear.JamText(cond)
    local p = Wear.JamChance(cond)
    if p <= 0 then return "no jams" end
    return string.format("jams about 1 shot in %d", math.floor(1 / p + 0.5))
end

-- What repairing it to 100% costs now.
function Wear.RepairPrice(d)
    local worn = 100 - Wear.Cond(d)
    if worn <= 0 then return 0 end
    return math.max(1, math.floor(Armory.BuildPrice(d) * Wear.REPAIR_SHARE * worn / 100 + 0.5))
end

-- A worn gun sells for less: half at 0%.
function Wear.SellFactor(d) return 0.5 + Wear.Cond(d) / 200 end

------------------------------------------------------------ repair

local function money(v) return PDTI.Ammo.Money(v) end

-- Repairs the weapon item to 100% (at home). ok, what was said.
function Wear.Repair(c, iid)
    if not Wear.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if Armory.InHeist() then return false, "weapons are repaired at home (the menu or the safehouse)" end
    local item = PDTI.FindItem(c, iid)
    if not item or item.item_id ~= Armory.ITEM_ID or type(item.data) ~= "table" then return false, "no weapon" end
    local d = item.data
    if d.free then return false, "a free weapon never wears" end
    local price = Wear.RepairPrice(d)
    if price <= 0 then return false, "it is in full condition" end
    if not Armory.Take(price) then return false, "not enough money (" .. money(price) .. ")" end
    PDTI.EditItems({ update = { { container = c, instance_id = iid, data = { cond = 100 } } } })
    log(string.format("repaired %s (uid %d) for %d", tostring(d.name or d.weapon_id), uid_of(d), price))
    return true, string.format("Repaired the %s for %s: 100%%", tostring(d.name or d.weapon_id), money(price))
end

-- Your worn weapons (not free, under 100%), worst first:
-- { container, instance_id, data, cond, price }. Rust lists them (safehouse.lua).
function Wear.Worn()
    local out = {}
    for _, w in ipairs(Armory.Weapons()) do
        local cond = Wear.Cond(w.data)
        if cond < 100 then
            out[#out + 1] = { container = w.container, instance_id = w.instance_id, data = w.data, cond = cond,
                price = Wear.RepairPrice(w.data) }
        end
    end
    table.sort(out, function(a, b)
        if a.cond ~= b.cond then return a.cond < b.cond end
        return tostring(a.data.name or a.data.weapon_id) < tostring(b.data.name or b.data.weapon_id)
    end)
    return out
end

-- Repairs every worn weapon to 100% in one payment (at home; all or
-- nothing). ok, what was said.
function Wear.RepairAll()
    if not Wear.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if Armory.InHeist() then return false, "weapons are repaired at home (the menu or the safehouse)" end
    local worn = Wear.Worn()
    if #worn == 0 then return false, "your weapons are in full condition" end
    local total, update = 0, {}
    for i, w in ipairs(worn) do
        total = total + w.price
        update[i] = { container = w.container, instance_id = w.instance_id, data = { cond = 100 } }
    end
    if not Armory.Take(total) then return false, "not enough money (" .. money(total) .. ")" end
    PDTI.EditItems({ update = update })
    log(string.format("repaired %d weapon(s) for %d", #worn, total))
    return true, string.format("Repaired %d weapon(s) for %s: 100%%", #worn, money(total))
end

------------------------------------------------------------ in a heist

-- The weapon item of a uid: { weapon_id, free, cond } or false.
local function known(uid)
    local k = Wear.known[uid]
    if k ~= nil then return k end
    k = false
    local e = Armory.Items(function(_, it) return uid_of(it.data) == uid end)[1]
    if e then k = { weapon_id = e.item.data.weapon_id, free = e.item.data.free == true, cond = clamp(e.item.data.cond) } end
    Wear.known[uid] = k
    return k
end

-- The uid of a gun (an akimbo second gun: its parent's).
local function base_uid(base)
    local uid = nil
    pcall(function()
        uid = base._pdti_uid
        if uid == nil and base.parent_weapon then uid = base.parent_weapon:base()._pdti_uid end
    end)
    return type(uid) == "number" and uid > 0 and uid or nil
end

-- Writes the wear of this heist into the armory's file.
function Wear.Flush()
    Wear.last_flush = Wear.Now()
    if not Wear.dirty then return false end
    local d = Armory._Data()
    for uid, cond in pairs(Wear.live) do d.wear[tostring(uid)] = round2(cond) end
    Wear.dirty = false
    Armory.Save()
    return true
end

local function hint(text)
    local t = Wear.Now()
    if Wear.hint_t and t - Wear.hint_t < Wear.HINT_EVERY then return end
    Wear.hint_t = t
    if PDTI.Hint then pcall(PDTI.Hint, text, 2) end
end
Wear.JAM_HINT = "Your gun jammed: press Clear Jam (a key in the mod's key binds)"

-- A shot left your gun (in a heist): it wears, and may jam.
function Wear.OnShot(base)
    if not Wear.Enabled() or not Armory.InHeist() then return end
    local uid = base_uid(base)
    local k = uid and known(uid)
    if not k or k.free then return end
    local cond = clamp((Wear.live[uid] or k.cond) - Wear.PerRound(k.weapon_id))
    Wear.live[uid] = cond
    Wear.dirty = true
    if not Wear.jammed[uid] and Wear.random() < Wear.JamChance(cond) then
        Wear.jammed[uid] = true
        log(string.format("uid %d jammed at %.1f%%", uid, cond))
        -- (An automatic gun stops its fire sound.)
        local main = base
        pcall(function() if base.parent_weapon then main = base.parent_weapon:base() end end)
        if main.stop_shooting then pcall(main.stop_shooting, main) end
        Wear.hint_t = nil
        hint(Wear.JAM_HINT)
        Wear.Flush()
    elseif not Wear.last_flush or Wear.Now() - Wear.last_flush >= Wear.FLUSH_EVERY then
        Wear.Flush()
    end
end

function Wear.IsJammed(base)
    local uid = base and base_uid(base)
    return uid ~= nil and Wear.jammed[uid] == true
end

local function equipped()
    local A = PDTI.Ammo
    return A and A.EquippedBase and A.EquippedBase() or nil
end

local function reloading()
    local r = false
    pcall(function()
        local st = managers.player:player_unit():movement():current_state()
        r = st:_is_reloading() and true or false
    end)
    return r
end

-- The Clear Jam key.
function Wear.StartClear()
    if not Wear.Enabled() or Wear.clearing then return false end
    local base = equipped()
    if not base or not Wear.IsJammed(base) then hint("Your gun is not jammed"); return false end
    Wear.clearing = { base = base, uid = base_uid(base), done = Wear.Now() + Wear.CLEAR_TIME }
    Wear.hint_t = nil
    hint("Clearing the jam...")
    return true
end

-- Every frame in a heist: a clear in progress ends.
function Wear.Tick()
    local c = Wear.clearing
    if not c then return false end
    if equipped() ~= c.base or reloading() then
        Wear.clearing = nil
        Wear.hint_t = nil
        hint("Clearing the jam stopped: the gun is still jammed")
        return false
    end
    if Wear.Now() < c.done then return false end
    Wear.clearing = nil
    Wear.jammed[c.uid] = nil
    Wear.hint_t = nil
    hint("Jam cleared")
    return true
end

------------------------------------------------------------ the heist's edges

local function reset_live()
    Wear.live, Wear.jammed, Wear.known = {}, {}, {}
    Wear.dirty, Wear.last_flush, Wear.clearing = false, nil, nil
end
Wear.ResetLive = reset_live

-- A heist (or its next day) starts: it goes on from the wear written so far.
function Wear.OnHeistStart()
    reset_live()
    for k, v in pairs(Armory._Data().wear or {}) do
        local uid = math.floor(tonumber(k) or 0)
        if uid > 0 and tonumber(v) then Wear.live[uid] = clamp(v) end
    end
end

-- At the menu: the wear written in heists goes onto the weapons. Not final:
-- a uid not in the inventory yet waits (a weapon captured comes in later).
function Wear.Apply(final)
    local d = Armory._Data()
    local n, keep = 0, {}
    for k, v in pairs(d.wear) do
        local uid = math.floor(tonumber(k) or 0)
        local e = uid > 0 and Armory.Items(function(_, it) return uid_of(it.data) == uid end)[1]
        if e and tonumber(v) then
            PDTI.EditItems({ update = { { container = e.container, instance_id = e.item.instance_id,
                data = { cond = round2(clamp(v)) } } } })
            n = n + 1
        elseif not final then
            keep[k] = v
        end
    end
    d.wear = keep
    Armory.Save()
    if final then reset_live() end
    if n > 0 then log(string.format("the wear of the heist: %d weapon(s)", n)) end
    return n
end

------------------------------------------------------------ hooks

Wear._hooks = Wear._hooks or {}
local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(Wear._hooks, "wear", class_name, fn_name, make)
end

local function make_fire(orig)
    return function(self, ...)
        local result = orig(self, ...)
        if result then pcall(Wear.OnShot, self) end
        return result
    end
end

-- A jammed gun may not start shooting (the game then fires nothing).
local function make_start_allowed(orig)
    return function(self, ...)
        if next(Wear.jammed) ~= nil and Wear.IsJammed(self) then return false end
        return orig(self, ...)
    end
end

-- The trigger pressed on a jammed gun: a click and the hint.
local function make_primary_attack(orig)
    return function(self, t, input, ...)
        if type(input) == "table" and input.btn_primary_attack_press and next(Wear.jammed) ~= nil then
            pcall(function()
                local base = self._equipped_unit and self._equipped_unit:base()
                if base and Wear.IsJammed(base) then
                    if base.dryfire then base:dryfire() end
                    hint(Wear.JAM_HINT)
                end
            end)
        end
        return orig(self, t, input, ...)
    end
end

function Wear.InstallHooks()
    local a = wrap("NewRaycastWeaponBase", "fire", make_fire)
    wrap("NewRaycastWeaponBase", "start_shooting_allowed", make_start_allowed)
    wrap("PlayerStandard", "_check_action_primary_attack", make_primary_attack)
    return a
end
