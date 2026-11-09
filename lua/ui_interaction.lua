-- Renderer-independent "held item" interaction for the inventory screen.
-- Click-to-pick-up / click-to-place with rotation. All writes go through the
-- validated PDTI.RequestMove API, so an invalid placement can never change
-- the inventory, and nothing here touches saved state directly.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local held = nil
local status = nil
-- The item being dragged: where it was grabbed (see "drag and drop").
local drag = nil

local function describe(h)
    local def = PDTI.GetItemDefinition(h.item_id)
    return (def and def.name or h.item_id) .. (h.rotated and " (rotated)" or "")
end

function PDTI.UIGetHeld()
    if not held then return nil end
    return {
        container = held.container, instance_id = held.instance_id,
        item_id = held.item_id, rotated = held.rotated
    }
end

function PDTI.UIPickUp(container_name, instance_id)
    local item = PDTI.FindItem(container_name, instance_id)
    if not item then
        status = "Item not found"
        return false, status
    end
    held = {
        container = container_name, instance_id = instance_id,
        item_id = item.item_id, rotated = item.rotated == true
    }
    status = nil
    PDTI.SelectContainer(container_name)
    PDTI.SelectItem(instance_id)
    return true
end

function PDTI.UICancelHeld()
    held, status, drag = nil, nil, nil
    return true
end

function PDTI.UIRotateHeld()
    if not held then
        status = "Pick up an item first"
        return false, status
    end
    held.rotated = not held.rotated
    status = nil
    return true
end

-- A click on a grid cell. With nothing held, an occupied cell picks its item
-- up. With an item held, the clicked cell becomes the item's top-left cell.
function PDTI.UICellClick(container_name, x, y)
    if held and not PDTI.FindItem(held.container, held.instance_id) then
        held = nil -- the item vanished (used or removed) while held
    end

    if not held then
        local map = PDTI.GetOccupancyMap(container_name)
        local row = map and map.cells[y + 1]
        local id = row and row[x + 1]
        if id then return PDTI.UIPickUp(container_name, id) end
        status = nil
        return false, "empty cell"
    end

    local ok, reason = PDTI.RequestMove(
        held.container, held.instance_id, container_name, x, y, held.rotated
    )
    if not ok then
        status = reason
        return false, reason
    end
    held, status = nil, nil
    return true
end

-- Where a Ctrl+click sends an item: from the rig or the pockets into the
-- backpack, from the backpack into the pockets first, then the rig.
local QUICK_TARGETS = {
    pockets = { "backpack" },
    rig = { "backpack" },
    rig_2 = { "backpack" },
    rig_3 = { "backpack" },
    backpack = { "pockets", "rig", "rig_2", "rig_3" },
    -- Out of a weapon's slot: to hand, then the backpack.
    gun_primary = { "pockets", "rig", "rig_2", "rig_3", "backpack" },
    gun_secondary = { "pockets", "rig", "rig_2", "rig_3", "backpack" }
}

-- Moves an item to the first free place of the other side (Ctrl+click).
function PDTI.UIQuickTransfer(container_name, instance_id)
    local item = PDTI.FindItem(container_name, instance_id)
    if not item then
        status = "Item not found"
        return false, status
    end
    local def = PDTI.GetItemDefinition(item.item_id)
    local name = def and def.name or item.item_id
    local last_reason = "no free space"
    for _, target in ipairs(QUICK_TARGETS[container_name] or {}) do
        local x, y, rotated = PDTI.FindFreeSpace(target, item, true)
        if x ~= nil then
            local ok, reason = PDTI.RequestMove(container_name, instance_id, target, x, y, rotated)
            if ok then
                held = nil
                status = "Moved " .. name .. " to the " .. target
                return true, target
            end
            last_reason = reason
        else
            last_reason = y or last_reason
        end
    end
    status = "Cannot move " .. name .. ": " .. tostring(last_reason)
    return false, status
end

