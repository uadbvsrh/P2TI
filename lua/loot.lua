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
-- The loot slots (Clover's room) first: that is what they are for.
Loot.CONTAINERS = { "loot_slot", "rig", "rig_2", "rig_3", "backpack" }

-- After a throw, the next bag comes into your hands at once (the next frame)
-- if it can; it is tried for this long (e.g. while you climb a ladder).
Loot.PULL_WINDOW = 3
-- The "no room" hint is shown at most this often.
Loot.HINT_INTERVAL = 2

-- What a bag's quality writes into its data (loot_quality.lua).
Loot.QUALITY_FIELDS = { "quality", "mods", "w", "h", "max_stack" }

local CARRY_FIELDS = { "carry_id", "multiplier", "dye_initiated", "has_dye_pack", "dye_value_multiplier" }

local runtime = { pull_until = nil, failed_carry = nil, hooks = false }

local log = PDTI.Logger("PDTI LOOT")

local now = PDTI.AppTime

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
local function is_active_bag(container, item)
    return item.item_id == Loot.ITEM_ID and type(item.data) == "table" and item.data.active and true or false
end
local function active_entry()
    local container, item = PDTI.FindFirstItem(is_active_bag)
    if not item then return nil end
    return {
        container = container,
        instance_id = item.instance_id,
        amount = math.max(0, math.floor(tonumber(item.amount) or 0)),
        data = item.data
    }
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
        local placed = Loot.StackOnto(data)
        for _, name in ipairs(Loot.CONTAINERS) do
            if placed then break end
            local ok = PDTI.AddItemAuto(name, Loot.ITEM_ID, 1, data, true)
            if ok then placed = true end
        end
        if not placed then
            return false, "no room in the inventory"
        end
    end
    -- A Stackable bag that took a place of its own gathers the single bags
    -- of its loot.
    if type(data) == "table" and not data.active and Loot.Gather then Loot.Gather() end
    return true
end

-- Bags of the same loot: kind and what the dye pack left of its value (a
-- field missing in one and false in the other is the same). Quality and
-- modifiers do not matter: a Stackable bag carries any bag of its loot.
local function stack_key(data)
    local function num(v, default) return tonumber(v) or default end
    return table.concat({ tostring(data.carry_id), tostring(num(data.multiplier, 1)),
        tostring(data.dye_initiated == true), tostring(data.has_dye_pack == true),
        tostring(num(data.dye_value_multiplier, 100)) }, "|")
end
Loot.StackKey = stack_key

local function lq() return PDTI.LootQuality end

local function bag_limit(data)
    return PDTI.ItemMaxStack(PDTI.GetItemDefinition(Loot.ITEM_ID) or {}, data)
end

-- A stored Stackable bag with room that one more bag of this loot rides on,
-- or nil. (Only a single bag joins: a stack does not join another.)
local function stack_for(data, skip_id)
    if type(data) ~= "table" or data.active then return nil end
    if type(data.extra) == "string" and data.extra ~= "" then return nil end
    local key = stack_key(data)
    for _, entry in ipairs(bags()) do
        if entry.instance_id ~= skip_id and not entry.data.active and entry.amount < bag_limit(entry.data)
            and stack_key(entry.data) == key then
            return entry
        end
    end
    return nil
end
Loot._StackFor = stack_for

-- The edit that puts one bag (its data) onto a stack: one more, its roll
-- at the end of the stack's list.
local function join_spec(target, data)
    local L = lq()
    local roll = L and L.EncodeRoll(L.InfoOf(data) or { quality = 1, mods = {} }) or "1:"
    local extra = type(target.data.extra) == "string" and target.data.extra or ""
    -- A stack made before 0.35.2 (copies of its own roll): write them down.
    if L and extra == "" and target.amount > 1 then
        local own = L.EncodeRoll(L.InfoOf(target.data))
        local parts = {}
        for _ = 2, target.amount do parts[#parts + 1] = own end
        extra = table.concat(parts, ";")
    end
    extra = extra == "" and roll or (extra .. ";" .. roll)
    return {
        set_amount = { { container = target.container, instance_id = target.instance_id, amount = target.amount + 1 } },
        update = { { container = target.container, instance_id = target.instance_id, data = { extra = extra } } }
    }
end

-- Puts one bag onto a Stackable bag of its loot; true if it did.
function Loot.StackOnto(data)
    local target = stack_for(data)
    if not target then return false end
    local ok = PDTI.EditItems(join_spec(target, data))
    return ok and true or false
end

-- A bag lying on its own rides on a Stackable bag of its loot, if one has
-- room.
function Loot.TryStack(container, instance_id)
    local item = PDTI.FindItem(container, instance_id)
    if not item or item.item_id ~= Loot.ITEM_ID or (tonumber(item.amount) or 1) ~= 1 then return false end
    local target = stack_for(item.data, instance_id)
    if not target then return false end
    local spec = join_spec(target, item.data)
    spec.remove = { { container = container, instance_id = instance_id } }
    local ok = PDTI.EditItems(spec)
    return ok and true or false
end

-- A Stackable bag gathers the single bags of its loot lying in the
-- inventory, while it has room. Returns how many joined it.
function Loot.Gather()
    local n = 0
    for _ = 1, 64 do
        local moved = false
        for _, entry in ipairs(bags()) do
            if not entry.data.active and entry.amount == 1
                and not (type(entry.data.extra) == "string" and entry.data.extra ~= "")
                and Loot.TryStack(entry.container, entry.instance_id) then
                n, moved = n + 1, true
                break
            end
        end
        if not moved then break end
    end
    return n
end

-- The data of the bag that leaves a stack (the last one on it) and the
-- stack's list without it.
local function pop_spec(entry)
    local L = lq()
    local d = entry.data
    local single = {}
    for k, v in pairs(d) do single[k] = v end
    single.extra = nil
    local rolls = L and L.StackRolls(d, entry.amount) or {}
    local last = rolls[#rolls]
    if L and last and #rolls > 1 then L.Apply(single, last) end
    local rest = {}
    if L then
        for i = 2, #rolls - 1 do rest[#rest + 1] = L.EncodeRoll(rolls[i]) end
    end
    return single, table.concat(rest, ";")
end
Loot._PopSpec = pop_spec

-- Takes loot bags out of the inventory (the last ones on a stack first).
function Loot.Remove(amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local remaining = amount
    for _, entry in ipairs(bags()) do
        while remaining > 0 and entry.amount > 1 do
            local _, rest = pop_spec(entry)
            local ok = PDTI.EditItems({
                set_amount = { { container = entry.container, instance_id = entry.instance_id, amount = entry.amount - 1 } },
                update = { { container = entry.container, instance_id = entry.instance_id, data = { extra = rest } } }
            })
            if not ok then break end
            entry.amount = entry.amount - 1
            entry.data.extra = rest
            remaining = remaining - 1
        end
        if remaining > 0 and entry.amount == 1 then
            if PDTI.RemoveItem(entry.container, entry.instance_id, 1) then remaining = remaining - 1 end
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

    local ok, carry_id = pcall(pm.current_carry_id, pm)
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
-- rolled: the bag's data with its roll already made (it is not rolled again).
function Loot.StashCarried(rolled)
    if not Loot.MultiAllowed() then return false, "only the host can carry more than one bag" end
    local data = Loot.CarriedData()
    if not data then return false, "you carry no loot bag" end

    local stored = {}
    for k, v in pairs(rolled or data) do stored[k] = v end
    stored.active = false

    local active = active_entry()
    local ok, reason
    if active then
        ok, reason = PDTI.EditItems({ update = {
            { container = active.container, instance_id = active.instance_id, data = stored }
        } })
        if ok then
            Loot.TryStack(active.container, active.instance_id)
            Loot.Gather()
        end
    else
        local LQ = PDTI.LootQuality
        if LQ then LQ.Stamp(stored) end
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
    -- A bag from a stack: the last one on it takes a place of its own in
    -- your hands, with its own roll.
    if (tonumber(entry.amount) or 1) > 1 then
        local single, rest = pop_spec(entry)
        single.active = true
        d = single
        local placed = false
        for _, name in ipairs(Loot.CONTAINERS) do
            if PDTI.AddItemAuto(name, Loot.ITEM_ID, 1, single, true) then placed = true break end
        end
        if not placed then return false, "no room to take a bag off the stack" end
        local split = PDTI.EditItems({
            set_amount = { { container = entry.container, instance_id = entry.instance_id, amount = entry.amount - 1 } },
            update = { { container = entry.container, instance_id = entry.instance_id, data = { extra = rest } } }
        })
        if not split then
            local hands = active_entry()
            if hands then PDTI.RemoveItem(hands.container, hands.instance_id) end
            return false, "could not take a bag off the stack"
        end
        entry = active_entry()
        if not entry then return false, "could not take a bag off the stack" end
    end
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

Loot._hooks = Loot._hooks or {}
local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(Loot._hooks, "loot", class_name, fn_name, make)
end

-- The carry id of the bag lying in the world.
local function world_carry_id(ext)
    local cd = ext and PDTI.CarryExt(ext._unit)
    local ok, id = false, nil
    if cd and type(cd.carry_id) == "function" then ok, id = pcall(cd.carry_id, cd) end
    if ok and type(id) == "string" then return id end
    return ext and ext._carry_id or nil
end

local function game_blocks(ext)
    local blocked = false
    local cd = ext and PDTI.CarryExt(ext._unit)
    pcall(function()
        blocked = managers.player:carry_blocked_by_cooldown()
            or (cd ~= nil and cd:is_attached_to_zipline_unit())
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
local function can_swap(ext)
    if not Loot.MultiAllowed() then return false end
    if not Loot.CarriedId() then return false end
    return Loot.RoomForPickup() or (ext ~= nil and Loot.WouldStack(ext))
end

local last_hint = nil
local function hint_no_room()
    local t = now()
    if last_hint and t - last_hint < Loot.HINT_INTERVAL then return end
    last_hint = t
    log("no room in the inventory for another loot bag")
    PDTI.Hint("No room for the bag: make room in the rig or the backpack", 2)
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
    if not Loot.RoomForPickup() and not Loot.WouldStack(ext) then return "room" end
    return nil
end

-- The bag lying there as the inventory would hold it (its roll from the
-- level), or nil.
function Loot.WorldBagData(ext)
    local cd = ext and PDTI.CarryExt(ext._unit)
    local info = cd and cd._pdti_quality
    if type(info) ~= "table" then return nil end
    local data = { carry_id = world_carry_id(ext), multiplier = 1 }
    for _, key in ipairs({ "multiplier", "dye_initiated", "has_dye_pack", "dye_value_multiplier" }) do
        local fn = cd[key]
        if type(fn) == "function" then
            local ok, v = pcall(fn, cd)
            if ok and v ~= nil then data[key] = v end
        end
    end
    local LQ = PDTI.LootQuality
    if LQ then LQ.Apply(data, info) end
    data.active = false
    return data
end

-- Would that bag join a stack you have (a Stackable bag like it)?
-- Not while you carry a bag that has no place of its own.
function Loot.WouldStack(ext)
    if Loot.CarriedId() and not active_entry() then return false end
    local data = Loot.WorldBagData(ext)
    return data ~= nil and stack_for(data) ~= nil
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
                if can_swap(self) then return not can_carry(carry_id) end
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
            if can_swap(self) then
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
    local LQ = PDTI.LootQuality
    if LQ then pcall(LQ.InstallHooks) end
    if PDTI.Stash then pcall(PDTI.Stash.InstallHooks) end
    if PDTI.Armory then pcall(PDTI.Armory.InstallHooks) end
    -- The safehouse is not a heist: no loot is followed there.
    if PDTI.InSafehouse() then return end

    local carried = Loot.CarriedData()
    local active = active_entry()

    if carried then
        runtime.pull_until = nil
        runtime.drop_by_ui = nil
        if not active then
            local data = {}
            for k, v in pairs(carried) do data[k] = v end
            data.active = true
            if LQ then LQ.Stamp(data) end
            local ok, reason = Loot.Add(1, data)
            -- No place for it, but a stack of the same Stackable bags has
            -- room: it goes straight onto the stack, your hands are free.
            if not ok then
                local onto = {}
                for k, v in pairs(data) do onto[k] = v end
                onto.active = false
                local target = stack_for(onto)
                if target and Loot.StashCarried(onto) then
                    ok = true
                    log(string.format("the bag went onto a Stackable bag (%d of %d)", target.amount + 1,
                        bag_limit(target.data)))
                end
            end
            if not ok and runtime.failed_carry ~= carried.carry_id then
                runtime.failed_carry = carried.carry_id
                log("no room for the bag you carry: " .. tostring(reason))
            elseif ok then
                runtime.failed_carry = nil
            end
        elseif active.data.carry_id ~= carried.carry_id then
            local data = {}
            for k, v in pairs(carried) do data[k] = v end
            -- Another bag in your hands: its own roll, nothing of the old one
            -- (the update merges, so cleared fields are written as false).
            if LQ then LQ.Stamp(data) end
            for _, key in ipairs(Loot.QUALITY_FIELDS) do
                if data[key] == nil then data[key] = false end
            end
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
    if PDTI.LootQuality and PDTI.LootQuality.Reset then pcall(PDTI.LootQuality.Reset) end
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
