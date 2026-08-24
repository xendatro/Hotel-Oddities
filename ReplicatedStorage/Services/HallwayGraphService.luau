local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local HALLWAY_TAG = "MazeFloor"
local HALLWAY_ROOM_TAG = "HallwayRoomFloor"
local TRAVERSABLE_TAGS = { HALLWAY_TAG, HALLWAY_ROOM_TAG }
local PARALLEL_EPSILON = 1e-3
local CONNECTION_EPSILON = 0.5
local NODE_MERGE_DISTANCE = 4
local VERTICAL_CONNECTION_DISTANCE = 4
local MINIMUM_EDGE = 1

export type RouteNode = {
	Position: Vector3,
	Neighbors: { [RouteNode]: boolean },
	CanBeDestination: boolean,
}

type Hallway = {
	Center: Vector3,
	Direction: Vector3,
	HalfLength: number,
	HalfWidth: number,
	Nodes: { RouteNode },
	JunctionReach: { [RouteNode]: number },
	CanBeDestination: boolean,
}

type Graph = {
	Nodes: { RouteNode },
	Hallways: { Hallway },
}

local HallwayGraph = {}
local Cached: Graph?

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function cross2d(first: Vector3, second: Vector3): number
	return first.X * second.Z - first.Z * second.X
end

local function addNode(hallway: Hallway, node: RouteNode)
	node.CanBeDestination = node.CanBeDestination and hallway.CanBeDestination
	if not table.find(hallway.Nodes, node) then
		table.insert(hallway.Nodes, node)
	end
end

local function addJunction(hallway: Hallway, node: RouteNode, reach: number)
	addNode(hallway, node)
	hallway.JunctionReach[node] = math.max(hallway.JunctionReach[node] or 0, reach)
end

local function junctionAt(hallway: Hallway, position: Vector3): RouteNode?
	for _, node in hallway.Nodes do
		local reach = hallway.JunctionReach[node]
		if reach and (node.Position - position).Magnitude <= reach then return node end
	end
	return nil
end

local function endNodePosition(hallway: Hallway, sign: number): Vector3
	local inset = math.min(hallway.HalfWidth, math.max(hallway.HalfLength - MINIMUM_EDGE, 0))
	return hallway.Center + hallway.Direction * (hallway.HalfLength - inset) * sign
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
		CanBeDestination = true,
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

	local intersection = first.Center + first.Direction * firstDistance
	local node = getOrCreateNode(nodes, intersection)
	addJunction(first, node, second.HalfWidth + CONNECTION_EPSILON)
	addJunction(second, node, first.HalfWidth + CONNECTION_EPSILON)
end

local function addParallelIntersection(first: Hallway, second: Hallway, nodes: { RouteNode })
	if math.abs(first.Center.Y - second.Center.Y) > VERTICAL_CONNECTION_DISTANCE then return end
	if math.abs(cross2d(first.Direction, second.Direction)) > PARALLEL_EPSILON then return end

	local perpendicular = Vector3.new(-first.Direction.Z, 0, first.Direction.X)
	local maximumOffset = if first.CanBeDestination and second.CanBeDestination
		then CONNECTION_EPSILON
		else first.HalfWidth + second.HalfWidth + CONNECTION_EPSILON
	if math.abs((second.Center - first.Center):Dot(perpendicular)) > maximumOffset then return end

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

local function build(): Graph
	local nodes = {}
	local hallways: { Hallway } = {}
	local added: { [BasePart]: boolean } = {}

	for _, tag in TRAVERSABLE_TAGS do
		for _, instance in CollectionService:GetTagged(tag) do
			if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then continue end

			local part = instance :: BasePart
			if added[part] then continue end
			added[part] = true

			local runsAlongX = part.Size.X >= part.Size.Z
			local direction = horizontal(if runsAlongX then part.CFrame.RightVector else part.CFrame.LookVector).Unit
			local hallway: Hallway = {
				Center = part.Position,
				Direction = direction,
				HalfLength = (if runsAlongX then part.Size.X else part.Size.Z) / 2,
				HalfWidth = (if runsAlongX then part.Size.Z else part.Size.X) / 2,
				Nodes = {},
				JunctionReach = {},
				CanBeDestination = not CollectionService:HasTag(part, HALLWAY_ROOM_TAG),
			}
			table.insert(hallways, hallway)
		end
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
		for _, sign in { -1, 1 } do
			local tip = hallway.Center + hallway.Direction * hallway.HalfLength * sign
			if not junctionAt(hallway, tip) then
				addNode(hallway, getOrCreateNode(nodes, endNodePosition(hallway, sign)))
			end
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

	return {
		Nodes = nodes,
		Hallways = hallways,
	}
end

function HallwayGraph:Build(): { RouteNode }
	return build().Nodes
end

function HallwayGraph:Get(): { RouteNode }
	if not Cached then
		Cached = build()
	end
	return Cached.Nodes
end

function HallwayGraph:Invalidate()
	Cached = nil
end

function HallwayGraph:FindNearestNode(position: Vector3): RouteNode?
	local nearest, nearestDistance = nil, math.huge
	for _, node in self:Get() do
		local distance = (node.Position - position).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = node, distance
		end
	end
	return nearest
end

function HallwayGraph:CountExits(node: RouteNode): number
	local count = 0
	for _ in node.Neighbors do
		count += 1
	end
	return count
end

