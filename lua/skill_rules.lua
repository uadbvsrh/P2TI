-- Core rules of the skill rework (SKILLS_REWORK_SPEC.md, 0.22.0).
--
--   * R3, ECM durations: every ECM duration of the game is scaled by one
--     factor, so the longest jammer (both duration skills, x1.5) lasts 15 s.
--     The skills keep their relative value. Vanilla only: restoration-mod
--     has its own ECM numbers.
--   * R4, weight -> concealment: every 3 kg over 15 kg costs a point of
--     concealment (30 kg -5, 60 kg -15). The game's concealment feeds the
--     detection risk, so stealth and every concealment skill feel the
--     weight. The hook is BlackMarketManager:visibility_modifiers, the
--     modifier the game adds to the local player's visibility. Vanilla
--     only (0.22.1), like R3.
--
-- (R1, the black-part spill, lives in body.lua.)
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Rules = PDTI.Rules or {}
PDTI.Rules = Rules

-- R3: 20 s x 1.5 = 30 s at most in the game; x0.5 gives 15 s.
Rules.ECM_FACTOR = 0.5
Rules.ECM_KEYS = {
    "ecm_jammer_base_battery_life",
    "ecm_jammer_base_low_battery_life",
    "ecm_feedback_min_duration",
    "ecm_feedback_max_duration"
}
-- R4
Rules.CONCEAL_STEP = 3

local log = PDTI.Logger("PDTI RULES")

-- Restoration-mod is loaded: the skill rework stays off (its skills are
-- other skills on the same ids).
function Rules.Restoration()
    return rawget(_G, "restoration") ~= nil
end

------------------------------------------------------------------- R3: ECM

-- Scales the ECM durations once. The originals are kept on the table, so a
-- second call (the scripts run again on every state change) changes nothing.
function Rules.ApplyEcm()
    if Rules.Restoration() then return false end
    local td = rawget(_G, "tweak_data")
    local up = td and td.upgrades
    if type(up) ~= "table" then return false end
    if up._pdti_ecm then return true end
    local original = {}
    for _, key in ipairs(Rules.ECM_KEYS) do
        if type(up[key]) == "number" then
            original[key] = up[key]
            up[key] = up[key] * Rules.ECM_FACTOR
        end
    end
    up._pdti_ecm = original
    log(string.format("ECM durations x%.2f (jammer %s s)", Rules.ECM_FACTOR,
        tostring(up.ecm_jammer_base_battery_life)))
    return true
end

------------------------------------------------------- R4: weight -> concealment

-- Houston's room: the general rig's weight (half, or all of it) is not
-- seen by concealment.
function Rules.HiddenWeight()
    local perks = PDTI.Perks
    local share = perks and perks.RigConcealRelief and perks.RigConcealRelief() or 0
    if share <= 0 then return 0 end
    local w = 0
    for _, entry in ipairs(PDTI.FindItems(function(c, item) return c:find("^rig") ~= nil and item.item_id ~= "loot_bag" end)) do
        w = w + (tonumber(PDTI.ItemWeight(entry.item)) or 0)
    end
    return w * share
end

-- Concealment points the weight costs. Vanilla only, like every rule of the
-- rework.
function Rules.ConcealmentPenalty(weight)
    local Carry = PDTI.Carry
    if not Carry or not Carry.enabled or Rules.Restoration() then return 0 end
    weight = tonumber(weight)
    if not weight then
        local ok, w = pcall(Carry.LoadWeight)
        weight = ok and tonumber(w) or nil
        -- Not readable now: no answer, so the last value stays.
        if not weight then return nil end
        weight = math.max(0, weight - Rules.HiddenWeight())
    end
    local free = tonumber(Carry.FREE_WEIGHT) or 15
    if weight <= free then return 0 end
    return math.floor((weight - free) / Rules.CONCEAL_STEP + 1e-9)
end

-- The game asks for the concealment often; the weight changes only with the
-- inventory.
Rules.CACHE_TIME = 0.5
local cache = { value = nil, revision = nil, t = nil }

local clock = PDTI.AppTime

function Rules.InvalidateCache()
    cache.value = nil
end

function Rules.CurrentPenalty()
    local now = clock()
    local revision = PDTI.inventory_revision or 0
    if cache.value and cache.revision == revision and cache.t and now - cache.t < Rules.CACHE_TIME then
        return cache.value
    end
    local ok, value = pcall(Rules.ConcealmentPenalty)
    -- A failed read keeps the last value instead of dropping to 0.
    if ok and type(value) == "number" then cache.value = value
    elseif cache.value == nil then cache.value = 0 end
    cache.revision = revision
    cache.t = now
    return cache.value
end

-- The menu's detection meter is drawn when the game's loadout changes; what
-- you bring (the inventory screen) changes the weight too, so it is redrawn
-- when that screen closes.
function Rules.RefreshMenuDetection()
    Rules.InvalidateCache()
    local mc = rawget(_G, "managers") and managers.menu_component
    local gui = mc and mc._player_inventory_gui
    if gui and type(gui.update_detection) == "function" then
        pcall(gui.update_detection, gui)
        return true
    end
    return false
end

local hooked = {}

function Rules.InstallConcealment()
    local cls = rawget(_G, "BlackMarketManager")
    local current = cls and cls.visibility_modifiers
    if type(current) ~= "function" then return false end
    if hooked.visibility == current then return true end
    if PDTI.HookHas and PDTI.HookHas(current, "rules") then return true end
    local orig = current
    local hook = function(self, ...)
        local value = orig(self, ...)
        if type(value) ~= "number" then return value end
        return value + Rules.CurrentPenalty()
    end
    if PDTI.HookMark then PDTI.HookMark(hook, orig, "rules") end
    hooked.visibility = hook
    cls.visibility_modifiers = hook
    log("weight costs concealment: 1 point per " .. Rules.CONCEAL_STEP .. " kg over the free weight")
    return true
end

-- Everything that can go in now; safe to call again and again.
function Rules.Install()
    pcall(Rules.ApplyEcm)
    local ok, conceal = pcall(Rules.InstallConcealment)
    return ok and conceal
end

Rules.Install()
