-- Hooked on lib/units/beings/player/playermovement: the large backpack makes
-- the enemies focus on you (see gear.lua).
if not rawget(_G, "PDTI") then
    local dir = rawget(_G, "ModPath")
    if dir then pcall(dofile, dir .. "lua/main.lua") end
end
local pdti = rawget(_G, "PDTI")
if pdti and pdti.Gear and pdti.Gear.InstallHooks then pdti.Gear.InstallHooks() end
