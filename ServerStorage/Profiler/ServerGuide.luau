--[[
SERVER PACKAGE NOTES
This file is documentation only. Do not require it.

Start Bootstrap from the server init. Copy this folder together with the
ReplicatedStorage.Profiler folder. UsageGuide and AuthoringGuide in that folder
describe the public commands, scenario lifecycle, collector contracts and tests.

Config.Access is server-only. Studio permits the test player; published places
allow the creator, configured user IDs or configured creator-group roles.
Controlled scenarios default to Studio/private servers because they can move
the player or reset a workload. Never trust a client-provided admin flag.

Runtime is generated at startup and should not be copied as authored content.
It contains an MCP command bridge and bounded session reports. No DataStores
or external endpoints are used. Export results before a server or playtest ends.

HotelOddities is an optional scenario pack. It uses the game's streaming
handshake and EnemyDirectorService.AcquirePause to suppress ambient spawns.
Its world scenarios reset existing enemies in the isolated test session and
release the director afterward. They restore character position/anchoring;
they do not promise to reconstruct the previous enemies' AI state. The enemy
scenario marks only its own Chaser harmless so targeting still runs. Player
progress and persistent inventory are never intentionally changed by a scenario.
]]
