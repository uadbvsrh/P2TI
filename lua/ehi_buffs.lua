-- Extra Heist Info (EHI): the buffs of this mod in EHI's buff bar.
--   * New buffs: Stacked Barrier (absorption, then its cooldown), Doctor's
--     orders (Combat Doctor), Painkillers (the longest suspension left),
--     Overheal (Quick Fix ace), Momentum (Second Wind), HE ignite (HVT ace).
--   * EHI's own Yakuza and Berserker buffs show the reworked values (black
--     limbs / black parts) instead of the low-health ones.
-- Nothing happens without EHI or with its buffs switched off. The values are
-- read every 0.1 s (E.Poll, from the game hook) and pushed to EHI, which
-- counts the timers down by itself.
local PDTI = rawget(_G, "PDTI")
if not PDTI or not PDTI.Skills then return end
local Skills = PDTI.Skills

local E = PDTI.EHIBuffs or {}
PDTI.EHIBuffs = E

E.POLL = 0.1

local function log(message) Skills.log("ehi: " .. tostring(message)) end

------------------------------------------------------------ the sources

-- Each buff: skill (its icon), text (the line above the icon), kind
-- "timer" (seconds left) or "gauge" (ratio, the number shown), group (EHI's
-- colour group) and get() -> nil when it is not in force.
local function body() return PDTI.Body end

local function barrier_get()
    local B = PDTI.Barrier
    if not (B and B.Params and B.Params()) then return nil end
    local v = B.Value()
    if v <= 0 then return nil end
    local cap = B.Params().cap
    return v / cap, math.floor(v * 10 + 0.5)
end

local function barrier_cooldown_get()
    local B = PDTI.Barrier
    if not (B and B.Params and B.Params()) then return nil end
    B.Update()
    local left = (B.state.cooldown_until or 0) - B.now()
    if left > 0 then return left end
    return nil
end

local function doctor_get()
    local D, Bd = PDTI.DoctorBuffs, body()
    if not (D and D.Current and Bd) then return nil end
    local b = D.Current()
    if not b then return nil end
    local left = b.ends - Bd.clock()
    if left > 0 then return left end
    return nil
end

local function painkillers_get()
    local Bd = body()
    if not (Bd and Bd.Active and Bd.Active() and Bd.mods and Bd.mods.suspend_time) then return nil end
    local ok, t = pcall(Bd.mods.suspend_time)
    if not ok or type(t) ~= "number" or t <= 0 then return nil end
    local best
    for _, p in ipairs(Bd.PARTS) do
        if Bd.Suspended(p.id) then
            local left = t - (Bd.clock() - (Bd.state.black_at[p.id] or 0))
            if left > 0 and (not best or left > best) then best = left end
        end
    end
    return best
end

local function overheal_get()
    local Bd = body()
    if not (Bd and Bd.Active and Bd.Active()) then return nil end
    local over = 0
    for _, p in ipairs(Bd.PARTS) do over = over + (Bd.Over(p.id) or 0) end
    if over <= 1e-6 then return nil end
    return 1, math.floor(over * 10 + 0.5)
end

local function silent_until(field)
    return function()
        local SK = PDTI.SilentKiller
        if not (SK and SK.state and SK.now) then return nil end
        local left = (SK.state[field] or 0) - SK.now()
        if left > 0 then return left end
        return nil
    end
end

E.BUFFS = {
    { id = "PDTI_Barrier", skill = "fast_fire", text = "Barrier", kind = "gauge",
      group = "player_damage_absorption", get = barrier_get },
    { id = "PDTI_BarrierCooldown", skill = "fast_fire", text = "Barrier", kind = "timer", group = "cooldown",
      get = barrier_cooldown_get },
    { id = "PDTI_Doctor", skill = "medic_2x", text = "Doctor", kind = "timer", get = doctor_get },
    { id = "PDTI_Painkillers", skill = "fast_learner", text = "Pain", kind = "timer", get = painkillers_get },
    { id = "PDTI_Overheal", skill = "tea_time", text = "Overheal", kind = "gauge",
      group = "player_damage_absorption", get = overheal_get },
    { id = "PDTI_Momentum", skill = "scavenger", text = "Momentum", kind = "timer",
      group = "player_movement_increase", get = silent_until("momentum_until") },
    { id = "PDTI_Ignite", skill = "hitman", text = "Ignite", kind = "timer", get = silent_until("ignite_until") },
}

------------------------------------------------------- the definitions

local function icon(skill)
    local ok, xy = pcall(function() return tweak_data.skilltree.skills[skill].icon_xy end)
    if ok and type(xy) == "table" then return { xy[1], xy[2] } end
    return { 0, 0 }
end

-- EHI's buff definitions for E.BUFFS (no "option": always created).
function E.Definitions()
    local defs = {}
    for _, b in ipairs(E.BUFFS) do
        defs[b.id] = {
            u100skill = icon(b.skill),
            text = b.text,
            group = b.group,
            format = "standard",
            class = b.kind == "gauge" and "EHIGaugeBuffTracker" or nil,
        }
    end
    return defs