local function popNearest(frontier: { RouteNode }, distances: { [RouteNode]: number }): RouteNode
	local currentIndex, current = 1, frontier[1]
	for index = 2, #frontier do
		if distances[frontier[index]] < distances[current] then
			currentIndex, current = index, frontier[index]
		end
	end
	table.remove(frontier, currentIndex)
	return current
end

function HallwayGraph:FindPath(
	from: RouteNode,
	to: RouteNode,
	edgeCost: ((RouteNode, RouteNode) -> number)?
): { RouteNode }?
	if from == to then return { from } end

	local distances: { [RouteNode]: number } = { [from] = 0 }
	local previous: { [RouteNode]: RouteNode } = {}
	local settled: { [RouteNode]: boolean } = {}
	local frontier: { RouteNode } = { from }

	while #frontier > 0 do
		local current = popNearest(frontier, distances)
		if settled[current] then continue end
		settled[current] = true

		if current == to then
			local route = { to }
			local node = to
			while previous[node] do
				node = previous[node]
				table.insert(route, 1, node)
			end
			return route
		end

		local currentDistance = distances[current]
		for neighbor in current.Neighbors do
			if settled[neighbor] then continue end
			local step = if edgeCost
				then edgeCost(current, neighbor)
				else horizontal(current.Position - neighbor.Position).Magnitude
			local distance = currentDistance + step
			if distance < (distances[neighbor] or math.huge) then
				distances[neighbor] = distance
				previous[neighbor] = current
				table.insert(frontier, neighbor)
			end
		end
	end

	return nil
end

type RoutePoint = {
	Hallway: Hallway,
	Along: number,
	Position: Vector3,
	Distance: number,
}

local function getClosestRoutePoint(graph: Graph, position: Vector3): RoutePoint?
	local closest = nil :: RoutePoint?
	local closestDistance = math.huge
	local flatPosition = Vector3.new(position.X, 0, position.Z)

	for _, hallway in graph.Hallways do
		local flatCenter = Vector3.new(hallway.Center.X, 0, hallway.Center.Z)
		local offset = flatPosition - flatCenter
		local along = math.clamp(offset:Dot(hallway.Direction), -hallway.HalfLength, hallway.HalfLength)
		local across = math.clamp(offset:Dot(Vector3.new(-hallway.Direction.Z, 0, hallway.Direction.X)), -hallway.HalfWidth, hallway.HalfWidth)
		local point = flatCenter + hallway.Direction * along
			+ Vector3.new(-hallway.Direction.Z, 0, hallway.Direction.X) * across
		local distance = (flatPosition - point).Magnitude

		if distance < closestDistance then
			closestDistance = distance
			closest = {
				Hallway = hallway,
				Along = along,
				Position = point,
				Distance = distance,
			}
		end
	end

	return closest
end

local function getAdjacentNodes(routePoint: RoutePoint): { [RouteNode]: number }
	local candidates = {}
	local previous: RouteNode?
	local previousAlong = -math.huge

	for _, node in routePoint.Hallway.Nodes do
		local along = (node.Position - routePoint.Hallway.Center):Dot(routePoint.Hallway.Direction)
		if along <= routePoint.Along and along > previousAlong then
			previous = node
			previousAlong = along
		end
		if along >= routePoint.Along then
			candidates[node] = math.abs(along - routePoint.Along)
			break
		end
	end

	if previous then
		candidates[previous] = math.abs(previousAlong - routePoint.Along)
	end
	return candidates
end

local function getShortestNodeDistance(startCandidates: { [RouteNode]: number }, targetCandidates: { [RouteNode]: number }): number
	local distances = {}
	local frontier = {}
	for node, distance in startCandidates do
		distances[node] = distance
		table.insert(frontier, node)
	end

	local best = math.huge
	while #frontier > 0 do
		local current = popNearest(frontier, distances)

		local currentDistance = distances[current]
		local targetDistance = targetCandidates[current]
		if targetDistance then
			best = math.min(best, currentDistance + targetDistance)
		end
		if currentDistance >= best then continue end

		for neighbor in current.Neighbors do
			local distance = currentDistance + horizontal(current.Position - neighbor.Position).Magnitude
			if distance < (distances[neighbor] or math.huge) then
				distances[neighbor] = distance
				table.insert(frontier, neighbor)
			end
		end
	end

	return best
end

function HallwayGraph:GetWalkingDistance(firstPosition: Vector3, secondPosition: Vector3): number
	if not Cached then
		Cached = build()
	end

	local first = getClosestRoutePoint(Cached, firstPosition)
	local second = getClosestRoutePoint(Cached, secondPosition)
	if not first or not second then
		return horizontal(firstPosition - secondPosition).Magnitude
	end

	local direct = math.huge
	if first.Hallway == second.Hallway then
		direct = first.Distance + math.abs(first.Along - second.Along) + second.Distance
	end

	local route = getShortestNodeDistance(getAdjacentNodes(first), getAdjacentNodes(second))
	return math.min(direct, first.Distance + route + second.Distance)
end

function HallwayGraph:IsFarFromPlayers(position: Vector3, distance: number): boolean
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root and (root.Position - position).Magnitude < distance then
			return false
		end
	end
	return true
end

for _, tag in TRAVERSABLE_TAGS do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function()
		HallwayGraph:Invalidate()
	end)

	CollectionService:GetInstanceRemovedSignal(tag):Connect(function()
		HallwayGraph:Invalidate()
	end)
end

return HallwayGraph
