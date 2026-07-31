--- Plans command-spawned Rush routes and their light warnings. Automatic enemy scheduling does not
--- belong here; when that system arrives it can call Spawn through the same public boundary.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local EnemyService = require(ServerStorage.Services.EnemyService)
local LightService = require(ServerStorage.Services.LightService)
local TagService = require(ReplicatedStorage.Services.TagService)

local HALLWAY_TAG = "MazeFloor"
local PARALLEL_EPSILON = 1e-3
local CONNECTION_EPSILON = 0.5
local NODE_MERGE_DISTANCE = 4
local VERTICAL_CONNECTION_DISTANCE = 4
local MINIMUM_EDGE = 1
local ROUTE_ATTEMPTS = 20
local DIRECTION_TIE_EPSILON = 0.05

type WarningToken = {
	Cancelled: boolean,
}

type RouteNode = {
	Position: Vector3,
	Neighbors: { [RouteNode]: boolean },
}

type Hallway = {
	Center: Vector3,
	Direction: Vector3,
	HalfLength: number,
	HalfWidth: number,
	Nodes: { RouteNode },
}

local RushService = {}
local Config = EnemyConfigs.Rush
local PendingTokens: { WarningToken } = {}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function cross2d(first: Vector3, second: Vector3): number
	return first.X * second.Z - first.Z * second.X
end

local function addNode(hallway: Hallway, node: RouteNode)
	if not table.find(hallway.Nodes, node) then
		table.insert(hallway.Nodes, node)
	end
end

local function getOrCreateNode(nodes: { RouteNode }, position: Vector3): RouteNode
	for _, node in nodes do
		if (node.Position - position).Magnitude <= NODE_MERGE_DISTANCE then
			return node
		end
	end

	local node = {
		Position = position,
		Neighbors = {},
	}
	table.insert(nodes, node)
	return node
end

local function connect(first: RouteNode, second: RouteNode)
	if first == second then return end
	first.Neighbors[second] = true
	second.Neighbors[first] = true
end

local function addPerpendicularIntersection(first: Hallway, second: Hallway, nodes: { RouteNode })
	if math.abs(first.Center.Y - second.Center.Y) > VERTICAL_CONNECTION_DISTANCE then return end

	local determinant = cross2d(first.Direction, second.Direction)
	if math.abs(determinant) <= PARALLEL_EPSILON then return end

	local difference = second.Center - first.Center
	local firstDistance = cross2d(difference, second.Direction) / determinant
	local secondDistance = cross2d(difference, first.Direction) / determinant
	if math.abs(firstDistance) > first.HalfLength + second.HalfWidth + CONNECTION_EPSILON
		or math.abs(secondDistance) > second.HalfLength + first.HalfWidth + CONNECTION_EPSILON then
		return
	end

	local firstPoint = first.Center
		+ first.Direction * math.clamp(firstDistance, -first.HalfLength, first.HalfLength)
	local secondPoint = second.Center
		+ second.Direction * math.clamp(secondDistance, -second.HalfLength, second.HalfLength)
	if horizontal(firstPoint - secondPoint).Magnitude
		> first.HalfWidth + second.HalfWidth + CONNECTION_EPSILON then
		return
	end

	-- Use the true centerline crossing rather than the middle of the overlapping floor corners.
	-- It may sit just beyond one floor's nominal end, but remains inside the other floor's width and
	-- keeps both approach legs perfectly straight.
	local intersection = first.Center + first.Direction * firstDistance
	local node = getOrCreateNode(nodes, intersection)
	addNode(first, node)
	addNode(second, node)
end

local function addParallelIntersection(first: Hallway, second: Hallway, nodes: { RouteNode })
	if math.abs(first.Center.Y - second.Center.Y) > VERTICAL_CONNECTION_DISTANCE then return end
	if math.abs(cross2d(first.Direction, second.Direction)) > PARALLEL_EPSILON then return end

	local perpendicular = Vector3.new(-first.Direction.Z, 0, first.Direction.X)
	if math.abs((second.Center - first.Center):Dot(perpendicular)) > CONNECTION_EPSILON then return end

	local firstEnds = {
		first.Center - first.Direction * first.HalfLength,
		first.Center + first.Direction * first.HalfLength,
	}
	local secondEnds = {
		second.Center - second.Direction * second.HalfLength,
		second.Center + second.Direction * second.HalfLength,
	}
	for _, firstPoint in firstEnds do
		for _, secondPoint in secondEnds do
			if horizontal(firstPoint - secondPoint).Magnitude
				<= first.HalfWidth + second.HalfWidth + CONNECTION_EPSILON then
				local node = getOrCreateNode(nodes, firstPoint:Lerp(secondPoint, 0.5))
				addNode(first, node)
				addNode(second, node)
				return
			end
		end
	end
end

local function buildGraph(): { RouteNode }
	local nodes = {}
	local hallways = {}

	for _, instance in TagService:GetTaggedOfPredicate(HALLWAY_TAG, function(tagged: Instance)
		return tagged:IsA("BasePart")
	end) do
		local part = instance :: BasePart
		local direction = horizontal(part.CFrame.RightVector).Unit
		local center = part.Position + Vector3.yAxis * Config.RouteHeight
		local hallway: Hallway = {
			Center = center,
			Direction = direction,
			HalfLength = part.Size.X / 2,
			HalfWidth = part.Size.Z / 2,
			Nodes = {},
		}
		table.insert(hallways, hallway)

		addNode(hallway, getOrCreateNode(nodes, center - direction * hallway.HalfLength))
		addNode(hallway, getOrCreateNode(nodes, center + direction * hallway.HalfLength))
	end

	for firstIndex = 1, #hallways - 1 do
		for secondIndex = firstIndex + 1, #hallways do
			local first = hallways[firstIndex]
			local second = hallways[secondIndex]
			addPerpendicularIntersection(first, second, nodes)
			addParallelIntersection(first, second, nodes)
		end
	end

	for _, hallway in hallways do
		table.sort(hallway.Nodes, function(first: RouteNode, second: RouteNode)
			return (first.Position - hallway.Center):Dot(hallway.Direction)
				< (second.Position - hallway.Center):Dot(hallway.Direction)
		end)
		for index = 2, #hallway.Nodes do
			local previous = hallway.Nodes[index - 1]
			local current = hallway.Nodes[index]
			if horizontal(current.Position - previous.Position).Magnitude >= MINIMUM_EDGE then
				connect(previous, current)
			end
		end
	end

	return nodes
end

local function isFarFromPlayers(position: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0
			and (root.Position - position).Magnitude < Config.SpawnPlayerDistance then
			return false
		end
	end
	return true
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
	for _, node in buildGraph() do
		if next(node.Neighbors) and isFarFromPlayers(node.Position) then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then return nil end

	local previous = nil :: RouteNode?
	local current = candidates[math.random(1, #candidates)]
	local visited = { [current] = true }
	local route = { current.Position }

	while true do
		local nextNode = chooseNext(previous, current, visited)
		if not nextNode then break end

		previous, current = current, nextNode
		visited[current] = true
		table.insert(route, current.Position)
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
		local delay = math.max(0, Config.SpawnDelay + travel / Config.WalkSpeed - Config.WarningTime)
		task.delay(delay, function()
			if token.Cancelled then return end
			LightService:Flicker(light, Config.FlickerDuration, Config.FlickerInterval)
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
		if not isFarFromPlayers(origin) then
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
