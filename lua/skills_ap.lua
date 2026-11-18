-- Technician, Oppressor: the AP skills (SKILLS_REWORK_SPEC.md §6).
--   Surefire        basic "Stacked Barrier": every AP headshot adds 10
--                   absorption, up to 50; it soaks damage before armour and
--                   health, fades 3 s after the last hit that fed it, then 10 s
--                   of cooldown; ace: up to 60, fades after 4 s, 9 s cooldown
--   Body Expertise  vanilla (body shots with automatic weapons) + AP body
--                   shots feed the barrier: 3 (basic) / 9 (ace)
-- The values are the screen's (10 = 1 in the game's units). LMG penetrator
-- rounds count as AP. With the ammo system off the vanilla skills stay.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local B = PDTI.Barrier or {}
PDTI.Barrier = B

-- In the game's units (the screen shows ten times this).
B.BASIC = { cap = 5.0, fade = 3, cooldown = 10 }
B.ACE = { cap = 6.0, fade = 4, cooldown = 9 }
B.HEAD = 1.0
B.BODY = { 0.3, 0.9 }

-- value, last (the last hit that fed it), cooldown_until
B.state = B.state or { value = 0, last = 0, cooldown_until = 0, told = false }
local state = B.state

local now = PDTI.GameTime
B.now = now

local function ammo_on() return Skills.AmmoOn() end

local function on(id) return function() return ammo_on() and Skills.Basic(id) end end
Skills.Off("player", "automatic_mag_increase", on("fast_fire"))
Skills.Off("player", "ap_bullets", on("fast_fire"))

-- The numbers in force, or nil without either skill.
function B.Params()
    if not ammo_on() then return nil end
    if Skills.Ace("fast_fire") then return B.ACE end
    if Skills.Basic("fast_fire") or Skills.Basic("body_expertise") then return B.BASIC end
    return nil
end

-- The barrier fades after its time; the cooldown follows.
function B.Update()
    local p = B.Params() or B.BASIC
    if state.value > 0 and now() - state.last >= p.fade then
        state.value = 0
        state.cooldown_until = now() + p.cooldown
    end
end

function B.Value()
    B.Update()
    return state.value
end

-- An AP hit: a headshot (Surefire) or a body shot of an automatic weapon
-- (Body Expertise, vanilla's scope: the weapon's added headshot multiplier).
function B.OnApHit(head, wep)
    local p = B.Params()
    if not p then return 0 end
    B.Update()
    if now() < state.cooldown_until then return 0 end
    local gain = 0
    if head then
        if Skills.Basic("fast_fire") then gain = B.HEAD end
    elseif Skills.Basic("body_expertise") then
        local ok, mul = pcall(function() return wep:get_add_head_shot_mul() end)
        if ok and mul then gain = B.BODY[Skills.Ace("body_expertise") and 2 or 1] end
    end
    if gain <= 0 then return 0 end
    local before = state.value
    state.value = math.min(p.cap, state.value + gain)
    state.last = now()
    if before <= 0 and not state.told then
        state.told = true
        PDTI.Hint("Stacked Barrier: absorbs damage")
    end
    return state.value - before
end

-- Soaks damage (game units); returns what is left.
function B.Absorb(damage)
    if type(damage) ~= "number" or damage <= 0 then return damage end
    B.Update()
    if state.value <= 0 then return damage end
    local soak = math.min(state.value, damage)
    state.value = state.value - soak
    return damage - soak
end

function B.Line()
    if not B.Params() then return nil end
    B.Update()
    local t = now()
    if state.value > 0 then
        local p = B.Params()
        return string.format("Barrier: %d (%d s)", math.floor(state.value * 10 + 0.5),
            math.max(0, math.ceil(p.fade - (t - state.last))))
    end
    if t < state.cooldown_until then
        return string.format("Barrier: cooldown %d s", math.ceil(state.cooldown_until - t))
    end
    return nil
end

local function make_PlayerManager_modify_value(orig)
    return function(self, key, value, ...)
        local result = orig(self, key, value, ...)
        if key ~= "damage_taken" or type(result) ~= "number" then return result end
        local left = B.Absorb(result)
        if type(left) == "number" and left > 0 then
            local SK = PDTI.SilentKiller
            if SK and SK.OnDamageTaken then pcall(SK.OnDamageTaken) end
        end
        return left
    end
end

local function install()
    -- The game's "damage_taken" step: after dodge, before armour.
    Skills.wrap("PlayerManager", "modify_value", make_PlayerManager_modify_value, "barrier")
    local Body = PDTI.Body
    if Body and Body.lines then Body.lines.barrier = B.Line end
end

function B.OnHeistStart()
    state.value = 0
    state.last = 0
    state.cooldown_until = 0
    state.told = false
end

Skills.OnInstall("barrier", install)

Skills.Text("fast_fire", "BASIC: ##$basic##\n"
    .. "Stacked Barrier: every headshot with armour piercing rounds gives you ##10## absorption, up to ##50##. "
    .. "Absorption takes damage before your armor and health. It fades ##3## seconds after your last such hit, "
    .. "then it can't build for ##10## seconds.\n\n"
    .. "ACE: ##$pro##\n"
    .. "Up to ##60## absorption; it fades after ##4## seconds and can build again after ##9## seconds.")
Skills.Text("body_expertise", "BASIC: ##$basic##\n"
    .. "Body shots with automatic weapons deal ##30%## of your headshot damage bonus. Armour piercing body shots "
    .. "with them add ##3## absorption to your Stacked Barrier.\n\n"
    .. "ACE: ##$pro##\n"
    .. "##90%## of the headshot bonus, and ##9## absorption per armour piercing body shot.")
