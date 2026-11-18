-- The safehouse as your base (0.30.0, safehouse phase 3 of 5).
--
--   * In the safehouse the mod behaves as in the menu (PDTI.InSafehouse in
--     inventory.lua): the inventory key opens the whole screen (what you
--     bring, the rig and the backpack, the captured loot and the stash), and
--     everything is saved.
--   * "Start in the safehouse" (an option, on): the game goes to the
--     safehouse when it starts, and again after every job you finish offline.
--     Leaving the safehouse takes you to the menu as usual. The main menu is
--     not shown on the way (it goes in the frame the menu opens, under a black
--     screen), and the safehouse's briefing is passed: ready is pressed for
--     you and Bain's intro is skipped (0.30.1).
--   * A raid on the safehouse is waiting: instead of the safehouse, the game's
--     own "safehouse under attack" contract opens (difficulty, One Down,
--     Defend, Ignore). Defend starts the raid offline; Ignore goes on to the
--     safehouse; Back stays in the menu (0.30.3).
--   * The rooms: talking to a room's heister (Wolf in his workshop, ...)
--     opens the room's menu: its tier, your coins, Upgrade (the game's own
--     purchase), and the room's own action (Chains: the menu inventory).
--   * Chains' room: pressing interact while not aiming at anything usable,
--     inside the room (or "Menu inventory" in his room's menu), takes you to
--     the main menu's inventory (build, skills, perks, weapon mods, ...); when
--     you back out of it to the menu's first page you are loaded straight back
--     into the safehouse (0.30.7). The room is the area around where Chains
--     stands (the heisters stand in their rooms). The weapon racks are the
--     game's again (the mod's own screen is on its key).
--   * The laptop (the game's "exit to crime.net", 0.31.1): instead of just
--     leaving, it takes you to crime.net with the Contract Broker open
--     (offline). Pick a heist there and it starts as usual; back out of
--     crime.net to the menu's first page and the safehouse loads again.
--   * The probe: each time the inventory screen opens in the safehouse, the
--     log gets where you stand and what can be used nearby. The stash and
--     market spots of the next version are chosen from it.
local PDTI = rawget(_G, "PDTI")
if not PDTI then return end

local Home = PDTI.Safehouse or {}
PDTI.Safehouse = Home

local log = PDTI.Logger("PDTI HOME")

Home.JOB = "chill"
Home.MENU_NODE = "main"  -- the main menu's first page
Home.DELAY = 0           -- seconds in the main menu before going (0: at once)
Home.GIVE_UP = 30        -- seconds to wait for a dialog to close, then stay
Home.HINT_AFTER = 4      -- seconds in the safehouse before the hint
Home.HINT_TIME = 7
Home.PROBE = true
Home.PROBE_RADIUS = 600  -- cm
Home.PROBE_MAX = 20

-- Global survives the change between the menu and a level (Lua does not).
local function memory()
    local g = rawget(_G, "Global")
    if type(g) ~= "table" then return nil end
    if type(g.pdti_home) ~= "table" then g.pdti_home = {} end
    return g.pdti_home
end
Home._Memory = memory

local function round(v) return math.floor((tonumber(v) or 0) + 0.5) end

local function xyz(pos)
    return string.format("(%d, %d, %d)", round(pos.x), round(pos.y), round(pos.z))
end

local function single_player()
    local g = rawget(_G, "Global")
    local gs = type(g) == "table" and g.game_settings
    return type(gs) == "table" and gs.single_player == true
end

function Home.Enabled()
    if rawget(_G, "restoration") ~= nil then return false end
    local s = PDTI.Ammo and PDTI.Ammo.settings
    return s ~= nil and s.safehouse_home ~= false
end

------------------------------------------------------------ what happened

-- A level was loaded (the safehouse or a heist): the game is past its start,
-- and nothing has ended yet.
function Home.OnLevelStart()
    local mem = memory()
    if not mem then return end
    mem.booted = true
    mem.after_job = false
end

-- A job reached its end screen, won or lost (offline only: after a job with
-- a crew you go back to the lobby with them).
function Home.OnMissionEnd()
    local mem = memory()
    if not mem or PDTI.InSafehouse() then return end
    mem.after_job = single_player()
end

------------------------------------------------------------ the main menu

-- Why the game stays in the menu (nil: it may go).
function Home.Blocked(invited)
    local g = rawget(_G, "Global")
    if type(g) ~= "table" then return "no game data" end
    if invited then return "you were invited to a game" end
    if g.load_start_menu_lobby then return "you are in a lobby" end
    if g.exe_argument_level then return "a level was asked for at start" end
    local nm = rawget(_G, "managers") and managers.network
    local session = nm and type(nm.session) == "function" and nm:session()
    if session and not single_player() then return "you are online" end
    return nil
end

-- The main menu was entered (after the game's own code).
function Home.OnMenuMain(invited)
    local mem = memory()
    if not mem then return false end
    local to_inventory = mem.to_inventory == true
    local to_broker = mem.to_broker == true
    mem.to_inventory = nil
    mem.to_broker = nil
    local reason = (to_broker and "back from crime.net") or (to_inventory and "back from the inventory")
        or (not mem.booted and "the game started")
        or (mem.after_job == true and "a job ended") or nil
    -- Asked once: whatever comes of it, the next time in the menu you stay.
    mem.booted = true
    mem.after_job = false
    mem.skip_briefing = nil
    Home.pending = nil
    Home.raid_offered = nil
    pcall(Home.InstallRaidHooks)
    -- The trip to the menu inventory is yours: it comes back with the option
    -- off too.
    if not reason or (not to_inventory and not to_broker and not Home.Enabled()) then return false end
    local why = Home.Blocked(invited)
    if why then
        log("staying in the menu: " .. why)
        return false
    end
    if to_broker then
        Home.pending = { waited = 0, reason = reason, broker = true }
        log("the contract broker: back to the safehouse when you return to the menu's first page")
        return true
    end
    if to_inventory then
        Home.pending = { waited = 0, reason = reason, inventory = true }
        log("the menu inventory: back to the safehouse when you return to the menu's first page")
        return true
    end
    Home.pending = { waited = 0, reason = reason }
    Home.Cover(true)
    log(reason .. ": going to the safehouse (the option \"Start in the safehouse\")")
    return true
end

-- "ready": the main menu's first page, nothing in the way. "dialog": a
-- dialog is open (it must be seen). "wait": the save is busy or the menu is
-- not up yet. Anything else: you went somewhere (its name).
function Home.MenuState()
    local m = rawget(_G, "managers")
    if type(m) ~= "table" then return "wait" end
    local sm = m.system_menu
    if sm and type(sm.is_active) == "function" and sm:is_active() then return "dialog" end
    local sf = m.savefile
    if sf and type(sf.is_active) == "function" and sf:is_active() then return "wait" end
    local mm = m.menu
    local menu = mm and type(mm.active_menu) == "function" and mm:active_menu()
    local logic = type(menu) == "table" and menu.logic
    local node = logic and type(logic.selected_node) == "function" and logic:selected_node()
    local params = node and type(node.parameters) == "function" and node:parameters()
    local name = type(params) == "table" and params.name
    if type(name) ~= "string" then return "wait" end
    if name ~= Home.MENU_NODE then return name end
    return "ready"
end

-- A black screen over the main menu while the way to the safehouse is
-- pending, so the menu is not seen (the loading screen follows). Taken away
-- whenever you stay, and while a dialog waits for you.
Home.COVER = { blend_mode = "normal", fade_in = 0, sustain = 60, fade_out = 0.25, play_paused = true }

function Home.Cover(on)
    local m = rawget(_G, "managers")
    local fx = type(m) == "table" and m.overlay_effect
    if not fx then return false end
    if on then
        if Home.cover_id ~= nil then return true end
        local color = rawget(_G, "Color")
        local kind = type(color)
        if (kind ~= "table" and kind ~= "userdata") or type(fx.play_effect) ~= "function" then return false end
        local data = {}
        for k, v in pairs(Home.COVER) do data[k] = v end
        data.color = color.black
        local ok, id = pcall(fx.play_effect, fx, data)
        Home.cover_id = ok and id or nil
        return Home.cover_id ~= nil
    end
    local id = Home.cover_id
    Home.cover_id = nil
    if id ~= nil and type(fx.stop_effect) == "function" then pcall(fx.stop_effect, fx, id) end
    return id ~= nil
end

-- Starts the safehouse the way the game's own "enter safehouse" does.
function Home.Go(reason)
    local mch = rawget(_G, "MenuCallbackHandler")
    if type(mch) ~= "table" or type(mch.play_single_player) ~= "function"
        or type(mch.start_single_player_job) ~= "function" then
        log("cannot go to the safehouse: the game's menu functions are not there")
        return false
    end
    log("loading the safehouse (" .. tostring(reason) .. ")")
    local ok, err = pcall(function()
        mch:play_single_player()
        mch:start_single_player_job({ job_id = Home.JOB, difficulty = "normal" })
    end)
    if not ok then log("the safehouse could not be started: " .. tostring(err)) end
    -- The safehouse's briefing is passed (IngameWaitingForPlayersState).
    local mem = memory()
    if mem then mem.skip_briefing = ok or nil end
    return ok
end

-- The trip to the menu inventory: once the menu has settled, open its page
-- (again once if it did not open); back to the safehouse only after you
-- were on another page and are back on the first one. If the page will not
-- open you stay in the menu (open it yourself; the way back still works).
Home.INVENTORY_DELAY = 0.5 -- seconds in the menu before the page is opened
Home.INVENTORY_RETRY = 2   -- seconds to see the page before trying again

local function open_inventory_page(p)
    p.tries = (p.tries or 0) + 1
    p.asked_at = p.waited
    local m = rawget(_G, "managers")
    local mm = m and m.menu
    if not mm or type(mm.open_node) ~= "function" then return false, "no menu" end
    local ok, err = pcall(mm.open_node, mm, Home.INVENTORY_NODE)
    log(ok and ("opening the menu's \"" .. Home.INVENTORY_NODE .. "\" page (try " .. p.tries .. ")")
        or ("the inventory page could not open: " .. tostring(err)))
    return ok, err
end

function Home.InventoryTick(p)
    local state = Home.MenuState()
    if state == "wait" or state == "dialog" then
        if not p.left_main and p.waited > Home.GIVE_UP then
            Home.pending = nil
            log("the menu was busy for too long: staying in the menu")
        end
        return false
    end
    if state ~= "ready" then
        -- On a page of the menu (the inventory or one of its pages).
        if state ~= p.page then
            p.page = state
            log("in the menu's \"" .. tostring(state) .. "\" page")
        end
        p.left_main = true
        return false
    end
    if p.left_main then
        Home.pending = nil
        return Home.Go(p.reason)
    end
    if p.waited < Home.INVENTORY_DELAY then return false end
    if not p.tries or (p.tries < 2 and p.waited - p.asked_at >= Home.INVENTORY_RETRY) then
        open_inventory_page(p)
        return false
    end
    if p.tries >= 2 and not p.gave_up and p.waited - p.asked_at >= Home.INVENTORY_RETRY then
        p.gave_up = true
        log("the inventory page did not open: open it yourself, the safehouse loads when you come back here")
        PDTI.Hint("Open the Inventory yourself: the safehouse loads again when you are back on this page.", Home.HINT_TIME)
    end
    return false
end

-- The trip to the Contract Broker: the game opens crime.net by itself
-- (Global.load_crime_net); once it is up, the broker is opened on it, once.
-- Back on the menu's first page after crime.net: the safehouse again. If
-- crime.net does not come, it is opened (once), then you are told.
Home.BROKER_NODE = "contract_broker"
Home.CRIMENET_NODES = { crimenet_single_player = true, crimenet = true }
Home.BROKER_TWEAK = "exit_to_crimenet"

local function open_node(name, what)
    local m = rawget(_G, "managers")
    local mm = m and m.menu
    if not mm or type(mm.open_node) ~= "function" then return false end
    local ok, err = pcall(mm.open_node, mm, name)
    log(ok and ("opening " .. what) or (what .. " could not open: " .. tostring(err)))
    return ok
end

function Home.BrokerTick(p)
    local state = Home.MenuState()
    if state == "wait" or state == "dialog" then
        if not p.left_main and p.waited > Home.GIVE_UP then
            Home.pending = nil
            log("the menu was busy for too long: staying in the menu")
        end
        return false
    end
    if state ~= "ready" then
        if state ~= p.page then
            p.page = state
            p.page_at = p.waited
            log("in the menu's \"" .. tostring(state) .. "\" page")
        end
        p.left_main = true
        if Home.CRIMENET_NODES[state] and not p.broker_tried and p.waited - p.page_at >= Home.INVENTORY_DELAY then
            p.broker_tried = true
            open_node(Home.BROKER_NODE, "the Contract Broker")
        end
        return false
    end
    if p.left_main then
        Home.pending = nil
        return Home.Go(p.reason)
    end
    if p.waited < Home.INVENTORY_RETRY then return false end
    if not p.crimenet_tried then
        -- The game did not open crime.net: open it the way it does.
        p.crimenet_tried = true
        p.asked_at = p.waited
        local mch = rawget(_G, "MenuCallbackHandler")
        if type(mch) == "table" and type(mch.play_single_player) == "function" then
            pcall(mch.play_single_player, mch)
        end
        open_node("crimenet_single_player", "crime.net")
        return false
    end
    if not p.gave_up and p.waited - p.asked_at >= Home.INVENTORY_RETRY then
        p.gave_up = true
        log("crime.net did not open: open it yourself, the safehouse loads when you come back here")
        PDTI.Hint("Open crime.net yourself: the safehouse loads again when you are back on this page.", Home.HINT_TIME)
    end
    return false
end

-- Every frame of the main menu while a trip to the safehouse is pending.
function Home.MenuTick(dt)
    local p = Home.pending
    if not p then return false end
    p.waited = p.waited + (tonumber(dt) or 0)
    if p.broker then return Home.BrokerTick(p) end
    if p.inventory then return Home.InventoryTick(p) end
    if p.waited < Home.DELAY then return false end
    local state = Home.MenuState()
    if state == "wait" or state == "dialog" then
        -- A dialog is for you to read: no black screen over it.
        if state == "dialog" then Home.Cover(false) end
        if p.waited > Home.GIVE_UP then
            Home.pending = nil
            Home.Cover(false)
            log("the menu was busy for too long: staying in the menu")
        end
        return false
    end
    Home.pending = nil
    if state ~= "ready" then
        Home.Cover(false)
        log("you went to \"" .. tostring(state) .. "\" in the menu: staying there")
        return false
    end
    if not p.no_raid and Home.RaidWaiting() then
        Home.Cover(false)
        if Home.OfferRaid() then return false end
    end
    local ok = Home.Go(p.reason)
    if not ok then Home.Cover(false) end
    return ok
end

------------------------------------------------------- the safehouse's briefing

-- Every frame of the briefing (IngameWaitingForPlayersState) of a safehouse
-- the mod sent you to: ready, as the button does it, and the start; then
-- Bain's intro on the black screen is skipped as soon as the game allows it
-- (the way the game's own "-auto_enter_level" start does). "start", "skip"
-- or "wait".
function Home.BriefingTick(state)
    if type(state) ~= "table" or not state._pdti_auto then return "wait" end
    local m = rawget(_G, "managers")
    if not state._starting_game_intro then
        local mc = type(m) == "table" and m.menu_component
        if mc and type(mc.on_ready_pressed_mission_briefing_gui) == "function" then
            mc:on_ready_pressed_mission_briefing_gui(true)
        end
        if not state._starting_game_intro and type(state.start_game_intro) == "function" then
            state:start_game_intro()
        end
        return "start"
    end
    if state._skip_promt_shown and state._audio_started and not state._skipped and type(state._skip) == "function" then
        local hud = type(m) == "table" and m.hud
        if hud and type(hud.blackscreen_skip_circle_done) == "function" then hud:blackscreen_skip_circle_done() end
        state:_skip()
        state._pdti_auto = nil
        return "skip"
    end
    return "wait"
end

------------------------------------------------------------------ the raid

Home.RAID_NODE = "crimenet_contract_chill"

-- The game says the safehouse is under attack (the raid contract is up).
function Home.RaidWaiting()
    local m = rawget(_G, "managers")
    local cs = type(m) == "table" and m.custom_safehouse
    if not cs or type(cs.is_being_raided) ~= "function" then return false end
    local ok, raided = pcall(cs.is_being_raided, cs)
    return ok and raided == true
end

-- Opens the game's raid contract (as the safehouse page's "Defend" does).
function Home.OfferRaid()
    local m = rawget(_G, "managers")
    local mm = type(m) == "table" and m.menu
    if not mm or type(mm.open_node) ~= "function" then return false end
    local ok, err = pcall(mm.open_node, mm, Home.RAID_NODE)
    if not ok then
        log("the safehouse raid could not be shown: " .. tostring(err))
        return false
    end
    Home.raid_offered = true
    log("the safehouse is under attack: choose the difficulty and defend it, or ignore it")
    return true
end

-- Defend: the game starts the raid offline only when the game is set to
-- offline already (it is not, in the main menu): set it first.
local function make_play_raid(orig)
    return function(self, item, ...)
        if Home.raid_offered then
            Home.raid_offered = nil
            local m = rawget(_G, "managers")
            local nm = type(m) == "table" and m.network
            local session = nm and type(nm.session) == "function" and nm:session()
            local mch = rawget(_G, "MenuCallbackHandler")
            if not session and mch and type(mch.play_single_player) == "function" then
                local ok, err = pcall(mch.play_single_player, mch)
                if not ok then log("the raid could not be set offline: " .. tostring(err)) end
            end
            log("defending the safehouse")
        end
        return orig(self, item, ...)
    end
end

-- Ignore: on to the safehouse, as if there had been no raid.
local function make_ignore_raid(orig)
    return function(self, item, ...)
        local offered = Home.raid_offered
        Home.raid_offered = nil
        local r = orig(self, item, ...)
        if offered and Home.Enabled() then
            Home.pending = { waited = 0, reason = "the raid was ignored", no_raid = true }
            Home.Cover(true)
            log("the raid was ignored: going to the safehouse")
        end
        return r
    end
end

------------------------------------------------------------------ the rooms

-- What a room's menu offers besides Upgrade (room id -> action).
Home.ROOM_ACTIONS = { spanish = "menu_inventory", terry = "market" }
Home.INVENTORY_NODE = "inventory" -- the main menu's inventory page

local function room_data(room_id)
    local td = rawget(_G, "tweak_data")
    local rooms = type(td) == "table" and type(td.safehouse) == "table" and td.safehouse.rooms
    if type(rooms) ~= "table" then return nil end
    for _, r in ipairs(rooms) do
        if type(r) == "table" and r.room_id == room_id then return r end
    end
    return nil
end
Home.RoomData = room_data

-- The room of a heister (the game's own mapping: wolf -> german, ...).
function Home.RoomOfHeister(ext)
    if type(ext) ~= "table" then return nil end
    local who = ext.character
    if type(who) ~= "string" and type(ext.tweak_data) == "string" then
        who = ext.tweak_data:match("^talk_to_heister_(.+)$")
    end
    if type(who) ~= "string" then return nil end
    local cm = rawget(_G, "CriminalsManager")
    local convert = cm and cm.convert_new_to_old_character_workname
    local room = type(convert) == "function" and convert(who) or who
    if room == "ecp_male" or room == "ecp_female" then room = "ecp" end
    if not room_data(room) then return nil end
    return room
end

local function safehouse_manager()
    local m = rawget(_G, "managers")
    local cs = type(m) == "table" and m.custom_safehouse
    if type(cs) ~= "table" then return nil end
    for _, f in ipairs({ "get_room_current_tier", "get_room_max_tier", "get_next_tier_unlocked",
        "can_afford_room_tier", "get_upgrade_cost", "purchase_room_tier", "set_room_tier", "coins" }) do
        if type(cs[f]) ~= "function" then return nil end
    end
    return cs
end

-- { tier, max, next (nil at the top), cost, coins, affordable }
function Home.RoomState(room_id)
    local cs = safehouse_manager()
    if not cs or not room_data(room_id) then return nil end
    local tier = cs:get_room_current_tier(room_id)
    local max = cs:get_room_max_tier(room_id)
    if type(tier) ~= "number" or type(max) ~= "number" then return nil end
    local st = { tier = tier, max = max, coins = cs:coins() }
    local nxt = cs:get_next_tier_unlocked(room_id)
    if type(nxt) == "number" and nxt <= max then
        st.next = nxt
        st.cost = cs:get_upgrade_cost(room_id, nxt)
        st.affordable = cs:can_afford_room_tier(room_id, nxt) == true
    end
    return st
end

local function text(id, macros)
    local m = rawget(_G, "managers")
    local loc = type(m) == "table" and m.localization
    if loc and type(loc.text) == "function" and type(id) == "string" then
        local t = loc:text(id, macros)
        if type(t) == "string" and t ~= "" then return t end
    end
    return nil
end

-- Buys the next tier the way the safehouse page does.
function Home.UpgradeRoom(room_id)
    local st = Home.RoomState(room_id)
    if not st or not st.next then return false, "the room is at its top tier" end
    if not st.affordable then return false, "not enough coins" end
    local cs = safehouse_manager()
    cs:purchase_room_tier(room_id, st.next)
    cs:set_room_tier(room_id, st.next)
    local m = rawget(_G, "managers")
    local sf = m.savefile
    if sf and type(sf.save_progress) == "function" then sf:save_progress() end
    log(string.format("the room %s: upgraded to tier %d for %s coin(s)", room_id, st.next, tostring(st.cost)))
    local name = text((room_data(room_id) or {}).name_id) or room_id
    PDTI.Hint(string.format("%s: tier %d. The room changes the next time you enter the safehouse.", name, st.next),
        Home.HINT_TIME)
    return true
end

-- The room's menu (the game's own dialog).
function Home.ShowRoomMenu(room_id)
    local m = rawget(_G, "managers")
    local sm = type(m) == "table" and m.system_menu
    local data = room_data(room_id)
    local st = Home.RoomState(room_id)
    if not sm or type(sm.show) ~= "function" or not data or not st then return false end
    local name = text(data.name_id) or room_id
    local lines = { string.format("Tier %d of %d. Continental coins: %s.", st.tier, st.max, tostring(st.coins)) }
    -- Its room bonus (perks.lua).
    local perks = PDTI.Perks
    if perks and perks.RoomLines then
        local bonus = perks.RoomLines(room_id, st.tier)
        if #bonus > 0 then lines[#lines + 1] = "\n" .. table.concat(bonus, "\n") end
    end
    if st.next then
        local about = text(type(data.help_id) == "string" and (data.help_id .. "_" .. st.next) or nil)
        if about then lines[#lines + 1] = "\nTier " .. st.next .. ": " .. about end
        lines[#lines + 1] = string.format("\nUpgrade to tier %d: %s coin(s)%s", st.next, tostring(st.cost),
            st.affordable and "." or " (not enough coins).")
    else
        lines[#lines + 1] = "\nThe room is at its top tier."
    end
    local buttons = {}
    if st.next and st.affordable then
        buttons[#buttons + 1] = { text = string.format("Upgrade to tier %d (%s coins)", st.next, tostring(st.cost)),
            callback_func = function() Home.UpgradeRoom(room_id) end }
    end
    if Home.ROOM_ACTIONS[room_id] == "menu_inventory" then
        buttons[#buttons + 1] = { text = "Menu inventory (leaves the safehouse, comes back)",
            callback_func = function() Home.ToMenuInventory() end }
    end
    -- Scarface runs the market (market.lua): its prices and contracts.
    local market = PDTI.Market
    if Home.ROOM_ACTIONS[room_id] == "market" and market and market.Enabled() then
        buttons[#buttons + 1] = { text = "Market (sell loot, contracts)",
            callback_func = function()
                if PDTI.OpenMarket then
                    local ok = PDTI.OpenMarket()
                    log(ok and "the market is open (Scarface)" or "the market could not be opened")
                end
            end }
    end
    buttons[#buttons + 1] = { text = "Close", cancel_button = true }
    sm:show({ id = "pdti_room_menu", title = name, text = table.concat(lines, "\n"), button_list = buttons,
        focus_button = 1 })
    log("the room " .. room_id .. ": its menu (tier " .. st.tier .. " of " .. st.max .. ")")
    return true
end

-- Rooms you can use by pressing interact inside them (room id -> zone).
-- The zone is centred on the room's heister (found when you arrive), else
-- on `at`; `radius` across and `height` up or down, in cm.
Home.ROOM_ZONES = {
    spanish = { at = { x = 650, y = -1674, z = 0 }, radius = 600, height = 250 }
}
Home.ZONE_CHECK = 0.25 -- seconds between checks of where you are

local function zone_center(room_id)
    local zone = Home.ROOM_ZONES[room_id]
    if not zone then return nil end
    Home.zone_at = Home.zone_at or {}
    return Home.zone_at[room_id] or zone.at
end

-- Where the room's heister stands (once per visit, when you arrive).
function Home.FindZones()
    Home.zone_at = Home.zone_at or {}
    for _, h in ipairs(Home.Heisters()) do
        if h.room and Home.ROOM_ZONES[h.room] and not Home.zone_at[h.room] then
            Home.zone_at[h.room] = { x = h.pos.x, y = h.pos.y, z = h.pos.z }
            log(string.format("the room %s is around %s (where its heister stands)", h.room, xyz(h.pos)))
        end
    end
    -- Found them all: not looked for again this visit.
    for room_id in pairs(Home.ROOM_ZONES) do
        if not Home.zone_at[room_id] then return false end
    end
    Home.zones_found = true
    return true
end

-- The room whose zone holds `pos` (nil: none).
function Home.RoomAt(pos)
    if type(pos) ~= "table" and type(pos) ~= "userdata" then return nil end
    for room_id, zone in pairs(Home.ROOM_ZONES) do
        local c = zone_center(room_id)
        local dx, dy, dz = pos.x - c.x, pos.y - c.y, pos.z - c.z
        if dx * dx + dy * dy <= zone.radius * zone.radius and math.abs(dz) <= zone.height then
            return room_id
        end
    end
    return nil
end

local function player_pos()
    local unit = PDTI.PlayerUnit and PDTI.PlayerUnit()
    local is_alive = rawget(_G, "alive")
    if unit == nil or (is_alive and not is_alive(unit)) then return nil end
    if type(unit) == "table" and type(unit.position) ~= "function" then return nil end
    return unit:position()
end

local function room_name(room_id)
    return text((room_data(room_id) or {}).name_id) or room_id
end

-- The interact key was pressed: in a room with an action and not aiming at
-- anything usable, the room's action runs (true: the game's interact does
-- not run).
function Home.RoomInteract()
    if not PDTI.InSafehouse() then return false end
    if PDTI.IsUIOpen and PDTI.IsUIOpen() then return false end
    local m = rawget(_G, "managers")
    local im = type(m) == "table" and m.interaction
    local target = im and type(im.active_unit) == "function" and im:active_unit()
    local is_alive = rawget(_G, "alive")
    if target ~= nil and (not is_alive or is_alive(target)) then return false end
    local room = Home.RoomAt(player_pos())
    if not room or Home.ROOM_ACTIONS[room] ~= "menu_inventory" then return false end
    log("the room " .. room .. ": to the menu inventory")
    return Home.ToMenuInventory()
end

-- Every frame in the safehouse: walking into a usable room says what to do.
function Home.ZoneTick(dt)
    Home.zone_wait = (Home.zone_wait or 0) + (tonumber(dt) or 0)
    if Home.zone_wait < Home.ZONE_CHECK then return end
    Home.zone_wait = 0
    if not Home.zones_found then Home.FindZones() end
    local room = Home.RoomAt(player_pos())
    if room == Home.in_room then return end
    Home.in_room = room
    if room and Home.ROOM_ACTIONS[room] == "menu_inventory" then
        PDTI.Hint(room_name(room) .. ": press interact (aiming at nothing) for the menu inventory (you come back here)",
            Home.HINT_TIME)
        log("you walked into the room " .. room)
    end
end

-- The talk took the daily side job: the room's menu waits for the next talk.
function Home.OnDailyTaken(ext)
    if not PDTI.InSafehouse() then return false end
    local room = Home.RoomOfHeister(ext)
    if not room then return false end
    log("the room " .. room .. ": this talk took the daily side job, the room's menu is on the next talk")
    PDTI.Hint("Daily side job taken. Talk to them again for the room's menu.", Home.HINT_TIME)
    return true
end

-- Every heister in the level with their room, where they stand and whether
-- they can be talked to (logged once on arrival: a room whose heister is
-- missing here cannot have its menu).
function Home.Heisters()
    local out = {}
    local im = rawget(_G, "managers") and managers.interaction
    local units = im and im._interactive_units
    if type(units) ~= "table" then return out end
    local is_alive = rawget(_G, "alive")
    for _, unit in pairs(units) do
        if not is_alive or is_alive(unit) then
            local ext = unit:interaction()
            local who = type(ext) == "table" and (ext.character
                or (type(ext.tweak_data) == "string" and ext.tweak_data:match("^talk_to_heister_(.+)$")))
            if who then
                out[#out + 1] = { who = who, room = Home.RoomOfHeister(ext), pos = unit:position(),
                    active = ext._active == true }
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.who) < tostring(b.who) end)
    return out
end

function Home.LogHeisters()
    local list = Home.Heisters()
    local parts = {}
    for _, h in ipairs(list) do
        parts[#parts + 1] = string.format("%s (%s) at %s%s", tostring(h.who), tostring(h.room or "no room"), xyz(h.pos),
            h.active and "" or " off")
    end
    log("heisters here: " .. (#parts > 0 and table.concat(parts, "; ") or "none found"))
    return #list
end

-- A heister was talked to (after the game's own answer).
function Home.OnHeister(ext)
    if not PDTI.InSafehouse() then return false end
    local room = Home.RoomOfHeister(ext)
    if not room then
        log("a heister without a room: " .. tostring(type(ext) == "table" and (ext.character or ext.tweak_data) or "?"))
        return false
    end
    return Home.ShowRoomMenu(room)
end

---------------------------------------------------------- the menu inventory

-- Leaves the safehouse for the main menu's inventory; the menu brings you
-- back (Home.OnMenuMain / MenuTick). The way the game's "end game" leaves.
function Home.ToMenuInventory()
    if not PDTI.InSafehouse() then return false end
    local mch = rawget(_G, "MenuCallbackHandler")
    local mem = memory()
    if not mem or type(mch) ~= "table" or type(mch._dialog_end_game_yes) ~= "function" then
        log("cannot leave for the menu inventory: the game's functions are not there")
        return false
    end
    mem.to_inventory = true
    log("leaving for the menu inventory (back to the safehouse after it)")
    local ok, err = pcall(mch._dialog_end_game_yes, mch)
    if not ok then
        mem.to_inventory = nil
        log("could not leave the safehouse: " .. tostring(err))
    end
    return ok
end

-- The laptop: leaves the safehouse for crime.net with the Contract Broker
-- open (offline only; with a crew it stays the game's).
function Home.ToBroker()
    if not PDTI.InSafehouse() or not single_player() then return false end
    local mch = rawget(_G, "MenuCallbackHandler")
    local mem = memory()
    local g = rawget(_G, "Global")
    if not mem or type(g) ~= "table" or type(mch) ~= "table" or type(mch._dialog_end_game_yes) ~= "function" then
        log("cannot leave for the Contract Broker: the game's functions are not there")
        return false
    end
    mem.to_broker = true
    g.load_crime_net = true
    log("leaving for the Contract Broker (back to the safehouse when you leave crime.net)")
    local ok, err = pcall(mch._dialog_end_game_yes, mch)
    if not ok then
        mem.to_broker = nil
        g.load_crime_net = nil
        log("could not leave the safehouse: " .. tostring(err))
    end
    return ok
end

-- An interaction finished in the safehouse: the laptop goes to the broker.
-- Every other one is logged once by name (to find the safehouse's objects).
Home.seen_tweaks = Home.seen_tweaks or {}
function Home.OnInteract(ext)
    if not PDTI.InSafehouse() or type(ext) ~= "table" then return false end
    local tweak = ext.tweak_data
    if type(tweak) == "string" and not Home.seen_tweaks[tweak] then
        Home.seen_tweaks[tweak] = true
        log("used in the safehouse: " .. tweak)
    end
    if tweak ~= Home.BROKER_TWEAK then return false end
    return Home.ToBroker()
end

------------------------------------------------------------------ the probe


-- What can be used near the player, nearest first: { dist, tweak, unit_id,
-- pos, name, active }.
function Home.Nearby(origin, radius)
    local out = {}
    local im = rawget(_G, "managers") and managers.interaction
    local units = im and im._interactive_units
    if type(units) ~= "table" then return out end
    local is_alive = rawget(_G, "alive")
    for _, unit in pairs(units) do
        if not is_alive or is_alive(unit) then
            local pos = unit:position()
            local dx, dy, dz = pos.x - origin.x, pos.y - origin.y, pos.z - origin.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= radius then
                local ext = unit:interaction()
                local data = unit:unit_data()
                local name = unit:name()
                out[#out + 1] = {
                    dist = dist, pos = pos,
                    tweak = ext and ext.tweak_data or "?",
                    unit_id = type(data) == "table" and data.unit_id or "?",
                    name = name and type(name.key) == "function" and name:key() or "?",
                    active = ext ~= nil and ext._active == true
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- Writes where you stand and what is near to the log.
function Home.Probe()
    if not Home.PROBE or not PDTI.InSafehouse() then return false end
    local unit = PDTI.PlayerUnit and PDTI.PlayerUnit()
    local is_alive = rawget(_G, "alive")
    if unit == nil or (is_alive and not is_alive(unit)) then return false end
    local pos = unit:position()
    log("probe: you stand at " .. xyz(pos))
    local near = Home.Nearby(pos, Home.PROBE_RADIUS)
    for i = 1, math.min(#near, Home.PROBE_MAX) do
        local n = near[i]
        log(string.format("probe: %.1f m  tweak=%s  unit_id=%s  at %s  name=%s%s", n.dist / 100, tostring(n.tweak),
            tostring(n.unit_id), xyz(n.pos), tostring(n.name), n.active and "" or "  (off)"))
    end
    if #near == 0 then log("probe: nothing to use within " .. round(Home.PROBE_RADIUS / 100) .. " m") end
    return true, #near
end

------------------------------------------------------------------ hooks

local hooks = {}

local function wrap(class_name, fn_name, make)
    return PDTI.Wrap(hooks, "home", class_name, fn_name, make)
end

local function make_mission_end(orig)
    return function(self, ...)
        local r = orig(self, ...)
        pcall(Home.OnMissionEnd)
        return r
    end
end

local function make_heister_interact(orig)
    return function(self, player, ...)
        -- The daily side job is taken by talking to its heister: that talk
        -- stays the game's alone.
        local daily = type(self.is_daily_contractor) == "function" and type(self.is_daily_accepted) == "function"
            and self:is_daily_contractor() and not self:is_daily_accepted()
        local r = orig(self, player, ...)
        if daily then
            pcall(Home.OnDailyTaken, self)
        else
            local ok, err = pcall(Home.OnHeister, self)
            if not ok then log("the room's menu failed: " .. tostring(err)) end
        end
        return r
    end
end

local function make_room_interact(orig)
    return function(self, t, input, ...)
        if type(input) == "table" and input.btn_interact_press then
            local ok, used = pcall(Home.RoomInteract)
            if ok and used then return false end
        end
        return orig(self, t, input, ...)
    end
end

local function make_interact(orig)
    return function(self, ...)
        local ok, used = pcall(Home.OnInteract, self)
        if ok and used then return true end
        return orig(self, ...)
    end
end

local function make_menu_enter(orig)
    return function(self, ...)
        -- The game's own code uses the invite up: look before it runs.
        local g = rawget(_G, "Global")
        local invited = type(g) == "table" and g.boot_invite ~= nil
        local r = orig(self, ...)
        -- The armory first (armory.lua): a heist left unfinished is lost.
        local armory = PDTI.Armory
        if armory and armory.OnMenu then pcall(armory.OnMenu) end
        -- A new save of the mod's own: the start dialog (save_slot.lua). The
        -- way to the safehouse waits while it is open.
        local slot = PDTI.SaveSlot
        if slot and slot.OnMenu then pcall(slot.OnMenu) end
        local ok, err = pcall(Home.OnMenuMain, invited)
        if not ok then log("the way home failed: " .. tostring(err)) end
        -- At once, in this same frame (as the game's own "-level" start
        -- does): the menu is never seen. A dialog or a busy save: the
        -- menu's update tries again.
        if ok and Home.pending then
            local ok2, err2 = pcall(Home.MenuTick, 0)
            if not ok2 then
                Home.pending = nil
                Home.Cover(false)
                log("the way home failed: " .. tostring(err2))
            end
        end
        return r
    end
end

local function make_menu_update(orig)
    return function(self, t, dt, ...)
        if Home.pending then
            local ok, err = pcall(Home.MenuTick, dt)
            if not ok then
                Home.pending = nil
                Home.Cover(false)
                log("the way home failed: " .. tostring(err))
            end
        end
        return orig(self, t, dt, ...)
    end
end

local function make_briefing_enter(orig)
    return function(self, ...)
        local mem = memory()
        local asked = mem ~= nil and mem.skip_briefing == true
        if mem then mem.skip_briefing = nil end
        local r = orig(self, ...)
        if asked and Home.Enabled() and PDTI.InSafehouse() and single_player() then
            self._pdti_auto = true
            log("the safehouse's briefing: ready is pressed for you")
        end
        return r
    end
end

local function make_briefing_update(orig)
    return function(self, t, dt, ...)
        local r = orig(self, t, dt, ...)
        if self._pdti_auto then
            local ok, err = pcall(Home.BriefingTick, self)
            if not ok then
                self._pdti_auto = nil
                log("passing the briefing failed (press ready yourself): " .. tostring(err))
            end
        end
        return r
    end
end

-- In a level (called every frame until the class is there).
function Home.InstallGameHooks()
    local a = wrap("MissionEndState", "at_enter", make_mission_end)
    local c = wrap("CivilianHeisterInteractionExt", "interact", make_heister_interact)
    -- The safehouse's player state has its own interact check.
    local d = wrap("PlayerCivilian", "_check_action_interact", make_room_interact)
    -- The laptop (its class is the plain or the "use" interaction).
    wrap("BaseInteractionExt", "interact", make_interact)
    wrap("UseInteractionExt", "interact", make_interact)
    return a and c and d
end

-- In the menu (hooks_home.lua, once the main menu's state is loaded).
function Home.InstallMenuHooks()
    local a = wrap("MenuMainState", "at_enter", make_menu_enter)
    local b = wrap("MenuMainState", "update", make_menu_update)
    pcall(Home.InstallRaidHooks)
    return a and b
end

-- The raid contract's buttons (MenuCallbackHandler, the menu's).
function Home.InstallRaidHooks()
    local a = wrap("MenuCallbackHandler", "play_chill_combat", make_play_raid)
    local b = wrap("MenuCallbackHandler", "ignore_chill_combat", make_ignore_raid)
    return a and b
end

-- The briefing of a level (hooks_home.lua, once that state's class is loaded).
function Home.InstallBriefingHooks()
    local a = wrap("IngameWaitingForPlayersState", "at_enter", make_briefing_enter)
    local b = wrap("IngameWaitingForPlayersState", "update", make_briefing_update)
    return a and b
end

-- Every frame of a level. In the safehouse, once: what the inventory key
-- is for there (and the captured bags still waiting for a choice).
function Home.GameTick(dt)
    Home.InstallGameHooks()
    if not PDTI.InSafehouse() then return end
    Home.ZoneTick(dt)
    if Home.hinted then return end
    Home.hint_wait = (Home.hint_wait or 0) + (tonumber(dt) or 0)
    if Home.hint_wait < Home.HINT_AFTER then return end
    Home.hinted = true
    pcall(Home.LogHeisters)
    local stash = PDTI.Stash
    local waiting = stash and stash.Enabled() and #stash.Pending() or 0
    if waiting > 0 then
        PDTI.Hint(string.format("Tactical Inventory: %d captured bag(s) wait for your choice (inventory key)", waiting),
            Home.HINT_TIME)
    else
        PDTI.Hint("Tactical Inventory: the inventory key opens your loadout, the stash and the captured loot",
            Home.HINT_TIME)
    end
end

function Home.Reset()
    Home.Cover(false)
    Home.pending = nil
    Home.raid_offered = nil
    Home.hinted, Home.hint_wait = nil, nil
    Home.zone_at, Home.in_room, Home.zone_wait, Home.zones_found = nil, nil, nil, nil
    Home.seen_tweaks = {}
    local g = rawget(_G, "Global")
    if type(g) == "table" then g.pdti_home = nil end
end
