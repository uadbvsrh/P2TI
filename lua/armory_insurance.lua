-- Weapon insurance (0.45.0). A weapon of yours can be insured at home (the
-- menu or the safehouse) for 30% of its built price: the game's price of the
-- weapon and of every part on it beyond its own. The insurance lasts until
-- the weapon is lost: a failed or abandoned heist, left on the ground or
-- thrown away in a won one. Then the weapon comes back into the locker 10
-- real minutes after the heist ended, as it was insured, without its loaded
-- magazine. Won heists do not use it up.
--
-- The insurance is for one build: a change at home (a part fitted or taken
-- off, a template, what a won heist changed) cancels it and pays it back, so
-- a part is never had twice and a bare gun insured cheaply never brings back
-- parts fitted later. Selling the weapon or throwing it away at home pays it
-- back too. Duke's room (perks.lua) makes it cheaper and faster.
--
-- The policies and the weapons on their way back live in the armory's file
-- (armory.lua: policies, returns, ended_at).
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Armory then return end

local Armory = PDTI.Armory
local Insurance = PDTI.Insurance or {}
PDTI.Insurance = Insurance

local log = PDTI.Logger("PDTI INSURANCE")

Insurance.SHARE = 0.3   -- of the weapon's built price
Insurance.DELAY = 600   -- real seconds from the heist's end to the return

-- Real time (tests replace it).
Insurance.Now = function() return os.time() end

-- What was said about a weapon's insurance this session, by uid.
Insurance.notes = Insurance.notes or {}

local function money(v)
    if PDTI.Ammo and PDTI.Ammo.Money then return PDTI.Ammo.Money(v) end
    return "$" .. tostring(math.floor((tonumber(v) or 0) + 0.5))
end

local function uid_of(d) return type(d) == "table" and math.floor(tonumber(d.uid) or 0) or 0 end

local function data() return Armory._Data() end

