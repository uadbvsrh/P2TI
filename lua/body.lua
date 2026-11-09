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
--     when a part goes black, spreads to the other parts at 70%.
--   * The head at 0: you go down. When you are revived the head has 1 HP;
--     every other part stays as it was, black parts stay black.
--   * A first aid kit (and every skill that heals) heals the parts that are
--     not black. A medic bag heals every part to full, black ones too; so
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
    spread_damage = 0.7,      -- damage on a black part, passed on to the others
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
local state = { frac = {}, owner = nil, revision = 0, full_on_revive = false }
Body.state = state

local function log(message)
    local line = "[PDTI BODY] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function reset_full()
    for _, p in ipairs(Body.PARTS) do state.frac[p.id] = 1 end
    state.revision = state.revision + 1
end
reset_full()

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

function Body.PartMax(id, max)
    local p = BY_ID[id]
    return p and (max or state.max or 23) * p.share / TOTAL_SHARE or 0
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
    state.frac[id] = hp / cap
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

local function alive_parts()
    local list = {}
    for _, p in ipairs(Body.PARTS) do
        if not Body.IsBlack(p.id) then list[#list + 1] = p.id end
    end
    return list
end

local hit_part

-- Damage spread evenly over the parts that are not black; what a part
-- cannot take goes on at the spread rate again.
local function spread_even(amount, max, depth)
    if amount <= 1e-9 or depth > 8 then return end
    local list = alive_parts()
    if #list == 0 then return end
    local each = amount / #list
    for _, id in ipairs(list) do hit_part(id, each, max, depth + 1) end
end

hit_part = function(id, amount, max, depth)
    depth = depth or 0
    if amount <= 0 then return end
    local hp = Body.HP(id, max)
    if hp <= 0 then
        spread_even(amount * Body.EFFECTS.spread_damage, max, depth)
        return
    end
    local take = math.min(hp, amount)
    set_hp(id, hp - take, max)
    local rest = amount - take
    if rest > 1e-9 then spread_even(rest * Body.EFFECTS.spread_damage, max, depth) end
end

-- Damage spread by share over every part (explosions, fire, the unknown).
local function spread_share(amount, max)
    for _, p in ipairs(Body.PARTS) do hit_part(p.id, amount * p.share / TOTAL_SHARE, max, 0) end
end

-- where: a part id, or "spread".
function Body.Damage(amount, where, max)
    max = max or state.max
    if BY_ID[where] then hit_part(where, amount, max, 0) else spread_share(amount, max) end
    changed()
    return Body.Sum(max)
end

-- Heals the parts by what they miss. allow_black: a medic bag.
function Body.Heal(amount, allow_black, max)
    max = max or state.max
    local need, total = {}, 0
    for _, p in ipairs(Body.PARTS) do
        if allow_black or not Body.IsBlack(p.id) then
            local miss = Body.PartMax(p.id, max) - Body.HP(p.id, max)
            if miss > 0 then need[p.id] = miss; total = total + miss end
        end
    end
    if total <= 0 or amount <= 0 then return 0 end
    local give = math.min(amount, total)
    for id, miss in pairs(need) do set_hp(id, Body.HP(id, max) + give * miss / total, max) end
    changed()
    return give
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
    reset_full()
    changed()
end

----------------------------------------------------------------- the effects

local function count_black(a, b)
    return (Body.IsBlack(a) and 1 or 0) + (Body.IsBlack(b) and 1 or 0)
end

function Body.Active()
    return Body.Enabled() and state.owner ~= nil
end

function Body.RecoilMul()
    if not Body.Active() then return 1 end
    return Body.EFFECTS.arm_recoil ^ count_black("arm_l", "arm_r")
end

function Body.SpreadMul()
    if not Body.Active() then return 1 end
    return Body.EFFECTS.arm_spread ^ count_black("arm_l", "arm_r")
end

function Body.SpeedFactor()
    if not Body.Active() then return 1 end
    return Body.EFFECTS.leg_speed ^ count_black("leg_l", "leg_r")
end

-- A black arm cannot fire the akimbo gun in its hand.
function Body.ArmBlocked(id)
    return Body.Active() and (id == "arm_l" or id == "arm_r") and Body.IsBlack(id)
end

function Body.CanSprint()
    if not Body.Active() then return true end
    return count_black("leg_l", "leg_r") == 0
end

function Body.StaminaMul()
    if not Body.Active() then return 1 end
    return Body.IsBlack("body") and Body.EFFECTS.body_stamina or 1
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
    if Body.IsBlack("arm_l") then lines[#lines + 1] = "Left arm black: the left akimbo gun cannot fire" end
    if Body.IsBlack("arm_r") then lines[#lines + 1] = "Right arm black: the right akimbo gun cannot fire" end
    local legs = count_black("leg_l", "leg_r")
    if legs > 0 then
        lines[#lines + 1] = string.format("%s: no sprinting, speed %d%%",
            legs == 2 and "Both legs black" or "A leg black", pct(E.leg_speed ^ legs))
    end
    if Body.IsBlack("body") then
        lines[#lines + 1] = string.format("Body black: stamina %d%%", pct(E.body_stamina))
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
    local cls = rawget(_G, class_name)
    local current = cls and cls[fn_name]
    if type(current) ~= "function" then return false end
    local key = class_name .. "." .. fn_name
    if hooks[key] == current then return true end
    if PDTI.HookHas(current, "body") then return true end
    local hook = make(current)
    PDTI.HookMark(hook, current, "body")
    hooks[key] = hook
    cls[fn_name] = hook
    return true
end

local function real_health(pd)
    local ok, value = pcall(function() return pd:get_real_health() end)
    if ok and type(value) == "number" then return value end
    return tonumber(pd._health) or 0
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
        reset_full()
        state.max = max_health(pd)
        local cur = real_health(pd)
        local sum = Body.Sum(state.max)
        if cur < sum - 1e-6 then spread_share(sum - cur, state.max) end
        changed()
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
    local ok, pd = pcall(function() return managers.player:player_unit():character_damage() end)
    if not ok or type(pd) ~= "table" then return false end
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
            Body.Damage(-delta, self._pdti_hit or "spread", state.max)
        else
            Body.Heal(delta, false, state.max)
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
        elseif Body.HP("head", state.max) < Body.EFFECTS.revive_head then
            set_hp("head", Body.EFFECTS.revive_head, state.max)
        end
        changed()
        busy = true
        pcall(function() self:set_health(Body.Sum(state.max)) end)
        busy = false
        pcall(function()
            managers.hud:set_player_health({ current = real_health(self), total = self:_max_health(),
                revives = Application:digest_value(self._revives, false) })
        end)
        return result
    end
end

-- The medic bag, and a full refill: every part to full.
local function make_full(orig)
    return function(self, ...)
        if not Body.Enabled() or busy then return orig(self, ...) end
        attach(self)
        local downed = Body.HeadDown()
        -- Got up by the medic bag: the revive inside is a full one.
        if downed then state.full_on_revive = true end
        Body.RestoreAll()
        local result = orig(self, ...)
        state.full_on_revive = false
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

local function is_player_weapon(wep)
    local ok, mine = pcall(function()
        local user = wep._setup and wep._setup.user_unit
        return user ~= nil and user == managers.player:player_unit()
    end)
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

function Body.InstallHooks()
    local all = true
    local function w(...) if not wrap(...) then all = false end end
    w("PlayerDamage", "change_health", make_change_health)
    w("PlayerDamage", "set_health", make_set_health)
    w("PlayerDamage", "revive", make_revive)
    w("PlayerDamage", "recover_health", make_full)
    w("PlayerDamage", "replenish", make_full)
    w("PlayerDamage", "damage_bullet", make_hit("bullet"))
    w("PlayerDamage", "damage_melee", make_hit("melee"))
    w("PlayerDamage", "damage_fall", make_hit("leg"))
    for _, fn in ipairs({ "damage_explosion", "damage_fire", "damage_killzone", "damage_simple" }) do
        wrap("PlayerDamage", fn, make_hit("spread"))
    end
    wrap("NewRaycastWeaponBase", "recoil_multiplier", multiply(Body.RecoilMul))
    wrap("NewRaycastWeaponBase", "spread_multiplier", multiply(Body.SpreadMul))
    wrap("PlayerStandard", "_start_action_running", function(orig)
        return function(self, ...)
            if not Body.CanSprint() then return end
            return orig(self, ...)
        end
    end)
    -- Already sprinting when a leg goes black: stop.
    wrap("PlayerStandard", "_check_action_run", function(orig)
        return function(self, t, input, ...)
            if not Body.CanSprint() and self._running and self._end_action_running then
                pcall(self._end_action_running, self, t)
            end
            return orig(self, t, input, ...)
        end
    end)
    wrap("PlayerMovement", "_max_stamina", function(orig)
        return function(self, ...)
            local value = orig(self, ...)
            if type(value) ~= "number" then return value end
            local mul = Body.StaminaMul()
            if mul ~= 1 then
                value = value * mul
                pcall(function() managers.hud:set_max_stamina(value) end)
            end
            return value
        end
    end)
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

--------------------------------------------------------------------- the HUD

local FONT = "fonts/font_medium_mf"
local hud = { panel = nil, revision = nil }
Body.hud_dirty = true

-- Green when full, yellow, red, black at 0.
function Body.PartColor(frac)
    if frac <= 0 then return { 0.05, 0.05, 0.05 } end
    if frac >= 0.6 then return { 0.25, 0.70, 0.30 } end
    if frac >= 0.3 then return { 0.85, 0.75, 0.20 } end
    return { 0.80, 0.20, 0.15 }
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
    local ok, now = pcall(function() return Application:time() end)
    now = ok and type(now) == "number" and now or os.clock()
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
