-- Safehouse room bonuses (0.31.0).
--
-- Every rig, backpack and armour class has two room options. The room's
-- tier 2 unlocks its option, tier 3 makes it stronger. In the inventory
-- (before the heist) you pick one option per piece; the choice is saved
-- with the inventory. Other rooms (Bonnie, Scarface, the vault) have a bonus
-- of their own, on from tier 2 and stronger at tier 3, nothing to choose.
--
-- This file loads before inventory.lua: the save is read when that file
-- loads, and a rig row a room added must be there by then, or what is in it
-- would be moved. Nothing here runs the game's code at load time.
--
-- Room tiers: the safehouse manager's tier, or the one seen before (kept in
-- the inventory save, room tiers never go down), whichever is higher. The
-- saved one counts while the safehouse is not loaded yet.
local PDTI = rawget(_G, "PDTI") or {}
_G.PDTI = PDTI

local Perks = PDTI.Perks or {}
PDTI.Perks = Perks

local function log(message)
    if PDTI.Logger then
        Perks.log = Perks.log or PDTI.Logger("PDTI PERKS")
        Perks.log(message)
    end
end

-- The rooms with a bonus. name: the heister (or the room).
Perks.ROOMS = {
    russian = "Dallas", max = "Sangres", spanish = "Chains", wild = "Rust",
    american = "Houston", old_hoxton = "Old Hoxton", sokol = "Sokol", bodhi = "Bodhi",
    clover = "Clover", dragan = "Dragan", german = "Wolf", livingroom = "Living room",
    sydney = "Sydney", jimmy = "Jimmy", jowi = "John Wick", dragon = "Jiro",
    bonnie = "Bonnie", myh = "Duke", terry = "Scarface", joy = "Joy",
    jacket = "Jacket", ecp = "Ethan & Hila", vault = "Vault"
}

-- The pieces with a choice, in the order the inventory shows them. A rig or
-- a backpack piece has the id of that equipment.
Perks.PIECE_ORDER = { "medical_rig", "assault_rig", "general_rig", "small_backpack",
    "medium_backpack", "large_backpack", "light_armour", "heavy_armour" }
Perks.PIECES = {
    medical_rig = { name = "Medical Rig", rooms = { "russian", "max" } },
    assault_rig = { name = "Assault Rig", rooms = { "spanish", "wild" } },
    general_rig = { name = "General Rig", rooms = { "american", "old_hoxton" } },
    small_backpack = { name = "Small Backpack", rooms = { "sokol", "bodhi" } },
    medium_backpack = { name = "Medium Backpack", rooms = { "clover", "dragan" } },
    large_backpack = { name = "Large Backpack", rooms = { "german", "livingroom" } },
    light_armour = { name = "Light armour", rooms = { "sydney", "jimmy" } },
    heavy_armour = { name = "Heavy armour", rooms = { "jowi", "dragon" } }
}

