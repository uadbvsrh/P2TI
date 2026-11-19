-- Lasting body damage (0.48.0). The body parts (body.lua) keep the health a
-- heist left them with: the next heist, and the safehouse, start that way.
-- Black parts stay black. Nothing heals for free between heists: a first aid
-- kit or a medic bag in a heist, or Dallas.
--
--   * A heist ended down or in custody (won or failed), or left / quit:
--     every part comes home at 0, the head at 1 HP.
--   * Back from custody inside a heist the body is fresh, as before; only
--     the heist's end counts.
--   * Dallas (his room's menu in the safehouse) and the menu's inventory
--     screen: "Heal everything" for $15,000, every part to full.
--
-- The parts are kept in their own file (pdti_save_body_profile<n>.json, or
-- pdti_body.json), written at the heist's start and end and after a heal.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Body then return end

local Body = PDTI.Body
local Lasting = PDTI.BodyLasting or {}
PDTI.BodyLasting = Lasting

local log = PDTI.Logger("PDTI BODY")

Lasting.PRICE = 15000

function Lasting.Enabled() return Body.Enabled() end

------------------------------------------------------------------ the file

local data, loaded_profile = nil, nil

local function file_name(index)
    local own = PDTI.SaveFileName and PDTI.SaveFileName("body", index)
    if own then return own end
    if index == 1 then return "pdti_body.json" end
    return "pdti_body_profile" .. tostring(index) .. ".json"
end
Lasting.FileName = file_name

local function path(index) return (rawget(_G, "SavePath") or "") .. file_name(index) end

local function profile() return (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1 end

-- { frac = { id = 0..1 }, in_heist = bool }
local function sanitize(raw)
    local d = { frac = {}, in_heist = false }
    for _, p in ipairs(Body.PARTS) do d.frac[p.id] = 1 end
    if type(raw) ~= "table" then return d end
    d.in_heist = raw.in_heist == true
    local f = type(raw.frac) == "table" and raw.frac or {}
    for _, p in ipairs(Body.PARTS) do
        local v = tonumber(f[p.id])
        if v and v == v then d.frac[p.id] = math.max(0, math.min(1, v)) end
    end
    return d
end
Lasting._Sanitize = sanitize

local function get()
    local index = profile()
    if data and loaded_profile == index then return data end
    local raw = nil
    local fh = io.open(path(index), "r")
    if fh then
        local text = fh:read("*a")
        fh:close()
        local js = rawget(_G, "json")
        if js and type(text) == "string" and text ~= "" then
            local ok, v = pcall(js.decode, text)
            if ok then raw = v else log("the body file could not be read") end
        end
    end
    data, loaded_profile = sanitize(raw), index
    return data
end
Lasting._Data = get

function Lasting.Reset() data, loaded_profile = nil, nil end

-- Written at once (also in a heist: it is not the inventory).
function Lasting.Save()
    local d = get()
    local js = rawget(_G, "json")
    if not js then return false end
    local ok, text = pcall(js.encode, d)
    if not ok or type(text) ~= "string" then return false end
    local fh = io.open(path(loaded_profile), "w")
    if not fh then log("the body file could not be written"); return false end
    fh:write(text)
    fh:close()
end

------------------------------------------------------------------ the rules

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

-- Down or in custody, or a heist left: every part at 0, the head at 1 HP.
local function down_parts()
    local frac = {}
    for _, p in ipairs(Body.PARTS) do frac[p.id] = 0 end
    local head_max = Body.PartMax("head", Body.state.max)
    frac.head = head_max > 0 and math.min(1, Body.EFFECTS.revive_head / head_max) or 0
    return frac
end

function Lasting.Parts() return copy(get().frac) end

function Lasting.Hurt()
    for _, v in pairs(get().frac) do
        if v < 1 then return true end
    end
    return false
end

-- "Left leg 0% (black), Body 40%" (the hurt parts), or nil.
function Lasting.Summary()
    local d, out = get(), {}
    for _, p in ipairs(Body.PARTS) do
        local f = d.frac[p.id]
        if f < 1 then
            out[#out + 1] = string.format("%s %d%%%s", p.name, math.floor(f * 100 + 0.5), f <= 0 and " (black)" or "")
        end
    end
    if #out == 0 then return nil end
    return table.concat(out, ", ")
end

-- (The safehouse is home: PDTI.InHeist says no there.)
local function at_home() return not PDTI.InHeist() end

local function money(v) return PDTI.Ammo.Money(v) end

local function take(amount)
    local ok, have = pcall(function() return managers.money:total() end)
    if not ok or type(have) ~= "number" or have < amount then return false end
    return pcall(function() managers.money:deduct_from_total(amount) end)
end

-- Heals every part to full for Lasting.PRICE (at home). ok, what was said.
function Lasting.HealAll()
    if not Lasting.Enabled() then return false, "Health per body part is off" end
    if not at_home() then return false, "In a heist, heal with a first aid kit or a medic bag" end
    if not Lasting.Hurt() then return false, "You are not hurt" end
    if not take(Lasting.PRICE) then return false, "Not enough money (" .. money(Lasting.PRICE) .. ")" end
    local d = get()
    for _, p in ipairs(Body.PARTS) do d.frac[p.id] = 1 end
    Lasting.Save()
    -- In the safehouse your character heals at once.
    if Body.state.owner then Body.FullHeal() else Body.ShowParts(d.frac) end
    log("healed every part for " .. Lasting.PRICE)
    return true, "Healed everything for " .. money(Lasting.PRICE)
end

------------------------------------------------------------------ the edges

-- A level starts (gamesetup): the first spawn starts as the last heist left
-- you. A heist (not the safehouse) is marked: left or quit, it counts as
-- ended down.
function Lasting.OnLevelStart()
    if not Lasting.Enabled() then return false end
    local d = get()
    Body.start_frac = copy(d.frac)
    if not PDTI.InSafehouse() then
        d.in_heist = true
        Lasting.Save()
    end
    return true
end

local function is_down()
    if PDTI.PlayerUnit() == nil then return true end
    local ok, s = pcall(function() return managers.player:current_state() end)
    if ok and (s == "bleed_out" or s == "fatal" or s == "incapacitated" or s == "arrested") then return true end
    return Body.HeadDown()
end

-- The heist (or a day of it) ended: the parts as they are, or down.
function Lasting.OnMissionEnd()
    if not Lasting.Enabled() or PDTI.InSafehouse() then return false end
    local d = get()
    local down = is_down()
    d.frac = down and down_parts() or copy(Body.state.frac)
    d.in_heist = false
    Lasting.Save()
    log(down and "the heist ended down: every part at 0, the head at 1 HP" or "the heist ended: the parts are kept")
    return true
end

-- At the menu: a heist still marked was left or quit (ended down). The
-- screen shows the saved parts.
function Lasting.OnMenu()
    if not Lasting.Enabled() then return false end
    local d = get()
    if d.in_heist then
        d.frac = down_parts()
        d.in_heist = false
        Lasting.Save()
        log("a heist was left: every part at 0, the head at 1 HP")
    end
    Body.state.owner = nil
    Body.ShowParts(d.frac)
    return true
end
