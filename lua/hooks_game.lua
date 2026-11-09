-- Hooked on lib/units/beings/player/states/playerstandard (same hook point
-- ISSR uses). Wraps PlayerStandard._get_input, which the game calls every frame.
--   * runs the ammunition system (the reload, the packing of magazines, the
--     HUD panel and the pickup of dropped magazines)
--   * follows the loot bags the player carries
--   * keeps the deployable key working
--   * while the inventory screen is open, returns an empty input table so no
--     key reaches the player (R no longer reloads)
if not rawget(_G, "PDTI") then
    local dir = rawget(_G, "ModPath")
    if dir then pcall(dofile, dir .. "lua/main.lua") end
end
local PS = rawget(_G, "PlayerStandard")
if not rawget(_G, "PDTI") or not PS or not PS._get_input then return end
if PDTI._game_hook == PS._get_input then return end

local previous = PS._get_input
local failed = false

-- The game starts its own deploy action when the deploy key is pressed: the
-- player kneels down, the timer of the game runs and the item appears. The
-- mod uses that action, so the placement takes the same time as in the game.
--
-- When the key of the mod was pressed but the game did not see it (the key
-- was rebound, or the inventory screen had the focus), the action is started
-- here.
local function patch_use_item()
    if not PS or type(PS._check_use_item) ~= "function" then return end
    if PDTI._pdti_check_use_item then return end

    local original = PS._check_use_item
    PDTI._pdti_check_use_item = original
    PS._check_use_item = function(self, t, input)
        local request = PDTI._deploy_request

        -- The game saw the deploy key itself (the mod's key is the game's
        -- key): the game handles it, and the mod must not start a second
        -- action. This matters most while a bag is carried: the game holds
        -- the key press back (a tap throws the bag, a hold deploys) and only
        -- passes it on when the key is let go. Starting a deploy action then,
        -- while the bag is thrown and the player state changes, crashed the
        -- game (HUDInteraction: _interact_circle is nil).
        if input and (input.btn_use_item_press or input.btn_use_item_release) then
            PDTI._game_use_item_t = t
        end
        local held = false
        pcall(function()
            held = self._controller and self._controller:get_input_bool("use_item") and true or false
        end)
        if held then PDTI._game_use_item_t = t end

        if request then
            local carrying = false
            pcall(function() carrying = managers.player:is_carrying() end)
            local seen = PDTI._game_use_item_t and t and (t - PDTI._game_use_item_t) < 0.5
            if carrying or seen then
                PDTI._deploy_request = nil
                request = false
            end
        end

        if request then
            PDTI._deploy_request = nil

            local dep = PDTI.Deployables
            local now = dep and dep.Now and dep.Now() or 0
            local asked = PDTI._deploy_request_t or now

            -- A request that was never handled (the player was in another
            -- state) is thrown away.
            if now - asked > 1 then
                request = false
            end

            local pressed = input and input.btn_use_item_press

            if request and not pressed then
                local forbidden = self._use_item_expire_t or self._equipping_mask
                    or self:_interacting() or self:_is_throwing_projectile() or self:_is_meleeing()

                if not forbidden and managers.player:can_use_selected_equipment(self._unit) then
                    self:_start_action_use_item(t)
                    return true
                end
            end
        end

        return original(self, t, input)
    end
end

local wrapper = function(self, t, dt, paused)
    -- The player is in the heist: from now on nothing is saved, so the next
    -- heist starts again with what was chosen in the menu or the briefing.
    if PDTI.SetSessionOnly and not PDTI.session_only then
        PDTI.SetSessionOnly(true)
        if PDTI.RedrawUI then pcall(PDTI.RedrawUI) end
    end

    patch_use_item()

    local input = previous(self, t, dt, paused)

    if not paused then
        if PDTI.Ammo and PDTI.Ammo.GameTick then
            local ok, err = pcall(PDTI.Ammo.GameTick, self, t, dt, paused)
            if not ok and not failed then
                failed = true
                if _G.log then _G.log("[PDTI AMMO] ammunition tick failed: " .. tostring(err)) end
            end
        end
        if PDTI.Loot and PDTI.Loot.Tick then
            pcall(PDTI.Loot.Tick)
        end
        if PDTI.Deployables then
            PDTI.Deployables.EnsureKeyTrigger()
        end
        if PDTI.DeployHud then
            pcall(PDTI.DeployHud.Update)
        end
        -- Getting up with the medic bag (medical rig). The downed state uses
        -- this same input function.
        if PDTI.Gear and PDTI.Gear.Tick then
            pcall(PDTI.Gear.Tick, input)
            pcall(PDTI.Gear.InstallHooks)
        end
        if PDTI.Carry then
            pcall(PDTI.Carry.InstallHooks)
        end
        -- What the heist uses up of the plan is paid again (the restock).
        if PDTI.Plan and PDTI.Plan.RestockTick then pcall(PDTI.Plan.RestockTick) end
        -- Health per body part.
        if PDTI.Body then
            pcall(PDTI.Body.InstallHooks)
            pcall(PDTI.Body.UpdateHud)
        end
    end

    if PDTI.IsUIOpen and PDTI.IsUIOpen() then return {} end
    return input
end

PS._get_input = wrapper
PDTI._game_hook = wrapper
