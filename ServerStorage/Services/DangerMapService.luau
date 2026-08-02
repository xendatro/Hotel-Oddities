--- Owns the danger map: where the field is measured from, and the pool of places something is allowed
--- to appear.
---
--- Two jobs that are easy to conflate. Evaluating danger at a point is free and stateless -- that is
--- `DangerField`, and anything can ask for it at any time. What this service adds is a **baked pool
--- of candidate spawn points** laid out across the parts tagged `MazeFloor`, which is what makes
--- "pick somewhere dangerous to put a Chaser" a weighted draw rather than a search.
---
--- The pool is points along the floors rather than the corridor graph's nodes. The graph only has
--- junctions and dead ends in it, so drawing from it would mean every enemy in the game appears at a
--- corner -- sparse, and learnable in exactly the wrong way. Points every few studs down the length
--- of each corridor give mid-hallway placements too, and stay on authored walkable floor by
--- construction.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local DangerField = require(ReplicatedStorage.Modules.DangerField)

local MAZE_FLOOR_TAG = "MazeFloor"
local START_TAG = "Start"

export type SpawnPoint = DangerField.SpawnPoint

local DangerMapService = {}

local Points: { SpawnPoint } = {}
local Settings: DangerField.FieldSettings? = nil
local Extent = 0
-- Cumulative weight tables by danger bias. Every enemy draws with its own exponent and the pool never
-- moves, so the scan that builds one is worth keeping until the map is rebaked.
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

--- Rebuilds the point pool and the field settings from the map as it stands. Called once at boot and
--- again whenever the debug UI moves something the field depends on.
function DangerMapService:Rebake(overrides: { [string]: any }?)
	local floors = getFloors()
	if #floors == 0 then
		warn(`[danger] no "{MAZE_FLOOR_TAG}" parts in workspace; the danger map has nowhere to spawn anything`)
		Points = {}
		WeightCache = {}
		Extent = 1 -- never zero: everything else divides distances by this
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

--- The resolved field settings. Nil only before the first bake.
function DangerMapService:GetSettings(): DangerField.FieldSettings?
	return Settings
end

--- The longest horizontal side of the map, which every fractional distance is measured against.
function DangerMapService:GetExtent(): number
	return Extent
end

--- How dangerous a position is, 0..1. Stateless -- this does not consult the baked pool at all, so a
--- point nowhere near a tagged floor still gets an honest answer.
function DangerMapService:GetDanger(position: Vector3): number
	if not Settings then return 0 end
	return DangerField.Sample(position, Settings :: DangerField.FieldSettings)
end

--- Every baked candidate. The debug heatmap wants the whole pool; nothing else should.
function DangerMapService:GetPoints(): { SpawnPoint }
	return Points
end

local function getCumulativeWeights(bias: number): { number }
	local cached = WeightCache[bias]
	if cached then return cached end

	local cumulative = table.create(#Points)
	local total = 0
	for index, point in Points do
		-- A bias of zero makes every point equally likely, which is what an enemy with no preference
		-- for dangerous ground should get -- `0 ^ 0` would otherwise hand it a flat one regardless.
		total += if bias <= 0 then 1 else point.Danger ^ bias
		cumulative[index] = total
	end

	WeightCache[bias] = cumulative
	return cumulative
end

--- One point drawn in proportion to `danger ^ bias`. Nil while the pool is empty or every point has
--- zero weight, which is what a map whose floors all sit inside the safe radius looks like.
local function drawPoint(bias: number): SpawnPoint?
	if #Points == 0 then return nil end

	local cumulative = getCumulativeWeights(bias)
	local total = cumulative[#cumulative]
	if total <= 0 then return nil end

	local roll = math.random() * total
	-- Binary search: the pool runs to thousands of points and this is on the spawn path.
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

--- A point that suits `bias` and satisfies `accept`, or nil if `attempts` draws all failed.
---
--- Rejection sampling rather than filtering the pool, because `accept` is where the raycasts live:
--- drawing first and testing one point is a handful of casts, and testing every point to draw from
--- what survives is thousands. A run of failures is a perfectly good outcome -- it means everywhere
--- suitable was in somebody's sight, and the honest answer to that is to spawn nothing this tick.
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
