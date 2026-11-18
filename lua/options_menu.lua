-- The mod's page in Options > Mod Options (BLT's MenuHelper). Every change is
-- written at once into the two settings files (Ammo.SaveSettings).
-- Hooked on lib/managers/menumanager, after main.lua.
if not rawget(_G, "PDTI") then
    local dir = rawget(_G, "ModPath")
    if dir then pcall(dofile, dir .. "lua/main.lua") end
end
local PDTI = rawget(_G, "PDTI")
if not PDTI or PDTI._options_menu then return end

local Options = {}
PDTI.Options = Options
Options.MENU_ID = "pdti_options"

local log = PDTI.Logger("PDTI OPTIONS")

-- kind: "toggle", "slider" (min, max, step, int) or "choice" (choices).
-- Settings marked "heist" take effect from the next heist; "hud" redraws the
-- ammunition HUD.
Options.LIST = {
    { section = "General" },
    { key = "enabled", kind = "toggle", title = "Ammunition system",
      desc = "Magazines and loose rounds as inventory items. Off: the game's own ammunition." },
    { key = "ui_scale", kind = "slider", min = 0.7, max = 1.5, step = 0.05, title = "Inventory screen size",
      desc = "Size of the boxes and text of the inventory screen (from the next time it opens). Lower it if the screen does not fit." },
    { key = "item_pictures", kind = "toggle", title = "Pictures of weapons and parts",
      desc = "The game's pictures of your weapons and parts on the inventory screen: in their cells, in a weapon's view and in the market." },
    { key = "item_picture_names", kind = "toggle", title = "Names on pictures",
      desc = "A weapon's or part's name over its picture in the grid, and the weapon's name and weight in PRI / SEC. Off: the picture alone." },

    { key = "safehouse_home", kind = "toggle", title = "Start in the safehouse",
      desc = "The game starts in your safehouse, and you go back there after every job you finish offline. Leaving the safehouse takes you to the menu as usual." },

    { section = "Health and armour" },
    { key = "body_parts", kind = "toggle", heist = true, title = "Health per body part",
      desc = "Head, body, arms and legs have their own health. From the next heist." },
    { key = "heavy_armour", kind = "toggle", heist = true, title = "Heavy armour plates",
      desc = "Flak Jacket, Combined Tactical Vest and ICTV do not regenerate once broken: insert a plate. From the next heist." },

    { section = "Reloading" },
    { key = "wheel_choose", kind = "toggle", title = "Mouse wheel chooses the magazine",
      desc = "The wheel picks the magazine the next reload loads, or the one in the gun: R then takes it out. Keys 1 and 2 still change the weapon." },
    { key = "drop_mode", kind = "choice", title = "Dropped magazines",
      choices = { "Never", "Only empty magazines", "Always" },
      desc = "When the old magazine falls to the floor on a reload (you can pick it up again). A fast reload always drops it." },
    { key = "round_interval", kind = "slider", min = 0.1, max = 1, step = 0.05, title = "Round loading time",
      desc = "Seconds to put one round into a magazine." },
    { key = "hold_time", kind = "slider", min = 0.1, max = 1, step = 0.05, title = "Reload hold time",
      desc = "Holding the reload key longer than this (seconds) is a hold, shorter is a tap." },
    { key = "unblock_bag", kind = "toggle", title = "Ammo bags refill magazines",
      desc = "An ammo bag can be used while a magazine is not full, and its rounds go into your magazines." },
    { key = "akimbo_buttons", kind = "toggle", title = "Akimbo mouse buttons",
      desc = "With akimbo guns the left mouse button fires the left gun and the right one the right gun." },

    { section = "Ammunition HUD" },
    { key = "overlay_always", kind = "toggle", hud = true, title = "Always show",
      desc = "Show the ammunition panel all the time, not only while reloading." },
    { key = "show_mags", kind = "toggle", hud = true, title = "Show the next magazine",
      desc = "The line under the panel shows the rounds of the next magazine." },
    { key = "show_loose", kind = "toggle", hud = true, title = "Show loose rounds", desc = "Show the loose rounds you carry." },
    { key = "show_ammo_type", kind = "toggle", hud = true, title = "Show the calibre", desc = "Show the calibre under the panel." },
    { key = "show_more", kind = "toggle", hud = true, title = "Show \"more\"", desc = "Show a mark when there are more magazines than boxes." },
    { key = "max_boxes", kind = "slider", min = 2, max = 10, step = 1, int = true, hud = true, title = "Magazine boxes",
      desc = "How many magazines the panel shows." },
    { key = "font_size", kind = "slider", min = 10, max = 40, step = 1, int = true, hud = true, title = "Font size",
      desc = "Text size of the panel." },
    { key = "pad_right", kind = "slider", min = 0, max = 1000, step = 10, int = true, hud = true, title = "Distance from the right",
      desc = "Where the panel is, from the right edge." },
    { key = "pad_bottom", kind = "slider", min = 0, max = 700, step = 10, int = true, hud = true, title = "Distance from the bottom",
      desc = "Where the panel is, from the bottom edge." },
}

local function settings() return PDTI.Ammo and PDTI.Ammo.settings end

local function entry_id(entry) return "pdti_opt_" .. entry.key end

