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

local reported = {}

local function log(message)
    local line = "[PDTI DEPLOY] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function hint(text)
    pcall(function() managers.hud:show_hint({ text = text }) end)
end

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
    for _, item_id in pairs(Dep.MAP) do
        if entry.equipment == Dep.EquipmentId(item_id) then return nil end
    end
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
    for _, item_id in pairs(Dep.MAP) do
        if entry.equipment == Dep.EquipmentId(item_id) then return entry end
    end
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
    if not Dep.enabled then return false end
    return Dep.GetSelection() ~= nil
end

-- True when the game's own deployable must not be placed: it is one of the
-- kinds the inventory manages (you brought an ammo bag), but there is none in
-- your rig or pockets. What you place is what you carry.
function Dep.BlocksGame()
    if not Dep.enabled then return false end
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
    if data and type(equipment.valid_shape_placement) == "function" then
        pcall(function() equipment:valid_shape_placement(equipment_id, data) end)
    end

    local ok, used, redirect = pcall(fn, equipment)
    if not ok then
        return false, nil, "placement failed: " .. tostring(used)
    end
    return (used ~= nil and used ~= false), redirect, nil
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
    if not Dep.enabled then return false end

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

    local placed, redirect, err = Dep.RunPlacement(equipment, selection)
    if not placed then
        if err then log(err) end
        return false, nil
    end

    local consumed, why = Dep.Consume(selection)
    if not consumed then
        log("could not take the item out of the inventory: " .. tostring(why))
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

-- True when the game's own deploy action must not start, because the
-- inventory places the deployable itself. One key press never places two
-- things.
function Dep.SuppressVanillaDeploy()
    return false
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
