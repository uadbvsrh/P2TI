-- Loot.
--
-- In the game, a bag of loot is picked up into the carry system: the player
-- carries one bag on the back, throws it or banks it at the escape zone.
--
-- Here every bag is an inventory item. The bag "in your hands" is the bag the
-- game carries (it is thrown with the throw key, as usual); every other bag
-- lies in the rig or the backpack and takes up space and weight:
--
--   * Every bag needs its own place in the rig or the backpack. A bag you
--     have no room for stays on the floor (a hint says why).
--   * Picking up a bag while you carry one puts the carried bag into the
--     inventory and you carry the new one.
--   * Throwing or securing the carried bag brings the next stored bag into
--     your hands, so the bags can be thrown one after another.
--   * The inventory screen can stash the carried bag or take a stored bag
--     out; "Discard held" on a bag drops it in front of you.
--
-- The game lets every player register only one carried bag at a time. As the
-- host (or offline) the mod keeps the game's books right; as a client of
-- another host it cannot, so there you carry one bag, as in the game.
--
-- The carry id of the bag tells what the player carries: the game's carry
-- data has a "bag_value" for every bag that holds loot, and the body bags for
-- corpses and mission items have none.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Loot = PDTI.Loot or {}
PDTI.Loot = Loot

Loot.ITEM_ID = "loot_bag"

-- The containers a loot bag can lie in. The pockets are too small for one.
Loot.CONTAINERS = { "rig", "rig_2", "rig_3", "backpack" }

-- After a throw, the next bag comes into your hands at once (the next frame)
-- if it can; it is tried for this long (e.g. while you climb a ladder).
Loot.PULL_WINDOW = 3
-- The "no room" hint is shown at most this often.
Loot.HINT_INTERVAL = 2

local CARRY_FIELDS = { "carry_id", "multiplier", "dye_initiated", "has_dye_pack", "dye_value_multiplier" }

local runtime = { pull_until = nil, failed_carry = nil, hooks = false }

local function log(message)
    local line = "[PDTI LOOT] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function now()
    local ok, t = pcall(function() return Application:time() end)
    if ok and type(t) == "number" then return t end
    return os.clock()
end

-- The loot bags in the inventory.
local function bags()
    local out = {}
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        return item.item_id == Loot.ITEM_ID
    end)) do
        out[#out + 1] = {
            container = entry.container,
            instance_id = entry.item.instance_id,
            amount = math.max(0, math.floor(tonumber(entry.item.amount) or 0)),
            data = type(entry.item.data) == "table" and entry.item.data or {}
        }
    end
    return out
end

-- The item of the bag the game carries.
local function active_entry()
    for _, entry in ipairs(bags()) do
        if entry.data.active then return entry end
    end
    return nil
end

