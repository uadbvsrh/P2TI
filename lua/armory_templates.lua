-- Gun build templates (0.41.0): a build you saved, to put on another weapon.
--
-- A template is the parts you fitted on a weapon, beyond the weapon's own:
-- save the build once and put the same build on the next gun of the same kind
-- (or on this one again). The parts stay yours: a template is a recipe, not
-- a copy of the parts. To apply one you need the parts as items (the ones
-- you have, or new ones from the market); the parts that come off the
-- weapon become items again.
--
-- The templates are in their own file (one per profile), like the armory's.
-- A build is changed at home only: in a heist every change takes time
-- (armory_hotmod.lua) and a template is a whole build at once.
--
-- The weapon view (ui_beardlib.lua) is where they are made and used: save
-- the build of the weapon you are looking at, and put one on any weapon
-- later.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Armory or not PDTI.Parts then return end

local Armory, Parts = PDTI.Armory, PDTI.Parts
local Templates = PDTI.Templates or {}
PDTI.Templates = Templates

local log = PDTI.Logger("PDTI TEMPLATES")

Templates.FILE_VERSION = 1
Templates.MAX = 24           -- how many templates you can keep
Templates.MAX_NAME = 30      -- the letters of a template's name

------------------------------------------------------------------ saving

local data, loaded_profile = nil, nil

local function file_name(index)
    local own = PDTI.SaveFileName and PDTI.SaveFileName("templates", index)
    if own then return own end
    if index == 1 then return "pdti_templates.json" end
    return "pdti_templates_profile" .. tostring(index) .. ".json"
end
Templates.FileName = file_name

local function path(index)
    return (rawget(_G, "SavePath") or "") .. file_name(index)
end

