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
--   right: the backpack and the test spawner
--
-- The sizes are for a scale of 1 and follow the "ui_scale" setting (applied
-- when the screen opens). The cells are wider than tall: the text in them
-- (rounds and bullets) is wide, and the left window has to fit 720 high.
local BASE = {
    CELL_W = 36, CELL_H = 32, GAP = 2, PAD = 10, LABEL_H = 20,
    BTN_W = 96, BTN_H = 24, BTN_GAP = 4, WIN_W = 320,
    LINE_H = 16, LINE_FONT = 13, CELL_FONT = 11, BTN_FONT = 13,
    LIST_H = 21, LIST_FONT = 12, ROW_H = 23, SMALL_W = 24, HEALTH_W = 330, SHOP_W = 500
}
local CELL_W, CELL_H, GAP, PAD, LABEL_H
local BTN_W, BTN_H, BTN_GAP, WIN_W, INNER_W
local LINE_H, LINE_FONT, CELL_FONT, BTN_FONT
local LIST_H, LIST_FONT, ROW_H, SMALL_W, HEALTH_W, HALF_W, SHOP_W
local UI_SCALE = 1
local MIN_FONT = 8
local DYN = "pdti_dynamic"

local function apply_scale(scale)
    scale = tonumber(scale) or 1
    if scale < 0.6 then scale = 0.6 elseif scale > 1.6 then scale = 1.6 end
    UI_SCALE = scale
    local function s(v) return math.floor(v * scale + 0.5) end
    CELL_W, CELL_H, GAP, PAD, LABEL_H = s(BASE.CELL_W), s(BASE.CELL_H), BASE.GAP, s(BASE.PAD), s(BASE.LABEL_H)
    BTN_W, BTN_H, BTN_GAP, WIN_W = s(BASE.BTN_W), s(BASE.BTN_H), BASE.BTN_GAP, s(BASE.WIN_W)
    INNER_W = WIN_W - 2 * PAD
    LINE_H, LINE_FONT, CELL_FONT, BTN_FONT = s(BASE.LINE_H), s(BASE.LINE_FONT), s(BASE.CELL_FONT), s(BASE.BTN_FONT)
    LIST_H, LIST_FONT, ROW_H, SMALL_W = s(BASE.LIST_H), s(BASE.LIST_FONT), s(BASE.ROW_H), s(BASE.SMALL_W)
    HEALTH_W, SHOP_W = s(BASE.HEALTH_W), s(BASE.SHOP_W)
    HALF_W = math.floor((INNER_W - BTN_GAP) / 2)
end
apply_scale(1)

local function setting_scale()
    local st = PDTI.Ammo and PDTI.Ammo.settings
    return st and st.ui_scale or 1
end

-- The biggest font (at most base, at least MIN_FONT) at which the text fits
-- a box of w x h: a character is about 0.55 of the font size wide, a line
-- about 1.15 of it high.
local function fit_font(text, w, h, base)
    text = tostring(text or "")
    local longest, lines = 0, 0
    for part in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + 1
        if #part > longest then longest = #part end
    end
    lines = math.max(lines, 1)
    local size = math.floor(base)
    while size > MIN_FONT do
        local fits_w = longest == 0 or longest * size * 0.55 <= (w - 4)
        local fits_h = not h or lines * size * 1.15 <= h
        if fits_w and fits_h then break end
        size = size - 1
    end
    return math.max(size, MIN_FONT)
end
PDTI._UIFitFont = fit_font

local view = { menu = nil, left = nil, right = nil, open = false, triggers = {}, input_block = nil,
    cells = {}, slots = {}, preview = {}, pics = {} }

local log = PDTI.Logger("PDTI UI")

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
    pouch = { 0.24, 0.15, 0.08 },     -- copper: the ammo pouch (loose rounds)
    backpack = { 0.15, 0.13, 0.10 },  -- brown: the backpack
    general = { 0.16, 0.16, 0.17 },   -- grey: anything
    medical = { 0.10, 0.24, 0.14 },   -- green: kits and medic bags
    ammo = { 0.27, 0.19, 0.06 },      -- amber: magazines and loose rounds
    ammo_bags = { 0.10, 0.17, 0.30 }  -- blue: ammo bags
}
PDTI.SLOT_KIND_COLORS = SLOT_KIND_COLORS

local function slot_kind(container, model)
    if container == "pockets" or container == "backpack" or container == "pouch" then return container end
    if container == "loot_slot" then return "backpack" end
    for _, section in ipairs(model and model.rig_sections or {}) do
        if section.container == container then return section.kind or "general" end
    end
    return "general"
end

-- The bullets have their colours; standard rounds keep the weapon's
-- (orange PRI, blue SEC). A magazine of several kinds shows its top one.
local BULLET_COLORS = {
    hollow = { 0.74, 0.18, 0.22 },  -- red: hollow points
    ap = { 0.20, 0.58, 0.36 },      -- green: armour piercing
    -- shotgun shells
    custom = { 0.55, 0.42, 0.20 },     -- brown: 000 buckshot
    flechette = { 0.45, 0.52, 0.60 },  -- steel: flechette
    slug = { 0.20, 0.58, 0.36 },       -- green: AP slug (armour piercing)
    tombstone = { 0.45, 0.25, 0.55 },  -- purple: tombstone (poison)
    dragon = { 0.85, 0.40, 0.10 },     -- orange-red: dragon's breath (fire)
    he = { 0.80, 0.70, 0.15 },         -- yellow: HE
    -- LMG rounds
    explosive = { 0.80, 0.70, 0.15 },  -- yellow: HE
    penetrator = { 0.30, 0.50, 0.80 }  -- blue: penetrator
}
PDTI.UI_BULLET_COLORS = BULLET_COLORS

-- Loot bags by quality: standard grey-brown, high blue, exceptional gold.
local LOOT_COLORS = {
    [2] = { 0.25, 0.40, 0.75 },
    [3] = { 0.80, 0.62, 0.15 }
}

local function item_color(def, item)
    local data = item and type(item.data) == "table" and item.data or nil
    local slot = data and data.slot
    if def and def.ammo_managed and data then
        local top = data.bullet
        if data.load and PDTI.Ammo then top = PDTI.Ammo.LoadTop(PDTI.Ammo.LoadOf(data)) or top end
        if BULLET_COLORS[top] then return BULLET_COLORS[top] end
    end
    if def and def.ammo_managed and SLOT_COLORS[slot] then return SLOT_COLORS[slot] end
    if item and item.item_id == "loot_bag" and data and LOOT_COLORS[tonumber(data.quality) or 1] then
        return LOOT_COLORS[tonumber(data.quality) or 1]
    end
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

-- Is a Shift key held? A click on a weapon or a part then inspects it.
local function shift_down()
    local ok, down = pcall(function()
        local kb = Input:keyboard()
        return kb:down(Idstring("left shift")) or kb:down(Idstring("right shift"))
    end)
    if ok and down then return true end
    ok, down = pcall(function()
        local input = BeardLib.Utils.Input
        return input:Down("left shift") or input:Down("right shift")
    end)
    return ok and down and true or false
