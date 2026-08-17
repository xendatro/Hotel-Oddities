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

-- Graph nodes sit at hallway centre lines. A Watcher needs the actual outside corner of the two
-- hallway rectangles, not the node centre: using only one edge leaves the rig in the middle of the
-- crossing. Find both spans and move to the diagonal edge on the player's side of the junction.
local function physicalCorner(nodePosition: Vector3, branch: Vector3, viewerPosition: Vector3): Vector3
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

	local position = nodePosition
	if crossingHalfWidth < math.huge then
		position += branch * crossingHalfWidth
	end
	if branchHalfWidth < math.huge then
		local side = if (viewerPosition - nodePosition):Dot(across) >= 0 then 1 else -1
		position += across * branchHalfWidth * side
	end
	return position
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

		for neighbor in node.Neighbors do
			local branch = horizontal(neighbor.Position - node.Position)
			if branch.Magnitude < 1e-3 then continue end
			branch = branch.Unit
			if math.abs(branch:Dot(sight)) > MAX_ALONG_SIGHT then continue end
			local position = physicalCorner(node.Position, branch, eye)
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
