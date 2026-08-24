local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local HallwayGraphService = require(ReplicatedStorage.Services.HallwayGraphService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)

type StraightSpan = Hallways.StraightSpan

local SistersService = {}
local Config = EnemyConfigs.Sisters

type SisterRoute = {
	StartTip: Vector3,
	DestinationTip: Vector3,
	Direction: Vector3,
}

local function routeBetween(startTip: Vector3, destinationTip: Vector3): SisterRoute
	local offset = destinationTip - startTip
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	return {
		StartTip = startTip,
		DestinationTip = destinationTip,
		Direction = flatOffset.Unit,
	}
end

local function routesForSpan(span: StraightSpan): (SisterRoute, SisterRoute)
	return routeBetween(span.Start, span.Finish), routeBetween(span.Finish, span.Start)
end

local function spawnPosition(route: SisterRoute): Vector3
	return route.StartTip + route.Direction * Config.EndInset
end

local function getRoutes(): { SisterRoute }
	local routes = {}
	for _, span in Hallways.StraightSpans() do
		local forward, reverse = routesForSpan(span)
		table.insert(routes, forward)
		table.insert(routes, reverse)
	end
	return routes
end

local function chooseRoute(routes: { SisterRoute }): SisterRoute?
	local cumulative = {}
	local total = 0
	for _, route in routes do
		total += 0.1 + DangerMapService:GetDanger(route.StartTip) ^ (Config.DangerBias or 1)
		table.insert(cumulative, total)
	end
	if total <= 0 then return nil end

	local roll = math.random() * total
	for index, ceiling in cumulative do
		if roll <= ceiling then return routes[index] end
	end
	return routes[#routes]
end

local function spawnRoute(route: SisterRoute): any?
	local start = spawnPosition(route)
	local walkStart = start + Vector3.yAxis * Config.RouteHeight
	local spawnCFrame = CFrame.lookAt(walkStart, walkStart + route.Direction)
	return EnemyService:Spawn(
		"Sisters",
		spawnCFrame,
		route.StartTip,
		route.Direction,
		route.DestinationTip
	)
end

function SistersService:Spawn(): any?
	local eligible = {}
	for _, route in getRoutes() do
		if HallwayGraphService:IsFarFromPlayers(spawnPosition(route), Config.SpawnPlayerDistance) then
			table.insert(eligible, route)
		end
	end

	local route = chooseRoute(eligible)
	return if route then spawnRoute(route) else nil
end

function SistersService:SpawnInHallway(player: Player): any?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local span = Hallways.StraightSpanAt(root.Position, root.CFrame.LookVector)
	if not span then return nil end

	local forward, reverse = routesForSpan(span)
	local route = if (forward.StartTip - root.Position).Magnitude >= (reverse.StartTip - root.Position).Magnitude
		then forward
		else reverse
	return spawnRoute(route)
end

return SistersService
