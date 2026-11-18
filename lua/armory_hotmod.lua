-- Hot modding (0.39.0): weapon parts are changed in a heist too.
--
-- In the menu and the safehouse a change is made at once (armory_parts.lua).
-- In a heist it takes time, by the part's kind (HotMod.TIMES): the part goes
-- on (or comes off) when the time is up, and the gun in your hands is made
-- again with it (Armory.ApplyHands). Shooting, aiming, reloading, switching
-- weapons or going down stops it (its time is lost). One change at a time;
-- magazines are changed at home.
--
-- A won heist keeps what it changed: HotMod.RecordWin writes it into the
-- armory file, HotMod.ApplyWin into the inventory (in the menu, or before the
-- next day of the heist). A failed heist loses what you brought (armory.lua).
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Armory or not PDTI.Parts then return end

local Armory, Parts = PDTI.Armory, PDTI.Parts
local HotMod = PDTI.HotMod or {}
PDTI.HotMod = HotMod

local log = PDTI.Logger("PDTI HOTMOD")

-- Seconds a change takes, by the kind of the part fitted or taken off.
HotMod.TIMES = {
    barrel_ext = 2, gadget = 2, bonus = 2, sight = 3, vertical_grip = 3, grip = 3, stock = 4,
    slide = 6, foregrip = 6, barrel = 8, upper_reciever = 10, lower_reciever = 10
}
HotMod.DEFAULT_TIME = 4
HotMod.STOPS = "shooting, aiming, reloading or switching stops it"
-- The player's states a change goes on in (not downed, cuffed, tased...;
-- before the mask is on too).
HotMod.STATES = { standard = true, carry = true, mask_off = true }

local job = nil

function HotMod.Time(ptype) return HotMod.TIMES[ptype] or HotMod.DEFAULT_TIME end

local function uid_of(item) return math.floor(tonumber(item.data.uid) or 0) end

-- The item with this uid: its container and a copy, or nil.
local function find_uid(item_id, uid)
    local e = PDTI.FindItems(function(_, it)
        return it.item_id == item_id and type(it.data) == "table" and it.data.uid == uid
    end)[1]
    if e then return e.container, e.item end
    return nil
end

local function doing(kind) return kind == "fit" and "fitted" or "taken off" end

-- The change going on, or nil: { kind, part_id, ptype, weapon_uid,
-- progress (0 to 1) }.
function HotMod.Active()
    if not job then return nil end
    return { kind = job.kind, part_id = job.part_id, ptype = job.ptype, weapon_uid = job.weapon_uid,
        progress = math.min(1, job.t / job.time) }
end

-- Why another change has to wait, or nil.
function HotMod.Busy()
    if not job then return nil end
    return "wait: the " .. Parts.Name(job.part_id) .. " is being " .. doing(job.kind)
end

-- The screen, when it is open, shows how far it is (not while something is
-- dragged: that would lose the drag's preview).
local function redraw()
    if PDTI.UIIsDragging and PDTI.UIIsDragging() then return end
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
end

local function say(text)
    if PDTI.Hint then pcall(PDTI.Hint, text, 3) end
    if PDTI.UISetStatus then PDTI.UISetStatus(text) end
end

local function standing()
    local ok, state = pcall(function() return managers.player:current_state() end)
    if not ok or state == nil then return true end
    return HotMod.STATES[state] == true
end

-- Why no change can start now (in a heist), or nil.
local function cannot()
    local busy = HotMod.Busy()
    if busy then return busy end
    if not standing() then return "not while you are down, cuffed or tased" end
    return nil
end

local function start(j)
    j.t, j.time = 0, HotMod.Time(j.ptype)
    job = j
    local text = string.format("%s the %s: %d s (%s)", j.kind == "fit" and "Fitting" or "Taking off",
        Parts.Name(j.part_id), j.time, HotMod.STOPS)
    if PDTI.Hint then pcall(PDTI.Hint, text, 3) end
    log(string.format("%s %s (weapon %s)", j.kind, tostring(j.part_id), tostring(j.weapon_uid)))
    return true, text
end

-- Fits the part item onto the weapon item: at once at home, timed in a heist.
function HotMod.Fit(part_c, part_iid, weapon_c, weapon_iid)
    if not Armory.InHeist() then return Parts.Fit(part_c, part_iid, weapon_c, weapon_iid) end
    local no = cannot()
    if no then return false, no end
    local ok, why, part, weapon = Parts.CheckFit(part_c, part_iid, weapon_c, weapon_iid)
    if not ok then return false, why end
    return start({ kind = "fit", part_uid = part.data.uid, part_id = part.data.part_id,
        ptype = Parts.Type(part.data.part_id), weapon_uid = weapon.data.uid })
end

-- Takes a part off the weapon item (to this cell, or next to the weapon):
-- at once at home, timed in a heist.
function HotMod.TakeOff(weapon_c, weapon_iid, part_id, to_c, x, y, rotated)
    if not Armory.InHeist() then return Parts.TakeOff(weapon_c, weapon_iid, part_id, to_c, x, y, rotated) end
    local no = cannot()
    if no then return false, no end
    local ok, why, weapon = Parts.CheckTakeOff(weapon_c, weapon_iid, part_id, to_c)
    if ok and to_c then
        ok, why = PDTI.CanPlace(to_c, { item_id = Parts.ITEM_ID, data = Parts.MakeData(part_id) }, x, y, rotated == true)
    end
    if not ok then return false, why end
    return start({ kind = "off", part_id = part_id, ptype = Parts.Type(part_id), weapon_uid = weapon.data.uid,
        to = to_c and { container = to_c, x = x, y = y, rotated = rotated == true } or nil })
end

-- Stops the change going on: nothing changes, its time is lost.
function HotMod.Stop()
    if not job then return false end
    local j = job
    job = nil
    say(string.format("Stopped: the %s is not %s", Parts.Name(j.part_id), doing(j.kind)))
    log("stopped: " .. tostring(j.part_id))
    redraw()
    return true
end

-- The time is up: the change is made (everything checked again; the items
-- are found by uid wherever they are now).
local function finish()
    local j = job
    job = nil
    local wc, weapon = find_uid(Armory.ITEM_ID, j.weapon_uid)
    local ok, msg = false, "the weapon is gone"
    if weapon and j.kind == "fit" then
        local pc, part = find_uid(Parts.ITEM_ID, j.part_uid)
        msg = "the part is gone"
        if part then ok, msg = Parts.Fit(pc, part.instance_id, wc, weapon.instance_id) end
    elseif weapon then
        local to = j.to
        if to then ok, msg = Parts.TakeOff(wc, weapon.instance_id, j.part_id, to.container, to.x, to.y, to.rotated) end
        -- (Its cell was taken meanwhile: it goes next to the weapon.)
        if not ok then ok, msg = Parts.TakeOff(wc, weapon.instance_id, j.part_id) end
    end
    if not ok then msg = string.format("The %s is not %s: %s", Parts.Name(j.part_id), doing(j.kind), tostring(msg)) end
    say(msg)
    log(tostring(msg))
    redraw()
    return ok, msg
end

-- Every frame of a heist (hooks_game.lua), with the player's input. (While
-- the screen is open the game gets no input: the wheel scrolls the screen.)
function HotMod.Tick(dt, input)
    if not job then return false end
    local Ammo = PDTI.Ammo
    local open = PDTI.IsUIOpen and PDTI.IsUIOpen()
    local acted = not open and Ammo and Ammo.ActionPressed and Ammo.ActionPressed(input)
    if acted or not standing() then
        HotMod.Stop()
        return false
    end
    local before = math.floor(job.t)
    job.t = job.t + (tonumber(dt) or 0)
    if job.t >= job.time then return finish() end
    if math.floor(job.t) ~= before then redraw() end
    return true
