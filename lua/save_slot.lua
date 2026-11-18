-- 0.37.0: the mod's own progress save.
--
-- The game keeps your progress (level, money, skills, weapons) in one save
-- slot (98 on Windows, also under Proton). With this mod on, it uses slot 86
-- instead, the way restoration-mod uses 77: playing with the mod never
-- touches your vanilla progress, and vanilla play never sees the mod's.
-- The mod's own files (inventory, stash, armory) get their own names on
-- this save too (inventory.lua PDTI.SaveFileName).
--
-- A new save starts at level 0. The first time the menu opens on it, a
-- dialog offers the other start: level 100, 120 Continental coins,
-- $100,000 spending cash and $100,000 offshore.
--
-- This file runs twice: at lib/managers/savefilemanager (the slot, before
-- the game reads any save) and as a part of the mod (the start dialog).
local SLOT = 86

local function log_line(text)
    local f = rawget(_G, "log")
    if f then f("[PDTI SAVE] " .. text) end
end

local SFM = rawget(_G, "SavefileManager")
if SFM and not rawget(_G, "PDTI_SAVE_SLOT_SET") then
    rawset(_G, "PDTI_SAVE_SLOT_SET", true)
    local ok, win = pcall(function() return SystemInfo:platform() == Idstring("WIN32") end)
    if ok and win then
        SFM.PROGRESS_SLOT = SLOT
        SFM.BACKUP_SLOT = SLOT
        rawset(_G, "PDTI_SEPARATE_SAVE", true)
        log_line("progress is kept in slot " .. SLOT .. " (the mod's own save)")
    else
        rawset(_G, "PDTI_SEPARATE_SAVE", false)
        log_line("not Windows: the game's own save slot is used")
    end
end

local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local SaveSlot = PDTI.SaveSlot or {}
PDTI.SaveSlot = SaveSlot

local log = PDTI.Logger("PDTI SAVE")

SaveSlot.SLOT = SLOT
SaveSlot.MARKER = "pdti_save_start.json"
SaveSlot.START = { level = 100, coins = 120, spending = 100000, offshore = 100000 }

local function marker_path()
    return (rawget(_G, "SavePath") or "") .. SaveSlot.MARKER
end

-- Has this save had its start chosen?
function SaveSlot.Started()
    local f = io.open(marker_path(), "r")
    if not f then return false end
    f:close()
    return true
end

function SaveSlot.WriteMarker(choice)
    local f = io.open(marker_path(), "w")
    if not f then log("the start could not be written down"); return false end
    f:write(string.format('{"start":"%s","date":"%s"}', tostring(choice), os.date("%Y-%m-%d")))
    f:close()
    return true
end

local function level()
    local ok, v = pcall(function() return managers.experience:current_level() end)
    return ok and tonumber(v) or nil
end

local function rank()
    local ok, v = pcall(function() return managers.experience:current_rank() end)
    return ok and tonumber(v) or 0
end

-- Level 0 and never infamous: a save that has not been played.
function SaveSlot.Fresh()
    local lv = level()
    return lv ~= nil and lv == 0 and rank() == 0
end

-- Level 100 the way the game levels you (skill points and unlocks come
-- with each level), then the coins and the money.
function SaveSlot.ApplyStart()
    local s = SaveSlot.START
    local exp = managers.experience
    local guard = 0
    while (level() or s.level) < s.level and guard < s.level + 5 do
        local need = exp:next_level_data_points() - exp:next_level_data_current_points()
        if need <= 0 then break end
        exp:add_points(need, false, true)
        guard = guard + 1
    end
    pcall(function() managers.custom_safehouse:add_coins_ingore_locked(s.coins, "pdti_start") end)
    pcall(function() managers.money:_add_to_total(s.spending, { no_offshore = true }, "pdti_start") end)
    pcall(function() managers.money:add_to_offshore(s.offshore) end)
    pcall(function() managers.savefile:save_progress() end)
    log(string.format("started at level %s with %d coins, %d spending and %d offshore",
        tostring(level()), s.coins, s.spending, s.offshore))
    return level() == s.level
end

function SaveSlot.Choose(choice)
    if choice == "level100" then
        local ok, err = pcall(SaveSlot.ApplyStart)
        if not ok then log("the level 100 start failed: " .. tostring(err)) end
    else
        log("started fresh")
    end
    SaveSlot.WriteMarker(choice)
    return true
end

-- The first menu on the mod's own save: the start dialog (once).
function SaveSlot.OnMenu()
    if not PDTI.SeparateSave or not PDTI.SeparateSave() then return false end
    if SaveSlot.Started() or SaveSlot._asked then return false end
    if level() == nil then return false end
    if not SaveSlot.Fresh() then
        -- Played on already (the file was deleted): nothing to offer.
        SaveSlot.WriteMarker("existing")
        return false
    end
    local sm = rawget(_G, "managers") and managers.system_menu
    if not sm then return false end
    SaveSlot._asked = true
    local s = SaveSlot.START
    sm:show({
        id = "pdti_save_start",
        title = "Tactical Inventory: a new save",
        text = "The mod keeps its own progress, apart from your vanilla save.\n\n"
            .. string.format("Start fresh at level 0, or start at level %d with %d Continental coins, "
                .. "$%d spending cash and $%d offshore?", s.level, s.coins, s.spending, s.offshore),
        button_list = {
            { text = "Start at level " .. s.level, callback_func = function() SaveSlot.Choose("level100") end },
            { text = "Start fresh", callback_func = function() SaveSlot.Choose("fresh") end }
        }
    })
    return true
end