-- What each room gives. piece: the piece it is an option of (nil: a bonus
-- of its own). ready = false: not made yet (shown, cannot be picked).
-- apply(def, tier): changes a copy of the rig or backpack definition.
Perks.OPTIONS = {
    russian = { piece = "medical_rig", title = "Doctor bags",
        t2 = "Placing a doctor bag yourself recharges the self-revive",
        t3 = "Also two self-revives per heist, each uses a doctor bag" },
    max = { piece = "medical_rig", title = "First aid kits",
        t2 = "The self-revive uses a first aid kit instead of a doctor bag (it heals like a kit)",
        t3 = "Also: a first aid kit goes down in half the time" },
    spanish = { piece = "assault_rig", title = "More ammunition",
        -- Tier 3 grows a column, not a row: a fifth row would not fit the
        -- inventory window at 720p.
        t2 = "+1 ammunition row (7x4)", t3 = "Ammunition part 8x4",
        apply = function(def, tier)
            local s = def.sections and def.sections[1]
            if s then
                s.h = (tonumber(s.h) or 3) + 1
                if tier >= 3 then s.w = (tonumber(s.w) or 7) + 1 end
            end
        end },
    wild = { piece = "assault_rig", title = "Ammo bags",
        t2 = "Each ammo bag placed from the rig has +1 use",
        t3 = "Also: the \"Refill from the rig's ammo bag\" key takes a use without placing the bag" },
    american = { piece = "general_rig", title = "Concealment",
        t2 = "What is in the rig costs half concealment", t3 = "What is in the rig costs no concealment" },
    old_hoxton = { piece = "general_rig", title = "Space",
        t2 = "+1 column (4x6)", t3 = "+2 columns (5x6)",
        apply = function(def, tier)
            local s = def.sections and def.sections[1] or def
            s.w = (tonumber(s.w) or 3) + (tier - 1)
        end },
    sokol = { piece = "small_backpack", title = "Speed",
        t2 = "Speed bonus 25% -> 35%", t3 = "Speed bonus 25% -> 45%",
        apply = function(def, tier)
            def.speed_bonus = (tonumber(def.speed_bonus) or 0.25) + 0.10 * (tier - 1)
        end },
    bodhi = { piece = "small_backpack", title = "Space",
        t2 = "+1 row (5x3), up to 20 kg", t3 = "6x3, up to 24 kg",
        apply = function(def, tier)
            def.h = 3
            def.max_weight = 20
            if tier >= 3 then def.w = 6; def.max_weight = 24 end
        end },
    clover = { piece = "medium_backpack", title = "Loot slots",
        t2 = "A 2x2 slot for a loot bag next to the backpack", t3 = "Two of them (2x4)" },
    dragan = { piece = "medium_backpack", title = "Space and weight",
        t2 = "+1 row (5x5)", t3 = "+1 row (5x5), up to 35 kg",
        apply = function(def, tier)
            def.h = (tonumber(def.h) or 4) + 1
            if tier >= 3 then def.max_weight = 35 end
        end },
    german = { piece = "large_backpack", title = "Load",
        t2 = "Weight and loot slow you 40% less", t3 = "Weight and loot slow you 50% less",
        apply = function(def, tier)
            def.penalty_scale = tier >= 3 and 0.5 or 0.6
        end },
    livingroom = { piece = "large_backpack", title = "Low profile",
        t2 = "Enemies focus you 25% more (not 50%)", t3 = "Enemies focus you no more than usual",
        apply = function(def, tier)
            def.threat = tier >= 3 and 1 or 1.25
        end },
    sydney = { piece = "light_armour", title = "Faster regeneration",
        t2 = "Starts regenerating 25% sooner after a hit", t3 = "Starts regenerating 50% sooner after a hit" },
    jimmy = { piece = "light_armour", title = "Adrenaline",
        t2 = "When it breaks, hits deal half damage for 2 s", t3 = "When it breaks, hits deal half damage for 4 s" },
    jowi = { piece = "heavy_armour", title = "Fast plates",
        t2 = "A plate goes in in 1.5 s (not 3 s)", t3 = "A plate goes in in 1 s" },
    dragon = { piece = "heavy_armour", title = "Steady plates",
        t2 = "Firing does not stop a plate going in",
        t3 = "Firing does not stop it, and you move at full speed while inserting" },

    bonnie = { title = "Quality rolls",
        t2 = "High quality chance 17% -> 25%", t3 = "Also Exceptional chance 3% -> 6%" },
    terry = { title = "Sell-now",
        t2 = "Selling right after a heist pays 65% (not 50%)", t3 = "Selling right after a heist pays 75%" },
    vault = { title = "Stash",
        t2 = "+4 bag places in the stash", t3 = "+8 bag places in the stash" },
    myh = { title = "Appraisal", ready = false,
        t2 = "See a bag's quality before picking it up",
        t3 = "Also see its modifiers, and reroll one bag per heist" },
    joy = { title = "Hacking",
        t2 = "Timed hacks (computers, laptops, hacking devices) run 25% faster",
        t3 = "Also: once per heist a keycard you use is not used up" },
    jacket = { title = "Melee",
        t2 = "A melee attack charges 50% faster",
        t3 = "Also: a melee kill heals your most hurt body part by 15% of its max" },
    ecp = { title = "The market",
        t2 = "+1 contract offer a day", t3 = "Also: one loot type a day sells for +25% (shown in the Market tab)" }
}

