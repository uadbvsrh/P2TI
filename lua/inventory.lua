-- Inventory data model, persistence, equipment and grid operations.
local PDTI = rawget(_G, "PDTI") or {}
_G.PDTI = PDTI

PDTI.VERSION = "0.18.7"
PDTI.SCHEMA_VERSION = 6

-- Hooks on game functions. Several parts of the mod can hook the same
-- function (the AP recoil and the arm health both change the recoil), and
-- every part re-checks its hooks each frame, so a part that is not on top
-- would wrap again, every frame, until the stack overflows. So every hook
-- the mod makes remembers which parts' hooks are in its chain: a part wraps
-- again only when its hook is really gone (another mod replaced the
-- function).
PDTI.HookOwners = PDTI.HookOwners or setmetatable({}, { __mode = "k" })

function PDTI.HookHas(fn, tag)
    local owners = fn and PDTI.HookOwners[fn]
    return owners ~= nil and owners[tag] == true
end

-- new_fn wraps under_fn for the part `tag`.
function PDTI.HookMark(new_fn, under_fn, tag)
    local owners = {}
    for k in pairs(PDTI.HookOwners[under_fn] or {}) do owners[k] = true end
    owners[tag] = true
    PDTI.HookOwners[new_fn] = owners
end
PDTI.items = rawget(_G, "PDTI_ITEMS") or {}
PDTI.equipment = rawget(_G, "PDTI_EQUIPMENT") or {}

local DEFAULT_EQUIPMENT = {
    backpack = "medium_backpack",
    rig = "general_rig"
}

-- Every container. A rig has up to three sections: "rig", "rig_2", "rig_3".
-- The weapons have a slot each: the magazine in it goes into the gun (in the
-- menu: the one the heist starts with; in a heist: the next one loaded).
PDTI.CONTAINERS = { "pockets", "rig", "rig_2", "rig_3", "backpack", "gun_primary", "gun_secondary" }
PDTI.GUN_SLOTS = { gun_primary = "primary", gun_secondary = "secondary" }
PDTI.RIG_SECTIONS = { "rig", "rig_2", "rig_3" }
-- What is "to hand": the pockets and every section of the rig.
PDTI.TO_HAND = { "pockets", "rig", "rig_2", "rig_3" }
local RIG_INDEX = { rig = 1, rig_2 = 2, rig_3 = 3 }
local CONTAINER_SET = { pockets = true, rig = true, rig_2 = true, rig_3 = true, backpack = true,
    gun_primary = true, gun_secondary = true }
function PDTI.IsGunSlot(name) return PDTI.GUN_SLOTS[name] ~= nil end
function PDTI.IsRigSection(name) return RIG_INDEX[name] ~= nil end

local function log(message)
    local line = "[PDTI] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function copy_table(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == "string" or type(key) == "number" then
            result[key] = copy_table(child, seen)
        end
    end
    seen[value] = nil
    return result
end

local function serializable_item_data(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for key, child in pairs(value) do
        local key_type, child_type = type(key), type(child)
        if (key_type == "string" or key_type == "number")
            and (child_type == "string" or child_type == "number" or child_type == "boolean") then
            result[key] = child
        end
    end
    return result
end

local function shallow_data_equal(a, b)
    if a == nil and b == nil then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do
        if b[key] ~= value then return false end
    end
    for key, value in pairs(b) do
        if a[key] ~= value then return false end
    end
    return true
end

local function new_state()
    return {
        schema_version = PDTI.SCHEMA_VERSION,
        next_id = 1,
        equipment = {
            backpack = DEFAULT_EQUIPMENT.backpack,
            rig = DEFAULT_EQUIPMENT.rig
        },
        containers = {
            pockets = { items = {} },
            rig = { items = {} },
            rig_2 = { items = {} },
            rig_3 = { items = {} },
            backpack = { items = {} },
            gun_primary = { items = {} },
            gun_secondary = { items = {} }
        },
        -- Preserve save entries from optional item mods that register after
        -- this core mod has loaded. They are restored when their definition
        -- becomes available instead of being silently discarded.
        unresolved_items = {},
        unresolved_equipment = {},
        unresolved_deployable = nil,
        -- True once the ammunition you bring was chosen in the menu. Until
        -- then a heist gives each weapon the game's starting magazines.
        ammo_planned = false,
        -- The money paid for what the menu plan holds. Taking something out
        -- pays back at most this much (a plan from before the prices, or one
        -- the menu filled in, was never paid for).
        plan_paid = 0,
        plan_slots = {}
    }
end

-- The inventory belongs to the game's profile (the multi-profile manager
-- keeps the current one in Global, which survives the menu/heist reload).
function PDTI.ProfileIndex()
    local g = rawget(_G, "Global")
    local mp = type(g) == "table" and g.multi_profile or nil
    local index = type(mp) == "table" and tonumber(mp._current_profile) or nil
    if not index or index < 1 then return 1 end
    return math.floor(index)
end

-- Profile 1 keeps the file of the versions before profiles, so an existing
-- inventory becomes the first profile's.
local function profile_file(index)
    index = index or PDTI.loaded_profile or 1
    if index == 1 then return "pdti_inventory.json" end
    return "pdti_inventory_profile" .. tostring(index) .. ".json"
end
PDTI.ProfileFile = profile_file

local function save_path(index)
    return (rawget(_G, "SavePath") or "") .. profile_file(index)
end

local function safe_decode(raw)
    if not rawget(_G, "json") or type(raw) ~= "string" then return nil end
    local ok, result = pcall(json.decode, raw)
    if ok and type(result) == "table" then return result end
    return nil
end

local function read_state_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local raw = f:read("*all")
    f:close()
    return safe_decode(raw)
end

local function load_raw_state(index)
    local path = save_path(index)
    local primary = read_state_file(path)
    if primary then return primary end

    -- Recover the previous known-good save if the latest file is truncated
    -- or malformed. Never overwrite the backup while loading.
    local backup_path = path .. ".bak"
    local backup = read_state_file(backup_path)
    if backup then
        -- Remove the malformed primary so the next save cannot rotate that
        -- corrupt file over the known-good backup.
        os.remove(path)
        local source = io.open(backup_path, "r")
        if source then
            local contents = source:read("*all")
            source:close()
            if contents then
                local restored = io.open(path, "w")
                if restored then
                    restored:write(contents)
                    restored:close()
                end
            end
        end
        log("Primary save is invalid; recovered inventory from backup")
        return backup
    end
    -- A profile without an inventory of its own starts as a copy of the
    -- first profile's (it is only read, never changed).
    if index and index ~= 1 then
        local template = read_state_file(save_path(1))
        if template then return template end
    end
    return nil
end

-- The footprint of a magazine follows its weapon type and how many rounds it
-- holds. Each type has three steps: from the first a magazine takes 2 cells
-- (1x2), from the second 3 in one line (1x3), from the third a 2x2 square;
-- below the first it takes one cell.
PDTI.MAGAZINE_STEPS = {
    shotgun = { 6, 10, 20 },
    assault_rifle = { 30, 60, 100 },
    smg = { 32, 50, 80 },
    pistol = { 20, 33, 50 },
    revolver = { 8, 20, 40 },
    snp = { 10, 20, 30 },
    lmg = { 60, 100, 150 },
    minigun = { 200, 400, 700 },
    flamethrower = { 150, 300, 500 },
    default = { 30, 60, 100 }
}
local MAGAZINE_SHAPES = { { 1, 1 }, { 1, 2 }, { 1, 3 }, { 2, 2 } }

