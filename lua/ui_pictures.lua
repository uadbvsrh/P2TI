-- Pictures of weapons and parts (0.40.0): the game's own icons, drawn on the
-- inventory screen (ui_beardlib.lua draws them; nothing is drawn here).
--
-- A weapon's picture is the one the game's inventory and the briefing show
-- (BlackMarketManager:get_weapon_icon_path, the stock gun: fitted parts are
-- not on it). A part's is the weapon modding screen's
-- (guis/[dlcs/<bundle>/]textures/pd2/blackmarket/icons/mods/<part_id>).
-- Each texture is asked of the game once while the screen is open
-- (menu_component:request_texture, as its inventory does) and given back
-- when it closes.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Pictures = PDTI.Pictures or {}
PDTI.Pictures = Pictures

local log = PDTI.Logger("PDTI PICTURES")

-- A turned item's picture is turned this much (degrees).
Pictures.TURN = 90

local weapon_paths, part_paths = {}, {}
local sizes = {}
local state, requests = {}, {}
local requesting = false

-- Pictures are on unless the setting is off.
function Pictures.Enabled()
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return not (s and s.item_pictures == false)
end

-- Names over the pictures (a pictured item's cells, PRI / SEC) unless that
-- setting is off (0.40.1): then the picture alone.
function Pictures.ShowNames()
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return not (s and s.item_picture_names == false)
end

local function exists(path)
    local ok, has = pcall(function() return DB:has(Idstring("texture"), path) end)
    return ok and has == true
end

-- A path the game has, else false (said once in the log).
local function checked(kind, id, path)
    if path and exists(path) then return path end
    log(string.format("no picture for %s %s at %s", kind, tostring(id), tostring(path)))
    return false
end

function Pictures.WeaponPath(weapon_id)
    if type(weapon_id) ~= "string" then return nil end
    local p = weapon_paths[weapon_id]
    if p == nil then
        local ok, path = pcall(function() return managers.blackmarket:get_weapon_icon_path(weapon_id, nil) end)
        p = checked("weapon", weapon_id, ok and type(path) == "string" and path or nil)
        weapon_paths[weapon_id] = p
    end
    return p or nil
end

function Pictures.PartPath(part_id)
    if type(part_id) ~= "string" then return nil end
    local p = part_paths[part_id]
    if p == nil then
        local ok, bundle = pcall(function() return tweak_data.blackmarket.weapon_mods[part_id].texture_bundle_folder end)
        local folder = (ok and type(bundle) == "string") and ("dlcs/" .. bundle .. "/") or ""
        p = checked("part", part_id, "guis/" .. folder .. "textures/pd2/blackmarket/icons/mods/" .. part_id)
        part_paths[part_id] = p
    end
    return p or nil
end

-- The picture of an inventory item (a weapon or a part), or nil.
function Pictures.ItemPath(item)
    if not Pictures.Enabled() or type(item) ~= "table" or type(item.data) ~= "table" then return nil end
    if item.item_id == "weapon" then return Pictures.WeaponPath(item.data.weapon_id) end
    if item.item_id == "weapon_part" then return Pictures.PartPath(item.data.part_id) end
    return nil
end

-- The screen is drawn again when a texture came (once for all that came
-- together: ui_beardlib.lua's UIRedrawSoon). (A texture the game already had
-- comes at once, while the screen is drawn: it is drawn then.)
local function redraw()
    if requesting then return end
    if PDTI.UIRedrawSoon then pcall(PDTI.UIRedrawSoon) end
end

-- Can the texture be drawn now? It is asked for the first time (the game
-- loads it, then the screen is drawn again). Without the game's texture
-- loader it is drawn at once (as the briefing does).
function Pictures.Ready(path)
    if type(path) ~= "string" then return false end
    local st = state[path]
    if st ~= nil then return st == "ready" end
    local mc = rawget(_G, "managers") and managers.menu_component
    if not (mc and mc.request_texture) then
        state[path] = "ready"
        return true
    end
    state[path] = "waiting"
    requesting = true
    local ok, index = pcall(mc.request_texture, mc, path, function()
        if state[path] == "waiting" then state[path] = "ready" end
        redraw()
    end)
    requesting = false
    if not ok then
        state[path] = "ready"
        return true
    end
    requests[#requests + 1] = { path = path, index = index }
    return state[path] == "ready"
end

-- The screen closed: the textures go back to the game.
function Pictures.ReleaseAll()
    local mc = rawget(_G, "managers") and managers.menu_component
    for _, r in ipairs(requests) do
        if mc and mc.unretrieve_texture then pcall(mc.unretrieve_texture, mc, r.path, r.index) end
    end
    local n = #requests
    requests, state = {}, {}
    return n
end

-- The texture's size in pixels (read once from a bitmap on this panel), or
-- nil.
function Pictures.Size(path, panel)
    local s = sizes[path]
    if s then return s[1], s[2] end
    local ok, w, h = pcall(function()
        local b = panel:bitmap({ texture = path, visible = false })
        local tw, th = b:texture_width(), b:texture_height()
        panel:remove(b)
        return tw, th
    end)
    if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then
        sizes[path] = { w, h }
        return w, h
    end
    return nil
end

-- The pieces of a tw x th picture over an item of cols x rows cells (as it
-- lies: turned or not), cells cw x ch apart with a gap between them: the
-- picture fits the item's whole area less a margin, keeps its shape and is
-- centred; each cell shows its own piece. Returns { cx, cy, x, y, w, h (in
-- the cell), rect = { u, v, tw, th } (texture pixels), rotation }.
-- A turned item's cells each get the whole picture, unturned size, centred on
-- the item's centre and turned (Pictures.TURN) about it: the cell's panel
-- cuts it at its edges (rect is nil). A bitmap turns about its own centre,
-- so either way the engine turns, the pieces meet.
function Pictures.Slices(tw, th, cols, rows, cw, ch, gap, rotated, margin)
    tw, th = tonumber(tw) or 0, tonumber(th) or 0
    gap, margin = gap or 0, margin or 0
    if tw <= 0 or th <= 0 or cols < 1 or rows < 1 then return {} end
    local aw, ah = cols * cw - gap, rows * ch - gap
    local iw, ih = aw - 2 * margin, ah - 2 * margin
    if iw <= 0 or ih <= 0 then return {} end
    local dw, dh = tw, th
    if rotated then dw, dh = th, tw end
    local scale = math.min(iw / dw, ih / dh)
    local pw, ph = dw * scale, dh * scale
    local px, py = (aw - pw) / 2, (ah - ph) / 2
    local out = {}
    for cy = 0, rows - 1 do
        for cx = 0, cols - 1 do
            local x0, y0 = cx * cw, cy * ch
            local x1, y1 = x0 + cw - gap, y0 + ch - gap
            local dx0, dy0 = math.max(x0, px), math.max(y0, py)
            local dx1, dy1 = math.min(x1, px + pw), math.min(y1, py + ph)
            if dx1 - dx0 > 0.5 and dy1 - dy0 > 0.5 then
                -- The piece, 0 to 1 across the shown picture.
                local a0, a1 = (dx0 - px) / pw, (dx1 - px) / pw
                local b0, b1 = (dy0 - py) / ph, (dy1 - py) / ph
                local w, h = dx1 - dx0, dy1 - dy0
                local s = { cx = cx, cy = cy, rotation = 0 }
                if not rotated then
                    s.x, s.y, s.w, s.h = dx0 - x0, dy0 - y0, w, h
                    s.rect = { a0 * tw, b0 * th, (a1 - a0) * tw, (b1 - b0) * th }
                else
                    s.rotation = Pictures.TURN
                    s.w, s.h = ph, pw -- (the unturned size)
                    s.x = aw / 2 - x0 - s.w / 2
                    s.y = ah / 2 - y0 - s.h / 2
                end
                out[#out + 1] = s
            end
        end
    end
    return out
end

-- (Tests: forget what was looked up.)
function Pictures._Reset()
    weapon_paths, part_paths, sizes, state, requests = {}, {}, {}, {}, {}
end
