-- The skill rework (SKILLS_REWORK_SPEC.md): the frame every reworked skill
-- uses.
--
-- The game keeps the skills you own in the save and gives you their
-- upgrades when the save loads. Rewriting the skill tree's tweak data would
-- not take back what you already own, so the tree stays as it is:
--   * Skills.Step(id) reads what you own: 0 nothing, 1 basic, 2 ace.
--   * The vanilla upgrades a rework replaces are switched off where the game
--     reads them (PlayerManager:upgrade_value / has_category_upgrade), only
--     while that rework is in force: Skills.Off(category, upgrade, when).
--   * Skills.Override changes a value the game reads.
--   * The new effects are this mod's own code (skills_medic.lua, ...).
--   * The skill texts are replaced (Skills.Text).
-- Vanilla only: with restoration-mod its skills stay as they are.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Skills = PDTI.Skills or {}
PDTI.Skills = Skills
Skills.offs = Skills.offs or {}
Skills.overrides = Skills.overrides or {}
Skills.texts = Skills.texts or {}
Skills.levels = Skills.levels or {}
Skills.installers = Skills.installers or {}

local log = PDTI.Logger("PDTI SKILLS")
Skills.log = log

function Skills.Enabled()
    return rawget(_G, "restoration") == nil
end

-- 0 not owned, 1 basic, 2 ace. Tests replace Skills.step_of.
Skills.step_of = function(id)
    local st = rawget(_G, "managers") and managers.skilltree
    if not st or type(st.skill_step) ~= "function" then return 0 end
    local ok, step = pcall(st.skill_step, st, id)
    if ok and type(step) == "number" then return step end
    return 0
end

function Skills.Step(id)
    if not Skills.Enabled() then return 0 end
    return Skills.step_of(id) or 0
end

-- Can the skills be read yet (the skill tree exists)? Tests replace it.
Skills.known = function()
    local st = rawget(_G, "managers") and managers.skilltree
    return st ~= nil and type(st.skill_step) == "function"
end
function Skills.Known()
    if not Skills.Enabled() then return true end
    local ok, k = pcall(Skills.known)
    return ok and k == true
end

function Skills.Basic(id) return Skills.Step(id) >= 1 end
function Skills.Ace(id) return Skills.Step(id) >= 2 end

-- The PDTI systems a rework needs; with the system off the vanilla skill
-- stays.
function Skills.BodyOn()
    local b = PDTI.Body
    return b ~= nil and b.Enabled ~= nil and b.Enabled() == true
end
function Skills.AmmoOn()
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return s ~= nil and s.enabled ~= false
end
function Skills.ArmourOn()
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return not (s and s.heavy_armour == false)
end
function Skills.DeployablesOn()
    local d = PDTI.Deployables
    return d ~= nil and d.enabled ~= false
end

----------------------------------------------------------- the upgrades

local function key(category, upgrade) return tostring(category) .. "." .. tostring(upgrade) end

-- The vanilla upgrade is switched off while when() is true.
function Skills.Off(category, upgrade, when)
    Skills.offs[key(category, upgrade)] = when
end

