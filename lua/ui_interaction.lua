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
-- A part dragged out of its slot in the weapon view (0.38.2): it stays on
-- the weapon until it is let go on a cell. { container, instance_id (the
-- weapon), part_id, ptype, rotated }
local slot_drag = nil

local function describe(h)
    local def = PDTI.GetItemDefinition(h.item_id)
    local name = def and def.name or h.item_id
    -- A loot bag: its kind, quality and modifiers.
    if h.item_id == "loot_bag" and PDTI.LootQuality then
        local item = PDTI.FindItem(h.container, h.instance_id)
        if item then name = PDTI.LootQuality.Describe(item.data) end
    end
    -- A weapon or a weapon part: its name.
    if h.item_id == "weapon" or h.item_id == "weapon_part" then
        local item = PDTI.FindItem(h.container, h.instance_id)
        if item and type(item.data) == "table" and item.data.name then name = tostring(item.data.name) end
    end
    return name .. (h.rotated and " (rotated)" or "")
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
    slot_drag = nil
    status = nil
    PDTI.SelectContainer(container_name)
    PDTI.SelectItem(instance_id)
    return true
end

function PDTI.UICancelHeld()
    held, status, drag, slot_drag = nil, nil, nil, nil
    return true
end

function PDTI.UIRotateHeld()
    if slot_drag then
        slot_drag.rotated = not slot_drag.rotated
        return true
    end
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
    pouch = { "backpack", "pockets", "rig", "rig_2", "rig_3" },
    backpack = { "pouch", "pockets", "rig", "rig_2", "rig_3", "locker" },
    -- The locker: packed (a weapon goes to its slot first, see below); a
    -- slot's weapon back to the locker, or packed.
    locker = { "backpack", "rig", "rig_2", "rig_3" },
    hand_primary = { "locker", "backpack" },
    hand_secondary = { "locker", "backpack" },
    -- Out of a weapon's slot: to hand, then the backpack.
    gun_primary = { "pockets", "rig", "rig_2", "rig_3", "backpack" },
    gun_secondary = { "pockets", "rig", "rig_2", "rig_3", "backpack" }
}

local TARGET_NAMES = { pouch = "ammo pouch", hand_primary = "primary slot", hand_secondary = "secondary slot" }
local WEAPON_SLOT = { primaries = "hand_primary", secondaries = "hand_secondary" }

