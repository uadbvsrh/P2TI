-- Hooked on lib/setups/gamesetup. Runs once per heist: the inventory is the
-- current profile's, as chosen in the menu, and nothing done in the heist is
-- saved. The magazines chosen in the menu become a weapon's when it is first
-- used.
if not rawget(_G, "PDTI") then
    local dir = rawget(_G, "ModPath")
    if dir then pcall(dofile, dir .. "lua/main.lua") end
end
if not rawget(_G, "GameSetup") or rawget(_G, "PDTI_HEIST_START_HOOKED") then return end
_G.PDTI_HEIST_START_HOOKED = true

Hooks:PostHook(GameSetup, "init_finalize", "PDTI_heist_start", function()
    local pdti = rawget(_G, "PDTI")
    if not pdti then return end
    -- The heist starts with the inventory of the current profile, as chosen
    -- in the menu. The briefing (pre-planning) still counts as the menu:
    -- changes there are saved. From the moment the player spawns nothing is
    -- saved (hooks_game.lua).
    if pdti.EnsureProfile then pcall(pdti.EnsureProfile) end
    -- The plan was paid for in the menu; what this heist uses up of it is
    -- paid again as it is used (Plan.RestockTick).
    if pdti.Plan and pdti.Plan.StartRestock then pcall(pdti.Plan.StartRestock) end
    if pdti.Ammo and pdti.Ammo.OnHeistStart then pdti.Ammo.OnHeistStart() end
    if pdti.Loot and pdti.Loot.OnHeistStart then pdti.Loot.OnHeistStart() end
    if pdti.Deployables and pdti.Deployables.OnHeistStart then pdti.Deployables.OnHeistStart() end
    if pdti.Gear and pdti.Gear.OnHeistStart then pdti.Gear.OnHeistStart() end
    if pdti.Body and pdti.Body.OnHeistStart then pdti.Body.OnHeistStart() end
end)