-- Heavy armour ids (as Armour.HEAVY; that file loads later).
local HEAVY = { level_5 = true, level_6 = true, level_7 = true }

------------------------------------------------------------- the state

-- The perk part of an inventory state (its perks and room_tiers), or the
-- current inventory's.
local function perk_state(st)
    if st then return st end
    if type(PDTI.PerkState) == "function" then return PDTI.PerkState() end
    return nil
end

local function safehouse()
    local m = rawget(_G, "managers")
    local cs = m and m.custom_safehouse
    if type(cs) ~= "table" and type(cs) ~= "userdata" then return nil end
    if type(cs.get_room_current_tier) ~= "function" then return nil end
    -- Before the safehouse manager has its data, asking it would fail.
    local g = cs._global
    if type(g) ~= "table" or type(g.rooms) ~= "table" then return nil end
    return cs
end

-- The game's tier of a room (nil when it cannot be read now).
function Perks.LiveTier(room)
    local cs = safehouse()
    if not cs then return nil end
    local t = cs:get_room_current_tier(room)
    if type(t) == "number" then return t end
    return nil
end

-- The tier of a room: the game's, or the one seen before.
function Perks.Tier(room, st)
    st = perk_state(st)
    local saved = st and type(st.room_tiers) == "table" and tonumber(st.room_tiers[room]) or 0
    return math.max(1, Perks.LiveTier(room) or 0, saved)
end

-- Every room's tier as the game has it now, for the save (nil: unknown).
function Perks.LiveTiers()
    if not safehouse() then return nil end
    local out = {}
    for room in pairs(Perks.ROOMS) do
        local t = Perks.LiveTier(room)
        if t then out[room] = t end
    end
    return out
end

-- Remembers the rooms' tiers in the inventory save (the save keeps them
-- for when the safehouse is not loaded yet).
function Perks.Refresh()
    local tiers = Perks.LiveTiers()
    if tiers and type(PDTI.NoteRoomTiers) == "function" then return PDTI.NoteRoomTiers(tiers) end
    return false
end

-- Is the room's option made, and is the room at tier 2 or more.
function Perks.Unlocked(room, st)
    local o = Perks.OPTIONS[room]
    return o ~= nil and o.ready ~= false and Perks.Tier(room, st) >= 2
end

-- The option chosen for a piece and its tier, when it works now.
function Perks.Active(piece, st)
    st = perk_state(st)
    local room = st and type(st.perks) == "table" and st.perks[piece]
    if type(room) ~= "string" then return nil, 0 end
    local o = Perks.OPTIONS[room]
    if not o or o.piece ~= piece or not Perks.Unlocked(room, st) then return nil, 0 end
    return room, math.min(3, Perks.Tier(room, st))
end

-- Is the piece worn now (the rig, the backpack, or the armour class)?
function Perks.Worn(piece, st)
    if piece == "light_armour" or piece == "heavy_armour" then return Perks.ArmourPiece() == piece end
    st = perk_state(st)
    local eq = st and st.equipment
    if type(eq) ~= "table" then return false end
    return eq.rig == piece or eq.backpack == piece
end

-- Is this room's bonus in use: its tier, or 0. An option counts only while
-- its piece is worn.
function Perks.Level(room, st)
    local o = Perks.OPTIONS[room]
    if not o then return 0 end
    if not o.piece then
        if o.ready == false then return 0 end
        local t = math.min(3, Perks.Tier(room, st))
        return t >= 2 and t or 0
    end
    if not Perks.Worn(o.piece, st) then return 0 end
    local active, tier = Perks.Active(o.piece, st)
    if active == room then return tier end
    return 0
end

-- "light_armour" or "heavy_armour" for the equipped armour.
function Perks.ArmourPiece()
    local m = rawget(_G, "managers")
    local bm = m and m.blackmarket
    local id = nil
    if bm and type(bm.equipped_armor) == "function" then id = bm:equipped_armor(true, true) end
    if type(id) ~= "string" then return nil end
    return HEAVY[id] and "heavy_armour" or "light_armour"
end

