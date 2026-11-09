-- Runtime diagnostics useful when collecting player test logs.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

function PDTI.GetDiagnostics()
    local containers = {}
    for _, name in ipairs((PDTI.CONTAINERS or { "pockets", "rig", "backpack" })) do
        local info = PDTI.GetContainerInfo(name)
        containers[name] = info and {
            item_count = #info.items,
            width = info.width,
            height = info.height,
            weight = info.weight,
            weight_limit = info.weight_limit
        } or nil
    end
    return {
        version = PDTI.VERSION,
        schema_version = PDTI.SCHEMA_VERSION,
        ammo = PDTI.Ammo and PDTI.Ammo.GetSummary and PDTI.Ammo.GetSummary() or { stacks = {}, total = 0 },
        supplies = PDTI.Ammo and PDTI.Ammo.GetSupplySummary and PDTI.Ammo.GetSupplySummary() or {},
        loot_bags = PDTI.Loot and PDTI.Loot.Count and PDTI.Loot.Count() or 0,
        deployable = PDTI.GetDeployable and PDTI.GetDeployable() or nil,
        total_weight = PDTI.GetTotalWeight(),
        unresolved_item_count = #(PDTI.GetUnresolvedItems and PDTI.GetUnresolvedItems() or {}),
        unresolved_equipment = PDTI.GetUnresolvedEquipment and PDTI.GetUnresolvedEquipment() or {},
        containers = containers
    }
end

function PDTI.LogDiagnostics()
    local data = PDTI.GetDiagnostics()
    local function line(s)
        if _G.log then _G.log("[PDTI DIAG] " .. s) else print("[PDTI DIAG] " .. s) end
    end
    line("version=" .. tostring(data.version) .. " schema=" .. tostring(data.schema_version)
        .. " loose=" .. tostring(data.ammo and data.ammo.total or 0)
        .. " loot_bags=" .. tostring(data.loot_bags)
        .. " deployable=" .. tostring(data.deployable or "-")
        .. " total_weight=" .. tostring(data.total_weight)
        .. " unresolved=" .. tostring(data.unresolved_item_count)
        .. " unresolved_equipment=" .. tostring(data.unresolved_equipment.backpack or "-")
        .. "/" .. tostring(data.unresolved_equipment.rig or "-"))
    for name, info in pairs(data.containers) do
        if info then
            line(name .. ": " .. info.item_count .. " items, "
                .. info.weight .. "/" .. info.weight_limit .. " kg, "
                .. info.width .. "x" .. info.height)
        end
    end
    return data
end