-- Akimbo guns use one magazine per gun, so their magazines (half the
-- weapon's capacity) are sized like any other.
function PDTI.MagazineSize(capacity, class, akimbo)
    local c = tonumber(capacity) or 0
    local steps = PDTI.MAGAZINE_STEPS[class] or PDTI.MAGAZINE_STEPS.default
    local step = 1
    for i, at in ipairs(steps) do
        if c >= at then step = i + 1 end
    end
    local shape = MAGAZINE_SHAPES[step]
    return shape[1], shape[2]
end

-- The item itself, or its id: some calls only know the id, others also
-- know the item's data (the capacity of a magazine decides its size).
local function item_ref(ref)
    if type(ref) == "table" then return ref.item_id, ref.data end
    return ref, nil
end
PDTI.ItemRef = item_ref

local function dimensions(item, rotated, container_name)
    local def = item and PDTI.items[item.item_id]
    if not def then return nil, nil end
    -- A weapon's slot holds its magazine whatever its size: one cell each.
    if container_name and PDTI.GUN_SLOTS[container_name] then return 1, 1 end
    local w, h = tonumber(def.w), tonumber(def.h)
    if def.size_by_capacity then
        local data = type(item.data) == "table" and item.data or nil
        if data and tonumber(data.capacity) then
            w, h = PDTI.MagazineSize(data.capacity, data.mag_class, data.akimbo == true)
        end
    end
    if not w or not h or w < 1 or h < 1 then return nil, nil end
    w, h = math.floor(w), math.floor(h)
    if rotated then return h, w end
    return w, h
end

local function is_integer(value)
    return type(value) == "number" and value >= 0 and value % 1 == 0
end

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

local function valid_container_name(name)
    return CONTAINER_SET[name] == true
end

local state

-- A section that the rig does not have: nothing fits in it.
local NO_SECTION = { w = 0, h = 0, max_weight = 0, missing = true }

-- The sections of a rig (a rig without sections is one section).
local function rig_sections(rig)
    if not rig then return {} end
    if type(rig.sections) == "table" then return rig.sections end
    return { rig }
end
PDTI.RigSections = rig_sections

local function get_equipment_definition(container_name, source_state)
    local eq = (source_state or state).equipment or {}
    local index = RIG_INDEX[container_name]
    if index then
        local rig = PDTI.equipment.rigs[eq.rig]
        if not rig then return index == 1 and nil or NO_SECTION end
        return rig_sections(rig)[index] or NO_SECTION
    elseif container_name == "backpack" then
        return PDTI.equipment.backpacks[eq.backpack]
    elseif PDTI.GUN_SLOTS[container_name] then
        -- Room for the biggest magazine (2x2), or the two of akimbo guns.
        -- One magazine per gun: two cells for akimbo guns.
        return { w = 2, h = 1, max_weight = 10, gun = true }
    end
    return { w = 2, h = 2, max_weight = 4 }
end

-- The rig itself (not a section).
local function get_rig(source_state)
    local eq = (source_state or state).equipment or {}
    return PDTI.equipment.rigs[eq.rig]
end

local function container_size(container_name, source_state)
    local def = get_equipment_definition(container_name, source_state)
    if not def then return nil, nil end
    return def.w, def.h
end

local function item_allowed(container_name, item_id, source_state)
    local def = PDTI.items[item_id]
    if not def then return false, "unknown item definition" end
    local rule_name = RIG_INDEX[container_name] and "rig" or container_name
    if not (def.allowed and def.allowed[rule_name]) then
        return false, "item is not allowed in " .. rule_name
    end
    if RIG_INDEX[container_name] then
        local section = get_equipment_definition(container_name, source_state)
        if not section or section.missing then
            return false, "the rig has no such section"
        end
        if section.items and not section.items[item_id] then
            return false, "this part of the rig only holds " .. tostring(section.name or "other items")
        end
        if section.categories and not section.categories[def.category] then
            return false, "item category is not supported by this part of the rig"
        end
        local rig = get_rig(source_state)
        if rig and rig.allowed_categories and not rig.allowed_categories[def.category] then
            return false, "item category is not supported by the equipped rig"
        end
    end
    return true
end

-- The weight of a whole stack. Ammunition weighs by its rounds: a loose
-- round by its weapon type, a magazine as the empty magazine plus the rounds
-- it holds (a full one is heavier than an empty one).
PDTI.ROUND_WEIGHTS = {
    pistol = 0.012, revolver = 0.016, smg = 0.011, assault_rifle = 0.012, lmg = 0.012,
    minigun = 0.012, snp = 0.03, shotgun = 0.045, flamethrower = 0.005,
    grenade_launcher = 0.23, bow = 0.035, crossbow = 0.04, default = 0.012
}
function PDTI.RoundWeight(class)
    return PDTI.ROUND_WEIGHTS[class] or PDTI.ROUND_WEIGHTS.default
end
-- An empty magazine: a little for the body, more for every round it takes.
function PDTI.MagazineEmptyWeight(capacity)
    return 0.06 + 0.004 * math.max(0, tonumber(capacity) or 0)
end

local function item_weight(item)
    local def = item and PDTI.items[item.item_id]
    if not def then return 0 end
    local amount = tonumber(item.amount) or 1
    local data = type(item.data) == "table" and item.data or {}
    if def.weight_by_rounds and tonumber(data.capacity) then
        return (PDTI.MagazineEmptyWeight(data.capacity)
            + PDTI.RoundWeight(data.mag_class) * math.max(0, tonumber(data.rounds) or 0)) * amount
    end
    if def.weight_per_round then
        return PDTI.RoundWeight(data.mag_class) * amount
    end
    return (tonumber(def.weight) or 0) * amount
end
PDTI.ItemWeight = item_weight

local function container_weight(container_name, source_state)
    local src = source_state or state
    local c = src.containers[container_name]
    if not c or type(c.items) ~= "table" then return 0 end
    local total = 0
    for _, item in ipairs(c.items) do
        local def = PDTI.items[item.item_id]
        if def then total = total + item_weight(item) end
    end
    return total
end

local function total_weight(source_state)
    local src = source_state or state
    local total = 0
    for _, name in ipairs(PDTI.CONTAINERS) do
        total = total + container_weight(name, src)
    end
    return total
end

local function container_weight_limit(container_name, source_state)
    local def = get_equipment_definition(container_name, source_state)
    return def and tonumber(def.max_weight) or math.huge
end

local function placement_check(container_name, ref, x, y, rotated, ignore_id, source_state)
    local item_id, item_data = item_ref(ref)
    local src = source_state or state
    if not valid_container_name(container_name) then return false, "unknown container" end
    if not src.containers[container_name] then return false, "container data missing" end

    local gun_slot = PDTI.GUN_SLOTS[container_name]
    if gun_slot then
        -- Only a magazine of this weapon, one (two for akimbo guns).
        local magazine = PDTI.Ammo and PDTI.Ammo.MAGAZINE_ITEM or "spare_magazine"
        if item_id ~= magazine or type(item_data) ~= "table" or item_data.slot ~= gun_slot then
            return false, "only a magazine of this weapon goes here"
        end
        local others = 0
        for _, other in ipairs(src.containers[container_name].items) do
            if other.instance_id ~= ignore_id then others = others + 1 end
        end
        if others >= (item_data.akimbo and 2 or 1) then return false, "the weapon already has its magazine" end
    else
        local allowed, reason = item_allowed(container_name, item_id, src)
        if not allowed then return false, reason end
    end

    local w, h = dimensions({ item_id = item_id, data = item_data }, rotated == true, container_name)
    if not w then return false, "invalid item dimensions" end
    if not is_integer(x) or not is_integer(y) then
        return false, "grid coordinates must be non-negative integers"
    end

    local cw, ch = container_size(container_name, src)
    if not cw or not ch or x + w > cw or y + h > ch then
        return false, "item exceeds container bounds"
    end

    local items = src.containers[container_name].items
    for i = 1, #items do
        local other = items[i]
        if other.instance_id ~= ignore_id then
            local ow, oh = dimensions(other, other.rotated == true, container_name)
            if ow and oh and overlaps(x, y, w, h, other.x, other.y, ow, oh) then
                return false, "space occupied"
            end
        end
    end
    return true
end

-- Puts an item into the first container of the list where it fits (it may be
-- turned). Works on any state table. Returns the container or nil.
local function place_anywhere(src, item, names)
    local def = PDTI.items[item.item_id]
    if not def then return nil end
    local weight = item_weight(item)
    for _, name in ipairs(names) do
        if container_weight(name, src) + weight <= container_weight_limit(name, src) then
            local cw, ch = container_size(name, src)
            for r = 0, 1 do
                local rotated = r == 1
                for y = 0, (ch or 0) - 1 do
                    for x = 0, (cw or 0) - 1 do
                        if placement_check(name, item, x, y, rotated, item.instance_id, src) then
                            item.x, item.y, item.rotated = x, y, rotated
                            table.insert(src.containers[name].items, item)
                            return name
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function sanitize_loaded(data)
    local clean = new_state()
    if type(data) ~= "table" then return clean end

    -- Migrate the 0.1.0 save shape (no schema_version/equipment) without
    -- discarding its existing container items.
    if tonumber(data.schema_version) == 2 or data.containers then
        if type(data.equipment) == "table" then
            local renamed = rawget(_G, "PDTI_EQUIPMENT_RENAMED") or {}
            for _, kind in ipairs({ "backpack", "rig" }) do
                local id = data.equipment[kind]
                if type(id) == "string" and renamed[id] then data.equipment[kind] = renamed[id] end
            end
            if PDTI.equipment.backpacks[data.equipment.backpack] then
                clean.equipment.backpack = data.equipment.backpack
            elseif type(data.equipment.backpack) == "string" then
                clean.unresolved_equipment.backpack = data.equipment.backpack
            end
            if PDTI.equipment.rigs[data.equipment.rig] then
                clean.equipment.rig = data.equipment.rig
            elseif type(data.equipment.rig) == "string" then
                clean.unresolved_equipment.rig = data.equipment.rig
            end
        end
        clean.next_id = math.max(1, math.floor(tonumber(data.next_id) or 1))
    end
    clean.ammo_planned = data.ammo_planned == true
    clean.plan_paid = math.max(0, math.floor(tonumber(data.plan_paid) or 0))
    clean.plan_slots = {}
    if type(data.plan_slots) == "table" then
        for _, slot in ipairs({ "primary", "secondary" }) do
            local entry = data.plan_slots[slot]
            if type(entry) == "table" then
                local keep = {}
                for _, field in ipairs({ "gun_size", "gun_bullet", "pick_size", "pick_bullet", "pick_load", "gun_filled" }) do
                    if type(entry[field]) == "string" then keep[field] = entry[field] end
                end
                clean.plan_slots[slot] = keep
            end
        end
    end
    if type(data.unresolved_equipment) == "table" then
        for kind, equipment_id in pairs(data.unresolved_equipment) do
            if (kind == "backpack" or kind == "rig") and type(equipment_id) == "string" then
                clean.unresolved_equipment[kind] = equipment_id
            end
        end
    end

    -- The deployable the player picked. It is kept even when the item is
    -- unknown, so a save is not lost when an optional mod loads later.
    if type(data.deployable) == "string" and data.deployable ~= "" then
        if PDTI.items[data.deployable] then
            clean.deployable = data.deployable
        else
            clean.unresolved_deployable = data.deployable
        end
    end

    local seen = {}
    if type(data.unresolved_items) == "table" then
        for _, pending in ipairs(data.unresolved_items) do
            if type(pending) == "table" and valid_container_name(pending.container)
                and type(pending.item) == "table" and type(pending.item.item_id) == "string" then
                local id = tonumber(pending.item.instance_id)
                local x, y = tonumber(pending.item.x), tonumber(pending.item.y)
                local amount = math.floor(tonumber(pending.item.amount) or 1)
                if id and id >= 1 and id % 1 == 0 and not seen[id]
                    and is_integer(x) and is_integer(y) and amount >= 1 and amount <= 999
                    and not PDTI.items[pending.item.item_id] then
                    local candidate = {
                        instance_id = id, item_id = pending.item.item_id,
                        x = x, y = y, rotated = pending.item.rotated == true,
                        amount = amount, data = serializable_item_data(pending.item.data)
                    }
                    table.insert(clean.unresolved_items, { container = pending.container, item = candidate })
                    seen[id] = true
                    clean.next_id = math.max(clean.next_id, id + 1)
                end
            end
        end
    end
    local overflow = {}
    -- Stacks above the item's limit (an older version allowed more): the
    -- rest becomes new stacks.
    local splits = {}
    for _, name in ipairs(PDTI.CONTAINERS) do
        local old = data.containers and data.containers[name]
        local old_items = old and old.items
        if type(old_items) == "table" then
            for _, item in ipairs(old_items) do
                if type(item) == "table" and type(item.item_id) == "string" then
                    local id = tonumber(item.instance_id)
                    local x, y = tonumber(item.x), tonumber(item.y)
                    local amount = math.floor(tonumber(item.amount) or 1)
                    local def = PDTI.items[item.item_id]
                    local max_stack = def and math.max(1, math.floor(tonumber(def.max_stack) or 1)) or 999
                    local rotated = item.rotated == true
                    local extra = 0
                    if def and amount > max_stack and amount <= 100000 then
                        extra = amount - max_stack
                        amount = max_stack
                    end
                    if id and id >= 1 and id % 1 == 0 and not seen[id]
                        and is_integer(x) and is_integer(y)
                        and amount >= 1 and amount <= max_stack then
                        if extra > 0 then
                            splits[#splits + 1] = { item_id = item.item_id, amount = extra,
                                max_stack = max_stack, data = serializable_item_data(item.data) }
                        end
                        local candidate = {
                            instance_id = id, item_id = item.item_id,
                            x = x, y = y, rotated = rotated, amount = amount,
                            data = serializable_item_data(item.data)
                        }
                        if def then
                            local ok = placement_check(name, candidate, x, y, rotated, nil, clean)
                            local weight_ok = container_weight(name, clean)
                                + item_weight(candidate) <= container_weight_limit(name, clean)
                            if ok and weight_ok then
                                table.insert(clean.containers[name].items, candidate)
                            else
                                -- It does not fit where it was (the rig or the
                                -- backpack changed): it is placed elsewhere below.
                                overflow[#overflow + 1] = candidate
                            end
                            seen[id] = true
                            clean.next_id = math.max(clean.next_id, id + 1)
                        else
                            table.insert(clean.unresolved_items, {
                                container = name,
                                item = candidate
                            })
                            seen[id] = true
                            clean.next_id = math.max(clean.next_id, id + 1)
                        end
                    end
                end
            end
        end
    end
    for _, split in ipairs(splits) do
        local left = split.amount
        while left > 0 do
            local take = math.min(split.max_stack, left)
            overflow[#overflow + 1] = {
                instance_id = clean.next_id, item_id = split.item_id, x = 0, y = 0,
                rotated = false, amount = take, data = copy_table(split.data)
            }
            clean.next_id = clean.next_id + 1
            left = left - take
        end
    end
    for _, item in ipairs(overflow) do
        local placed = place_anywhere(clean, item, PDTI.CONTAINERS)
        if not placed then
            log("an item of the save had no room any more and was dropped: " .. tostring(item.item_id))
        end
    end
    return clean
end

PDTI.loaded_profile = PDTI.ProfileIndex()
state = sanitize_loaded(load_raw_state(PDTI.loaded_profile))

local function save()
    -- In a heist the inventory lives in memory only: the next heist starts
    -- again with what was chosen in the menu.
    if PDTI.session_only then
        PDTI.inventory_revision = (PDTI.inventory_revision or 0) + 1
        return true
    end
    if not rawget(_G, "json") then
        log("JSON library unavailable; inventory changes are session-only")
        return false
    end

    state.schema_version = PDTI.SCHEMA_VERSION
    local ok, encoded = pcall(json.encode, state)
    if not ok or type(encoded) ~= "string" then
        log("Could not encode inventory save")
        return false
    end

    local path = save_path()
    local temp_path = path .. ".tmp"
    local backup_path = path .. ".bak"
    local f, err = io.open(temp_path, "w")
    if not f then
        log("Could not open temporary save: " .. tostring(err))
        return false
    end

    local write_ok, write_err = f:write(encoded)
    local close_ok, close_err = f:close()
    if not write_ok or close_ok == nil then
        os.remove(temp_path)
        log("Could not write temporary save: " .. tostring(write_err or close_err))
        return false
    end

    -- Keep one previous save. Rename is atomic on the same filesystem on
    -- supported platforms; restore the backup if promoting the new file fails.
    local probe = io.open(path, "r")
    local had_primary = probe ~= nil
    if probe then probe:close() end
    if had_primary then
        local primary_is_valid = read_state_file(path) ~= nil
        if primary_is_valid then
            os.remove(backup_path)
            local moved_old, move_err = os.rename(path, backup_path)
            if not moved_old then
                os.remove(temp_path)
                log("Could not rotate previous save: " .. tostring(move_err))
                return false
            end
        else
            -- Never rotate a malformed primary over a valid recovery copy.
            local removed, remove_err = os.remove(path)
            if not removed then
                os.remove(temp_path)
                log("Could not remove malformed primary save: " .. tostring(remove_err))
                return false
            end
            had_primary = false
        end
    end

    local promoted, promote_err = os.rename(temp_path, path)
    if not promoted then
        if had_primary then os.rename(backup_path, path) end
        os.remove(temp_path)
        log("Could not promote temporary save: " .. tostring(promote_err))
        return false
    end
    -- Anything that shows the inventory (the HUD, the ammunition) follows
    -- this number and updates when it changes.
    PDTI.inventory_revision = (PDTI.inventory_revision or 0) + 1
    return true
end

function PDTI.RegisterItem(item_id, definition)
    if type(item_id) ~= "string" or item_id == "" or type(definition) ~= "table" then
        return false, "expected item id and definition table"
    end
    local w, h = tonumber(definition.w), tonumber(definition.h)
    if not w or not h or w < 1 or h < 1 or w % 1 ~= 0 or h % 1 ~= 0
        or w == math.huge or h == math.huge then
        return false, "invalid item dimensions"
    end
    if type(definition.allowed) ~= "table" then return false, "definition.allowed is required" end
    local has_allowed_container = false
    for container_name, allowed in pairs(definition.allowed) do
        if container_name ~= "pockets" and container_name ~= "rig" and container_name ~= "backpack" then
            return false, "unknown allowed container: " .. tostring(container_name)
        end
        if type(allowed) ~= "boolean" then return false, "allowed values must be booleans" end
        if allowed then has_allowed_container = true end
    end
    if not has_allowed_container then return false, "item must be allowed in at least one container" end
    if type(definition.category) ~= "string" or definition.category == "" then
        return false, "definition.category is required"
    end
    local max_stack = tonumber(definition.max_stack) or 1
    local weight = tonumber(definition.weight) or 0
    if max_stack ~= max_stack or weight ~= weight or max_stack < 1 or weight < 0
        or max_stack == math.huge or weight == math.huge then
        return false, "invalid stack limit or weight"
    end

    local copy = copy_table(definition)
    copy.w, copy.h = math.floor(w), math.floor(h)
    copy.max_stack, copy.weight = math.floor(max_stack), weight
    PDTI.items[item_id] = copy

    -- Restore saved instances which were unknown during initial save loading.
    local restored = 0
    for i = #state.unresolved_items, 1, -1 do
        local pending = state.unresolved_items[i]
        if pending.item and pending.item.item_id == item_id then
            local item = pending.item
            local amount = math.floor(tonumber(item.amount) or 1)
            if amount >= 1 and amount <= copy.max_stack then
                local ok = placement_check(pending.container, item, item.x, item.y,
                    item.rotated, nil, state)
                local weight_ok = container_weight(pending.container)
                    + item_weight(item) <= container_weight_limit(pending.container)
                if ok and weight_ok then
                    table.insert(state.containers[pending.container].items, item)
                    table.remove(state.unresolved_items, i)
                    restored = restored + 1
                end
            end
        end
    end
    if restored > 0 then
        log("Restored " .. restored .. " saved instance(s) for registered item " .. item_id)
        save()
    end

    -- A deployable that was picked before its item was known can be picked
    -- again now.
    if state.unresolved_deployable == item_id then
        if PDTI.SetDeployable(item_id) then
            state.unresolved_deployable = nil
            save()
        end
    end
    return true
end

function PDTI.GetUnresolvedItems()
    return copy_table(state.unresolved_items or {})
end

function PDTI.GetUnresolvedEquipment()
    return copy_table(state.unresolved_equipment or {})
end

function PDTI.GetState()
    return copy_table(state)
end

function PDTI.GetContainer(name)
    if not valid_container_name(name) then return nil end
    return copy_table(state.containers[name])
end

function PDTI.GetItemDefinition(item_id)
    return copy_table(PDTI.items[item_id])
end

-- Read-only search over every item in the inventory.
-- The predicate receives (container_name, item). The item table is the live
-- one, so callers must not modify it; use EditItems/RemoveItem to change
-- anything. Every entry is { container = name, item = item }.
function PDTI.FindItems(predicate)
    local out = {}
    if type(predicate) ~= "function" then return out end
    for _, name in ipairs(PDTI.CONTAINERS) do
        local items = state.containers[name] and state.containers[name].items
        for _, item in ipairs(items or {}) do
            if predicate(name, item) then
                out[#out + 1] = { container = name, item = item }
            end
        end
    end
    return out
end

function PDTI.GetItemDefinitions()
    return copy_table(PDTI.items)
end

function PDTI.GetContainerInfo(name)
    if not valid_container_name(name) then return nil end
    local w, h = container_size(name)
    return {
        name = name, width = w, height = h,
        weight = container_weight(name),
        weight_limit = container_weight_limit(name),
        items = copy_table(state.containers[name].items)
    }
end


function PDTI.ValidateState()
    local errors = {}
    local seen_ids = {}
    for _, name in ipairs(PDTI.CONTAINERS) do
        local container = state.containers[name]
        if not container or type(container.items) ~= "table" then
            errors[#errors + 1] = name .. ": missing item list"
        else
            for _, item in ipairs(container.items) do
                if type(item) ~= "table" then
                    errors[#errors + 1] = name .. ": non-table item entry"
                else
                    local instance_id = item.instance_id
                    if type(instance_id) ~= "number" or instance_id < 1 or instance_id % 1 ~= 0 then
                        errors[#errors + 1] = name .. ": invalid item instance id"
                    elseif seen_ids[instance_id] then
                        errors[#errors + 1] = "duplicate instance id " .. tostring(instance_id)
                    else
                        seen_ids[instance_id] = true
                    end
                    local ok, reason = placement_check(name, item, item.x, item.y,
                        item.rotated, instance_id)
                    if not ok then
                        errors[#errors + 1] = name .. "/" .. tostring(instance_id)
                            .. ": " .. tostring(reason)
                    end
                end
            end
            if container_weight(name) > container_weight_limit(name) then
                errors[#errors + 1] = name .. ": weight limit exceeded"
            end
        end
    end
    return #errors == 0, errors
end

function PDTI.GetTotalWeight()
    return total_weight()
end

-- The footprint of an item (or { item_id, data }), turned or not.
function PDTI.ItemSize(ref, rotated, container_name)
    if type(ref) == "string" then ref = { item_id = ref } end
    return dimensions(ref, rotated == true, container_name)
end

-- Would PDTI.MoveItem work? Checks the place and the weight, changes nothing.
function PDTI.CanMoveItem(from_name, instance_id, to_name, x, y, rotated)
    if not valid_container_name(from_name) or not valid_container_name(to_name) then
        return false, "unknown container"
    end
    local item
    for _, it in ipairs(state.containers[from_name].items) do
        if it.instance_id == instance_id then item = it break end
    end
    if not item then return false, "item not found" end
    local ok, reason = placement_check(to_name, item, x, y, rotated, item.instance_id)
    if not ok then return false, reason end
    if to_name ~= from_name
        and container_weight(to_name) + item_weight(item) > container_weight_limit(to_name) then
        return false, "destination container weight limit exceeded"
    end
    return true
end

function PDTI.CanPlace(container_name, item_id, x, y, rotated, ignore_id)
    return placement_check(container_name, item_id, x, y, rotated, ignore_id)
end

function PDTI.FindFreeSpace(container_name, item_id, allow_rotation)
    if not valid_container_name(container_name) then return nil, "unknown container" end
    local cw, ch = container_size(container_name)
    if not cw or not ch then return nil, "container dimensions unavailable" end

    for rotated_index = 0, (allow_rotation and 1 or 0) do
        local rotated = rotated_index == 1
        for y = 0, ch - 1 do
            for x = 0, cw - 1 do
                local ok = placement_check(container_name, item_id, x, y, rotated)
                if ok then return x, y, rotated end
            end
        end
    end
    return nil, "no free space"
end

function PDTI.AddItemAuto(container_name, item_id, amount, item_data, allow_rotation)
    local x, y, rotated_or_reason = PDTI.FindFreeSpace(container_name,
        { item_id = item_id, data = item_data }, allow_rotation)
    if x == nil then return false, y end
    return PDTI.AddItem(container_name, item_id, x, y, rotated_or_reason, amount, item_data)
end

function PDTI.AddItem(container_name, item_id, x, y, rotated, amount, item_data)
    local def = PDTI.items[item_id]
    if not def then return false, "unknown item" end
    local count = math.floor(tonumber(amount) or 1)
    local max_stack = math.max(1, math.floor(tonumber(def.max_stack) or 1))
    if count < 1 or count > max_stack then return false, "invalid stack amount" end

    local ok, reason = placement_check(container_name, { item_id = item_id, data = item_data }, x, y, rotated)
    if not ok then return false, reason end

    local weight_after = container_weight(container_name)
        + item_weight({ item_id = item_id, amount = count, data = item_data })
    if weight_after > container_weight_limit(container_name) then
        return false, "container weight limit exceeded"
    end

    local instance = {
        instance_id = state.next_id,
        item_id = item_id, x = x, y = y,
        rotated = rotated == true, amount = count
    }
    if type(item_data) == "table" then instance.data = serializable_item_data(item_data) end

    local previous_next_id = state.next_id
    state.next_id = state.next_id + 1
    table.insert(state.containers[container_name].items, instance)
    if not save() then
        table.remove(state.containers[container_name].items)
        state.next_id = previous_next_id
        return false, "could not save inventory; item addition rolled back"
    end
    return true, copy_table(instance)
end

function PDTI.FindItem(container_name, instance_id)
    if not valid_container_name(container_name) then return nil end
    for _, item in ipairs(state.containers[container_name].items) do
        if item.instance_id == instance_id then return copy_table(item) end
    end
    return nil
end

function PDTI.RemoveItem(container_name, instance_id, amount)
    if not valid_container_name(container_name) then return false, "unknown container" end
    local items = state.containers[container_name].items
    for i = 1, #items do
        local item = items[i]
        if item.instance_id == instance_id then
            local take = math.floor(tonumber(amount) or item.amount or 1)
            if take < 1 or take > (item.amount or 1) then return false, "invalid removal amount" end
            if take < (item.amount or 1) then
                local previous_amount = item.amount
                item.amount = item.amount - take
                if not save() then
                    item.amount = previous_amount
                    return false, "could not save inventory; item removal rolled back"
                end
                return true, copy_table(item), take
            end
            local removed = table.remove(items, i)
            if not save() then
                table.insert(items, i, removed)
                return false, "could not save inventory; item removal rolled back"
            end
            return true, copy_table(removed), take
        end
    end
    return false, "item not found"
end

-- Several item edits with ONE save, all or nothing.
--   spec.update = { {container = "rig", instance_id = 7, data = {rounds = 12}} }  (data is merged)
--   spec.set_amount = { {container = "rig", instance_id = 7, amount = 30} }        (stack size)
--   spec.remove = { {container = "rig", instance_id = 9} }                        (whole stack)
-- Used by the magazine sync so a reload costs a single disk write.
function PDTI.EditItems(spec)
    spec = spec or {}
    local backup = copy_table(state.containers)
    local function fail(reason)
        state.containers = backup
        return false, reason
    end
    local function locate(container_name, instance_id)
        if not valid_container_name(container_name) then return nil end
        local items = state.containers[container_name].items
        for i = 1, #items do
            if items[i].instance_id == instance_id then return items, i end
        end
        return nil
    end
    for _, change in ipairs(spec.update or {}) do
        local items, i = locate(change.container, change.instance_id)
        if not items then return fail("item not found") end
        local merged = {}
        for k, v in pairs(items[i].data or {}) do merged[k] = v end
        for k, v in pairs(change.data or {}) do merged[k] = v end
        items[i].data = serializable_item_data(merged)
    end
    for _, change in ipairs(spec.set_amount or {}) do
        local items, i = locate(change.container, change.instance_id)
        if not items then return fail("item not found") end
        local amount = math.floor(tonumber(change.amount) or 0)
        if amount < 1 then return fail("invalid stack amount") end
        local def = PDTI.items[items[i].item_id]
        local max_stack = math.max(1, math.floor(tonumber(def and def.max_stack) or 1))
        if amount > max_stack then return fail("stack amount is above the limit") end
        items[i].amount = amount
    end
    for _, change in ipairs(spec.remove or {}) do
        local items, i = locate(change.container, change.instance_id)
        if not items then return fail("item not found") end
        table.remove(items, i)
    end
    if not save() then return fail("could not save inventory; edit rolled back") end
    return true
end

-- Gives back units taken by a reservation (see PDTI.UseItem). Used when a
-- gameplay effect fails after its cost was already removed and saved, so the
-- worst outcome of a crash is a lost item, never a free effect.
-- Returns ok, item_copy_or_reason, persisted.
function PDTI.RestoreItemUnits(container_name, snapshot, units)
    if not valid_container_name(container_name) then return false, "unknown container" end
    units = math.floor(tonumber(units) or 0)
    if type(snapshot) ~= "table" or not PDTI.items[snapshot.item_id] or units < 1 then
        return false, "invalid restore request"
    end
    local items = state.containers[container_name].items
    local target
    for _, item in ipairs(items) do
        if item.instance_id == snapshot.instance_id then target = item; break end
    end

    local inserted = false
    if target then
        target.amount = (target.amount or 1) + units
    else
        local x, y, rotated = snapshot.x, snapshot.y, snapshot.rotated == true
        local ok = placement_check(container_name, snapshot, x, y, rotated)
        if not ok then
            local fx, fy, frot = PDTI.FindFreeSpace(container_name, snapshot, true)
            if fx == nil then return false, "no room to restore item" end
            x, y, rotated = fx, fy, frot
        end
        target = {
            instance_id = snapshot.instance_id, item_id = snapshot.item_id,
            x = x, y = y, rotated = rotated == true, amount = units
        }
        if type(snapshot.data) == "table" then target.data = serializable_item_data(snapshot.data) end
        table.insert(items, target)
        inserted = true
    end

    -- A failed save here is logged but the units stay restored in memory:
    -- the on-disk copy is then short by one item, which can only lose an
    -- item after a crash, never duplicate one.
    local persisted = save()
    if not persisted then log("Restored item units could not be saved") end
    return true, copy_table(target), persisted
end

function PDTI.MergeStacks(container_name, source_id, target_id, amount)
    if not valid_container_name(container_name) then return false, "unknown container" end
    if source_id == target_id then return false, "source and target are identical" end

    local items = state.containers[container_name].items
    local source, target
    for _, item in ipairs(items) do
        if item.instance_id == source_id then source = item end
        if item.instance_id == target_id then target = item end
    end
    if not source or not target then return false, "source or target item not found" end
    if source.item_id ~= target.item_id or not shallow_data_equal(source.data, target.data) then
        return false, "items cannot be stacked together"
    end

    local def = PDTI.items[source.item_id]
    local max_stack = math.max(1, math.floor(tonumber(def.max_stack) or 1))
    local available = math.max(0, max_stack - (target.amount or 1))
    local requested = math.floor(tonumber(amount) or (source.amount or 1))
    if requested < 1 then return false, "invalid merge amount" end
    local moved = math.min(requested, source.amount or 1, available)
    if moved <= 0 then return false, "target stack is already full" end

    local source_before, target_before = source.amount or 1, target.amount or 1
    local source_index
    source.amount = source_before - moved
    target.amount = target_before + moved
    if source.amount <= 0 then
        for i = #items, 1, -1 do
            if items[i].instance_id == source_id then
                source_index = i
                table.remove(items, i)
                break
            end
        end
    end
    if not save() then
        source.amount, target.amount = source_before, target_before
        if source_index then table.insert(items, source_index, source) end
        return false, "could not save inventory; stack merge rolled back"
    end
    return true, moved, PDTI.FindItem(container_name, target_id), PDTI.FindItem(container_name, source_id)
end

function PDTI.SplitStack(container_name, instance_id, amount, x, y, rotated)
    if not valid_container_name(container_name) then return false, "unknown container" end
    local source
    for _, item in ipairs(state.containers[container_name].items) do
        if item.instance_id == instance_id then source = item; break end
    end
    if not source then return false, "item not found" end

    local split_amount = math.floor(tonumber(amount) or 0)
    if split_amount < 1 or split_amount >= (source.amount or 1) then
        return false, "split amount must be smaller than the source stack"
    end
    local ok, reason = placement_check(container_name, source, x, y, rotated)
    if not ok then return false, reason end

    local previous_amount, previous_next_id = source.amount, state.next_id
    source.amount = source.amount - split_amount
    local new_item = {
        instance_id = state.next_id,
        item_id = source.item_id,
        x = x, y = y, rotated = rotated == true,
        amount = split_amount,
        data = copy_table(source.data)
    }
    state.next_id = state.next_id + 1
    table.insert(state.containers[container_name].items, new_item)
    if not save() then
        table.remove(state.containers[container_name].items)
        source.amount = previous_amount
        state.next_id = previous_next_id
        return false, "could not save inventory; stack split rolled back"
    end
    return true, copy_table(new_item), copy_table(source)
end

function PDTI.MoveItem(from_name, instance_id, to_name, x, y, rotated)
    if not valid_container_name(from_name) or not valid_container_name(to_name) then
        return false, "unknown container"
    end
    local source = state.containers[from_name].items
    local index, item
    for i = 1, #source do
        if source[i].instance_id == instance_id then index, item = i, source[i]; break end
    end
    if not item then return false, "item not found" end

    local old = { x = item.x, y = item.y, rotated = item.rotated }
    table.remove(source, index)

    local ok, reason = placement_check(to_name, item, x, y, rotated, item.instance_id)
    if not ok then
        table.insert(source, index, item)
        return false, reason
    end

    local def = PDTI.items[item.item_id]
    local new_weight = container_weight(to_name) + item_weight(item)
    if new_weight > container_weight_limit(to_name) then
        table.insert(source, index, item)
        return false, "destination container weight limit exceeded"
    end

    item.x, item.y, item.rotated = x, y, rotated == true
    table.insert(state.containers[to_name].items, item)
    if not save() then
        local destination_items = state.containers[to_name].items
        for i = #destination_items, 1, -1 do
            if destination_items[i].instance_id == instance_id then
                table.remove(destination_items, i)
                break
            end
        end
        item.x, item.y, item.rotated = old.x, old.y, old.rotated
        table.insert(source, index, item)
        return false, "could not save inventory; item move rolled back"
    end
    return true, copy_table(item), old
end

-- Changes the backpack or the rig. Everything that was in it stays where it
-- was when it still fits there; the rest is put where it fits: in the new
-- equipment first, then in the other containers. When something does not
-- fit anywhere, nothing changes.
function PDTI.SetEquipment(kind, equipment_id)
    if kind ~= "backpack" and kind ~= "rig" then return false, "unknown equipment slot" end
    local group = kind == "backpack" and "backpacks" or "rigs"
    local def = PDTI.equipment[group] and PDTI.equipment[group][equipment_id]
    if not def then return false, "unknown equipment item" end

    local candidate = copy_table(state)
    candidate.equipment[kind] = equipment_id
    local affected = kind == "rig" and PDTI.RIG_SECTIONS or { "backpack" }

    -- Take out what was in the old equipment.
    local moving = {}
    for _, name in ipairs(affected) do
        for _, item in ipairs(candidate.containers[name].items) do moving[#moving + 1] = { from = name, item = item } end
        candidate.containers[name].items = {}
    end
    -- First the items that still fit where they are, then the rest.
    local rest = {}
    for _, entry in ipairs(moving) do
        local item = entry.item
        local item_def = PDTI.items[item.item_id]
        local weight = item_weight(item)
        if placement_check(entry.from, item, item.x, item.y, item.rotated, item.instance_id, candidate)
            and container_weight(entry.from, candidate) + weight <= container_weight_limit(entry.from, candidate) then
            table.insert(candidate.containers[entry.from].items, item)
        else
            rest[#rest + 1] = item
        end
    end
    local order = {}
    for _, name in ipairs(affected) do order[#order + 1] = name end
    for _, name in ipairs(PDTI.CONTAINERS) do
        local inside = false
        for _, a in ipairs(affected) do if a == name then inside = true end end
        if not inside then order[#order + 1] = name end
    end
    for _, item in ipairs(rest) do
        if not place_anywhere(candidate, item, order) then
            local item_def = PDTI.items[item.item_id]
            return false, "cannot equip: no room for " .. tostring(item_def and item_def.name or item.item_id)
        end
    end

    local previous = state
    state = candidate
    if not save() then
        state = previous
        return false, "could not save inventory; equipment change rolled back"
    end
    return true
end


-- The deployable the player picked. It is an item id, or nil when the
-- vanilla deployables are used.
function PDTI.GetDeployable()
    return state.deployable
end

-- Picks the deployable. Passing nil clears the pick and gives the deploy
-- back to the game.
function PDTI.SetDeployable(item_id)
    if item_id == nil then
        local previous = state.deployable
        state.deployable = nil
        if not save() then
            state.deployable = previous
            return false, "could not save inventory; deployable change rolled back"
        end
        return true
    end

    if type(item_id) ~= "string" or item_id == "" then
        return false, "expected an item id"
    end
    local def = PDTI.items[item_id]
    if not def then
        state.unresolved_deployable = item_id
        save()
        return false, "unknown item"
    end
    if not def.deployable then
        return false, (def.name or item_id) .. " is not a deployable"
    end

    local previous = state.deployable
    state.deployable = item_id
    if not save() then
        state.deployable = previous
        return false, "could not save inventory; deployable change rolled back"
    end
    return true
end


-- Third-party equipment registration. Definitions are copied so callers
-- cannot mutate live inventory rules after registration.
function PDTI.RegisterEquipment(kind, equipment_id, definition)
    if kind ~= "backpack" and kind ~= "rig" then
        return false, "kind must be backpack or rig"
    end
    if type(equipment_id) ~= "string" or equipment_id == "" or type(definition) ~= "table" then
        return false, "expected equipment id and definition"
    end
    local w, h = tonumber(definition.w), tonumber(definition.h)
    local weight = tonumber(definition.max_weight)
    -- A rig made of sections: every section is checked like a grid.
    if kind == "rig" and type(definition.sections) == "table" then
        if #definition.sections < 1 or #definition.sections > #PDTI.RIG_SECTIONS then
            return false, "a rig has one to " .. #PDTI.RIG_SECTIONS .. " sections"
        end
        for _, section in ipairs(definition.sections) do
            local sw, sh, sm = tonumber(section.w), tonumber(section.h), tonumber(section.max_weight)
            if not sw or not sh or sw < 1 or sh < 1 or sw % 1 ~= 0 or sh % 1 ~= 0
                or sw == math.huge or sh == math.huge or not sm or sm < 0 or sm ~= sm or sm == math.huge then
                return false, "every rig section needs finite positive w, h and max_weight"
            end
        end
        w, h = tonumber(definition.sections[1].w), tonumber(definition.sections[1].h)
        weight = weight or tonumber(definition.sections[1].max_weight)
    end
    if not w or not h or w < 1 or h < 1 or w % 1 ~= 0 or h % 1 ~= 0
        or w == math.huge or h == math.huge then
        return false, "equipment dimensions must be finite positive integers"
    end
    if not weight or weight < 0 or weight ~= weight or weight == math.huge then
        return false, "max_weight must be a finite non-negative number"
    end
    if definition.allowed_categories ~= nil then
        if type(definition.allowed_categories) ~= "table" then
            return false, "allowed_categories must be a table"
        end
        for category, allowed in pairs(definition.allowed_categories) do
            if type(category) ~= "string" or type(allowed) ~= "boolean" then
                return false, "allowed_categories must map category names to booleans"
            end
        end
    end

    local copy = copy_table(definition)
    copy.w, copy.h, copy.max_weight = math.floor(w), math.floor(h), weight
    local group = kind == "backpack" and "backpacks" or "rigs"
    PDTI.equipment[group][equipment_id] = copy

    -- If this equipment was selected in a save before its optional mod loaded,
    -- retry that selection now that its definition exists.
    if state.unresolved_equipment and state.unresolved_equipment[kind] == equipment_id then
        local equipped = PDTI.SetEquipment(kind, equipment_id)
        if equipped then
            state.unresolved_equipment[kind] = nil
            save()
        end
    end
    return true
end

-- Returns a cell matrix where each occupied cell contains the item instance ID.
-- Coordinates are zero-based in the API; the returned matrix is Lua 1-based.
function PDTI.GetOccupancyMap(container_name)
    if not valid_container_name(container_name) then return nil, "unknown container" end
    local width, height = container_size(container_name)
    local map = {}
    for y = 1, height do
        map[y] = {}
        for x = 1, width do map[y][x] = false end
    end
    for _, item in ipairs(state.containers[container_name].items) do
        local w, h = dimensions(item, item.rotated == true, container_name)
        if w and h then
            for y = item.y + 1, item.y + h do
                for x = item.x + 1, item.x + w do
                    map[y][x] = item.instance_id
                end
            end
        end
    end
    return { width = width, height = height, cells = map }
end

-- Deterministic first-fit repacking. Work on a detached candidate state and
-- commit only if every item fits, so failed rearrangement cannot lose items.
function PDTI.AutoArrange(container_name, allow_rotation)
    if not valid_container_name(container_name) then return false, "unknown container" end
    local candidate = copy_table(state)
    local items = candidate.containers[container_name].items
    table.sort(items, function(a, b)
        local aw, ah = dimensions(a, false)
        local bw, bh = dimensions(b, false)
        local aa, ba = (aw or 0) * (ah or 0), (bw or 0) * (bh or 0)
        if aa ~= ba then return aa > ba end
        return (a.instance_id or 0) < (b.instance_id or 0)
    end)

    local placed = {}
    candidate.containers[container_name].items = {}
    for _, item in ipairs(items) do
        local x, y, rotated
        local cw, ch = container_size(container_name, candidate)
        for r = 0, (allow_rotation and 1 or 0) do
            local rr = r == 1
            for yy = 0, ch - 1 do
                for xx = 0, cw - 1 do
                    local ok = placement_check(container_name, item, xx, yy, rr, nil, candidate)
                    if ok then x, y, rotated = xx, yy, rr; break end
                end
                if x ~= nil then break end
            end
            if x ~= nil then break end
        end
        if x == nil then return false, "not all items fit; original layout preserved" end
        item.x, item.y, item.rotated = x, y, rotated
        table.insert(candidate.containers[container_name].items, item)
    end

    local previous_state = state
    state = candidate
    if not save() then
        state = previous_state
        return false, "save failed; original layout restored"
    end
    return true
end

function PDTI.GetQuickAccess()
    local result = {}
    for _, name in ipairs(PDTI.TO_HAND) do
        for _, item in ipairs(state.containers[name].items) do
            local def = PDTI.items[item.item_id]
            if def and def.quick_use then
                result[#result + 1] = {
                    container = name, instance_id = item.instance_id,
                    item_id = item.item_id, name = def.name, amount = item.amount
                }
            end
        end
    end
    return result
end

-- All backpacks or rigs, sorted by name.
function PDTI.GetEquipmentOptions(kind)
    local group = kind == "backpack" and PDTI.equipment.backpacks or PDTI.equipment.rigs
    local out = {}
    for id, def in pairs(group or {}) do
        out[#out + 1] = { id = id, name = def.name or id, short = def.short or def.name or id,
            description = def.description }
    end
    -- Small to large / by name.
    table.sort(out, function(a, b)
        local da, db = group[a.id], group[b.id]
        local sa = (tonumber(da.w) or 0) * (tonumber(da.h) or 0)
        local sb = (tonumber(db.w) or 0) * (tonumber(db.h) or 0)
        if kind == "backpack" and sa ~= sb then return sa < sb end
        return a.name < b.name
    end)
    return out
end

function PDTI.GetEquipment()
    return {
        backpack = state.equipment.backpack,
        rig = state.equipment.rig,
        backpack_definition = copy_table(get_equipment_definition("backpack")),
        rig_definition = copy_table(get_rig())
    }
end

local function rig_section_list()
    local out = {}
    for i, section in ipairs(rig_sections(get_rig())) do
        local name = PDTI.RIG_SECTIONS[i]
        if name then
            out[#out + 1] = { container = name, title = section.name or "Rig", kind = section.kind or "general" }
        end
    end
    return out
end

-- UI-ready snapshot. The future inventory screen should render this model
-- rather than reading or editing internal state tables.
function PDTI.GetInventoryViewModel()
    local deployable = PDTI.GetDeployable()
    if PDTI.Deployables and PDTI.Deployables.GetSelection then
        deployable = PDTI.Deployables.GetSelection()
    end
    local deployables = {}
    if PDTI.Deployables and PDTI.Deployables.GetOptions then
        deployables = PDTI.Deployables.GetOptions()
    end
    return {
        equipment = PDTI.GetEquipment(),
        deployable = deployable,
        deployables = deployables,
        loose_ammo = PDTI.Ammo and PDTI.Ammo.GetSummary
            and PDTI.Ammo.GetSummary() or { stacks = {}, total = 0 },
        ammo = PDTI.Ammo and PDTI.Ammo.GetSupplySummary
            and PDTI.Ammo.GetSupplySummary() or {},
        loot = PDTI.Loot and PDTI.Loot.Count and PDTI.Loot.Count() or 0,
        speed_factor = PDTI.Carry and PDTI.Carry.GetSpeedFactor
            and PDTI.Carry.GetSpeedFactor() or 1,
        speed = PDTI.Carry and PDTI.Carry.GetBreakdown and PDTI.Carry.GetBreakdown() or nil,
        loadout = PDTI.Loadout and PDTI.Loadout.Get and PDTI.Loadout.Get() or {},
        containers = {
            pockets = PDTI.GetContainerInfo("pockets"),
            rig = PDTI.GetContainerInfo("rig"),
            rig_2 = PDTI.GetContainerInfo("rig_2"),
            rig_3 = PDTI.GetContainerInfo("rig_3"),
            backpack = PDTI.GetContainerInfo("backpack"),
            gun_primary = PDTI.GetContainerInfo("gun_primary"),
            gun_secondary = PDTI.GetContainerInfo("gun_secondary")
        },
        -- The sections the equipped rig has, in order.
        rig_sections = rig_section_list(),
        total_weight = total_weight(),
        quick_access = PDTI.GetQuickAccess(),
        item_definitions = PDTI.GetItemDefinitions(),
        occupancy = {
            pockets = PDTI.GetOccupancyMap("pockets"),
            rig = PDTI.GetOccupancyMap("rig"),
            rig_2 = PDTI.GetOccupancyMap("rig_2"),
            rig_3 = PDTI.GetOccupancyMap("rig_3"),
            backpack = PDTI.GetOccupancyMap("backpack"),
            gun_primary = PDTI.GetOccupancyMap("gun_primary"),
            gun_secondary = PDTI.GetOccupancyMap("gun_secondary")
        },
        version = PDTI.VERSION,
        schema_version = PDTI.SCHEMA_VERSION
    }
end

function PDTI.Save()
    return save()
end

-- Loads the inventory of a profile (the current one by default).
function PDTI.LoadProfile(index)
    index = index or PDTI.ProfileIndex()
    PDTI.loaded_profile = index
    state = sanitize_loaded(load_raw_state(index))
    PDTI.inventory_revision = (PDTI.inventory_revision or 0) + 1
    log("inventory of profile " .. tostring(index) .. " loaded")
    return true
end

-- Loads the current profile's inventory if another one is loaded.
function PDTI.EnsureProfile()
    local index = PDTI.ProfileIndex()
    if index ~= PDTI.loaded_profile then return PDTI.LoadProfile(index) end
    return false
end

-- In a heist nothing is written: what you use or drop comes back next time.
function PDTI.SetSessionOnly(on)
    PDTI.session_only = on == true
end

-- The sizes and bullets chosen in the menu for an assault rifle or SMG:
-- the magazine in the gun (gun_size, gun_bullet) and the magazine "+ mag"
-- adds (pick_size, pick_bullet).
PDTI.PLAN_SLOT_FIELDS = { "gun_size", "gun_bullet", "pick_size", "pick_bullet", "pick_load", "gun_filled" }

function PDTI.GetPlanSlot(slot)
    local entry = type(state.plan_slots) == "table" and state.plan_slots[slot] or {}
    local Ammo = PDTI.Ammo
    local function size(v) return Ammo and Ammo.SizeId(v) or (v or "standard") end
    local function bullet(v) return Ammo and Ammo.BulletId(v) or (v or "standard") end
    return {
        gun_size = size(entry.gun_size), gun_bullet = bullet(entry.gun_bullet),
        pick_size = size(entry.pick_size), pick_bullet = bullet(entry.pick_bullet),
        -- The rounds of each bullet in a new magazine, top first
        -- ("ap:10,hollow:20"); nil: full of pick_bullet.
        pick_load = type(entry.pick_load) == "string" and entry.pick_load or nil,
        -- "1" once the weapon's slot got its first magazine.
        gun_filled = entry.gun_filled
    }
end

function PDTI.SetPlanSlot(slot, field, value)
    if slot ~= "primary" and slot ~= "secondary" then return false end
    local known = false
    for _, f in ipairs(PDTI.PLAN_SLOT_FIELDS) do
        if f == field then known = true end
    end
    if not known or type(value) ~= "string" then return false end
    state.plan_slots = type(state.plan_slots) == "table" and state.plan_slots or {}
    local entry = state.plan_slots[slot] or {}
    local before = entry[field]
    entry[field] = value
    state.plan_slots[slot] = entry
    if before ~= value and not save() then
        entry[field] = before
        return false
    end
    return true
end

function PDTI.IsAmmoPlanned()
    return state.ammo_planned == true
end

-- The money paid for the menu plan (refunds never pay back more).
function PDTI.PlanPaid()
    return math.max(0, tonumber(state.plan_paid) or 0)
end

function PDTI.SetPlanPaid(amount)
    local before = state.plan_paid
    state.plan_paid = math.max(0, math.floor((tonumber(amount) or 0) + 0.5))
    if before ~= state.plan_paid and not save() then
        state.plan_paid = before
        return false
    end
    return true
end

function PDTI.SetAmmoPlanned(on)
    local before = state.ammo_planned
    state.ammo_planned = on == true
    if before ~= state.ammo_planned and not save() then
        state.ammo_planned = before
        return false
    end
    return true
end

-- Replaces the data of an item (the data can change its size). The item stays
-- where it is if it still fits there, else it goes to the first container of
-- `names` with room. Returns ok, container.
function PDTI.ReplaceItemData(container_name, instance_id, data, names)
    if not valid_container_name(container_name) then return false, "unknown container" end
    local backup = copy_table(state.containers)
    local items = state.containers[container_name].items
    local item, index
    for i, candidate in ipairs(items) do
        if candidate.instance_id == instance_id then item, index = candidate, i break end
    end
    if not item then return false, "item not found" end
    table.remove(items, index)
    item.data = serializable_item_data(data)
    local where
    local weight_ok = container_weight(container_name) + item_weight(item) <= container_weight_limit(container_name)
    if weight_ok and placement_check(container_name, item, item.x, item.y, item.rotated == true) then
        table.insert(items, index, item)
        where = container_name
    else
        where = place_anywhere(state, item, names or PDTI.CONTAINERS)
    end
    if not where then
        state.containers = backup
        return false, "no room for the item"
    end
    if not save() then
        state.containers = backup
        return false, "could not save inventory; edit rolled back"
    end
    return true, where
end

function PDTI.Reset()
    local previous_state = state
    state = new_state()
    if not save() then
        state = previous_state
        return false
    end
    return true
end

PDTI._internal = {
    placement_check = placement_check,
    dimensions = dimensions,
    container_weight = container_weight,
    container_weight_limit = container_weight_limit
}
