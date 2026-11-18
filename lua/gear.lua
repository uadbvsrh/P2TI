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
--     Room bonuses (perks.lua): Dallas' room gives the revive back when you
--     place a doctor bag (tier 2) and a second one (tier 3); Sangres' room
--     makes it use a first aid kit, which heals like a kit (tier 2).
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Gear = PDTI.Gear or {}
PDTI.Gear = Gear

Gear.REVIVE_ITEM = "doctor_bag"
Gear.revive_used = Gear.revive_used or false
Gear.revives_used = Gear.revives_used or 0

local function perks() return PDTI.Perks end

-- The item the self-revive uses, and whether it heals every part to full.
function Gear.ReviveItem()
    local p = perks()
    if p and p.ReviveItem then return p.ReviveItem() end
    return Gear.REVIVE_ITEM, true
end

function Gear.ReviveCount()
    local p = perks()
    return p and p.ReviveCount and p.ReviveCount() or 1
end

local log = PDTI.Logger("PDTI GEAR")

local hint = PDTI.Hint

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
    local wanted = Gear.ReviveItem()
    for _, name in ipairs({ "rig", "rig_2", "rig_3", "pockets", "backpack" }) do
        for _, item in ipairs(PDTI.GetContainer(name).items) do
            if item.item_id == wanted then return name, item.instance_id end
        end
    end
    return nil
end

function Gear.RevivesLeft()
    return math.max(0, Gear.ReviveCount() - (Gear.revives_used or 0))
end

function Gear.CanSelfRevive()
    if not Gear.Rig().self_revive then return false end
    if Gear.RevivesLeft() <= 0 then return false end
    return find_revive_item() ~= nil
end

-- Dallas (tier 2): you placed a doctor bag, the self-revive comes back.
function Gear.OnDoctorBagPlaced()
    local p = perks()
    if not (p and p.BagRecharges and p.BagRecharges()) then return false end
    if not Gear.Rig().self_revive or (Gear.revives_used or 0) <= 0 then return false end
    Gear.revives_used = Gear.revives_used - 1
    Gear.revive_used = Gear.RevivesLeft() <= 0
    hint("Dallas: your self-revive is back")
    log("a doctor bag placed: the self-revive is back")
    return true
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
    local item_id, full = Gear.ReviveItem()
    local ok = PDTI.RemoveItem(container, instance_id, 1)
    if not ok then return false end
    Gear.revives_used = (Gear.revives_used or 0) + 1
    Gear.revive_used = Gear.RevivesLeft() <= 0
    -- A medic bag: every body part comes back full. A first aid kit (Sangres)
    -- heals like a kit after you are up.
    if full then
        if PDTI.Body and PDTI.Body.FullOnNextRevive then PDTI.Body.FullOnNextRevive() end
    else
        Gear.kit_heal_pending = true
    end
    local sent = pcall(function() managers.player:send_message(Message.RevivePlayer, nil, nil) end)
    if not sent then
        -- No message system: the damage extension directly.
        pcall(function() managers.player:player_unit():character_damage():revive(true) end)
    end
    log(string.format("got up with the %s (%d of %d this heist)", item_id == "doctor_bag" and "medic bag" or "first aid kit",
        Gear.revives_used, Gear.ReviveCount()))
    if PDTI.IsUIOpen and PDTI.IsUIOpen() and PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    return true
end

local hinted = false

-- Called every frame from the game hook with the state's input.
function Gear.Tick(input)
    if not is_bleeding_out() then
        hinted = false
        -- Up with a first aid kit (Sangres): it heals as a kit does.
        if Gear.kit_heal_pending then
            Gear.kit_heal_pending = nil
            pcall(function()
                local pd = managers.player:player_unit():character_damage()
                if pd.band_aid_health then pd:band_aid_health() end
            end)
        end
        return
    end
    if not Gear.CanSelfRevive() then return end
    if not hinted then
        hinted = true
        local item_id = Gear.ReviveItem()
        hint(string.format("Press SPACE to get up with your %s (%d left this heist)",
            item_id == "doctor_bag" and "medic bag" or "first aid kit", Gear.RevivesLeft()))
    end
    if input and input.btn_jump_press then Gear.SelfRevive() end
end

function Gear.OnHeistStart()
    Gear.revive_used = false
    Gear.revives_used = 0
    Gear.kit_heal_pending = nil
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
