-- The magazine panel of the HUD.
--
-- A port of the InsurgencySandstormStyleReload mod's panel, but the numbers
-- come from the inventory: the boxes are the magazines in the rig and the
-- pockets, the first box is the magazine in the gun, and LOOSE is the number
-- of loose rounds you carry.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Ammo then return end

local Ammo = PDTI.Ammo

local BOX_COLOR = Color(0.30, 0.30, 0.30, 0.9)
local FILL_COLOR = Color(0.62, 0.62, 0.62, 0.95)
local BG_COLOR = Color(0, 0, 0, 0.35)
local LINE_COLOR = Color(1, 1, 1, 1)
-- The mark under what the next reload loads (or the gun's magazine, when R
-- takes it out).
local CHOICE_COLOR = Color(1, 0.78, 0.2, 1)
local FONT = "fonts/font_medium_mf"

local BOX_W = 20
local BOX_H = 28
local BOX_GAP = 4

local panel = nil

local log = PDTI.Logger("PDTI AMMO")

local function L(id, fallback)
    local loc = managers and managers.localization
    if loc and loc.exists and loc:exists(id) then
        return loc:text(id)
    end
    return fallback
end

local function collect_rows()
    local wep = Ammo.EquippedBase()
    if not wep or Ammo.SkipWeapon(wep) then return nil end

    local info = Ammo.Identify(wep)
    if not info then return nil end

    local queue = {}
    local choice = not info.loose_fed and Ammo.CurrentChoice and Ammo.CurrentChoice(wep) or nil
    local chosen = choice == "gun" and "gun" or nil
    for _, entry in ipairs(Ammo.Magazines(info.key)) do
        queue[#queue + 1] = { rounds = entry.rounds, capacity = entry.capacity, size = entry.size,
            bullet = entry.bullet, load = entry.load }
        if choice and entry.instance_id == choice then chosen = #queue end
    end

    if info.loose_fed then
        -- No magazines: one box for what is loaded, and the loose rounds.
        -- A shotgun tube shows its shells and the kind the reload loads next.
        local installed = { rounds = wep:get_ammo_remaining_in_clip() }
        local spec = nil
        if info.typed then
            local loaded = Ammo.LoadedSpec(wep)
            installed.load = loaded and loaded.load or nil
            local next_shell = Ammo.NextShell and Ammo.NextShell(wep)
            spec = next_shell and ("+" .. Ammo.BulletShort(next_shell, info.family)) or nil
        end
        return {
            queue = {},
            caliber = info.caliber,
            capacity = math.max(1, info.capacity),
            installed = installed,
            no_mag = false,
            loose_fed = true,
            spec = spec,
            loose = Ammo.LooseOfKey(info.key)
        }
    end

    local installed = wep._issr_mag_installed or { rounds = 0 }
    installed.rounds = math.max(0, wep:get_ammo_remaining_in_clip() - Ammo.ChamberOf(wep))

    -- Akimbo: a box for the magazine of each gun.
    local pair = info.akimbo and Ammo.AkimboPair(wep) or nil

    -- An assault rifle or SMG: the loaded magazine's size and bullets.
    local loaded = info.typed and Ammo.LoadedSpec(wep) or nil
    local capacity = loaded and loaded.capacity or info.capacity
    if loaded then
        installed.capacity = capacity
        installed.load = loaded.load
    end

    local akimbo = pair and { { rounds = pair[1] }, { rounds = pair[2] } } or nil
    if akimbo and loaded then
        local views = Ammo.PairViews(wep)
        for i = 1, 2 do
            akimbo[i].load = views[i].load
            akimbo[i].capacity = views[i].capacity
        end
    end

    return {
        akimbo = akimbo,
        queue = queue,
        caliber = info.caliber,
        capacity = capacity,
        spec = loaded and Ammo.SpecTag(loaded.size, loaded.bullet, info.family) or nil,
        installed = installed,
        no_mag = wep._issr_no_mag and true or false,
        loose = Ammo.LooseOfKey(info.key),
        choice = chosen
    }
end

