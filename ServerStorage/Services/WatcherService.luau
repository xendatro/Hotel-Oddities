--- Puts Watchers in the world.
---
--- A Watcher only means anything on the blind side of a corner behind somebody, and which corner
--- that is has to be settled before there is a model to put anywhere -- so spawning one is a search
--- first and a spawn second. That ordering is the reason this exists rather than callers reaching
--- for `EnemyService` directly: spawned bare, a Watcher lands wherever it was told, in front of
--- somebody as often as not, and has to relocate itself once it works out where it should have been.
---
--- The search can come back empty, and that is a normal answer rather than a failure -- some rooms
--- have nothing to hide behind at the distance a Watcher wants. `SpawnNear` returns nil, and the
--- caller should try again later or somewhere else instead of settling for a worse spot.

local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)
local Watcher = require(ServerStorage.Classes.Enemies.Watcher)

-- How close a hand-spawn will settle for when the tuned distance turns nothing up. Only reachable
-- through `anyDirection`, so ambient spawning never sees it.
local HAND_SPAWN_MIN_DISTANCE = 12

local WatcherService = {}

--- A corner near `player` for a Watcher to work, or nil while the geometry around them offers none.
function WatcherService:FindSpot(player: Player): PeekSpotService.PeekSpot?
	return PeekSpotService:Find(player, Watcher.GetFindOptions(EnemyConfigs.Watcher))
end

--- Spawns a Watcher on the blind side of a corner behind `player`, already facing them and ready to
--- lean out. Returns the Watcher, or nil where there was no corner to put one on.
---
--- `anyDirection` gives up the two things the tuning asks for when the tuning cannot be satisfied:
--- first the requirement that the corner be behind them, then the distance floor. What it cannot
--- give up is the one promise this enemy is built on -- neither side of the spot may be on anybody's
--- screen -- so a hand-spawn still never puts one in front of you, it only stops insisting the
--- corner be one you have already walked past. Ambient spawning should leave it off; a hand-spawn
--- wants a Watcher now, to go and look at, and a warning is no use to somebody standing in a
--- corridor full of corners.
function WatcherService:SpawnNear(player: Player, anyDirection: boolean?)
	local spot = self:FindSpot(player)

	if not spot and anyDirection then
		local options = Watcher.GetFindOptions(EnemyConfigs.Watcher)
		options.RearArc = 360
		spot = PeekSpotService:Find(player, options)

		if not spot then
			options.MinDistance = math.min(HAND_SPAWN_MIN_DISTANCE, options.MinDistance)
			spot = PeekSpotService:Find(player, options)
		end
	end

	if not spot then return nil end

	-- Placed on the corner it will perform at, and handed the same corner, so its opening move is to
	-- lean out rather than to go looking for somewhere better.
	--
	-- The floor position goes in unadjusted: these rigs carry a `WorldPivot` at their feet, so
	-- `PivotTo` stands one on a floor point rather than burying it to the waist.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local origin = spot.Hide
	local facing = if root
		then Vector3.new(root.Position.X, origin.Y, root.Position.Z)
		else origin + Vector3.zAxis
	return EnemyService:Spawn("Watcher", CFrame.lookAt(origin, facing), spot, player)
end

return WatcherService
