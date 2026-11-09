-- The deployable line of the HUD, just above the magazine panel.
--
--   DEPLOY  First Aid Kit x2   [X]
--
-- It shows what the deployable key places now and is drawn again whenever
-- that changes (an item placed, picked with X, moved in the inventory).
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Hud = PDTI.DeployHud or {}
PDTI.DeployHud = Hud

local FONT = "fonts/font_medium_mf"
local GAP = 4

local state = { panel = nil, key = nil }

local function hud_panel()
    local ok, panel = pcall(function()
        local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)
        return hud and hud.panel
    end)
    return ok and panel or nil
end

local function remove()
    if not state.panel then return end
    local root = hud_panel()
    if root then pcall(function() root:remove(state.panel) end) end
    state.panel = nil
end

function Hud.Text()
    local dep = PDTI.Deployables
    if not dep or not dep.DisplayName then return nil end
    local key = string.upper(tostring(dep.CYCLE_KEY or "x"))
    return "DEPLOY  " .. dep.DisplayName() .. "   [" .. key .. "]"
end

local function settings()
    local s = PDTI.Ammo and PDTI.Ammo.settings or {}
    return tonumber(s.font_size) or 20, tonumber(s.pad_right) or 220, tonumber(s.pad_bottom) or 100
end

-- Where the line goes: on top of the magazine panel when it is shown,
-- else where that panel would start.
local function anchor(root)
    local font_size, pad_right, pad_bottom = settings()
    local ammo = root:child("pdti_ammo_panel")
    if ammo then
        return ammo:right(), ammo:top() - GAP
    end
    return root:w() - pad_right, root:h() - pad_bottom - GAP
end

local function build(root, text)
    local font_size = settings()
    local size = math.max(12, font_size - 2)
    local w, h = 320, size + 6
    local right, bottom = anchor(root)
    local panel = root:panel({
        name = "pdti_deploy_panel", x = right - w, y = bottom - h, w = w, h = h, layer = 10
    })
    local label = panel:text({
        name = "pdti_deploy_text", x = 0, y = 0, w = w - 4, h = h, layer = 11,
        color = Color(1, 1, 1, 1), font = FONT, font_size = size,
        text = text, vertical = "center", align = "right"
    })
    -- A dark backing as wide as the text.
    local tw = w
    pcall(function()
        local _, _, text_w = label:text_rect()
        if text_w and text_w > 0 then tw = math.min(w, text_w + 10) end
    end)
    panel:rect({ name = "pdti_deploy_bg", x = w - tw, y = 0, w = tw, h = h, layer = 9,
        color = Color(0, 0, 0, 0.35) })
    return panel
end

local function clock()
    local ok, t = pcall(function() return Application:time() end)
    if ok and type(t) == "number" then return t end
    return os.clock()
end

-- Called every frame from the game hook; looks ten times a second and draws
-- only when something changed.
Hud.INTERVAL = 0.1
function Hud.Update(force)
    local now = clock()
    if not force and state.t and now - state.t < Hud.INTERVAL then return end
    state.t = now
    local root = hud_panel()
    if not root then
        state.panel, state.key = nil, nil
        return
    end
    local text = Hud.Text()
    if not text then remove() return end
    local right, bottom = anchor(root)
    local key = text .. "|" .. tostring(right) .. "|" .. tostring(bottom)
    if key == state.key and state.panel then return end
    remove()
    local ok, panel = pcall(build, root, text)
    if ok then
        state.panel = panel
        state.key = key
    else
        state.key = key -- do not retry an error every frame
        if _G.log then _G.log("[PDTI DEPLOY] HUD line failed: " .. tostring(panel)) end
    end
end

function Hud.Remove()
    remove()
    state.key = nil
end
