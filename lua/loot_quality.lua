-- Loot quality.
--
-- Every loot bag keeps the value of its kind (gold, money, paintings ...),
-- but the first time you pick it up it rolls a quality:
--
--   Standard     80%   x1 value, no modifier
--   High          17%   x2 value, one modifier
--   Exceptional    3%   x4 value, two modifiers
--
-- The roll is shown in the inventory and stays with the bag: thrown and picked
-- up again, it is the same bag. A modifier works while the bag is in your
-- hands or in your inventory:
--
--   runner       you can run while you carry it (bags you cannot run with)
--   nimble       no jump penalty while you carry it
--   light        half the slowdown the bag costs
--   compact      takes 2x1 cells instead of 2x2
--   discreet     guards do not notice it once thrown (host or offline)
--   long_throw   thrown 50% further
--   quick_hands  no wait before you can pick up a bag after throwing it
--   padded       15% less damage taken while you carry it
--   stackable    up to 3 more bags of the same loot (any quality) ride with
--                it in its place; each keeps its own roll (data.extra)
--
-- The quality is your own: other players roll their own when they pick the
-- bag up. Off with restoration-mod (vanilla only, like the skill rework).
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local LQ = PDTI.LootQuality or {}
PDTI.LootQuality = LQ

LQ.TIERS = {
    { id = "standard", name = "Standard", tag = nil, chance = 0.80, value = 1, mods = 0 },
    { id = "high", name = "High quality", tag = "HQ", chance = 0.17, value = 2, mods = 1 },
    { id = "exceptional", name = "Exceptional", tag = "EX", chance = 0.03, value = 4, mods = 2 }
}

LQ.MODS = {
    runner = { name = "Runner", text = "you can run while carrying it" },
    nimble = { name = "Nimble", text = "no jump penalty while carrying it" },
    light = { name = "Light", text = "half the slowdown" },
    compact = { name = "Compact", text = "takes 2x1 cells" },
    discreet = { name = "Discreet", text = "guards do not notice it once thrown" },
    long_throw = { name = "Balanced", text = "thrown 50% further" },
    quick_hands = { name = "Quick hands", text = "no wait to pick up a bag after throwing it" },
    padded = { name = "Padded", text = "15% less damage taken while you carry it" },
    stackable = { name = "Stackable", text = "3 more bags of this loot fit in its place" }
}
-- The order modifiers are rolled from (and shown in).
LQ.MOD_ORDER = { "runner", "nimble", "light", "compact", "discreet", "long_throw", "quick_hands", "padded", "stackable" }

LQ.LIGHT_SHARE = 0.5   -- "light": the share of the slowdown left
LQ.THROW_MUL = 1.5     -- "long_throw"
LQ.DAMAGE_MUL = 0.85   -- "padded"
LQ.STACK = 4           -- "stackable"
LQ.COMPACT_W, LQ.COMPACT_H = 2, 1
LQ.HINT_TIME = 5       -- seconds the "High quality ..." hint stays
-- The outline of a thrown bag by quality (r, g, b): High blue, Exceptional gold.
LQ.OUTLINE = { [2] = { 0.25, 0.55, 1.0 }, [3] = { 1.0, 0.75, 0.1 } }

-- Tests replace it: returns a number in [0, 1).
LQ.random = function() return math.random() end

local log = PDTI.Logger("PDTI LOOT")

function LQ.Enabled()
    return rawget(_G, "restoration") == nil
end

------------------------------------------------------------- the roll

local function carry_type(carry_id)
    local carry = rawget(_G, "tweak_data") and tweak_data.carry
    local bag = carry and carry_id and carry[carry_id]
    return bag and bag.type and carry.types and carry.types[bag.type] or nil
end