local function sanitize(raw)
    local d = { version = Templates.FILE_VERSION, next_id = 1, templates = {} }
    if type(raw) ~= "table" then return d end
    d.next_id = math.max(1, math.floor(tonumber(raw.next_id) or 1))
    for _, t in ipairs(type(raw.templates) == "table" and raw.templates or {}) do
        if type(t) == "table" then
            local id = math.floor(tonumber(t.id) or 0)
            local parts = {}
            for _, p in ipairs(type(t.parts) == "table" and t.parts or {}) do
                if type(p) == "string" and p ~= "" then parts[#parts + 1] = p end
            end
            -- A template without parts is nothing: it is left out.
            if id > 0 and #parts > 0 then
                d.templates[#d.templates + 1] = {
                    id = id,
                    name = type(t.name) == "string" and t.name or "build",
                    weapon_id = type(t.weapon_id) == "string" and t.weapon_id or "",
                    parts = parts,
                    made = type(t.made) == "string" and t.made or ""
                }
                d.next_id = math.max(d.next_id, id + 1)
            end
        end
    end
    return d
end
Templates._Sanitize = sanitize

local function read_file(index)
    local f = io.open(path(index), "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    local js = rawget(_G, "json")
    if not js or type(text) ~= "string" or text == "" then return nil end
    local ok, raw = pcall(js.decode, text)
    if not ok then log("the templates file could not be read: " .. tostring(raw)); return nil end
    return raw
end

function Templates.Load(index)
    index = index or (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1
    data = sanitize(read_file(index))
    loaded_profile = index
    return data
end

local function get()
    local index = (PDTI.ProfileIndex and PDTI.ProfileIndex()) or 1
    if not data or loaded_profile ~= index then Templates.Load(index) end
    return data
end
Templates._Data = get

-- Written at once (the menu and the safehouse).
function Templates.Store()
    local d = get()
    local js = rawget(_G, "json")
    if not js then log("no JSON library: the templates are not saved"); return false end
    local ok, text = pcall(js.encode, d)
    if not ok or type(text) ~= "string" then log("the templates could not be encoded"); return false end
    local p = path(loaded_profile or 1)
    local tmp = p .. ".tmp"
    local f, err = io.open(tmp, "w")
    if not f then log("the templates could not be written: " .. tostring(err)); return false end
    local wrote = f:write(text)
    f:close()
    if not wrote then os.remove(tmp); log("the templates could not be written"); return false end
    os.remove(p)
    if not os.rename(tmp, p) then log("the templates file could not be replaced"); return false end
    return true
end

function Templates.Reset()
    data, loaded_profile = nil, nil
end

-------------------------------------------------------------- the templates

-- Every template you have (the ones of the weapon you are looking at
-- first).
function Templates.All(weapon_id)
    local out = {}
    for _, t in ipairs(get().templates) do
        if weapon_id == nil or t.weapon_id == weapon_id then out[#out + 1] = t end
    end
    return out
end

-- The template with this id, or nil.
function Templates.Find(id)
    id = math.floor(tonumber(id) or 0)
    if id <= 0 then return nil end
    for _, t in ipairs(get().templates) do
        if t.id == id then return t end
    end
    return nil
end

-- How many templates you have.
function Templates.Count()
    return #get().templates
end

-- The name a new template gets: the weapon's name and "build" (with a
-- number when that one is taken).
local function next_name(weapon_data)
    local base = tostring(weapon_data.name or weapon_data.weapon_id or "build") .. " build"
    if #base > Templates.MAX_NAME then base = base:sub(1, Templates.MAX_NAME) end
    local taken = {}
    for _, t in ipairs(get().templates) do taken[t.name] = true end
    if not taken[base] then return base end
    for i = 2, Templates.MAX + 1 do
        local name = base .. " " .. i
        if not taken[name] then return name end
    end
    return base
end

-- Saves the weapon's build as a template: the parts on it beyond its own.
-- ok, the template, then the message.
function Templates.Save(weapon_data, name)
    if not Armory.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if Armory.InHeist() then return false, "builds are changed at home" end
    if type(weapon_data) ~= "table" then return false, "no such weapon" end
    local parts = {}
    for _, f in ipairs(Parts.Fitted(weapon_data)) do
        -- (Only the parts that are items: the others come with the weapon.)
        if f.removable then parts[#parts + 1] = f.part_id end
    end
    if #parts == 0 then return false, "this weapon has no parts of yours to save" end
    local d = get()
    if #d.templates >= Templates.MAX then
        return false, string.format("you have %d templates already (the most)", Templates.MAX)
    end
    local t = {
        id = d.next_id,
        name = name or next_name(weapon_data),
        weapon_id = tostring(weapon_data.weapon_id or ""),
        parts = parts,
        made = os.date("%Y-%m-%d")
    }
    d.next_id = d.next_id + 1
    d.templates[#d.templates + 1] = t
    Templates.Store()
    log(string.format("template %d saved: %s (%d part(s))", t.id, tostring(t.name), #t.parts))
    return true, t, string.format("Saved: %s", t.name)
end

-- Throws a template away.
function Templates.Delete(id)
    local d = get()
    id = math.floor(tonumber(id) or 0)
    for i, t in ipairs(d.templates) do
        if t.id == id then
            table.remove(d.templates, i)
            Templates.Store()
            log(string.format("template %d deleted", id))
            return true, string.format("Deleted: %s", tostring(t.name))
        end
    end
    return false, "no such template"
end

-- Puts a template's build on a weapon: the parts the weapon takes and you
-- own go on it, the ones that come off become items again. ok, the message.
function Templates.Apply(id, weapon_c, weapon_iid)
    local t = Templates.Find(id)
    if not t then return false, "no such template" end
    if not Armory.Enabled() then return false, "the armory is off (restoration-mod or no stash)" end
    if Armory.InHeist() then return false, "builds are changed at home" end
    local weapon = PDTI.FindItem(weapon_c, weapon_iid)
    if not weapon or weapon.item_id ~= Armory.ITEM_ID or type(weapon.data) ~= "table" then
        return false, "no such weapon"
    end
    local ok, msg, fitted, skipped = Parts.ApplyBuild(weapon_c, weapon_iid, t.parts)
    if not ok then return false, msg end
    local text = tostring(msg)
    -- What did not go on is said too: the weapon does not take it, or it is
    -- not yours.
    local left = {}
    for _, s in ipairs(skipped or {}) do
        left[#left + 1] = string.format("%s (%s)", Parts.Name(s.part_id), tostring(s.why))
    end
    if #left > 0 then text = text .. "; not fitted: " .. table.concat(left, ", ") end
    log(string.format("template %d on the %s: %d part(s)", id, tostring(weapon.data.weapon_id), #(fitted or {})))
    return true, text
end

-- What a template is: its name and its parts.
function Templates.Describe(t)
    if type(t) ~= "table" then return "" end
    local names = {}
    for _, p in ipairs(t.parts or {}) do names[#names + 1] = Parts.Name(p) end
    return string.format("%s (%d part(s): %s)", tostring(t.name), #names, table.concat(names, ", "))
end
