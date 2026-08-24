local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MathService = require(ReplicatedStorage.Services.MathService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)

local ENEMY_TAG = "Enemy"
local MAZE_FLOOR_TAG = "MazeFloor"

local STANDING_HEIGHT = 5
local STANDING_CLEARANCE = 0.5
local SAMPLE_HEIGHTS = { 4.5, 1 }
local FLOOR_PROBE_UP = 4
local FLOOR_PROBE_DOWN = 8
local MAX_FLOOR_DROP = 3
local AREA_PER_SAMPLE = 200
local MAX_SAMPLES_PER_PART = 12
local CANDIDATE_LIMIT = 120
local VERIFY_LIMIT = 10

local DEFAULT_RANGE = 70
local DEFAULT_MIN_DISTANCE = 12
local MIN_EYE_CLEARANCE = 16
local RETREAT_GAIN = 4
local MAX_TOWARDS_DOT = 0.15
local TRAVEL_WEIGHT = 0.6
local MIN_HEADING_DOT = -0.5
local HEADING_WEIGHT = 10

local HideSpotService = {}

local warnedAboutTag = false

local function buildFilter(): { Instance }
	local filter = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(filter, player.Character)
		end
	end
	for _, model in CollectionService:GetTagged(ENEMY_TAG) do
		table.insert(filter, model)
	end
	return filter
end

local function getFloors(origin: Vector3, range: number): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart")
			and (instance.Position - origin).Magnitude - instance.Size.Magnitude / 2 <= range
		then
			table.insert(floors, instance)
		end
	end

	for index = #floors, 2, -1 do
		local swap = math.random(index)
		floors[index], floors[swap] = floors[swap], floors[index]
	end
	return floors
end

local flatten = MathService.Horizontal

local function sampleFace(part: BasePart, origin: Vector3, range: number, agentRadius: number): { Vector3 }
	local half = part.Size / 2
	local centre = part.CFrame:PointToObjectSpace(origin)

	local minX = math.max(-half.X + agentRadius, centre.X - range)
	local maxX = math.min(half.X - agentRadius, centre.X + range)
	local minZ = math.max(-half.Z + agentRadius, centre.Z - range)
	local maxZ = math.min(half.Z - agentRadius, centre.Z + range)
	if minX > maxX or minZ > maxZ then return {} end

	local count = math.clamp(
		math.floor((maxX - minX) * (maxZ - minZ) / AREA_PER_SAMPLE),
		1,
		MAX_SAMPLES_PER_PART
	)

	local points = {}
	for _ = 1, count do
		local x = minX + math.random() * (maxX - minX)
		local z = minZ + math.random() * (maxZ - minZ)
		table.insert(points, part.CFrame * Vector3.new(x, half.Y, z))
	end
	return points
end

local function nearestEye(eyes: { Vector3 }, point: Vector3): (number, Vector3?)
	local nearest, which = math.huge, nil :: Vector3?
	for _, eye in eyes do
		local distance = (eye - point).Magnitude
		if distance < nearest then
			nearest, which = distance, eye
		end
	end
	return nearest, which
end

local function findStanding(
	params: RaycastParams,
	overlap: OverlapParams,
	position: Vector3,
	agentRadius: number
): Vector3?
	local from = position + Vector3.new(0, FLOOR_PROBE_UP, 0)
	local result = workspace:Raycast(from, Vector3.new(0, -(FLOOR_PROBE_UP + FLOOR_PROBE_DOWN), 0), params)
	if not result or math.abs(result.Position.Y - position.Y) > MAX_FLOOR_DROP then return nil end

	local size = Vector3.new(agentRadius * 2, STANDING_HEIGHT, agentRadius * 2)
	local centre = result.Position + Vector3.new(0, STANDING_HEIGHT / 2 + STANDING_CLEARANCE, 0)
	if #workspace:GetPartBoundsInBox(CFrame.new(centre), size, overlap) > 0 then return nil end
	return result.Position
end

local function isVisible(params: RaycastParams, eyes: { Vector3 }, floorPosition: Vector3): boolean
	for _, height in SAMPLE_HEIGHTS do
		local point = floorPosition + Vector3.new(0, height, 0)
		for _, eye in eyes do
			local direction = point - eye
			if direction.Magnitude < 1e-3 or workspace:Raycast(eye, direction, params) == nil then
				return true
			end
		end
	end
	return false
end

export type FindOptions = {
	Range: number?,
	MinDistance: number?,
	Heading: Vector3?,
}

function HideSpotService:Find(origin: Vector3, agentRadius: number, options: FindOptions?): Vector3?
	local range = (options and options.Range) or DEFAULT_RANGE
	local minDistance = (options and options.MinDistance) or DEFAULT_MIN_DISTANCE

	local heading = options and options.Heading and flatten(options.Heading)
	heading = if heading and heading.Magnitude > 1e-3 then heading.Unit else nil

	local floors = getFloors(origin, range)
	if #floors == 0 then
		if not warnedAboutTag and #CollectionService:GetTagged(MAZE_FLOOR_TAG) == 0 then
			warnedAboutTag = true
			warn(`[enemies] nothing is tagged {MAZE_FLOOR_TAG}, so nothing can find anywhere to hide`)
		end
		return nil
	end

	local eyes = EnemyObservationService:GetEyes()
	local currentClearance, closest = nearestEye(eyes, origin)
	local towards = closest and flatten(closest - origin)
	towards = if towards and towards.Magnitude > 1e-3 then towards.Unit else nil

	local candidates = {}
	for _, part in floors do
		for _, point in sampleFace(part, origin, range, agentRadius) do
			local offset = flatten(point - origin)
			local travel = offset.Magnitude
			if travel < minDistance or travel > range then continue end

			local clearance = nearestEye(eyes, point)
			if clearance < MIN_EYE_CLEARANCE or clearance < currentClearance + RETREAT_GAIN then continue end
			if towards and offset.Unit:Dot(towards) > MAX_TOWARDS_DOT then continue end

			local score = clearance - TRAVEL_WEIGHT * travel
			if heading then
				local alignment = offset.Unit:Dot(heading)
				if alignment < MIN_HEADING_DOT then continue end
				score += HEADING_WEIGHT * alignment
			end

			table.insert(candidates, { Point = point, Score = score })
			if #candidates >= CANDIDATE_LIMIT then break end
		end
		if #candidates >= CANDIDATE_LIMIT then break end
	end

	table.sort(candidates, function(a, b)
		return a.Score > b.Score
	end)

	local filter = buildFilter()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = filter
	overlap.RespectCanCollide = true

	for index = 1, math.min(#candidates, VERIFY_LIMIT) do
		local floorPosition = findStanding(params, overlap, candidates[index].Point, agentRadius)
		if floorPosition and not isVisible(params, eyes, floorPosition) then
			return floorPosition
		end
	end
	return nil
end

return HideSpotService
