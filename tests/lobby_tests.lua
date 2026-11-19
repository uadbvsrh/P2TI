-- 0.46.0: lobby isolation (lobby.lua). Online, PDTI players only meet PDTI
-- players: the game's lobby key gets "_pdti", and a host removes a player
-- that never says hello (a client leaves such a host in the lobby).
--   luajit tests/lobby_tests.lua
local script = arg and arg[0] or "tests/lobby_tests.lua"
local ROOT = (script:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".") .. "/"
local ENV = dofile(ROOT .. "tests/mock_env.lua")
local TMP = (os.getenv("PDTI_TEST_DIR") or "/tmp/pdti_test_lobby") .. "/"
ENV.setup(ROOT, TMP)
ENV.install_game()

-- The game's matchmaking, as in networkmatchmakingsteam.lua: the key is a
-- lobby attribute, the search's filter, the friends' list's test and the
-- invite's check.
local VANILLA = "payday2_v1.143.240"
local LOBBIES = {
  { name = "vanilla", [VANILLA] = "true" },
  { name = "pdti", [VANILLA .. "_pdti"] = "true" }
}
local function key_valid(v) return v ~= nil and v ~= "value_missing" and v ~= "value_pending" end
local function matchmaking(key)
  local cls = { _BUILD_SEARCH_INTEREST_KEY = key }
  function cls:create_lobby()
    local attrs = { owner_name = "me" }
    if self._BUILD_SEARCH_INTEREST_KEY then attrs[self._BUILD_SEARCH_INTEREST_KEY] = "true" end
    self._lobby_attributes = attrs
    return attrs
  end
  function cls:search_lobby()
    local out = {}
    for _, l in ipairs(LOBBIES) do
      if l[self._BUILD_SEARCH_INTEREST_KEY] == "true" then out[#out + 1] = l.name end
    end
    return table.concat(out, ",")
  end
  function cls:get_friends_lobbies()
    local out = {}
    for _, l in ipairs(LOBBIES) do
      if key_valid(l[NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY]) then out[#out + 1] = l.name end
    end
    return table.concat(out, ",")
  end
  function cls:join_server_with_check(i)
    if not key_valid(LOBBIES[i][self._BUILD_SEARCH_INTEREST_KEY]) then return "failed" end
    return "joined"
  end
  return cls
end
_G.NetworkMatchMakingSTEAM = matchmaking(VANILLA)
_G.NetworkMatchMakingEPIC = matchmaking(VANILLA)
_G.NetworkMatchMaking = { _BUILD_SEARCH_INTEREST_KEY = 7 } -- (not a key: left alone)
local entered, added = 0, 0
_G.BaseNetworkSession = {
  on_entered_lobby = function() entered = entered + 1; return "entered" end,
  add_peer = function(_, name) added = added + 1; return 4, { name = name } end
}
-- SuperBLT: its networking and its delayed calls.
local net_sent, receive = {}, {}
local function install_net()
  _G.LuaNetworking = {
    SendToPeer = function(_, id, msg, data) net_sent[#net_sent + 1] = { id = id, msg = msg, data = data } end,
    AddReceiveHook = function(_, msg, hook_id, fn) receive[msg] = fn; receive.id = hook_id end
  }
end
install_net()
local dc_adds = 0
_G.DelayedCalls = { calls = {} }
function DelayedCalls:Add(id, t, fn) dc_adds = dc_adds + 1; self.calls[id] = { t = t, fn = fn } end

ENV.load_mod(ROOT)
local L = PDTI.Lobby
local V = PDTI.VERSION

local pass, fail = 0, 0
local function T(name, cond, detail)
  if cond then pass = pass + 1; print("PASS  " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. (detail and (" -> " .. tostring(detail)) or "")) end
end
local function logged(text)
  for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then return true end end
  return false
end
local function count_logs(text)
  local n = 0
  for _, l in ipairs(ENV.logs) do if tostring(l):find(text, 1, true) then n = n + 1 end end
  return n
end

------------------------------------------------------------------ the key

L.InstallHooks()
local mm = setmetatable({}, { __index = NetworkMatchMakingSTEAM })
T("the game's lobby key gets _pdti", NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY == VANILLA .. "_pdti",
  NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY)
T("  logged", logged("lobby key (NetworkMatchMakingSTEAM): " .. VANILLA .. "_pdti (PDTI players only)"))
T("  not twice", L.ApplyKey() == 2 and NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY == VANILLA .. "_pdti"
  and L.Key(VANILLA .. "_pdti") == VANILLA .. "_pdti" and count_logs("lobby key (NetworkMatchMakingSTEAM)") == 1)
local attrs = mm:create_lobby({})
T("a new lobby: marked PDTI, not vanilla (vanilla players don't see it)", attrs[VANILLA .. "_pdti"] == "true"
  and attrs[VANILLA] == nil)
T("the lobby search: PDTI lobbies only", mm:search_lobby(false) == "pdti", mm:search_lobby(false))
T("the friends' lobbies: PDTI ones only", mm:get_friends_lobbies() == "pdti", mm:get_friends_lobbies())
T("an invite to a vanilla lobby fails (the game's dialog)", mm:join_server_with_check(1) == "failed")
T("  to a PDTI lobby it goes", mm:join_server_with_check(2) == "joined")
T("Epic's matchmaking as well", NetworkMatchMakingEPIC._BUILD_SEARCH_INTEREST_KEY == VANILLA .. "_pdti")
T("  not a key: left alone", NetworkMatchMaking._BUILD_SEARCH_INTEREST_KEY == 7)
NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY = "other_mod_key" -- set by another mod after PDTI
attrs = mm:create_lobby({})
T("another mod's key set later: _pdti again before the lobby is made", attrs["other_mod_key_pdti"] == "true"
  and attrs["other_mod_key"] == nil)
NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY = VANILLA
T("  before a search", mm:search_lobby(false) == "pdti")
NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY = VANILLA
T("  before the friends' list", mm:get_friends_lobbies() == "pdti")
NetworkMatchMakingSTEAM._BUILD_SEARCH_INTEREST_KEY = VANILLA
T("  before an invite", mm:join_server_with_check(1) == "failed")
T("no Epic class: no trouble", (function()
  local epic = NetworkMatchMakingEPIC
  _G.NetworkMatchMakingEPIC = nil
  local n = L.ApplyKey()
  _G.NetworkMatchMakingEPIC = epic
  return n == 1
end)())
local hooked = NetworkMatchMakingSTEAM.create_lobby
dofile(ROOT .. "lua/hooks_net.lua")
dofile(ROOT .. "lua/hooks_net.lua")
T("hooks_net.lua: the hooks go on once", NetworkMatchMakingSTEAM.create_lobby == hooked
  and mm:create_lobby({})[VANILLA .. "_pdti"] == "true")
local mod = io.open(ROOT .. "mod.txt"):read("*a")
T("mod.txt hooks the matchmaking and the session's classes", mod:find('"lib/network/matchmaking/networkmatchmakingsteam"', 1, true)
  and mod:find('"lib/network/matchmaking/networkmatchmakingepic"', 1, true)
  and mod:find('"lib/network/base/basenetworksession"', 1, true) and mod:find('"lua/hooks_net.lua"', 1, true))
T("the hello is heard (SuperBLT's receive hook)", type(receive.PDTI_hello) == "function")

------------------------------------------------------------ the session

local is_host, now = true, 1000
_G.Network = { is_server = function() return is_host end }
L.Now = function() return now end
local function new_peer(id, o)
  o = o or {}
  local p = { _id = id, _name = o.name or ("P" .. id), _uid = o.uid or ("uid" .. id),
    verified = o.verified ~= false, lobby = o.lobby ~= false, sync = o.sync == true, load = o.load == true }
  function p:id() return self._id end
  function p:name() return self._name end
  function p:user_id() return self._uid end
  function p:ip_verified() return self.verified end
  function p:in_lobby() return self.lobby end
  function p:synched() return self.sync end
  function p:loading() return self.load end
  return p
end
local order = {}
local sess
local function new_session(peers, me)
  sess = { _peers = {}, sent = {}, kicked = {}, _me = me or new_peer(9, { name = "Me" }) }
  for _, p in ipairs(peers or {}) do sess._peers[p._id] = p end
  function sess:peers() return self._peers end
  function sess:peer(id) return self._peers[id] end
  function sess:local_peer() return self._me end
  function sess:send_to_peers(...) self.sent[#self.sent + 1] = { ... }; order[#order + 1] = "kick_peer" end
  function sess:on_peer_kicked(peer, id, msg)
    self.kicked[#self.kicked + 1] = { peer = peer, id = id, msg = msg }
    self._peers[id] = nil
  end
  return sess
end
local has_session = true
managers.network = { session = function() return has_session and sess or nil end }
local chat_all, chat_mine = {}, {}
_G.ChatManager = { GAME = 1 }
managers.chat = {
  send_message = function(_, ch, sender, text) chat_all[#chat_all + 1] = text; order[#order + 1] = "chat" end,
  feed_system_message = function(_, ch, text) chat_mine[#chat_mine + 1] = text end
}
_G.Global = _G.Global or {}
Global.game_settings = { single_player = false }
local left = 0
_G.MenuCallbackHandler = { _dialog_leave_lobby_yes = function() left = left + 1 end }
local dialogs = {}
managers.system_menu = { show = function(_, d) dialogs[#dialogs + 1] = d end }
local hints = {}
PDTI.Hint = function(text) hints[#hints + 1] = text end
local function sent_to(id, since)
  local out = {}
  for i = since or 1, #net_sent do
    if net_sent[i].id == id then out[#out + 1] = net_sent[i] end
  end
  return out
end
local function fresh(peers, me)
  L.Reset()
  net_sent, chat_all, chat_mine, order, hints, dialogs = {}, {}, {}, {}, {}, {}
  left = 0
  now = 1000
  is_host = true
  has_session = true
  PDTI.session_only = false
  return new_session(peers, me)
end
local function hello(id, data) return receive.PDTI_hello(data, id) end

------------------------------------------------------------------ the host

do
  local ann, bob = new_peer(2, { name = "Ann" }), new_peer(3, { name = "Bob" })
  fresh({ ann, bob })
  L.Tick()
  T("the host says hello to everyone who joins", #sent_to(2) == 1 and #sent_to(3) == 1
    and sent_to(3)[1].msg == "PDTI_hello" and sent_to(3)[1].data == V .. ";0", sent_to(3)[1] and sent_to(3)[1].data)
  hello(2, V .. ";0")
  T("a PDTI player answers: known, answered (\"I know you\")", L.peers[2].known == V and #sent_to(2) == 2
    and sent_to(2)[2].data == V .. ";1" and logged("Ann has PDTI " .. V))
  T("  the same version: nothing said", #chat_mine == 0)
  local n = #net_sent
  now = 1001; L.Tick()
  T("hello again: not every second", #net_sent == n)
  now = 1002; L.Tick()
  T("  every 2 s, to who has not answered only", #sent_to(3, n + 1) == 1 and #sent_to(2, n + 1) == 0)
  now = 1014; L.Tick()
  T("no answer: still there at 14 s", #sess.kicked == 0 and sess._peers[3] ~= nil)
  now = 1015
  T("  removed at 15 s", L.Tick() == 1 and #sess.kicked == 1 and sess.kicked[1].id == 3 and sess.kicked[1].peer == bob
    and sess.kicked[1].msg == 0)
  T("  the game's own kick: everyone is told, then the game's removal", sess.sent[1] and sess.sent[1][1] == "kick_peer"
    and sess.sent[1][2] == 3 and sess.sent[1][3] == 0)
  T("  the lobby is told why, first", chat_all[1] == "Bob was removed: this game needs the Tactical Inventory mod (PDTI)"
    and order[1] == "chat" and order[2] == "kick_peer", chat_all[1])
  T("  logged", logged("removed Bob: no PDTI hello in 15 s"))
  T("  the PDTI player stays", sess._peers[2] ~= nil and L.peers[3] == nil)
  now = 1100; L.Tick()
  T("  (once)", #sess.kicked == 1)
end

do -- loading, not verified, a drop-in
  local cal = new_peer(4, { name = "Cal", load = true })
  local dee = new_peer(5, { name = "Dee", verified = false })
  local eve = new_peer(6, { name = "Eve", lobby = false, sync = false })
  fresh({ cal, dee, eve })
  for t = 1000, 1030 do now = t; L.Tick() end
  T("loading, not verified or not in yet: no clock, no hello", #sess.kicked == 0 and #net_sent == 0)
  cal.load, dee.verified, eve.sync = false, true, true -- (Eve: a drop-in, loaded)
  for t = 1031, 1045 do now = t; L.Tick() end
  T("  then the 15 s run from when they can talk", #sess.kicked == 0)
  now = 1046; L.Tick()
  T("  and they are removed (a drop-in too)", #sess.kicked == 3)
end

do -- the clock starts again
  local fay = new_peer(2, { name = "Fay" })
  fresh({ fay })
  for t = 1000, 1010 do now = t; L.Tick() end
  fay.load = true
  now = 1011; L.Tick()
  fay.load = false
  for t = 1012, 1026 do now = t; L.Tick() end
  T("loading again: the 15 s start again", #sess.kicked == 0)
  now = 1027; L.Tick()
  T("  then removed", #sess.kicked == 1)
end

do -- a player leaves, another sits in the slot
  local ann = new_peer(2, { name = "Ann", uid = "a" })
  fresh({ ann })
  L.Tick()
  hello(2, V .. ";0")
  sess._peers[2] = nil
  L.Tick()
  T("a player who left is forgotten", L.peers[2] == nil)
  local gus = new_peer(2, { name = "Gus", uid = "g" })
  sess._peers[2] = gus
  now = 1001; L.Tick()
  now = 1016; L.Tick()
  T("  the next one in that slot is checked afresh", #sess.kicked == 1 and sess.kicked[1].peer == gus)
  local hal = new_peer(3, { name = "Hal", uid = "h" })
  fresh({ hal })
  L.Tick()
  hello(3, V .. ";0")
  sess._peers[3] = new_peer(3, { name = "Ida", uid = "i" }) -- (left and joined between two looks)
  now = 1001; L.Tick()
  now = 1016; L.Tick()
  T("  also when the slot changed between two looks", #sess.kicked == 1 and sess.kicked[1].peer._name == "Ida")
  local jay = new_peer(4, { name = "Jay", uid = "j" })
  fresh({ jay })
  L.Tick()
  sess._peers[4] = new_peer(4, { name = "Kai", uid = "k" })
  hello(4, V .. ";0") -- (Kai's hello comes before the next look)
  now = 1016; L.Tick()
  T("  a hello from the new one counts for the new one", #sess.kicked == 0 and L.peers[4].known == V)
end

do -- another PDTI version
  local jo = new_peer(2, { name = "Jo" })
  fresh({ jo })
  L.Tick()
  hello(2, "0.40.0;0")
  hello(2, "0.40.0;0")
  T("another PDTI version: said once, to you only", #chat_mine == 1 and chat_mine[1] == "Jo has PDTI 0.40.0 (you: "
    .. V .. ")" and #chat_all == 0, #chat_mine .. ":" .. tostring(chat_mine[1]))
  now = 1100; L.Tick()
  T("  and they stay", #sess.kicked == 0)
  local n = #net_sent
  hello(2, V .. ";1")
  T("a hello that says \"I know you\": no answer", #net_sent == n)
  T("an odd sender: nothing", L.OnHello(V .. ";0", "x") == false)
  hello(2, nil)
  T("an empty hello: an unknown version, no error", L.peers[2].known == "?")
end

------------------------------------------------------------------ a client

do
  local host = new_peer(1, { name = "Kim" })
  local me = new_peer(9, { name = "Me", lobby = true })
  fresh({ host }, me)
  is_host = false
  L.Tick()
  T("a client says hello to the host", #sent_to(1) == 1 and sent_to(1)[1].data == V .. ";0")
  hello(1, V .. ";1")
  for t = 1001, 1030 do now = t; L.Tick() end
  T("  the host answered: you stay", left == 0 and #dialogs == 0 and L.host.known == V and #sent_to(1) == 1)
  T("a hello from another player: not the client's business", L.OnHello(V .. ";0", 3) == false and #sent_to(3) == 0)
end

do
  local host = new_peer(1, { name = "Kim" })
  local me = new_peer(9, { name = "Me", lobby = true })
  fresh({ host }, me)
  is_host = false
  hello(1, V .. ";0")
  T("the host's hello first: the client answers it", #sent_to(1) == 1 and sent_to(1)[1].data == V .. ";1")
end

do -- a host with no PDTI, in the lobby
  local host = new_peer(1, { name = "Lou" })
  local me = new_peer(9, { name = "Me", lobby = true })
  fresh({ host }, me)
  is_host = false
  for t = 1000, 1014 do now = t; L.Tick() end
  T("a silent host: still there at 14 s", left == 0)
  T("  hello every 2 s", #sent_to(1) == 8, #sent_to(1))
  now = 1015; L.Tick()
  T("  at 15 s in the lobby: you leave it", left == 1)
  T("  the game's dialog says why", dialogs[1] and dialogs[1].text:find("its host has no Tactical Inventory mod", 1, true) ~= nil)
  T("  logged", logged("left the lobby: the host has no PDTI"))
  local hellos = #sent_to(1)
  now = 1020; L.Tick()
  T("  once, and no more hellos", left == 1 and #dialogs == 1 and #sent_to(1) == hellos)
  sess._peers[1] = new_peer(1, { name = "Mia" }) -- (another lobby's host)
  now = 1021; L.Tick()
  T("  another host: checked afresh", L.host.who:find("Mia", 1, true) ~= nil and L.host.left == nil)
end

do -- a host with no PDTI, in a heist (a drop-in)
  local host = new_peer(1, { name = "Max" })
  local me = new_peer(9, { name = "Me", lobby = false, sync = true })
  fresh({ host }, me)
  is_host = false
  PDTI.session_only = true
  for t = 1000, 1020 do now = t; L.Tick() end
  T("in a heist: no leaving (it would cost your weapons), a warning", left == 0 and #hints == 1
    and hints[1]:find("leave after this heist", 1, true) ~= nil and #chat_mine == 1)
  T("  logged", logged("the host has no PDTI (in a heist: warned only)"))
  T("  once, and no more hellos", #hints == 1 and L.LeaveHost() == false and #sent_to(1) == 8, #sent_to(1))
  PDTI.session_only = false
end

do -- the client is still loading
  local host = new_peer(1, { name = "Ned" })
  local me = new_peer(9, { name = "Me", lobby = true, load = true })
  fresh({ host }, me)
  is_host = false
  for t = 1000, 1030 do now = t; L.Tick() end
  T("a client still loading: no clock", left == 0 and #net_sent == 0)
  me.load = false
  for t = 1031, 1045 do now = t; L.Tick() end
  T("  then the 15 s run from when it can talk", left == 0 and #hints == 0)
  host.verified = false
  now = 1046; L.Tick()
  host.verified = true
  for t = 1047, 1061 do now = t; L.Tick() end
  T("  (the host not verified: the clock starts again)", left == 0 and #hints == 0)
  now = 1062; L.Tick()
  T("  (then it counts)", left == 1)
  T("no host in the session: nothing", (function() sess._peers[1] = nil; return L.Tick() == 0 end)())
end

------------------------------------------------------------------ no checks

do
  local bob = new_peer(3, { name = "Bob" })
  fresh({ bob })
  Global.game_settings.single_player = true
  for t = 1000, 1060 do now = t; L.Tick() end
  T("offline: nothing", #net_sent == 0 and #sess.kicked == 0)
  Global.game_settings.single_player = false
  local saved = LuaNetworking
  _G.LuaNetworking = nil
  fresh({ bob })
  for t = 1000, 1060 do now = t; L.Tick() end
  T("no SuperBLT networking: nobody is removed (the key still keeps PDTI apart)", #sess.kicked == 0)
  T("  logged once", count_logs("no SuperBLT networking") == 1)
  _G.LuaNetworking = { AddReceiveHook = function() end } -- (no way to send)
  fresh({ bob })
  for t = 1000, 1060 do now = t; L.Tick() end
  T("  networking that cannot send: the same", #sess.kicked == 0 and count_logs("no SuperBLT networking") == 2)
  _G.LuaNetworking = saved
  has_session = false
  T("no session: nothing", L.Tick() == 0 and L.OnHello(V .. ";0", 2) == false and L.Kick(bob, 3) == false)
  has_session = true
end

------------------------------------------------------------------ the timer

do
  fresh({})
  DelayedCalls.calls = {}
  dc_adds = 0
  T("a player joins: the looks start", select(1, BaseNetworkSession.add_peer({}, "Ann")) == 4
    and DelayedCalls.calls.pdti_lobby_tick ~= nil and DelayedCalls.calls.pdti_lobby_tick.t == 1 and added == 1)
  T("  the game's return passed on", select(2, BaseNetworkSession.add_peer({}, "Bo")).name == "Bo")
  T("  started once", dc_adds == 1)
  L.Reset(); DelayedCalls.calls = {}
  T("you enter a lobby: the looks start", BaseNetworkSession.on_entered_lobby({}) == "entered"
    and DelayedCalls.calls.pdti_lobby_tick ~= nil and entered == 1)
  local loop = DelayedCalls.calls.pdti_lobby_tick.fn
  DelayedCalls.calls = {}
  loop()
  T("  once a second while there is a session", DelayedCalls.calls.pdti_lobby_tick ~= nil)
  DelayedCalls.calls = {}
  has_session = false
  loop()
  T("  stopped with no session", DelayedCalls.calls.pdti_lobby_tick == nil and L.running == false)
  has_session = true
  local real = L.Tick
  L.Tick = function() error("boom") end
  DelayedCalls.calls = {}
  L.Loop()
  L.Tick = real
  T("  a failed look is logged, the looks go on", logged("check failed") and DelayedCalls.calls.pdti_lobby_tick ~= nil)
  local saved = DelayedCalls
  _G.DelayedCalls = nil
  L.Reset()
  T("  no DelayedCalls: no looks, no error", L.Start() == false)
  _G.DelayedCalls = saved
end

print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then os.exit(1) end
