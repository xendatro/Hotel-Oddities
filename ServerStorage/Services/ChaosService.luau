local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)
local LightService = require(ServerStorage.Services.LightService)
local MapOddityService = require(ServerStorage.Services.MapOddityService)

local ROUTE_ATTEMPTS = 20
local DIRECTION_TIE_EPSILON = 0.05
local SEARCH_BUDGET = 4000
local CONTINUING_BONUS = 4

type RouteNode = HallwayGraphService.RouteNode

type WarningToken = {
	Cancelled: boolean,
}

local ChaosService = {}
local Config = EnemyConfigs.Chaos
local PendingTokens: { WarningToken } = {}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function routePosition(node: RouteNode): Vector3
	return node.Position + Vector3.yAxis * Config.RouteHeight
end

local function hasUnvisitedExit(node: RouteNode, visited: { [RouteNode]: boolean }): boolean
	for neighbor in node.Neighbors do
		if not visited[neighbor] then return true end
	end
	return false
end

local function orderedExits(
	previous: RouteNode?,
	current: RouteNode,
	visited: { [RouteNode]: boolean }
): { RouteNode }
	local options = {}
	local ranks = {}

	for neighbor in current.Neighbors do
		if visited[neighbor] then continue end

		local score = if hasUnvisitedExit(neighbor, visited) then CONTINUING_BONUS else 0
		if previous then
			local incoming = horizontal(current.Position - previous.Position).Unit
			local outgoing = horizontal(neighbor.Position - current.Position).Unit
			score += incoming:Dot(outgoing)
		end
		score += DangerMapService:GetDanger(neighbor.Position) * DangerConfig.RouteDangerWeight

		table.insert(options, neighbor)
		ranks[neighbor] = math.round(score / DIRECTION_TIE_EPSILON) + math.random()
	end

	table.sort(options, function(first: RouteNode, second: RouteNode)
		return ranks[first] > ranks[second]
	end)
	return options
end

local function planRoute(start: RouteNode): { Vector3 }?
	local visited: { [RouteNode]: boolean } = { [start] = true }
	local path = { start }
	local steps = 0

	local function extend(previous: RouteNode?, current: RouteNode): boolean
		if steps >= SEARCH_BUDGET then return false end
		steps += 1

		for _, option in orderedExits(previous, current, visited) do
			visited[option] = true
			table.insert(path, option)
			if (option.CanBeDestination and HallwayGraphService:CountExits(option) == 1)
				or extend(current, option) then
				return true
			end

			table.remove(path)
			visited[option] = nil
		end
		return false
	end

	if not extend(nil, start) then return nil end

	local route = {}
	for _, node in path do
		table.insert(route, routePosition(node))
	end
	return route
end

local function distanceToRoute(position: Vector3, route: { Vector3 }): (number, number)
	local nearestDistance = math.huge
	local nearestTravel = 0
	local travelled = 0

	for index = 2, #route do
		local origin = route[index - 1]
		local destination = route[index]
		local offset = horizontal(destination - origin)
		local length = offset.Magnitude
		if length > 0 then
			local pointOffset = horizontal(position - origin)
			local alpha = math.clamp(pointOffset:Dot(offset) / (length * length), 0, 1)
			local closest = horizontal(origin) + offset * alpha
			local distance = (horizontal(position) - closest).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestTravel = travelled + length * alpha
			end
			travelled += length
		end
	end

	return nearestDistance, nearestTravel
end

local function livingRootPositions(): { Vector3 }
	local positions = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0 then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

local function anyPlayerNear(position: Vector3, range: number): boolean
	for _, playerPosition in livingRootPositions() do
		if (playerPosition - position).Magnitude <= range then return true end
	end
	return false
end

local function anyPlayerNearSpan(span: Hallways.StraightSpan, range: number): boolean
	for _, playerPosition in livingRootPositions() do
		local along = math.clamp((playerPosition - span.Start):Dot(span.Axis), 0, span.Length)
		if (playerPosition - (span.Start + span.Axis * along)).Magnitude <= range then
			return true
		end
	end
	return false
end

local function deferWarning(
	token: WarningToken,
	delay: number,
	expiresAt: number,
	isNearPlayer: () -> boolean,
	fire: (number) -> ()
)
	task.delay(delay, function()
		local recheck = math.max(Config.WarnCullRecheckInterval or 1, 0.1)
		while not token.Cancelled do
			local remaining = expiresAt - os.clock()
			if remaining <= 0 then return end
			if isNearPlayer() then
				fire(remaining)
				return
			end
			task.wait(math.min(recheck, remaining))
		end
	end)
end

