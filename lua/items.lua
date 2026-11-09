-- Item registry. Third-party mods can append definitions before or after this
-- file loads by editing PDTI_ITEMS, then calling PDTI.RegisterItem(definition).

_G.PDTI_ITEMS = _G.PDTI_ITEMS or {}

local defaults = {
    -- Medical
    bandage = {
        name = "Bandage", w = 1, h = 1, weight = 0.2, max_stack = 3,
        category = "medical", allowed = { pockets = true, rig = true, backpack = true },
        quick_use = true
    },
    first_aid_kit = {
        name = "First Aid Kit", w = 1, h = 1, weight = 1.0, max_stack = 1,
        category = "medical", allowed = { pockets = true, rig = true, backpack = true },
        quick_use = true,
        -- A deployable: how many you can place follows what you carry.
        deployable = true, deployable_id = "first_aid_kit", deploy_method = "use_first_aid_kit"
    },
    doctor_bag = {
        name = "Doctor Bag", w = 3, h = 2, weight = 3.0, max_stack = 1,
        category = "medical", allowed = { rig = true, backpack = true },
        deployable = true, deployable_id = "doctor_bag", deploy_method = "use_doctor_bag"
    },
    painkillers = {
        name = "Painkillers", w = 1, h = 1, weight = 0.1, max_stack = 2,
        category = "medical", allowed = { pockets = true, rig = true, backpack = true },
        quick_use = true
    },

    -- Ammunition. These are real inventory items: a magazine in the rig or in
    -- the pockets can be loaded into the gun, and loose ammunition is packed
    -- into the magazines round by round. The rounds of a magazine are in
    -- item.data.rounds, the rounds of a loose stack are its amount.
    spare_magazine = {
        name = "Spare Magazine", w = 1, h = 2, weight = 0.45, max_stack = 1,
        category = "ammunition", allowed = { pockets = true, rig = true, backpack = true },
        ammo_managed = true,
        -- The weight is the empty magazine plus its rounds (PDTI.ItemWeight).
        weight_by_rounds = true,
        -- The size follows the capacity (PDTI.MagazineSize): 1 cell under 30
        -- rounds, 1x2 from 30, 1x3 from 60, 2x2 from 100. w/h are the default.
        size_by_capacity = true
    },
    -- Loose rounds. The amount is the number of rounds; a round weighs by its
    -- weapon type (PDTI.RoundWeight: a shotgun shell more than a pistol round).
    loose_ammo = {
        -- At most 100 rounds in a stack: more start a new stack.
        name = "Loose Ammunition", w = 1, h = 1, weight = 0.012, max_stack = 100,
        category = "ammunition", allowed = { pockets = true, rig = true, backpack = true },
        weight_per_round = true,
        ammo_managed = true
    },
    ammo_bag = {
        name = "Ammo Bag", w = 3, h = 2, weight = 3.0, max_stack = 1,
        category = "utility", allowed = { rig = true, backpack = true },
        deployable = true, deployable_id = "ammo_bag", deploy_method = "use_ammo_bag"
    },
    loose_ammo_box = {
        name = "Loose Ammunition", w = 2, h = 1, weight = 0.8, max_stack = 1,
        category = "ammunition", allowed = { backpack = true }
    },

    -- Utility and explosives
    grenade = {
        name = "Grenade", w = 1, h = 2, weight = 0.6, max_stack = 1,
        category = "explosive", allowed = { rig = true, backpack = true },
        quick_use = true
    },
    ecm_battery = {
        name = "ECM Battery", w = 1, h = 1, weight = 0.3, max_stack = 2,
        category = "utility", allowed = { pockets = true, rig = true, backpack = true },
        quick_use = true
    },
    armor_kit = {
        name = "Armor Repair Kit", w = 2, h = 1, weight = 1.2, max_stack = 1,
        category = "utility", allowed = { rig = true, backpack = true },
        quick_use = true
    },
    bodybags_bag = {
        name = "Body Bags", w = 2, h = 2, weight = 1.5, max_stack = 1,
        category = "utility", allowed = { pockets = true, rig = true, backpack = true },
        deployable = true, deployable_id = "bodybags_bag", deploy_method = "use_bodybags_bag"
    },
    -- A bag of loot the player carries. The game keeps counting the bags, so
    -- the money is still paid out; this item is what the loot costs in space
    -- and weight.
    loot_bag = {
        name = "Loot Bag", w = 2, h = 2, weight = 4.0, max_stack = 1,
        category = "utility", allowed = { rig = true, backpack = true },
        no_supply = true
    }
}

