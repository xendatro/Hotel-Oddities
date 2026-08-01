--- Plans command-spawned Rush routes and their light warnings. Automatic enemy scheduling does not
--- belong here; when that system arrives it can call Spawn through the same public boundary.

local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)
local LightService = require(ServerStorage.Services.LightService)

local ROUTE_ATTEMPTS = 20
local DIRECTION_TIE_EPSILON = 0.05
local SEARCH_BUDGET = 4000
local CONTINUING_BONUS = 4

type RouteNode = HallwayGraphService.RouteNode

type WarningToken = {
	Cancelled: boolean,
}

local RushService = {}
local Config = EnemyConfigs.Rush
local PendingTokens: { WarningToken } = {}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Where Rush travels through a corridor node: above the floor rather than inside it. The graph puts
-- its nodes at the floor part's own center and leaves the height to whatever is standing on them.
local function routePosition(node: RouteNode): Vector3
	return node.Position + Vector3.yAxis * Config.RouteHeight
end

local function hasUnvisitedExit(node: RouteNode, visited: { [RouteNode]: boolean }): boolean
	for neighbor in node.Neighbors do
		if not visited[neighbor] then return true end
	end
	return false
end

--- Every way on from `current` Rush has not already crossed, best first: a branch that continues
--- outranks one that stops here, and among equals the straightest continuation of the leg being
--- travelled wins. Directions too close to call are ordered at random.
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

		table.insert(options, neighbor)
		ranks[neighbor] = math.round(score / DIRECTION_TIE_EPSILON) + math.random()
	end

	table.sort(options, function(first: RouteNode, second: RouteNode)
		return ranks[first] > ranks[second]
	end)
	return options
end

--- The route Rush travels from `start`, or nil if no dead end is reachable from there.
---
--- Rush is only allowed to stop where the corridor does, so the route is searched rather than walked:
--- a leg that traps the walk among nodes it has already crossed is taken back out again and the next
--- direction tried instead. The first path that reaches a node with one exit becomes the route.
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
			if HallwayGraphService:CountExits(option) == 1 or extend(current, option) then
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

local function scheduleWarnings(route: { Vector3 }, token: WarningToken): number
	local warningCount = 0
	for _, light in LightService:GetModels() do
		local distance, travel = distanceToRoute(light:GetPivot().Position, route)
		if distance > Config.LightRouteRange then continue end

		warningCount += 1
		local arrival = Config.SpawnDelay + travel / Config.WalkSpeed
		local delay = math.max(0, arrival - Config.WarningTime)
		task.delay(delay, function()
			if token.Cancelled then return end
			LightService:WarnRed(light, arrival - delay)
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

--- Plans one route, starts its light warnings now, and places Rush after the shortened spawn delay.
function RushService:Spawn(): boolean
	local starts = {}
	for _, node in HallwayGraphService:Build() do
		if next(node.Neighbors)
			and HallwayGraphService:IsFarFromPlayers(node.Position, Config.SpawnPlayerDistance) then
			table.insert(starts, node)
		end
	end
	if #starts == 0 then return false end

	local route, token
	for _ = 1, ROUTE_ATTEMPTS do
		local candidate = planRoute(starts[math.random(1, #starts)])
		if not candidate then continue end

		local candidateToken = { Cancelled = false }
		if scheduleWarnings(candidate, candidateToken) > 0 then
			route, token = candidate, candidateToken
			break
		end
	end
	if not route or not token then
		warn("[Rush] found no lit route ending at a dead end")
		return false
	end

	table.insert(PendingTokens, token)
	task.delay(Config.SpawnDelay, function()
		removePending(token)
		if token.Cancelled then return end

		local origin = route[1]
		if not HallwayGraphService:IsFarFromPlayers(origin, Config.SpawnPlayerDistance) then
			token.Cancelled = true
			warn("[Rush] cancelled because a player approached its planned spawn")
			return
		end

		local destination = route[2]
		local rush = EnemyService:Spawn("Rush", CFrame.lookAt(origin, destination), route, token)
		if not rush then
			token.Cancelled = true
		end
	end)
	return true
end

--- Cancels command-spawned Rushes that are still in their pre-spawn warning.
function RushService:CancelPending(): number
	local count = #PendingTokens
	for _, token in PendingTokens do
		token.Cancelled = true
	end
	table.clear(PendingTokens)
	return count
end

return RushService
