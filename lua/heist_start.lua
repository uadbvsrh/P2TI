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
    if pdti.Safehouse and pdti.Safehouse.OnLevelStart then pcall(pdti.Safehouse.OnLevelStart) end
    -- The safehouse is not a heist: the inventory stays as it is saved, and
    -- nothing is restocked, cleared or reset.
    if pdti.InSafehouse and pdti.InSafehouse() then return end
    -- The plan was paid for in the menu; what this heist uses up of it is
    -- paid again as it is used (Plan.RestockTick).
    if pdti.Plan and pdti.Plan.StartRestock then pcall(pdti.Plan.StartRestock) end
    if pdti.Ammo and pdti.Ammo.OnHeistStart then pdti.Ammo.OnHeistStart() end
    if pdti.Loot and pdti.Loot.OnHeistStart then pdti.Loot.OnHeistStart() end
    -- From here a failed (or left) heist loses the weapons you brought.
    if pdti.Armory and pdti.Armory.OnHeistStart then pcall(pdti.Armory.OnHeistStart) end
    if pdti.Deployables and pdti.Deployables.OnHeistStart then pdti.Deployables.OnHeistStart() end
    if pdti.Gear and pdti.Gear.OnHeistStart then pdti.Gear.OnHeistStart() end
    if pdti.Perks and pdti.Perks.OnHeistStart then pdti.Perks.OnHeistStart() end
    if pdti.Body and pdti.Body.OnHeistStart then pdti.Body.OnHeistStart() end
    if pdti.DoctorBuffs and pdti.DoctorBuffs.OnHeistStart then pdti.DoctorBuffs.OnHeistStart() end
    if pdti.AmmoSkills and pdti.AmmoSkills.OnHeistStart then pdti.AmmoSkills.OnHeistStart() end
    if pdti.SilentKiller and pdti.SilentKiller.OnHeistStart then pdti.SilentKiller.OnHeistStart() end
    if pdti.Barrier and pdti.Barrier.OnHeistStart then pdti.Barrier.OnHeistStart() end
    if pdti.GhostSkills and pdti.GhostSkills.OnHeistStart then pdti.GhostSkills.OnHeistStart() end
    if pdti.Armour and pdti.Armour.OnHeistStart then pdti.Armour.OnHeistStart() end
end)
