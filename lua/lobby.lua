-- Lobby isolation (0.46.0): online, PDTI players only meet PDTI players.
--
-- The game marks every lobby with its build key
-- (NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY): a new lobby gets it
-- as an attribute, the lobby search and the friends' list keep only lobbies
-- that have it, and an invite (join_server_with_check) refuses a lobby
-- without it. PDTI adds "_pdti" to it, so vanilla players never see a PDTI
-- lobby and PDTI players never see a vanilla one (restoration-mod keeps its
-- players apart the same way).
--
-- Who joins anyway (a modified game) is checked: every PDTI player says
-- hello over SuperBLT's networking (LuaNetworking); the host removes a
-- player who has not, 15 s after that player could; a client leaves a host
-- that has not, in the lobby (in a heist leaving would cost the weapons it
-- brought: a warning only). Any PDTI version plays with any other: a
-- different one is only said.
PDTI = PDTI or {}
local Lobby = PDTI.Lobby or {}
PDTI.Lobby = Lobby

Lobby.SUFFIX = "_pdti"
Lobby.MSG = "PDTI_hello"
Lobby.WAIT = 15      -- seconds a player has to say hello once they can
Lobby.RESEND = 2     -- seconds between hellos
Lobby.STEP = 1       -- seconds between looks (SuperBLT's DelayedCalls)
Lobby.CALL_ID = "pdti_lobby_tick"
Lobby.CLASSES = { "NetworkMatchMakingSTEAM", "NetworkMatchMakingEPIC", "NetworkMatchMaking" }
-- The game's calls that use the key (another mod may set its own key later:
-- PDTI's is put back first).
Lobby.KEY_CALLS = { "create_lobby", "search_lobby", "get_friends_lobbies", "join_server_with_check" }
Lobby.Now = function() return os.time() end

local log = PDTI.Logger and PDTI.Logger("PDTI LOBBY") or function(m) print("[PDTI LOBBY] " .. tostring(m)) end
Lobby._log = log

Lobby.hooks = Lobby.hooks or {}
Lobby.peers = Lobby.peers or {}     -- the host's view: by peer id
Lobby.host = Lobby.host or {}       -- a client's view of the host
Lobby.keys_told = Lobby.keys_told or {}

function Lobby.Reset()
    Lobby.peers = {}
    Lobby.host = {}
    Lobby.running = false
    Lobby.no_net_told = nil
end

------------------------------------------------------------------ the key

function Lobby.Key(base)
    if type(base) ~= "string" then return base end
    local n = #Lobby.SUFFIX
    if #base >= n and base:sub(-n) == Lobby.SUFFIX then return base end
    return base .. Lobby.SUFFIX
end

-- PDTI's key on every matchmaking class there is; how many.
function Lobby.ApplyKey()
    local n = 0
    for _, name in ipairs(Lobby.CLASSES) do
        local cls = rawget(_G, name)
        local base = type(cls) == "table" and cls._BUILD_SEARCH_INTEREST_KEY
        if type(base) == "string" then
            local key = Lobby.Key(base)
            if key ~= base then cls._BUILD_SEARCH_INTEREST_KEY = key end
            if Lobby.keys_told[name] ~= key then
                Lobby.keys_told[name] = key
                log("lobby key (" .. name .. "): " .. key .. " (PDTI players only)")
            end
            n = n + 1
        end
    end
    return n
end

------------------------------------------------------------ small helpers

local function call(obj, fn, ...)
    if type(obj) ~= "table" and type(obj) ~= "userdata" then return nil end
    local f = obj[fn]
    if type(f) ~= "function" then return nil end
    local ok, r = pcall(f, obj, ...)
    if ok then return r end
    return nil
end

local function session()
    local m = rawget(_G, "managers")
    local nm = type(m) == "table" and m.network
    if type(nm) ~= "table" or type(nm.session) ~= "function" then return nil end
    local ok, s = pcall(nm.session, nm)
    if ok then return s end
    return nil
end

local function offline()
    local g = rawget(_G, "Global")
    local gs = type(g) == "table" and g.game_settings
    return type(gs) == "table" and gs.single_player == true
end

local function is_host()
    local net = rawget(_G, "Network")
    return call(net, "is_server") == true
end

local function net()
    local n = rawget(_G, "LuaNetworking")
    if type(n) == "table" and type(n.SendToPeer) == "function" then return n end
    return nil
end

local function version() return tostring(PDTI.VERSION or "?") end

local function peer_name(peer, id)
    local n = call(peer, "name")
    if type(n) == "string" and n ~= "" then return n end
    return "Player " .. tostring(id)
end

-- Who sits in a peer slot (a new player in the same slot starts afresh).
local function ident(peer, id)
    return tostring(call(peer, "user_id") or "") .. "|" .. peer_name(peer, id)
end

-- The player can talk: verified, and in the lobby or done loading.
local function ready(peer)
    if not call(peer, "ip_verified") then return false end
    if call(peer, "loading") then return false end
    return call(peer, "in_lobby") == true or call(peer, "synched") == true
end

-- Hello: "<version>;<1 if I know you already>".
local function send(id, knows)
    local n = net()
    if not n then return false end
    local ok = pcall(n.SendToPeer, n, id, Lobby.MSG, version() .. ";" .. (knows and "1" or "0"))
    return ok
end

local function chat_local(text)
    local m = rawget(_G, "managers")
    local chat = type(m) == "table" and m.chat
    local cm = rawget(_G, "ChatManager")
    local channel = type(cm) == "table" and cm.GAME or 1
    if chat and type(chat.feed_system_message) == "function" then
        pcall(chat.feed_system_message, chat, channel, text)
    end
end

local function chat_all(text)
    local m = rawget(_G, "managers")
    local chat = type(m) == "table" and m.chat
    local cm = rawget(_G, "ChatManager")
    local channel = type(cm) == "table" and cm.GAME or 1
    if chat and type(chat.send_message) == "function" then
        pcall(chat.send_message, chat, channel, "PDTI", text)
    end
end

------------------------------------------------------------ hello received

-- A hello from a peer (SuperBLT's receive hook: data, sender).
function Lobby.OnHello(data, sender)
    local id = tonumber(sender)
    if not id then return false end
    local s = session()
    if not s then return false end
    local ver, knows = tostring(data or ""):match("^([^;]*);?(%d?)$")
    ver = (ver and ver ~= "") and ver or "?"
    local peer = call(s, "peer", id)
    local st
    if is_host() then
        st = Lobby.peers[id]
        local who = ident(peer, id)
        if not st or st.who ~= who then st = { who = who }; Lobby.peers[id] = st end
    elseif id == 1 then
        st = Lobby.host
    else
        return false -- (clients only check the host)
    end
    local first = st.known == nil
    st.known = ver
    if first then
        log(peer_name(peer, id) .. " has PDTI " .. ver)
        if ver ~= version() then
            chat_local(string.format("%s has PDTI %s (you: %s)", peer_name(peer, id), ver, version()))
        end
    end
    -- They have not heard from me: say hello back. (A known player gets no
    -- more hellos from the looks.)
    if knows ~= "1" then send(id, true) end
    return true
end

------------------------------------------------------------ removing

function Lobby.Kick(peer, id)
    local s = session()
    if not s then return false end
    local name = peer_name(peer, id)
    chat_all(name .. " was removed: this game needs the Tactical Inventory mod (PDTI)")
    -- The game's own host kick (VoteManager:message_host_kick, no dialog).
    pcall(s.send_to_peers, s, "kick_peer", id, 0)
    pcall(s.on_peer_kicked, s, peer, id, 0)
    log("removed " .. name .. ": no PDTI hello in " .. Lobby.WAIT .. " s")
    Lobby.peers[id] = nil
    return true
end

local function show_dialog(title, text)
    local m = rawget(_G, "managers")
    local sm = type(m) == "table" and m.system_menu
    if sm and type(sm.show) == "function" then
        pcall(sm.show, sm, { title = title, text = text, button_list = { { text = "OK", is_cancel_button = true } } })
    end
end

-- The host never said hello.
function Lobby.LeaveHost()
    local st = Lobby.host
    if st.left or st.warned then return false end
    local mch = rawget(_G, "MenuCallbackHandler")
    if not PDTI.InHeist() and type(mch) == "table" and type(mch._dialog_leave_lobby_yes) == "function" then
        st.left = true
        log("left the lobby: the host has no PDTI (no hello in " .. Lobby.WAIT .. " s)")
        pcall(mch._dialog_leave_lobby_yes, mch)
        show_dialog("Tactical Inventory", "You left the lobby: its host has no Tactical Inventory mod (PDTI). "
            .. "PDTI players play only with PDTI players.")
        return "left"
    end
    st.warned = true
    local text = "This host has no Tactical Inventory mod (PDTI): leave after this heist (leaving now loses the weapons you brought)"
    log("the host has no PDTI (in a heist: warned only)")
    chat_local(text)
    PDTI.Hint(text, 8)
    return "warned"
end

------------------------------------------------------------ the check

local function tick_host(s, now)
    local peers = call(s, "peers") or {}
    for id in pairs(Lobby.peers) do
        if peers[id] == nil then Lobby.peers[id] = nil end
    end
    local kicked = 0
    for id, peer in pairs(peers) do
        local who = ident(peer, id)
        local st = Lobby.peers[id]
        if not st or st.who ~= who then st = { who = who }; Lobby.peers[id] = st end
        if st.known == nil then
            if ready(peer) then
                st.ready_at = st.ready_at or now
                if not st.sent_at or now - st.sent_at >= Lobby.RESEND then
                    send(id, false)
                    st.sent_at = now
                end
                if now - st.ready_at >= Lobby.WAIT and Lobby.Kick(peer, id) then kicked = kicked + 1 end
            else
                st.ready_at = nil -- (the clock runs while they can talk)
            end
        end
    end
    return kicked
end

local function tick_client(s, now)
    local host = call(s, "peer", 1)
    local st = Lobby.host
    if not host then Lobby.host = {}; return 0 end
    local who = ident(host, 1)
    if st.who ~= who then st = { who = who }; Lobby.host = st end
    if st.known ~= nil or st.left or st.warned then return 0 end
    local me = call(s, "local_peer")
    local can = call(host, "ip_verified") and not call(me, "loading")
        and (call(me, "in_lobby") == true or call(me, "synched") == true)
    if not can then st.ready_at = nil; return 0 end
    st.ready_at = st.ready_at or now
    if not st.sent_at or now - st.sent_at >= Lobby.RESEND then
        send(1, false)
        st.sent_at = now
    end
    if now - st.ready_at >= Lobby.WAIT then
        Lobby.LeaveHost()
        return 1
    end
    return 0
end

-- One look (once a second while a session exists).
function Lobby.Tick()
    local s = session()
    if not s or offline() then
        Lobby.peers, Lobby.host = {}, {}
        return 0
    end
    if not net() then
        if not Lobby.no_net_told then
            Lobby.no_net_told = true
            log("no SuperBLT networking: players are not checked (the lobby key still keeps PDTI apart)")
        end
        return 0
    end
    local now = Lobby.Now()
    if is_host() then return tick_host(s, now) end
    return tick_client(s, now)
end

-- The look, once a second, while there is a session (DelayedCalls runs in
-- the menu and in a heist, also while you are in custody).
function Lobby.Loop()
    Lobby.running = false
    local ok, err = pcall(Lobby.Tick)
    if not ok then log("check failed: " .. tostring(err)) end
    if session() then Lobby.Start() end
end

function Lobby.Start()
    if Lobby.running then return true end
    local dc = rawget(_G, "DelayedCalls")
    if type(dc) ~= "table" or type(dc.Add) ~= "function" then return false end
    local ok = pcall(dc.Add, dc, Lobby.CALL_ID, Lobby.STEP, Lobby.Loop)
    Lobby.running = ok
    return ok
end

------------------------------------------------------------ hooks

local function key_first(orig)
    return function(self, ...)
        pcall(Lobby.ApplyKey)
        return orig(self, ...)
    end
end

local function start_after(orig)
    local function pass(...)
        pcall(Lobby.Start)
        return ...
    end
    return function(self, ...)
        return pass(orig(self, ...))
    end
end

function Lobby.InstallHooks()
    Lobby.ApplyKey()
    local n = 0
    for _, cls in ipairs(Lobby.CLASSES) do
        for _, fn in ipairs(Lobby.KEY_CALLS) do
            if PDTI.Wrap(Lobby.hooks, "pdti_lobby", cls, fn, key_first) then n = n + 1 end
        end
    end
    for _, fn in ipairs({ "on_entered_lobby", "add_peer" }) do
        if PDTI.Wrap(Lobby.hooks, "pdti_lobby", "BaseNetworkSession", fn, start_after) then n = n + 1 end
    end
    local nw = net()
    if nw and type(nw.AddReceiveHook) == "function" and not Lobby.receiving then
        Lobby.receiving = pcall(nw.AddReceiveHook, nw, Lobby.MSG, "pdti_lobby_hello",
            function(data, sender) pcall(Lobby.OnHello, data, sender) end)
    end
    return n
end