-- fn(value, default) returns the value the game gets (nil: the game's).
function Skills.Override(category, upgrade, fn)
    Skills.overrides[key(category, upgrade)] = fn
end

-- fn(level) returns the level PlayerManager:upgrade_level gives (nil: the
-- game's). The game reads some upgrades only by level (the ammo bag's).
function Skills.Level(category, upgrade, fn)
    Skills.levels[key(category, upgrade)] = fn
end

function Skills.UpgradeLevel(category, upgrade, level)
    local fn = Skills.levels[key(category, upgrade)]
    if type(fn) ~= "function" then return level end
    local ok, v = pcall(fn, level)
    if ok and v ~= nil then return v end
    return level
end

local function is_off(k)
    local when = Skills.offs[k]
    if type(when) ~= "function" then return false end
    local ok, off = pcall(when)
    return ok and off == true
end

function Skills.UpgradeValue(category, upgrade, value, default)
    local k = key(category, upgrade)
    if is_off(k) then
        if default ~= nil then return default end
        return 0
    end
    local fn = Skills.overrides[k]
    if type(fn) == "function" then
        local ok, v = pcall(fn, value, default)
        if ok and v ~= nil then return v end
    end
    return value
end

local hooked = {}
local wrap_ids = {}

-- id: several modules can wrap the same function, each with its own id.
local function wrap(class_name, fn_name, make, id)
    if not id then return PDTI.Wrap(hooked, "skills", class_name, fn_name, make) end
    local by_id = wrap_ids[id]
    if not by_id then
        by_id = { tag = "skills_" .. id, keys = {} }
        wrap_ids[id] = by_id
    end
    local keys = by_id.keys
    local by_class = keys[class_name]
    if not by_class then by_class = {}; keys[class_name] = by_class end
    local key = by_class[fn_name]
    if not key then
        key = class_name .. "." .. fn_name .. "#" .. id
        by_class[fn_name] = key
    end
    return PDTI.Wrap(hooked, by_id.tag, class_name, fn_name, make, key)
end
Skills.wrap = wrap

local function make_upgrade_value(orig)
    return function(self, category, upgrade, default, ...)
        local value = orig(self, category, upgrade, default, ...)
        if not Skills.Enabled() then return value end
        return Skills.UpgradeValue(category, upgrade, value, default)
    end
end
local function make_has_category_upgrade(orig)
    return function(self, category, upgrade, ...)
        local has = orig(self, category, upgrade, ...)
        if has and Skills.Enabled() and is_off(key(category, upgrade)) then return false end
        return has
    end
end
local function make_upgrade_level(orig)
    return function(self, category, upgrade, default, ...)
        local level = orig(self, category, upgrade, default, ...)
        if not Skills.Enabled() then return level end
        return Skills.UpgradeLevel(category, upgrade, level)
    end
end

-- Runs every frame: the makers are built once.
local function install_upgrade_hooks()
    local a = wrap("PlayerManager", "upgrade_value", make_upgrade_value)
    local b = wrap("PlayerManager", "has_category_upgrade", make_has_category_upgrade)
    wrap("PlayerManager", "upgrade_level", make_upgrade_level)
    return a and b
end

--------------------------------------------------------------- the texts

-- desc: the whole description, as the game's skill page shows it.
-- The skills whose text ids in the game are not menu_<id>_beta
-- (skilltreetweakdata.lua name_id / desc_id).
Skills.TEXT_KEYS = {
    optic_illusions = "menu_optic_illusions",
    hitman = "menu_spotter_teamwork_beta",
    frenzy = "menu_frenzy",
}

-- key: the text id when it is not menu_<id>_beta (Skills.TEXT_KEYS).
function Skills.Text(id, desc, name, key)
    local base = key or Skills.TEXT_KEYS[id] or ("menu_" .. id .. "_beta")
    Skills.texts[base .. "_desc"] = desc
    if name then Skills.texts[base] = name end
end

local function apply_texts()
    if not Skills.Enabled() or next(Skills.texts) == nil then return false end
    local done = false
    local LM = rawget(_G, "LocalizationManager")
    if LM and type(LM.add_localized_strings) == "function" then
        done = pcall(LM.add_localized_strings, LM, Skills.texts)
    end
    local m = rawget(_G, "managers")
    local loc = m and m.localization
    if loc and type(loc.add_localized_strings) == "function" then
        done = pcall(loc.add_localized_strings, loc, Skills.texts) or done
    end
    return done
end
Skills.ApplyTexts = apply_texts

if not Skills._loc_hook and rawget(_G, "Hooks") and type(Hooks.Add) == "function" then
    Skills._loc_hook = true
    pcall(Hooks.Add, Hooks, "LocalizationManagerPostInit", "PDTI_Skills_Texts", function(loc)
        if not Skills.Enabled() then return end
        pcall(loc.add_localized_strings, loc, Skills.texts)
    end)
end

------------------------------------------------------------- installing

-- A rework module registers what it installs; each runs on every Install
-- (they must be safe to call again).
function Skills.OnInstall(name, fn)
    Skills.installers[name] = fn
end

function Skills.Install()
    local ok_up = install_upgrade_hooks()
    for name, fn in pairs(Skills.installers) do
        local ok, err = pcall(fn)
        if not ok then
            Skills.failed = Skills.failed or {}
            if not Skills.failed[name] then
                Skills.failed[name] = true
                log(name .. ": " .. tostring(err))
            end
        end
    end
    if not Skills._texts_done then Skills._texts_done = apply_texts() end
    if ok_up and not Skills._logged then
        Skills._logged = true
        log(Skills.Enabled() and "skill rework in place (vanilla)" or "restoration-mod: skills left as they are")
    end
    return ok_up
end