-- A Ctrl+click on a grid cell: the item there changes sides.
function PDTI.UICellQuickTransfer(container_name, x, y)
    if held then
        status = "Place the held item first"
        return false, status
    end
    local map = PDTI.GetOccupancyMap(container_name)
    local row = map and map.cells[y + 1]
    local id = row and row[x + 1]
    if not id then return false, "empty cell" end
    return PDTI.UIQuickTransfer(container_name, id)
end

-- Adds one unit of a registered item to the first container that accepts it,
-- trying the selected container first. This is the "stash": without a source
-- of items the grids would always be empty.
function PDTI.UIAddSupply(item_id)
    local def = PDTI.GetItemDefinition(item_id)
    if not def then
        status = "Unknown item"
        return false, status
    end
    local order, seen = {}, {}
    local selected = PDTI.GetUIState().selected_container
    for _, name in ipairs({ selected, "backpack", "rig", "rig_2", "rig_3", "pockets" }) do
        if name and not seen[name] then seen[name] = true; order[#order + 1] = name end
    end
    local last_reason
    for _, name in ipairs(order) do
        local ok, result = PDTI.AddItemAuto(name, item_id, 1, nil, true)
        if ok then
            status = "Added " .. def.name .. " to " .. name
            return true, name, result
        end
        last_reason = result
    end
    status = "Cannot add " .. def.name .. ": " .. tostring(last_reason)
    return false, status
end

-- Permanently removes the held stack from the inventory.
function PDTI.UIDiscardHeld()
    if not held then
        status = "Pick up an item first"
        return false, status
    end
    local def = PDTI.GetItemDefinition(held.item_id)
    -- A loot bag is not thrown away: it is dropped in front of you.
    if held.item_id == "loot_bag" and PDTI.Loot and PDTI.Loot.DropItem then
        local ok, reason = PDTI.Loot.DropItem(held.container, held.instance_id)
        status = ok and "Dropped the loot bag" or reason
        if ok then held = nil end
        return ok, status
    end
    local ok, reason = PDTI.RemoveItem(held.container, held.instance_id)
    if not ok then
        status = reason
        return false, reason
    end
    status = "Discarded " .. (def and def.name or held.item_id)
    held = nil
    return true
end

-- Picks the held item as the deployable. This is what the deployable key
-- does while the inventory screen is open.
function PDTI.UISelectDeployable()
    if not held then
        status = "Pick up a deployable first"
        return false, status
    end
    local def = PDTI.GetItemDefinition(held.item_id)
    if not def or not def.deployable then
        status = (def and def.name or held.item_id) .. " is not a deployable"
        return false, status
    end
    local ok, reason = PDTI.Deployables.SetSelection(held.item_id)
    if not ok then
        status = reason
        return false, reason
    end
    status = def.name .. " is your deployable now"
    return true, status
end

-- Picks a deployable from the list in the side column.
function PDTI.UISelectDeployableById(item_id)
    local def = PDTI.GetItemDefinition(item_id)
    if not def then
        status = "Unknown item"
        return false, status
    end
    if not def.deployable then
        status = def.name .. " is not a deployable"
        return false, status
    end
    local ok, reason = PDTI.Deployables.SetSelection(item_id)
    if not ok then
        status = reason
        return false, reason
    end
    status = def.name .. " is your deployable now"
    return true, status
end

-- Forgets your own pick: the first deployable found is placed again.
function PDTI.UIClearDeployable()
    local ok, reason = PDTI.Deployables.SetSelection(nil)
    if not ok then
        status = reason
        return false, reason
    end
    status = "The first deployable found is placed again"
    return true, status
end

------------------------------------------------------------ drag and drop
--
-- Press on an item, hold, move, let go:
--   * over a cell: the item goes there (the cell under the cursor is the
--     cell of the item you grabbed it by);
--   * over the inventory windows but not a cell: it stays where it was;
--   * outside the inventory: it is discarded (a loot bag is thrown).

function PDTI.UIIsDragging() return drag ~= nil and held ~= nil end

-- Starts dragging the item in this cell. Returns false on an empty cell.
function PDTI.UIDragStart(container_name, x, y)
    drag = nil
    local map = PDTI.GetOccupancyMap(container_name)
    local row = map and map.cells[y + 1]
    local id = row and row[x + 1]
    if not id then return false, "empty cell" end
    local ok = PDTI.UIPickUp(container_name, id)
    if not ok then return false end
    local item = PDTI.FindItem(container_name, id)
    drag = { dx = x - item.x, dy = y - item.y, container = container_name, x = x, y = y, rotated = item.rotated == true }
    return true
end

-- The held item turned while dragged: the grab point stays inside it.
local function clamp_grab()
    if not drag or not held then return end
    local item = PDTI.FindItem(held.container, held.instance_id)
    local w, h = PDTI.ItemSize(item or held.item_id, held.rotated)
    if not w then return end
    if held.rotated ~= drag.rotated then
        drag.dx, drag.dy = drag.dy, drag.dx
        drag.rotated = held.rotated
    end
    drag.dx = math.max(0, math.min(w - 1, drag.dx))
    drag.dy = math.max(0, math.min(h - 1, drag.dy))
end

-- Where the dragged item would go with the cursor over this cell: its top
-- left cell, its size and whether it can go there.
function PDTI.UIDragPreview(container_name, x, y)
    if not drag or not held then return nil end
    local item = PDTI.FindItem(held.container, held.instance_id)
    if not item then return nil end
    clamp_grab()
    local w, h = PDTI.ItemSize(item, held.rotated)
    local ox, oy = x - drag.dx, y - drag.dy
    -- A weapon's slot: the magazine goes into the cell under the cursor.
    if PDTI.IsGunSlot(container_name) then ox, oy, w, h = x, y, 1, 1 end
    local valid, reason = false, "outside the grid"
    if ox >= 0 and oy >= 0 then
        valid, reason = PDTI.CanMoveItem(held.container, held.instance_id, container_name, ox, oy, held.rotated)
    end
    return { container = container_name, x = ox, y = oy, w = w, h = h, valid = valid == true, reason = reason }
end

-- Lets go of the dragged item. target is { container, x, y } for a cell,
-- "window" for the inventory outside the grids, "outside" for the rest.
function PDTI.UIDragDrop(target)
    if not drag or not held then
        drag = nil
        return false
    end
    local d = drag
    drag = nil
    if target == "outside" then
        return PDTI.UIDiscardHeld()
    end
    if type(target) ~= "table" then
        held, status = nil, nil
        return false, "put back"
    end
    -- Let go where it was picked up: nothing moves.
    if target.container == d.container and target.x == d.x and target.y == d.y and held.rotated == d.rotated then
        held, status = nil, nil
        return false, "put back"
    end
    clamp_grab()
    local ox, oy = target.x - d.dx, target.y - d.dy
    if PDTI.IsGunSlot(target.container) then ox, oy = target.x, target.y end
    local ok, reason = false, "outside the grid"
    if ox >= 0 and oy >= 0 then
        ok, reason = PDTI.RequestMove(held.container, held.instance_id, target.container, ox, oy, held.rotated)
    end
    local name = describe(held)
    held = nil
    if not ok then
        status = name .. " stays where it was: " .. tostring(reason)
        return false, reason
    end
    status = nil
    return true
end

-- Text for the screen's status line.
function PDTI.UIGetStatusText()
    if held then
        local item = PDTI.FindItem(held.container, held.instance_id)
        local kg = item and PDTI.ItemWeight(item) or 0
        local line = string.format("Holding: %s (%.2f kg) - drop it on a cell; outside the inventory it is discarded",
            describe(held), kg)
        if status then line = line .. "  [" .. tostring(status) .. "]" end
        return line
    end
    return status or "Click an item to pick it up, Ctrl+click to move it to the other side"
end

-- Lets the renderer show the outcome of non-grid actions (equip, arrange).
function PDTI.UISetStatus(message)
    status = message
end

function PDTI.UIResetInteraction()
    drag = nil
    held, status = nil, nil
end
