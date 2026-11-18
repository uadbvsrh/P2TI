-- Health per body part.
--
-- The player's health is split into six parts: the head, the body, two arms
-- and two legs. The game's own health is always the sum of the parts, so the
-- health ring, the sync to the other players and every skill that reads or
-- heals health keep working.
--
--   * A hit lands on one part: bullets roll for it (mostly the body, rarely
--     the head), a fall hits a leg, explosions and fire spread over every
--     part. The armour still takes the damage first, as in the game; only
--     what reaches the health reaches the parts.
--   * A part at 0 is black. Damage on a black part, and what is left over
--     when a part goes black, goes on at 75% to the body; when the body is
--     black (or it was the body), to the head.
--   * The head at 0: you go down. When you are revived the head has 1 HP;
--     every other part stays as it was, black parts stay black.
--   * A first aid kit (and every skill that heals) heals the parts that are
--     not black, the most hurt one first. A medic bag heals every part to full, black ones too; so
--     does getting up with the medic bag of the medical rig.
--   * Black arms: more recoil and spread. A black leg: no sprinting, and
--     each one makes you slower. A black body: less stamina.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Body = PDTI.Body or {}
PDTI.Body = Body

-- share: the part's share of the health (Tarkov's HP; the thorax and the
-- stomach are one part). bullet, melee: how likely a hit lands there.
Body.PARTS = {
    { id = "head",  name = "Head",      short = "H",  share = 35,  bullet = 0.06, melee = 0.10 },
    { id = "body",  name = "Body",      short = "B",  share = 155, bullet = 0.42, melee = 0.60 },
    { id = "arm_l", name = "Left arm",  short = "LA", share = 60,  bullet = 0.12, melee = 0.15 },
    { id = "arm_r", name = "Right arm", short = "RA", share = 60,  bullet = 0.12, melee = 0.15 },
    { id = "leg_l", name = "Left leg",  short = "LL", share = 65,  bullet = 0.14, melee = 0 },
    { id = "leg_r", name = "Right leg", short = "RL", share = 65,  bullet = 0.14, melee = 0 },
}

Body.EFFECTS = {
    spread_damage = 0.75,     -- damage on a black part, passed on to the body (or the head)
    revive_head = 0.1,        -- the head after a revive (1 HP on the screen)
    arm_recoil = 1.35,        -- per black arm
    arm_spread = 1.25,        -- per black arm
    leg_speed = 0.85,         -- per black leg
    body_stamina = 0.5,       -- black body
}

-- The roll of a hit; tests replace it.
Body.roll = function() return math.random() end

local TOTAL_SHARE = 0
local BY_ID = {}
for _, p in ipairs(Body.PARTS) do
    TOTAL_SHARE = TOTAL_SHARE + p.share
    BY_ID[p.id] = p
end

-- Each part: a fraction of its own maximum, so a change of the max health
-- (a skill, a perk) keeps the parts right.
-- over: overheal per part (game units, a first aid kit with Quick Fix ace);
-- black_at: when a part went black (Painkillers ace suspends the penalties).
local state = { frac = {}, owner = nil, revision = 0, full_on_revive = false, over = {}, black_at = {} }
Body.state = state

-- Hook points the skills fill (skills_medic.lua, doctor_buffs.lua). Each is
-- a function, or nil for the plain rule.
--   spill_rate()        -> the spill rate instead of EFFECTS.spread_damage
--   revive_head_full()  -> true: a revive sets the head to full
--   auto_revive_full()  -> true: an auto-revive (Uppers) sets the head to full
--   overheal_cap()      -> a first aid kit's heal past a part's max is kept, up
--                          to this share of the part's max
--   suspend_time()      -> seconds a part's penalties wait after it goes black
--   recoil(), spread(), stamina() -> extra multipliers
--   on_doctor_bag(list) -> a doctor bag healed these black parts
--   part_max(id, max)   -> the part's max instead of its share (Frenzy)
--   start_black(id)     -> true: the part starts the heist black (Frenzy)
Body.mods = Body.mods or {}
-- Extra lines for the health window, by name: fn() -> text or nil.
Body.lines = Body.lines or {}