-- Which boxes the panel shows: the gun's magazine(s), then the magazines in
-- grid order, at most max_boxes. A chosen magazine further down takes the
-- last box, so you always see it. Returns the list indices to draw, the
-- positions to mark and how many are not shown.
function Ammo.HudOrder(in_gun, queue_n, choice, max_boxes)
    local total = in_gun + queue_n
    local shown = math.min(total, max_boxes)
    local order = {}
    for i = 1, shown do order[i] = i end
    local marked = {}
    if choice == "gun" then
        for i = 1, math.min(in_gun, shown) do marked[i] = true end
    elseif type(choice) == "number" then
        local index = in_gun + choice
        if index > shown and shown > in_gun then
            order[shown] = index
            marked[shown] = true
        elseif index <= shown then
            marked[index] = true
        end
    end
    return order, marked, total - shown
end

local function hud_panel()
    local ok, root = pcall(function()
        local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)
        return hud and hud.panel
    end)
    return ok and root or nil
end

local function remove_panel()
    if not panel then return end
    local root = hud_panel()
    if root then
        pcall(function() root:remove(panel) end)
    end
    panel = nil
end

local function add_text(target, name, x, y, w, h, size, text, align)
    target:text({
        name = name, x = x, y = y, w = w, h = h, layer = 11,
        color = LINE_COLOR, font = FONT, font_size = size,
        text = text, vertical = "center", align = align or "left"
    })
end

