-- Hooked on lib/managers/blackmarketmanager: the core skill rules
-- (skill_rules.lua) go in once the black market manager exists. Whichever
-- comes second installs them: the mod (main.lua loads skill_rules.lua) or
-- this file.
local p = rawget(_G, "PDTI")
if p and p.Rules and p.Rules.Install then pcall(p.Rules.Install) end
if p and p.Skills and p.Skills.Install then pcall(p.Skills.Install) end
if p and p.Armory and p.Armory.InstallHooks then pcall(p.Armory.InstallHooks) end
