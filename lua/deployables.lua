-- Deployables.
--
-- Two things happen here:
--
--   * How many deployables you can place follows what you carry. The rig and
--     the pockets are what is "to hand": three ammo bags in the rig means
--     three ammo bags you can place, and a bag that lies in the backpack is
--     not to hand at all.
--   * You pick the deployable yourself. In the inventory screen you hold an
--     item and press the deployable key to make it your deployable; outside
--     the screen the same key places it.
--
-- The placement itself is the game's own code: the matching
-- PlayerEquipment:use_* function is called, so the placement raycast, the
-- unit that is spawned and the game statistics all keep working.
--
-- One detail of the game matters here. The placement functions call
-- PlayerEquipment:valid_shape_placement with only the equipment id, but that
-- function needs the equipment data to create its placement dummy. The game
-- creates the dummy earlier, while it checks whether the placement is valid;
-- when the function is called directly, the dummy does not exist yet and the
-- placement fails with an error. So the dummy is primed here first.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Dep = PDTI.Deployables or {}
PDTI.Deployables = Dep
if Dep.enabled == nil then Dep.enabled = true end

-- The key that places the selected deployable. It is the key the game uses
-- for "Deploy Equipment" (G by default).
Dep.KEY = "g"

-- PlayerEquipment placement function -> inventory item
Dep.MAP = {
    use_doctor_bag = "doctor_bag",
    use_ammo_bag = "ammo_bag",
    use_first_aid_kit = "first_aid_kit",
    use_bodybags_bag = "bodybags_bag"
}

-- Only the pockets and the rig are "to hand", searched in this order (every
-- section of the rig in turn). A deployable in the backpack is carried, but
-- it cannot be placed.
Dep.CARRIED = { "pockets", "rig", "rig_2", "rig_3" }

-- The key that picks the next deployable you carry.
Dep.CYCLE_KEY = "x"

-- The pick "the game's own equipment" (a sentry gun, a trip mine you
-- brought): the cycle offers it after the inventory's deployables.
Dep.GAME = "__game__"


local log = PDTI.Logger("PDTI DEPLOY")

local hint = PDTI.Hint

-- The placement function of an item, from its definition.
function Dep.Method(item_id)
    local def = PDTI.GetItemDefinition(item_id)
    if def and type(def.deploy_method) == "string" then return def.deploy_method end
    for fn_name, mapped in pairs(Dep.MAP) do
        if mapped == item_id then return fn_name end
    end
    return nil
end

-- The equipment id of the game for an item ("ammo_bag" and so on).
function Dep.EquipmentId(item_id)
    local def = PDTI.GetItemDefinition(item_id)
    if def and type(def.deployable_id) == "string" then return def.deployable_id end
    for _, mapped in pairs(Dep.MAP) do
        if mapped == item_id then return item_id end
    end
    return item_id
end

-- Is this game equipment id one the inventory manages (an item places it)?
function Dep.ManagedEquipment(equipment_id)
    if not equipment_id then return false end
    for id, def in pairs(PDTI.GetItemDefinitions()) do
        if def.deployable and Dep.EquipmentId(id) == equipment_id then return true end
    end
    return false
end

-- How the game checks where it goes: "look" (on a wall or the floor in
-- front: trip mines, ECMs, spy cameras), "none" (used on yourself: the armor
-- kit) or "shape" (put down like a bag).
Dep.LOOK = { trip_mine = true, ecm_jammer = true, spy_camera = true }
Dep.NO_PLACEMENT = { armor_kit = true }
function Dep.PlacementKind(item_id)
    local def = PDTI.GetItemDefinition(item_id)
    if def and def.placement == "look" then return "look" end
    if def and def.placement == "none" then return "none" end
    local equipment_id = Dep.EquipmentId(item_id)
    if Dep.LOOK[equipment_id] then return "look" end
    if Dep.NO_PLACEMENT[equipment_id] then return "none" end
    return "shape"
end