local function draw_header(target, rows, row_w)
    local parts = {}
    if Ammo.settings.show_mags and not rows.loose_fed then
        parts[#parts + 1] = L("issr_hud_mags", "MAGS") .. " " .. tostring(#rows.queue)
    end
    if Ammo.settings.show_loose then
        parts[#parts + 1] = L("issr_hud_loose", "LOOSE") .. " " .. tostring(rows.loose)
    end
    add_text(target, "pdti_ammo_header", 2, 0, row_w - 4,
        Ammo.settings.font_size, Ammo.settings.font_size, table.concat(parts, "    "))
end

local function draw_no_mag(target, x, y)
    local dash, gap, t = 4, 3, 2
    local function dashes(name, x0, y0, len, horizontal)
        local pos, n = 0, 0
        while pos < len do
            local l = math.min(dash, len - pos)
            target:rect({
                name = name .. n,
                x = horizontal and (x0 + pos) or x0,
                y = horizontal and y0 or (y0 + pos),
                w = horizontal and l or t,
                h = horizontal and t or l,
                layer = 11, color = LINE_COLOR
            })
            pos = pos + dash + gap
            n = n + 1
        end
    end
    dashes("pdti_mag_dash_t", x, y, BOX_W, true)
    dashes("pdti_mag_dash_b", x, y + BOX_H - t, BOX_W, true)
    dashes("pdti_mag_dash_l", x, y, BOX_H, false)
    dashes("pdti_mag_dash_r", x + BOX_W - t, y, BOX_H, false)

    target:text({
        name = "pdti_mag_x", x = x, y = y, w = BOX_W, h = BOX_H, layer = 13,
        color = LINE_COLOR, font = FONT,
        font_size = math.min(Ammo.settings.font_size, BOX_H),
        text = "X", vertical = "center", align = "center"
    })
end

-- The colour of a bullet in the HUD (standard: the panel's own).
local function bullet_color(bullet)
    local c = PDTI.UI_BULLET_COLORS and PDTI.UI_BULLET_COLORS[bullet]
    if not c then return nil end
    local ok, color = pcall(Color, c[1], c[2], c[3])
    return ok and color or nil
end

-- The parts of a magazine's fill, bottom first: { rounds, colour }.
function Ammo.HudSegments(mag)
    local out = {}
    local load = mag and mag.load
    if type(load) ~= "table" or #load == 0 then return out end
    local left = math.max(0, mag.rounds or 0)
    for i = #load, 1, -1 do
        local n = math.min(load[i][2], left)
        if n > 0 then out[#out + 1] = { rounds = n, bullet = load[i][1] } end
        left = left - n
    end
    return out
end

local function draw_mag(target, index, mag, x, y, capacity)
    capacity = mag.capacity or capacity
    local ratio = math.max(0, math.min(1, (mag.rounds or 0) / math.max(1, capacity)))
    target:rect({
        name = "pdti_mag_box_" .. index, x = x, y = y, w = BOX_W, h = BOX_H,
        layer = 10, color = BOX_COLOR
    })
    local segments = Ammo.HudSegments(mag)
    if ratio > 0 and #segments > 0 then
        -- Each kind of bullet in its colour, the bottom of the magazine first.
        local bottom = y + BOX_H - 2
        for i, seg in ipairs(segments) do
            local h = math.max(1, (BOX_H - 4) * seg.rounds / math.max(1, capacity))
            target:rect({
                name = "pdti_mag_fill_" .. index .. "_" .. i, x = x + 2, y = bottom - h,
                w = BOX_W - 4, h = h, layer = 11, color = bullet_color(seg.bullet) or FILL_COLOR
            })
            bottom = bottom - h
        end
    elseif ratio > 0 then
        local fh = math.max(2, (BOX_H - 4) * ratio)
        target:rect({
            name = "pdti_mag_fill_" .. index, x = x + 2, y = y + BOX_H - 2 - fh,
            w = BOX_W - 4, h = fh, layer = 11, color = FILL_COLOR
        })
    end
end

local function draw_footer(target, rows, first, row_w, y)
    local text
    if rows.loose_fed then
        text = L("pdti_hud_loaded", "LOADED") .. " " .. tostring(first and first.rounds or 0)
            .. "/" .. tostring(rows.capacity)
        if rows.spec then
            -- The next shell a reload loads (the wheel chooses it).
            text = text .. "  " .. rows.spec
        elseif Ammo.settings.show_ammo_type then
            text = text .. "    " .. tostring(rows.caliber)
        end
    elseif Ammo.settings.show_mags then
        if rows.no_mag then
            text = L("issr_hud_no_mag", "NO MAG")
        elseif rows.choice == "gun" then
            text = L("pdti_hud_take_out", "R: TAKE OUT")
        else
            text = L("issr_hud_next", "NEXT") .. " " .. tostring(first and first.rounds or 0)
                .. "/" .. tostring(rows.capacity)
            if rows.akimbo then
                text = "L " .. tostring(rows.akimbo[1].rounds) .. "  R " .. tostring(rows.akimbo[2].rounds)
                    .. "  /" .. tostring(rows.capacity)
            end
        end
        if rows.spec then
            text = text .. "  " .. rows.spec
        elseif Ammo.settings.show_ammo_type then
            text = text .. "    " .. tostring(rows.caliber)
        end
    else
        text = tostring(rows.caliber)
    end
    add_text(target, "pdti_ammo_footer", 2, y, row_w - 4,
        Ammo.settings.font_size, Ammo.settings.font_size, text)
end

local function build_panel(rows)
    local root = hud_panel()
    if not root then return nil end

    local list = rows.akimbo and { rows.akimbo[1], rows.akimbo[2] } or { rows.installed }
    local in_gun = #list
    for i = 1, #rows.queue do list[#list + 1] = rows.queue[i] end

    local max_boxes = math.max(2, math.floor(Ammo.settings.max_boxes or 4))
    local order, marked, hidden = Ammo.HudOrder(in_gun, #rows.queue, rows.choice, max_boxes)
    local shown = #order
    local row_w = (BOX_W + BOX_GAP) * max_boxes + BOX_GAP
    local header_on = Ammo.settings.show_mags or Ammo.settings.show_loose
    local foot_on = Ammo.settings.show_mags or Ammo.settings.show_ammo_type or rows.loose_fed
    local head_h = header_on and (Ammo.settings.font_size + 2) or 0
    local foot_h = foot_on and (Ammo.settings.font_size + 2) or 0
    local panel_h = head_h + BOX_H + 6 + foot_h

    local target = root:panel({
        name = "pdti_ammo_panel",
        x = root:w() - row_w - Ammo.settings.pad_right,
        y = root:h() - panel_h - Ammo.settings.pad_bottom,
        w = row_w, h = panel_h, layer = 10
    })

    target:rect({
        name = "pdti_ammo_bg", x = 0, y = 0, w = row_w, h = panel_h,
        layer = 9, color = BG_COLOR
    })

    if header_on then draw_header(target, rows, row_w) end

    for i = 1, shown do
        local x = BOX_GAP + (i - 1) * (BOX_W + BOX_GAP)
        local index = order[i]
        if index <= in_gun then
            target:rect({
                name = "pdti_mag_line_" .. i, x = x, y = head_h - 3, w = BOX_W, h = 2,
                layer = 12, color = LINE_COLOR
            })
        end
        if index <= in_gun and rows.no_mag then
            draw_no_mag(target, x, head_h)
        else
            draw_mag(target, i, list[index], x, head_h, rows.capacity)
        end
        if marked[i] then
            target:rect({
                name = "pdti_mag_choice_" .. i, x = x, y = head_h + BOX_H + 1, w = BOX_W, h = 2,
                layer = 12, color = CHOICE_COLOR
            })
        end
    end

    -- "+N" on the last box, or the one before when the last is the chosen.
    local more_at = marked[shown] and order[shown] ~= shown and shown - 1 or shown
    if Ammo.settings.show_more and hidden > 0 and more_at > in_gun then
        local x = BOX_GAP + (more_at - 1) * (BOX_W + BOX_GAP)
        target:text({
            name = "pdti_ammo_more", x = x, y = head_h, w = BOX_W, h = BOX_H,
            layer = 13, color = LINE_COLOR, font = FONT,
            font_size = math.min(Ammo.settings.font_size, 14),
            text = "+" .. tostring(hidden), vertical = "center", align = "center"
        })
    end

    -- The footer's NEXT is what the next reload loads.
    local next_mag = list[1]
    if type(rows.choice) == "number" then next_mag = rows.queue[rows.choice] end
    if foot_on then draw_footer(target, rows, next_mag, row_w, head_h + BOX_H + 4) end
    return target
end

-- Why the panel could not be shown, written to the log once per reason
-- (another HUD mod can take the player's HUD panel away).
local reported = {}
local function hud_problem(reason)
    if reported[reason] then return end
    reported[reason] = true
    log("the ammunition panel cannot be shown: " .. reason)
end
Ammo._HudProblems = reported

local function rebuild_panel(rows)
    remove_panel()
    if not hud_panel() then
        hud_problem("the game's player HUD panel is missing (another HUD mod?)")
    end
    local ok, result = pcall(build_panel, rows)
    if not ok then
        hud_problem("drawing failed: " .. tostring(result))
        result = nil
        remove_panel()
        pcall(function()
            local root = hud_panel()
            local left = root and root:child("pdti_ammo_panel")
            if left then root:remove(left) end
        end)
    end
    panel = result
    Ammo.panel_visible = panel ~= nil
end

-- For the tests.
Ammo.HudRows = function() return collect_rows() end

function Ammo.SetPanel(want)
    if want == Ammo.panel_visible then return end
    if not want then
        Ammo.panel_visible = false
        remove_panel()
        return
    end
    local rows = collect_rows()
    if not rows then
        local wep = Ammo.EquippedBase()
        if wep and not Ammo.Identify(wep) then
            hud_problem("the weapon " .. tostring(wep._name_id) .. " is not known to the ammunition system")
        end
        return
    end
    rebuild_panel(rows)
end

function Ammo.RefreshPanel()
    if not Ammo.panel_visible then return end
    local rows = collect_rows()
    if not rows then return end
    rebuild_panel(rows)
end

-- The ammo counters of both weapons: a magazine weapon shows the number of
-- spare magazines.
function Ammo.RefreshHud()
    local pl = Ammo.PlayerUnit()
    if not pl then return end
    pcall(function()
        for _, sel in pairs(pl:inventory():available_selections() or {}) do
            local base = sel.unit and sel.unit:base()
            if base and base.selection_index and base.ammo_info then
                managers.hud:set_ammo_amount(base:selection_index(), base:ammo_info())
            end
        end
    end)
end