local function mod(name, ...)
    local f = Body.mods[name]
    if type(f) ~= "function" then return nil end
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end

-- The time the suspension is measured in; tests replace it.
Body.clock = PDTI.AppTime

local log = PDTI.Logger("PDTI BODY")

local function reset_full()
    for _, p in ipairs(Body.PARTS) do state.frac[p.id] = 1 end
    state.revision = state.revision + 1
end
reset_full()

-- A fresh start (a heist, back from custody): the parts a skill wants black
-- start at 0 (no Painkillers suspension: they did not go black by a hit).
local function reset_start()
    reset_full()
    for _, p in ipairs(Body.PARTS) do
        if p.id ~= "head" and mod("start_black", p.id) == true then state.frac[p.id] = 0 end
    end
end

function Body.Enabled()
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return not (s and s.body_parts == false)
end

local function changed()
    state.revision = state.revision + 1
    if PDTI.Carry and PDTI.Carry.InvalidateCache then pcall(PDTI.Carry.InvalidateCache) end
    Body.hud_dirty = true
end

------------------------------------------------------------------ the parts

-- The max health the parts are measured against (the game's internal
-- units; the screen shows ten times that). Perks that lower the max health
-- (Frenzy) do it through _max_health_reduction; the game caps the health
-- there, so the parts do too.
local function max_health(pd)
    local ok, value = pcall(function() return pd:_max_health() * (tonumber(pd._max_health_reduction) or 1) end)
    if ok and type(value) == "number" and value > 0 then return value end
    return state.max or 23
end

-- The part's max by its share alone (what Frenzy moves to the head).
function Body.ShareMax(id, max)
    local p = BY_ID[id]
    return p and (max or state.max or 23) * p.share / TOTAL_SHARE or 0
end

function Body.PartMax(id, max)
    if not BY_ID[id] then return 0 end
    local m = max or state.max or 23
    local v = mod("part_max", id, m)
    if type(v) == "number" and v > 0 then return v end
    return Body.ShareMax(id, m)
end

function Body.HP(id, max)
    return (state.frac[id] or 0) * Body.PartMax(id, max)
end

local function set_hp(id, hp, max)
    local cap = Body.PartMax(id, max)
    if cap <= 0 then return end
    hp = math.max(0, math.min(cap, hp))
    -- Tiny rests count as 0, so a part that is meant to be black is.
    if hp < 1e-6 then hp = 0 end
    local was = state.frac[id] or 0
    state.frac[id] = hp / cap
    if hp == 0 and was > 0 then state.black_at[id] = Body.clock() end
end

-- Overheal of a part, in game units.
function Body.Over(id)
    return state.over[id] or 0
end

function Body.Sum(max)
    local sum = 0
    for _, p in ipairs(Body.PARTS) do sum = sum + Body.HP(p.id, max) end
    return sum
end

function Body.IsBlack(id)
    return (state.frac[id] or 0) <= 0
end

function Body.HeadDown()
    return Body.IsBlack("head")
end

local hit_part

-- Where damage that a part cannot take goes (0.22.0): to the body, or to the
-- head when the body is black (or the damage came from the body). With the
-- head black too there is nowhere left: you are down.
function Body.SpillTarget(from)
    if from ~= "body" and not Body.IsBlack("body") then return "body" end
    if from ~= "head" and not Body.IsBlack("head") then return "head" end
    return nil
end

-- The share of a black part's damage that goes on (Painkillers: 50%).
function Body.SpillRate()
    local v = mod("spill_rate")
    if type(v) == "number" then return v end
    return Body.EFFECTS.spread_damage
end

local function spill(from, amount, max, depth)
    if amount <= 1e-9 or depth > 8 then return end
    local target = Body.SpillTarget(from)
    if target then hit_part(target, amount, max, depth + 1) end
end

