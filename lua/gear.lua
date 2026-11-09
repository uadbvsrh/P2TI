-- What the rig and the backpack do besides holding things.
--
--   * speed_bonus (general rig, small backpack): you are that much faster.
--     Bonuses add up: both together are +50%.
--   * penalty_scale (large backpack): the slowdown from the load and from
--     the loot is scaled by it (0.7 = 30% smaller). The armour stays the
--     game's.
--   * threat (large backpack): enemies weigh you that much more when they
--     choose whom to shoot. It goes through the attention weight the game
--     uses for skills like the camouflage bonuses. The enemies are run by
--     the host, so this works when you host or play offline.
--   * self_revive (medical rig): once per heist, while you are down
--     (bleeding out), SPACE gets you up without help when a medic bag is in
--     your inventory. The medic bag is used up. It goes through the same
--     message the Messiah skill uses, so it is synced like that skill.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Gear = PDTI.Gear or {}
PDTI.Gear = Gear

Gear.REVIVE_ITEM = "doctor_bag"
Gear.revive_used = Gear.revive_used or false

local function log(message)
    local line = "[PDTI GEAR] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function hint(text)
    pcall(function() managers.hud:show_hint({ text = text }) end)
end

function Gear.Rig()
    local eq = PDTI.GetEquipment()
    return eq.rig_definition or {}
end

function Gear.Backpack()
    local eq = PDTI.GetEquipment()
    return eq.backpack_definition or {}
end

-- +0.25 for each piece that makes you faster.
function Gear.SpeedBonus()
    return (tonumber(Gear.Rig().speed_bonus) or 0) + (tonumber(Gear.Backpack().speed_bonus) or 0)
end

-- How much of the load and loot slowdown you feel (1 = all of it).
function Gear.PenaltyScale()
    local scale = (tonumber(Gear.Rig().penalty_scale) or 1) * (tonumber(Gear.Backpack().penalty_scale) or 1)
    return math.max(0, math.min(1, scale))
end

-- How much more the enemies focus on you (1 = as in the game).
function Gear.Threat()
    return (tonumber(Gear.Rig().threat) or 1) * (tonumber(Gear.Backpack().threat) or 1)
end

------------------------------------------------------------ getting up

-- Where the medic bag is: the rig first, then the pockets, then the backpack.
local function find_revive_item()
    for _, name in ipairs({ "rig", "rig_2", "rig_3", "pockets", "backpack" }) do
        for _, item in ipairs(PDTI.GetContainer(name).items) do
            if item.item_id == Gear.REVIVE_ITEM then return name, item.instance_id end
        end
    end
    return nil
end

function Gear.CanSelfRevive()
    if not Gear.Rig().self_revive then return false end
    if Gear.revive_used then return false end
    return find_revive_item() ~= nil
end

local function is_bleeding_out()
    local ok, state = pcall(function() return managers.player:current_state() end)
    return ok and state == "bleed_out"
end

-- Gets you up. Returns true when it worked.
function Gear.SelfRevive()
    if not Gear.CanSelfRevive() then return false end
    if not is_bleeding_out() then return false end
    local container, instance_id = find_revive_item()
    local ok = PDTI.RemoveItem(container, instance_id, 1)
    if not ok then return false end
    Gear.revive_used = true
    -- It is a medic bag: every body part comes back full.
    if PDTI.Body and PDTI.Body.FullOnNextRevive then PDTI.Body.FullOnNextRevive() end
    local sent = pcall(function() managers.player:send_message(Message.RevivePlayer, nil, nil) end)
    if not sent then
        -- No message system: the damage extension directly.
        pcall(function() managers.player:player_unit():character_damage():revive(true) end)
    end
    log("got up with the medic bag (once per heist)")
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    return true
end

local hinted = false

-- Called every frame from the game hook with the state's input.
function Gear.Tick(input)
    if not is_bleeding_out() then
        hinted = false
        return
    end
    if not Gear.CanSelfRevive() then return end
    if not hinted then
        hinted = true
        hint("Press SPACE to get up with your medic bag (once per heist)")
    end
    if input and input.btn_jump_press then Gear.SelfRevive() end
end

function Gear.OnHeistStart()
    Gear.revive_used = false
    hinted = false
end

---------------------------------------------------------- enemy focus

-- PlayerMovement:_apply_attention_setting_modifications: the game sets the
-- attention weight of your attention settings there.
function Gear.InstallHooks()
    local PM = rawget(_G, "PlayerMovement")
    if not PM or type(PM._apply_attention_setting_modifications) ~= "function" then return false end
    if PM._pdti_threat_hook == PM._apply_attention_setting_modifications then return true end
    local original = PM._apply_attention_setting_modifications
    local hook = function(self, setting, ...)
        local result = original(self, setting, ...)
        local ok, threat = pcall(Gear.Threat)
        if ok and type(threat) == "number" and threat ~= 1 and type(setting) == "table" then
            setting.weight_mul = (setting.weight_mul or 1) * threat
        end
        return result
    end
    PM._apply_attention_setting_modifications = hook
    PM._pdti_threat_hook = hook
    log("enemy focus follows the backpack")
    return true
end