end
PDTI._shift_down = shift_down

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
local redraw_capture -- forward declaration (the end screen's captured loot window)
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

-- The cells are small: a label has two short lines (what, then how many).
local function short_label(def, item)
    local data = item and item.data
    if def and def.ammo_managed and data and data.rounds then
        -- An assault rifle's or SMG's magazine shows its bullets.
        if data.bullet and PDTI.Ammo and PDTI.Ammo.BULLETS[data.bullet] then
            return tostring(data.rounds) .. "\n" .. PDTI.Ammo.LoadTag(PDTI.Ammo.LoadOf(data), data.bullet, data.family)
        end
        return tostring(data.rounds) .. "\n/" .. tostring(data.capacity or "?")
    end
    -- Loose rounds are labelled by their weapon ("AMCAR AP"); older ones by
    -- their slot.
    local tag = type(data) == "table" and (data.wtag or SLOT_TAGS[data.slot]) or nil
    if def and def.ammo_managed and type(data) == "table" and data.bullet
        and (data.bullet ~= "standard" or data.family == "shell")
        and tag and PDTI.Ammo and PDTI.Ammo.BULLETS[data.bullet] then
        return tag .. " " .. PDTI.Ammo.BulletShort(data.bullet, data.family) .. "\n" .. tostring(item.amount or 0)
    end
    if def and def.ammo_managed and type(data) == "table" and tag then
        return tag .. "\n" .. tostring(item.amount or 0)
    end
    if item and item.item_id == "weapon" and type(data) == "table" and data.name then
        -- A weapon: its name (two short lines at most).
        local n = tostring(data.name)
        if #n > 14 then n = n:sub(1, 13) .. "." end
        if #n > 7 then
            local cut = n:find(" ", 3, true)
            if cut and cut <= 9 then return n:sub(1, cut - 1) .. "\n" .. n:sub(cut + 1) end
        end
        return n
    end
    if item and item.item_id == "weapon_part" and type(data) == "table" and PDTI.Parts then
        -- A weapon part: its type, then the first word of its name.
        local word = tostring(data.name or data.part_id or ""):match("^%S+") or ""
        if #word > 7 then word = word:sub(1, 6) .. "." end
        return PDTI.Parts.Tag(data.ptype) .. "\n" .. word
    end
    if item and item.item_id == "loot_bag" and type(data) == "table" then
        -- The quality's tag (HQ, EX) after the word.
        local tier = PDTI.LootQuality and PDTI.LootQuality.Tier(data)
        local word = tier and tier.tag and ("Bag " .. tier.tag) or "Bag"
        if data.active then return word .. "\n(hand)" end
        if item.amount and item.amount > 1 then return word .. "\nx" .. item.amount end
        return word
    end
    local name = def and def.name or "?"
    -- The first word, at most seven letters.
    name = name:match("^%S+") or name
    if #name > 7 then name = name:sub(1, 6) .. "." end
    if item and item.amount and item.amount > 1 then name = name .. "\nx" .. item.amount end
    return name
end

------------------------------------------------------------ pictures (0.40.0)
-- The game's picture of a weapon or part (ui_pictures.lua finds and loads
-- it), drawn on a MenuUI item's own panel: above its colour (layers 1 and
-- 2) and under its text, which goes up to 5 (the border is 4, the drop
-- preview 50). Whatever fails leaves the item as it was.
local PIC_LAYER, TEXT_LAYER = 3, 5
local PIC_MARGIN = 2
local BASE_PIC_H = 72 -- (the market's picture, at scale 1)
local WEAPON_PIC_H = 120 -- (the weapon view's picture, in the middle of it, at scale 1)
local BOX_PIC_ALPHA = 0.45 -- (PRI / SEC: behind the weapon's name)

-- The path when its picture can be drawn now, else nil.
local function ready(path)
    local Pic = PDTI.Pictures
    if path and Pic and Pic.Enabled() and Pic.Ready(path) then return path end
    return nil
end

local function item_picture(item)
    return ready(PDTI.Pictures and PDTI.Pictures.ItemPath(item))
end

-- The pictures drawn (view.pics): the hidden screen keeps its items, so
-- they are removed when it closes, before their textures go back to the
-- game (as the game removes its own). The ones a redraw cleared away are
-- forgotten at the next.
local function live(o)
    local f = rawget(_G, "alive")
    if not f then return true end
    local ok, yes = pcall(f, o)
    return ok and yes == true
end
local function forget_dead_pics()
    local keep = {}
    for _, e in ipairs(view.pics) do if live(e.bitmap) then keep[#keep + 1] = e end end
    view.pics = keep
end
local function remove_pics()
    for _, e in ipairs(view.pics) do
        if live(e.bitmap) then pcall(function() e.panel:remove(e.bitmap) end) end
    end
    view.pics = {}
end

-- One piece (Pictures.Slices) on the item's panel.
local function draw_piece(btn, path, s)
    local ok = pcall(function()
        local p = { name = "pdti_pic", texture = path, x = s.x, y = s.y, w = s.w, h = s.h, layer = PIC_LAYER }
        if s.rect then p.texture_rect = s.rect end
        if s.rotation and s.rotation ~= 0 then p.rotation = s.rotation end
        if s.alpha then p.alpha = s.alpha end
        local panel = btn:Panel()
        view.pics[#view.pics + 1] = { panel = panel, bitmap = panel:bitmap(p) }
    end)
    if ok then pcall(function() if btn.title then btn.title:set_layer(TEXT_LAYER) end end) end
    return ok
end

-- The whole picture fitted in a box (its shape kept, centred), or nil
-- (the texture's size is not known).
local function fitted(path, panel, bw, bh)
    local Pic = PDTI.Pictures
    local tw, th = Pic.Size(path, panel)
    if not tw then return nil end
    return Pic.Slices(tw, th, 1, 1, bw, bh, 0, false, 0)[1]
end

-- A picture on the right of a bw x bh box (a slot's box in the weapon
-- view): its piece and the width it takes, or nil. (The text keeps the rest.)
local function side_picture(win, path, bw, bh)
    if not path then return nil end
    local pw = math.min(2 * (bh - 4), math.floor(bw * 0.4))
    local s = fitted(path, win:Panel(), pw, bh - 4)
    if not s then return nil end
    s.x, s.y = s.x + bw - pw - 2, s.y + 2
    return s, pw
end

-- A box of its own with the picture in it (the weapon view, the market):
-- the next y (the same y when there is no picture).
local function big_picture(win, name, path, x, y, w, height)
    local h = height or math.floor(BASE_PIC_H * UI_SCALE + 0.5)
    local s = path and fitted(path, win:Panel(), w, h)
    if not s then return y end
    local div = win:Divider({ name = name, label = DYN, text = "", position = { x, y }, w = w, size = h })
    fit(div, w, h)
    draw_piece(div, path, s)
    return y + h + 4
end

-- An insured weapon (armory_insurance.lua): a small blue mark in the
-- corner of its box (its top-right cell in a grid).
local INS_COLOR, INS_MARK = { 0.3, 0.6, 1.0 }, 8
local function insured(item)
    local I = PDTI.Insurance
    return I ~= nil and type(item) == "table" and item.item_id == "weapon" and type(item.data) == "table"
        and I.Policy(item.data.uid) ~= nil
end
local function ins_mark(btn, w)
    pcall(function()
        btn:Panel():rect({ name = "pdti_ins_mark", x = w - INS_MARK - 3, y = 3, w = INS_MARK, h = INS_MARK,
            color = rgb(INS_COLOR), layer = TEXT_LAYER + 1 })
    end)
end

-- A worn weapon (armory_wear.lua): a thin bar along the bottom of its box
-- (its top-left cell in a grid), as long as its condition: green, yellow
-- below 50%, red below 25%. Not drawn at 100%.
local WEAR_H = 3
local function wear_cond(item)
    local W = PDTI.Wear
    if not W or type(item) ~= "table" or item.item_id ~= "weapon" or type(item.data) ~= "table" then return nil end
    local cond = W.Cond(item.data)
    if cond >= 100 then return nil end
    return cond
end
local function wear_color(cond)
    if cond < 25 then return { 0.9, 0.2, 0.2 } end
    if cond < 50 then return { 0.95, 0.8, 0.2 } end
    return { 0.3, 0.85, 0.35 }
end
local function wear_bar(btn, w, h, cond)
    pcall(function()
        btn:Panel():rect({ name = "pdti_wear_bar", x = 3, y = h - WEAR_H - 2,
            w = math.max(1, math.floor((w - 6) * cond / 100 + 0.5)), h = WEAR_H,
            color = rgb(wear_color(cond)), layer = TEXT_LAYER + 1 })
    end)
end

-- first_row, rows: only these rows are drawn, the first at origin_y (the
-- locker scrolls); all of them when not given.
local function draw_grid(win, container, origin_x, origin_y, model, first_row, rows)
    local info = model.containers[container]
    local map = model.occupancy[container]
    if not info or not map then return end
    local held = PDTI.UIGetHeld()
    local empty = SLOT_KIND_COLORS[slot_kind(container, model)] or SLOT_KIND_COLORS.general
    local items_by_id = {}
    for _, item in ipairs(info.items) do items_by_id[item.instance_id] = item end
    -- A weapon's or part's picture across its cells (in PRI / SEC, whole in
    -- its one cell): its pieces by cell, or false.
    local hand = PDTI.HAND_SLOTS[container] ~= nil
    local pics = {}
    local function pieces_of(item)
        local p = pics[item.instance_id]
        if p ~= nil then return p end
        p = false
        local path = item_picture(item)
        local tw, th
        if path then tw, th = PDTI.Pictures.Size(path, win:Panel()) end
        local turned = item.rotated == true and not hand
        local w, h = PDTI.ItemSize(item, turned, container)
        if tw and w then
            local by = {}
            for _, s in ipairs(PDTI.Pictures.Slices(tw, th, w, h, CELL_W, CELL_H, GAP, turned, PIC_MARGIN)) do
                by[s.cx .. "_" .. s.cy] = s
            end
            p = { path = path, by = by }
        end
        pics[item.instance_id] = p
        return p
    end

    first_row = first_row or 0
    local last_row = math.min(map.height, first_row + (rows or map.height)) - 1
    for y = first_row, last_row do
        for x = 0, map.width - 1 do
            local id = map.cells[y + 1][x + 1]
            local item = id and items_by_id[id]
            local def = item and model.item_definitions[item.item_id]
            local text = ""
            local pic = item and pieces_of(item)
            -- (A pictured item's name is optional: the picture alone.)
            if item and item.x == x and item.y == y and not (pic and not PDTI.Pictures.ShowNames()) then
                text = short_label(def, item)
            end

            local base = item_color(def, item)
            local is_held = held and id and held.instance_id == id and held.container == container
            local btn = win:Button({
                name = string.format("cell_%s_%d_%d", container, x, y),
                label = DYN,
                text = text,
                position = { origin_x + x * CELL_W, origin_y + (y - first_row) * CELL_H },
                w = CELL_W - GAP, size = CELL_H - GAP,
                font_size = fit_font(text, CELL_W - GAP, CELL_H - GAP, CELL_FONT),
                -- (A pictured item's name in its corner.)
                text_align = pic and "left" or "center", text_vertical = pic and "top" or "center",
                background_color = item and rgb(base, is_held and 1.5 or 1) or rgb(empty),
                highlight_color = item and rgb(base, 1.3) or rgb(empty, 1.8),
                on_callback = safe(function()
                    if shift_down() and not ctrl_down() and PDTI._UIInspect(container, x, y) then
                        -- (inspected: nothing moves)
                    elseif ctrl_down() then
                        PDTI.UICellQuickTransfer(container, x, y)
                    else
                        PDTI.UICellClick(container, x, y)
                    end
                    sync_guns()
                    redraw()
                end)
            })
            fit(btn, CELL_W - GAP, CELL_H - GAP)
            local piece = pic and pic.by[(x - item.x) .. "_" .. (y - item.y)]
            if piece then draw_piece(btn, pic.path, piece) end
            if item and y == item.y and insured(item) then
                local iw = PDTI.ItemSize(item, item.rotated == true and not hand, container) or 1
                if x == item.x + iw - 1 then ins_mark(btn, CELL_W - GAP) end
            end
            if item and y == item.y and x == item.x then
                local cond = wear_cond(item)
                if cond then wear_bar(btn, CELL_W - GAP, CELL_H - GAP, cond) end
            end
            view.cells[#view.cells + 1] = { item = btn, container = container, x = x, y = y }
        end
    end
end

local function label(win, name, text, x, y, w)
    local div = win:Divider({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = LABEL_H - 4, font_size = fit_font(text, w, nil, LABEL_H - 4)
    })
    fit(div, w, LABEL_H - 2)
    return div
end

-- One line of small text (or h high, for text that wraps). A single line
-- that is too long gets a smaller font.
local function line(win, name, text, x, y, w, h, color)
    h = h or LINE_H
    w = w or INNER_W
    local font = LINE_FONT
    if h <= LINE_H then font = fit_font(text, w, nil, LINE_FONT) end
    local div = win:Divider({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = font, font_size = font, foreground = color
    })
    fit(div, w, h - 1)
    return div
end

local function button(win, name, text, x, y, callback, w)
    w = w or BTN_W
    local btn = win:Button({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = BTN_H, font_size = fit_font(text, w, BTN_H, BTN_FONT),
        text_align = "center", text_vertical = "center",
        background_color = Color(0.18, 0.18, 0.22), highlight_color = Color(0.30, 0.30, 0.38),
        on_callback = callback
    })
    fit(btn, w, BTN_H)
    return btn
end

-- A small coloured button for the lists (two per row).
local function list_button(win, name, text, x, y, color, active, callback, w)
    w = w or HALF_W
    local btn = win:Button({
        name = name, label = DYN, text = text, position = { x, y },
        w = w, size = LIST_H - 2, font_size = fit_font(text, w - 4, LIST_H - 2, LIST_FONT),
        text_align = "left", text_vertical = "center",
        background_color = rgb(color, active and 1.5 or 0.75), highlight_color = rgb(color, 1.3),
        on_callback = callback
    })
    fit(btn, w, LIST_H - 2)
    return btn
end
local function list_pos(i, x, y)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    return x + col * (HALF_W + BTN_GAP), y + row * LIST_H
end

local SLOT_NAMES = { primary = "PRI", secondary = "SEC", throwable = "THR", armour = "ARM" }

local function pct(v) return math.floor((tonumber(v) or 1) * 100 + 0.5) end

local function short(text, n)
    text = tostring(text or "?")
    if #text > n then return text:sub(1, n - 1) .. "." end
    return text
end

-- The room bonus of a piece (perks.lua): "No bonus" and its two rooms. A
-- room below tier 2 (or a bonus not made yet) is dim; picking it says why.
local function pick_perk(piece, room)
    local ok, reason = PDTI.SetPerkChoice(piece, room)
    PDTI.UISetStatus(ok and nil or reason)
end

local equip_tab = "gear"
PDTI._EquipTab = function(tab) if tab then equip_tab = tab end return equip_tab end

-- One piece: a line with what is picked, then its three buttons.
local function draw_perk_piece(win, piece, x, y)
    local perks = PDTI.Perks
    if not perks.PIECES[piece] then return y end
    local choices = perks.Choices(piece)
    local function bx(i) return x + (i - 1) * (BTN_W + BTN_GAP) end
    local picked
    for _, c in ipairs(choices) do if c.chosen then picked = c end end
    local head = perks.PIECES[piece].name .. ": "
    if picked and picked.unlocked then
        head = head .. picked.name .. " " .. string.rep("I", picked.tier) .. ", "
            .. (picked.tier >= 3 and perks.OPTIONS[picked.room].t3 or perks.OPTIONS[picked.room].t2)
    else
        head = head .. "no bonus"
    end
    line(win, "perk_" .. piece .. "_info", head, x, y, INNER_W)
    y = y + LINE_H
    local entries = { { name = "No bonus", chosen = not (picked and picked.unlocked), unlocked = true } }
    for _, c in ipairs(choices) do entries[#entries + 1] = c end
    for i, c in ipairs(entries) do
        local text = c.room and (c.name .. " " .. (c.unlocked and string.rep("I", c.tier) or "-")) or c.name
        local on = c.chosen and (c.room == nil or c.unlocked)
        local btn = win:Button({
            name = "perk_" .. piece .. "_" .. (c.room or "none"), label = DYN,
            text = (on and "> " or "") .. text,
            position = { bx(i), y }, w = BTN_W, size = BTN_H,
            font_size = fit_font(text, BTN_W, BTN_H, BTN_FONT),
            text_align = "center", text_vertical = "center",
            background_color = on and rgb(CATEGORY_COLORS.medical, 1.4)
                or (c.unlocked and Color(0.18, 0.18, 0.22) or Color(0.11, 0.11, 0.13)),
            highlight_color = Color(0.30, 0.30, 0.38),
            on_callback = after(function() pick_perk(piece, c.room) end)
        })
        fit(btn, BTN_W, BTN_H)
    end
    return y + BTN_H + BTN_GAP + 2
end

-- In the menu: the rig and the backpack, or the room bonuses (two tabs).
function draw_equipment(win, model, x, y)
    local perks = PDTI.Perks
    local has_perks = perks and perks.PIECES and PDTI.SetPerkChoice ~= nil
    if has_perks then
        pcall(perks.Refresh)
        local half = math.floor((INNER_W - BTN_GAP) / 2)
        for i, tab in ipairs({ { id = "gear", text = "Rig and backpack" }, { id = "perks", text = "Room bonuses" } }) do
            local on = equip_tab == tab.id
            local btn = win:Button({
                name = "equip_tab_" .. tab.id, label = DYN, text = (on and "> " or "") .. tab.text,
                position = { x + (i - 1) * (half + BTN_GAP), y }, w = half, size = LABEL_H - 2,
                font_size = fit_font(tab.text, half, LABEL_H - 2, BTN_FONT),
                text_align = "center", text_vertical = "center",
                background_color = on and rgb(CATEGORY_COLORS.utility, 1.4) or Color(0.18, 0.18, 0.22),
                highlight_color = Color(0.30, 0.30, 0.38),
                on_callback = after(function() equip_tab = tab.id end)
            })
            fit(btn, half, LABEL_H - 2)
        end
        -- The tabs take the place of the "Rig" heading.
        y = y + LABEL_H
        if equip_tab == "perks" then
            for _, kind in ipairs({ "rig", "backpack" }) do
                y = draw_perk_piece(win, model.equipment[kind], x, y)
            end
            local armour = perks.ArmourPiece()
            if armour then y = draw_perk_piece(win, armour, x, y) end
            return y
        end
    end
    local function bx(i) return x + (i - 1) * (BTN_W + BTN_GAP) end
    for _, kind in ipairs({ "rig", "backpack" }) do
        if kind ~= "rig" or not has_perks then
            label(win, "equip_" .. kind .. "_label", kind == "rig" and "Rig" or "Backpack", x, y, INNER_W)
            y = y + LABEL_H
        end
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
                w = BTN_W, size = BTN_H, font_size = fit_font(option.short, BTN_W, BTN_H, BTN_FONT),
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
        w = w, size = ROW_H - 2, font_size = fit_font(text, w, ROW_H - 2, BTN_FONT),
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

-- A click changes a bullet by a step; Ctrl+click on "+" fills the rest of
-- the magazine with it, on "-" takes all of it out.
local function pick_change(slot, bullet, add)
    local plan = PDTI.Plan
    local ok, reason
    if ctrl_down() and plan.FillPick then
        if add then ok, reason = plan.FillPick(slot, bullet) else ok, reason = plan.ClearPick(slot, bullet) end
    else
        ok, reason = plan.ChangePickCount(slot, bullet, add)
    end
    PDTI.UISetStatus(ok and nil or reason)
end

-- A "-", a "+" and a short text, three to a row.
local function pm_group(win, name, text, x, y, w, minus, plus)
    local pm = math.floor(SMALL_W * 0.8)
    small_button(win, name:gsub("%%s", "minus"), "-", x, y, minus, pm)
    small_button(win, name:gsub("%%s", "plus"), "+", x + pm + 1, y, plus, pm)
    line(win, name:gsub("%%s", "count"), text, x + 2 * pm + 3, y + 2, w - 2 * pm - 5)
end

-- An assault rifle or SMG: the magazine "+" adds. Its size, then how many
-- rounds of each bullet go in (the order is top first; Flip turns it).
-- A shotgun's magazine has no sizes (the game's), and its rounds are the
-- shells the gun takes: three to a row.
local function draw_pick_rows(win, slot, spec, x, y, w, row)
    local Ammo = PDTI.Ammo
    row = row or {}
    local sized = row.sized ~= false
    local bullets = row.bullets or Ammo.BULLET_ORDER
    local label_w = math.floor(SMALL_W * 1.6)
    line(win, "bring_pick_label_" .. slot, "+Mag", x, y + 2, label_w)
    local bx = x + label_w + 2
    if sized then
        for _, id in ipairs(Ammo.SIZE_ORDER) do
            small_button(win, "bring_pick_size_" .. slot .. "_" .. id, Ammo.MAG_SIZES[id].short, bx, y,
                after(function() spec_change(slot, "pick_size", id) end), SMALL_W, spec.size == id)
            bx = bx + SMALL_W + 2
        end
    end
    local flip_w = label_w
    small_button(win, "bring_pick_flip_" .. slot, "Flip", bx + 4, y,
        after(function() PDTI.Plan.FlipPick(slot) end), flip_w)
    local price = PDTI.Plan.AddPrice and PDTI.Plan.AddPrice("mag:" .. slot) or 0
    local ix = bx + flip_w + 8
    line(win, "bring_pick_info_" .. slot, string.format("%d/%d %s", spec.rounds, spec.capacity, PDTI.Ammo.Money(price)),
        ix, y + 2, w - (ix - x))
    y = y + ROW_H
    local group = math.floor(w / 3)
    bx = x
    for i, id in ipairs(bullets) do
        if i > 1 and (i - 1) % 3 == 0 then
            y = y + ROW_H
            bx = x
        end
        local count = 0
        for _, part in ipairs(spec.load) do if part[1] == id then count = count + part[2] end end
        pm_group(win, "bring_pick_%s_" .. slot .. "_" .. id, Ammo.BulletShort(id, row.family) .. " " .. count, bx, y, group,
            after(function() pick_change(slot, id, false) end), after(function() pick_change(slot, id, true) end))
        bx = bx + group
    end
    return y + ROW_H
end

-- A bring row's widget id part, and whether it is an item row (a kind
-- without ":").
local function kind_ids(row)
    local id = tostring(row.kind):gsub(":", "_")
    return id, not tostring(row.kind):find(":")
end

-- What you bring into every heist, w wide. The weapons have full rows, the
-- items two to a row (there are a dozen of them).
local function draw_bring(win, x, y, w)
    local plan = PDTI.Plan
    if not plan then return y end
    w = w or INNER_W
    label(win, "bring_label", "Bring into every heist", x, y, w)
    y = y + LABEL_H
    -- Adding pays at once, taking out pays back; what a heist uses up is
    -- paid again.
    if plan.Cost then
        local Ammo = PDTI.Ammo
        local money = plan.Money and plan.Money()
        local text = "Loadout worth " .. Ammo.Money(plan.Cost())
        if money then text = text .. "   you have " .. Ammo.Money(money) end
        line(win, "bring_cost", text, x, y, w)
        y = y + LINE_H
    end
    local rows = plan.Rows()
    local typed = false
    for _, row in ipairs(rows) do if row.typed then typed = true end end
    if #rows == 0 then
        line(win, "bring_none", "(no weapons known here)", x, y, w)
        return y + LINE_H + 4
    end
    local half = math.floor((w - BTN_GAP) / 2)
    local col = 0 -- the column of the last item placed (0: none on this row)
    local function end_items()
        if col > 0 then y = y + ROW_H; col = 0 end
    end
    local i = 1
    while i <= #rows do
        local row = rows[i]
        local id, is_item = kind_ids(row)
        if not is_item then end_items() end
        if row.category then
            -- An ammunition category's heading (AR/SMG, Shotgun, LMG, Other).
            line(win, "bring_cat_" .. row.category, "-- " .. row.text .. " --", x, y + 2, w)
            y = y + LINE_H + 2
            i = i + 1
            row = rows[i]
            if not row then break end
            id, is_item = kind_ids(row)
        end
        if row.header then
            -- A shotgun loaded shell by shell: its name over its shells.
            line(win, "bring_weapon_" .. row.slot, short(row.name or "", 30), x, y + 2, w)
            y = y + ROW_H - 4
            i = i + 1
            row = rows[i]
            if not row then break end
            id, is_item = kind_ids(row)
        end
        if row.typed then
            line(win, "bring_weapon_" .. row.slot, short(row.name or "", 30), x, y + 2, w)
            y = y + ROW_H - 4
            y = draw_pick_rows(win, row.slot, row.pick, x, y, w, row)
        end
        if row.bullet then
            -- The loose rounds of the bullets share rows, three to a row.
            local bx = x
            local group = math.floor(w / 3)
            local in_row = 0
            while rows[i] and rows[i].bullet do
                if in_row == 3 then
                    y = y + ROW_H
                    bx = x
                    in_row = 0
                end
                in_row = in_row + 1
                local r = rows[i]
                local rid = tostring(r.kind):gsub(":", "_")
                local pm = math.floor(SMALL_W * 0.8)
                small_button(win, "bring_minus_" .. rid, "-", bx, y, after(function() plan_change(r.kind, false) end), pm)
                small_button(win, "bring_plus_" .. rid, "+", bx + pm + 1, y, after(function() plan_change(r.kind, true) end), pm)
                line(win, "bring_line_" .. rid, (r.text:gsub("^%u+ ", "")), bx + 2 * pm + 3, y + 2, group - 2 * pm - 5)
                bx = bx + group
                i = i + 1
            end
            y = y + ROW_H
        else
            -- A weapon's row is as wide as the window, an item's half of it.
            local rx, rw = x, w
            if is_item then
                rx, rw = x + col * (half + BTN_GAP), half
            end
            small_button(win, "bring_minus_" .. id, "-", rx, y, after(function() plan_change(row.kind, false) end))
            small_button(win, "bring_plus_" .. id, "+", rx + SMALL_W + 2, y, after(function() plan_change(row.kind, true) end))
            local text = row.text
            if row.name and not row.typed then text = text .. "  " .. short(row.name, 14) end
            line(win, "bring_line_" .. id, text, rx + 2 * SMALL_W + 6, y + 2, rw - 2 * SMALL_W - 6)
            if is_item then
                col = col + 1
                if col == 2 then y = y + ROW_H; col = 0 end
            else
                y = y + ROW_H
            end
            i = i + 1
        end
    end
    end_items()
    if typed then
        line(win, "bring_pick_hint", "Ctrl+click +: fill the magazine, -: take that bullet out", x, y, w)
        y = y + LINE_H
    end
    return y + 4
end

-- The safehouse stash (0.29.0): the captured bags to choose for, and the
-- bags kept. Each row: name, value, then its buttons.
-- A stash button: works on the end screen too, where the inventory screen
-- (and the guns it keeps in step) is not there.
local function stash_after(action)
    return safe(function()
        action()
        if view.open then
            sync_guns()
            redraw()
        end
        if redraw_capture then redraw_capture() end
    end)
end

local function set_stash_status(why)
    PDTI.UISetStatus(why)
    view.cap_status = why
end

local function stash_action(fn, id)
    return stash_after(function()
        local ok, why = fn(id)
        set_stash_status(ok and nil or why)
    end)
end

local function bag_text(stash, bag, price)
    local text = stash.Name(bag) .. "  " .. PDTI.Ammo.Money(price)
    if bag.mods ~= "" then
        local names = {}
        local LQ = PDTI.LootQuality
        for id in bag.mods:gmatch("[^,]+") do names[#names + 1] = (LQ.MODS[id] or {}).name or id end
        text = text .. "  [" .. table.concat(names, ", ") .. "]"
    end
    return text
end

-- High blue, Exceptional gold, Standard the usual text colour.
local function bag_color(bag)
    local c = LOOT_COLORS[bag.quality]
    return c and rgb(c, 1.25) or nil
end

local function draw_captured(win, stash, x, y, w)
    local pending = stash.Pending()
    label(win, "cap_label", "Captured loot", x, y, w)
    y = y + LABEL_H
    if #pending == 0 then
        line(win, "cap_none", "Nothing waiting. Win a job with bags secured or in your inventory.", x, y, w)
        return y + LINE_H + 4
    end
    line(win, "cap_help", string.format("Stash it, or sell now for %d%% of its value.",
        math.floor((stash.SellNowShare and stash.SellNowShare() or stash.SELL_NOW) * 100 + 0.5)), x, y, w)
    y = y + LINE_H
    local bw = math.floor(SMALL_W * 2.4)
    for _, bag in ipairs(pending) do
        local id = bag.id
        small_button(win, "cap_keep_" .. id, "Stash", x, y, stash_action(stash.Keep, id), bw)
        small_button(win, "cap_sell_" .. id, "Sell " .. PDTI.Ammo.Money(stash.SellNowPrice(bag)), x + bw + 2, y,
            stash_action(stash.SellNow, id), bw + SMALL_W)
        local tx = x + 2 * bw + SMALL_W + 6
        line(win, "cap_line_" .. id, bag_text(stash, bag, bag.value), tx, y + 2, w - (tx - x), nil, bag_color(bag))
        y = y + ROW_H
    end
    local half = math.floor((w - BTN_GAP) / 2)
    button(win, "cap_keep_all", "Stash all", x, y + 2, stash_after(function()
        local left = stash.KeepAll()
        set_stash_status(left > 0 and (left .. " bag(s) did not fit: the safehouse stash is full") or nil)
    end), half)
    button(win, "cap_sell_all", "Sell all now", x + half + BTN_GAP, y + 2, stash_after(function()
        stash.SellAllNow()
        set_stash_status(nil)
    end), half)
    return y + BTN_H + 8
end

local function draw_stash(win, stash, x, y, w)
    local bags = stash.Bags()
    label(win, "stash_label", string.format("Safehouse stash  %d/%d places", math.ceil(stash.CellsUsed() / stash.BAG_CELLS),
        math.floor(stash.Capacity() / stash.BAG_CELLS)), x, y, w)
    y = y + LABEL_H
    if #bags == 0 then
        line(win, "stash_none", "Empty.", x, y, w)
        return y + LINE_H + 4
    end
    local total = 0
    for _, bag in ipairs(bags) do total = total + stash.StoredPrice(bag) end
    line(win, "stash_total", "Worth " .. PDTI.Ammo.Money(total), x, y, w)
    y = y + LINE_H
    local bw = math.floor(SMALL_W * 2.4)
    for _, bag in ipairs(bags) do
        local id = bag.id
        small_button(win, "stash_sell_" .. id, "Sell", x, y, stash_action(stash.Sell, id), bw)
        local tx = x + bw + 4
        local text = bag_text(stash, bag, stash.StoredPrice(bag))
        local m = PDTI.Market
        local f = m and m.FactorText and m.FactorText(bag.carry_id) or ""
        if f ~= "" then text = text .. "  (" .. f .. " today)" end
        line(win, "stash_line_" .. id, text, tx, y + 2, w - (tx - x), nil, bag_color(bag))
        y = y + ROW_H
    end
    return y + 4
end

-- The market (0.33.0): the contracts you took, the day's offers.
local function contract_text(m, c, active)
    local LQ = PDTI.LootQuality
    local name = LQ and LQ.CarryName(c.carry_id) or c.carry_id
    local q = c.quality > 1 and (" (" .. ((LQ and LQ.TIERS[c.quality] or {}).name or "?") .. "+)") or ""
    local text = string.format("%s  %dx %s%s", m.LevelName(c.level), c.count, name, q)
    if active then
        local left = m.DaysLeft(c)
        text = text .. string.format("  %d/%d  %s", math.min(#m.Matching(c), c.count), c.count,
            left == 0 and "today" or (left .. "d left"))
    else
        text = text .. string.format("  %dd", c.days)
    end
    text = text .. string.format("  pays x%.1f +%dc", c.mult, c.coins)
    if c.rare then text = text .. " +High" end
    return text
end

local function draw_market(win, stash, x, y, w)
    local m = PDTI.Market
    label(win, "market_label", "Market  " .. tostring(m.Today()), x, y, w)
    y = y + LABEL_H
    local featured = m.Featured()
    if featured then
        local LQ = PDTI.LootQuality
        line(win, "market_featured", string.format("Ethan & Hila: %s sells for +%d%% today",
            LQ and LQ.CarryName(featured) or featured, math.floor((m.FEATURED - 1) * 100 + 0.5)), x, y, w)
        y = y + LINE_H
    end
    if m.HighRolls() > 0 then
        line(win, "market_high", string.format("High rolls waiting: %d (the next bag you pick up is at least High)",
            m.HighRolls()), x, y, w)
        y = y + LINE_H
    end
    local bw = math.floor(SMALL_W * 2.4)
    local active = m.Active()
    label(win, "market_active_label", string.format("Your contracts  %d/%d", #active, m.MAX_ACTIVE), x, y, w)
    y = y + LABEL_H
    if #active == 0 then
        line(win, "market_active_none", "None. Accept an offer, then deliver its bags from the stash.", x, y, w)
        y = y + LINE_H
    end
    line(win, "market_key", "c: Continental coins.  +High: the next bag you pick up is at least High.", x, y, w)
    y = y + LINE_H
    for i, c in ipairs(active) do
        local key = c.key
        small_button(win, "market_deliver_" .. i, "Deliver", x, y, stash_action(m.Deliver, key), bw, m.CanDeliver(c))
        local tx = x + bw + 4
        line(win, "market_active_" .. i, contract_text(m, c, true), tx, y + 2, w - (tx - x))
        y = y + ROW_H
    end
    y = y + 4
    local offers = m.Offers()
    label(win, "market_offers_label", "Offers today", x, y, w)
    y = y + LABEL_H
    if #offers == 0 then
        line(win, "market_offers_none", "No more offers today.", x, y, w)
        y = y + LINE_H
    end
    for i, o in ipairs(offers) do
        local key = o.key
        small_button(win, "market_accept_" .. i, "Accept", x, y, stash_action(m.Accept, key), bw)
        local tx = x + bw + 4
        line(win, "market_offer_" .. i, contract_text(m, o, false), tx, y + 2, w - (tx - x))
        y = y + ROW_H
    end
    return y + 4
end

-- The market's prices (the left window while the market is open): every
-- loot type in a list that scrolls, and the last 7 days of the one picked.
local GRAPH = "pdti_graph"
-- The price list keeps its own label: a redraw (the health, the ammunition)
-- leaves it where it was scrolled to unless its rows changed.
local PRICES = "pdti_prices"
local PRICE_ROWS = 10      -- rows seen at once (the rest scroll)
local GRAPH_H = 80         -- the tallest bar

local function short_money(v)
    v = tonumber(v) or 0
    if v >= 1000000 then return string.format("$%.1fM", v / 1000000) end
    if v >= 10000 then return string.format("$%dk", math.floor(v / 1000 + 0.5)) end
    if v >= 1000 then return string.format("$%.1fk", v / 1000) end
    return "$" .. math.floor(v + 0.5)
end
PDTI._UIShortMoney = short_money

local WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local function weekday(day)
    local y, m, d = tostring(day):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return "?" end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return t and WEEKDAYS[tonumber(os.date("%w", t)) + 1] or "?"
end

-- The graph of the picked type; drawn alone when a row is clicked, so the
-- list keeps where it was scrolled to.
local function draw_price_graph(win)
    local at = view.graph_at
    local m = PDTI.Market
    if not at or not m then return at and at.y or 0 end
    pcall(function() win:ClearItems(GRAPH) end)
    local x, y, w = at.x, at.y, at.w
    local id = view.market_pick
    local LQ = PDTI.LootQuality
    local name = id and (LQ and LQ.CarryName(id) or id) or nil
    if not id then
        local t = "Click a loot type for its last 7 days."
        local d = win:Divider({ name = "market_graph_none", label = GRAPH, text = t, position = { x, y }, w = w,
            size = LINE_FONT, font_size = fit_font(t, w, nil, LINE_FONT) })
        fit(d, w, LINE_H - 1)
        return y + LINE_H
    end
    local hist = m.History(id)
    local title = win:Divider({ name = "market_graph_title", label = GRAPH, text = name .. ": the last 7 days",
        position = { x, y }, w = w, size = LINE_FONT, font_size = fit_font(name .. ": the last 7 days", w, nil, LINE_FONT) })
    fit(title, w, LINE_H - 1)
    y = y + LINE_H + 2
    local lo, hi = math.huge, -math.huge
    for _, h in ipairs(hist) do lo = math.min(lo, h.price); hi = math.max(hi, h.price) end
    local gap = 4
    local bw = math.floor((w - (#hist - 1) * gap) / #hist)
    local base_y = y + LINE_H + GRAPH_H
    for i, h in ipairs(hist) do
        local bh = hi > lo and math.floor(GRAPH_H * (0.25 + 0.75 * (h.price - lo) / (hi - lo)) + 0.5) or math.floor(GRAPH_H * 0.6)
        local bx = x + (i - 1) * (bw + gap)
        local today = i == #hist
        local color = today and { 0.95, 0.75, 0.2 } or { 0.35, 0.55, 0.85 }
        local price_text = short_money(h.price)
        local pt = win:Divider({ name = "market_graph_price_" .. i, label = GRAPH, text = price_text,
            position = { bx, base_y - bh - LINE_H }, w = bw, size = LINE_FONT, text_align = "center",
            font_size = fit_font(price_text, bw, nil, LINE_FONT) })
        fit(pt, bw, LINE_H - 1)
        local bar = win:Button({ name = "market_graph_bar_" .. i, label = GRAPH, text = "",
            position = { bx, base_y - bh }, w = bw, size = bh,
            background_color = rgb(color), highlight_color = rgb(color) })
        fit(bar, bw, bh)
        local dt = today and "Today" or weekday(h.day)
        local dl = win:Divider({ name = "market_graph_day_" .. i, label = GRAPH, text = dt,
            position = { bx, base_y + 2 }, w = bw, size = LINE_FONT, text_align = "center",
            font_size = fit_font(dt, bw, nil, LINE_FONT) })
        fit(dl, bw, LINE_H - 1)
    end
    return base_y + 2 + LINE_H
end
PDTI._UIDrawPriceGraph = function() if view.left then draw_price_graph(view.left); align(view.left) end end

local function draw_prices(win)
    local m = PDTI.Market
    local x, y, w = PAD, 6, INNER_W
    local rows = m.Catalog()
    label(win, "market_prices_label", string.format("Prices  (%d loot types, dearest first)", #rows), x, y, w)
    y = y + LABEL_H
    line(win, "market_prices_help", "Now: today's price. Real: the bag's base value.", x, y, w)
    y = y + LINE_H
    line(win, "market_prices_help2", "For a Standard bag; your bags: their value x the change.", x, y, w)
    y = y + LINE_H + 2
    if #rows == 0 then
        pcall(function() win:ClearItems(PRICES) end)
        view.price_list, view.price_sig = nil, nil
        line(win, "market_prices_none", "No loot types found.", x, y, w)
        view.graph_at = nil
        return y + LINE_H + PAD
    end
    local list_h = math.min(#rows, PRICE_ROWS) * ROW_H
    if view.market_pick == nil and rows[1] then
        for _, r in ipairs(rows) do if r.stashed > 0 then view.market_pick = r.carry_id break end end
        view.market_pick = view.market_pick or rows[1].carry_id
    end
    local texts = {}
    for i, r in ipairs(rows) do
        texts[i] = string.format("%s%s   now %s   real %s%s", r.name, r.stashed > 0 and (" (" .. r.stashed .. ")") or "",
            short_money(r.now), short_money(r.real), r.change ~= "" and ("   " .. r.change) or "")
    end
    local sig = table.concat({ x, y, w, ROW_H, table.concat(texts, "|") }, "#")
    if view.price_list and view.price_sig == sig then
        -- The same rows: the list stays, scrolled where it was.
        y = y + list_h + 8
        view.graph_at = { x = x, y = y, w = w }
        return draw_price_graph(win) + PAD
    end
    pcall(function() win:ClearItems(PRICES) end)
    view.price_sig = sig
    local list = win:Menu({ name = "market_prices", label = PRICES, position = { x, y }, w = w,
        auto_height = true, max_height = math.max(ROW_H, list_h), scrollbar = #rows > PRICE_ROWS,
        background_color = Color(0.12, 0.12, 0.14), size = LIST_FONT })
    view.price_list = list
    PDTI._UIPriceBuilds = (PDTI._UIPriceBuilds or 0) + 1
    local rw = w - (#rows > PRICE_ROWS and 14 or 0)
    for i, r in ipairs(rows) do
        local text = texts[i]
        local id = r.carry_id
        local row = list:Button({ name = "market_price_" .. id, label = DYN, text = text, w = rw, size = ROW_H - 2,
            font_size = fit_font(text, rw - 8, ROW_H - 2, LIST_FONT), text_vertical = "center",
            background_color = Color(0.16, 0.16, 0.19), highlight_color = Color(0.30, 0.30, 0.38),
            on_callback = safe(function()
                view.market_pick = id
                draw_price_graph(win)
                align(win)
            end) })
        fit(row, rw, ROW_H - 2)
    end
    fit(list, w, list_h)
    y = y + list_h + 8
    view.graph_at = { x = x, y = y, w = w }
    return draw_price_graph(win) + PAD
end

-- The weapons market (0.36.0, armory.lua): every weapon in a list that
-- scrolls on the left (kept like the loot prices), the picked one with its
-- Buy button in the middle.
local WPRICES = "pdti_wprices"

local function weapon_row_text(r)
    local f = PDTI.Armory.FactorText(r.weapon_id)
    return string.format("%s   %s   (normal %s%s)   %s", r.name, short_money(r.today), short_money(r.normal),
        f ~= "" and (", " .. f) or "", r.stock > 0 and (r.stock .. " for sale") or "none today")
end

-- The weapons by page (0.42.0): primary or secondary, then the weapon's
-- type (Armory.TYPES), each its own list. A page or a type with no weapons
-- gives way to the first that has some; the weapon picked is one of the
-- list shown (the first, until you pick one).
local WEAPON_PAGES = { { id = "primaries", text = "Primary" }, { id = "secondaries", text = "Secondary" } }
local TYPE_COLS = 4 -- type buttons a row

local function weapon_view(all)
    local by = { primaries = {}, secondaries = {} }
    for _, r in ipairs(all) do
        local page = by[r.category]
        if page then
            page[r.wtype] = page[r.wtype] or {}
            table.insert(page[r.wtype], r)
        end
    end
    local page = view.weapon_page
    if not (by[page] and next(by[page])) then page = next(by.primaries) and "primaries" or "secondaries" end
    local types = {}
    for _, ty in ipairs(PDTI.Armory.TYPES) do
        if by[page][ty.id] then types[#types + 1] = ty end
    end
    local wtype = view.weapon_type
    if not by[page][wtype] then wtype = types[1] and types[1].id end
    local rows = wtype and by[page][wtype] or {}
    local picked = false
    for _, r in ipairs(rows) do
        if r.weapon_id == view.weapon_pick then picked = true end
    end
    if not picked then view.weapon_pick = rows[1] and rows[1].weapon_id end
    view.weapon_page, view.weapon_type = page, wtype
    return by, page, types, wtype, rows
end

local function draw_weapon_prices(win)
    local A = PDTI.Armory
    local x, y, w = PAD, 6, INNER_W
    local by, page, types, wtype, rows = weapon_view(A.Catalog())
    -- The pages: primary, secondary (how many each).
    local pw = math.floor((w - BTN_GAP) / 2)
    for i, pg in ipairs(WEAPON_PAGES) do
        local n = 0
        for _, list in pairs(by[pg.id]) do n = n + #list end
        small_button(win, "wmarket_page_" .. pg.id, string.format("%s (%d)", pg.text, n), x + (i - 1) * (pw + BTN_GAP), y,
            after(function()
                if view.weapon_page ~= pg.id then view.weapon_page, view.weapon_type = pg.id, nil end
            end), pw, page == pg.id)
    end
    y = y + ROW_H + 2
    -- Its types, a row of four at most.
    local cols = math.max(1, math.min(TYPE_COLS, #types))
    local tw = math.floor((w - (cols - 1) * BTN_GAP) / cols)
    for i, ty in ipairs(types) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        small_button(win, "wmarket_type_" .. ty.id, ty.short, x + col * (tw + BTN_GAP), y + row * ROW_H,
            after(function() view.weapon_type = ty.id end), tw, wtype == ty.id)
    end
    y = y + math.ceil(#types / cols) * ROW_H + 2
    local name = "Weapons"
    for _, ty in ipairs(types) do
        if ty.id == wtype then name = ty.name end
    end
    label(win, "wmarket_prices_label", string.format("%s  (%d)", name, #rows), x, y, w)
    y = y + LABEL_H
    line(win, "wmarket_prices_help", "Today's price, the game's own, and how many are for sale.", x, y, w)
    y = y + LINE_H + 2
    if #rows == 0 then
        pcall(function() win:ClearItems(WPRICES) end)
        view.wprice_list, view.wprice_sig = nil, nil
        line(win, "wmarket_prices_none", "No weapons found.", x, y, w)
        return y + LINE_H + PAD
    end
    local texts = {}
    for i, r in ipairs(rows) do texts[i] = weapon_row_text(r) end
    local list_h = math.min(#rows, PRICE_ROWS) * ROW_H
    local sig = table.concat({ x, y, w, ROW_H, table.concat(texts, "|") }, "#")
    if view.wprice_list and view.wprice_sig == sig then return y + list_h + PAD end
    pcall(function() win:ClearItems(WPRICES) end)
    view.wprice_sig = sig
    local list = win:Menu({ name = "wmarket_prices", label = WPRICES, position = { x, y }, w = w,
        auto_height = true, max_height = math.max(ROW_H, list_h), scrollbar = #rows > PRICE_ROWS,
        background_color = Color(0.12, 0.12, 0.14), size = LIST_FONT })
    view.wprice_list = list
    PDTI._UIWeaponPriceBuilds = (PDTI._UIWeaponPriceBuilds or 0) + 1
    local rw = w - (#rows > PRICE_ROWS and 14 or 0)
    for i, r in ipairs(rows) do
        local text = texts[i]
        local id = r.weapon_id
        local row = list:Button({ name = "wmarket_price_" .. id, label = DYN, text = text, w = rw, size = ROW_H - 2,
            font_size = fit_font(text, rw - 8, ROW_H - 2, LIST_FONT), text_vertical = "center",
            background_color = Color(0.16, 0.16, 0.19), highlight_color = Color(0.30, 0.30, 0.38),
            on_callback = after(function() view.weapon_pick = id end) })
        fit(row, rw, ROW_H - 2)
    end
    fit(list, w, list_h)
    return y + list_h + PAD
end

-- A weapon's parts for sale (0.38.0, armory_parts.lua): a list that
-- scrolls under its Buy button, kept while it shows the same rows.
local PARTS = "pdti_parts"

local function part_row_text(r)
    local f = PDTI.Armory.FactorText(r.part_id)
    return string.format("%s: %s   %s%s", PDTI.Parts.Tag(r.ptype), r.name, short_money(r.today),
        f ~= "" and ("  (" .. f .. ")") or "")
end

local function draw_part_list(win, weapon_id, x, y, w)
    local P = PDTI.Parts
    local rows = P.ForWeapon(weapon_id)
    view.parts_drawn = true
    label(win, "wmarket_parts_label", string.format("Parts for the %s  (%d)", PDTI.Armory.Name(weapon_id), #rows), x, y, w)
    y = y + LABEL_H
    if #rows == 0 then
        pcall(function() win:ClearItems(PARTS) end)
        view.parts_list, view.parts_sig = nil, nil
        line(win, "wmarket_parts_none", "No parts for sale for this weapon.", x, y, w)
        return y + LINE_H + 4
    end
    local picked = nil
    for _, r in ipairs(rows) do
        if r.part_id == view.part_pick then picked = r end
    end
    local texts = {}
    for i, r in ipairs(rows) do texts[i] = part_row_text(r) end
    local list_h = math.min(#rows, PRICE_ROWS) * ROW_H
    local sig = table.concat({ weapon_id, x, y, w, ROW_H, table.concat(texts, "|") }, "#")
    if not (view.parts_list and view.parts_sig == sig) then
        pcall(function() win:ClearItems(PARTS) end)
        view.parts_sig = sig
        local list = win:Menu({ name = "wmarket_parts", label = PARTS, position = { x, y }, w = w,
            auto_height = true, max_height = math.max(ROW_H, list_h), scrollbar = #rows > PRICE_ROWS,
            background_color = Color(0.12, 0.12, 0.14), size = LIST_FONT })
        view.parts_list = list
        local rw = w - (#rows > PRICE_ROWS and 14 or 0)
        for i, r in ipairs(rows) do
            local text = texts[i]
            local id = r.part_id
            local row = list:Button({ name = "wmarket_part_" .. id, label = DYN, text = text, w = rw, size = ROW_H - 2,
                font_size = fit_font(text, rw - 8, ROW_H - 2, LIST_FONT), text_vertical = "center",
                background_color = Color(0.16, 0.16, 0.19), highlight_color = Color(0.30, 0.30, 0.38),
                on_callback = after(function() view.part_pick = id end) })
            fit(row, rw, ROW_H - 2)
        end
        fit(list, w, list_h)
    end
    y = y + list_h + 4
    if not picked then
        line(win, "wmarket_part_none", "Pick a part in the list. A bought part goes into your locker.", x, y, w)
        return y + LINE_H + 4
    end
    button(win, "wmarket_buy_part", "Buy " .. picked.name .. " " .. PDTI.Ammo.Money(picked.today), x, y,
        stash_action(function() return P.Buy(weapon_id, picked.part_id) end), w)
    return y + BTN_H + 4
end

-- The insured weapons on their way back (armory_insurance.lua), a line each.
local function draw_returns(win, prefix, x, y, w)
    local I = PDTI.Insurance
    if not I then return y end
    for i, text in ipairs(I.ReturnLines()) do
        line(win, prefix .. "_return_" .. i, text, x, y, w)
        y = y + LINE_H
    end
    return y
end

local function draw_weapon_market(win, x, y, w)
    local A = PDTI.Armory
    label(win, "wmarket_label", "Weapons market  " .. tostring(A.Today()), x, y, w)
    y = y + LABEL_H
    y = draw_returns(win, "wmarket", x, y, w)
    -- (Drawn before the list on the left: the page and the pick are settled here too.)
    weapon_view(A.Catalog())
    local id = view.weapon_pick
    if not id then
        line(win, "wmarket_none", "Pick a weapon on the left.", x, y, w)
        return y + LINE_H + 4
    end
    local stock = A.Stock(id)
    local f = A.FactorText(id)
    line(win, "wmarket_pick", string.format("%s: %s today (normal %s%s)", A.Name(id), PDTI.Ammo.Money(A.TodayPrice(id)),
        PDTI.Ammo.Money(A.BasePrice(id)), f ~= "" and (", " .. f) or ""), x, y, w)
    y = y + LINE_H
    line(win, "wmarket_stock", stock > 0 and (stock .. " for sale today.") or "None for sale today: come back tomorrow.", x, y, w)
    y = y + LINE_H + 2
    y = big_picture(win, "wmarket_picture", ready(PDTI.Pictures and PDTI.Pictures.WeaponPath(id)), x, y, w)
    button(win, "wmarket_buy", "Buy " .. PDTI.Ammo.Money(A.TodayPrice(id)), x, y, stash_action(A.Buy, id), w)
    y = y + BTN_H + 6
    line(win, "wmarket_owned", string.format("A bought weapon goes into your locker (the inventory's Locker tab): %d weapon(s) now.",
        #A.Weapons()), x, y, w)
    y = y + LINE_H + 6
    if PDTI.Parts then y = draw_part_list(win, id, x, y, w) end
    return y
end

-- Inspect (0.38.0): right-click (or Shift+click) a weapon or a part. The
-- middle window shows what it is: a weapon with its slots (0.38.2), a box
-- for each with the part in it; both can be sold (a second click sells).
local function inspected()
    local i = view.inspect
    local item = i and PDTI.FindItem(i.container, i.instance_id)
    if not item or (item.item_id ~= "weapon" and item.item_id ~= "weapon_part") then
        view.inspect = nil
        return nil
    end
    return item
end

-- Opens Inspect for the item in this cell (in a heist too, 0.39.0: in the
-- health window's place). True when it did.
function PDTI._UIInspect(container, x, y)
    if not PDTI.Parts or not PDTI.Parts.Reachable(container) then return false end
    local map = PDTI.GetOccupancyMap(container)
    local row = map and map.cells[y + 1]
    local id = row and row[x + 1]
    local item = id and PDTI.FindItem(container, id)
    if not item or (item.item_id ~= "weapon" and item.item_id ~= "weapon_part") then return false end
    view.inspect = { container = container, instance_id = id }
    view.sell_armed, view.inspect_status = nil, nil
    PDTI.UICancelHeld()
    return true
end

local function inspect_status(msg)
    view.inspect_status = msg
    PDTI.UISetStatus(msg)
end

-- The weapon's slots (0.38.2), around the weapon's picture (0.41.0): the
-- parts that go on top of it (the sights, the gadgets) above the picture,
-- the ones that hang under it (the grip, the foregrip, the stock, the
-- magazine) below it. A box for each, with the part in it (yours in a
-- part's colour, the weapon's own grey, an empty slot dark). Drag a part
-- onto its slot to fit it; drag yours out onto a cell, or Ctrl+click it, to
-- take it off (ui_interaction.lua: the slot drag).
local SLOT_COLS = 3
local OWN_PART = { 0.30, 0.30, 0.32 }
-- The slots that go on top of the weapon; every other slot is under it.
local TOP_TYPES = { sight = true, gadget = true, bonus = true }
-- The order of the slots on top of the weapon, and of the ones under it (the
-- ones that hang under it first, then the gun's own parts).
local TOP_ORDER = { "sight", "gadget", "bonus" }
local BOTTOM_ORDER = { "grip", "foregrip", "vertical_grip", "stock", "magazine", "ammo",
    "custom", "extra", "drag_handle", "barrel_ext", "barrel", "upper_reciever", "lower_reciever", "slide" }
-- job: the change going on in a heist on this weapon (armory_hotmod.lua).
local function slot_text(s, job)
    local P = PDTI.Parts
    if job and job.ptype == s.ptype then
        return P.TypeName(s.ptype) .. "\n" .. string.format("%s... %d%%", job.kind == "fit" and "Fitting" or "Taking off",
            math.floor(job.progress * 100))
    end
    local what
    if not s.part_id then what = "empty"
    elseif s.name then what = s.name
    elseif s.standard then what = "standard"
    else what = s.part_id end
    if s.part_id and not s.standard and not s.removable then what = what .. " (fixed)" end
    -- (In a heist magazines are changed at home.)
    if s.ptype == "magazine" and PDTI.InHeist() then what = what .. " (at home)" end
    return P.TypeName(s.ptype) .. "\n" .. short(what, 26)
end

-- The weapon's slots in two bands: the ones on top of the weapon and the
-- ones under it, each in its own order.
local function slot_bands(slots)
    local top, bottom = {}, {}
    for _, s in ipairs(slots) do
        if TOP_TYPES[s.ptype] then top[#top + 1] = s else bottom[#bottom + 1] = s end
    end
    local function by_order(list, order)
        local function rank(ptype)
            for i, t in ipairs(order) do
                if t == ptype then return i end
            end
            return #order + 1
        end
        table.sort(list, function(a, b)
            local ra, rb = rank(a.ptype), rank(b.ptype)
            if ra ~= rb then return ra < rb end
            if a.ptype ~= b.ptype then return a.ptype < b.ptype end
            return (a.part_id or "") < (b.part_id or "")
        end)
    end
    by_order(top, TOP_ORDER)
    by_order(bottom, BOTTOM_ORDER)
    return top, bottom
end

-- A slot's box: the part in it, with its picture on the right (not on the
-- weapon's own standard parts).
local function draw_slot_box(win, at, d, s, index, x, y, bw, bh)
    local slot = { container = at.container, instance_id = at.instance_id, ptype = s.ptype, part_id = s.part_id }
    local base = s.removable and CATEGORY_COLORS.utility or (s.part_id and OWN_PART or SLOT_KIND_COLORS.general)
    local out = PDTI.UIGetSlotDrag()
    local job = PDTI.HotMod and PDTI.HotMod.Active()
    if job and job.weapon_uid ~= d.uid then job = nil end
    local lifted = out and s.part_id ~= nil and out.part_id == s.part_id
    local text = slot_text(s, job)
    local path = s.part_id and not s.standard and ready(PDTI.Pictures and PDTI.Pictures.PartPath(s.part_id))
    local piece, pw = side_picture(win, path, bw, bh)
    local btn = win:Button({
        name = "inspect_slot_" .. index, label = DYN, text = text,
        position = { x, y }, w = bw, size = bh,
        font_size = fit_font(text, piece and (bw - pw - 4) or bw, bh, CELL_FONT),
        text_align = piece and "left" or "center", text_vertical = "center",
        background_color = rgb(base, lifted and 1.5 or 1), highlight_color = rgb(base, 1.3),
        -- (A press is the drag's, _UIMousePressed; this is the click's
        -- own way, when the press did not take it.)
        on_callback = after(function()
            if ctrl_down() then
                PDTI.UISlotTakeOff(slot)
                view.inspect_status = PDTI.UIGetStatus()
            else
                PDTI.UISetStatus("Drag it out of its slot onto a cell, or Ctrl+click it, to take it off")
            end
        end)
    })
    fit(btn, bw, bh)
    if piece then draw_piece(btn, path, piece) end
    view.slots[#view.slots + 1] = { item = btn, slot = slot }
    return btn
end

-- A band of slots (the ones on top of the weapon, or the ones under it): a
-- row of boxes, three to a row. The next y and the number of the next box.
local function draw_slot_band(win, at, d, slots, x, y, w, first)
    if #slots == 0 then return y, first end
    local bw = math.floor((w - (SLOT_COLS - 1) * BTN_GAP) / SLOT_COLS)
    local bh = 2 * LINE_H + 4
    for i, s in ipairs(slots) do
        local col, row = (i - 1) % SLOT_COLS, math.floor((i - 1) / SLOT_COLS)
        draw_slot_box(win, at, d, s, first + i - 1, x + col * (bw + BTN_GAP),
            y + row * (bh + BTN_GAP), bw, bh)
    end
    return y + math.ceil(#slots / SLOT_COLS) * (bh + BTN_GAP) + 2, first + #slots
end

-- The build templates (0.41.0): the builds you saved. Save the build of the
-- weapon you are looking at, and put one on any weapon later. The parts are
-- still yours: a template is a recipe, not a copy of the parts.
local TEMPLATE_ROWS = 8
local function draw_templates(win, at, d, x, y, w)
    local T = PDTI.Templates
    if not T then return y end
    label(win, "templates_label", "Build templates", x, y, w)
    y = y + LABEL_H
    local list = T.All()
    if #list == 0 then
        line(win, "templates_none", "No templates yet: save this build to put it on another weapon.", x, y, w)
        y = y + LINE_H + 2
    else
        local apply_w, del_w = 56, 40
        local name_w = w - apply_w - del_w - 2 * BTN_GAP
        for i, t in ipairs(list) do
            if i > TEMPLATE_ROWS then break end
            -- (Its own id: the loop's variable is not the one to keep.)
            local tid = t.id
            local text = string.format("%s  (%d part(s))", tostring(t.name or "build"), #(t.parts or {}))
            line(win, "template_line_" .. tostring(tid), short(text, 44), x, y + 2, name_w)
            small_button(win, "template_apply_" .. tostring(tid), "Apply", x + name_w + BTN_GAP, y,
                after(function()
                    local ok, msg = T.Apply(tid, at.container, at.instance_id)
                    inspect_status(msg)
                end), apply_w)
            small_button(win, "template_delete_" .. tostring(tid), "Del", x + name_w + BTN_GAP + apply_w + BTN_GAP, y,
                after(function()
                    local ok, msg = T.Delete(tid)
                    inspect_status(msg)
                end), del_w)
            y = y + ROW_H
        end
        if #list > TEMPLATE_ROWS then
            line(win, "templates_more", string.format("and %d more template(s)", #list - TEMPLATE_ROWS), x, y + 2, w)
            y = y + LINE_H
        end
        y = y + 2
    end
    button(win, "template_save", "Save this build as a template", x, y, after(function()
        local ok, t, msg = T.Save(d)
        inspect_status(msg)
    end), w)
    y = y + BTN_H + 4
    return y
end

-- The weapon's view (0.41.0): its picture in the middle, its slots around
-- it (the ones on top of it above the picture, the ones under it below).
local function draw_weapon_view(win, at, item, d, x, y, w)
    local P = PDTI.Parts
    local slots = P.Slots(d)
    local yours = 0
    for _, s in ipairs(slots) do
        if s.removable then yours = yours + 1 end
    end
    label(win, "inspect_parts_label", string.format("Slots  (%d; %d part(s) of yours)", #slots, yours), x, y, w)
    y = y + LABEL_H
    local top, bottom = slot_bands(slots)
    local index = 1
    if #top > 0 then
        line(win, "inspect_slots_top", "On top of the weapon", x, y, w)
        y = y + LINE_H + 2
        y, index = draw_slot_band(win, at, d, top, x, y, w, index)
    end
    -- The weapon's picture, in the middle of the view.
    y = big_picture(win, "inspect_picture", item_picture(item), x, y, w,
        math.floor(WEAPON_PIC_H * UI_SCALE + 0.5))
    if #bottom > 0 then
        line(win, "inspect_slots_bottom", "Under the weapon", x, y, w)
        y = y + LINE_H + 2
        y, index = draw_slot_band(win, at, d, bottom, x, y, w, index)
    end
    line(win, "inspect_slots_help", "Drag a part onto its slot to fit it. Drag yours out onto a cell, or Ctrl+click it, to take it off.",
        x, y, w, 2 * LINE_H)
    y = y + 2 * LINE_H + 2
    if PDTI.InHeist() then
        line(win, "inspect_heist_help", "In a heist each change takes time: shooting, aiming, reloading or switching stops it.",
            x, y, w, 2 * LINE_H)
        y = y + 2 * LINE_H + 2
    end
    return y
end

-- The weapon view's insurance (0.45.0, at home): insure it, or what it is
-- insured for and the Cancel button. What the last change at home did to it.
local function draw_insurance(win, at, d, x, y, w)
    local I = PDTI.Insurance
    local money = PDTI.Ammo.Money
    if d.free then
        line(win, "inspect_insure_free", "A free weapon needs no insurance: it is given again.", x, y, w)
        return y + LINE_H + 4
    end
    local p = I.Policy(d.uid)
    if p then
        line(win, "inspect_insured", string.format("Insured: lost, it is back in your locker %s after the heist.",
            I.DelayText()), x, y, w)
        y = y + LINE_H
        button(win, "inspect_uninsure", "Cancel insurance (" .. money(p.paid) .. " back)", x, y, after(function()
            local _, msg = I.CancelItem(at.container, at.instance_id)
            inspect_status(msg)
        end), w)
        return y + BTN_H + 4
    end
    local note = I.Note(d.uid)
    if note then
        line(win, "inspect_insure_note", note, x, y, w, 2 * LINE_H)
        y = y + 2 * LINE_H
    end
    button(win, "inspect_insure", string.format("Insure for %s (back %s after a loss)", money(I.Price(d)),
        I.DelayText()), x, y, after(function()
        local _, msg = I.Insure(at.container, at.instance_id)
        inspect_status(msg)
    end), w)
    return y + BTN_H + 4
end

local function draw_inspect(win, x, y, w)
    local P = PDTI.Parts
    local item = inspected()
    if not item then return nil end
    local at = view.inspect
    local d = item.data
    local weapon = item.item_id == "weapon"
    local name = weapon and tostring(d.name or d.weapon_id) or P.Name(d.part_id)
    label(win, "inspect_label", "Inspect: " .. name, x, y, w)
    y = y + LABEL_H
    if weapon then
        local mag
        if PDTI.HAND_SLOTS[at.container] then mag = "its magazine is in its slot's box"
        elseif (tonumber(d.gun_n) or 0) > 0 then mag = string.format("a magazine of %d rounds loaded", tonumber(d.gun1_rounds) or 0)
        elseif d.gun_set == 1 then mag = "no magazine loaded"
        else mag = "a full magazine comes with it" end
        local conceal = P.Concealment(d)
        line(win, "inspect_weight", string.format("%.1f kg%s, %s.", PDTI.ItemWeight(item),
            conceal and (", concealment " .. conceal) or "", mag), x, y, w)
        y = y + LINE_H + 2
        -- Its condition (armory_wear.lua).
        local W = PDTI.Wear
        if W and not d.free then
            local cond = W.Cond(d)
            line(win, "inspect_condition", string.format("Condition %d%%: %s.", math.floor(cond), W.JamText(cond)),
                x, y, w)
            y = y + LINE_H + 2
        end
        -- Its skin (armory_skins.lua): Sydney changes it.
        local S = PDTI.WeaponSkins
        if S and type(d.skin_id) == "string" then
            line(win, "inspect_skin", "Skin: " .. S.Label(S.Of(d)) .. " (Sydney changes it).", x, y, w)
            y = y + LINE_H + 2
        end
        y = draw_weapon_view(win, at, item, d, x, y, w)
        -- (A build is changed at home: no templates in a heist.)
        if not PDTI.InHeist() then y = draw_templates(win, at, d, x, y, w) end
    else
        y = big_picture(win, "inspect_picture", item_picture(item), x, y, w)
        local _, _, kg = P.Size(d.ptype)
        line(win, "inspect_part_type", string.format("%s, %.1f kg.", P.Tag(d.ptype), tonumber(d.weight) or kg), x, y, w)
        y = y + LINE_H
        local fits = P.FitsYours(d.part_id)
        line(win, "inspect_part_fits", #fits > 0 and ("Fits your " .. table.concat(fits, ", ") .. ".")
            or "Fits none of your weapons.", x, y, w)
        y = y + LINE_H
        line(win, "inspect_part_help", "Drag it onto a weapon, or onto its slot in the weapon's view, to fit it.",
            x, y, w, 2 * LINE_H)
        y = y + 2 * LINE_H
    end
    y = y + 4
    -- (Selling waits for home.)
    if not PDTI.InHeist() then
        local key = tostring(at.container) .. "#" .. tostring(at.instance_id)
        local price = P.SellPrice(item)
        local text
        if weapon and d.free then text = "A free weapon sells for nothing"
        elseif view.sell_armed == key then text = "Click again: sell for " .. PDTI.Ammo.Money(price)
        else text = "Sell for " .. PDTI.Ammo.Money(price) end
        button(win, "inspect_sell", text, x, y, after(function()
            if weapon and d.free then return inspect_status("a free weapon sells for nothing: throw it away instead") end
            if view.sell_armed ~= key then view.sell_armed = key return end
            view.sell_armed = nil
            -- (Sold: inspected() finds it gone and closes.)
            local _, msg = P.Sell(at.container, at.instance_id)
            inspect_status(msg)
        end), w)
        y = y + BTN_H + 4
        -- Repair (armory_wear.lua).
        local W = PDTI.Wear
        if weapon and W and not d.free and W.RepairPrice(d) > 0 then
            button(win, "inspect_repair", string.format("Repair for %s (to 100%%)", PDTI.Ammo.Money(W.RepairPrice(d))),
                x, y, after(function()
                    local _, msg = W.Repair(at.container, at.instance_id)
                    inspect_status(msg)
                end), w)
            y = y + BTN_H + 4
        end
        if weapon and PDTI.Insurance then y = draw_insurance(win, at, d, x, y, w) end
    end
    if view.inspect_status then
        line(win, "inspect_status", tostring(view.inspect_status), x, y, w, 2 * LINE_H)
        y = y + 2 * LINE_H
    end
    button(win, "inspect_close", "Close", x, y, after(function()
        view.inspect, view.sell_armed, view.inspect_status = nil, nil, nil
    end), w)
    return y + BTN_H + 8
end

-- The locker shows LOCKER_VIEW rows at once (0.51.0); the arrows and the
-- mouse wheel move it LOCKER_STEP rows.
local LOCKER_VIEW, LOCKER_STEP = 8, 2

-- Scrolls the locker by delta rows (kept in its bounds). Returns the first
-- row shown (from 0), the rows shown and the locker's rows.
function PDTI.UILockerScroll(delta)
    local total = PDTI.LOCKER.h
    local rows = math.min(LOCKER_VIEW, total)
    local top = math.floor((tonumber(view.locker_top) or 0) + (tonumber(delta) or 0))
    top = math.max(0, math.min(total - rows, top))
    view.locker_top = top
    return top, rows, total
end

-- The weapons you keep (the inventory's Locker tab, 0.37.0). Every weapon
-- is a grid item: drag it onto PRI or SEC (the left window) to take it into
-- the heist, or into the backpack or rig as a spare; Ctrl+click sends it to
-- its slot.
local function draw_locker(win, x, y, w, model)
    local A = PDTI.Armory
    label(win, "locker_grid_label", string.format("Locker  (%d weapon(s))", #A.Weapons()), x, y, w)
    y = y + LABEL_H
    y = draw_returns(win, "locker", x, y, w)
    line(win, "locker_help", "Drag a weapon onto PRI or SEC to use it; right-click it to see its slots. A failed heist loses what you bring.",
        x, y, w, 2 * LINE_H)
    y = y + 2 * LINE_H + 2
    -- (0.51.0: the locker scrolls; the wheel over it or the arrows.)
    local top, rows, total = PDTI.UILockerScroll(0)
    local bw = math.floor(BTN_W / 2)
    small_button(win, "locker_up", "Up", x, y, safe(function() PDTI.UILockerScroll(-LOCKER_STEP); redraw() end), bw)
    small_button(win, "locker_down", "Down", x + bw + BTN_GAP, y,
        safe(function() PDTI.UILockerScroll(LOCKER_STEP); redraw() end), bw)
    line(win, "locker_rows", string.format("Rows %d-%d of %d (the mouse wheel scrolls)", top + 1, top + rows, total),
        x + 2 * (bw + BTN_GAP), y + 2, w - 2 * (bw + BTN_GAP))
    y = y + ROW_H + 2
    draw_grid(win, "locker", x, y, model, top, rows)
    return y + rows * CELL_H + 4
end

-- The middle window in the menu has tabs: what you bring, the captured loot,
-- the safehouse stash and your weapons.
local draw_health -- (below: the health window, and the menu's Health tab)

-- Sydney's skins screen (0.49.0, armory_skins.lua): your weapons, then the
-- skins the one you pick takes. Pages of SKIN_ROWS.
local SKIN_ROWS = 9
local SKIN_PLACES = { hand_primary = "PRI", hand_secondary = "SEC", locker = "locker", backpack = "backpack",
    rig = "rig", rig_2 = "rig", rig_3 = "rig" }

local function skin_pager(win, key, page, pages, x, y, w)
    if pages <= 1 then return y end
    local bw = math.floor((w - 2 * BTN_GAP) / 3)
    if page > 1 then
        small_button(win, key .. "_prev", "< Prev", x, y, after(function() view[key] = page - 1 end), bw)
    end
    line(win, key .. "_at", string.format("Page %d of %d", page, pages), x + bw + BTN_GAP, y + 2, bw)
    if page < pages then
        small_button(win, key .. "_next", "Next >", x + 2 * (bw + BTN_GAP), y, after(function() view[key] = page + 1 end), bw)
    end
    return y + ROW_H + 2
end

local function page_of(key, n)
    local pages = math.max(1, math.ceil(n / SKIN_ROWS))
    local page = math.max(1, math.min(pages, tonumber(view[key]) or 1))
    view[key] = page
    return page, pages, (page - 1) * SKIN_ROWS
end

local function draw_skins(win, x, y, w)
    local S, A = PDTI.WeaponSkins, PDTI.Armory
    label(win, "skins_label", "Sydney: weapon skins", x, y, w)
    y = y + LABEL_H
    local pick = view.skin_pick
    local item = pick and PDTI.FindItem(pick.container, pick.instance_id)
    if item and item.item_id ~= A.ITEM_ID then item = nil end
    if not item then
        view.skin_pick = nil
        local list = A.Weapons()
        table.sort(list, function(a, b)
            local ha, hb = PDTI.HAND_SLOTS[a.container] ~= nil, PDTI.HAND_SLOTS[b.container] ~= nil
            if ha ~= hb then return ha end
            local na, nb = tostring(a.data.name or a.data.weapon_id), tostring(b.data.name or b.data.weapon_id)
            if na ~= nb then return na < nb end
            return (tonumber(a.data.uid) or 0) < (tonumber(b.data.uid) or 0)
        end)
        line(win, "skins_help", "Pick a weapon:", x, y, w)
        y = y + LINE_H + 2
        if #list == 0 then
            line(win, "skins_none", "You own no weapons.", x, y, w)
            y = y + LINE_H
        end
        local page, pages, first = page_of("skins_wpage", #list)
        for i = first + 1, math.min(#list, first + SKIN_ROWS) do
            local e = list[i]
            local text = string.format("%s (%s): %s", tostring(e.data.name or e.data.weapon_id),
                SKIN_PLACES[e.container] or e.container, S.Label(S.Of(e.data)))
            button(win, "skins_weapon_" .. (i - first), text, x, y, after(function()
                view.skin_pick = { container = e.container, instance_id = e.instance_id }
                view.skins_spage, view.skins_status = 1, nil
            end), w)
            y = y + BTN_H + 2
        end
        y = skin_pager(win, "skins_wpage", page, pages, x, y, w)
    else
        local d = item.data
        local name = tostring(d.name or d.weapon_id)
        line(win, "skins_weapon", name .. ": " .. S.Label(S.Of(d)), x, y, w)
        y = y + LINE_H + 2
        if type(d.skin_id) == "string" then
            button(win, "skins_remove", "Remove the skin", x, y, after(function()
                local _, msg = S.Remove(pick.container, pick.instance_id)
                view.skins_status = msg
            end), w)
            y = y + BTN_H + 2
        end
        local owned = S.Owned(d.weapon_id)
        if #owned == 0 then
            line(win, "skins_none", "You own no skins for the " .. name .. ".", x, y, w)
            y = y + LINE_H
        end
        local page, pages, first = page_of("skins_spage", #owned)
        for i = first + 1, math.min(#owned, first + SKIN_ROWS) do
            local e = owned[i]
            local worn = d.skin_id == e.id
            button(win, "skins_skin_" .. (i - first), S.Label(e) .. (worn and "  - on it" or ""), x, y, after(function()
                local _, msg = S.Apply(pick.container, pick.instance_id, e.id)
                view.skins_status = msg
            end), w)
            y = y + BTN_H + 2
        end
        y = skin_pager(win, "skins_spage", page, pages, x, y, w)
        line(win, "skins_legendary", "A legendary skin brings its own parts (free); yours come off.", x, y, w)
        y = y + LINE_H
        button(win, "skins_back", "Back to your weapons", x, y, after(function()
            view.skin_pick, view.skins_status = nil, nil
        end), w)
        y = y + BTN_H + 2
    end
    if view.skins_status then
        line(win, "skins_status", tostring(view.skins_status), x, y, w, 2 * LINE_H)
        y = y + 2 * LINE_H
    end
    button(win, "skins_close", "Close (Esc)", x, y + 2, after(function() PDTI.SetUIOpen(false) end), w)
    return y + BTN_H + 10
end

-- The menu's Health tab (0.48.0, body_lasting.lua): the parts the last heist
-- left you with, and Heal everything for $15,000.
local function draw_health_tab(win, x, y, w)
    local L = PDTI.BodyLasting
    local h = draw_health(win, x, y)
    y = y + h
    if L.Hurt() then
        button(win, "health_heal", "Heal everything (" .. PDTI.Ammo.Money(L.PRICE) .. ")", x, y, after(function()
            local _, msg = L.HealAll()
            view.heal_status = msg
        end), w)
        y = y + BTN_H + 4
    else
        line(win, "health_fine", "You are not hurt.", x, y, w)
        y = y + LINE_H
    end
    line(win, "health_lasting", "Damage stays after a heist. Dallas (safehouse) heals too.", x, y, w)
    y = y + LINE_H
    if view.heal_status then
        line(win, "health_status", tostring(view.heal_status), x, y, w)
        y = y + LINE_H
    end
    return y + 8
end

local function draw_shop(win, x, y, w, model)
    local stash = PDTI.Stash
    -- Opened through Sydney (safehouse.lua): the skins alone.
    if view.skins_mode and PDTI.WeaponSkins then return draw_skins(win, x, y, w) end
    -- Opened through Scarface (safehouse.lua): the market alone.
    if view.market_mode then
        if not stash or not stash.Enabled() or not PDTI.Market then return y end
        -- Loot (prices, contracts) or weapons (armory.lua).
        if PDTI.Armory then
            local mtabs = { { id = "loot", text = "Loot" }, { id = "weapons", text = "Weapons" } }
            local mw = math.floor((w - BTN_GAP) / 2)
            for i, tab in ipairs(mtabs) do
                small_button(win, "market_tab_" .. tab.id, tab.text, x + (i - 1) * (mw + BTN_GAP), y,
                    after(function() view.market_tab = tab.id end), mw, (view.market_tab or "loot") == tab.id)
            end
            y = y + ROW_H + 4
        end
        if view.market_tab == "weapons" and PDTI.Armory then
            y = draw_weapon_market(win, x, y, w)
        else
            y = draw_market(win, stash, x, y, w)
        end
        local s = view.cap_status
        if s then
            line(win, "market_status", tostring(s), x, y, w, 2 * LINE_H)
            y = y + 2 * LINE_H
        end
        button(win, "market_close", "Close (Esc)", x, y + 2, after(function() PDTI.SetUIOpen(false) end), w)
        return y + BTN_H + 8
    end
    if view.inspect and PDTI.Parts then
        local done = draw_inspect(win, x, y, w)
        if done then return done end
    end
    -- In a heist the middle window is the weapon view's alone.
    if PDTI.InHeist() then return y end
    if not stash or not stash.Enabled() then return draw_bring(win, x, y, w) end
    local pending = #stash.Pending()
    if view.shop_tab == nil then view.shop_tab = pending > 0 and "captured" or "bring" end
    local tabs = {
        { id = "bring", text = "Bring list" },
        { id = "captured", text = pending > 0 and ("Captured (" .. pending .. ")") or "Captured" },
        { id = "stash", text = "Stash (" .. #stash.Bags() .. ")" }
    }
    if PDTI.Armory and PDTI.Armory.Enabled() then
        tabs[#tabs + 1] = { id = "locker", text = "Locker (" .. #PDTI.Armory.Weapons() .. ")" }
    end
    local lasting = PDTI.BodyLasting
    local health_tab = lasting ~= nil and lasting.Enabled()
    if health_tab then tabs[#tabs + 1] = { id = "health", text = lasting.Hurt() and "Health (hurt)" or "Health" } end
    local tw = math.floor((w - (#tabs - 1) * BTN_GAP) / #tabs)
    for i, tab in ipairs(tabs) do
        small_button(win, "shop_tab_" .. tab.id, tab.text, x + (i - 1) * (tw + BTN_GAP), y,
            after(function() view.shop_tab = tab.id end), tw, view.shop_tab == tab.id)
    end
    y = y + ROW_H + 4
    if view.shop_tab == "captured" then return draw_captured(win, stash, x, y, w) end
    if view.shop_tab == "stash" then return draw_stash(win, stash, x, y, w) end
    if view.shop_tab == "locker" and PDTI.Armory and model then return draw_locker(win, x, y, w, model) end
    if view.shop_tab == "health" and health_tab then return draw_health_tab(win, x, y, w) end
    return draw_bring(win, x, y, w)
end
PDTI._UIDrawShop = draw_shop

-- The left window: loadout, pockets, rig, deployable, controls, weight.
-- A weapon slot (PRI / SEC, 0.37.0): the weapon in it is a grid item like
-- any other. Drag a weapon onto it from the locker, the backpack or the rig,
-- or drag it off; Ctrl+click sends it back. An empty slot gets the game's
-- free weapon. It is one cell of the grid ("cell_hand_primary_0_0" for the
-- drag), drawn as the weapon's box.
local HAND_OF = { primary = "hand_primary", secondary = "hand_secondary" }
local function draw_weapon_slot(win, entry, x, y, w, model)
    local hand = HAND_OF[entry.slot]
    local info = hand and model.containers[hand]
    local item = info and info.items[1]
    local text = string.format("%s %s\n%.1f kg", SLOT_NAMES[entry.slot], short(entry.name, 11), entry.weight or 0)
    -- Empty: no weapon there.
    local A = PDTI.Armory
    if info and not item and A and A.InUse and A.InUse() then
        text = string.format("%s empty\nno weapon", SLOT_NAMES[entry.slot])
    end
    local held = PDTI.UIGetHeld()
    local is_held = item and held and held.instance_id == item.instance_id and held.container == hand
    local base = SLOT_COLORS[entry.slot]
    -- The weapon's picture behind its text (the box is small: faint); with
    -- the names off, the picture alone, full.
    local path = item and item_picture(item)
    local piece = path and fitted(path, win:Panel(), w - 2 * PIC_MARGIN, CELL_H - GAP - 2 * PIC_MARGIN)
    local bare = piece and not PDTI.Pictures.ShowNames()
    if bare then text = "" end
    local btn = win:Button({
        name = "weapon_box_" .. entry.slot, label = DYN,
        text = text,
        position = { x, y }, w = w, size = CELL_H - GAP,
        font_size = fit_font(text, w, CELL_H - GAP, CELL_FONT),
        text_align = "center", text_vertical = "center",
        background_color = rgb(base, is_held and 1.1 or (item and 0.8 or 0.45)),
        highlight_color = rgb(base, info and 1.0 or 0.55),
        on_callback = safe(function()
            if not info then return end
            if shift_down() and not ctrl_down() and PDTI._UIInspect(hand, 0, 0) then
                -- (inspected: nothing moves)
            elseif ctrl_down() then
                PDTI.UICellQuickTransfer(hand, 0, 0)
            else
                PDTI.UICellClick(hand, 0, 0)
            end
            sync_guns()
            redraw()
        end)
    })
    fit(btn, w, CELL_H - GAP)
    if piece then
        piece.x, piece.y = piece.x + PIC_MARGIN, piece.y + PIC_MARGIN
        if not bare then piece.alpha = BOX_PIC_ALPHA end
        draw_piece(btn, path, piece)
    end
    if insured(item) then ins_mark(btn, w) end
    local cond = wear_cond(item)
    if cond then wear_bar(btn, w, CELL_H - GAP, cond) end
    if info then view.cells[#view.cells + 1] = { item = btn, container = hand, x = 0, y = 0 } end
end

-- A weapon slot the game could not name (no loadout read): from the
-- weapon in it, or the free weapon.
local function slot_entry(slot, model)
    local info = model.containers[HAND_OF[slot]]
    if not info then return nil end
    local item = info.items[1]
    if item and type(item.data) == "table" then
        return { slot = slot, name = tostring(item.data.name or item.data.weapon_id), weight = tonumber(item.data.weight) or 0 }
    end
    local A = PDTI.Armory
    local free = A and A.FALLBACK[slot == "primary" and "primaries" or "secondaries"]
    return { slot = slot, name = free and A.Name(free.weapon_id) or "-", weight = 0 }
end

local function draw_left(win, model)
    local x = PAD
    label(win, "title", "Tactical Inventory", x, 6, INNER_W)
    local y = 6 + LABEL_H + 2

    -- The loadout: weapons, throwables and armour have their own slots.
    -- The weapons: a box each (name and weight) with the weapon's magazine
    -- slot next to it, side by side.
    local col_w = math.floor((INNER_W - 8) / 2)
    local weapons = 0
    local by_slot = {}
    for _, entry in ipairs(model.loadout or {}) do by_slot[entry.slot] = entry end
    for _, slot in ipairs({ "primary", "secondary" }) do
        local gun = "gun_" .. slot
        local entry = by_slot[slot] or slot_entry(slot, model)
        if entry and model.containers[gun] then
            local wx = x + weapons * (col_w + 8)
            weapons = weapons + 1
            local box_w = col_w - 2 * CELL_W - 2
            draw_weapon_slot(win, entry, wx, y, box_w, model)
            draw_grid(win, gun, wx + box_w + 2, y, model)
        end
    end
    if weapons > 0 then y = y + CELL_H + 2 end
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
    local pouch_info = model.containers and model.containers.pouch
    if pouch_info and (tonumber(pouch_info.width) or 0) > 0 then
        grids[#grids + 1] = { container = "pouch", title = "Ammo pouch" }
    end
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
        g.w, g.h = info.width * CELL_W, info.height * CELL_H
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
        -- Only the kinds you carry (there are eleven kinds).
        local n = 0
        for _, entry in ipairs(model.deployables or {}) do
            if (entry.count or 0) > 0 or entry.item_id == model.deployable then
            n = n + 1
            local bx, by = list_pos(n, x, y)
            list_button(win, "deployable_" .. entry.item_id,
                string.format("%s x%d", short(entry.name, 14), entry.count or 0), bx, by,
                CATEGORY_COLORS.utility, entry.item_id == model.deployable,
                after(function() PDTI.UISelectDeployableById(entry.item_id) end))
            end
        end
        n = n + 1
        local cx, cy = list_pos(n, x, y)
        list_button(win, "deployable_clear", "First found", cx, cy, { 0.3, 0.3, 0.34 }, manual == nil,
            after(function() PDTI.UIClearDeployable() end))
        y = y + math.ceil(n / 2) * LIST_H + 6
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
    -- The rig has no weight cap: only its weight.
    line(win, "weights_parts", string.format("Pockets %.1f/%g  Rig %.1f  Pack %.1f/%g",
        pk.weight, pk.weight_limit, rg.weight, bp.weight, bp.weight_limit), x, y)
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

-- The right window: the backpack and the test spawner.
local function draw_right(win, model)
    local x = PAD
    local bp = model.containers.backpack
    local y = 6
    -- Clover's loot slots, next to the backpack.
    local slots = model.containers.loot_slot
    local has_slots = slots and (tonumber(slots.width) or 0) > 0
    local sx = x + bp.width * CELL_W + 12
    label(win, "backpack_label", "Backpack: " .. tostring(model.equipment.backpack_definition
        and model.equipment.backpack_definition.name or model.equipment.backpack), x, y,
        has_slots and (sx - x - 4) or INNER_W)
    if has_slots then label(win, "loot_slot_label", "Loot", sx, y, slots.width * CELL_W) end
    y = y + LABEL_H + 2
    draw_grid(win, "backpack", x, y, model)
    local grid_h = bp.height * CELL_H
    if has_slots then
        draw_grid(win, "loot_slot", sx, y, model)
        grid_h = math.max(grid_h, slots.height * CELL_H)
    end
    y = y + grid_h + 6
    local function bx(i) return x + (i - 1) * (BTN_W + BTN_GAP) end
    button(win, "btn_arrange_pack", "Arrange pack", bx(1), y, after(function() arrange("backpack") end))
    y = y + BTN_H + 8

    -- In the menu: what you bring takes the place of the ammunition and the
    -- test spawner.
    -- (It has its own window in the middle; without one it is drawn here.)
    if not PDTI.InHeist() then
        if not view.shop_drawn then y = draw_bring(win, x, y, INNER_W) end
        return y + PAD
    end

    -- The test spawner: the deployables and the ammunition of both guns.
    label(win, "supplies_label", "Spawn for testing", x, y, INNER_W)
    y = y + LABEL_H
    -- The deployables in three columns (there are eleven of them).
    local n = 0
    local third_w = math.floor((INNER_W - 2 * BTN_GAP) / 3)
    for _, id in ipairs(sorted_ids(model.item_definitions)) do
        local def = model.item_definitions[id]
        if def.deployable and not def.ammo_managed and not def.no_supply then
            local col, row = n % 3, math.floor(n / 3)
            n = n + 1
            list_button(win, "supply_" .. id, short(def.name or id, 16), x + col * (third_w + BTN_GAP),
                y + row * LIST_H, CATEGORY_COLORS[def.category] or { 0.3, 0.3, 0.3 }, false,
                after(function() PDTI.UIAddSupply(id) end), third_w)
        end
    end
    y = y + math.ceil(n / 3) * LIST_H
    n = 0
    -- The ammunition of the spawn buttons: a category (AR/SMG, Shotgun, LMG)
    -- and one of its bullets, one row per category.
    local Ammo = PDTI.Ammo
    local cat = view.spawn_category or "rifle"
    local bullet = view.spawn_bullet or "standard"
    local tag = " " .. Ammo.CATEGORY_NAMES[cat]
    if bullet ~= "standard" then tag = tag .. " " .. Ammo.BulletShort(bullet, cat) end
    local spawns = {
        { "spawn_loose_primary", "PRI loose" .. tag, "primary", "DevSpawnLoose" },
        { "spawn_mag_primary", "PRI magazine" .. tag, "primary", "DevSpawnMagazine" },
        { "spawn_loose_secondary", "SEC loose" .. tag, "secondary", "DevSpawnLoose" },
        { "spawn_mag_secondary", "SEC magazine" .. tag, "secondary", "DevSpawnMagazine" }
    }
    if n % 2 == 1 then n = n + 1 end
    local by = y + math.ceil(n / 2) * LIST_H
    local lw = math.floor(SMALL_W * 2.2)
    local bw = math.floor(SMALL_W * 1.6)
    local per_row = math.max(1, math.floor((INNER_W - lw - 2) / (bw + 2)))
    for _, c in ipairs({ "rifle", "shell", "lmg" }) do
        line(win, "spawn_cat_" .. c, Ammo.CATEGORY_NAMES[c], x, by + 2, lw)
        local bx = x + lw + 2
        for i, id in ipairs(Ammo.CATEGORY_BULLETS[c]) do
            if i > 1 and (i - 1) % per_row == 0 then
                by = by + LIST_H
                bx = x + lw + 2
                n = n + 2
            end
            small_button(win, "spawn_bullet_" .. c .. "_" .. id, Ammo.BulletShort(id, c), bx, by,
                after(function()
                    view.spawn_category = c
                    view.spawn_bullet = id
                end), bw, cat == c and bullet == id)
            bx = bx + bw + 2
        end
        by = by + LIST_H
        n = n + 2
    end
    for _, spawn in ipairs(spawns) do
        local name, text, slot, fn = spawn[1], spawn[2], spawn[3], spawn[4]
        n = n + 1
        local px, py = list_pos(n, x, y)
        list_button(win, name, text, px, py, SLOT_COLORS[slot], false, after(function()
            local ammo = PDTI.Ammo
            if not ammo or not ammo[fn] then return end
            -- Ctrl+click on a loose button: a full stack (100 rounds).
            local rounds = nil
            if fn == "DevSpawnLoose" and ctrl_down() then rounds = ammo.MAX_STACK end
            -- The weapon of the slot must be of the chosen category.
            local wep = ammo.WeaponInSlot and ammo.WeaponInSlot(slot)
            local winfo = wep and ammo.Identify(wep)
            local wcat = winfo and ammo.AmmoCategory(winfo)
            if wcat and wcat ~= cat then
                PDTI.UISetStatus(string.format("%s takes %s ammunition, not %s", SLOT_TAGS[slot],
                    ammo.CATEGORY_NAMES[wcat], ammo.CATEGORY_NAMES[cat]))
                return
            end
            local ok, result = ammo[fn](slot, bullet ~= "standard" and bullet or nil, rounds)
            if ok then
                PDTI.UISetStatus(string.format("Added %s (%s round(s))", text, tostring(result)))
            else
                PDTI.UISetStatus(tostring(result))
            end
        end))
    end
    y = y + math.ceil(n / 2) * LIST_H
    return y + PAD
end

-- The health window (in a heist): every body part as a box in the shape of
-- a body, coloured by what it has left (green when full, dark green above
-- 75%, yellow above 50%, orange above 25%, red, black at 0),
-- with its HP and its maximum, then what the black parts do.
-- The figure is drawn for a width of 300 and scaled to HEALTH_W.
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

-- (Not while the weapon view has the middle of the screen.)
local function health_shown()
    local body = PDTI.Body
    return body ~= nil and body.Enabled and body.Enabled() and PDTI.InHeist() and not view.inspect
end

-- (x0, y0: where in the window; the health window's corner by default.
-- Returns the height drawn.)
draw_health = function(win, x0, y0)
    local body = PDTI.Body
    -- The real max health (skills and perks) even before the first hit.
    if body.AttachPlayer then pcall(body.AttachPlayer) end
    local x, y = x0 or PAD, y0 or 6
    local top = y0 or 0
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
    local k = (HEALTH_W - 2 * PAD) / 280
    local function sc(v) return math.floor(v * k + 0.5) end
    for _, part in ipairs(PART_BOXES) do
        local id = part[1]
        local frac = body.Frac(id)
        local color = frac <= 0 and BLACK_PART or body.PartColor(frac)
        local text = string.format("%s\n%d / %d", part[2], body.ShownHP(id), body.ShownMax(id))
        local w, h = sc(part[5]), sc(part[6])
        local box = win:Button({
            name = "health_part_" .. id, label = DYN, text = text,
            position = { x + sc(part[3]), y + sc(part[4]) }, w = w, size = h,
            font_size = fit_font(text, w, h, BTN_FONT), text_align = "center", text_vertical = "center",
            background_color = rgb(color), highlight_color = rgb(color)
        })
        fit(box, w, h)
    end
    y = y + sc(226)
    local effects = body.EffectLines()
    if #effects == 0 then effects = { "No black parts" } end
    for i, text in ipairs(effects) do
        line(win, "health_effect_" .. i, text, x, y, HEALTH_W - 2 * PAD)
        y = y + LINE_H
    end
    local armour = PDTI.Armour and PDTI.Armour.StatusLine and PDTI.Armour.StatusLine()
    if armour then
        -- The armour line is long: it wraps on two lines.
        line(win, "health_armour", armour, x, y, HEALTH_W - 2 * PAD, 2 * LINE_H)
        y = y + 2 * LINE_H
    end
    y = y + 4
    line(win, "health_hint_fak", "First aid kit: heals parts above 0", x, y, HEALTH_W - 2 * PAD)
    y = y + LINE_H
    line(win, "health_hint_medic", "Medic bag: heals every part, black too", x, y, HEALTH_W - 2 * PAD)
    y = y + LINE_H
    body.ui_revision = body.state and body.state.revision
    return y + PAD - top
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

-- In the menu: what you bring, in the middle of the screen (the health
-- window's place in a heist). Made the first time it is needed.
local function shop_window()
    if view.shop then return view.shop end
    local ok, win = pcall(function()
        return view.menu:Menu({
            name = "pdti_shop",
            position = "Center",
            scrollbar = false,
            auto_height = false,
            auto_align = false,
            background_color = Color(0.08, 0.08, 0.09),
            background_alpha = 0.92,
            size = 14
        })
    end)
    if ok and win then view.shop = win else log("no window for the shopping list: " .. tostring(win)) end
    return view.shop
end

-- The height there is for a window (the GUI is 720 high).
local function screen_height()
    local ok, h = pcall(function() return view.menu._panel:h() end)
    if ok and type(h) == "number" and h > 100 then return h end
    return 720
end
PDTI._UIScreenHeight = screen_height

local function align(win)
    -- auto_align is off (hundreds of items would re-align on every add), so
    -- the items only get their positions when we align manually.
    local ok, err = pcall(function() win:AlignItems(true) end)
    if not ok then log("AlignItems failed: " .. tostring(err)) end
end

-- MenuUI takes a click only on the item it highlighted, and it highlights
-- only when the mouse moves. A redraw makes new items, so the button under a
-- still mouse took no second click. On the next update the mouse "moves" to
-- where it is, which highlights the new item under it.
local function rehighlight()
    local menu = view.menu
    if not menu or not view.open or type(menu.RunCallbackNextUpdate) ~= "function" then return end
    pcall(function()
        menu:RunCallbackNextUpdate(function()
            if not view.open then return end
            pcall(function()
                local x, y = managers.mouse_pointer._mouse:world_position()
                menu:MouseMoved(nil, x, y)
            end)
        end)
    end)
end
PDTI._UIRehighlight = rehighlight

function redraw()
    local left, right = view.left, view.right
    if not left or not right or not view.open then return end
    -- In the menu the game's weapons follow your hands (armory.lua).
    local armory = PDTI.Armory
    if armory and armory.SyncEquipped and not PDTI.InHeist() then pcall(armory.SyncEquipped) end
    -- With a player (a heist, the safehouse): the weapons in hand follow the slots.
    if armory and armory.ApplyHands then pcall(armory.ApplyHands) end
    local model = PDTI.GetInventoryViewModel()
    forget_dead_pics()
    left:ClearItems(DYN)
    right:ClearItems(DYN)
    view.cells = {}
    view.slots = {}
    view.preview = {}
    local in_heist = PDTI.InHeist()
    -- In the menu what you bring has its own window in the middle; in a
    -- heist the weapon view (0.39.0) has it while it is open.
    local middle = (not in_heist) or view.inspect ~= nil
    local shop = middle and shop_window() or view.shop
    if shop then shop:ClearItems(DYN) end
    view.shop_drawn = middle and shop ~= nil
    view.parts_drawn = false
    local tallest = 0
    if shop then
        if view.shop_drawn then
            shop:SetSize(SHOP_W, 600)
            local sh = draw_shop(shop, PAD, 6, SHOP_W - 2 * PAD, model) + PAD
            -- The parts for sale go when they are not shown.
            if not view.parts_drawn and view.parts_list then
                pcall(function() shop:ClearItems(PARTS) end)
                view.parts_list, view.parts_sig = nil, nil
            end
            shop:SetSize(SHOP_W, sh)
            align(shop)
            tallest = sh
        else
            shop:SetSize(1, 1)
        end
    end
    if view.skins_mode then
        -- Sydney's skins alone: the side windows empty.
        left:SetSize(1, 1)
        right:SetSize(1, 1)
    elseif view.market_mode then
        -- The market alone: the prices on the left, the right window empty.
        pcall(function() left:ClearItems(GRAPH) end)
        local weapons = view.market_tab == "weapons" and PDTI.Armory ~= nil
        -- The other tab's list goes.
        if weapons and view.price_list then
            pcall(function() left:ClearItems(PRICES) end)
            view.price_list, view.price_sig = nil, nil
        elseif not weapons and view.wprice_list then
            pcall(function() left:ClearItems(WPRICES) end)
            view.wprice_list, view.wprice_sig = nil, nil
        end
        if PDTI.Market then
            left:SetSize(WIN_W, 600)
            local lh = weapons and draw_weapon_prices(left) or draw_prices(left)
            left:SetSize(WIN_W, lh)
            align(left)
            tallest = math.max(tallest, lh)
        else
            left:SetSize(1, 1)
        end
        right:SetSize(1, 1)
    else
    -- Not the market: its lists and its price graph go.
    pcall(function() left:ClearItems(GRAPH) end)
    if view.price_list then
        pcall(function() left:ClearItems(PRICES) end)
        view.price_list, view.price_sig = nil, nil
    end
    if view.wprice_list then
        pcall(function() left:ClearItems(WPRICES) end)
        view.wprice_list, view.wprice_sig = nil, nil
    end
    -- The backpack decides the right window's width (the heavy pack is wide).
    local bp_w = model.containers.backpack.width * CELL_W + 2 * PAD
    left:SetSize(WIN_W, 600)
    right:SetSize(math.max(WIN_W, bp_w), 600)
    local lh = draw_left(left, model)
    local rh = draw_right(right, model)
    left:SetSize(WIN_W, lh)
    right:SetSize(math.max(WIN_W, bp_w), rh)
    align(left)
    align(right)
    tallest = math.max(tallest, lh, rh)
    end
    local health = health_shown() and health_window() or view.health
    if health then
        health:ClearItems(DYN)
        if health_shown() then
            health:SetSize(HEALTH_W, 600)
            local hh = draw_health(health)
            health:SetSize(HEALTH_W, hh)
            align(health)
        else
            health:SetSize(1, 1)
        end
    end
    -- A window taller than the screen is cut off: everything is drawn
    -- again, smaller (until the screen is opened again). Sizes are rounded,
    -- so it may take a second or third try.
    local avail = screen_height()
    view.refits = view.refits or 0
    if tallest > avail and view.refits < 3 and UI_SCALE > 0.6 then
        local scale = math.max(0.6, math.floor(UI_SCALE * (avail - 8) / tallest * 100) / 100)
        if scale >= UI_SCALE then scale = math.max(0.6, UI_SCALE - 0.02) end
        log(string.format("a window is %d high, the screen %d: scale %.2f", tallest, avail, scale))
        apply_scale(scale)
        view.refits = view.refits + 1
        local ok, err = pcall(redraw)
        view.refits = view.refits - 1
        if not ok then log("redraw failed: " .. tostring(err)) end
        return
    end
    rehighlight()
end

------------------------------------------------------------ drag and drop

local function inside(item, x, y)
    local ok, result = pcall(function() return item:MouseInside(x, y) end)
    return ok and result and true or false
end

-- What is under the mouse: a cell ({ container, x, y }), "window" (the
-- inventory, not a cell) or "outside".
-- A slot of the weapon view (0.38.2) is { mod_slot = { container,
-- instance_id, ptype, part_id } }.
function PDTI._UIHit(x, y)
    for _, cell in ipairs(view.cells) do
        if inside(cell.item, x, y) then return { container = cell.container, x = cell.x, y = cell.y } end
    end
    for _, entry in ipairs(view.slots) do
        if inside(entry.item, x, y) then return { mod_slot = entry.slot } end
    end
    -- (The middle window is the inventory too: what is let go there stays.)
    if (view.left and inside(view.left, x, y)) or (view.right and inside(view.right, x, y))
        or (view.shop_drawn and view.shop and inside(view.shop, x, y)) then
        return "window"
    end
    return "outside"
end

-- The weapon view's slot i as the mouse finds it (for the tests).
function PDTI._UISlotHit(i)
    local entry = view.slots[i]
    return entry and { mod_slot = entry.slot } or nil
end

local function is_left(button)
    local ids = rawget(_G, "Idstring")
    if not ids or button == nil then return true end
    local ok, left = pcall(ids, "0")
    return not ok or button == left
end

-- The right mouse button (the game's "1").
-- The mouse wheel: -1 up, 1 down, nil for any other button.
local function wheel_dir(button)
    local ok, up, down = pcall(function()
        local ids = rawget(_G, "Idstring")
        return ids("mouse wheel up"), ids("mouse wheel down")
    end)
    if ok and button == up then return -1 end
    if ok and button == down then return 1 end
end

local function is_right(button)
    local ids = rawget(_G, "Idstring")
    if not ids or button == nil then return false end
    local ok, right = pcall(ids, "1")
    return ok and button == right
end

local function clear_preview()
    for _, entry in ipairs(view.preview) do
        pcall(function() entry.panel:remove(entry.rect) end)
    end
    view.preview = {}
end

-- A part dragged (0.44.0): every weapon that takes it is marked green, a
-- lighter green under the cells it would take.
local FIT_MARK_ALPHA = 0.3
local function show_fit_marks()
    local marks = PDTI.UIFitWeapons and PDTI.UIFitWeapons()
    if not marks then return 0 end
    local maps, n = {}, 0
    for _, cell in ipairs(view.cells) do
        local wanted = marks[cell.container]
        if wanted then
            if maps[cell.container] == nil then maps[cell.container] = PDTI.GetOccupancyMap(cell.container) or false end
            local map = maps[cell.container]
            local row = map and map.cells[cell.y + 1]
            local id = row and row[cell.x + 1]
            if id and wanted[id] then
                pcall(function()
                    local panel = cell.item:Panel()
                    local rect = panel:rect({ name = "pdti_fit_mark", w = panel:w(), h = panel:h(),
                        color = Color(0.25, 0.85, 0.35), alpha = FIT_MARK_ALPHA, layer = 49 })
                    view.preview[#view.preview + 1] = { panel = panel, rect = rect }
                    n = n + 1
                end)
            end
        end
    end
    return n
end

-- Tints the cells the dragged item would take: green when it fits there,
-- red when it does not.
local function show_preview(hit)
    clear_preview()
    view.last_preview = nil
    pcall(show_fit_marks)
    if type(hit) ~= "table" then return end
    local slot = hit.mod_slot
    local p
    if slot then p = PDTI.UISlotPreview(slot) else p = PDTI.UIDragPreview(hit.container, hit.x, hit.y) end
    view.last_preview = p
    if not p then return end
    local color = p.valid and Color(0.25, 0.85, 0.35) or Color(0.9, 0.25, 0.2)
    local function tint(item)
        pcall(function()
            local panel = item:Panel()
            local rect = panel:rect({ name = "pdti_preview", w = panel:w(), h = panel:h(),
                color = color, alpha = 0.55, layer = 50 })
            view.preview[#view.preview + 1] = { panel = panel, rect = rect }
        end)
    end
    -- A part over a slot: that slot lights up.
    if slot then
        for _, entry in ipairs(view.slots) do
            if entry.slot == slot then tint(entry.item) end
        end
        return
    end
    for _, cell in ipairs(view.cells) do
        if cell.container == p.container and cell.x >= p.x and cell.x < p.x + p.w
            and cell.y >= p.y and cell.y < p.y + p.h then
            tint(cell.item)
        end
    end
end
PDTI._UIShowPreview = show_preview

function PDTI._UIMousePressed(button, x, y)
    if not view.open then return nil end
    -- The mouse wheel over the locker scrolls it (also while dragging).
    local wheel = wheel_dir(button)
    if wheel then
        local hit = PDTI._UIHit(x, y)
        if type(hit) ~= "table" or hit.container ~= "locker" then return nil end
        PDTI.UILockerScroll(wheel * LOCKER_STEP)
        redraw()
        -- (A weapon being dragged: its preview under the mouse again.)
        if PDTI.UIIsDragging() then show_preview(PDTI._UIHit(x, y)) end
        return false
    end
    -- The right button on a weapon (or a part): the weapon view (Inspect).
    if is_right(button) then
        if PDTI.UIIsDragging() then return nil end
        local hit = PDTI._UIHit(x, y)
        if type(hit) ~= "table" then return nil end
        local opened = false
        local ok = pcall(function()
            opened = PDTI._UIInspect(hit.container, hit.x, hit.y) == true
            if opened then redraw() end
        end)
        if not ok then log("right press failed") end
        if opened then return false end
        return nil
    end
    if not is_left(button) then return nil end
    local hit = PDTI._UIHit(x, y)
    if type(hit) ~= "table" then return nil end
    -- A weapon's slot: Ctrl takes its part off, a press drags it out.
    if hit.mod_slot then
        local ok = pcall(function()
            if ctrl_down() then
                PDTI.UISlotTakeOff(hit.mod_slot)
            else
                PDTI.UISlotDragStart(hit.mod_slot)
            end
            view.inspect_status = PDTI.UIGetStatus()
            sync_guns()
            redraw()
        end)
        if not ok then log("slot press failed") end
        return false
    end
    local ok = pcall(function()
        if shift_down() and not ctrl_down() and PDTI._UIInspect(hit.container, hit.x, hit.y) then
            -- Inspected (the middle window): nothing is picked up.
        elseif ctrl_down() then
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
    -- What a slot does (a part out of it, or onto it) the weapon view says.
    local slot_action = PDTI.UIGetSlotDrag() ~= nil or (type(hit) == "table" and hit.mod_slot ~= nil)
    local ok, err = pcall(PDTI.UIDragDrop, hit)
    if not ok then log("drop failed: " .. tostring(err)) end
    if slot_action and view.inspect then view.inspect_status = PDTI.UIGetStatus() end
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

------------------------------------------------- captured loot on the end screen

-- After a won job the end screen shows the captured bags in a window of its
-- own and waits (stash.lua) until each one is stashed or sold.
local cap = { menu = nil, win = nil, open = false, triggers = {} }

-- Keys as well as buttons (if the mouse does not reach the window, the end
-- screen must not be stuck): S stashes all that fits, X sells all now.
local function capture_keys(on)
    local input = BeardLib and BeardLib.Utils and BeardLib.Utils.Input
    if not input then return end
    if not on then
        for _, t in ipairs(cap.triggers) do pcall(function() input:RemoveTrigger(t) end) end
        cap.triggers = {}
        return
    end
    if #cap.triggers > 0 then return end
    local function add(key, fn)
        local ok, t = pcall(function() return input:Trigger(key, fn) end)
        if ok and t then cap.triggers[#cap.triggers + 1] = t end
    end
    local stash = PDTI.Stash
    add("s", stash_after(function()
        if not cap.open then return end
        local left = stash.KeepAll()
        set_stash_status(left > 0 and (left .. " bag(s) did not fit: the safehouse stash is full") or nil)
    end))
    add("x", stash_after(function()
        if not cap.open then return end
        stash.SellAllNow()
        set_stash_status(nil)
    end))
end
PDTI._CaptureTriggers = function() return cap.triggers end

-- true when the window is there, "wait" while BeardLib still makes it.
local function capture_build()
    if cap.menu then return cap.win ~= nil or "wait" end
    if not PDTI.IsUIAvailable() then return false end
    local ok, err = pcall(function()
        cap.menu = MenuUI:new({
            name = "PDTI_Capture",
            layer = 1200,
            enabled = false,
            create_items = function(menu)
                cap.win = menu:Menu({
                    name = "pdti_capture",
                    position = "Center",
                    scrollbar = false,
                    auto_height = false,
                    auto_align = false,
                    background_color = Color(0.08, 0.08, 0.09),
                    background_alpha = 0.95,
                    size = 14
                })
            end
        })
    end)
    if not ok then
        cap.menu, cap.win = nil, nil
        log("could not create the captured loot window: " .. tostring(err))
        return false
    end
    return cap.win ~= nil or "wait"
end

local function draw_capture_window(win, stash)
    local w = SHOP_W - 2 * PAD
    win:SetSize(SHOP_W, 600)
    local y = draw_captured(win, stash, PAD, 6, w)
    line(win, "cap_space", string.format("Stash: %d of %d places used. Decide for every bag to continue (S: stash all, X: sell all).",
        math.ceil(stash.CellsUsed() / stash.BAG_CELLS), math.floor(stash.Capacity() / stash.BAG_CELLS)), PAD, y, w)
    y = y + LINE_H
    if view.cap_status then
        line(win, "cap_status", tostring(view.cap_status), PAD, y, w, 2 * LINE_H)
        y = y + 2 * LINE_H
    end
    return y + PAD
end

function redraw_capture()
    if not cap.open or not cap.win then return end
    local stash = PDTI.Stash
    if not stash or #stash.Pending() == 0 then
        PDTI.SetCaptureOpen(false)
        return
    end
    cap.win:ClearItems(DYN)
    local h = draw_capture_window(cap.win, stash)
    -- Many bags: drawn smaller until the window fits the screen.
    local tries = 0
    while h > screen_height() - 8 and UI_SCALE > 0.6 and tries < 3 do
        apply_scale(math.max(0.6, math.floor(UI_SCALE * (screen_height() - 8) / h * 100) / 100))
        cap.win:ClearItems(DYN)
        h = draw_capture_window(cap.win, stash)
        tries = tries + 1
    end
    cap.win:SetSize(SHOP_W, h)
    align(cap.win)
end
PDTI._CaptureRedraw = function() if redraw_capture then redraw_capture() end end

function PDTI.IsCaptureOpen() return cap.open end
PDTI._CaptureView = cap

function PDTI.SetCaptureOpen(open)
    open = open == true
    if open == cap.open then return true end
    if open then
        local built = capture_build()
        if built ~= true then return built end
        apply_scale(setting_scale())
        cap.open = true
        view.cap_status = nil
        local ok, err = pcall(function() cap.menu:Enable() end)
        if not ok then
            cap.open = false
            log("could not show the captured loot window: " .. tostring(err))
            return false
        end
        capture_keys(true)
        redraw_capture()
        log("captured loot window open")
    else
        cap.open = false
        view.cap_status = nil
        capture_keys(false)
        if cap.menu then pcall(function() cap.menu:Disable() end) end
        log("captured loot window closed")
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

-- Every frame while the screen is open: something else (a dialog that just
-- closed, e.g. Scarface's room menu that opened the market) may have turned
-- the controls back on; they go off again, and are on when the screen
-- closes.
function PDTI.UIKeepInputBlocked()
    if not view.open then return false end
    if not view.input_block then
        block_game_input()
        return view.input_block ~= nil
    end
    local block = view.input_block
    local ok, on = pcall(function() return block.controller:enabled() end)
    if ok and on then
        block.was_enabled = true
        pcall(function() block.controller:set_enabled(false) end)
        log("game input was turned on by something else: off again while the screen is open")
        return true
    end
    return false
end

-- Tests: the block as it is, or a fake one.
PDTI._UIInputBlock = function(set) if set ~= nil then view.input_block = set or nil end return view.input_block end

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
        -- The ammo pouch without its skill: what is in it moves out.
        if PDTI.AmmoSkills and PDTI.AmmoSkills.TidyPouch then pcall(PDTI.AmmoSkills.TidyPouch) end
        if PDTI.GhostSkills and PDTI.GhostSkills.Tidy then pcall(PDTI.GhostSkills.Tidy) end
        if not build() then return false end
        if not view.left or not view.right then
            log("window is not ready yet (MenuUI is still initializing); try again")
            return false
        end
        view.open = true
        apply_scale(setting_scale())
        -- The current profile's inventory; in the menu the plan follows the
        -- weapons you have now.
        if PDTI.OnUIOpen then
            local ok, err = pcall(PDTI.OnUIOpen)
            if not ok then log("opening: " .. tostring(err)) end
        end
        PDTI.SetUIVisible(true)
        log("opening inventory screen")
        -- In the safehouse: where you stand goes to the log (for the spots).
        if PDTI.Safehouse and PDTI.Safehouse.Probe then pcall(PDTI.Safehouse.Probe) end
        view.menu:Enable()
        block_game_input()
        add_keys()
        -- The deployable key has to work inside the screen as well, and the
        -- screen can be opened in the menu where the game hook never runs.
        if PDTI.Deployables then pcall(PDTI.Deployables.EnsureKeyTrigger) end
        redraw()
    else
        view.open = false
        view.market_mode = false
        view.skins_mode, view.skin_pick, view.skins_status = false, nil, nil
        view.skins_wpage, view.skins_spage = nil, nil
        view.market_pick = nil
        if view.parts_list and view.shop then pcall(function() view.shop:ClearItems(PARTS) end) end
        view.parts_list, view.parts_sig, view.part_pick = nil, nil, nil
        view.inspect, view.sell_armed, view.inspect_status = nil, nil, nil
        if view.price_list and view.left then pcall(function() view.left:ClearItems(PRICES) end) end
        view.price_list, view.price_sig = nil, nil
        view.cap_status = nil
        view.shop_tab = nil -- the next opening shows the captured loot first
        PDTI.UIResetInteraction() -- closing never changes inventory state
        view.redraw_soon = nil
        -- The pictures go, then their textures back to the game.
        remove_pics()
        if PDTI.Pictures then pcall(PDTI.Pictures.ReleaseAll) end
        PDTI.SetUIVisible(false)
        remove_keys()
        restore_game_input()
        if view.menu then view.menu:Disable() end
        -- The weight costs concealment: the menu's detection meter follows.
        if PDTI.Rules and PDTI.Rules.RefreshMenuDetection then pcall(PDTI.Rules.RefreshMenuDetection) end
    end
    return true
end

function PDTI.RedrawUI()
    if view.open then redraw() end
end

-- Drawn again on MenuUI's next update (pictures came: many come at once, one
-- redraw draws them all). Not while something is dragged (that would lose
-- the drag's preview; the drop draws it again).
function PDTI.UIRedrawSoon()
    local menu = view.menu
    if not view.open or view.redraw_soon then return false end
    if not menu or type(menu.RunCallbackNextUpdate) ~= "function" then
        if not PDTI.UIIsDragging() then redraw() end
        return true
    end
    view.redraw_soon = true
    local ok = pcall(function()
        menu:RunCallbackNextUpdate(function()
            view.redraw_soon = nil
            if view.open and not PDTI.UIIsDragging() then redraw() end
        end)
    end)
    if not ok then view.redraw_soon = nil end
    return ok
end

-- The market (Scarface in the safehouse): the screen opens with the market
-- alone in it. Returns true when it is open.
function PDTI.OpenMarket()
    if not (PDTI.Market and PDTI.Market.Enabled()) then return false end
    if view.open then PDTI.SetUIOpen(false) end
    view.market_mode = true
    local ok = PDTI.SetUIOpen(true) == true and view.open
    if not ok then view.market_mode = false end
    return ok
end
function PDTI.IsMarketOpen() return view.open and view.market_mode == true end

-- Sydney's weapon skins (safehouse.lua): the screen opens with them alone.
function PDTI.OpenSkins()
    local S = PDTI.WeaponSkins
    if not (S and S.Enabled()) then return false end
    if view.open then PDTI.SetUIOpen(false) end
    view.skins_mode = true
    local ok = PDTI.SetUIOpen(true) == true and view.open
    if not ok then view.skins_mode = false end
    return ok
end

function PDTI.ToggleUI()
    return PDTI.SetUIOpen(not view.open)
end

function PDTI.IsUIOpen()
    return view.open
end
