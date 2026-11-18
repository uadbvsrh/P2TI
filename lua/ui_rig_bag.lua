-- Keybind entry point (see "keybinds" in mod.txt): Rust's room, tier 3 --
-- take a use of an ammo bag in the rig without placing it.
if rawget(_G, "PDTI") and PDTI.Perks and PDTI.Perks.RigBagRefill then pcall(PDTI.Perks.RigBagRefill) end
