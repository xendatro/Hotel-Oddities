local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local DangerField = require(ReplicatedStorage.Services.DangerFieldService)

local MAZE_FLOOR_TAG = "MazeFloor"
local START_TAG = "Start"

export type SpawnPoint = DangerField.SpawnPoint

local DangerMapService = {}

local Points: { SpawnPoint } = {}
local Settings: DangerField.FieldSettings? = nil
local Extent = 0
local WeightCache: { [number]: { number } } = {}

local function getFloors(): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(floors, instance)
		end
	end
	return floors
end

function DangerMapService:Rebake(overrides: { [string]: any }?)
	local floors = getFloors()
	if #floors == 0 then
		warn(`[danger] no "{MAZE_FLOOR_TAG}" parts in workspace; the danger map has nowhere to spawn anything`)
		Points = {}
		WeightCache = {}
		Extent = 1
		return
	end

	local extent, centre = DangerField.MeasureExtent(floors)
	Extent = extent

	local startPart = CollectionService:GetTagged(START_TAG)[1] :: BasePart?
	if not startPart then
		warn(`[danger] no part tagged "{START_TAG}"; measuring the safe zone from the middle of the map instead`)
	end
	local startPosition = if startPart then startPart.Position else centre

	Settings = DangerField.BuildSettings(startPosition, extent, overrides)

	Points = DangerField.BakePoints(floors, DangerConfig.PointSpacing, Settings :: DangerField.FieldSettings)
	WeightCache = {}
end

function DangerMapService:GetSettings(): DangerField.FieldSettings?
	return Settings
end

function DangerMapService:GetExtent(): number
	return Extent
end

function DangerMapService:GetDanger(position: Vector3): number
	if not Settings then return 0 end
	return DangerField.Sample(position, Settings :: DangerField.FieldSettings)
end

function DangerMapService:GetPoints(): { SpawnPoint }
	return Points
end

local function getCumulativeWeights(bias: number): { number }
	local cached = WeightCache[bias]
	if cached then return cached end

	local cumulative = table.create(#Points)
	local total = 0
	for index, point in Points do
		total += if bias <= 0 then 1 else point.Danger ^ bias
		cumulative[index] = total
	end

	WeightCache[bias] = cumulative
	return cumulative
end

local function drawPoint(bias: number): SpawnPoint?
	if #Points == 0 then return nil end

	local cumulative = getCumulativeWeights(bias)
	local total = cumulative[#cumulative]
	if total <= 0 then return nil end

	local roll = math.random() * total
	local low, high = 1, #cumulative
	while low < high do
		local middle = (low + high) // 2
		if cumulative[middle] < roll then
			low = middle + 1
		else
			high = middle
		end
	end
	return Points[low]
end

function DangerMapService:PickPoint(bias: number, accept: (SpawnPoint) -> boolean, attempts: number): SpawnPoint?
	for _ = 1, attempts do
		local point = drawPoint(bias)
		if not point then return nil end
		if accept(point) then return point end
	end
	return nil
end

DangerMapService:Rebake()

return DangerMapService