-- The line for an option at a tier: "Wolf (tier 2): ...".
function Perks.Text(room, tier)
    local o = Perks.OPTIONS[room]
    if not o then return "" end
    return string.format("%s (tier %d): %s", Perks.ROOMS[room] or room, tier, tier >= 3 and o.t3 or o.t2)
end

------------------------------------------------------------- equipment

local function copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = copy(v) end
    return out
end

local cache = setmetatable({}, { __mode = "k" })

-- The rig or backpack definition with its room option on (the same table
-- when there is none). Cached per definition, option and tier.
function Perks.Equipment(id, def, st)
    if type(def) ~= "table" then return def end
    local room, tier = Perks.Active(id, st)
    if not room then return def end
    local o = Perks.OPTIONS[room]
    if type(o.apply) ~= "function" then return def end
    local by_def = cache[def]
    if not by_def then by_def = {}; cache[def] = by_def end
    local key = room .. tier
    local out = by_def[key]
    if out then return out end
    out = copy(def)
    o.apply(out, tier)
    by_def[key] = out
    return out
end

------------------------------------------------------------- bonuses

-- Bonnie: the quality chances (standard, high, exceptional).
function Perks.QualityChances(high, exceptional)
    local t = Perks.Level("bonnie")
    if t >= 2 then high = math.max(high, 0.25) end
    if t >= 3 then exceptional = math.max(exceptional, 0.06) end
    return 1 - high - exceptional, high, exceptional
end

-- Scarface: the share sell-now pays.
function Perks.SellNowShare(base)
    local t = Perks.Level("terry")
    if t >= 3 then return math.max(base, 0.75) end
    if t >= 2 then return math.max(base, 0.65) end
    return base
end

-- The vault: extra stash cells (bag_cells: the cells one bag takes).
function Perks.StashCells(bag_cells)
    local t = Perks.Level("vault")
    if t >= 3 then return 8 * bag_cells end
    if t >= 2 then return 4 * bag_cells end
    return 0
end

-- John Wick: seconds to insert a plate.
function Perks.PlateTime(base)
    local t = Perks.Level("jowi")
    if t >= 3 then return 1 end
    if t >= 2 then return 1.5 end
    return base
end

-- Jiro: firing does not stop a plate (tier 2), full speed while inserting
-- (tier 3).
function Perks.PlateKeepsFiring() return Perks.Level("dragon") >= 2 end
function Perks.PlateFullSpeed() return Perks.Level("dragon") >= 3 end

-- Sydney: the light armour regeneration delay multiplier.
function Perks.RegenMultiplier()
    if Perks.ArmourPiece() ~= "light_armour" then return 1 end
    local t = Perks.Level("sydney")
    if t >= 3 then return 0.5 end
    if t >= 2 then return 0.75 end
    return 1
end

-- Jimmy: seconds of half damage after the light armour breaks.
function Perks.AdrenalineTime()
    local t = Perks.Level("jimmy")
    if t >= 3 then return 4 end
    if t >= 2 then return 2 end
    return 0
end
Perks.ADRENALINE_DAMAGE = 0.5

-- Dallas: self-revives per heist, and whether placing a doctor bag gives one
-- back.
function Perks.ReviveCount()
    return Perks.Level("russian") >= 3 and 2 or 1
end
function Perks.BagRecharges() return Perks.Level("russian") >= 2 end

-- Sangres: the item the self-revive uses, whether it heals every part to
-- full (a doctor bag) and the first aid kit's deploy time factor.
function Perks.ReviveItem()
    if Perks.Level("max") >= 2 then return "first_aid_kit", false end
    return "doctor_bag", true
end
function Perks.FakTimeFactor() return Perks.Level("max") >= 3 and 0.5 or 1 end

-- Rust: extra uses of an ammo bag placed from the rig.
function Perks.BagExtraUses(container)
    if type(container) ~= "string" or not container:find("^rig") then return 0 end
    return Perks.Level("wild") >= 2 and 1 or 0
end
function Perks.RigRefillOn() return Perks.Level("wild") >= 3 end

-- Houston: the share of the general rig's weight concealment does not see.
function Perks.RigConcealRelief()
    local t = Perks.Level("american")
    if t >= 3 then return 1 end
    if t >= 2 then return 0.5 end
    return 0
