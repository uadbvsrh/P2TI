-- BeardLib MenuUI renderer for the tactical inventory screen.
--
-- Uses only MenuUI parameters/functions from the BeardLib docs
-- (luffyyy.gitbook.io/beardlib/menuui). It is a thin view: every action calls
-- the public PDTI API (ui_interaction.lua / ui_model.lua) and then redraws from
-- a fresh view model. NOT yet verified inside PAYDAY 2; see README.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

-- Two small windows at the edges of the screen, the middle stays free:
--   left:  the loadout, the pockets, the rig, the deployable and the controls
--   right: the backpack, the ammunition and the test spawner
local CELL, GAP, PAD, LABEL_H = 30, 2, 10, 18
local BTN_W, BTN_H, BTN_GAP = 86, 22, 4
local WIN_W = 290
local INNER_W = WIN_W - 2 * PAD
local LINE_H, LINE_FONT = 15, 12
local DYN = "pdti_dynamic"

local view = { menu = nil, left = nil, right = nil, open = false, triggers = {}, input_block = nil,
    cells = {}, preview = {} }

local function log(message)
    local line = "[PDTI UI] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

function PDTI.IsUIAvailable()
    return rawget(_G, "MenuUI") ~= nil
end

local CATEGORY_COLORS = {
    medical = { 0.20, 0.55, 0.30 }, ammunition = { 0.65, 0.50, 0.15 },
    explosive = { 0.60, 0.22, 0.20 }, utility = { 0.22, 0.38, 0.62 }
}
-- The ammunition of the two guns looks different: primary is orange,
-- secondary is blue.
local SLOT_COLORS = {
    primary = { 0.78, 0.42, 0.10 }, secondary = { 0.18, 0.48, 0.72 }
}
local SLOT_TAGS = { primary = "PRI", secondary = "SEC" }

-- Empty slots are tinted by what goes in them.
local SLOT_KIND_COLORS = {
    pockets = { 0.19, 0.16, 0.23 },   -- violet: the pockets
    backpack = { 0.15, 0.13, 0.10 },  -- brown: the backpack
    general = { 0.16, 0.16, 0.17 },   -- grey: anything
    medical = { 0.10, 0.24, 0.14 },   -- green: kits and medic bags
    ammo = { 0.27, 0.19, 0.06 },      -- amber: magazines and loose rounds
    ammo_bags = { 0.10, 0.17, 0.30 }  -- blue: ammo bags
}
PDTI.SLOT_KIND_COLORS = SLOT_KIND_COLORS

local function slot_kind(container, model)
    if container == "pockets" or container == "backpack" then return container end
    for _, section in ipairs(model and model.rig_sections or {}) do
        if section.container == container then return section.kind or "general" end
    end
    return "general"
end

-- The bullets have their colours; standard rounds keep the weapon's
-- (orange PRI, blue SEC). A magazine of several kinds shows its top one.
local BULLET_COLORS = {
    hollow = { 0.74, 0.18, 0.22 },  -- red: hollow points
    ap = { 0.20, 0.58, 0.36 }       -- green: armour piercing
}
PDTI.UI_BULLET_COLORS = BULLET_COLORS

local function item_color(def, item)
    local data = item and type(item.data) == "table" and item.data or nil
    local slot = data and data.slot
    if def and def.ammo_managed and data then
        local top = data.bullet
        if data.load and PDTI.Ammo then top = PDTI.Ammo.LoadTop(PDTI.Ammo.LoadOf(data)) or top end
        if BULLET_COLORS[top] then return BULLET_COLORS[top] end
    end
    if def and def.ammo_managed and SLOT_COLORS[slot] then return SLOT_COLORS[slot] end
    return CATEGORY_COLORS[def and def.category] or { 0.35, 0.35, 0.35 }
end

-- Is a Ctrl key held? The click then moves the item to the other side.
local function ctrl_down()
    local ok, down = pcall(function()
        local kb = Input:keyboard()
        return kb:down(Idstring("left ctrl")) or kb:down(Idstring("right ctrl"))
    end)
    if ok and down then return true end
    ok, down = pcall(function()
        local input = BeardLib.Utils.Input
        return input:Down("left ctrl") or input:Down("right ctrl")
    end)
    return ok and down and true or false
end
PDTI._ctrl_down = ctrl_down

local function rgb(t, mult)
    mult = mult or 1
    return Color(math.min(1, t[1] * mult), math.min(1, t[2] * mult), math.min(1, t[3] * mult))
end