end

------------------------------------------------------------ a won heist

local function set_of(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- A won heist (Armory.OnMissionEnd): what it changed, against what you
-- carried at spawn (d.taken, d.taken_bp): the weapons whose build changed,
-- what you brought that is gone (fitted, thrown away, left on the ground)
-- and the parts taken off. Added to what earlier wins left to do (applied
-- in order: the last build of a weapon counts); the caller saves.
function HotMod.RecordWin(d)
    if type(d) ~= "table" or not d.taken_set then return false end
    local after, taken, present = d.after, set_of(d.taken), {}
    for _, e in ipairs(Armory.Owned()) do
        local it, uid = e.item, uid_of(e.item)
        present[uid] = true
        local carried = e.container ~= "locker"
        if carried and it.item_id == Armory.ITEM_ID and taken[uid]
            and tostring(it.data.blueprint or "") ~= d.taken_bp[tostring(uid)] then
            after.builds[#after.builds + 1] = { uid = uid, blueprint = tostring(it.data.blueprint) }
        elseif carried and it.item_id == Parts.ITEM_ID and not taken[uid] then
            after.parts[#after.parts + 1] = { data = copy(it.data), at = e.container }
        end
    end
    for _, uid in ipairs(d.taken) do
        if not present[uid] then after.gone[#after.gone + 1] = uid end
    end
    log(string.format("won: %d build(s), %d gone, %d part(s) taken off", #after.builds, #after.gone, #after.parts))
    return true
end

-- What won heists changed goes into the inventory (the menu, or before the
-- next day of a heist): the new builds, what is gone out, the parts taken
-- off in (where they were, else the locker; with no room they wait).
function HotMod.ApplyWin()
    local d = Armory._Data()
    local after = d.after
    if #after.builds + #after.gone + #after.parts == 0 then return 0 end
    local n = 0
    for _, b in ipairs(after.builds) do
        local c, item = find_uid(Armory.ITEM_ID, b.uid)
        if item then
            Parts.SetBuild(c, item.instance_id, item.data, Armory.SplitBlueprint(b.blueprint))
            n = n + 1
        end
    end
    local gone = set_of(after.gone)
    for _, e in ipairs(Armory.Owned(function(_, it) return gone[uid_of(it)] end)) do
        if PDTI.RemoveItem(e.container, e.item.instance_id) then n = n + 1 end
    end
    local wait = {}
    for _, e in ipairs(after.parts) do
        if not find_uid(Parts.ITEM_ID, e.data.uid) then
            local put = (e.at ~= "locker" and PDTI.AddItemAuto(e.at, Parts.ITEM_ID, 1, e.data, true))
                or PDTI.AddItemAuto("locker", Parts.ITEM_ID, 1, e.data, true)
            if put then n = n + 1 else wait[#wait + 1] = e end
        end
    end
    d.after = { builds = {}, gone = {}, parts = wait }
    Armory.Save()
    log(string.format("what a won heist changed: %d change(s), %d part(s) wait for room", n, #wait))
    return n
end