-- The value of a menu item as the setting stores it.
function Options.Value(entry, raw)
    if entry.kind == "toggle" then return raw == true or raw == "on" end
    local n = tonumber(raw) or 0
    if entry.kind == "choice" then
        -- The menu counts from 1, the setting from 0.
        return math.max(0, math.min(#entry.choices - 1, math.floor(n + 0.5) - 1))
    end
    if n < entry.min then n = entry.min elseif n > entry.max then n = entry.max end
    -- Dragging a slider with the mouse ignores its step: snap to it (whole
    -- numbers for whole-number settings).
    local step = entry.int and math.max(1, entry.step or 1) or entry.step
    if step and step > 0 then
        n = entry.min + math.floor((n - entry.min) / step + 0.5) * step
        n = math.floor(n * 1000 + 0.5) / 1000
        if n > entry.max then n = entry.max end
    end
    if entry.int then n = math.floor(n + 0.5) end
    return n
end

-- Decimals a slider shows: none for whole numbers, else as many as its step.
function Options.Precision(entry)
    if entry.int then return 0 end
    local text = tostring(entry.step or 1)
    local dot = text:find(".", 1, true)
    return dot and #text - dot or 0
end

-- Sets one setting from the menu, saves, and refreshes what shows it.
function Options.Set(key, raw)
    local entry
    for _, e in ipairs(Options.LIST) do if e.key == key then entry = e end end
    local s = settings()
    if not entry or not s then return false end
    s[key] = Options.Value(entry, raw)
    local saved = PDTI.Ammo.SaveSettings and PDTI.Ammo.SaveSettings()
    if entry.hud then
        if PDTI.Ammo.MarkPanelDirty then pcall(PDTI.Ammo.MarkPanelDirty) end
        if PDTI.Ammo.RefreshHud then pcall(PDTI.Ammo.RefreshHud) end
    end
    return saved ~= false
end

-- The texts of the page (the menu shows localized ids).
function Options.Strings()
    local strings = {
        pdti_options_title = "Tactical Inventory",
        pdti_options_desc = "Settings of PAYDAY 2: Tactical Inventory.",
    }
    for i, entry in ipairs(Options.LIST) do
        if entry.section then
            strings["pdti_opt_section_" .. i] = "-- " .. entry.section .. " --"
        else
            strings[entry_id(entry) .. "_title"] = entry.title
            strings[entry_id(entry) .. "_desc"] = entry.desc
            for c, text in ipairs(entry.choices or {}) do strings[entry_id(entry) .. "_choice_" .. c] = text end
        end
    end
    return strings
end

-- Adds every entry to the page (helper is BLT's MenuHelper).
function Options.Populate(helper, handler)
    local s = settings() or {}
    local count = #Options.LIST
    for i, entry in ipairs(Options.LIST) do
        local priority = count - i + 1 -- MenuHelper shows the highest first
        if entry.section then
            helper:AddButton({
                id = "pdti_opt_section_" .. i, title = "pdti_opt_section_" .. i, desc = "pdti_options_desc",
                callback = "pdti_options_noop", menu_id = Options.MENU_ID, priority = priority
            })
        else
            local id = entry_id(entry)
            local callback = "pdti_options_" .. entry.key
            handler[callback] = function(_, item)
                local raw = item and item.value and item:value()
                Options.Set(entry.key, raw)
                -- The slider shows the snapped value.
                local now = settings()
                if entry.kind == "slider" and item and item.set_value and now and now[entry.key] ~= nil then
                    pcall(item.set_value, item, now[entry.key])
                end
            end
            local params = {
                id = id, title = id .. "_title", desc = id .. "_desc", callback = callback,
                menu_id = Options.MENU_ID, priority = priority
            }
            if entry.kind == "toggle" then
                params.value = s[entry.key] ~= false
                helper:AddToggle(params)
            elseif entry.kind == "slider" then
                params.value = tonumber(s[entry.key]) or entry.min
                params.min, params.max, params.step = entry.min, entry.max, entry.step
                params.show_value = true
                params.display_precision = Options.Precision(entry)
                helper:AddSlider(params)
            else
                local items = {}
                for c in ipairs(entry.choices) do items[c] = id .. "_choice_" .. c end
                params.items = items
                params.value = (tonumber(s[entry.key]) or 0) + 1
                helper:AddMultipleChoice(params)
            end
        end
    end
    handler.pdti_options_noop = function() end
end

local function install()
    local Hooks, MenuHelper = rawget(_G, "Hooks"), rawget(_G, "MenuHelper")
    if not Hooks or not MenuHelper then
        log("BLT's MenuHelper is not available: no options page")
        return false
    end
    Hooks:Add("LocalizationManagerPostInit", "PDTI_Options_Localization", function(loc)
        pcall(function() loc:add_localized_strings(Options.Strings()) end)
    end)
    Hooks:Add("MenuManagerSetupCustomMenus", "PDTI_Options_Setup", function()
        MenuHelper:NewMenu(Options.MENU_ID)
    end)
    Hooks:Add("MenuManagerPopulateCustomMenus", "PDTI_Options_Populate", function()
        local ok, err = pcall(Options.Populate, MenuHelper, MenuCallbackHandler)
        if not ok then log("could not fill the options page: " .. tostring(err)) end
    end)
    Hooks:Add("MenuManagerBuildCustomMenus", "PDTI_Options_Build", function(_, nodes)
        nodes[Options.MENU_ID] = MenuHelper:BuildMenu(Options.MENU_ID)
        MenuHelper:AddMenuItem(nodes["blt_options"], Options.MENU_ID, "pdti_options_title", "pdti_options_desc")
    end)
    return true
end

local ok, err = pcall(install)
if not ok then log("options page failed: " .. tostring(err)) end
PDTI._options_menu = true
