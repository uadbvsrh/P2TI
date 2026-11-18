-- Ghost: Shinobi and Artful Dodger (SKILLS_REWORK_SPEC.md §7.1, §7.2).
--   Cleaner ace          the body bag case takes 2 cells instead of 4; you can
--                        run with a bagged body, at 70% of the run speed
--   ECM Specialist basic ECM jammers stack 2 to a cell
--   Inner Pockets ace    +2 pocket cells (a third row), with any armour
--   Sneaky Bastard       dodge by your speed, without a cap: 0 standing
--                        still, 10% at the base sprint speed (ace: at the
--                        base run speed), more the faster you go; no longer
--                        by concealment
-- The item parts need the deployables-as-items system, Sneaky Bastard the
-- weight system; without them the vanilla skills stay.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local G = PDTI.GhostSkills or {}
PDTI.GhostSkills = G

G.BODY_RUN = 0.7
-- The dodge at the reference speed; it keeps growing above it (0.27.1).
G.DODGE_MAX = 0.10
G.ECM_STACK = 2
-- The base speeds the dodge is measured against (the game's tweak data).
G.SPRINT_SPEED = 575
G.RUN_SPEED = 350

local function log(message) Skills.log("ghost: " .. tostring(message)) end

local hint = PDTI.Hint

------------------------------------------------------------ the items

-- Before the skills can be read (a save loaded in the menu) the items and
-- the pockets take their skill sizes, so a save is never cut down at load;
-- G.Tidy() puts things right once the skills are known.
local function unknown() return Skills.Known ~= nil and not Skills.Known() end

function G.SmallBodyBags()
    if not Skills.DeployablesOn() then return false end
    return unknown() or Skills.Ace("cleaner")
end

function G.EcmStack()
    if Skills.DeployablesOn() and (unknown() or Skills.Basic("ecm_2x")) then return G.ECM_STACK end
    return 1
end

function G.PocketsBig()
    return unknown() or Skills.Ace("thick_skin")
end
PDTI.PocketsBig = function() return G.PocketsBig() end

local function apply_items()
    local items = PDTI.items or {}
    if items.bodybags_bag then items.bodybags_bag.h = G.SmallBodyBags() and 1 or 2 end
    if items.ecm_jammer then items.ecm_jammer.max_stack = G.EcmStack() end
end
G.ApplyItems = apply_items
apply_items()

-- What no longer fits after a skill change (pockets without the third row,
-- a body bag case grown back, ECM stacks above the limit) goes where it
-- fits; what fits nowhere stays where it is.
local TO = { "backpack", "rig", "rig_2", "rig_3", "pockets" }

local function move_anywhere(from, item)
    for _, name in ipairs(TO) do
        local x, y, rotated = PDTI.FindFreeSpace(name, item, true)
        if x ~= nil and PDTI.MoveItem(from, item.instance_id, name, x, y, rotated) then return true end
    end
    return false
end

local function split_anywhere(from, item, amount)
    for _, name in ipairs(TO) do
        local x, y, rotated = PDTI.FindFreeSpace(name, { item_id = item.item_id, data = item.data }, true)
        if x ~= nil then
            if name == from then
                if PDTI.SplitStack(from, item.instance_id, amount, x, y, rotated) then return true end
            else
                local ok = PDTI.AddItem(name, item.item_id, x, y, rotated, amount, item.data)
                if ok then
                    PDTI.RemoveItem(from, item.instance_id, amount)
                    return true
                end
            end
        end
    end
    return false
end

function G.Tidy()
    apply_items()
    if not PDTI.FindItems or not PDTI.CanPlace then return 0 end
    local fixed, stuck = 0, 0
    for _, entry in ipairs(PDTI.FindItems(function() return true end)) do
        local item, from = entry.item, entry.container
        local def = PDTI.items[item.item_id]
        local limit = def and math.max(1, math.floor(tonumber(def.max_stack) or 1)) or 1
        while (item.amount or 1) > limit do
            local extra = math.min(limit, (item.amount or 1) - limit)
            if not split_anywhere(from, item, extra) then stuck = stuck + 1 break end
            fixed = fixed + 1
        end
        if not PDTI.GUN_SLOTS[from]
            and not PDTI.CanPlace(from, item, item.x, item.y, item.rotated == true, item.instance_id) then
            if move_anywhere(from, item) then fixed = fixed + 1 else stuck = stuck + 1 end
        end
    end
    if stuck > 0 then
        log(stuck .. " item(s) no longer fit and found no room")
        hint("Some items no longer fit where they are; move them")
    end
    return fixed
end

------------------------------------------------------- Cleaner: the body

local function carrying_body(self)
    return self._tweak_data_name == "being"
end

local function body_run() return Skills.Ace("cleaner") end

local function make_PlayerCarry__check_action_run(orig)
    return function(self, ...)
        if body_run() and carrying_body(self) and PlayerCarry.super and PlayerCarry.super._check_action_run then
            return PlayerCarry.super._check_action_run(self, ...)
        end
        return orig(self, ...)
    end
end

local function make_PlayerCarry__get_max_walk_speed(orig)
    return function(self, ...)
        if self._running and body_run() and carrying_body(self)
            and PlayerCarry.super and PlayerCarry.super._get_max_walk_speed then
            local ok, v = pcall(PlayerCarry.super._get_max_walk_speed, self, ...)
            if ok and type(v) == "number" then return v * G.BODY_RUN end
        end
        return orig(self, ...)
    end
end

local function install_carry_hooks()
    Skills.wrap("PlayerCarry", "_check_action_run", make_PlayerCarry__check_action_run, "cleaner")
    Skills.wrap("PlayerCarry", "_get_max_walk_speed", make_PlayerCarry__get_max_walk_speed, "cleaner")
end

-------------------------------------------------------- Sneaky Bastard

local function weight_on()
    local c = PDTI.Carry
    return c ~= nil and c.enabled ~= false
end

local function dodger() return weight_on() and Skills.Basic("jail_diet") end

Skills.Off("player", "detection_risk_add_dodge_chance", dodger)

local function base_speed(name, default)
    local ok, v = pcall(function() return tweak_data.player.movement_state.standard.movement.speed[name] end)
    if ok and type(v) == "number" and v > 0 then return v end
    return default
end

-- The player's speed now (cm/s), 0 when it can't be read.
G.velocity = function()
    local ok, v = pcall(function()
        local st = managers.player:player_unit():movement():current_state()
        local vel = st and st._last_velocity_xy
        if not vel then return 0 end
        if type(vel.length) == "function" then return vel:length() end
        return mvector3.length(vel)
    end)
    if ok and type(v) == "number" then return v end
    return 0
end

function G.DodgeRef()
    if Skills.Ace("jail_diet") then return base_speed("STANDARD_MAX", G.RUN_SPEED) end
    return base_speed("RUNNING_MAX", G.SPRINT_SPEED)
end

function G.VelocityDodge()
    if not dodger() then return 0 end
    local speed = tonumber(G.velocity()) or 0
    -- No cap; only a broken reading (NaN, infinite) gives nothing.
    if speed ~= speed or speed <= 0 or speed == math.huge then return 0 end
    return G.DODGE_MAX * speed / G.DodgeRef()
end

local function make_PlayerManager_skill_dodge_chance(orig)
    return function(self, running, crouching, on_zipline, override_armor, detection_risk, ...)
        local chance = orig(self, running, crouching, on_zipline, override_armor, detection_risk, ...)
        -- The menu's stats pass a detection risk: no speed there.
        if type(chance) ~= "number" or detection_risk ~= nil then return chance end
        return chance + G.VelocityDodge()
    end
end

local function install_dodge_hook()
    Skills.wrap("PlayerManager", "skill_dodge_chance", make_PlayerManager_skill_dodge_chance, "dodger")
end

------------------------------------------------------------ installing

function G.OnHeistStart()
    pcall(G.Tidy)
end

Skills.OnInstall("ghost", function()
    apply_items()
    install_carry_hooks()
    install_dodge_hook()
end)

------------------------------------------------------------ the texts

Skills.Text("cleaner", "BASIC: ##$basic##\n"
    .. "You can carry ##1## more body bag.\n\n"
    .. "ACE: ##$pro##\n"
    .. "You can carry ##1## more body bag. A body bag case takes ##2## inventory cells instead of ##4##. You can run while carrying a bagged body, "
    .. "at ##70%## of your run speed.")
Skills.Text("ecm_2x", "BASIC: ##$basic##\n"
    .. "ECM jammers stack ##2## to an inventory cell.\n\n"
    .. "ACE: ##$pro##\n"
    .. "The ECM jammer and feedback last ##25%## longer. The ECM jammer also delays pager answers.")
Skills.Text("thick_skin", "BASIC: ##$basic##\n"
    .. "Increases the concealment of melee weapons by ##2##.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Your pockets get ##2## more cells, with any armor. Ballistic vests are ##4## more concealable.")
Skills.Text("jail_diet", "BASIC: ##$basic##\n"
    .. "Your dodge chance grows with your speed, without a limit: none standing still, ##10%## at full "
    .. "sprint, more the faster you go. A heavy load slows you, so it costs you dodge.\n\n"
    .. "ACE: ##$pro##\n"
    .. "The dodge grows faster: ##10%## already at running speed, about ##16%## at full sprint.")

return G
