--- Grid-backed hallway corners used by enemies that need to appear at a corridor mouth.
---
--- The hallway graph is built from the authored floor grid. This service turns its junction nodes into
--- corner candidates; standability, sight and path checks remain with `PeekSpotService`.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallwayGraph = require(ServerStorage.Services.HallwayGraphService)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

-- A branch this closely aligned with the viewer is the corridor being looked down, not a corner
-- somebody can hide around.
local MAX_ALONG_SIGHT = 0.5
-- Two branches leaving one node this close to parallel are a single corridor passing through it. A
-- node needs a pair that are not, or it is a point part way along a straight run rather than a
-- junction. The graph puts a node wherever two authored floor parts meet, so an unbroken corridor is
-- full of them, and every one used to offer up a "corner" whenever the player happened to stand
-- square to the run -- which is how a Watcher ends up leaning out of open floor with no wall in it.
local MAX_BRANCH_ALIGNMENT = 0.5
local MAX_FLOOR_GAP = 10
local CONNECTION_EPSILON = 0.5
local DEPTHS = { 0, 2 }

export type Corner = {
	Position: Vector3,
	Axis: Vector3,
	Lateral: Vector3,
	Depths: { number },
}

local HallwayGridService = {}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

--- The branch directions leaving a node, as horizontal unit vectors.
local function branchesOf(node: HallwayGraph.RouteNode): { Vector3 }
	local branches = {}
	for neighbor in node.Neighbors do
		local branch = horizontal(neighbor.Position - node.Position)
		if branch.Magnitude < 1e-3 then continue end
		table.insert(branches, branch.Unit)
	end
	return branches
end

--- Whether `branch` opens off another corridor here rather than continuing one. This is the whole of
--- what makes a node a corner: something has to run across the mouth for there to be an edge to wait
--- behind. A dead end has one branch and a mid-run node has two collinear ones, and neither has a
--- corner anywhere near it.
local function isMouth(branches: { Vector3 }, branch: Vector3): boolean
	for _, other in branches do
		if math.abs(other:Dot(branch)) <= MAX_BRANCH_ALIGNMENT then return true end
	end
	return false
end

-- Graph nodes sit at hallway centre lines. A Watcher needs the actual outside corner of the two
-- hallway rectangles, not the node centre: using only one edge leaves the rig in the middle of the
-- crossing. Find both spans and move to the diagonal edge on the player's side of the junction.
--
-- Nil where either span is missing. Both widths are what name the edge, and the node centre this
-- used to fall back to is the middle of the floor -- the one place the corner certainly is not.
local function physicalCorner(nodePosition: Vector3, branch: Vector3, viewerPosition: Vector3): Vector3?
	local crossingHalfWidth = math.huge
	local branchHalfWidth = math.huge
	local across = Vector3.new(-branch.Z, 0, branch.X)
	local floorGap = 10
	for _, hallway in Hallways.All(true) do
		if math.abs(hallway.FloorY - nodePosition.Y) > floorGap then continue end

		local offset = nodePosition - hallway.Center
		if math.abs(offset:Dot(hallway.Axis)) > hallway.HalfLength + hallway.HalfWidth + CONNECTION_EPSILON
			or math.abs(offset:Dot(hallway.Across)) > hallway.HalfWidth + CONNECTION_EPSILON
		then
			continue
		end

		if math.abs(hallway.Axis:Dot(branch)) > MAX_ALONG_SIGHT then
			branchHalfWidth = math.min(branchHalfWidth, hallway.HalfWidth)
		else
			crossingHalfWidth = math.min(crossingHalfWidth, hallway.HalfWidth)
		end
	end

	if crossingHalfWidth == math.huge or branchHalfWidth == math.huge then return nil end

	local side = if (viewerPosition - nodePosition):Dot(across) >= 0 then 1 else -1
	return nodePosition + branch * crossingHalfWidth + across * branchHalfWidth * side
end

--- Every junction between `minDistance` and `maxDistance` of `eye` that can form a corner.
function HallwayGridService:GetCorners(
	eye: Vector3,
	floorY: number,
	minDistance: number,
	maxDistance: number
): { Corner }
	local corners = {}

	for _, node in HallwayGraph:Get() do
		if math.abs(node.Position.Y - floorY) > MAX_FLOOR_GAP then continue end

		local sight = horizontal(node.Position - eye)
		local distance = sight.Magnitude
		if distance < minDistance or distance > maxDistance then continue end
		sight = sight.Unit

		local branches = branchesOf(node)
		for _, branch in branches do
			if not isMouth(branches, branch) then continue end
			if math.abs(branch:Dot(sight)) > MAX_ALONG_SIGHT then continue end

			local position = physicalCorner(node.Position, branch, eye)
			if not position then continue end

			local cornerSight = horizontal(position - eye)
			local cornerDistance = cornerSight.Magnitude
			if cornerDistance < minDistance or cornerDistance > maxDistance then continue end

			table.insert(corners, {
				Position = position,
				Axis = cornerSight.Unit,
				Lateral = -branch,
				Depths = DEPTHS,
			} :: Corner)
		end
	end

	return corners
end

return HallwayGridService
