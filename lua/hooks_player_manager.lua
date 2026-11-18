-- Hooked on lib/managers/playermanager (see mod.txt).
--
-- The game places a deployable through PlayerManager:use_selected_equipment.
-- That function uses the equipment the player selected in the game, so it
-- would place the game's own deployable and not the one in the inventory.
--
-- These patches give the game the inventory's deployable instead:
--   * selected_equipment returns an entry that looks like the game's own
--     equipment entries, but describes the item in the inventory. The deploy
--     timer, the placement check and the HUD use it.
--   * can_use_selected_equipment is true while an item is to hand, so the
--     game starts its deploy action.
--   * use_selected_equipment places the item of the inventory and takes it
--     out of the inventory. The game's own equipment count is left alone.
--
-- What you place is what you carry: when the game would place one of the
-- kinds the inventory manages (the ammo bag you brought) but none is in
-- your rig or pockets, nothing is placed. Equipment the inventory does not
-- manage (a sentry gun, a trip mine) stays the game's.
if not rawget(_G, "PDTI") then
    local dir = rawget(_G, "ModPath")
    if dir then pcall(dofile, dir .. "lua/main.lua") end
end
-- The skill rework reads and changes the upgrades through PlayerManager.
do
    local p = rawget(_G, "PDTI")
    if p and p.Skills and p.Skills.Install then pcall(p.Skills.Install) end
end
local PM = rawget(_G, "PlayerManager")
if not PM or type(PM.selected_equipment) ~= "function" then return end
if PM._pdti_deploy_patched then return end

PM._pdti_original = PM._pdti_original or {}

local function patch(name, wrapper)
    local current = PM[name]
    if type(current) ~= "function" then return false end
    if not PM._pdti_original[name] then PM._pdti_original[name] = current end
    PM[name] = wrapper(PM._pdti_original[name])
    return true
end

local function deployables()
    local pdti = rawget(_G, "PDTI")
    return pdti and pdti.Deployables
end

patch("selected_equipment", function(original)
    return function(self, ...)
        local dep = deployables()
        if dep and dep.Manages and dep.Manages() then
            local entry = dep.SyntheticEntry and dep.SyntheticEntry()
            if entry then return entry end
        end
        return original(self, ...)
    end
end)

patch("can_use_selected_equipment", function(original)
    return function(self, ...)
        local dep = deployables()
        if dep and dep.Manages and dep.Manages() then
            local entry = dep.SyntheticEntry and dep.SyntheticEntry()
            if entry then return true end
        end
        -- You brought an ammo bag but carry none: nothing to place.
        if dep and dep.BlocksGame and dep.BlocksGame() then return false end
        return original(self, ...)
    end
end)

-- The game checks the placement with the equipment the player brought to the
-- heist. A deployable from the inventory that the player did not bring (a
-- doctor bag when an ammo bag was brought) is not in that list: every spot
-- looked invalid and no placement model was shown. The check is done here
-- for the inventory's item, the same way the game does it for bags and kits.
patch("check_equipment_placement_valid", function(original)
    return function(self, player, equipment, ...)
        local dep = deployables()
        local entry = dep and dep.Manages and dep.Manages() and dep.SyntheticEntry and dep.SyntheticEntry()
        local data = entry and entry.equipment == equipment and tweak_data.equipments
            and tweak_data.equipments[equipment]
        if data then
            local ext = player and player.equipment and player:equipment()
            if ext and dep.ValidPlacement then
                -- The game's own check for the kind: on a wall (trip mine,
                -- ECM, spy camera), on yourself (armor kit) or like a bag.
                return dep.ValidPlacement(ext, entry.pdti_item) and true or false
            end
        end
        return original(self, player, equipment, ...)
    end
end)

patch("use_selected_equipment", function(original)
    return function(self, unit, ...)
        local dep = deployables()
        local entry = dep and dep.Manages and dep.Manages() and dep.SyntheticEntry and dep.SyntheticEntry()
        if not entry then
            if dep and dep.BlocksGame and dep.BlocksGame() then return nil end
            return original(self, unit, ...)
        end

        local equipment = unit and unit.equipment and unit:equipment()
        if not equipment then return original(self, unit, ...) end

        -- The game comes here when its deploy timer is over. The item of the
        -- inventory is placed and taken out of the inventory; the game's own
        -- equipment count is left alone.
        local placed, redirect = dep.Place(equipment)

        if placed and redirect then
            pcall(redirect, unit)
            if entry.on_use_callback then
                local player_unit = managers.player and managers.player:player_unit()
                if player_unit then
                    pcall(function() player_unit:event_listener():call(entry.on_use_callback) end)
                end
            end
        end

        return {
            expire_timer = entry.action_timer,
            redirect = nil
        }
    end
end)

-- A deployable used up by an interaction instead of being placed: a trip mine
-- set as a shaped charge on a safe or a door. The game asks its own count
-- (has_deployable_left) and takes one (remove_equipment); a trip mine in
-- your rig or pockets counts too, and is taken when the game has none.
patch("has_deployable_left", function(original)
    return function(self, equipment, slot, ...)
        if original(self, equipment, slot, ...) then return true end
        local dep = deployables()
        return dep ~= nil and dep.ItemToHandFor ~= nil and dep.ItemToHandFor(equipment) ~= nil
    end
end)

patch("remove_equipment", function(original)
    return function(self, equipment_id, slot, ...)
        local dep = deployables()
        if dep and dep.GameCount and dep.GameCount(equipment_id, slot) < 1 then
            local item_id = dep.ItemToHandFor and dep.ItemToHandFor(equipment_id)
            if item_id then
                dep.Consume(item_id)
                if dep.Changed then pcall(dep.Changed) end
                if _G.log then _G.log("[PDTI DEPLOY] used a " .. tostring(item_id) .. " from the inventory") end
                return
            end
            -- The game has none either: its own code would fail on it.
            if not (self.has_equipment and self:has_equipment(equipment_id)) then return end
        end
        return original(self, equipment_id, slot, ...)
    end
end)

-- A sentry gun picked up goes back into the inventory, not to the game's
-- equipment count (when there is room; else the game keeps it).
patch("add_sentry_gun", function(original)
    return function(self, num, sentry_type, ...)
        local dep = deployables()
        if dep and dep.OnSentryPickedUp and (num or 1) > 0 then
            local ok, stored = pcall(dep.OnSentryPickedUp, sentry_type)
            if ok and stored then return end
        end
        return original(self, num, sentry_type, ...)
    end
end)

-- A client: the host placed the sentry gun asked for. When it came from the
-- inventory, the item is taken out (the game's count is left alone).
patch("from_server_equipment_place_result", function(original)
    return function(self, selected_index, unit, sentry_gun_unit, ...)
        local dep = deployables()
        if dep and dep.pending_sentry then
            if alive(unit) and alive(sentry_gun_unit) then
                pcall(function() unit:equipment():from_server_sentry_gun_place_result(sentry_gun_unit:id()) end)
            end
            pcall(dep.OnSentryPlaced)
            return
        end
        return original(self, selected_index, unit, sentry_gun_unit, ...)
    end
end)

PM._pdti_deploy_patched = true
if _G.log then
    _G.log("[PDTI DEPLOY] the game places the deployable from the inventory")
end
