-- Hooked on lib/states/menumainstate and lib/states/ingamewaitingforplayers
-- (see mod.txt): the main menu's state is loaded, so the way to the safehouse
-- can be put on it, and the briefing's, so the safehouse's briefing can be
-- passed (safehouse.lua). When the mod itself is loaded later, main.lua does
-- this instead.
local pdti = rawget(_G, "PDTI")
local home = pdti and pdti.Safehouse
if home then
    if home.InstallMenuHooks then pcall(home.InstallMenuHooks) end
    if home.InstallBriefingHooks then pcall(home.InstallBriefingHooks) end
end
-- The room bonuses (perks.lua): room tiers set in the menu are remembered.
if pdti and pdti.Perks and pdti.Perks.InstallHooks then pcall(pdti.Perks.InstallHooks) end
-- The armory (armory.lua): weapons for the heist, no restart, a left heist lost.
if pdti and pdti.Armory and pdti.Armory.InstallHooks then pcall(pdti.Armory.InstallHooks) end
