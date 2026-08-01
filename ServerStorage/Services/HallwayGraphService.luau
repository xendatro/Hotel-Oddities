--- Builds the corridor graph the anchored hallway enemies travel along. Every part tagged
--- `MazeFloor` is one straight hallway; the nodes are its two ends plus every point another hallway
--- meets it, and an edge is a stretch of floor between two of those with nothing in between.
---
--- Nodes sit at the height of the floor part's own center, with no allowance for how tall anything
--- standing on them is. Each enemy adds its own vertical offset when it turns a node into a place to
--- be, because what that offset should be is a fact about that enemy's model rather than about the
--- map -- `Rush` rides above the floor, a rig stands on it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local HALLWAY_TAG = "MazeFloor"
local PARALLEL_EPSILON = 1e-3
local CONNECTION_EPSILON = 0.5
local NODE_MERGE_DISTANCE = 4
local VERTICAL_CONNECTION_DISTANCE = 4
local MINIMUM_EDGE = 1

export type RouteNode = {
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

local HallwayGraphService = {}

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

--- Every node in the map's corridor graph, built fresh from the tags as they stand right now.
function HallwayGraphService:Build(): { RouteNode }
	local nodes = {}
	local hallways = {}

	for _, instance in TagService:GetTaggedOfPredicate(HALLWAY_TAG, function(tagged: Instance)
		return tagged:IsA("BasePart")
	end) do
		local part = instance :: BasePart
		local direction = horizontal(part.CFrame.RightVector).Unit
		local hallway: Hallway = {
			Center = part.Position,
			Direction = direction,
			HalfLength = part.Size.X / 2,
			HalfWidth = part.Size.Z / 2,
			Nodes = {},
		}
		table.insert(hallways, hallway)

		addNode(hallway, getOrCreateNode(nodes, hallway.Center - direction * hallway.HalfLength))
		addNode(hallway, getOrCreateNode(nodes, hallway.Center + direction * hallway.HalfLength))
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

--- How many ways out `node` has. One is a dead end: walking into it means walking back out again.
function HallwayGraphService:CountExits(node: RouteNode): number
	local count = 0
	for _ in node.Neighbors do
		count += 1
	end
	return count
end

--- Whether every living player is at least `distance` studs from `position`. What both hallway
--- enemies mean by somewhere they can appear without being watched appearing.
function HallwayGraphService:IsFarFromPlayers(position: Vector3, distance: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0
			and (root.Position - position).Magnitude < distance then
			return false
		end
	end
	return true
end

return HallwayGraphService