hit_part = function(id, amount, max, depth)
    depth = depth or 0
    if amount <= 0 then return end
    -- Overheal goes first.
    local over = state.over[id] or 0
    if over > 0 then
        local soak = math.min(over, amount)
        state.over[id] = over - soak
        amount = amount - soak
        if amount <= 1e-9 then return end
    end
    local hp = Body.HP(id, max)
    if hp <= 0 then
        spill(id, amount * Body.SpillRate(), max, depth)
        return
    end
    local take = math.min(hp, amount)
    set_hp(id, hp - take, max)
    local rest = amount - take
    if rest > 1e-9 then spill(id, rest * Body.SpillRate(), max, depth) end
end

-- Damage spread by share over every part (explosions, fire, the unknown).
local function spread_share(amount, max)
    for _, p in ipairs(Body.PARTS) do hit_part(p.id, amount * p.share / TOTAL_SHARE, max, 0) end
end

-- where: a part id, or "spread". mul: what reaches every part but the head
-- (broken heavy armour, armour.lua); nil is all of it.
function Body.Damage(amount, where, max, mul)
    max = max or state.max
    mul = tonumber(mul) or 1
    if BY_ID[where] then
        hit_part(where, where == "head" and amount or amount * mul, max, 0)
    else
        for _, p in ipairs(Body.PARTS) do
            hit_part(p.id, amount * p.share / TOTAL_SHARE * (p.id == "head" and 1 or mul), max, 0)
        end
    end
    changed()
    return Body.Sum(max)
end

-- Heals one part at a time: the most hurt part (the lowest share of its own
-- maximum) is filled first, then the next. A small heal (a perk, a skill)
-- then shows on one part instead of a few tenths on every part.
-- Black parts are left out; allow_black (a medic bag) takes them too.
function Body.Heal(amount, allow_black, max, overheal_cap)
    max = max or state.max
    if not amount or amount <= 0 then return 0 end
    local left = amount
    local given = 0
    for _ = 1, #Body.PARTS do
        local pick, pick_frac
        for _, p in ipairs(Body.PARTS) do
            if allow_black or not Body.IsBlack(p.id) then
                local miss = Body.PartMax(p.id, max) - Body.HP(p.id, max)
                local frac = state.frac[p.id] or 0
                if miss > 1e-9 and (pick == nil or frac < pick_frac) then pick, pick_frac = p.id, frac end
            end
        end
        if not pick or left <= 1e-9 then break end
        local miss = Body.PartMax(pick, max) - Body.HP(pick, max)
        local take = math.min(miss, left)
        set_hp(pick, Body.HP(pick, max) + take, max)
        left = left - take
        given = given + take
    end
    -- What is left becomes overheal (a first aid kit with Quick Fix ace),
    -- the part with the least of it first.
    local cap = tonumber(overheal_cap)
    if cap and cap > 0 and left > 1e-9 then
        for _ = 1, #Body.PARTS do
            local pick, pick_frac
            for _, p in ipairs(Body.PARTS) do
                if not Body.IsBlack(p.id) then
                    local room = cap * Body.PartMax(p.id, max) - (state.over[p.id] or 0)
                    local frac = (state.over[p.id] or 0) / math.max(1e-9, Body.PartMax(p.id, max))
                    if room > 1e-9 and (pick == nil or frac < pick_frac) then pick, pick_frac = p.id, frac end
                end
            end
            if not pick or left <= 1e-9 then break end
            local room = cap * Body.PartMax(pick, max) - (state.over[pick] or 0)
            local take = math.min(room, left)
            state.over[pick] = (state.over[pick] or 0) + take
            left = left - take
            given = given + take
        end
    end
    if given > 0 then changed() end
    return given
end

function Body.RestoreAll()
    reset_full()
    changed()
end

-- The part a hit of this kind lands on.
function Body.RollPart(kind)
    local field = kind == "melee" and "melee" or "bullet"
    local total = 0
    for _, p in ipairs(Body.PARTS) do total = total + (p[field] or 0) end
    local r = Body.roll() * total
    for _, p in ipairs(Body.PARTS) do
        r = r - (p[field] or 0)
        if r < 0 then return p.id end
    end
    return "body"
end

function Body.OnHeistStart()
    state.owner = nil
    state.full_on_revive = false
    state.over = {}
    state.black_at = {}
    reset_start()
    changed()
end

----------------------------------------------------------------- the effects

