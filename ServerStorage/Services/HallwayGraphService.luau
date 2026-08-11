--- Builds the corridor graph the anchored hallway enemies travel along. Every part tagged
--- `MazeFloor` is one straight hallway; the nodes are every point another hallway meets it plus its
--- own two ends, and an edge is a stretch of floor between two of those with nothing in between.
---
--- An end only counts where the hallway genuinely stops. Floors are authored butted together, so at a
--- corner or a tee each hallway's end lies across the opening of the other, a half-width past where
--- they cross. Such an end is the inside of a junction rather than a place the corridor stops, and it
--- becomes the crossing node instead of a stub of its own -- otherwise every corner offers a turn
--- into the wall that no player can see, and looks to an enemy like a dead end to stop at.
---
--- Nodes sit at the height of the floor part's own center, with no allowance for how tall anything
--- standing on them is. Each enemy adds its own vertical offset when it turns a node into a place to
--- be, because what that offset should be is a fact about that enemy's model rather than about the
--- map -- `Chaos` rides above the floor, a rig stands on it.

local CollectionService = game:GetService("CollectionService")
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
	-- How far along this hallway each of its crossings reaches, for the nodes that are crossings.
	JunctionReach: { [RouteNode]: number },
}

local HallwayGraphService = {}

-- The graph as last built. Every patrolling enemy walks this, so rebuilding it per query -- which is
-- a pass over every pair of hallways -- is not affordable any more. The tag signals below drop it,
-- which is the only thing that can change the answer while a round is running.
local Cached: { RouteNode }? = nil

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

--- Records a node that is where another hallway crosses this one, along with how much of this hallway
--- the crossing occupies: the width of the corridor passing through.
local function addJunction(hallway: Hallway, node: RouteNode, reach: number)
	addNode(hallway, node)
	hallway.JunctionReach[node] = math.max(hallway.JunctionReach[node] or 0, reach)
end

--- The crossing a hallway end falls inside, if any. The corridor carries on across the opening there,
--- so that end is not an end at all.
local function junctionAt(hallway: Hallway, position: Vector3): RouteNode?
	for _, node in hallway.Nodes do
		local reach = hallway.JunctionReach[node]
		if reach and (node.Position - position).Magnitude <= reach then return node end
	end
	return nil
end

--- Where a hallway's end node goes, for the ends that are genuinely ends. Not on the outer face of
--- the floor: that point is the last one on the walkable surface, and a pathfinding agent with a
--- radius cannot stand on it, so asking for a route there is asking for the one goal in the corridor
--- that may have no answer. It sits back by half the corridor's own width instead -- where something
--- about as wide as the hallway comes to rest against the end wall -- which is a fact about the map
--- rather than about any particular agent's dimensions.
---
--- Clamped so that a stub wider than it is long keeps a hallway of its own rather than folding both
--- ends into a single point somewhere past its middle.
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
	addJunction(first, node, second.HalfWidth + CONNECTION_EPSILON)
	addJunction(second, node, first.HalfWidth + CONNECTION_EPSILON)
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
	local hallways: { Hallway } = {}

	for _, instance in TagService:GetTaggedOfAncestor(workspace, HALLWAY_TAG) do
		if not instance:IsA("BasePart") then continue end

		local part = instance :: BasePart
		local runsAlongX = part.Size.X >= part.Size.Z
		local hallway: Hallway = {
			Center = part.Position,
			Direction = horizontal(if runsAlongX then part.CFrame.RightVector else part.CFrame.LookVector).Unit,
			HalfLength = (if runsAlongX then part.Size.X else part.Size.Z) / 2,
			HalfWidth = (if runsAlongX then part.Size.Z else part.Size.X) / 2,
			Nodes = {},
			JunctionReach = {},
		}
		table.insert(hallways, hallway)
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
			-- Tested at the true tip -- whether the corridor stops here is a question about where the
			-- floor actually ends -- but placed short of it once the answer is yes.
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

	return nodes
end

--- The corridor graph, built once and kept. Callers must treat the nodes as read-only: everything
--- that walks the map shares these tables, so a route that mutated one would rewrite the hotel for
--- everything else. Use `Build` where a private copy is genuinely wanted.
function HallwayGraphService:Get(): { RouteNode }
	if not Cached then
		Cached = self:Build()
	end
	return Cached :: { RouteNode }
end

--- Throws the cached graph away. The tag signals do this for you; call it by hand only after moving
--- floor parts around without retagging them.
function HallwayGraphService:Invalidate()
	Cached = nil
end

--- The graph node nearest `position`, or nil while the map has no tagged floors at all. What
--- something standing anywhere in the hotel uses to work out where it is on the corridor network.
function HallwayGraphService:FindNearestNode(position: Vector3): RouteNode?
	local nearest, nearestDistance = nil, math.huge
	for _, node in self:Get() do
		local distance = (node.Position - position).Magnitude
		if distance < nearestDistance then
			nearest, nearestDistance = node, distance
		end
	end
	return nearest
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

CollectionService:GetInstanceAddedSignal(HALLWAY_TAG):Connect(function()
	HallwayGraphService:Invalidate()
end)

CollectionService:GetInstanceRemovedSignal(HALLWAY_TAG):Connect(function()
	HallwayGraphService:Invalidate()
end)

return HallwayGraphService
