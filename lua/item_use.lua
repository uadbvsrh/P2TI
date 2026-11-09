-- Item-use registry. Gameplay mods register concrete effects; this module
-- deliberately ships no fake healing/ammo/ECM effects.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

PDTI._item_use_handlers = PDTI._item_use_handlers or {}

function PDTI.RegisterItemUse(item_id, callback)
    if type(item_id) ~= "string" or type(callback) ~= "function" then
        return false, "expected item id and callback"
    end
    local def = PDTI.GetItemDefinition(item_id)
    if not def then return false, "unknown item" end
    if not def.quick_use then return false, "item is not marked quick_use" end
    PDTI._item_use_handlers[item_id] = callback
    return true
end

function PDTI.UnregisterItemUse(item_id)
    PDTI._item_use_handlers[item_id] = nil
    return true
end

-- Handler signature: callback(item_snapshot, context)
-- Return true only after the gameplay effect has actually succeeded.
--
-- Order of operations (reserve, apply, refund on failure):
--   1. Remove one unit and persist that removal. If it cannot be saved the
--      effect is never run, so a failed save can never grant a free use.
--   2. Run the handler.
--   3. If the handler errors or reports failure, give the unit back.
-- A crash between steps 1 and 3 loses the item; it never duplicates it.
function PDTI.UseItem(container_name, instance_id, context)
    local item = PDTI.FindItem(container_name, instance_id)
    if not item then return false, "item not found" end

    local def = PDTI.GetItemDefinition(item.item_id)
    if not def or not def.quick_use then return false, "item is not usable" end

    local handler = PDTI._item_use_handlers[item.item_id]
    if type(handler) ~= "function" then
        return false, "no gameplay handler is registered for this item"
    end

    local reserved, result = PDTI.RemoveItem(container_name, instance_id, 1)
    if not reserved then
        return false, "could not reserve item for use: " .. tostring(result)
    end

    local ok, used, message = pcall(handler, item, context or {})
    if not ok or used ~= true then
        local restored, why = PDTI.RestoreItemUnits(container_name, item, 1)
        local reason = (not ok) and ("item-use handler failed: " .. tostring(used))
            or message or "item effect did not succeed"
        if not restored then
            reason = reason .. " (item could not be restored: " .. tostring(why) .. ")"
        end
        return false, reason
    end
    return true, "used", result
end