end

local function add_definitions()
    local ok, err = pcall(function()
        local buff = tweak_data.ehi.buff
        for id, def in pairs(E.Definitions()) do buff[id] = def end
    end)
    if not ok then log("definitions: " .. tostring(err)) end
end

---------------------------------------------- EHI's Yakuza and Berserker

local function patch_yakuza()
    local C = rawget(_G, "EHIYakuzaBuffTracker")
    if not C or C._pdti then return end
    C._pdti = true
    local update = C.UpdateValue
    function C:UpdateValue(...)
        local Y = PDTI.Yakuza
        if not (Y and Y.Active and Y.Active()) then return update(self, ...) end
        local ratio = Y.Scale()
        self._current_armor_regen_multiplier = 1 + self._armor_regen_multiplier * ratio
        self._current_movement_multiplier = 1 + self._movement_multiplier * ratio
        if self._persistent or ratio > 0 then
            self:ActivateSoft()
            self:SetRatio(ratio)
        else
            self:DeactivateSoft()
        end
    end
end

local function patch_berserker()
    local C = rawget(_G, "EHIBerserkerBuffTracker")
    if not C or C._pdti then return end
    C._pdti = true
    local pre, update = C.PreUpdate, C.UpdateValue
    local function on()
        local BR = PDTI.Brawler
        return BR and Skills.Enabled() and Skills.BodyOn() and Skills.Basic("wolverine")
    end
    function C:PreUpdate(...)
        if not on() then return pre(self, ...) end
        -- The game's checks see the vanilla upgrades switched off; set up
        -- from the reworked skill instead.
        EHISkillRefreshBuffTracker.PreUpdate(self)
        local BR = PDTI.Brawler
        local most = BR.PER_PART * BR.MAX_PARTS
        self._melee_damage_multiplier = most
        self._damage_multiplier = Skills.Ace("wolverine") and most or 0
        if self._text_format == "$dmg;$postfix;" and self._damage_multiplier == 0 then
            self:delete_with_class()
            return
        end
        self.__pre_update = true
        self:SetPersistent()
        self:CanActivateUpdateLoop()
    end
    function C:UpdateValue(...)
        if not on() then return update(self, ...) end
        local BR = PDTI.Brawler
        local ratio = BR.Black() / BR.MAX_PARTS
        self._current_melee_damage_multiplier = BR.Multiplier("melee")
        self._current_damage_multiplier = BR.Multiplier("bullet")
        self:ActivateSoft()
        self:SetRatio(ratio)
    end
end

-- EHI calls "BuffsInit" after loading its buff classes, before it creates
-- the buffs.
function E.OnBuffsInit()
    if not Skills.Enabled() then return end
    add_definitions()
    local ok, err = pcall(patch_yakuza)
    if not ok then log("yakuza: " .. tostring(err)) end
    ok, err = pcall(patch_berserker)
    if not ok then log("berserker: " .. tostring(err)) end
end

function E.Register()
    if E._registered then return true end
    local EHI = rawget(_G, "EHI")
    if not EHI or type(EHI.AddCallback) ~= "function" then return false end
    E._registered = true
    EHI:AddCallback("BuffsInit", E.OnBuffsInit)
    return true
end
E.Register()
Skills.OnInstall("ehi", E.Register)

------------------------------------------------------------ the polling

local function manager()
    local m = rawget(_G, "managers")
    local b = m and m.ehi_buff
    if b and type(b._buffs) == "table" then return b end
    return nil
end

local clock = PDTI.GameTime

local function push(mgr, b)
    local tracker = mgr._buffs[b.id]
    if not tracker then return end
    local active = tracker._active == true
    local a, c = b.get()
    if b.kind == "timer" then
        if a then
            -- Start it, or set it again when it was renewed (EHI counts down).
            if not active or a > (tracker._time or 0) + 0.5 then mgr:AddBuff(b.id, a) end
        elseif active then
            mgr:RemoveBuff(b.id)
        end
    else
        if a then
            -- EHI skips a ratio it already shows; the number may still change.
            if active and tracker._ratio == a and tracker._pdti_value ~= c then tracker._ratio = -1 end
            tracker._pdti_value = c
            mgr:AddGauge(b.id, a, c)
        elseif active then
            mgr:RemoveBuff(b.id)
        end
    end
end

function E.Poll(force)
    local mgr = manager()
    if not mgr or not Skills.Enabled() then return end
    local t = clock()
    if not force and E._last and t - E._last < E.POLL and t >= E._last then return end
    E._last = t
    for _, b in ipairs(E.BUFFS) do
        local ok, err = pcall(push, mgr, b)
        if not ok and not E._failed then
            E._failed = true
            log(b.id .. ": " .. tostring(err))
        end
    end
end

return E