-- Painkillers ace: a part that just went black keeps working for a while
-- (the head never: a black head is down).
function Body.Suspended(id)
    if id == "head" or not Body.IsBlack(id) then return false end
    local t = mod("suspend_time")
    local at = state.black_at[id]
    if type(t) ~= "number" or t <= 0 or not at then return false end
    return Body.clock() - at < t
end

-- Black and its penalties in force.
function Body.Penalized(id)
    return Body.IsBlack(id) and not Body.Suspended(id)
end

local function count_black(a, b)
    return (Body.Penalized(a) and 1 or 0) + (Body.Penalized(b) and 1 or 0)
end

local function extra(name)
    local v = mod(name)
    return type(v) == "number" and v or 1
end

function Body.Active()
    return Body.Enabled() and state.owner ~= nil
end

function Body.RecoilMul()
    if not Body.Active() then return 1 end
    return Body.EFFECTS.arm_recoil ^ count_black("arm_l", "arm_r") * extra("recoil")
end

function Body.SpreadMul()
    if not Body.Active() then return 1 end
    return Body.EFFECTS.arm_spread ^ count_black("arm_l", "arm_r") * extra("spread")
end

function Body.SpeedFactor()
    -- Inserting an armour plate slows you (armour.lua).
    local plate = PDTI.Armour and PDTI.Armour.SpeedFactor and PDTI.Armour.SpeedFactor() or 1
    if not Body.Active() then return plate end
    return plate * Body.EFFECTS.leg_speed ^ count_black("leg_l", "leg_r")
end

-- A black arm cannot fire the akimbo gun in its hand.
function Body.ArmBlocked(id)
    return Body.Active() and (id == "arm_l" or id == "arm_r") and Body.Penalized(id)
end

function Body.CanSprint()
    if not Body.Active() then return true end
    return count_black("leg_l", "leg_r") == 0
end

function Body.StaminaMul()
    if not Body.Active() then return 1 end
    return (Body.Penalized("body") and Body.EFFECTS.body_stamina or 1) * extra("stamina")
end

function Body.Frac(id)
    return state.frac[id] or 0
end