-- At home: the menu or the safehouse, the inventory that is kept.
local function at_home()
    if not Armory.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    -- (A heist's inventory is session-only: Armory.InHeist counts it.)
    if Armory.InHeist() then return false, "insurance is bought at home (the menu or the safehouse)" end
    return true
end
Insurance.AtHome = at_home

------------------------------------------------------------ the price

function Insurance.Share()
    local P = PDTI.Perks
    if P and P.InsuranceShare then return P.InsuranceShare(Insurance.SHARE) end
    return Insurance.SHARE
end

function Insurance.Delay()
    local P = PDTI.Perks
    if P and P.InsuranceDelay then return P.InsuranceDelay(Insurance.DELAY) end
    return Insurance.DELAY
end

-- "10 min" / "90 s".
function Insurance.DelayText(seconds)
    seconds = math.floor(tonumber(seconds) or Insurance.Delay())
    if seconds % 60 == 0 then return (seconds / 60) .. " min" end
    return seconds .. " s"
end

-- What insuring this weapon costs now (d: a weapon item's data).
function Insurance.Price(d)
    return math.floor(Armory.BuildPrice(d) * Insurance.Share() + 0.5)
end

------------------------------------------------------------ policies

function Insurance.Policy(uid)
    uid = math.floor(tonumber(uid) or 0)
    if uid <= 0 then return nil end
    return data().policies[tostring(uid)]
end

function Insurance.Note(uid) return Insurance.notes[math.floor(tonumber(uid) or 0)] end

-- Can this item be insured now? ok, why.
function Insurance.Insurable(item)
    local home, why = at_home()
    if not home then return false, why end
    if type(item) ~= "table" or item.item_id ~= Armory.ITEM_ID or type(item.data) ~= "table" then
        return false, "only weapons are insured"
    end
    if item.data.free then return false, "a free weapon is given again: it needs no insurance" end
    if uid_of(item.data) <= 0 then return false, "this weapon cannot be insured" end
    if Insurance.Policy(item.data.uid) then return false, "it is insured already" end
    return true
end

local function name_of(d) return tostring(d.name or d.weapon_id or "weapon") end

-- The policy of a weapon whose price was paid (for its build now).
local function add_policy(d, price)
    data().policies[tostring(uid_of(d))] = { paid = price, bp = tostring(d.blueprint or ""), name = name_of(d),
        weapon_id = tostring(d.weapon_id), at = Insurance.Now() }
    Insurance.notes[uid_of(d)] = nil
end

-- Insures the weapon item: its price is paid now.
function Insurance.Insure(c, iid)
    local item = PDTI.FindItem(c, iid)
    local ok, why = Insurance.Insurable(item)
    if not ok then return false, why end
    local d = item.data
    local price = Insurance.Price(d)
    if not Armory.Take(price) then return false, "not enough money (" .. money(price) .. ")" end
    add_policy(d, price)
    Armory.Save()
    log(string.format("insured %s (uid %d) for %d", name_of(d), uid_of(d), price))
    return true, string.format("Insured the %s for %s: lost, it is back in your locker %s after the heist",
        name_of(d), money(price), Insurance.DelayText())
end

-- Your weapons by insurance (Houston lists them, safehouse.lua): the ones
-- that can be insured now, dearest first (then by name), and the insured
-- ones, by name. Each { container, instance_id, data, price }.
function Insurance.Weapons()
    local open, insured = {}, {}
    for _, w in ipairs(Armory.Weapons()) do
        local e = { container = w.container, instance_id = w.instance_id, data = w.data, price = Insurance.Price(w.data) }
        if Insurance.Policy(w.data.uid) then
            insured[#insured + 1] = e
        elseif Insurance.Insurable(PDTI.FindItem(w.container, w.instance_id)) then
            open[#open + 1] = e
        end
    end
    table.sort(open, function(a, b)
        if a.price ~= b.price then return a.price > b.price end
        return name_of(a.data) < name_of(b.data)
    end)
    table.sort(insured, function(a, b) return name_of(a.data) < name_of(b.data) end)
    return open, insured
end

-- Insures every weapon that can be (at home), in one payment: all or
-- nothing. ok, what was said.
function Insurance.InsureAll()
    local home, why = at_home()
    if not home then return false, why end
    local open = Insurance.Weapons()
    if #open == 0 then return false, "no weapon to insure" end
    local total = 0
    for _, e in ipairs(open) do total = total + e.price end
    if not Armory.Take(total) then return false, "not enough money (" .. money(total) .. ")" end
    for _, e in ipairs(open) do add_policy(e.data, e.price) end
    Armory.Save()
    log(string.format("insured %d weapon(s) for %d", #open, total))
    return true, string.format("Insured %d weapon(s) for %s: lost, each is back in your locker %s after the heist",
        #open, money(total), Insurance.DelayText())
end

-- Ends a policy and pays it back. Returns true and what was paid back.
function Insurance.Cancel(uid, why)
    local key = tostring(math.floor(tonumber(uid) or 0))
    local p = data().policies[key]
    if not p then return false, 0 end
    data().policies[key] = nil
    local back = Armory.Give(p.paid)
    Armory.Save()
    log(string.format("the insurance of %s (uid %s) ended (%s): %d paid back", tostring(p.name), key,
        tostring(why or "cancelled"), back))
    return true, p.paid
end

-- The Cancel button: the weapon item's insurance.
function Insurance.CancelItem(c, iid)
    local item = PDTI.FindItem(c, iid)
    if not item or type(item.data) ~= "table" then return false, "no weapon" end
    local home, why = at_home()
    if not home then return false, why end
    local ok, paid = Insurance.Cancel(item.data.uid, "cancelled")
    if not ok then return false, "it is not insured" end
    return true, string.format("The %s is not insured any more: %s back", name_of(item.data), money(paid))
end

local function cancelled(d, why, new_d)
    local uid = uid_of(d)
    local _, paid = Insurance.Cancel(uid, why)
    local text = string.format("Insurance of the %s cancelled: %s (%s back). Insure it again for %s.", name_of(d),
        why, money(paid), money(Insurance.Price(new_d or d)))
    Insurance.notes[uid] = text
    if PDTI.Hint then pcall(PDTI.Hint, text, 4) end
    return text
end

-- A weapon's build changed (armory_parts.lua's set_build): at home, its
-- insurance (for the old build) is cancelled and paid back. In a heist
-- nothing happens until you are home.
function Insurance.OnBuildChanged(d, bp)
    if not at_home() or type(d) ~= "table" then return nil end
    local p = Insurance.Policy(d.uid)
    bp = type(bp) == "table" and Armory.JoinBlueprint(bp) or tostring(bp or "")
    if not p or p.bp == bp then return nil end
    local new_d = { weapon_id = d.weapon_id, factory_id = d.factory_id, blueprint = bp }
    return cancelled(d, "its build changed", new_d)
end

-- A weapon is sold (armory_parts.lua): its insurance is paid back.
function Insurance.OnSold(d)
    if type(d) ~= "table" then return 0 end
    local ok, paid = Insurance.Cancel(d.uid, "sold")
    return ok and paid or 0
end

------------------------------------------------------------ losses

-- A weapon you lost (taken out of the inventory: armory.lua's ApplyLost,
-- armory_hotmod.lua's ApplyWin). Insured: the policy is used, and the weapon
-- comes back when the delay after the heist's end (at) is over. Returns true
-- and the time it is due.
function Insurance.Claim(d, at)
    local uid = uid_of(d)
    local p = uid > 0 and data().policies[tostring(uid)]
    if not p then return false end
    if tostring(d.blueprint or "") ~= p.bp then
        -- (Changed since: never at home. The build insured is not the one
        -- lost, so nothing comes back: what was paid does.)
        Insurance.Cancel(uid, "lost with another build than the insured one")
        return false
    end
    data().policies[tostring(uid)] = nil
    local back = Armory.MakeData(d.weapon_id, Armory.SplitBlueprint(p.bp), Armory.NewUid())
    -- No magazine comes back with it.
    back.gun_set, back.gun_n, back.gun_weight = 1, 0, 0
    -- As worn as it was lost (armory_wear.lua).
    if tonumber(d.cond) and tonumber(d.cond) < 100 then back.cond = tonumber(d.cond) end
    -- With its skin (armory_skins.lua).
    for _, k in ipairs({ "skin_id", "skin_iid", "skin_quality", "skin_bonus", "skin_color" }) do back[k] = d[k] end
    local due = math.floor((tonumber(at) or Insurance.Now()) + Insurance.Delay())
    local list = data().returns
    list[#list + 1] = { data = back, due = due, name = name_of(back) }
    Armory.Save()
    log(string.format("lost %s (uid %d): insured, back at %s", name_of(d), uid, os.date("%H:%M", due)))
    return true, due
end

-- At home: a policy whose weapon is gone without a loss (sold, thrown away)
-- or has another build now is paid back. Not while losses or a heist's
-- changes wait to be taken out (those weapons are claimed then).
function Insurance.Sweep()
    if not at_home() then return 0 end
    local d = data()
    if d.in_heist or #d.lost > 0 or #d.after.gone > 0 or #d.after.builds > 0 then return 0 end
    if next(d.policies) == nil then return 0 end
    local owned = {}
    for _, e in ipairs(Armory.Items()) do owned[uid_of(e.item.data)] = e.item.data end
    local keys = {}
    for key in pairs(d.policies) do keys[#keys + 1] = key end
    table.sort(keys)
    local n = 0
    for _, key in ipairs(keys) do
        local p = d.policies[key]
        local w = owned[tonumber(key)]
        if not w then
            Insurance.Cancel(key, "the weapon is gone (sold or thrown away)")
            n = n + 1
        elseif tostring(w.blueprint or "") ~= p.bp then
            cancelled(w, "its build changed")
            n = n + 1
        end
    end
    return n
end

------------------------------------------------------------ returns

-- The weapons on their way back, the first due first:
-- { name, due, clock ("14:32"), here (due now: waiting for room) }.
function Insurance.Returns()
    local now, out = Insurance.Now(), {}
    for _, r in ipairs(data().returns) do
        out[#out + 1] = { name = r.name, due = r.due, clock = os.date("%H:%M", r.due), here = r.due <= now }
    end
    table.sort(out, function(a, b) return a.due < b.due end)
    return out
end

-- The lines the screen shows about them.
function Insurance.ReturnLines()
    local lines = {}
    for _, r in ipairs(Insurance.Returns()) do
        if r.here then
            lines[#lines + 1] = string.format("Insurance: the %s is back, but your locker has no room for it", r.name)
        else
            lines[#lines + 1] = string.format("Insurance: the %s is back at %s", r.name, r.clock)
        end
    end
    return lines
end

-- At home: every weapon due is put into the locker (no room: it waits).
-- Returns how many came.
function Insurance.Deliver()
    if not at_home() then return 0 end
    local d = data()
    if d.in_heist or #d.returns == 0 then return 0 end
    local now, keep, came, changed = Insurance.Now(), {}, {}, false
    for _, r in ipairs(d.returns) do
        if r.due <= now and PDTI.AddItemAuto("locker", Armory.ITEM_ID, 1, r.data, true) then
            came[#came + 1] = r.name
            log("back from the insurance: " .. tostring(r.name))
        else
            if r.due <= now and not r.told then
                r.told, changed = true, true
                log("no room in the locker for the " .. tostring(r.name) .. " back from the insurance: it waits")
            end
            keep[#keep + 1] = r
        end
    end
    d.returns = keep
    if #came > 0 or changed then Armory.Save() end
    if #came > 0 then
        local text = "Insurance: your " .. table.concat(came, ", ") .. " " .. (#came > 1 and "are" or "is")
            .. " back in your locker"
        Insurance.last = text
        if PDTI.Hint then pcall(PDTI.Hint, text, 5) end
        if PDTI.UISetStatus then PDTI.UISetStatus(text) end
    end
    return #came
end

-- Every frame at home (the main menu, the safehouse): once a second, the
-- returns due come in and policies with nothing to cover are paid back.
local last_check = nil
function Insurance.Tick()
    local now = Insurance.Now()
    if now == last_check then return 0 end
    last_check = now
    if not at_home() then return 0 end
    local d = data()
    local n = 0
    if #d.returns > 0 then n = Insurance.Deliver() end
    if next(d.policies) ~= nil then Insurance.Sweep() end
    if n > 0 and PDTI.IsUIOpen and PDTI.IsUIOpen() and not (PDTI.UIIsDragging and PDTI.UIIsDragging())
        and PDTI.RedrawUI then
        pcall(PDTI.RedrawUI)
    end
    return n
end

function Insurance.ResetTick() last_check = nil end