-- Is the spot in front valid for the item (the game's own check)?
function Dep.ValidPlacement(equipment, item_id)
    local equipment_id = Dep.EquipmentId(item_id)
    local data = tweak_data.equipments and tweak_data.equipments[equipment_id]
    local kind = Dep.PlacementKind(item_id)
    if kind == "none" then return true end
    if not equipment or not data then return false end
    local ok, valid
    if kind == "look" then
        ok, valid = pcall(equipment.valid_look_at_placement, equipment, data)
    else
        ok, valid = pcall(equipment.valid_shape_placement, equipment, equipment_id, data)
    end
    return ok and valid and true or false
end

-- Every item that can be selected as a deployable.
function Dep.GetOptions()
    local out = {}
    for id, def in pairs(PDTI.GetItemDefinitions()) do
        if def.deployable then
            out[#out + 1] = {
                item_id = id,
                name = def.name or id,
                count = Dep.Count(id),
                method = Dep.Method(id)
            }
        end
    end
    table.sort(out, function(a, b) return a.item_id < b.item_id end)
    return out
end

-- How many of an item are to hand.
function Dep.Count(item_id)
    if not item_id then return 0 end
    local total = 0
    for _, name in ipairs(Dep.CARRIED) do
        for _, item in ipairs(PDTI.GetContainer(name).items) do
            if item.item_id == item_id then
                total = total + math.max(1, math.floor(tonumber(item.amount) or 1))
            end
        end
    end
    return total
end

-- The first stack of an item that is to hand.
function Dep.Find(item_id)
    for _, name in ipairs(Dep.CARRIED) do
        for _, item in ipairs(PDTI.GetContainer(name).items) do
            if item.item_id == item_id then return name, item.instance_id end
        end
    end
    return nil
end

-- The items of a container in reading order: top row first, left to right.
local function reading_order(name)
    local list = {}
    for _, item in ipairs(PDTI.GetContainer(name).items) do list[#list + 1] = item end
    table.sort(list, function(a, b)
        local ay, by = tonumber(a.y) or 0, tonumber(b.y) or 0
        if ay ~= by then return ay < by end
        return (tonumber(a.x) or 0) < (tonumber(b.x) or 0)
    end)
    return list
end

-- The kinds of deployable to hand, in the order they are found: the pockets
-- first, then the rig, each read from the top left.
function Dep.ToHand()
    local out, seen = {}, {}
    for _, name in ipairs(Dep.CARRIED) do
        for _, item in ipairs(reading_order(name)) do
            local id = item.item_id
            if not seen[id] then
                local def = PDTI.GetItemDefinition(id)
                if def and def.deployable then
                    seen[id] = true
                    out[#out + 1] = id
                end
            end
        end
    end
    return out
end

-- The equipment the game would place itself, when it is not one of the
-- deployables the inventory manages (a sentry gun, a trip mine).
function Dep.GameEquipment()
    local pm = managers and managers.player
    local eq = pm and pm._equipment
    local entry = eq and eq.selections and eq.selections[eq.selected_index]
    if not entry or not entry.equipment then return nil end
    if Dep.ManagedEquipment(entry.equipment) then return nil end
    local amount = entry.amount and entry.amount[1]
    if amount ~= nil and Application and Application.digest_value then
        local ok, n = pcall(function() return Application:digest_value(amount, false) end)
        if ok and type(n) == "number" and n < 1 then return nil end
    end
    return entry
end

-- The game's selected equipment when it is one of the kinds the inventory
-- manages (the ammo bag you brought).
function Dep.GameManagedEquipment()
    local pm = managers and managers.player
    local eq = pm and pm._equipment
    local entry = eq and eq.selections and eq.selections[eq.selected_index]
    if not entry or not entry.equipment then return nil end
    if Dep.ManagedEquipment(entry.equipment) then return entry end
    return nil
end

-- The deployable you picked yourself (nil: the first one found is used).
function Dep.GetManual()
    if Dep.game_pick then return Dep.GAME end
    return PDTI.GetDeployable and PDTI.GetDeployable() or nil
end

-- The deployable G places: the one you picked while you carry it, else the
-- first one found in the pockets and the rig. nil while you carry none (or
-- picked the game's own equipment).
function Dep.GetSelection()
    if not Dep.enabled then return nil end
    if Dep.game_pick then
        if Dep.GameEquipment() then return nil end
        Dep.game_pick = false
    end
    local manual = PDTI.GetDeployable and PDTI.GetDeployable()
    if manual and Dep.Count(manual) > 0 then return manual end
    return Dep.ToHand()[1]
end

-- Picks the deployable yourself. Only items that are a deployable can be
-- picked; Dep.GAME picks the game's own equipment; nil goes back to the
-- first one found.
function Dep.SetSelection(item_id)
    if item_id == Dep.GAME then
        if not Dep.GameEquipment() then return false, "You brought no other equipment" end
        Dep.game_pick = true
        Dep.Changed()
        return true
    end
    local ok, reason = PDTI.SetDeployable(item_id)
    if not ok then return false, reason end
    Dep.game_pick = false
    Dep.Changed()
    return true
end

-- A new heist: nothing is picked, the first one found is placed.
function Dep.OnHeistStart()
    if PDTI.InSafehouse() then return end
    Dep.game_pick = false
    if PDTI.GetDeployable and PDTI.GetDeployable() then pcall(PDTI.SetDeployable, nil) end
end

-- What the X key goes through: the kinds to hand, then the game's own
-- equipment if you brought something the inventory does not manage.
function Dep.CycleList()
    local list = Dep.ToHand()
    if Dep.GameEquipment() then list[#list + 1] = Dep.GAME end
    return list
end

-- The X key: the next kind you carry, back to the first after the last.
-- Returns the new pick (nil when there is nothing to pick).
function Dep.Cycle()
    if not Dep.enabled then return nil end
    local list = Dep.CycleList()
    if #list == 0 then return nil end
    local current = Dep.GetSelection() or (Dep.game_pick and Dep.GAME) or nil
    if current == nil and Dep.GameEquipment() and #Dep.ToHand() == 0 then current = Dep.GAME end
    local index = 0
    for i, id in ipairs(list) do
        if id == current then index = i break end
    end
    local next_id = list[index % #list + 1]
    local ok = Dep.SetSelection(next_id)
    if not ok then return nil end
    return next_id
end

-- The name of what G places now, for the HUD and the hints.
function Dep.DisplayName()
    local selection = Dep.GetSelection()
    if selection then
        local def = PDTI.GetItemDefinition(selection)
        return (def and def.name or selection) .. " x" .. tostring(Dep.Count(selection))
    end
    local game = Dep.GameEquipment()
    if game then
        local name = tostring(game.equipment)
        pcall(function()
            local data = tweak_data.equipments[game.equipment]
            if data and data.text_id then name = managers.localization:text(data.text_id) end
        end)
        return name .. " (brought)"
    end
    return "none"
end

-- Something about the pick changed: the HUD and the screen show it.
function Dep.Changed()
    Dep.revision = (Dep.revision or 0) + 1
    if PDTI.DeployHud and PDTI.DeployHud.Update then pcall(PDTI.DeployHud.Update, true) end
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
end

-- True while the inventory places the deployable: you carry one.
function Dep.Manages()
    -- In the safehouse nothing of the inventory is placed or used up.
    if not Dep.enabled or PDTI.InSafehouse() then return false end
    return Dep.GetSelection() ~= nil
end

-- True when the game's own deployable must not be placed: it is one of the
-- kinds the inventory manages (you brought an ammo bag), but there is none in
-- your rig or pockets. What you place is what you carry.
function Dep.BlocksGame()
    if not Dep.enabled or PDTI.InSafehouse() then return false end
    if Dep.Manages() then return false end
    return Dep.GameManagedEquipment() ~= nil
end

-- The game's equipment object of the player.
local function player_equipment()
    local manager = managers and managers.player
    if not manager then return nil end
    local unit = manager:player_unit()
    if not unit then return nil end
    if _G.alive and not alive(unit) then return nil end
    local ok, equipment = pcall(function() return unit:equipment() end)
    if ok and equipment then return equipment end
    return nil
end

-- The equipment entry of the game, shaped like the entries of the vanilla
-- equipment (equipment, amount, use_function, icon, unit). The game uses it
-- for the deploy timer, the placement check and the HUD.
function Dep.SyntheticEntry()
    if not Dep.Manages() then return nil end
    local selection = Dep.GetSelection()
    local count = Dep.Count(selection)
    if count < 1 then return nil end

    local equipment_id = Dep.EquipmentId(selection)
    local data = tweak_data.equipments and tweak_data.equipments[equipment_id]
    if not data then return nil end

    local amount = { count }
    if Application and Application.digest_value then
        local ok, digested = pcall(function() return Application:digest_value(count, true) end)
        if ok and digested then amount[1] = digested end
    end

    return {
        equipment = equipment_id,
        amount = amount,
        use_function = Dep.Method(selection),
        action_timer = data.action_timer,
        icon = data.icon,
        unit = data.unit,
        on_use_callback = data.on_use_callback,
        pdti_item = selection
    }
end

-- Calls the placement function of the game for an item.
-- Returns true when something was placed, the redirect of the game and, when
-- it failed, the reason.
function Dep.RunPlacement(equipment, item_id)
    local method = Dep.Method(item_id)
    if not method then return false, nil, "no placement function" end

    local fn = equipment[method]
    if type(fn) ~= "function" then
        return false, nil, "the game has no placement function '" .. tostring(method) .. "'"
    end

    -- The game creates its placement dummy while it checks the placement.
    -- The placement functions do not pass the equipment data, so the dummy
    -- has to exist before they are called.
    local equipment_id = Dep.EquipmentId(item_id)
    local data = tweak_data.equipments and tweak_data.equipments[equipment_id]
    if data then Dep.ValidPlacement(equipment, item_id) end

    -- As the game calls it: the selected slot and the unit index (the sentry
    -- gun uses them: 1 the normal sentry, 2 the suppressed one).
    local selected_index = nil
    pcall(function() selected_index = managers.player._equipment.selected_index end)
    local ok, used, redirect = pcall(fn, equipment, selected_index, data and data.unit)
    if not ok then
        return false, nil, "placement failed: " .. tostring(used)
    end
    -- A client asks the host for a sentry gun and gets the answer later
    -- (Dep.OnSentryPlaced): the item is taken out then.
    if not used and method == "use_sentry_gun" and equipment._sentrygun_placement_requested then
        Dep.pending_sentry = item_id
        return false, nil, nil, true
    end
    return (used ~= nil and used ~= false), redirect, nil
end

-- An item to hand (rig or pockets) that is this game equipment (a trip mine
-- for "trip_mine"), or nil. Used where the game asks for a deployable
-- without placing it: a trip mine set as a shaped charge on a safe.
function Dep.ItemToHandFor(equipment_id)
    if not Dep.enabled or type(equipment_id) ~= "string" or PDTI.InSafehouse() then return nil end
    local found = nil
    for id, def in pairs(PDTI.GetItemDefinitions()) do
        if def.deployable and Dep.EquipmentId(id) == equipment_id and Dep.Count(id) > 0 then
            if not found or id < found then found = id end
        end
    end
    return found
end

-- The game's own count of an equipment (0 when it was not brought).
function Dep.GameCount(equipment_id, slot)
    local pm = managers and managers.player
    local eq = pm and pm._equipment
    if not eq or type(eq.selections) ~= "table" then return 0 end
    for _, entry in ipairs(eq.selections) do
        if entry.equipment == equipment_id and type(entry.amount) == "table" then
            local amount = entry.amount[slot or 1]
            if amount == nil then return 0 end
            local n = amount
            if Application and Application.digest_value then
                local ok, v = pcall(function() return Application:digest_value(amount, false) end)
                if ok then n = v end
            end
            return tonumber(n) or 0
        end
    end
    return 0
end

-- The item that places a game equipment id ("sentry_gun" -> "sentry_gun").
function Dep.ItemFor(equipment_id)
    local found = nil
    for id, def in pairs(PDTI.GetItemDefinitions()) do
        if def.deployable and Dep.EquipmentId(id) == equipment_id then
            if not found or id < found then found = id end
        end
    end
    return found
end

-- Where a picked-up deployable goes: to hand first, then the backpack.
Dep.STORE = { "rig", "rig_2", "rig_3", "pockets", "backpack" }

function Dep.HasRoomFor(item_id)
    for _, name in ipairs(Dep.STORE) do
        local ok, found = pcall(PDTI.FindFreeSpace, name, { item_id = item_id }, true)
        if ok and found then return true end
    end
    return false
end

-- Puts a deployable back into the inventory (a sentry gun picked up).
function Dep.Store(item_id)
    for _, name in ipairs(Dep.STORE) do
        local ok, placed = pcall(PDTI.AddItemAuto, name, item_id, 1)
        if ok and placed then
            Dep.Changed()
            return true, name
        end
    end
    return false
end

-- A client's sentry gun was placed by the host: its item is taken out now.
function Dep.OnSentryPlaced()
    local item_id = Dep.pending_sentry
    Dep.pending_sentry = nil
    if not item_id then return false end
    Dep.Consume(item_id)
    Dep.Changed()
    return true
end

-- The game's sentry gun picked up: it goes back into the inventory (true),
-- or false when it is not one the inventory manages.
function Dep.OnSentryPickedUp(sentry_type)
    if not Dep.enabled then return false end
    local item_id = Dep.ItemFor(sentry_type)
    if not item_id then return false end
    local ok, where = Dep.Store(item_id)
    if ok then
        local def = PDTI.GetItemDefinition(item_id)
        hint((def and def.name or item_id) .. " put in your " .. tostring(where):gsub("_%d", ""))
        return true
    end
    log("no room for the picked-up " .. tostring(item_id) .. ": it goes to the game's equipment")
    return false
end

-- Hooks on the game's equipment code, installed once the classes exist
-- (called every frame until they are in place).
function Dep.InstallGameHooks()
    if Dep._game_hooks_done then return true end
    local PE, SGB = rawget(_G, "PlayerEquipment"), rawget(_G, "SentryGunBase")
    if not PE or not SGB then return false end

    -- A sentry gun costs no ammunition while the ammunition system runs:
    -- the rounds are inventory items, and the game's cost would be undone
    -- (and its refund on pickup would be free rounds).
    if type(PE._sentry_gun_ammo_cost) == "function" and not PE._pdti_ammo_cost then
        local original = PE._sentry_gun_ammo_cost
        PE._pdti_ammo_cost = original
        PE._sentry_gun_ammo_cost = function(self, ...)
            local ammo = PDTI.Ammo
            if Dep.enabled and ammo and ammo.settings and ammo.settings.enabled then return end
            return original(self, ...)
        end
    end

    -- Picking a sentry gun up: refused when there is no room for it.
    if type(SGB.on_interaction) == "function" and not SGB._pdti_on_interaction then
        local original = SGB.on_interaction
        SGB._pdti_on_interaction = original
        SGB.on_interaction = function(self, ...)
            local ok, sentry_type = pcall(function() return self:get_type() end)
            local item_id = ok and Dep.enabled and Dep.ItemFor(sentry_type)
            if item_id and not Dep.HasRoomFor(item_id) then
                local def = PDTI.GetItemDefinition(item_id)
                hint("No room for the " .. (def and def.name or item_id))
                return
            end
            return original(self, ...)
        end
    end

    Dep._game_hooks_done = true
    return true
end

-- Takes one item out of the inventory.
function Dep.Consume(item_id)
    local container, instance_id = Dep.Find(item_id)
    if not container then return false, "not to hand" end
    local ok, reason = PDTI.RemoveItem(container, instance_id, 1)
    if not ok then
        log("could not consume " .. tostring(item_id) .. ": " .. tostring(reason))
        return false, reason
    end
    if PDTI.IsUIOpen and PDTI.IsUIOpen() then pcall(PDTI.RedrawUI) end
    return true
end

-- Places the selected deployable. Returns true when something was placed and
-- the redirect of the game.
function Dep.Place(equipment)
    if not Dep.enabled or PDTI.InSafehouse() then return false end

    local selection = Dep.GetSelection()
    if not selection then
        -- Nothing was picked: the game places its own deployable.
        return false
    end

    local count = Dep.Count(selection)
    if count < 1 then
        local def = PDTI.GetItemDefinition(selection)
        hint("No " .. (def and def.name or selection) .. " in your rig or pockets")
        Dep.Changed()
        return false
    end

    equipment = equipment or player_equipment()
    if not equipment then
        log("the player has no equipment object")
        return false
    end

    -- An ammo bag with fewer uses (a Spoils drop): the bag that appears gets them.
    local skills = PDTI.AmmoSkills
    if selection == "ammo_bag" and skills and skills.OnBagDeploy then
        local c, iid = Dep.Find(selection)
        local item = c and PDTI.FindItem(c, iid)
        pcall(skills.OnBagDeploy, item and item.data, c)
    end
    local placed, redirect, err, pending = Dep.RunPlacement(equipment, selection)
    if pending then return false, nil end
    if not placed and skills and skills.OnBagDeploy and selection == "ammo_bag" then
        pcall(skills.OnBagDeploy, nil)
    end
    if not placed then
        if err then log(err) end
        return false, nil
    end

    local consumed, why = Dep.Consume(selection)
    if not consumed then
        log("could not take the item out of the inventory: " .. tostring(why))
    end
    -- Dallas' room: a doctor bag you place gives the self-revive back.
    if selection == "doctor_bag" and PDTI.Gear and PDTI.Gear.OnDoctorBagPlaced then
        pcall(PDTI.Gear.OnDoctorBagPlaced)
    end
    -- The pick is used up: the next one found becomes the deployable.
    if PDTI.GetDeployable and PDTI.GetDeployable() == selection and Dep.Count(selection) < 1 then
        pcall(PDTI.SetDeployable, nil)
    end
    Dep.Changed()

    if PDTI.IsUIOpen and PDTI.IsUIOpen() then pcall(PDTI.RedrawUI) end
    return true, redirect
end

-- The key that places the deployable. Inside the inventory screen it picks
-- the deployable that is held, outside it asks the game to place it.
function Dep.OnKey()
    if PDTI.IsUIOpen and PDTI.IsUIOpen() then
        if PDTI.UISelectDeployable then
            PDTI.UISelectDeployable()
            if PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
        end
        return
    end

    -- The game places the deployable: the player kneels down, the timer of the
    -- game runs and the item appears. The mod only asks the game to start that
    -- action, so the placement takes the same time as in the game.
    if Dep.ShouldPlaceOurs() then
        PDTI._deploy_request = true
        PDTI._deploy_request_t = Dep.Now()
    end
end

-- The time of the game, used to throw away a request that was never handled.
function Dep.Now()
    local manager = managers and managers.player
    if manager and manager.player_timer then
        local ok, timer = pcall(function() return manager:player_timer() end)
        if ok and timer and timer.time then
            local ok2, now = pcall(function() return timer:time() end)
            if ok2 and type(now) == "number" then return now end
        end
    end
    return 0
end

-- True when this key press places the deployable of the inventory: you
-- carry one and did not pick the game's own equipment.
function Dep.ShouldPlaceOurs()
    if not Dep.enabled then return false end
    if not Dep.HasKeyTrigger() then return false end
    return Dep.Manages()
end

-- Registers the key with BeardLib. Called every frame until it works, so it
-- does not matter whether BeardLib is loaded before or after this mod.
function Dep.EnsureKeyTrigger()
    Dep.EnsureCycleTrigger()
    if PDTI._deploy_key_trigger then return true end
    local beardlib = rawget(_G, "BeardLib")
    if not (beardlib and beardlib.Utils and beardlib.Utils.Input) then return false end
    local ok, result = pcall(function()
        return beardlib.Utils.Input:Trigger(Dep.KEY, function() Dep.OnKey() end)
    end)
    if ok and result then
        PDTI._deploy_key_trigger = result
        log("deployable key '" .. Dep.KEY .. "' registered")
        return true
    end
    return false
end

-- The X key. Not while you type in the chat.
local function typing()
    local ok, focus = pcall(function() return managers.hud and managers.hud._chat_focus end)
    return ok and focus and true or false
end

function Dep.OnCycleKey()
    if typing() then return end
    local in_heist = false
    pcall(function() in_heist = managers.player:player_unit() ~= nil end)
    if not in_heist and not (PDTI.IsUIOpen and PDTI.IsUIOpen()) then return end
    Dep.Cycle()
end

function Dep.EnsureCycleTrigger()
    if PDTI._cycle_key_trigger then return true end
    local beardlib = rawget(_G, "BeardLib")
    if not (beardlib and beardlib.Utils and beardlib.Utils.Input) then return false end
    local ok, result = pcall(function()
        return beardlib.Utils.Input:Trigger(Dep.CYCLE_KEY, function() Dep.OnCycleKey() end)
    end)
    if ok and result then
        PDTI._cycle_key_trigger = result
        log("deployable cycle key '" .. Dep.CYCLE_KEY .. "' registered")
        return true
    end
    return false
end

function Dep.HasKeyTrigger()
    return PDTI._deploy_key_trigger ~= nil
end