-- HP as the screen shows it (ten times the game's units), rounded.
function Body.ShownHP(id)
    return math.floor(Body.HP(id) * 10 + 0.5)
end

function Body.ShownMax(id)
    return math.floor(Body.PartMax(id) * 10 + 0.5)
end

-- What the black parts do now, one line each (none: an empty list).
function Body.EffectLines()
    local lines = {}
    local E = Body.EFFECTS
    local function pct(v) return math.floor(v * 100 + 0.5) end
    if Body.IsBlack("head") then lines[#lines + 1] = "Head black: you are down" end
    local arms = count_black("arm_l", "arm_r")
    if arms > 0 then
        lines[#lines + 1] = string.format("%s: recoil +%d%%, spread +%d%%",
            arms == 2 and "Both arms black" or "An arm black",
            pct(E.arm_recoil ^ arms) - 100, pct(E.arm_spread ^ arms) - 100)
    end
    if Body.Penalized("arm_l") then lines[#lines + 1] = "Left arm black: the left akimbo gun cannot fire" end
    if Body.Penalized("arm_r") then lines[#lines + 1] = "Right arm black: the right akimbo gun cannot fire" end
    local legs = count_black("leg_l", "leg_r")
    if legs > 0 then
        lines[#lines + 1] = string.format("%s: no sprinting, speed %d%%",
            legs == 2 and "Both legs black" or "A leg black", pct(E.leg_speed ^ legs))
    end
    if Body.Penalized("body") then
        lines[#lines + 1] = string.format("Body black: stamina %d%%", pct(E.body_stamina))
    end
    -- Painkillers ace.
    for _, p in ipairs(Body.PARTS) do
        if Body.Suspended(p.id) then
            local left = (mod("suspend_time") or 0) - (Body.clock() - (state.black_at[p.id] or 0))
            lines[#lines + 1] = string.format("%s black, no penalty for %d s", p.name, math.max(0, math.ceil(left)))
        end
    end
    -- Quick Fix ace.
    local over = 0
    for _, p in ipairs(Body.PARTS) do over = over + (state.over[p.id] or 0) end
    if over > 1e-6 then lines[#lines + 1] = string.format("Overheal: +%d", math.floor(over * 10 + 0.5)) end
    -- Combat Doctor.
    local buff = mod("buff_line")
    if type(buff) == "string" and buff ~= "" then lines[#lines + 1] = buff end
    -- Other skills' lines (the AP barrier, ...): Body.lines[name] = fn.
    local names = {}
    for name in pairs(Body.lines) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, line = pcall(Body.lines[name])
        if ok and type(line) == "string" and line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end

-- "H 18  B 77  LA 0 ..." in the screen's units.
function Body.Summary()
    local parts = {}
    for _, p in ipairs(Body.PARTS) do
        parts[#parts + 1] = p.short .. " " .. tostring(math.floor(Body.HP(p.id) * 10 + 0.5))
    end
    return table.concat(parts, "  ")
end

------------------------------------------------------------------ the hooks

local hooks = Body.hooks or {}
Body.hooks = hooks
local busy = false

local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(hooks, "body", class_name, fn_name, make)
end

local function real_health(pd)
    local ok, value = pcall(function() return pd:get_real_health() end)
    if ok and type(value) == "number" then return value end
    return tonumber(pd._health) or 0
end

-- The game's health becomes the sum of the parts (without re-entering the
-- hooks), and the HUD shows it.
local function push_health(pd)
    busy = true
    pcall(function() pd:set_health(Body.Sum(state.max)) end)
    busy = false
    pcall(function()
        managers.hud:set_player_health({ current = real_health(pd), total = pd:_max_health(),
            revives = Application:digest_value(pd._revives, false) })
    end)
end

-- The parts start with this damage extension (a new one after custody is
-- full health); a health the parts do not know of is taken in.
local function attach(pd)
    -- The game rescales the health when the max health changed (skills,
    -- perks, armour that becomes health). That happens inside its own
    -- change_health, after this mod did its sums, so it is done first.
    if type(pd._check_update_max_health) == "function" then pcall(pd._check_update_max_health, pd) end
    if state.owner ~= pd then
        state.owner = pd
        state.over = {}
        state.black_at = {}
        reset_start()
        state.max = max_health(pd)
        local cur = real_health(pd)
        local sum = Body.Sum(state.max)
        if cur < sum - 1e-6 then spread_share(sum - cur, state.max) end
        changed()
        -- Parts that start black (Frenzy): the game's health drops to the sum.
        if cur > sum + 1e-6 and not busy then
            busy = true
            pcall(function() pd:set_health(sum) end)
            busy = false
        end
    end
    local max = max_health(pd)
    if max ~= state.max then
        state.max = max
        changed()
    end
end

-- The parts follow the player from the moment the hooks are in, not from
-- the first hit: the screens show the real max health (skills and perks
-- included) right away, and follow it when it changes.
function Body.AttachPlayer()
    if not Body.Enabled() or busy then return false end
    local pd = PDTI.PlayerDamage()
    if not pd then return false end
    attach(pd)
    return true
end

local function active(pd)
    return Body.Enabled() and not busy and pd ~= nil
end

-- The game's health becomes the parts' sum (0 when the head is black).
local function target_health()
    if Body.HeadDown() then return 0 end
    return Body.Sum(state.max)
end

local function make_change_health(orig)
    return function(self, delta, ...)
        if not active(self) or type(delta) ~= "number" or delta == 0 then return orig(self, delta, ...) end
        attach(self)
        if delta < 0 then
            local mul = 1
            if PDTI.Armour and PDTI.Armour.Protection then
                local ok, p = pcall(PDTI.Armour.Protection, self)
                if ok and type(p) == "number" then mul = 1 - p end
            end
            Body.Damage(-delta, self._pdti_hit or "spread", state.max, mul)
        else
            local cap = state.fak and mod("overheal_cap") or nil
            Body.Heal(delta, false, state.max, cap)
        end
        busy = true
        local ok, result = pcall(orig, self, target_health() - real_health(self), ...)
        busy = false
        if not ok then error(result, 0) end
        return result
    end
end

-- A health set directly that the hooks below did not make: a heal of the
-- parts that are not black, or damage spread over them.
local function make_set_health(orig)
    return function(self, health, ...)
        if not active(self) or type(health) ~= "number" then return orig(self, health, ...) end
        attach(self)
        local sum = Body.Sum(state.max)
        if health <= 0 then
            -- Set to 0 on purpose (a deadly fall, a kill zone, forced into
            -- bleed-out): you go down.
            set_hp("head", 0, state.max)
            changed()
        elseif health < sum - 1e-6 then
            Body.Damage(sum - health, self._pdti_hit or "spread", state.max)
        elseif health > sum + 1e-6 then
            Body.Heal(health - sum, false, state.max)
        end
        busy = true
        local ok, result = pcall(orig, self, target_health(), ...)
        busy = false
        if not ok then error(result, 0) end
        return result
    end
end

-- After the game's revive: the head has 1 HP, the rest stays. Getting up
-- with a medic bag heals every part.
local function make_revive(orig)
    return function(self, ...)
        if not Body.Enabled() or busy then return orig(self, ...) end
        attach(self)
        busy = true
        local ok, result = pcall(orig, self, ...)
        busy = false
        if not ok then error(result, 0) end
        if state.full_on_revive then
            state.full_on_revive = false
            reset_full()
        else
            local head = Body.ReviveHeadHP(state.max)
            if Body.HP("head", state.max) < head then set_hp("head", head, state.max) end
        end
        changed()
        push_health(self)
        return result
    end
end

-- The medic bag, and a full refill: every part to full. A medic bag
-- (recover_health) tells the skills which black parts it healed.
local function make_full(doctor_bag)
    return function(orig)
        return function(self, ...)
            if not Body.Enabled() or busy then return orig(self, ...) end
            attach(self)
            local downed = Body.HeadDown()
            local healed = {}
            for _, p in ipairs(Body.PARTS) do
                if p.id ~= "head" and Body.IsBlack(p.id) then healed[#healed + 1] = p.id end
            end
            -- Got up by the medic bag: the revive inside is a full one.
            if downed then state.full_on_revive = true end
            Body.RestoreAll()
            local result = orig(self, ...)
            state.full_on_revive = false
            if doctor_bag then mod("on_doctor_bag", healed) end
            return result
        end
    end
end

-- A first aid kit: its heal may become overheal (Quick Fix ace). Used while
-- the game checks for bleed-out, it is the Uppers auto-revive: the black
-- head first gets the revive value (full with Uppers ace), or the kit would
-- heal every part but the head and leave you at 0.
local function make_band_aid(orig)
    return function(self, ...)
        if not Body.Enabled() or busy then return orig(self, ...) end
        attach(self)
        if state.bleed_check and Body.HeadDown() then
            local full = mod("auto_revive_full")
            set_hp("head", full and Body.PartMax("head", state.max) or Body.ReviveHeadHP(state.max), state.max)
            changed()
            busy = true
            pcall(function() self:set_health(Body.Sum(state.max)) end)
            busy = false
        end
        local before = state.fak
        state.fak = true
        local ok, result = pcall(orig, self, ...)
        state.fak = before
        if not ok then error(result, 0) end
        return result
    end
end

local function make_bleed_check(orig)
    return function(self, ...)
        local before = state.bleed_check
        state.bleed_check = true
        local ok, result = pcall(orig, self, ...)
        state.bleed_check = before
        if not ok then error(result, 0) end
        return result
    end
end

local function make_hit(where)
    return function(orig)
        return function(self, attack_data, ...)
            if not Body.Enabled() then return orig(self, attack_data, ...) end
            local before = self._pdti_hit
            if where == "bullet" or where == "melee" then
                self._pdti_hit = Body.RollPart(where)
            elseif where == "leg" then
                self._pdti_hit = Body.roll() < 0.5 and "leg_l" or "leg_r"
            else
                self._pdti_hit = "spread"
            end
            local ok, result = pcall(orig, self, attack_data, ...)
            self._pdti_hit = before
            if not ok then error(result, 0) end
            return result
        end
    end
end

local function weapon_user_is_player(wep)
    local user = wep._setup and wep._setup.user_unit
    return user ~= nil and user == managers.player:player_unit()
end
local function is_player_weapon(wep)
    local ok, mine = pcall(weapon_user_is_player, wep)
    return ok and mine
end

local function multiply(fn)
    return function(orig)
        return function(self, ...)
            local value = orig(self, ...)
            if type(value) ~= "number" or not is_player_weapon(self) then return value end
            return value * fn()
        end
    end
end

local function set_max_stamina(value) managers.hud:set_max_stamina(value) end

-- The hooks, made once: InstallHooks runs every frame and must not allocate.
-- { class, function, maker, required }
local HOOKS = {
    { "PlayerDamage", "change_health", make_change_health, true },
    { "PlayerDamage", "set_health", make_set_health, true },
    { "PlayerDamage", "revive", make_revive, true },
    { "PlayerDamage", "recover_health", make_full(true), true },
    { "PlayerDamage", "replenish", make_full(false), true },
    { "PlayerDamage", "band_aid_health", make_band_aid },
    { "PlayerDamage", "_check_bleed_out", make_bleed_check },
    { "PlayerDamage", "damage_bullet", make_hit("bullet"), true },
    { "PlayerDamage", "damage_melee", make_hit("melee"), true },
    { "PlayerDamage", "damage_fall", make_hit("leg"), true },
    { "PlayerDamage", "damage_explosion", make_hit("spread") },
    { "PlayerDamage", "damage_fire", make_hit("spread") },
    { "PlayerDamage", "damage_killzone", make_hit("spread") },
    { "PlayerDamage", "damage_simple", make_hit("spread") },
    { "NewRaycastWeaponBase", "recoil_multiplier", multiply(Body.RecoilMul) },
    { "NewRaycastWeaponBase", "spread_multiplier", multiply(Body.SpreadMul) },
    { "PlayerStandard", "_start_action_running", function(orig)
        return function(self, ...)
            if not Body.CanSprint() then return end
            return orig(self, ...)
        end
    end },
    -- Already sprinting when a leg goes black: stop.
    { "PlayerStandard", "_check_action_run", function(orig)
        return function(self, t, input, ...)
            if not Body.CanSprint() and self._running and self._end_action_running then
                pcall(self._end_action_running, self, t)
            end
            return orig(self, t, input, ...)
        end
    end },
    { "PlayerMovement", "_max_stamina", function(orig)
        return function(self, ...)
            local value = orig(self, ...)
            if type(value) ~= "number" then return value end
            local mul = Body.StaminaMul()
            if mul ~= 1 then
                value = value * mul
                pcall(set_max_stamina, value)
            end
            return value
        end
    end },
}

function Body.InstallHooks()
    local all = true
    for i = 1, #HOOKS do
        local h = HOOKS[i]
        if not wrap(h[1], h[2], h[3]) and h[4] then all = false end
    end
    if all and not hooks._logged then
        hooks._logged = true
        log("health per body part installed")
    end
    return all
end

-- Getting up with the medical rig's medic bag: that revive heals every part.
function Body.FullOnNextRevive()
    state.full_on_revive = true
end

-- The head after a revive: 1 HP on the screen, or full (Combat Medic ace).
function Body.ReviveHeadHP(max)
    if mod("revive_head_full") then return Body.PartMax("head", max or state.max) end
    return Body.EFFECTS.revive_head
end

-- Sets the head to a share of its max (Combat Medic ace when you revive
-- someone) and gives the game the new sum.
function Body.HealHead(frac)
    if not Body.Enabled() then return false end
    local pd = state.owner
    if not pd then return false end
    local want = Body.PartMax("head", state.max) * math.max(0, math.min(1, frac or 1))
    if Body.HP("head", state.max) >= want then return false end
    set_hp("head", want, state.max)
    changed()
    push_health(pd)
    return true
end

-- Heals one part by amount (game units), up to its max; not a black part
-- (only a doctor bag heals those). Returns the amount healed.
function Body.HealPart(id, amount)
    if not Body.Enabled() then return 0 end
    local pd = state.owner
    if not pd or not BY_ID[id] or Body.IsBlack(id) then return 0 end
    local before = Body.HP(id, state.max)
    set_hp(id, before + math.max(0, tonumber(amount) or 0), state.max)
    local healed = Body.HP(id, state.max) - before
    if healed <= 0 then return 0 end
    changed()
    push_health(pd)
    return healed
end

--------------------------------------------------------------------- the HUD

local FONT = "fonts/font_medium_mf"
local hud = { panel = nil, revision = nil }
Body.hud_dirty = true

-- Green when full; dark green above 75%, yellow above 50%, orange above
-- 25%, red down to 0, black at 0.
Body.COLORS = {
    full = { 0.25, 0.75, 0.30 },
    dark_green = { 0.10, 0.42, 0.16 },
    yellow = { 0.88, 0.78, 0.20 },
    orange = { 0.92, 0.50, 0.12 },
    red = { 0.80, 0.18, 0.14 },
    black = { 0.05, 0.05, 0.05 },
}
function Body.ColorName(frac)
    if frac <= 0 then return "black" end
    if frac >= 0.999 then return "full" end
    if frac > 0.75 then return "dark_green" end
    if frac > 0.5 then return "yellow" end
    if frac > 0.25 then return "orange" end
    return "red"
end
function Body.PartColor(frac)
    return Body.COLORS[Body.ColorName(frac)]
end

-- The figure: x, y, w, h of every part, on a 40 x 74 grid.
Body.FIGURE = {
    head  = { 14, 0, 12, 12 },
    body  = { 11, 14, 18, 26 },
    arm_l = { 2, 14, 8, 24 },
    arm_r = { 30, 14, 8, 24 },
    leg_l = { 11, 42, 8, 32 },
    leg_r = { 21, 42, 8, 32 },
}

local function hud_root()
    local ok, panel = pcall(function()
        local h = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_PD2)
        return h and h.panel
    end)
    return ok and panel or nil
end

local function remove_hud()
    if not hud.panel then return end
    local root = hud_root()
    if root then pcall(function() root:remove(hud.panel) end) end
    hud.panel = nil
end

local function color(c, a)
    local C = rawget(_G, "Color")
    if not C then return nil end
    local ok, value = pcall(function() return C(a or 1, c[1], c[2], c[3]) end)
    return ok and value or nil
end

local function build_hud(root)
    local scale = 1
    local panel = root:panel({ name = "pdti_body_panel", x = 16, y = root:h() - 260, w = 60, h = 100, layer = 10 })
    for _, p in ipairs(Body.PARTS) do
        local r = Body.FIGURE[p.id]
        local frac = state.frac[p.id] or 0
        panel:rect({ name = "part_" .. p.id, x = r[1] * scale, y = r[2] * scale, w = r[3] * scale,
            h = r[4] * scale, color = color(Body.PartColor(frac), 0.85) })
    end
    panel:text({ name = "body_hp", x = 0, y = 78, w = 60, h = 16, font = FONT, font_size = 12,
        text = tostring(math.floor(Body.Sum() * 10 + 0.5)), align = "center",
        color = color({ 1, 1, 1 }, 0.9) })
    return panel
end

-- The inventory screen shows every part's HP: while it is open it is drawn
-- again when a part changes, at most this often.
Body.UI_REFRESH = 0.25
local ui_last = nil

local function refresh_screen()
    if not (PDTI.IsUIOpen and PDTI.IsUIOpen()) then return end
    if Body.ui_revision == state.revision then return end
    local now = PDTI.AppTime()
    if ui_last and now - ui_last < Body.UI_REFRESH then return end
    ui_last = now
    if PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
end

-- Called every frame; draws again only when a part changed.
function Body.UpdateHud()
    pcall(Body.AttachPlayer)
    refresh_screen()
    if not Body.Enabled() or not state.owner then
        remove_hud()
        return
    end
    if hud.panel and hud.revision == state.revision then return end
    local root = hud_root()
    if not root then return end
    remove_hud()
    local ok, panel = pcall(build_hud, root)
    if ok then hud.panel = panel end
    hud.revision = state.revision
end