-- Which modifiers can this bag have? Running only matters for a bag you
-- cannot run with, jumping only for one that weighs on the jump.
function LQ.Eligible(carry_id)
    local class = carry_type(carry_id)
    local out = {}
    for _, id in ipairs(LQ.MOD_ORDER) do
        local ok = true
        if id == "runner" then ok = class ~= nil and class.can_run == false end
        if id == "nimble" then ok = class ~= nil and (tonumber(class.jump_modifier) or 1) < 1 end
        if ok then out[#out + 1] = id end
    end
    return out
end

-- The chance of each tier (Bonnie's room raises them, perks.lua).
function LQ.Chances()
    local s, h, e = LQ.TIERS[1].chance, LQ.TIERS[2].chance, LQ.TIERS[3].chance
    local perks = PDTI.Perks
    if perks and perks.QualityChances then s, h, e = perks.QualityChances(h, e) end
    return { s, h, e }
end

-- Rolls a bag: { quality = 1..3, mods = { ids } }.
function LQ.Roll(carry_id, min_quality)
    local r = LQ.random()
    local chances = LQ.Chances()
    local quality, acc = #LQ.TIERS, 0
    for i in ipairs(LQ.TIERS) do
        acc = acc + chances[i]
        if r < acc then quality = i break end
    end
    if tonumber(min_quality) and quality < min_quality then quality = math.min(#LQ.TIERS, min_quality) end
    local pool = LQ.Eligible(carry_id)
    local mods = {}
    for _ = 1, math.min(LQ.TIERS[quality].mods, #pool) do
        local i = math.min(#pool, math.floor(LQ.random() * #pool) + 1)
        mods[#mods + 1] = table.remove(pool, i)
    end
    return { quality = quality, mods = LQ.Sorted(mods) }
end

-- The modifiers in their fixed order: two bags with the same modifiers have
-- the same data (and stack).
local RANK = {}
for i, id in ipairs(LQ.MOD_ORDER) do RANK[id] = i end
function LQ.Sorted(mods)
    local out = {}
    for _, id in ipairs(mods or {}) do if RANK[id] then out[#out + 1] = id end end
    table.sort(out, function(a, b) return RANK[a] < RANK[b] end)
    return out
end

-- Writes a roll into a bag item's data (item data holds only plain values,
-- so the modifiers are one comma-separated string).
function LQ.Apply(data, info)
    if type(data) ~= "table" or type(info) ~= "table" then return data end
    local mods = LQ.Sorted(info.mods)
    data.quality = info.quality or 1
    data.mods = table.concat(mods, ",")
    data.w, data.h, data.max_stack = nil, nil, nil
    for _, id in ipairs(mods) do
        if id == "compact" then data.w, data.h = LQ.COMPACT_W, LQ.COMPACT_H end
        if id == "stackable" then data.max_stack = LQ.STACK end
    end
    return data
end

-- A roll as text ("2:light,padded"), and back. The bags riding on a
-- Stackable bag are kept as such texts in data.extra, separated by ";".
function LQ.EncodeRoll(info)
    if type(info) ~= "table" then return "1:" end
    return tostring(math.floor(tonumber(info.quality) or 1)) .. ":" .. table.concat(LQ.Sorted(info.mods), ",")
end

function LQ.DecodeRoll(text)
    local q, mods = tostring(text or ""):match("^(%d+):(.*)$")
    local info = { quality = math.max(1, math.min(3, tonumber(q) or 1)), mods = {} }
    for id in tostring(mods or ""):gmatch("[^,]+") do info.mods[#info.mods + 1] = id end
    return info
end

-- The rolls of the bags riding on a stack (not its own), oldest first.
function LQ.ExtraRolls(data)
    local out = {}
    if type(data) ~= "table" or type(data.extra) ~= "string" then return out end
    for part in data.extra:gmatch("[^;]+") do out[#out + 1] = LQ.DecodeRoll(part) end
    return out
end

-- Every bag in an item of `amount` bags: its own roll first, then the ones
-- riding on it (a stack made before 0.35.2 has copies of its own roll).
function LQ.StackRolls(data, amount)
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    local own = LQ.InfoOf(data)
    local out = { own }
    local extra = LQ.ExtraRolls(data)
    for i = 2, amount do out[i] = extra[i - 1] or own end
    return out
end

-- The roll a bag item carries, or nil.
function LQ.InfoOf(data)
    if type(data) ~= "table" or not tonumber(data.quality) then return nil end
    local mods = {}
    for id in tostring(data.mods or ""):gmatch("[^,]+") do mods[#mods + 1] = id end
    return { quality = math.floor(tonumber(data.quality)), mods = mods }
end

-- Does the bag have this modifier? (No tables: called every frame.)
function LQ.Has(data, mod)
    if type(data) ~= "table" or type(data.mods) ~= "string" or data.mods == "" then return false end
    local s = "," .. data.mods .. ","
    return s:find("," .. mod .. ",", 1, true) ~= nil
end

function LQ.Tier(data)
    local q = type(data) == "table" and tonumber(data.quality) or nil
    return q and LQ.TIERS[math.floor(q)] or nil
end

-- The value multiplier of the bag's quality.
function LQ.ValueMul(data)
    local tier = LQ.Tier(data)
    return tier and tier.value or 1
end

local function carry_name(carry_id)
    local carry = rawget(_G, "tweak_data") and tweak_data.carry and tweak_data.carry[carry_id]
    local name_id = carry and carry.name_id
    local loc = rawget(_G, "managers") and managers.localization
    if name_id and loc then
        local ok, text = pcall(loc.text, loc, name_id)
        if ok and type(text) == "string" and text ~= "" and not text:find("ERROR", 1, true) then return text end
    end
    return tostring(carry_id or "Loot")
end
LQ.CarryName = carry_name

-- "Gold, High quality: Runner (...)" for the screen.
function LQ.Describe(data)
    if type(data) ~= "table" then return "Loot Bag" end
    local text = carry_name(data.carry_id)
    local tier = LQ.Tier(data)
    if tier then text = text .. ", " .. tier.name end
    local info = LQ.InfoOf(data)
    if info and #info.mods > 0 then
        local names = {}
        for _, id in ipairs(info.mods) do
            local m = LQ.MODS[id]
            names[#names + 1] = m and (m.name .. " (" .. m.text .. ")") or id
        end
        text = text .. ": " .. table.concat(names, ", ")
    end
    -- The bags riding on a Stackable bag.
    local extra = LQ.ExtraRolls(data)
    if #extra > 0 then
        local counts = { 0, 0, 0 }
        for _, r in ipairs(extra) do counts[r.quality] = counts[r.quality] + 1 end
        local parts = {}
        for q = 3, 1, -1 do
            if counts[q] > 0 then parts[#parts + 1] = counts[q] .. " " .. LQ.TIERS[q].name end
        end
        text = text .. "; with " .. table.concat(parts, ", ")
    end
    return text
end

------------------------------------------- following the bag in the world

-- A bag picked up from the world brings its roll here until the inventory
-- takes it (Loot.Tick); a thrown bag takes its roll onto the world unit.
local runtime = { pickup = nil, dropping = nil, hooks = {} }
LQ._runtime = runtime

-- The roll for a bag that comes into your hands now: the one it had in the
-- world, or a new one. Returns info, is_new.
function LQ.ForPickup(carry_id)
    local p = runtime.pickup
    runtime.pickup = nil
    -- A bag you threw: the same bag, its roll (you know it: no hint).
    if p and p.carry_id == carry_id and p.info then return p.info, false, true end
    local info, new = LQ.Roll(carry_id), true
    -- A High roll from a contract (market.lua): this bag is at least High.
    local market = PDTI.Market
    if info.quality < 2 and market and market.TakeHighRoll and market.TakeHighRoll() then
        info, new = LQ.Roll(carry_id, 2), true
    end
    return info, new
end

-- Gives a new bag item its roll (and logs a new one). A bag that already
-- has one keeps it.
function LQ.Stamp(data)
    if not LQ.Enabled() or type(data) ~= "table" or LQ.InfoOf(data) then return data end
    local info, new, held_before = LQ.ForPickup(data.carry_id)
    LQ.Apply(data, info)
    log(string.format("%s %s %s%s", tostring(data.carry_id), new and "rolled" or "picked up:",
        LQ.TIERS[info.quality].name, #info.mods > 0 and (" (" .. table.concat(info.mods, ", ") .. ")") or ""))
    -- A better bag says so on the screen when it comes into your hands.
    -- (Not for a bag you held before: you know it.)
    if info.quality > 1 and not held_before then PDTI.Hint(LQ.Describe(data), LQ.HINT_TIME) end
    return data
end

local function is_hands_bag(_, item)
    return item.item_id == "loot_bag" and type(item.data) == "table" and item.data.active and true or false
end

-- The data of the bag in your hands, or nil.
function LQ.HandsData()
    local _, item = PDTI.FindFirstItem(is_hands_bag)
    return item and item.data or nil
end

function LQ.HandsHas(mod)
    if not LQ.Enabled() then return false end
    return LQ.Has(LQ.HandsData(), mod)
end

local wanted_mod = nil
local function has_wanted(_, item)
    if item.item_id ~= "loot_bag" then return false end
    if LQ.Has(item.data, wanted_mod) then return true end
    local extra = type(item.data) == "table" and item.data.extra
    if type(extra) ~= "string" or extra == "" then return false end
    return (";" .. extra):find("[:,]" .. wanted_mod .. "[,;]") ~= nil or (extra):find("[:,]" .. wanted_mod .. "$") ~= nil
end

-- Is any bag you carry (hands or inventory) one with this modifier?
function LQ.AnyCarried(mod)
    if not LQ.Enabled() then return false end
    wanted_mod = mod
    local _, item = PDTI.FindFirstItem(has_wanted)
    wanted_mod = nil
    return item ~= nil
end

local function local_peer_id()
    local ok, id = pcall(function() return managers.network:session():local_peer():id() end)
    if ok then return id end
    return nil
end

-- Removes the attention a lying bag draws (the game does the same while a
-- bag hangs on a zipline).
local function hide_from_guards(unit)
    local att = unit.attention and unit:attention()
    if not att then return end
    local ids = {}
    for id in pairs(att:attention_data() or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do att:remove_attention(id) end
end
LQ._hide_from_guards = hide_from_guards

-- The outline of a lying bag: a High quality or Exceptional bag is always
-- outlined in its colour (the game outlines a bag only near you); while you
-- look at it, it has the game's "selected" outline.
local ids_contour_color, ids_contour_opacity, outline_colors = nil, nil, {}
local function outline_color(quality)
    local rgb = LQ.OUTLINE[quality]
    local Vector3 = rawget(_G, "Vector3")
    if not rgb or not Vector3 then return nil end
    outline_colors[quality] = outline_colors[quality] or Vector3(rgb[1], rgb[2], rgb[3])
    return outline_colors[quality]
end

local function quality_of_unit(unit)
    local cd = PDTI.CarryExt(unit)
    local info = cd and cd._pdti_quality
    if type(info) == "table" then return info end
    return nil
end
LQ.QualityOfUnit = quality_of_unit

local function paint_outline(ext, quality)
    local color = outline_color(quality)
    if not color then return false end
    ids_contour_color = ids_contour_color or Idstring("contour_color")
    ids_contour_opacity = ids_contour_opacity or Idstring("contour_opacity")
    for _, m in ipairs(ext._materials or {}) do
        m:set_variable(ids_contour_color, color)
        m:set_variable(ids_contour_opacity, 1)
    end
    return true
end

local function make_set_contour(orig)
    return function(self, color, opacity, ...)
        if color ~= "selected_color" and LQ.Enabled() and not (self._tweak_data and self._tweak_data.no_contour)
            and not self._contour_override then
            local info = self._unit and quality_of_unit(self._unit)
            if info and (info.quality or 1) > 1 then
                local ok, painted = pcall(paint_outline, self, info.quality)
                if ok and painted then return end
            end
        end
        return orig(self, color, opacity, ...)
    end
end

-- Outlines a bag that was just thrown (the game sets the outline when the
-- bag becomes interactable; this paints it at once).
function LQ.OutlineUnit(unit)
    local info = quality_of_unit(unit)
    if not info or (info.quality or 1) <= 1 then return false end
    local ok, ext = pcall(function() return unit:interaction() end)
    if not ok or not ext or type(ext.set_contour) ~= "function" then return false end
    ext:set_contour("standard_color", 1)
    return true
end

-- Before the bag in your hands leaves them: remember its roll.
local function before_drop()
    runtime.dropping = nil
    local data = LQ.HandsData()
    local info = LQ.InfoOf(data)
    if not info then return nil end
    runtime.dropping = { carry_id = data.carry_id, info = info, quick = LQ.Has(data, "quick_hands") }
    return runtime.dropping
end

local function make_drop(orig)
    return function(self, ...)
        local d = LQ.Enabled() and before_drop() or nil
        local result = orig(self, ...)
        if d and d.quick then
            -- Quick hands: the next bag can be picked up at once.
            self._carry_blocked_cooldown_t = 0
        end
        return result
    end
end

-- The game makes the thrown bag here (host, offline and every client).
local function make_sync_carry_data(orig)
    return function(self, unit, carry_id, carry_multiplier, dye_initiated, has_dye_pack, dye_value_multiplier,
                    position, dir, throw_level, zipline_unit, peer_id, ...)
        local d = runtime.dropping
        local mine = d ~= nil and d.carry_id == carry_id and peer_id ~= nil and peer_id == local_peer_id()
        if mine then
            runtime.dropping = nil
            local long = false
            for _, id in ipairs(d.info.mods) do if id == "long_throw" then long = true end end
            if long and dir ~= nil and zipline_unit == nil then
                local ok, scaled = pcall(function() return dir * LQ.THROW_MUL end)
                if ok and scaled ~= nil then dir = scaled end
            end
        end
        local result = orig(self, unit, carry_id, carry_multiplier, dye_initiated, has_dye_pack, dye_value_multiplier,
            position, dir, throw_level, zipline_unit, peer_id, ...)
        if mine then
            local cd = PDTI.CarryExt(unit)
            if cd then
                cd._pdti_quality = d.info
                for _, id in ipairs(d.info.mods) do
                    if id == "discreet" then pcall(hide_from_guards, unit) end
                end
                pcall(LQ.OutlineUnit, unit)
            end
        end
        return result
    end
end

-- Picking a bag up: its roll goes with it.
local function make_interact(orig)
    return function(self, player, ...)
        if LQ.Enabled() then
            runtime.pickup = nil
            local cd = PDTI.CarryExt(self._unit)
            local info = cd and cd._pdti_quality
            if type(info) == "table" then
                local ok, id = pcall(cd.carry_id, cd)
                if ok then runtime.pickup = { carry_id = id, info = info } end
            end
        end
        return orig(self, player, ...)
    end
end

local function make_check_run(orig)
    return function(self, ...)
        if LQ.HandsHas("runner") and PlayerCarry.super and PlayerCarry.super._check_action_run then
            return PlayerCarry.super._check_action_run(self, ...)
        end
        return orig(self, ...)
    end
end

local function make_jump(orig)
    return function(self, jump_vec, ...)
        if LQ.HandsHas("nimble") and PlayerCarry.super and PlayerCarry.super._perform_jump then
            return PlayerCarry.super._perform_jump(self, jump_vec, ...)
        end
        return orig(self, jump_vec, ...)
    end
end

local function make_modify_value(orig)
    return function(self, key, value, ...)
        local result = orig(self, key, value, ...)
        if key == "damage_taken" and type(result) == "number" and LQ.AnyCarried("padded") then
            return result * LQ.DAMAGE_MUL
        end
        return result
    end
end

local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(runtime.hooks, "loot_quality", class_name, fn_name, make)
end

-- Every frame (from Loot.Tick): the hooks of classes loaded late.
function LQ.InstallHooks()
    if not LQ.Enabled() then return false end
    local a = wrap("PlayerManager", "drop_carry", make_drop)
    local b = wrap("PlayerManager", "force_drop_carry", make_drop)
    local c = wrap("PlayerManager", "sync_carry_data", make_sync_carry_data)
    local d = wrap("PlayerManager", "modify_value", make_modify_value)
    local e = wrap("CarryInteractionExt", "interact", make_interact)
    local f = wrap("PlayerCarry", "_check_action_run", make_check_run)
    local g = wrap("PlayerCarry", "_perform_jump", make_jump)
    -- CarryInteractionExt inherits set_contour: give the class its own one
    -- that asks the parent class each call (a later hook there still counts).
    local cie = rawget(_G, "CarryInteractionExt")
    if cie and rawget(cie, "set_contour") == nil and cie.super and type(cie.super.set_contour) == "function" then
        cie.set_contour = function(self, ...) return cie.super.set_contour(self, ...) end
    end
    local h = wrap("CarryInteractionExt", "set_contour", make_set_contour)
    return a and b and c and d and e and f and g and h
end

function LQ.Reset()
    runtime.pickup = nil
    runtime.dropping = nil
end
