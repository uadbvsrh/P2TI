-- Hooked on lib/network/matchmaking/networkmatchmakingsteam,
-- lib/network/matchmaking/networkmatchmakingepic and
-- lib/network/base/basenetworksession (see mod.txt): once their classes are
-- loaded, PDTI's lobby key and its player check go on them (lobby.lua). When
-- the mod itself is loaded later, main.lua does this instead.
local pdti = rawget(_G, "PDTI")
local lobby = pdti and pdti.Lobby
if lobby and lobby.InstallHooks then pcall(lobby.InstallHooks) end