-- The bags that lie in the inventory (not the one in your hands).
local function stored_entries()
    local out = {}
    for _, entry in ipairs(bags()) do
        if not entry.data.active then out[#out + 1] = entry end
    end
    return out
end

function Loot.Count()
    local total = 0
    for _, entry in ipairs(bags()) do total = total + entry.amount end
    return total
end

function Loot.StoredCount()
    return #stored_entries()
end

-- Is there room for one more bag?
function Loot.HasRoom()
    local def = PDTI.GetItemDefinition(Loot.ITEM_ID)
    local weight = def and tonumber(def.weight) or 0
    local internal = PDTI._internal or {}
    for _, name in ipairs(Loot.CONTAINERS) do
        if PDTI.FindFreeSpace(name, Loot.ITEM_ID, true) then
            local ok, fits = pcall(function()
                return internal.container_weight(name) + weight <= internal.container_weight_limit(name)
            end)
            if not ok or fits then return true end
        end
    end
    return false
end

-- Adds loot bags to the inventory. data describes the bag (its carry id,
-- value multiplier and dye pack), so it can be carried again later.
function Loot.Add(amount, data)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true end

    for _ = 1, amount do
        local placed = false
        for _, name in ipairs(Loot.CONTAINERS) do
            local ok = PDTI.AddItemAuto(name, Loot.ITEM_ID, 1, data, true)
            if ok then placed = true break end
        end
        if not placed then
            return false, "no room in the inventory"
        end
    end
    return true
end

-- Takes loot bags out of the inventory.
function Loot.Remove(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local remaining = amount
    for _, entry in ipairs(bags()) do
        if remaining <= 0 then break end
        if entry.amount > 0 then
            local take = math.min(remaining, entry.amount)
            local ok = PDTI.RemoveItem(entry.container, entry.instance_id, take)
            if ok then remaining = remaining - take end
        end
    end
    return amount - remaining
end

------------------------------------------------------------ the game's bag

local function is_loot(carry_id)
    local carry = type(carry_id) == "string" and tweak_data and tweak_data.carry
        and tweak_data.carry[carry_id]
    -- Every bag that holds loot has a bag value; the body bags for corpses
    -- and the mission items do not.
    return type(carry) == "table" and carry.bag_value ~= nil
end

-- The id of the loot bag the player carries, or nil.
function Loot.CarriedId()
    local pm = managers and managers.player
    if not pm then return nil end
    if type(pm.current_carry_id) ~= "function" then return nil end
    -- Only with a player in the heist: in the menu the game's carry data is
    -- not there, and the game logs the error even when it is caught.
    if type(pm.player_unit) ~= "function" or not pm:player_unit() then return nil end

    local ok, carry_id = pcall(function() return pm:current_carry_id() end)
    if not ok or type(carry_id) ~= "string" or carry_id == "" then return nil end
    if not is_loot(carry_id) then return nil end

    return carry_id
end

-- Everything about the loot bag the player carries, or nil.
function Loot.CarriedData()
    local carry_id = Loot.CarriedId()
    if not carry_id then return nil end
    local data = { carry_id = carry_id, multiplier = 1 }
    local pm = managers.player
    local ok, carried = pcall(function() return pm:get_my_carry_data() end)
    if ok and type(carried) == "table" then
        for _, key in ipairs(CARRY_FIELDS) do
            if carried[key] ~= nil then data[key] = carried[key] end
        end
    end
    data.carry_id = carry_id
    return data
end

local function is_client()
    local ok, client = pcall(function() return Network:is_client() end)
    return ok and client and true or false
end

local function local_peer()
    local ok, peer = pcall(function() return managers.network:session():local_peer() end)
    if ok then return peer end
    return nil
end

-- More than one bag is only possible where the mod keeps the game's books.
function Loot.MultiAllowed()
    return not is_client()
end

local function player_state()
    local ok, value = pcall(function() return managers.player:current_state() end)
    if ok then return value end
    return nil
end

-------------------------------------------------- stash and take out

-- Can the carried bag go into the inventory?
function Loot.CanStash()
    if not Loot.MultiAllowed() then return false end
    if not Loot.CarriedId() then return false end
    return active_entry() ~= nil or Loot.HasRoom()
end

-- Puts the bag you carry into the inventory: your hands are free again.
function Loot.StashCarried()
    if not Loot.MultiAllowed() then return false, "only the host can carry more than one bag" end
    local data = Loot.CarriedData()
    if not data then return false, "you carry no loot bag" end

    local stored = {}
    for k, v in pairs(data) do stored[k] = v end
    stored.active = false

    local active = active_entry()
    local ok, reason
    if active then
        ok, reason = PDTI.EditItems({ update = {
            { container = active.container, instance_id = active.instance_id, data = stored }
        } })
    else
        ok, reason = Loot.Add(1, stored)
    end
    if not ok then return false, reason or "no room in the inventory" end

    -- The game's books: the bag is no longer carried.
    if not is_client() then
        local peer = local_peer()
        if peer and peer.verify_bag then pcall(function() peer:verify_bag(data.carry_id, false) end) end
    end
    local cleared = pcall(function() managers.player:clear_carry() end)
    if not cleared then log("could not clear the carried bag") end
    runtime.pull_until = nil
    return true
end

-- Can a stored bag come into your hands?
function Loot.CanTakeOut()
    if not Loot.MultiAllowed() then return false end
    if Loot.CarriedId() then return false end
    local ok, carrying = pcall(function() return managers.player:is_carrying() end)
    if ok and carrying then return false end
    if #stored_entries() == 0 then return false end
    local state = player_state()
    if state ~= nil and state ~= "standard" then return false end
    return true
end

-- A stored bag comes into your hands: you carry it as in the game.
function Loot.TakeOut(entry)
    if not Loot.CanTakeOut() then return false, "you cannot take a bag out right now" end
    entry = entry or stored_entries()[1]
    if not entry or not is_loot(entry.data.carry_id) then return false, "no stored loot bag" end

    local d = entry.data
    local ok, err = pcall(function()
        managers.player:set_carry(d.carry_id, d.multiplier or 1, d.dye_initiated, d.has_dye_pack, d.dye_value_multiplier)
        local peer = local_peer()
        if peer then managers.player:register_carry(peer, d.carry_id) end
    end)
    if not ok then
        log("could not take the bag out: " .. tostring(err))
        return false, "could not take the bag out"
    end

    PDTI.EditItems({ update = {
        { container = entry.container, instance_id = entry.instance_id, data = { active = true } }
    } })
    runtime.pull_until = nil
    return true
end

-- Drops a bag in front of you (the inventory screen's discard).
function Loot.DropItem(container, instance_id)
    local item = PDTI.FindItem(container, instance_id)
    if not item or item.item_id ~= Loot.ITEM_ID then return false, "not a loot bag" end
    local data = type(item.data) == "table" and item.data or {}

    if not data.active then
        if Loot.CarriedId() then return false, "throw the bag you carry first" end
        local ok, reason = Loot.TakeOut({ container = container, instance_id = instance_id, data = data })
        if not ok then return false, reason end
    end

    local ok, err = pcall(function() managers.player:drop_carry() end)
    if not ok then
        log("could not drop the bag: " .. tostring(err))
        return false, "could not drop the bag"
    end
    -- The bag is in the world now; no other bag follows it into your hands.
    runtime.drop_by_ui = true
    return true
end

----------------------------------------------------------- the game hooks

local function wrap(class_name, fn_name, make)
    local cls = rawget(_G, class_name)
    local current = cls and cls[fn_name]
    if type(current) ~= "function" then return false end
    Loot._hooks = Loot._hooks or {}
    local key = class_name .. "." .. fn_name
    if Loot._hooks[key] == current then return true end
    if PDTI.HookHas(current, "loot") then return true end
    local hook = make(current)
    PDTI.HookMark(hook, current, "loot")
    Loot._hooks[key] = hook
    cls[fn_name] = hook
    return true
end

-- The carry id of the bag lying in the world.
local function world_carry_id(ext)
    local ok, id = pcall(function() return ext._unit:carry_data():carry_id() end)
    if ok and type(id) == "string" then return id end
    return ext and ext._carry_id or nil
end

local function game_blocks(ext)
    local blocked = false
    pcall(function()
        blocked = managers.player:carry_blocked_by_cooldown()
            or ext._unit:carry_data():is_attached_to_zipline_unit()
    end)
    return blocked
end

local function can_carry(carry_id)
    local ok, result = pcall(function() return managers.player:can_carry(carry_id) end)
    if ok and result == false then return false end
    return true
end

-- A new bag needs a place of its own. While you carry a bag, that bag must
-- already be in the inventory (it is stashed and the new one takes its own
-- place), so one free place is always enough.
function Loot.RoomForPickup()
    if Loot.CarriedId() and not active_entry() then return false end
    return Loot.HasRoom()
end

-- Picking up a bag while you carry one: the carried bag goes into the
-- inventory and you carry the new one.
local function can_swap()
    if not Loot.MultiAllowed() then return false end
    if not Loot.CarriedId() then return false end
    return Loot.RoomForPickup()
end

local last_hint = nil
local function hint_no_room()
    local t = now()
    if last_hint and t - last_hint < Loot.HINT_INTERVAL then return end
    last_hint = t
    log("no room in the inventory for another loot bag")
    pcall(function()
        managers.hud:show_hint({ text = "No room for the bag: make room in the rig or the backpack", time = 2 })
    end)
end
Loot._hint_no_room = hint_no_room

-- Why a loot bag in the world cannot be picked up, or nil.
function Loot.PickupBlocked(ext)
    local carry_id = world_carry_id(ext)
    if not is_loot(carry_id) then return nil end
    local carrying = false
    pcall(function() carrying = managers.player:is_carrying() end)
    if carrying and not Loot.CarriedId() then return nil end -- a body or mission item: the game's rule
    if carrying and not Loot.MultiAllowed() then return nil end -- one bag, the game's rule
    if not Loot.RoomForPickup() then return "room" end
    return nil
end

function Loot.InstallHooks()
    if runtime.hooks then return true end
    local ok = wrap("CarryInteractionExt", "_interact_blocked", function(orig)
        return function(self, player)
            local carry_id = world_carry_id(self)
            if is_loot(carry_id) then
                if game_blocks(self) then return true, true end
                if Loot.PickupBlocked(self) == "room" then
                    hint_no_room()
                    return true, true
                end
                if can_swap() then return not can_carry(carry_id) end
            end
            return orig(self, player)
        end
    end)
    ok = wrap("CarryInteractionExt", "can_select", function(orig)
        return function(self, player)
            -- While you carry a loot bag, another one can still be selected
            -- (the pickup itself explains when there is no room).
            if is_loot(world_carry_id(self)) and Loot.MultiAllowed() and Loot.CarriedId() then
                if game_blocks(self) then return false end
                return CarryInteractionExt.super.can_select(self, player)
            end
            return orig(self, player)
        end
    end) and ok
    ok = wrap("CarryInteractionExt", "interact", function(orig)
        return function(self, player)
            if is_loot(world_carry_id(self)) and Loot.PickupBlocked(self) == "room" then
                hint_no_room()
                return false
            end
            if can_swap() then
                local stashed, reason = Loot.StashCarried()
                if not stashed then
                    log("could not stash the carried bag: " .. tostring(reason))
                    return false
                end
            end
            return orig(self, player)
        end
    end) and ok
    if ok then
        runtime.hooks = true
        log("you can carry more than one loot bag")
    end
    return ok
end

------------------------------------------------------------- every frame

-- Follows the bag the player carries.
function Loot.Tick()
    pcall(Loot.InstallHooks)

    local carried = Loot.CarriedData()
    local active = active_entry()

    if carried then
        runtime.pull_until = nil
        runtime.drop_by_ui = nil
        if not active then
            local data = {}
            for k, v in pairs(carried) do data[k] = v end
            data.active = true
            local ok, reason = Loot.Add(1, data)
            if not ok and runtime.failed_carry ~= carried.carry_id then
                runtime.failed_carry = carried.carry_id
                log("no room for the bag you carry: " .. tostring(reason))
            elseif ok then
                runtime.failed_carry = nil
            end
        elseif active.data.carry_id ~= carried.carry_id then
            local data = {}
            for k, v in pairs(carried) do data[k] = v end
            PDTI.EditItems({ update = {
                { container = active.container, instance_id = active.instance_id, data = data }
            } })
        end
        return
    end

    runtime.failed_carry = nil

    if active then
        -- The bag left your hands: thrown, secured or lost when you went down.
        PDTI.RemoveItem(active.container, active.instance_id)
        if not runtime.drop_by_ui then runtime.pull_until = now() + Loot.PULL_WINDOW end
        runtime.drop_by_ui = nil
    end

    -- The next bag comes into your hands at once. The game's carry cooldown
    -- after a throw is only there so you do not grab the bag you just threw
    -- from the floor; a bag from your own inventory does not wait for it.
    if runtime.pull_until then
        if now() > runtime.pull_until then
            runtime.pull_until = nil
        elseif Loot.CanTakeOut() then
            Loot.TakeOut()
        end
    end
end

-- A new heist: the loot of last heist is gone.
function Loot.OnHeistStart()
    runtime.pull_until = nil
    runtime.failed_carry = nil
    local spec = { remove = {} }
    for _, entry in ipairs(PDTI.FindItems(function(container, item)
        return item.item_id == Loot.ITEM_ID
    end)) do
        spec.remove[#spec.remove + 1] = {
            container = entry.container, instance_id = entry.item.instance_id
        }
    end
    if #spec.remove > 0 then
        local ok, reason = PDTI.EditItems(spec)
        if not ok then log("could not clear last heist's loot: " .. tostring(reason)) end
    end
end

function Loot.Reset()
    runtime.pull_until = nil
    runtime.failed_carry = nil
end
