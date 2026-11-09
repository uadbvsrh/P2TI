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
            if ext and type(ext.valid_shape_placement) == "function" then
                local ok, valid = pcall(ext.valid_shape_placement, ext, equipment, data)
                return ok and valid and true or false
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

PM._pdti_deploy_patched = true
if _G.log then
    _G.log("[PDTI DEPLOY] the game places the deployable from the inventory")
end