end

-- Clover: the loot slots next to the medium backpack (nil: none).
Perks.LOOT_SLOTS = {
    [2] = { w = 2, h = 2, max_weight = 200, name = "Loot slots", items = { loot_bag = true } },
    [3] = { w = 2, h = 4, max_weight = 200, name = "Loot slots", items = { loot_bag = true } }
}
function Perks.LootSlot(st)
    local t = Perks.Level("clover", st)
    if t < 2 then return nil end
    return Perks.LOOT_SLOTS[math.min(3, t)]
end

-- Joy: the timer factor of hacks (not drills or saws), and the keycard.
Perks.HACK_FACTOR = 0.75
Perks.KEYCARD = "bank_manager_key"
function Perks.HackFactor() return Perks.Level("joy") >= 2 and Perks.HACK_FACTOR or 1 end
Perks.keycard_cloned = false
function Perks.KeycardClone(name)
    if name ~= Perks.KEYCARD or Perks.keycard_cloned or Perks.Level("joy") < 3 then return false end
    Perks.keycard_cloned = true
    log("Joy: the keycard was not used up (once per heist)")
    if PDTI.Hint then PDTI.Hint("Joy's clone: your keycard was not used up (once per heist)", 4) end
    return true
end

-- Jacket: the melee charge (the share of the charge reached is multiplied),
-- and the heal of a melee kill.
Perks.MELEE_CHARGE = 1.5
Perks.MELEE_KILL_HEAL = 0.15
function Perks.MeleeChargeFactor() return Perks.Level("jacket") >= 2 and Perks.MELEE_CHARGE or 1 end

-- The most hurt part that can be healed (not black, not full), or nil.
function Perks.MostHurtPart()
    local Body = PDTI.Body
    if not (Body and Body.Enabled and Body.Enabled()) then return nil end
    local best, best_frac
    for _, p in ipairs(Body.PARTS) do
        local f = Body.Frac(p.id)
        if not Body.IsBlack(p.id) and f < 0.999 and (best_frac == nil or f < best_frac) then
            best, best_frac = p.id, f
        end
    end
    return best
end

function Perks.OnMeleeKill()
    if Perks.Level("jacket") < 3 then return 0 end
    local id = Perks.MostHurtPart()
    if not id then return 0 end
    local Body = PDTI.Body
    local healed = Body.HealPart(id, Body.PartMax(id) * Perks.MELEE_KILL_HEAL)
    if healed > 0 then log(string.format("Jacket: a melee kill healed %s by %.1f", id, healed * 10)) end
    return healed
end

------------------------------------------------------------- Rust's refill

-- How many uses a full ammo bag of yours has (the game's base and your
-- upgrades), plus Rust's.
function Perks.BagUses()
    local base = 4
    local td = rawget(_G, "tweak_data")
    if td and td.upgrades and tonumber(td.upgrades.ammo_bag_base) then base = tonumber(td.upgrades.ammo_bag_base) end
    local m = rawget(_G, "managers")
    local pm = m and m.player
    if pm and type(pm.upgrade_value) == "function" then
        local inc = pm:upgrade_value("ammo_bag", "ammo_increase", 0)
        if type(inc) == "number" then base = base + inc end
    end
    return base + Perks.BagExtraUses("rig")
end