-- Wrap click handlers so one bad callback cannot break the menu.
local function safe(fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then log("callback error: " .. tostring(err)) end
    end
end

-- Make sure an item ended up with the intended pixel size, whichever of the
-- documented size parameters MenuUI honoured.
local function fit(item, w, h)
    pcall(function()
        local panel = item and item:Panel()
        if panel and (panel:w() ~= w or panel:h() ~= h) then panel:set_size(w, h) end
    end)
end

local function sorted_ids(map)
    local ids = {}
    for id in pairs(map or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

-- The key that places the deployable.
local function deploy_key()
    if PDTI.Deployables and PDTI.Deployables.KEY then return tostring(PDTI.Deployables.KEY) end
    return "g"
end

local function equip(kind, id)
    local ok, reason = PDTI.RequestEquip(kind, id)
    if ok then PDTI.UISetStatus(nil) else PDTI.UISetStatus(reason) end
end

-- "rig" arranges every section of the rig.
local function arrange(container, model)
    local list = { container }
    if container == "rig" and model and model.rig_sections then
        list = {}
        for _, section in ipairs(model.rig_sections) do list[#list + 1] = section.container end
    end
    for _, name in ipairs(list) do
        local ok, reason = PDTI.RequestAutoArrange(name, true)
        if not ok then PDTI.UISetStatus(reason) return end
    end
    PDTI.UISetStatus(nil)
end

local redraw -- forward declaration
local draw_equipment

-- After any UI action the screen is drawn again from the fresh model.
-- A magazine moved into or out of a weapon's slot goes into or out of the
-- gun at once.
local function sync_guns()
    local ammo = PDTI.Ammo
    if ammo and ammo.ForEachWeapon and ammo.SyncGunSlot then
        pcall(ammo.ForEachWeapon, ammo.SyncGunSlot)
    end
end

local function after(action)
    return safe(function()
        action()
        sync_guns()
        redraw()
    end)
end

local function short_label(def, item)
    local data = item and item.data
    if def and def.ammo_managed and data and data.rounds then
        -- An assault rifle's or SMG's magazine shows its bullets.
        if data.bullet and PDTI.Ammo and PDTI.Ammo.BULLETS[data.bullet] then
            return tostring(data.rounds) .. " " .. PDTI.Ammo.LoadTag(PDTI.Ammo.LoadOf(data), data.bullet)
        end
        return tostring(data.rounds) .. "/" .. tostring(data.capacity or "?")
    end
    if def and def.ammo_managed and type(data) == "table" and data.bullet and data.bullet ~= "standard"
        and SLOT_TAGS[data.slot] and PDTI.Ammo and PDTI.Ammo.BULLETS[data.bullet] then
        return SLOT_TAGS[data.slot] .. " " .. PDTI.Ammo.BULLETS[data.bullet].short .. " " .. tostring(item.amount or 0)
    end
    if def and def.ammo_managed and type(data) == "table" and SLOT_TAGS[data.slot] then
        return SLOT_TAGS[data.slot] .. " " .. tostring(item.amount or 0)
    end
    if item and item.item_id == "loot_bag" and type(data) == "table" and data.active then
        return "Bag (hand)"
    end
    local name = def and def.name or "?"
    -- The cells are small: the first word, at most six letters.
    name = name:match("^%S+") or name
    if #name > 6 then name = name:sub(1, 5) .. "." end
    if item and item.amount and item.amount > 1 then name = name .. " x" .. item.amount end
    return name
end

local function draw_grid(win, container, origin_x, origin_y, model)
    local info = model.containers[container]
    local map = model.occupancy[container]
    if not info or not map then return end
    local held = PDTI.UIGetHeld()
    local empty = SLOT_KIND_COLORS[slot_kind(container, model)] or SLOT_KIND_COLORS.general
    local items_by_id = {}
    for _, item in ipairs(info.items) do items_by_id[item.instance_id] = item end

    for y = 0, map.height - 1 do
        for x = 0, map.width - 1 do
            local id = map.cells[y + 1][x + 1]
            local item = id and items_by_id[id]
            local def = item and model.item_definitions[item.item_id]
            local text = ""
            if item and item.x == x and item.y == y then text = short_label(def, item) end

            local base = item_color(def, item)
            local is_held = held and id and held.instance_id == id and held.container == container
            local btn = win:Button({
                name = string.format("cell_%s_%d_%d", container, x, y),
                label = DYN,
                text = text,
                position = { origin_x + x * CELL, origin_y + y * CELL },
                w = CELL - GAP, size = CELL - GAP,
                font_size = 10,
                text_align = "center", text_vertical = "center",
                background_color = item and rgb(base, is_held and 1.5 or 1) or rgb(empty),
                highlight_color = item and rgb(base, 1.3) or rgb(empty, 1.8),
                on_callback = safe(function()
                    if ctrl_down() then
                        PDTI.UICellQuickTransfer(container, x, y)
                    else
                        PDTI.UICellClick(container, x, y)
                    end
                    sync_guns()
                    redraw()
                end)
            })
            fit(btn, CELL - GAP, CELL - GAP)
            view.cells[#view.cells + 1] = { item = btn, container = container, x = x, y = y }
        end
    end
end

local function label(win, name, text, x, y, w)
    local div = win:Divider({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = 14, font_size = 14
    })
    fit(div, w, LABEL_H - 2)
    return div
end

-- One line of small text.
local function line(win, name, text, x, y, w, h)
    h = h or LINE_H
    local div = win:Divider({
        name = name, label = DYN, text = text, position = { x, y },
        w = w or INNER_W, size = LINE_FONT, font_size = LINE_FONT
    })
    fit(div, w or INNER_W, h - 1)
    return div
end

local function button(win, name, text, x, y, callback, w)
    w = w or BTN_W
    local btn = win:Button({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = BTN_H, font_size = 12,
        text_align = "center", text_vertical = "center",
        background_color = Color(0.18, 0.18, 0.22), highlight_color = Color(0.30, 0.30, 0.38),
        on_callback = callback
    })
    fit(btn, w, BTN_H)
    return btn
end

-- A small coloured button for the lists (two per row).
local HALF_W = math.floor((INNER_W - BTN_GAP) / 2)
local function list_button(win, name, text, x, y, color, active, callback)
    local btn = win:Button({
        name = name, label = DYN, text = text, position = { x, y },
        w = HALF_W, size = 18, font_size = 11,
        text_align = "left", text_vertical = "center",
        background_color = rgb(color, active and 1.5 or 0.75), highlight_color = rgb(color, 1.3),
        on_callback = callback
    })
    fit(btn, HALF_W, 18)
    return btn
end
local function list_pos(i, x, y)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    return x + col * (HALF_W + BTN_GAP), y + row * 20
end

local SLOT_NAMES = { primary = "PRI", secondary = "SEC", throwable = "THR", armour = "ARM" }

local function pct(v) return math.floor((tonumber(v) or 1) * 100 + 0.5) end

local function short(text, n)
    text = tostring(text or "?")
    if #text > n then return text:sub(1, n - 1) .. "." end
    return text
end

-- In the menu: three rigs and three backpacks to choose from, with what the
-- chosen one does.
function draw_equipment(win, model, x, y)
    local function bx(i) return x + (i - 1) * (BTN_W + BTN_GAP) end
    for _, kind in ipairs({ "rig", "backpack" }) do
        label(win, "equip_" .. kind .. "_label", kind == "rig" and "Rig" or "Backpack", x, y, INNER_W)
        y = y + LABEL_H
        local current = model.equipment[kind]
        local options = PDTI.GetEquipmentOptions(kind)
        local description
        for i, option in ipairs(options) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local chosen = option.id == current
            if chosen then description = option.description end
            local btn = win:Button({
                name = "equip_" .. kind .. "_" .. option.id, label = DYN,
                text = (chosen and "> " or "") .. tostring(option.short),
                position = { bx(col + 1), y + row * (BTN_H + BTN_GAP) },
                w = BTN_W, size = BTN_H, font_size = 12,
                text_align = "center", text_vertical = "center",
                background_color = chosen and rgb(CATEGORY_COLORS.utility, 1.4) or Color(0.18, 0.18, 0.22),
                highlight_color = Color(0.30, 0.30, 0.38),
                on_callback = after(function() equip(kind, option.id) end)
            })
            fit(btn, BTN_W, BTN_H)
        end
        y = y + math.ceil(#options / 3) * (BTN_H + BTN_GAP)
        line(win, "equip_" .. kind .. "_info", tostring(description or ""), x, y, INNER_W, 2 * LINE_H)
        y = y + 2 * LINE_H + 4
    end
    return y
end

-- In the menu: what you bring into every heist. A row per thing, with a
-- button for one less and one more.
local ROW_H = 20
local SMALL_W = 22
local function plan_change(kind, add)
    local plan = PDTI.Plan
    if not plan then return end
    local ok, reason
    if add then ok, reason = plan.Add(kind) else ok, reason = plan.Remove(kind) end
    PDTI.UISetStatus(ok and nil or reason)
end

local function small_button(win, name, text, x, y, callback, w, chosen)
    w = w or SMALL_W
    local btn = win:Button({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = ROW_H - 2, font_size = 13,
        text_align = "center", text_vertical = "center",
        background_color = chosen and rgb(CATEGORY_COLORS.utility, 1.4) or Color(0.18, 0.18, 0.22),
        highlight_color = Color(0.30, 0.30, 0.38),
        on_callback = callback
    })
    fit(btn, w, ROW_H - 2)
    return btn
end

local function spec_change(slot, field, value)
    local ok, reason = PDTI.Plan.SetSpec(slot, field, value)
    PDTI.UISetStatus(ok and nil or reason)
end

local function pick_change(slot, bullet, add)
    local ok, reason = PDTI.Plan.ChangePickCount(slot, bullet, add)
    PDTI.UISetStatus(ok and nil or reason)
end

-- An assault rifle or SMG: the magazine "+" adds. Its size, then how many
-- rounds of each bullet go in (the order is top first; Flip turns it).
local function draw_pick_rows(win, slot, spec, x, y)
    local Ammo = PDTI.Ammo
    line(win, "bring_pick_label_" .. slot, "+Mag", x, y + 2, 34)
    local bx = x + 36
    for _, id in ipairs(Ammo.SIZE_ORDER) do
        small_button(win, "bring_pick_size_" .. slot .. "_" .. id, Ammo.MAG_SIZES[id].short, bx, y,
            after(function() spec_change(slot, "pick_size", id) end), SMALL_W, spec.size == id)
        bx = bx + SMALL_W + 2
    end
    small_button(win, "bring_pick_flip_" .. slot, "Flip", bx + 4, y,
        after(function() PDTI.Plan.FlipPick(slot) end), 34)
    local order = {}
    for _, part in ipairs(spec.load) do order[#order + 1] = Ammo.BULLETS[part[1]].short end
    local price = PDTI.Plan.AddPrice and PDTI.Plan.AddPrice("mag:" .. slot) or 0
    line(win, "bring_pick_info_" .. slot, string.format("%d/%d %s", spec.rounds, spec.capacity, PDTI.Ammo.Money(price)),
        bx + 42, y + 2, INNER_W - (bx + 42 - x))
    y = y + ROW_H
    bx = x
    for _, id in ipairs(Ammo.BULLET_ORDER) do
        local count = 0
        for _, part in ipairs(spec.load) do if part[1] == id then count = count + part[2] end end
        small_button(win, "bring_pick_minus_" .. slot .. "_" .. id, "-", bx, y,
            after(function() pick_change(slot, id, false) end), 18)
        small_button(win, "bring_pick_plus_" .. slot .. "_" .. id, "+", bx + 19, y,
            after(function() pick_change(slot, id, true) end), 18)
        line(win, "bring_pick_count_" .. slot .. "_" .. id, Ammo.BULLETS[id].short .. " " .. count, bx + 39, y + 2, 50)
        bx = bx + 90
    end
    return y + ROW_H
end

local function draw_bring(win, x, y)
    local plan = PDTI.Plan
    if not plan then return y end
    label(win, "bring_label", "Bring into every heist", x, y, INNER_W)
    y = y + LABEL_H
    -- Adding pays at once, taking out pays back; what a heist uses up is
    -- paid again.
    if plan.Cost then
        local Ammo = PDTI.Ammo
        local money = plan.Money and plan.Money()
        local text = "Loadout worth " .. Ammo.Money(plan.Cost())
        if money then text = text .. "   you have " .. Ammo.Money(money) end
        line(win, "bring_cost", text, x, y, INNER_W)
        y = y + LINE_H
    end
    local rows = plan.Rows()
    if #rows == 0 then
        line(win, "bring_none", "(no weapons known here)", x, y)
        return y + LINE_H + 4
    end
    local i = 1
    while i <= #rows do
        local row = rows[i]
        local id = tostring(row.kind):gsub(":", "_")
        if row.typed then
            line(win, "bring_weapon_" .. row.slot, short(row.name or "", 30), x, y + 2, INNER_W)
            y = y + ROW_H - 4
            y = draw_pick_rows(win, row.slot, row.pick, x, y)
        end
        if row.bullet then
            -- The loose rounds of the three bullets share a row.
            local bx = x
            while rows[i] and rows[i].bullet do
                local r = rows[i]
                local rid = tostring(r.kind):gsub(":", "_")
                small_button(win, "bring_minus_" .. rid, "-", bx, y, after(function() plan_change(r.kind, false) end), 18)
                small_button(win, "bring_plus_" .. rid, "+", bx + 19, y, after(function() plan_change(r.kind, true) end), 18)
                line(win, "bring_line_" .. rid, r.text:gsub("^%u+ ", ""), bx + 39, y + 2, 50)
                bx = bx + 90
                i = i + 1
            end
            y = y + ROW_H
        else
        small_button(win, "bring_minus_" .. id, "-", x, y, after(function() plan_change(row.kind, false) end))
        small_button(win, "bring_plus_" .. id, "+", x + SMALL_W + 2, y, after(function() plan_change(row.kind, true) end))
        local text = row.text
        if row.name and not row.typed then text = text .. "  " .. short(row.name, 14) end
        line(win, "bring_line_" .. id, text, x + 2 * SMALL_W + 8, y + 2, INNER_W - 2 * SMALL_W - 8)
        y = y + ROW_H
        i = i + 1
        end
    end
    return y + 4
end

-- The left window: loadout, pockets, rig, deployable, controls, weight.
local function draw_left(win, model)
    local x = PAD
    label(win, "title", "Tactical Inventory", x, 6, INNER_W)
    local y = 6 + LABEL_H + 2

    -- The loadout: weapons, throwables and armour have their own slots.
    -- The weapons: a box each (name and weight) with the weapon's magazine
    -- slot next to it, side by side.
    local col_w = math.floor((INNER_W - 8) / 2)
    local weapons = 0
    for _, entry in ipairs(model.loadout or {}) do
        local gun = entry.slot == "primary" and "gun_primary" or entry.slot == "secondary" and "gun_secondary" or nil
        if gun and model.containers[gun] then
            local wx = x + weapons * (col_w + 8)
            weapons = weapons + 1
            local box_w = col_w - 2 * CELL - 2
            local btn = win:Button({
                name = "weapon_box_" .. entry.slot, label = DYN,
                text = string.format("%s %s\n%.1f kg", SLOT_NAMES[entry.slot], short(entry.name, 9), entry.weight or 0),
                position = { wx, y }, w = box_w, size = CELL - GAP, font_size = 10,
                text_align = "center", text_vertical = "center",
                background_color = rgb(SLOT_COLORS[entry.slot], 0.55), highlight_color = rgb(SLOT_COLORS[entry.slot], 0.55),
                on_callback = function() end
            })
            fit(btn, box_w, CELL - GAP)
            draw_grid(win, gun, wx + box_w + 2, y, model)
        end
    end
    if weapons > 0 then y = y + CELL + 2 end
    -- The throwable and the armour share a line.
    local rest = {}
    for i, entry in ipairs(model.loadout or {}) do
      if not (entry.slot == "primary" or entry.slot == "secondary") or not model.containers.gun_primary then
        local text = string.format("%s %s", SLOT_NAMES[entry.slot] or entry.slot, short(entry.name, 12))
        if entry.slot == "throwable" then text = text .. string.format(" x%d", entry.amount or 0) end
        text = text .. string.format("  %.1f kg", entry.weight or 0)
        if entry.slot == "armour" and (entry.penalty or 0) > 0 then
            text = text .. string.format(" -%g%%", math.floor(entry.penalty * 1000 + 0.5) / 10)
        end
        rest[#rest + 1] = { i = i, text = text }
      end
    end
    for k, r in ipairs(rest) do
        local w = #rest > 1 and math.floor(INNER_W / 2) - 2 or INNER_W
        line(win, "loadout_line_" .. r.i, r.text, x + ((k - 1) % 2) * (w + 4), y, w)
        if k % 2 == 0 or k == #rest then y = y + LINE_H end
    end
    if #(model.loadout or {}) == 0 then
        line(win, "loadout_none", "(not available here)", x, y)
        y = y + LINE_H
    end
    y = y + 6

    -- The pockets and the sections of the rig, packed into rows.
    local grids = { { container = "pockets", title = "Pockets" } }
    for i, section in ipairs(model.rig_sections or {}) do
        local title = section.title
        if i == 1 then
            local rig = model.equipment.rig_definition
            local short_name = rig and (rig.short or rig.name) or "Rig"
            title = title == short_name and (rig and rig.name or title) or (short_name .. ": " .. tostring(title))
        end
        grids[#grids + 1] = { container = section.container, title = title }
    end
    local rows = {}
    for _, g in ipairs(grids) do
        local info = model.containers[g.container]
        g.w, g.h = info.width * CELL, info.height * CELL
        g.label_w = math.max(g.w, math.min(INNER_W, #g.title * 7))
        local width = math.max(g.w, g.label_w)
        local placed = false
        for _, row in ipairs(rows) do
            if row.used + 12 + width <= INNER_W then
                g.x = x + row.used + 12
                row.used = row.used + 12 + width
                row.list[#row.list + 1] = g
                placed = true
                break
            end
        end
        if not placed then
            g.x = x
            rows[#rows + 1] = { used = width, list = { g } }
        end
    end
    for _, row in ipairs(rows) do
        local height = 0
        for _, g in ipairs(row.list) do
            label(win, g.container .. "_label", g.title, g.x, y, g.label_w)
            draw_grid(win, g.container, g.x, y + LABEL_H, model)
            height = math.max(height, g.h)
        end
        y = y + LABEL_H + height + 6
    end

    if not PDTI.InHeist() then
        -- In the menu: choose the rig and the backpack (what you bring is in
        -- the right window).
        y = draw_equipment(win, model, x, y)
    else
        -- The deployable: what G places, X picks the next one.
        local selected = nil
        for _, entry in ipairs(model.deployables or {}) do
            if entry.item_id == model.deployable then selected = entry end
        end
        local dep = PDTI.Deployables
        local manual = dep and dep.GetManual and dep.GetManual()
        local now
        if selected then
            now = string.format("%s x%d", selected.name, selected.count or 0)
                .. ((manual and manual == selected.item_id) and " (picked)" or " (first found)")
        elseif dep and dep.DisplayName then
            now = dep.DisplayName()
        else
            now = "none"
        end
        label(win, "deploy_label", string.format("Deployable [%s place, %s next]",
            string.upper(deploy_key()), string.upper(dep and dep.CYCLE_KEY or "x")), x, y, INNER_W)
        y = y + LABEL_H
        line(win, "deploy_now", "> " .. now, x, y)
        y = y + LINE_H + 2
        local n = 0
        for _, entry in ipairs(model.deployables or {}) do
            n = n + 1
            local bx, by = list_pos(n, x, y)
            list_button(win, "deployable_" .. entry.item_id,
                string.format("%s x%d", short(entry.name, 14), entry.count or 0), bx, by,
                CATEGORY_COLORS.utility, entry.item_id == model.deployable,
                after(function() PDTI.UISelectDeployableById(entry.item_id) end))
        end
        n = n + 1
        local cx, cy = list_pos(n, x, y)
        list_button(win, "deployable_clear", "First found", cx, cy, { 0.3, 0.3, 0.34 }, manual == nil,
            after(function() PDTI.UIClearDeployable() end))
        y = y + math.ceil(n / 2) * 20 + 6
    end

    -- Controls.
    local function bx(i) return x + (i - 1) * (BTN_W + BTN_GAP) end
    local row1, row2 = y, y + BTN_H + BTN_GAP
    button(win, "btn_rotate", "Rotate (R)", bx(1), row1, after(function() PDTI.UIRotateHeld() end))
    button(win, "btn_cancel", "Cancel hold", bx(2), row1, after(function() PDTI.UICancelHeld() end))
    button(win, "btn_discard", "Discard", bx(3), row1, after(function() PDTI.UIDiscardHeld() end))
    button(win, "btn_arrange_rig", "Arrange rig", bx(1), row2, after(function() arrange("rig", model) end))
    button(win, "btn_close", "Close (Esc)", bx(2), row2, safe(function() PDTI.SetUIOpen(false) end))
    y = row2 + BTN_H + BTN_GAP
    local loot = PDTI.Loot
    if loot and loot.CanStash and loot.CanStash() then
        button(win, "btn_loot", "Stash bag", bx(1), y, after(function()
            local ok, reason = loot.StashCarried()
            PDTI.UISetStatus(ok and "The bag is in your inventory" or reason)
        end))
        y = y + BTN_H + BTN_GAP
    elseif loot and loot.CanTakeOut and loot.CanTakeOut() then
        button(win, "btn_loot", "Carry a bag", bx(1), y, after(function()
            local ok, reason = loot.TakeOut()
            PDTI.UISetStatus(ok and "You carry a bag; throw it as usual" or reason)
        end))
        y = y + BTN_H + BTN_GAP
    end
    y = y + 2

    -- Weight and speed.
    local bp, pk = model.containers.backpack, model.containers.pockets
    local rg = { weight = 0, weight_limit = 0 }
    for _, section in ipairs(model.rig_sections or {}) do
        local info = model.containers[section.container]
        rg.weight = rg.weight + (info.weight or 0)
        rg.weight_limit = rg.weight_limit + (tonumber(info.weight_limit) or 0)
    end
    local loadout_kg = 0
    for _, entry in ipairs(model.loadout or {}) do loadout_kg = loadout_kg + (entry.weight or 0) end
    line(win, "weights", string.format("Weight %.1f kg (loadout %.1f)", model.total_weight + loadout_kg, loadout_kg), x, y)
    y = y + LINE_H
    line(win, "weights_parts", string.format("Pockets %.1f/%g  Rig %.1f/%g  Pack %.1f/%g",
        pk.weight, pk.weight_limit, rg.weight, rg.weight_limit, bp.weight, bp.weight_limit), x, y)
    y = y + LINE_H
    local parts = model.speed
    local speed_text = string.format("Speed %d%%", pct(model.speed_factor))
    if parts then
        speed_text = string.format("Speed %d%%: load %d%%, armour %d%%, loot %d%%",
            pct(parts.total), pct(parts.load), pct(parts.armour), pct(parts.loot))
    end
    if parts and parts.gear and parts.gear ~= 1 then
        speed_text = speed_text .. string.format(", gear +%d%%", pct(parts.gear) - 100)
    end
    if parts and parts.legs and parts.legs ~= 1 then
        speed_text = speed_text .. string.format(", legs %d%%", pct(parts.legs))
    end
    line(win, "info", string.format("%s  |  bags %d", speed_text, model.loot or 0), x, y)
    y = y + LINE_H + 2
    line(win, "status", PDTI.UIGetStatusText(), x, y, INNER_W, 2 * LINE_H)
    y = y + 2 * LINE_H
    return y + PAD
end

-- The right window: the backpack, the ammunition and the test spawner.
local function draw_right(win, model)
    local x = PAD
    local bp = model.containers.backpack
    local y = 6
    label(win, "backpack_label", "Backpack: " .. tostring(model.equipment.backpack_definition
        and model.equipment.backpack_definition.name or model.equipment.backpack), x, y, INNER_W)
    y = y + LABEL_H + 2
    draw_grid(win, "backpack", x, y, model)
    y = y + bp.height * CELL + 6
    local function bx(i) return x + (i - 1) * (BTN_W + BTN_GAP) end
    button(win, "btn_arrange_pack", "Arrange pack", bx(1), y, after(function() arrange("backpack") end))
    y = y + BTN_H + 8

    -- In the menu: what you bring takes the place of the ammunition and the
    -- test spawner.
    if not PDTI.InHeist() then
        y = draw_bring(win, x, y)
        return y + PAD
    end

    -- Ammunition: loose rounds and the magazines to hand.
    label(win, "ammo_label", "Ammunition", x, y, INNER_W)
    y = y + LABEL_H
    local loose = model.loose_ammo or { stacks = {}, total = 0 }
    local loose_lines = {}
    for _, entry in ipairs(loose.stacks or {}) do
        loose_lines[#loose_lines + 1] = string.format("%sloose %s: %d",
            entry.slot and (SLOT_TAGS[entry.slot] .. " ") or "",
            short(entry.caliber or entry.queue_key, 18), entry.rounds or 0)
    end
    if #loose_lines == 0 then loose_lines[1] = "No loose rounds" end
    for i, text in ipairs(loose_lines) do
        line(win, "loose_line_" .. i, text, x, y)
        y = y + LINE_H
    end
    local lines = {}
    for _, supply in ipairs(model.ammo or {}) do
        local rounds = {}
        for _, value in ipairs(supply.magazines or {}) do rounds[#rounds + 1] = tostring(value) end
        lines[#lines + 1] = string.format("%s%s mags: %s",
            supply.slot and (SLOT_TAGS[supply.slot] .. " ") or "",
            short(supply.caliber or supply.queue_key, 14),
            #rounds > 0 and table.concat(rounds, "/") or "-")
    end
    if #lines == 0 then lines[1] = "No magazines yet" end
    for i, text in ipairs(lines) do
        line(win, "mag_line_" .. i, text, x, y)
        y = y + LINE_H
    end
    y = y + 6

    -- The test spawner: the deployables and the ammunition of both guns.
    label(win, "supplies_label", "Spawn for testing", x, y, INNER_W)
    y = y + LABEL_H
    local n = 0
    for _, id in ipairs(sorted_ids(model.item_definitions)) do
        local def = model.item_definitions[id]
        if def.deployable and not def.ammo_managed and not def.no_supply then
            n = n + 1
            local px, py = list_pos(n, x, y)
            list_button(win, "supply_" .. id, short(def.name or id, 16), px, py,
                CATEGORY_COLORS[def.category] or { 0.3, 0.3, 0.3 }, false,
                after(function() PDTI.UIAddSupply(id) end))
        end
    end
    local bullet = view.spawn_bullet or "standard"
    local tag = bullet ~= "standard" and (" " .. PDTI.Ammo.BULLETS[bullet].short) or ""
    local spawns = {
        { "spawn_loose_primary", "PRI loose" .. tag, "primary", "DevSpawnLoose" },
        { "spawn_mag_primary", "PRI magazine" .. tag, "primary", "DevSpawnMagazine" },
        { "spawn_loose_secondary", "SEC loose" .. tag, "secondary", "DevSpawnLoose" },
        { "spawn_mag_secondary", "SEC magazine" .. tag, "secondary", "DevSpawnMagazine" }
    }
    if n % 2 == 1 then n = n + 1 end
    -- The bullets of the spawned ammunition (assault rifles and SMGs).
    local rows_before = math.ceil(n / 2)
    local by = y + rows_before * 20
    line(win, "spawn_bullet_label", "Bullets", x, by + 2, 50)
    local bx = x + 52
    for _, id in ipairs(PDTI.Ammo.BULLET_ORDER) do
        small_button(win, "spawn_bullet_" .. id, PDTI.Ammo.BULLETS[id].short, bx, by,
            after(function() view.spawn_bullet = id end), 36, bullet == id)
        bx = bx + 38
    end
    n = n + 2
    for _, spawn in ipairs(spawns) do
        local name, text, slot, fn = spawn[1], spawn[2], spawn[3], spawn[4]
        n = n + 1
        local px, py = list_pos(n, x, y)
        list_button(win, name, text, px, py, SLOT_COLORS[slot], false, after(function()
            local ammo = PDTI.Ammo
            if not ammo or not ammo[fn] then return end
            local ok, result = ammo[fn](slot, bullet ~= "standard" and bullet or nil)
            if ok then
                PDTI.UISetStatus(string.format("Added %s (%s round(s))", text, tostring(result)))
            else
                PDTI.UISetStatus(tostring(result))
            end
        end))
    end
    y = y + math.ceil(n / 2) * 20
    return y + PAD
end

-- The health window (in a heist): every body part as a box in the shape of
-- a body, coloured by what it has left (green, yellow, red, black at 0),
-- with its HP and its maximum, then what the black parts do.
local HEALTH_W = 300
local PART_BOXES = {
    -- id, label, x, y, w, h (y from the top of the figure)
    { "head",  "HEAD",  105, 0,   70,  34 },
    { "arm_l", "L ARM", 0,   38,  66,  96 },
    { "body",  "BODY",  70,  38,  140, 96 },
    { "arm_r", "R ARM", 214, 38,  66,  96 },
    { "leg_l", "L LEG", 70,  138, 68,  84 },
    { "leg_r", "R LEG", 142, 138, 68,  84 },
}
local BLACK_PART = { 0.13, 0.13, 0.14 }

local function health_shown()
    local body = PDTI.Body
    return body ~= nil and body.Enabled and body.Enabled() and PDTI.InHeist()
end

local function draw_health(win)
    local body = PDTI.Body
    -- The real max health (skills and perks) even before the first hit.
    if body.AttachPlayer then pcall(body.AttachPlayer) end
    local x, y = PAD, 6
    -- The total as the game shows it, rounded once (not the sum of the
    -- rounded parts).
    local now, max = 0, 0
    for _, part in ipairs(PART_BOXES) do
        now = now + body.HP(part[1])
        max = max + body.PartMax(part[1])
    end
    now, max = math.floor(now * 10 + 0.5), math.floor(max * 10 + 0.5)
    label(win, "health_label", string.format("Health  %d / %d", now, max), x, y, HEALTH_W - 2 * PAD)
    y = y + LABEL_H + 4
    for _, part in ipairs(PART_BOXES) do
        local id = part[1]
        local frac = body.Frac(id)
        local color = frac <= 0 and BLACK_PART or body.PartColor(frac)
        local text = string.format("%s\n%d / %d", part[2], body.ShownHP(id), body.ShownMax(id))
        local box = win:Button({
            name = "health_part_" .. id, label = DYN, text = text,
            position = { x + part[3], y + part[4] }, w = part[5], size = part[6],
            font_size = 12, text_align = "center", text_vertical = "center",
            background_color = rgb(color), highlight_color = rgb(color)
        })
        fit(box, part[5], part[6])
    end
    y = y + 226
    local effects = body.EffectLines()
    if #effects == 0 then effects = { "No black parts" } end
    for i, text in ipairs(effects) do
        line(win, "health_effect_" .. i, text, x, y, HEALTH_W - 2 * PAD)
        y = y + LINE_H
    end
    y = y + 4
    line(win, "health_hint_fak", "First aid kit: heals parts above 0", x, y, HEALTH_W - 2 * PAD)
    y = y + LINE_H
    line(win, "health_hint_medic", "Medic bag: heals every part, black too", x, y, HEALTH_W - 2 * PAD)
    y = y + LINE_H
    body.ui_revision = body.state and body.state.revision
    return y + PAD
end

-- Made the first time it is needed (there is no health window in the menu).
local function health_window()
    if view.health then return view.health end
    local ok, win = pcall(function()
        return view.menu:Menu({
            name = "pdti_health",
            position = "CenterBottom",
            scrollbar = false,
            auto_height = false,
            auto_align = false,
            background_color = Color(0.08, 0.08, 0.09),
            background_alpha = 0.92,
            size = 14
        })
    end)
    if ok then view.health = win end
    return view.health
end

local function align(win)
    -- auto_align is off (hundreds of items would re-align on every add), so
    -- the items only get their positions when we align manually.
    local ok, err = pcall(function() win:AlignItems(true) end)
    if not ok then log("AlignItems failed: " .. tostring(err)) end
end

function redraw()
    local left, right = view.left, view.right
    if not left or not right or not view.open then return end
    local model = PDTI.GetInventoryViewModel()
    left:ClearItems(DYN)
    right:ClearItems(DYN)
    view.cells = {}
    view.preview = {}
    -- The backpack decides the right window's width (the heavy pack is wide).
    local bp_w = model.containers.backpack.width * CELL + 2 * PAD
    left:SetSize(WIN_W, 600)
    right:SetSize(math.max(WIN_W, bp_w), 600)
    local lh = draw_left(left, model)
    local rh = draw_right(right, model)
    left:SetSize(WIN_W, lh)
    right:SetSize(math.max(WIN_W, bp_w), rh)
    align(left)
    align(right)
    local health = health_shown() and health_window() or view.health
    if health then
        health:ClearItems(DYN)
        if health_shown() then
            health:SetSize(HEALTH_W, 600)
            health:SetSize(HEALTH_W, draw_health(health))
            align(health)
        else
            health:SetSize(1, 1)
        end
    end
end

------------------------------------------------------------ drag and drop

local function inside(item, x, y)
    local ok, result = pcall(function() return item:MouseInside(x, y) end)
    return ok and result and true or false
end

-- What is under the mouse: a cell ({ container, x, y }), "window" (the
-- inventory, not a cell) or "outside".
function PDTI._UIHit(x, y)
    for _, cell in ipairs(view.cells) do
        if inside(cell.item, x, y) then return { container = cell.container, x = cell.x, y = cell.y } end
    end
    if (view.left and inside(view.left, x, y)) or (view.right and inside(view.right, x, y)) then
        return "window"
    end
    return "outside"
end

local function is_left(button)
    local ids = rawget(_G, "Idstring")
    if not ids or button == nil then return true end
    local ok, left = pcall(ids, "0")
    return not ok or button == left
end

local function clear_preview()
    for _, entry in ipairs(view.preview) do
        pcall(function() entry.panel:remove(entry.rect) end)
    end
    view.preview = {}
end

-- Tints the cells the dragged item would take: green when it fits there,
-- red when it does not.
local function show_preview(hit)
    clear_preview()
    view.last_preview = nil
    if type(hit) ~= "table" then return end
    local p = PDTI.UIDragPreview(hit.container, hit.x, hit.y)
    view.last_preview = p
    if not p then return end
    local color = p.valid and Color(0.25, 0.85, 0.35) or Color(0.9, 0.25, 0.2)
    for _, cell in ipairs(view.cells) do
        if cell.container == p.container and cell.x >= p.x and cell.x < p.x + p.w
            and cell.y >= p.y and cell.y < p.y + p.h then
            pcall(function()
                local panel = cell.item:Panel()
                local rect = panel:rect({ name = "pdti_preview", w = panel:w(), h = panel:h(),
                    color = color, alpha = 0.55, layer = 50 })
                view.preview[#view.preview + 1] = { panel = panel, rect = rect }
            end)
        end
    end
end
PDTI._UIShowPreview = show_preview

function PDTI._UIMousePressed(button, x, y)
    if not view.open or not is_left(button) then return nil end
    local hit = PDTI._UIHit(x, y)
    if type(hit) ~= "table" then return nil end
    local ok = pcall(function()
        if ctrl_down() then
            PDTI.UICellQuickTransfer(hit.container, hit.x, hit.y)
        else
            PDTI.UIDragStart(hit.container, hit.x, hit.y)
        end
        redraw()
        if PDTI.UIIsDragging() then show_preview(hit) end
    end)
    if not ok then log("press failed") end
    -- The cell's own click is not wanted: the drag handles it.
    return false
end

function PDTI._UIMouseMoved(x, y)
    if not view.open or not PDTI.UIIsDragging() then return nil end
    view.mouse = { x, y }
    pcall(show_preview, PDTI._UIHit(x, y))
    return nil
end

function PDTI._UIMouseReleased(button, x, y)
    if not view.open or not PDTI.UIIsDragging() then return nil end
    local hit = PDTI._UIHit(x, y)
    clear_preview()
    local ok, err = pcall(PDTI.UIDragDrop, hit)
    if not ok then log("drop failed: " .. tostring(err)) end
    sync_guns()
    redraw()
    return false
end

local function build()
    if view.menu then return true end
    if not PDTI.IsUIAvailable() then
        log("BeardLib MenuUI is not available; install BeardLib to use the inventory screen")
        return false
    end
    local ok, err = pcall(function()
        view.menu = MenuUI:new({
            name = "PDTI_Inventory",
            layer = 1000,
            -- No background_blur and no background_color: BeardLib shows its
            -- full-screen background whenever either key is set, even to
            -- false, and without a texture it is drawn white.
            enabled = false,
            -- Drag and drop: these see the mouse before any button does.
            pre_mouse_press = function(button, x, y) return PDTI._UIMousePressed(button, x, y) end,
            pre_mouse_move = function(x, y) return PDTI._UIMouseMoved(x, y) end,
            pre_mouse_release = function(button, x, y) return PDTI._UIMouseReleased(button, x, y) end,
            create_items = function(menu)
                local function window(name, position)
                    local win = menu:Menu({
                        name = name,
                        position = position,
                        scrollbar = false,
                        auto_height = false,
                        auto_align = false,
                        background_color = Color(0.08, 0.08, 0.09),
                        background_alpha = 0.92,
                        size = 14
                    })
                    win:SetSize(WIN_W, 400)
                    return win
                end
                view.left = window("pdti_left", "LeftCentery")
                view.right = window("pdti_right", "RightCentery")
            end
        })
    end)
    if not ok then
        view.menu = nil
        log("could not create menu: " .. tostring(err))
        return false
    end
    return true
end

-- Game input. While the screen is open the player's controller is disabled so
-- keys such as R do not reach the game (reload, etc.). The previous enabled
-- state is restored on close. Every call is guarded; the result is logged so
-- a failure shows up in the BLT log instead of breaking the screen.
local function player_controller()
    local unit = managers and managers.player and managers.player:player_unit()
    if not unit or not alive(unit) then return nil, "no player unit (menu or not spawned)" end
    local base = unit:base()
    local controller = base and base.controller and base:controller()
    if not controller then return nil, "player has no controller" end
    return controller
end

local function block_game_input()
    if view.input_block then return end
    local ok, controller, why = pcall(player_controller)
    if not ok then log("input block failed: " .. tostring(controller)); return end
    if not controller then log("input not blocked: " .. tostring(why)); return end
    local ok2, was_enabled = pcall(function() return controller:enabled() end)
    if not ok2 then log("input block failed (enabled): " .. tostring(was_enabled)); return end
    local ok3, err = pcall(function() controller:set_enabled(false) end)
    if not ok3 then log("input block failed (set_enabled): " .. tostring(err)); return end
    view.input_block = { controller = controller, was_enabled = was_enabled }
    log("game input blocked while the inventory is open")
end

local function restore_game_input()
    local block = view.input_block
    view.input_block = nil
    if not block then return end
    pcall(function()
        if block.was_enabled then block.controller:set_enabled(true) end
    end)
end

local function add_keys()
    if #view.triggers > 0 then return end
    local function add(key, fn)
        local ok, trigger = pcall(function() return BeardLib.Utils.Input:Trigger(key, safe(fn)) end)
        if ok and trigger then view.triggers[#view.triggers + 1] = trigger
        else log("could not register key '" .. key .. "': " .. tostring(trigger)) end
    end
    add("r", function()
        if not view.open then return end
        PDTI.UIRotateHeld()
        redraw()
        if PDTI.UIIsDragging() and view.mouse then show_preview(PDTI._UIHit(view.mouse[1], view.mouse[2])) end
    end)
    add("esc", function() if view.open then PDTI.SetUIOpen(false) end end)
end

local function remove_keys()
    for _, trigger in ipairs(view.triggers) do
        pcall(function() BeardLib.Utils.Input:RemoveTrigger(trigger) end)
    end
    view.triggers = {}
end

function PDTI.SetUIOpen(open)
    open = open == true
    if open == view.open then return true end
    if open then
        if not build() then return false end
        if not view.left or not view.right then
            log("window is not ready yet (MenuUI is still initializing); try again")
            return false
        end
        view.open = true
        -- The current profile's inventory; in the menu the plan follows the
        -- weapons you have now.
        if PDTI.OnUIOpen then
            local ok, err = pcall(PDTI.OnUIOpen)
            if not ok then log("opening: " .. tostring(err)) end
        end
        PDTI.SetUIVisible(true)
        log("opening inventory screen")
        view.menu:Enable()
        block_game_input()
        add_keys()
        -- The deployable key has to work inside the screen as well, and the
        -- screen can be opened in the menu where the game hook never runs.
        if PDTI.Deployables then pcall(PDTI.Deployables.EnsureKeyTrigger) end
        redraw()
    else
        view.open = false
        PDTI.UIResetInteraction() -- closing never changes inventory state
        PDTI.SetUIVisible(false)
        remove_keys()
        restore_game_input()
        if view.menu then view.menu:Disable() end
    end
    return true
end

function PDTI.RedrawUI()
    if view.open then redraw() end
end

function PDTI.ToggleUI()
    return PDTI.SetUIOpen(not view.open)
end

function PDTI.IsUIOpen()
    return view.open
end