local function scheduleWarnings(route: { Vector3 }, token: WarningToken): number
	local scheduledAt = os.clock()
	local warningCount = 0
	for _, light in LightService:GetModels() do
		local lightPosition = light:GetPivot().Position
		local distance, travel = distanceToRoute(lightPosition, route)
		if distance > Config.LightRouteRange then continue end

		warningCount += 1
		local arrival = Config.SpawnDelay + travel / Config.WalkSpeed
		local delay = math.max(0, arrival - Config.WarningTime)
		deferWarning(token, delay, scheduledAt + arrival, function()
			return anyPlayerNear(lightPosition, Config.WarnRedCullRange or math.huge)
		end, function(remaining: number)
			LightService:WarnRed(light, remaining)
		end)
	end

	local seenSpans: { [string]: boolean } = {}
	local travelled = 0
	for index, point in route do
		if index > 1 then
			travelled += horizontal(point - route[index - 1]).Magnitude
		end

		local span = Hallways.StraightSpanAt(point)
		if not span then continue end

		local key = string.format(
			"%d:%d:%d:%d",
			math.round(span.Center.X),
			math.round(span.Center.Z),
			math.round(math.abs(span.Axis.X) * 10),
			math.round(math.abs(span.Axis.Z) * 10)
		)
		if seenSpans[key] then continue end
		seenSpans[key] = true

		local arrival = Config.SpawnDelay + travelled / Config.WalkSpeed
		local delay = math.max(0, arrival - Config.WarningTime)
		deferWarning(token, delay, scheduledAt + arrival, function()
			return anyPlayerNearSpan(span, Config.WarnHallwayCullRange or math.huge)
		end, function(remaining: number)
			MapOddityService:Warn(point, remaining)
		end)
	end

	return warningCount
end

local function removePending(token: WarningToken)
	local index = table.find(PendingTokens, token)
	if index then
		table.remove(PendingTokens, index)
	end
end

local SPAN_HEIGHT_WINDOW = 24
local SPAN_WIDTH_SLACK = 2

local function farthestNodeInHallway(position: Vector3): RouteNode?
	local span = Hallways.StraightSpanAt(position)
	local hallway = Hallways.At(position)
	if not span or not hallway then return nil end

	local across = Vector3.yAxis:Cross(span.Axis).Unit
	local playerAlong = (position - span.Center):Dot(span.Axis)

	local best, bestDistance = nil, -1
	for _, node in HallwayGraphService:Get() do
		if not next(node.Neighbors) then continue end

		local offset = node.Position - span.Center
		local height = node.Position.Y - hallway.FloorY
		if height > SPAN_HEIGHT_WINDOW or height < -SPAN_HEIGHT_WINDOW then continue end
		if math.abs(offset:Dot(across)) > hallway.HalfWidth + SPAN_WIDTH_SLACK then continue end

		local along = offset:Dot(span.Axis)
		if math.abs(along) > span.Length / 2 then continue end

		local distance = math.abs(along - playerAlong)
		if distance > bestDistance then
			best, bestDistance = node, distance
		end
	end
	return best
end

local function beginRoute(route: { Vector3 }, requireClearance: boolean, onSpawned: ((any) -> ())?): boolean
	local token: WarningToken = { Cancelled = false }

	scheduleWarnings(route, token)

	table.insert(PendingTokens, token)
	task.delay(Config.SpawnDelay, function()
		removePending(token)
		if token.Cancelled then return end

		local origin = route[1]
		if requireClearance
			and not HallwayGraphService:IsFarFromPlayers(origin, Config.SpawnPlayerDistance)
		then
			token.Cancelled = true
			warn("[Chaos] cancelled because a player approached its planned spawn")
			return
		end

		local destination = route[2]
		local chaos = EnemyService:Spawn("Chaos", CFrame.lookAt(origin, destination), route, token)
		if not chaos then
			token.Cancelled = true
			return
		end
		if onSpawned then
			onSpawned(chaos)
		end
	end)
	return true
end

local function drawStart(): RouteNode?
	local starts = {}
	local cumulative = {}
	local total = 0

	for _, node in HallwayGraphService:Get() do
		if node.CanBeDestination
			and next(node.Neighbors)
			and HallwayGraphService:IsFarFromPlayers(node.Position, Config.SpawnPlayerDistance) then
			total += 0.1 + DangerMapService:GetDanger(node.Position) ^ (Config.DangerBias or 1)
			table.insert(starts, node)
			table.insert(cumulative, total)
		end
	end
	if #starts == 0 or total <= 0 then return nil end

	local roll = math.random() * total
	for index, ceiling in cumulative do
		if roll <= ceiling then
			return starts[index]
		end
	end
	return starts[#starts]
end

function ChaosService:Spawn(onSpawned: ((any) -> ())?): boolean
	local route
	for _ = 1, ROUTE_ATTEMPTS do
		local start = drawStart()
		if not start then return false end

		local candidate = planRoute(start)
		if candidate then
			route = candidate
			break
		end
	end
	if not route then
		warn("[Chaos] found no route ending at a dead end")
		return false
	end

	return beginRoute(route, true, onSpawned)
end

function ChaosService:SpawnInHallway(player: Player, onSpawned: ((any) -> ())?): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end

	local start = farthestNodeInHallway(root.Position)
	if not start then return false end

	local route = planRoute(start)
	if not route then
		warn("[Chaos] no route out of the caller's hallway ends at a dead end")
		return false
	end

	return beginRoute(route, false, onSpawned)
end

function ChaosService:CancelPending(): number
	local count = #PendingTokens
	for _, token in PendingTokens do
		token.Cancelled = true
	end
	table.clear(PendingTokens)
	return count
end

return ChaosService
