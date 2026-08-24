local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)

local AXIS_EPSILON = 1e-4
local JUNCTION_INSET = -0.75

local MapLayoutService = {}

export type Entry = {
	Key: string,
	Center: Vector2,
	Axis: Vector2,
	Across: Vector2,
	HalfLength: number,
	HalfWidth: number,
	IsRoom: boolean,
	Openings: { [number]: { number } },
	CapOpenings: { [number]: { number } },
}

local Entries: { Entry } = {}
local ByKey: { [string]: Entry } = {}
local Origin = Vector2.zero
local Scale = 1

local function slab(offset: number, slope: number, halfSize: number): (number?, number?)
	if math.abs(slope) < AXIS_EPSILON then
		if math.abs(offset) > halfSize then return nil, nil end
		return -math.huge, math.huge
	end

	local first = (-halfSize - offset) / slope
	local second = (halfSize - offset) / slope
	return math.min(first, second), math.max(first, second)
end

local function rectInterval(origin: Vector2, direction: Vector2, entry: Entry): (number?, number?)
	local offset = origin - entry.Center
	local alongMin, alongMax = slab(offset:Dot(entry.Axis), direction:Dot(entry.Axis), entry.HalfLength - JUNCTION_INSET)
	if not alongMin then return nil, nil end

	local acrossMin, acrossMax = slab(offset:Dot(entry.Across), direction:Dot(entry.Across), entry.HalfWidth - JUNCTION_INSET)
	if not acrossMin then return nil, nil end

	local minimum = math.max(alongMin :: number, acrossMin :: number)
	local maximum = math.min(alongMax :: number, acrossMax :: number)
	if minimum >= maximum then return nil, nil end

	return minimum, maximum
end

local function mergeIntervals(intervals: { { number } }): { number }
	table.sort(intervals, function(first, second)
		return first[1] < second[1]
	end)

	local packed = {}
	for _, interval in intervals do
		local count = #packed
		if count > 0 and interval[1] <= packed[count] then
			packed[count] = math.max(packed[count], interval[2])
		else
			table.insert(packed, interval[1])
			table.insert(packed, interval[2])
		end
	end
	return packed
end

local function openingsAlong(origin: Vector2, direction: Vector2, skip: Entry): { number }
	local intervals = {}
	for _, other in Entries do
		if other == skip then continue end
		local minimum, maximum = rectInterval(origin, direction, other)
		if minimum and maximum then
			table.insert(intervals, { minimum, maximum })
		end
	end
	return mergeIntervals(intervals)
end

local function buildOpenings(entry: Entry)
	entry.Openings = {}
	entry.CapOpenings = {}

	for _, side in { 1, -1 } do
		local wall = entry.Center + entry.Across * (side * entry.HalfWidth)
		entry.Openings[side] = openingsAlong(wall, entry.Axis, entry)

		local cap = entry.Center + entry.Axis * (side * entry.HalfLength)
		entry.CapOpenings[side] = openingsAlong(cap, entry.Across, entry)
	end
end

function MapLayoutService:Load(layout: { any })
	Entries = {}
	ByKey = {}

	local minX, maxX = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge

	for _, raw in layout do
		local axis = Vector2.new(raw.AxisX, raw.AxisZ)
		local entry: Entry = {
			Key = raw.Key,
			Center = Vector2.new(raw.X, raw.Z),
			Axis = axis,
			Across = Vector2.new(-axis.Y, axis.X),
			HalfLength = raw.HalfLength,
			HalfWidth = raw.HalfWidth,
			IsRoom = raw.IsRoom,
			Openings = {},
			CapOpenings = {},
		}

		table.insert(Entries, entry)
		ByKey[entry.Key] = entry

		local extentX = math.abs(axis.X) * entry.HalfLength + math.abs(entry.Across.X) * entry.HalfWidth
		local extentZ = math.abs(axis.Y) * entry.HalfLength + math.abs(entry.Across.Y) * entry.HalfWidth
		minX = math.min(minX, entry.Center.X - extentX)
		maxX = math.max(maxX, entry.Center.X + extentX)
		minZ = math.min(minZ, entry.Center.Y - extentZ)
		maxZ = math.max(maxZ, entry.Center.Y + extentZ)
	end

	if #Entries == 0 then return end

	local resolution = MapConfig.Canvas.Resolution
	local usable = resolution * (1 - MapConfig.Canvas.Margin * 2)
	Scale = usable / math.max(maxX - minX, maxZ - minZ)
	Origin = Vector2.new((minX + maxX) / 2, (minZ + maxZ) / 2)

	for _, entry in Entries do
		buildOpenings(entry)
	end
end

function MapLayoutService:IsLoaded(): boolean
	return #Entries > 0
end

function MapLayoutService:GetEntries(): { Entry }
	return Entries
end

function MapLayoutService:Get(key: string): Entry?
	return ByKey[key]
end

function MapLayoutService:GetScale(): number
	return Scale
end

function MapLayoutService:ToCanvas(worldX: number, worldZ: number): Vector2
	local half = MapConfig.Canvas.Resolution / 2
	return Vector2.new((worldX - Origin.X) * Scale + half, (worldZ - Origin.Y) * Scale + half)
end

function MapLayoutService:ToCanvasScale(): number
	return MapConfig.Canvas.Resolution
end

function MapLayoutService:WallPoint(entry: Entry, side: number, along: number): Vector2
	local world = entry.Center + entry.Axis * along + entry.Across * (side * entry.HalfWidth)
	return self:ToCanvas(world.X, world.Y)
end

function MapLayoutService:Subtract(minimum: number, maximum: number, openings: { number }): { { number } }
	local remaining = { { minimum, maximum } }

	for index = 1, #openings - 1, 2 do
		local low, high = openings[index], openings[index + 1]
		local next = {}

		for _, piece in remaining do
			if high <= piece[1] or low >= piece[2] then
				table.insert(next, piece)
				continue
			end
			if low > piece[1] then table.insert(next, { piece[1], low }) end
			if high < piece[2] then table.insert(next, { high, piece[2] }) end
		end

		remaining = next
	end

	return remaining
end

return MapLayoutService
