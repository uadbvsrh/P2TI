-- Lightweight model tests. Run with PDTI.RunSelfTests() from a Lua console
-- after the mod loads. Tests operate on a temporary state and do not alter saves.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

function PDTI.RunSelfTests()
    local results = {}
    local function check(name, condition, detail)
        results[#results + 1] = {
            name = name, passed = condition == true,
            detail = detail
        }
    end

    local can = PDTI._internal.placement_check
    local fake = {
        equipment = { backpack = "medium_backpack", rig = "general_rig" },
        containers = {
            pockets = { items = {} },
            rig = { items = {} }, rig_2 = { items = {} }, rig_3 = { items = {} },
            backpack = { items = {} }
        }
    }

    local ok1 = can("backpack", "doctor_bag", 0, 0, false, nil, fake)
    check("valid placement", ok1 == true)

    local ok2, why2 = can("backpack", "doctor_bag", 4, 3, false, nil, fake)
    check("out-of-bounds placement rejected", ok2 == false, why2)

    fake.containers.backpack.items = {
        { instance_id = 10, item_id = "doctor_bag", x = 0, y = 0, rotated = false, amount = 1 }
    }
    local ok3, why3 = can("backpack", "bandage", 1, 1, false, nil, fake)
    check("overlap rejected", ok3 == false, why3)

    local ok4 = can("pockets", "doctor_bag", 0, 0, false, nil, fake)
    check("container category restriction", ok4 == false)

    local ok5 = can("rig", "spare_magazine", 0, 0, true, nil, fake)
    check("rotated item accepted when it fits", ok5 == true)

    local medic_fake = {
        equipment = { backpack = "medium_backpack", rig = "medical_rig" },
        containers = {
            pockets = { items = {} },
            rig = { items = {} }, rig_2 = { items = {} }, rig_3 = { items = {} },
            backpack = { items = {} }
        }
    }
    local ok6, why6 = can("rig", "spare_magazine", 0, 0, false, nil, medic_fake)
    check("rig section restriction", ok6 == false, why6)

    local weight_fake = {
        containers = {
            pockets = { items = {} },
            rig = { items = {} },
            backpack = { items = {
                { item_id = "bandage", amount = 3 }
            } }
        }
    }
    local weight = PDTI._internal.container_weight("backpack", weight_fake)
    check("stack weight calculation", math.abs(weight - 0.6) < 0.0001, weight)

    -- Public API regression checks that do not alter the player's inventory.
    local occupancy = PDTI.GetOccupancyMap("backpack")
    check("occupancy map dimensions", type(occupancy) == "table"
        and occupancy.width > 0 and occupancy.height > 0)

    local bad_item_ok = PDTI.RegisterItem("__pdti_test_invalid", {
        name = "Invalid", w = 0, h = 1, weight = 0,
        category = "test", allowed = { backpack = true }
    })
    check("invalid item definition rejected", bad_item_ok == false)

    local unknown_use_ok = PDTI.UseItem("pockets", -999999, {})
    check("unknown item use rejected safely", unknown_use_ok == false)

    local ui_state = PDTI.GetUIState and PDTI.GetUIState() or nil
    check("UI state model available", type(ui_state) == "table"
        and type(ui_state.model) == "table")

    local state_valid, state_errors = PDTI.ValidateState()
    check("live inventory validates", state_valid == true,
        state_valid and nil or table.concat(state_errors or {}, "; "))

    -- Deployables: the pick, the count and the placement.
    if PDTI.Deployables then
        local dep_ok = PDTI.SetDeployable("ammo_bag")
        check("a deployable can be picked", dep_ok == true)
        check("the picked deployable is known", PDTI.GetDeployable() == "ammo_bag")
        check("the count of a deployable is read", PDTI.Deployables.Count("ammo_bag") >= 0)
        check("the deployable can be given back", PDTI.SetDeployable(nil) == true)
    end

    -- Loose ammunition: the summary of what is carried.
    if PDTI.Ammo then
        local summary = PDTI.Ammo.GetSummary()
        check("the loose ammunition summary is available",
            type(summary) == "table" and type(summary.total) == "number")
        local supplies = PDTI.Ammo.GetSupplySummary()
        check("the magazine summary is available", type(supplies) == "table")
    end

    -- Loot: the bags the player carries are inventory items.
    if PDTI.Loot then
        check("the loot bag count is a number", type(PDTI.Loot.Count()) == "number")
    end

    -- Carry weight: the speed factor.
    if PDTI.Carry then
        local factor = PDTI.Carry.GetSpeedFactor()
        check("the speed factor is a number", type(factor) == "number" and factor > 0 and factor <= 2)
    end

    local passed = 0
    for _, result in ipairs(results) do
        if result.passed then passed = passed + 1 end
        local msg = (result.passed and "PASS " or "FAIL ") .. result.name
        if result.detail then msg = msg .. " (" .. tostring(result.detail) .. ")" end
        if _G.log then _G.log("[PDTI TEST] " .. msg) else print("[PDTI TEST] " .. msg) end
    end
    return passed, #results, results
end
