-- UI interaction state only. The actual Payday 2 GUI renderer is a separate
-- layer; this controller gives it safe, testable commands and view snapshots.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local ui = {
    visible = false,
    selected_container = "backpack",
    selected_instance_id = nil,
    revision = 0,
    last_error = nil
}

local function refresh()
    ui.revision = ui.revision + 1
    return PDTI.GetInventoryViewModel()
end

function PDTI.GetUIState()
    local model = PDTI.GetInventoryViewModel()
    return {
        visible = ui.visible,
        selected_container = ui.selected_container,
        selected_instance_id = ui.selected_instance_id,
        revision = ui.revision,
        last_error = ui.last_error,
        model = model
    }
end

function PDTI.SetUIVisible(visible)
    ui.visible = visible == true
    refresh()
    return true
end

function PDTI.SelectContainer(name)
    if not (name == "pockets" or name == "backpack" or (PDTI.IsRigSection and PDTI.IsRigSection(name))) then
        return false, "unknown container"
    end
    ui.selected_container = name
    ui.selected_instance_id = nil
    ui.last_error = nil
    refresh()
    return true
end

function PDTI.SelectItem(instance_id)
    local item = PDTI.FindItem(ui.selected_container, instance_id)
    if not item then return false, "item not found" end
    ui.selected_instance_id = instance_id
    ui.last_error = nil
    refresh()
    return true, item
end

function PDTI.RequestMove(from_name, instance_id, to_name, x, y, rotated)
    local ok, result, detail = PDTI.MoveItem(from_name, instance_id, to_name, x, y, rotated)
    if not ok then
        ui.last_error = result
        return false, result
    end
    ui.selected_container = to_name
    ui.selected_instance_id = instance_id
    ui.last_error = nil
    refresh()
    return true, result
end

function PDTI.RequestRotate(container_name, instance_id)
    local item = PDTI.FindItem(container_name, instance_id)
    if not item then return false, "item not found" end
    return PDTI.RequestMove(
        container_name, instance_id, container_name,
        item.x, item.y, not item.rotated
    )
end

-- True while you are in a heist (the player is spawned).
-- In a heist: the player is spawned, or the heist has loaded (the briefing
-- counts too: nothing is saved there either).
function PDTI.InHeist()
    if PDTI.session_only then return true end
    local ok, unit = pcall(function() return managers.player:player_unit() end)
    return ok and unit ~= nil
end

-- The backpack and the rig are chosen in the menu, before the heist.
function PDTI.RequestEquip(kind, equipment_id)
    if PDTI.InHeist() then
        ui.last_error = "The rig and the backpack are chosen in the menu"
        return false, ui.last_error
    end
    local ok, reason = PDTI.SetEquipment(kind, equipment_id)
    if not ok then
        ui.last_error = reason
        return false, reason
    end
    ui.last_error = nil
    refresh()
    return true
end

function PDTI.RequestAutoArrange(container_name, allow_rotation)
    local ok, reason = PDTI.AutoArrange(container_name, allow_rotation)
    if not ok then
        ui.last_error = reason
        return false, reason
    end
    ui.last_error = nil
    refresh()
    return true
end

function PDTI.RefreshUI()
    ui.last_error = nil
    return refresh()
end
