-- The "Deployable" slot of the game's loadout opens the tactical inventory:
-- there you choose the rig, the backpack and what you bring. Hooked on:
--   lib/managers/menu/playerinventorygui  the main menu's Inventory screen
--   lib/managers/menu/missionbriefinggui  the loadout tab of the briefing
--                                          (pre-planning)
-- If the inventory screen cannot open (no BeardLib), the game's own
-- deployable menu opens as before.
local mod_path = rawget(_G, "ModPath")

local function pdti()
    local p = rawget(_G, "PDTI")
    if p and p._loaded then return p end
    if mod_path then pcall(dofile, mod_path .. "lua/main.lua") end
    return rawget(_G, "PDTI")
end

-- Opens the inventory screen; false when it cannot open.
local function open_inventory()
    local p = pdti()
    if not p or not p.SetUIOpen or not (p.IsUIAvailable and p.IsUIAvailable()) then return false end
    if p.IsUIOpen and p.IsUIOpen() then return true end
    local ok, opened = pcall(p.SetUIOpen, true)
    if not ok and _G.log then _G.log("[PDTI] could not open the inventory: " .. tostring(opened)) end
    return ok and opened == true
end

local function hook_method(class, name, make)
    if type(class) ~= "table" or type(class[name]) ~= "function" then return end
    local flag = "_pdti_hooked_" .. name
    if class[flag] == class[name] then return end
    local hooked = make(class[name])
    class[name] = hooked
    class[flag] = hooked
end

-- The Inventory screen of the main menu (both deployable boxes use this).
hook_method(rawget(_G, "PlayerInventoryGui"), "open_deployable_menu", function(orig)
    return function(self, ...)
        if open_inventory() then return end
        return orig(self, ...)
    end
end)

-- The briefing's loadout tab: item 6 is the deployable.
hook_method(rawget(_G, "NewLoadoutTab"), "open_node", function(orig)
    return function(self, node, ...)
        if node == 6 and open_inventory() then return end
        return orig(self, node, ...)
    end
end)

-- The older loadout item of the briefing: item 5 is the deployable.
hook_method(rawget(_G, "LoadoutItem"), "open_node", function(orig)
    return function(self, node, ...)
        if node == 5 and open_inventory() then return end
        return orig(self, node, ...)
    end
end)