-- The guns of the player: { base, ... }.
local function player_guns()
    local unit = PDTI.PlayerUnit and PDTI.PlayerUnit()
    if unit == nil or type(unit.inventory) ~= "function" then return {} end
    local inv = unit:inventory()
    if not inv or type(inv.available_selections) ~= "function" then return {} end
    local out = {}
    for _, sel in pairs(inv:available_selections() or {}) do
        local u = sel and sel.unit
        local base = u and u:base()
        if base and type(base.add_ammo_from_bag) == "function" then out[#out + 1] = base end
    end
    return out
end

-- The key: one ammo bag in the rig refills the guns as if you used it where
-- it stood. Returns true when ammunition was taken.
function Perks.RigBagRefill()
    if not Perks.RigRefillOn() then
        if PDTI.Hint then PDTI.Hint("Needs Rust's room at tier 3, picked for the Assault Rig", 3) end
        return false
    end
    local found
    for _, entry in ipairs(PDTI.FindItems(function(c, item) return c:find("^rig") and item.item_id == "ammo_bag" end)) do
        found = entry
        break
    end
    if not found then
        if PDTI.Hint then PDTI.Hint("No ammo bag in your rig", 3) end
        return false
    end
    local item = found.item
    local left = tonumber(item.data and item.data.uses) or Perks.BagUses()
    local taken = 0
    for _, gun in ipairs(player_guns()) do
        if left <= 0 then break end
        local took = tonumber(gun:add_ammo_from_bag(left)) or 0
        took = math.max(0, math.min(left, took))
        taken = taken + took
        left = left - took
    end
    if taken <= 0 then
        if PDTI.Hint then PDTI.Hint("Your ammunition is full", 2) end
        return false
    end
    if left <= 1e-3 then
        PDTI.EditItems({ remove = { { container = found.container, instance_id = item.instance_id } } })
        log("Rust: refilled from the rig's ammo bag, it is empty now")
    else
        PDTI.EditItems({ update = { { container = found.container, instance_id = item.instance_id,
            data = { uses = math.floor(left * 100 + 0.5) / 100 } } } })
        log(string.format("Rust: refilled from the rig's ammo bag, %.2f use(s) left", left))
    end
    if PDTI.Hint then PDTI.Hint(string.format("Refilled from the rig's ammo bag (%.1f use(s) left)", math.max(0, left)), 3) end
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    return true
end

------------------------------------------------------------- the menu

-- For the inventory screen: the options of a piece.
-- { room, name, title, tier, unlocked, ready, chosen, text }
function Perks.Choices(piece, st)
    local p = Perks.PIECES[piece]
    if not p then return {} end
    st = perk_state(st)
    local chosen = st and type(st.perks) == "table" and st.perks[piece]
    local out = {}
    for _, room in ipairs(p.rooms) do
        local o = Perks.OPTIONS[room]
        local tier = math.min(3, Perks.Tier(room, st))
        local ready = o.ready ~= false
        local text
        if not ready then
            text = string.format("%s: %s (not made yet)", Perks.ROOMS[room], o.t2)
        elseif tier >= 2 then
            text = Perks.Text(room, tier)
        else
            text = string.format("%s: %s (from tier 2)", Perks.ROOMS[room], o.t2)
        end
        out[#out + 1] = {
            room = room, name = Perks.ROOMS[room], title = o.title, tier = tier,
            ready = ready, unlocked = ready and tier >= 2, chosen = chosen == room, text = text
        }
    end
    return out
end

-- Why an option cannot be picked (nil when it can).
function Perks.WhyLocked(piece, room, st)
    local p = Perks.PIECES[piece]
    local o = Perks.OPTIONS[room]
    if not p or not o or o.piece ~= piece then return "That room has no bonus for this" end
    if o.ready == false then return (Perks.ROOMS[room] or room) .. "'s bonus is not made yet" end
    if Perks.Tier(room, st) < 2 then
        return string.format("Upgrade %s's room to tier 2 first", Perks.ROOMS[room] or room)
    end
    return nil
end

-- The lines a room's menu shows about its bonus.
function Perks.RoomLines(room, tier)
    local o = Perks.OPTIONS[room]
    if not o then return {} end
    local lines = {}
    local head = "Bonus: " .. o.title
    if o.piece then head = head .. " (" .. Perks.PIECES[o.piece].name .. ", pick it in the inventory)" end
    if o.ready == false then head = head .. " - not made yet" end
    lines[#lines + 1] = head
    lines[#lines + 1] = (tier >= 2 and "> " or "  ") .. "Tier 2: " .. o.t2
    lines[#lines + 1] = (tier >= 3 and "> " or "  ") .. "Tier 3: " .. o.t3
    return lines
end

------------------------------------------------------------- hooks

Perks.hooks = Perks.hooks or {}

local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(Perks.hooks, "perks", class_name, fn_name, make)
end

-- Jimmy: when the light armour breaks, half damage until this time.
Perks.adrenaline_until = nil
Perks.armour_was_up = false

local function now()
    if PDTI.AppTime then return PDTI.AppTime() end
    return os.clock()
end

-- Every frame of a heist (with the player's damage extension): sees the
-- light armour break.
function Perks.Tick(pd)
    if not pd or type(pd.get_real_armor) ~= "function" then return end
    local armour = pd:get_real_armor()
    if type(armour) ~= "number" then return end
    if armour > 0 then Perks.armour_was_up = true; return end
    if not Perks.armour_was_up then return end
    Perks.armour_was_up = false
    if Perks.ArmourPiece() ~= "light_armour" then return end
    local time = Perks.AdrenalineTime()
    if time > 0 then
        Perks.adrenaline_until = now() + time
        log(string.format("light armour broke: half damage for %d s", time))
    end
end

function Perks.DamageMultiplier()
    if Perks.adrenaline_until and now() < Perks.adrenaline_until then return Perks.ADRENALINE_DAMAGE end
    return 1
end

-- Joy: a timer that is not a drill's or a saw's.
local function is_hack(timer_gui)
    local unit = timer_gui and timer_gui._unit
    if unit == nil or type(unit.base) ~= "function" then return true end
    local base = unit:base()
    if type(base) ~= "table" then return true end
    return not (base.is_drill or base.is_saw)
end

function Perks.InstallHooks()
    if not PDTI.Wrap then return end
    wrap("TimerGui", "_start", function(orig)
        return function(self, ...)
            if not self._pdti_joy and is_hack(self) then
                local f = Perks.HackFactor()
                if f ~= 1 then
                    self._pdti_joy = f
                    self._timer_multiplier = (self._timer_multiplier or 1) * f
                    log("Joy: a hack runs " .. math.floor((1 - f) * 100 + 0.5) .. "% faster")
                end
            end
            return orig(self, ...)
        end
    end)
    wrap("TimerGui", "set_timer_multiplier", function(orig)
        return function(self, multiplier, ...)
            if self._pdti_joy and type(multiplier) == "number" then multiplier = multiplier * self._pdti_joy end
            return orig(self, multiplier, ...)
        end
    end)
    wrap("PlayerStandard", "_get_melee_charge_lerp_value", function(orig)
        return function(self, ...)
            local v = orig(self, ...)
            local f = Perks.MeleeChargeFactor()
            if f ~= 1 and type(v) == "number" then v = math.min(1, v * f) end
            return v
        end
    end)
    wrap("CopDamage", "damage_melee", function(orig)
        return function(self, attack_data, ...)
            local r = orig(self, attack_data, ...)
            if type(attack_data) == "table" and type(attack_data.result) == "table" and attack_data.result.type == "death"
                and attack_data.attacker_unit ~= nil and PDTI.PlayerUnit and attack_data.attacker_unit == PDTI.PlayerUnit() then
                pcall(Perks.OnMeleeKill)
            end
            return r
        end
    end)
    wrap("PlayerManager", "remove_special", function(orig)
        return function(self, name, ...)
            if Perks.KeycardClone(name) then return end
            return orig(self, name, ...)
        end
    end)
    wrap("PlayerManager", "body_armor_regen_multiplier", function(orig)
        return function(self, ...)
            local m = orig(self, ...)
            if type(m) ~= "number" then return m end
            return m * Perks.RegenMultiplier()
        end
    end)
    wrap("PlayerManager", "damage_reduction_skill_multiplier", function(orig)
        return function(self, ...)
            local m = orig(self, ...)
            if type(m) ~= "number" then return m end
            return m * Perks.DamageMultiplier()
        end
    end)
    -- Room tiers bought in the menu or the safehouse (buying unlocks a
    -- tier, setting it makes it the room's): remember them.
    wrap("CustomSafehouseManager", "set_room_tier", function(orig)
        return function(self, ...)
            local r = orig(self, ...)
            Perks.Refresh()
            return r
        end
    end)
end

function Perks.Reset()
    Perks.adrenaline_until = nil
    Perks.armour_was_up = false
    Perks.keycard_cloned = false
end

-- A heist starts: the once-per-heist bonuses come back.
function Perks.OnHeistStart()
    Perks.Reset()
end

return Perks
