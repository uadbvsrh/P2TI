-- Keybind entry point (see "keybinds" in mod.txt): clear a jammed weapon.
if rawget(_G, "PDTI") and PDTI.Wear and PDTI.Wear.StartClear then PDTI.Wear.StartClear() end
