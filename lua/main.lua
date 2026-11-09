-- PAYDAY 2: Tactical Inventory
-- SuperBLT entry point.
--
-- The mod contains the InsurgencySandstormStyleReload ammunition system: the
-- magazine supply is the inventory, so the two can never get out of step.
-- The old InsurgencySandstormStyleReload mod must be removed, otherwise both
-- mods hook the same reload functions.

-- This script is hooked in both the main menu and in heists. Load the mod
-- once per session so the second hook does not reload saves or reset
-- registrations made by optional mods.
if rawget(_G, "PDTI") and PDTI._loaded then return end

local function get_mod_dir()
    local dir = rawget(_G, "ModPath")
    if type(dir) == "string" and dir ~= "" then
        if not dir:match("[/\\]$") then dir = dir .. "/" end
        return dir
    end
    -- No ModPath (a test harness, for example): this script lives in
    -- <mod>/lua/main.lua, so the mod folder is one level up.
    local src = debug.getinfo(1, "S").source
    local path = (src:sub(1, 1) == "@" and src:sub(2)) or ""
    path = path:gsub("[/\\]lua[/\\][^/\\]*$", "")
    if path == "" then return "./" end
    if not path:match("[/\\]$") then path = path .. "/" end
    return path
end

local DIR = get_mod_dir()

local function report(message)
    local line = "[PDTI] " .. tostring(message)
    if _G.log then _G.log(line) else print(line) end
end

local function load_part(name)
    local ok, err = pcall(dofile, DIR .. "lua/" .. name .. ".lua")
    if not ok then report("Failed loading " .. name .. ": " .. tostring(err)) end
    return ok
end

if not load_part("items") then return end
if not load_part("inventory") then return end
if not load_part("ammo") then return end
load_part("plan")
if not load_part("item_use") then return end
if not load_part("ui_model") then return end
if not load_part("ui_interaction") then return end
load_part("ammo_hud")
load_part("ammo_hooks")
load_part("loot")
load_part("deployables")
load_part("deploy_hud")
load_part("loadout")
load_part("gear")
load_part("body")
load_part("carry")
load_part("ui_beardlib") -- optional: needs BeardLib's MenuUI at runtime
if not load_part("diagnostics") then return end
load_part("selftest")

PDTI._loaded = true
report("Tactical Inventory " .. tostring(PDTI.VERSION) .. " loaded")