for id, def in pairs(defaults) do
    if _G.PDTI_ITEMS[id] == nil then _G.PDTI_ITEMS[id] = def end
end

_G.PDTI_EQUIPMENT = _G.PDTI_EQUIPMENT or {}

-- Backpacks are one grid. Rigs are made of sections: each section is a grid
-- of its own with its own rule for what goes in it.
--   section.items       only these item ids
--   section.categories  only items of these categories
--   (neither)           any item that may go in a rig
-- The first section of a rig is the container "rig", the next ones are
-- "rig_2" and "rig_3".
local AMMO = { spare_magazine = true, loose_ammo = true }

local equipment = {
    backpacks = {
        small_backpack = {
            name = "Small Backpack", short = "Small", w = 5, h = 2, max_weight = 15,
            speed_bonus = 0.25,
            description = "10 slots. 25% faster."
        },
        medium_backpack = {
            name = "Medium Backpack", short = "Medium", w = 5, h = 4, max_weight = 25,
            description = "20 slots."
        },
        large_backpack = {
            name = "Large Backpack", short = "Large", w = 6, h = 5, max_weight = 40,
            penalty_scale = 0.7, threat = 1.5,
            description = "30 slots. Weight and loot slow you 30% less. Enemies focus you 50% more."
        }
    },
    rigs = {
        medical_rig = {
            name = "Medical Rig", short = "Medical", self_revive = true,
            description = "Kits and medic bags, 2 ammo pouches. Get up once per heist with a medic bag (SPACE).",
            sections = {
                { name = "Medical", kind = "medical", w = 8, h = 2, max_weight = 14,
                  items = { first_aid_kit = true, doctor_bag = true } },
                { name = "Pouch", kind = "ammo", w = 1, h = 3, max_weight = 3, items = AMMO },
                { name = "Pouch", kind = "ammo", w = 1, h = 3, max_weight = 3, items = AMMO }
            }
        },
        assault_rig = {
            name = "Assault Rig", short = "Assault",
            description = "21 slots for ammunition, 12 slots for ammo bags.",
            sections = {
                { name = "Ammunition", kind = "ammo", w = 7, h = 3, max_weight = 14, items = AMMO },
                { name = "Ammo bags", kind = "ammo_bags", w = 6, h = 2, max_weight = 8, items = { ammo_bag = true } }
            }
        },
        general_rig = {
            name = "General Rig", short = "General", speed_bonus = 0.25,
            description = "18 slots for anything. 25% faster.",
            sections = {
                { name = "General", kind = "general", w = 3, h = 6, max_weight = 15 }
            }
        }
    }
}

-- Saves of 0.10 and older name equipment that no longer exists.
_G.PDTI_EQUIPMENT_RENAMED = {
    compact_pack = "small_backpack", assault_pack = "medium_backpack",
    field_pack = "medium_backpack", heavy_pack = "large_backpack",
    light_rig = "general_rig", combat_rig = "general_rig", medic_rig = "medical_rig"
}

for group, defs in pairs(equipment) do
    _G.PDTI_EQUIPMENT[group] = _G.PDTI_EQUIPMENT[group] or {}
    for id, def in pairs(defs) do
        if _G.PDTI_EQUIPMENT[group][id] == nil then
            _G.PDTI_EQUIPMENT[group][id] = def
        end
    end
end
