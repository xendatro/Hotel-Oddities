local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local Hallways = require(ReplicatedStorage.Services.HallwaysService)
local MathService = require(ReplicatedStorage.Services.MathService)

local MAX_ALONG_SIGHT = 0.5
local MAX_BRANCH_ALIGNMENT = 0.5
local MAX_FLOOR_GAP = 10
local CONNECTION_EPSILON = 0.5
local DEPTHS = { 2, 3, 4 }
local ENEMY_TAG = "Enemy"
local WALL_PROBE_HEIGHT = 2.5
local WALL_PROBE_INSET = 3
local WALL_PROBE_MARGIN = 2
local MOUTH_PROBE_OUTSET = 1

export type Corner = {
	Position: Vector3,
	Axis: Vector3,
	Lateral: Vector3,
	Depths: { number },
}

local HallwayGridService = {}

local horizontal = MathService.Horizontal

local function branchesOf(node: HallwayGraph.RouteNode): { Vector3 }
	local branches = {}
	for neighbor in node.Neighbors do
		local branch = horizontal(neighbor.Position - node.Position)
		if branch.Magnitude < 1e-3 then continue end
		table.insert(branches, branch.Unit)
	end
	return branches
end

local function isMouth(branches: { Vector3 }, branch: Vector3): boolean
	for _, other in branches do
		if math.abs(other:Dot(branch)) <= MAX_BRANCH_ALIGNMENT then return true end
	end
	return false
end

local function wallParams(): RaycastParams
	local filter = {}
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(filter, player.Character) end
	end
	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		table.insert(filter, model)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true
	return params
end

local function surfaceDistance(params: RaycastParams, origin: Vector3, direction: Vector3, reach: number): number?
	local result = workspace:Raycast(origin, direction * reach, params)
	return if result then result.Distance else nil
end

local function physicalCorner(
	nodePosition: Vector3,
	branch: Vector3,
	viewerPosition: Vector3,
	params: RaycastParams
): Vector3?
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
	local sideways = across * side
	local probe = nodePosition + Vector3.yAxis * WALL_PROBE_HEIGHT

	local wall = surfaceDistance(
		params,
		probe + branch * (crossingHalfWidth + WALL_PROBE_INSET),
		sideways,
		branchHalfWidth + WALL_PROBE_MARGIN
	) or branchHalfWidth
	local mouth = surfaceDistance(
		params,
		probe + sideways * (wall + MOUTH_PROBE_OUTSET),
		branch,
		crossingHalfWidth + WALL_PROBE_MARGIN
	) or crossingHalfWidth

	return nodePosition + branch * mouth + sideways * wall
end

function HallwayGridService:GetCorners(
	eye: Vector3,
	floorY: number,
	minDistance: number,
	maxDistance: number
): { Corner }
	local corners = {}
	local params = wallParams()

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

			local position = physicalCorner(node.Position, branch, eye, params)
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