-- Where a Ctrl+click sends this item: a weapon goes into its slot (PRI /
-- SEC) first (from its slot that is refused: it holds the weapon already).
local function quick_targets(container_name, item)
    local list = QUICK_TARGETS[container_name] or {}
    local slot = item.item_id == "weapon" and type(item.data) == "table" and WEAPON_SLOT[item.data.category]
    if not slot then return list end
    local out = { slot }
    for _, t in ipairs(list) do out[#out + 1] = t end
    return out
end

-- Moves an item to the first free place of the other side (Ctrl+click).
function PDTI.UIQuickTransfer(container_name, instance_id)
    local item = PDTI.FindItem(container_name, instance_id)
    if not item then
        status = "Item not found"
        return false, status
    end
    local def = PDTI.GetItemDefinition(item.item_id)
    local name = def and def.name or item.item_id
    if item.item_id == "weapon" and type(item.data) == "table" and item.data.name then name = tostring(item.data.name) end
    local last_reason = "no free space"
    for _, target in ipairs(quick_targets(container_name, item)) do
        local x, y, rotated = PDTI.FindFreeSpace(target, item, true)
        if x ~= nil then
            local ok, reason = PDTI.RequestMove(container_name, instance_id, target, x, y, rotated)
            if ok then
                held = nil
                status = "Moved " .. name .. " to the " .. (TARGET_NAMES[target] or target)
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

function PDTI.UIIsDragging() return (drag ~= nil and held ~= nil) or slot_drag ~= nil end

------------------------------------------------- a weapon's slots (0.38.2)
--
-- The weapon view (ui_beardlib.lua) has a box for each of the weapon's
-- slots. slot is { container, instance_id (the weapon), ptype, part_id (nil:
-- empty) }.
--   * press on your part and drag it onto a cell: it comes off there;
--   * Ctrl+click it: it comes off next to the weapon;
--   * drag a part onto its slot: it is fitted.

local function slot_name(slot)
    return PDTI.Parts.Name(slot.part_id)
end

-- Who makes a change: armory_hotmod.lua (at once at home, timed in a heist),
-- else armory_parts.lua.
local function changer() return PDTI.HotMod or PDTI.Parts end

-- Why a change has to wait (another is going on in a heist), or nil.
local function busy() return PDTI.HotMod and PDTI.HotMod.Busy() or nil end

-- The part dragged out of its slot, or nil: { container, instance_id,
-- part_id, ptype, rotated }.
function PDTI.UIGetSlotDrag()
    if not slot_drag then return nil end
    return { container = slot_drag.container, instance_id = slot_drag.instance_id,
        part_id = slot_drag.part_id, ptype = slot_drag.ptype, rotated = slot_drag.rotated }
end

-- The weapons a held part goes on (0.44.0): every weapon of yours, wherever
-- it is, whose kind the game lets take the part (one that has it already
-- too). { [container] = { [instance_id] = true } }, or nil when the item
-- held is not a part. The screen marks them green while the part is dragged.
function PDTI.UIFitWeapons()
    local P, A = PDTI.Parts, PDTI.Armory
    if not held or not P or not A or held.item_id ~= P.ITEM_ID then return nil end
    local part = PDTI.FindItem(held.container, held.instance_id)
    local part_id = part and type(part.data) == "table" and part.data.part_id
    if type(part_id) ~= "string" then return nil end
    local out = {}
    for _, e in ipairs(PDTI.FindItems(function(_, it) return it.item_id == A.ITEM_ID and type(it.data) == "table" end)) do
        if P.Takes(e.item.data.weapon_id, part_id) then
            out[e.container] = out[e.container] or {}
            out[e.container][e.item.instance_id] = true
        end
    end
    return out
end

-- A press on a slot: its part starts coming off (when it can).
function PDTI.UISlotDragStart(slot)
    held, drag, slot_drag = nil, nil, nil
    local P = PDTI.Parts
    local weapon = P and type(slot) == "table" and PDTI.FindItem(slot.container, slot.instance_id)
    if not weapon then
        status = "No such weapon"
        return false, status
    end
    if not slot.part_id then
        status = "The " .. P.TypeName(slot.ptype) .. " slot is empty: drag a part onto it"
        return false, status
    end
    local ok, why = P.CanTakeOff(weapon.data, slot.part_id)
    if ok and busy() then ok, why = false, busy() end
    if not ok then
        status = "The " .. slot_name(slot) .. " stays on: " .. tostring(why)
        return false, status
    end
    slot_drag = { container = slot.container, instance_id = slot.instance_id, part_id = slot.part_id,
        ptype = P.Type(slot.part_id), rotated = false }
    status = nil
    return true
end

-- Ctrl+click on a slot: its part comes off, next to the weapon.
function PDTI.UISlotTakeOff(slot)
    if held or slot_drag then
        status = "Place the held item first"
        return false, status
    end
    local P = PDTI.Parts
    if not P or type(slot) ~= "table" or not slot.part_id then
        status = "Nothing to take off there"
        return false, status
    end
    local ok, msg = changer().TakeOff(slot.container, slot.instance_id, slot.part_id)
    status = ok and msg or ("The " .. slot_name(slot) .. " stays on: " .. tostring(msg))
    return ok, status
end

-- Why this item does not go in this slot (nil when it is a part of the
-- slot's kind).
local function not_for_slot(item, slot)
    local P = PDTI.Parts
    if not item or item.item_id ~= P.ITEM_ID then return "only a weapon part goes in a slot" end
    local ptype = P.Type(item.data.part_id)
    if ptype ~= slot.ptype then return "it goes in the " .. P.TypeName(ptype) .. " slot" end
    return nil
end

-- The part dragged over a slot: does it go in? { valid, reason }, or nil
-- (nothing held: a part out of a slot is not held either).
function PDTI.UISlotPreview(slot)
    if not drag or not held or type(slot) ~= "table" then return nil end
    local item = PDTI.FindItem(held.container, held.instance_id)
    local weapon = PDTI.FindItem(slot.container, slot.instance_id)
    if not item or not weapon then return nil end
    local no = not_for_slot(item, slot)
    if no then return { valid = false, reason = no } end
    local ok, why = PDTI.Parts.CanFit(item.data, weapon.data)
    if ok and busy() then ok, why = false, busy() end
    return { valid = ok == true, reason = ok and "fit" or why }
end

-- The raw message of the last action (nil when there is none).
function PDTI.UIGetStatus() return status end

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

-- The magazine under the cursor that the held loose rounds can be loaded
-- into, or nil (and why not, when it is a magazine they do not fit).
local function load_target(container_name, x, y)
    local Ammo = PDTI.Ammo
    if not Ammo or not Ammo.CanLoadInto or not held then return nil end
    local map = PDTI.GetOccupancyMap(container_name)
    local row = map and map.cells[y + 1]
    local id = row and row[x + 1]
    if not id or id == held.instance_id then return nil end
    local mag = PDTI.FindItem(container_name, id)
    local loose = PDTI.FindItem(held.container, held.instance_id)
    if not mag or not loose or loose.item_id ~= Ammo.LOOSE_ITEM or mag.item_id ~= Ammo.MAGAZINE_ITEM then return nil end
    local ok, why = Ammo.CanLoadInto(loose, mag)
    return mag, ok, why
end
PDTI._UILoadTarget = load_target

-- The weapon under the cursor that the held part can be fitted to
-- (armory_parts.lua), or nil; and whether it fits, or why not.
local function fit_target(container_name, x, y)
    local P = PDTI.Parts
    if not P or not P.CanFit or not held or held.item_id ~= P.ITEM_ID then return nil end
    local map = PDTI.GetOccupancyMap(container_name)
    local row = map and map.cells[y + 1]
    local id = row and row[x + 1]
    if not id or id == held.instance_id then return nil end
    local weapon = PDTI.FindItem(container_name, id)
    local part = PDTI.FindItem(held.container, held.instance_id)
    if not weapon or not part or weapon.item_id ~= "weapon" then return nil end
    local ok, why = P.CanFit(part.data, weapon.data)
    if ok and busy() then ok, why = false, busy() end
    return weapon, ok, why
end
PDTI._UIFitTarget = fit_target

-- Where the dragged item would go with the cursor over this cell: its top
-- left cell, its size and whether it can go there.
function PDTI.UIDragPreview(container_name, x, y)
    -- A part out of its slot: it would come off there (its top left cell).
    if slot_drag then
        local P = PDTI.Parts
        local ref = { item_id = P.ITEM_ID, data = P.MakeData(slot_drag.part_id) }
        local w, h = PDTI.ItemSize(ref, slot_drag.rotated, container_name)
        local valid, reason = PDTI.CanPlace(container_name, ref, x, y, slot_drag.rotated)
        return { container = container_name, x = x, y = y, w = w or 1, h = h or 1, valid = valid == true, reason = reason }
    end
    if not drag or not held then return nil end
    local item = PDTI.FindItem(held.container, held.instance_id)
    if not item then return nil end
    -- Loose rounds over a magazine: the magazine is what lights up.
    local mag, can, why = load_target(container_name, x, y)
    if mag then
        local mw, mh = PDTI.ItemSize(mag, mag.rotated == true)
        return { container = container_name, x = mag.x, y = mag.y, w = mw or 1, h = mh or 1,
            valid = can == true, reason = can and "load" or why, load = true }
    end
    -- A part over a weapon: the weapon lights up (a weapon slot is one cell).
    local weapon, fits, no = fit_target(container_name, x, y)
    if weapon then
        local ww, wh = PDTI.ItemSize(weapon, weapon.rotated == true, container_name)
        return { container = container_name, x = weapon.x, y = weapon.y, w = ww or 1, h = wh or 1,
            valid = fits == true, reason = fits and "fit" or no, fit = true }
    end
    clamp_grab()
    local w, h = PDTI.ItemSize(item, held.rotated)
    local ox, oy = x - drag.dx, y - drag.dy
    -- A weapon's slot: the magazine goes into the cell under the cursor.
    if PDTI.IsGunSlot(container_name) then ox, oy, w, h = x, y, 1, 1 end
    -- A weapon slot (PRI / SEC): one cell, whatever the weapon's size.
    if PDTI.IsHandSlot and PDTI.IsHandSlot(container_name) then ox, oy, w, h = 0, 0, 1, 1 end
    local valid, reason = false, "outside the grid"
    if ox >= 0 and oy >= 0 then
        valid, reason = PDTI.CanMoveItem(held.container, held.instance_id, container_name, ox, oy, held.rotated)
    end
    return { container = container_name, x = ox, y = oy, w = w, h = h, valid = valid == true, reason = reason }
end

-- Lets go of the dragged item. target is { container, x, y } for a cell,
-- "window" for the inventory outside the grids, "outside" for the rest.
function PDTI.UIDragDrop(target)
    -- A part out of its slot: let go on a cell, it comes off there; anywhere
    -- else it stays on (it is never thrown away).
    if slot_drag then
        local s = slot_drag
        slot_drag = nil
        if type(target) ~= "table" or not target.container then
            status = nil
            return false, "put back"
        end
        local ok, msg = changer().TakeOff(s.container, s.instance_id, s.part_id, target.container, target.x, target.y, s.rotated)
        status = ok and msg or ("The " .. slot_name(s) .. " stays on: " .. tostring(msg))
        return ok, ok and "off" or msg
    end
    if not drag or not held then
        drag = nil
        return false
    end
    local d = drag
    drag = nil
    if target == "outside" then
        return PDTI.UIDiscardHeld()
    end
    -- A part let go on its slot in the weapon view: it is fitted; anything
    -- else let go on a slot stays where it was.
    if type(target) == "table" and target.mod_slot then
        local slot = target.mod_slot
        local name = describe(held)
        local part_c, part_id = held.container, held.instance_id
        held = nil
        local no = not_for_slot(PDTI.FindItem(part_c, part_id), slot)
        local ok, msg = false, no
        -- (Fit checks the rest, and says why not.)
        if not no then ok, msg = changer().Fit(part_c, part_id, slot.container, slot.instance_id) end
        status = ok and msg or (name .. " stays where it was: " .. tostring(msg))
        return ok, ok and "fit" or msg
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
    -- Loose rounds let go on a magazine are loaded into it (round by round in
    -- a heist, at once in the menu).
    local mag, can, why = load_target(target.container, target.x, target.y)
    if mag then
        local name = describe(held)
        local loose_id = held.instance_id
        held = nil
        if not can then
            status = name .. " stays where it was: " .. tostring(why)
            return false, why
        end
        local ok, msg = PDTI.Ammo.StartLoad(loose_id, mag.instance_id)
        if not ok then
            status = name .. " stays where it was: " .. tostring(msg)
            return false, msg
        end
        status = msg == "loading" and "Loading the magazine round by round - shooting, reloading or aiming stops it"
            or ("Magazine loaded: " .. tostring(msg))
        return true, "load"
    end
    -- A part let go on a weapon is fitted to it.
    local weapon = fit_target(target.container, target.x, target.y)
    if weapon then
        local name = describe(held)
        local part_c, part_id = held.container, held.instance_id
        held = nil
        -- (Fit checks again what the preview showed, and says why not.)
        local ok, msg = changer().Fit(part_c, part_id, target.container, weapon.instance_id)
        if not ok then
            status = name .. " stays where it was: " .. tostring(msg)
            return false, msg
        end
        status = msg
        return true, "fit"
    end
    clamp_grab()
    local ox, oy = target.x - d.dx, target.y - d.dy
    if PDTI.IsGunSlot(target.container) then ox, oy = target.x, target.y end
    -- A weapon slot: wherever the weapon was grabbed, it takes the slot.
    if PDTI.IsHandSlot and PDTI.IsHandSlot(target.container) then ox, oy = 0, 0 end
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
    if slot_drag then
        return "Taking off: " .. slot_name(slot_drag) .. " - let go on a free cell; anywhere else it stays on"
    end
    if held then
        local item = PDTI.FindItem(held.container, held.instance_id)
        local kg = item and PDTI.ItemWeight(item) or 0
        local line = string.format("Holding: %s (%.2f kg) - drop it on a cell; outside the inventory it is discarded",
            describe(held), kg)
        if status then line = line .. "  [" .. tostring(status) .. "]" end
        return line
    end
    return status or "Click: pick up. Ctrl+click: move across. Right-click a weapon: its parts"
end

-- Lets the renderer show the outcome of non-grid actions (equip, arrange).
function PDTI.UISetStatus(message)
    status = message
end

function PDTI.UIResetInteraction()
    drag, slot_drag = nil, nil
    held, status = nil, nil
end
