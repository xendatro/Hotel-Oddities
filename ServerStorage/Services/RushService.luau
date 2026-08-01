--- Plans command-spawned Rush routes and their light warnings. Automatic enemy scheduling does not
--- belong here; when that system arrives it can call Spawn through the same public boundary.

local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)
local LightService = require(ServerStorage.Services.LightService)

local ROUTE_ATTEMPTS = 20
local DIRECTION_TIE_EPSILON = 0.05

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

local function chooseNext(
	previous: RouteNode?,
	current: RouteNode,
	visited: { [RouteNode]: boolean }
): RouteNode?
	local options = {}
	for neighbor in current.Neighbors do
		if not visited[neighbor] then
			table.insert(options, neighbor)
		end
	end
	if #options == 0 then return nil end

	-- A branch that continues gets priority over an immediate dead end. Rush only commits to a dead
	-- end once every available direction ends there.
	local continuing = {}
	for _, option in options do
		if hasUnvisitedExit(option, visited) then
			table.insert(continuing, option)
		end
	end
	if #continuing > 0 then
		options = continuing
	end

	if not previous then
		return options[math.random(1, #options)]
	end

	local incoming = horizontal(current.Position - previous.Position).Unit
	local bestDot = -math.huge
	local straightest = {}
	for _, option in options do
		local outgoing = horizontal(option.Position - current.Position).Unit
		local dot = incoming:Dot(outgoing)
		if dot > bestDot + DIRECTION_TIE_EPSILON then
			bestDot = dot
			straightest = { option }
		elseif math.abs(dot - bestDot) <= DIRECTION_TIE_EPSILON then
			table.insert(straightest, option)
		end
	end
	return straightest[math.random(1, #straightest)]
end

local function planRoute(): { Vector3 }?
	local candidates = {}
	for _, node in HallwayGraphService:Build() do
		if next(node.Neighbors)
			and HallwayGraphService:IsFarFromPlayers(node.Position, Config.SpawnPlayerDistance) then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then return nil end

	local previous = nil :: RouteNode?
	local current = candidates[math.random(1, #candidates)]
	local visited = { [current] = true }
	local route = { routePosition(current) }

	while true do
		local nextNode = chooseNext(previous, current, visited)
		if not nextNode then break end

		previous, current = current, nextNode
		visited[current] = true
		table.insert(route, routePosition(current))
	end

	return if #route >= 2 then route else nil
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
	local route, token
	for _ = 1, ROUTE_ATTEMPTS do
		route = planRoute()
		if not route then return false end

		token = { Cancelled = false }
		if scheduleWarnings(route, token) > 0 then break end
		route, token = nil, nil
	end
	if not route or not token then return false end

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
