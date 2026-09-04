local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)

local AXIS_EPSILON = 1e-4
local JUNCTION_INSET = 0
-- Corridor floors abut exactly rather than overlapping, so openings are found by probing just
-- outside a wall or past an end for continuing floor rather than by testing the line itself.
local CAP_PROBE = 1.5
local WALL_PROBE = 1.5

local MapLayoutService = {}

export type Entry = {
	Key: string,
	Center: Vector2,
	Axis: Vector2,
	Across: Vector2,
	HalfLength: number,
	HalfWidth: number,
	IsRoom: boolean,
	Kind: string,
	Openings: { [number]: { number } },
	CapOpenings: { [number]: { number } },
	ClosedCaps: { [number]: boolean },
	Shape: string,
	CutAlong: number,
	CutAcross: number,
}

export type Sample = {
	Point: Vector2,
	Normal: Vector2,
}

local Entries: { Entry } = {}
local ByKey: { [string]: Entry } = {}
local Origin = Vector2.zero
local Minimum = Vector2.zero
local Maximum = Vector2.zero
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

local function acrossRange(entry: Entry, along: number): (number, number)
	if entry.Shape == "Round" then
		local radius = entry.HalfLength
		local half = math.sqrt(math.max(radius * radius - along * along, 0))
		return -half, half
	end

	if entry.Shape == "Wedge" then
		local edge = -(entry.CutAcross * entry.CutAlong) * entry.HalfWidth * along / entry.HalfLength
		if entry.CutAcross > 0 then
			return -entry.HalfWidth, math.max(edge, -entry.HalfWidth)
		end
		return math.min(edge, entry.HalfWidth), entry.HalfWidth
	end

	return -entry.HalfWidth, entry.HalfWidth
end

local function containsPoint(entry: Entry, point: Vector2): boolean
	local offset = point - entry.Center
	local along = offset:Dot(entry.Axis)
	local across = offset:Dot(entry.Across)
	if math.abs(along) > entry.HalfLength or math.abs(across) > entry.HalfWidth then return false end
	if entry.Shape == "Rect" then return true end

	local lower, upper = acrossRange(entry, along)
	return across >= lower and across <= upper
end

local function shapeInterval(origin: Vector2, direction: Vector2, entry: Entry): (number?, number?)
	local minimum, maximum = rectInterval(origin, direction, entry)
	if not minimum or not maximum then return nil, nil end

	local offset = origin - entry.Center

	if entry.Shape == "Round" then
		local projection = offset:Dot(direction)
		local discriminant = projection * projection - (offset:Dot(offset) - entry.HalfLength * entry.HalfLength)
		if discriminant <= 0 then return nil, nil end

		local root = math.sqrt(discriminant)
		minimum = math.max(minimum, -projection - root)
		maximum = math.min(maximum, -projection + root)
	elseif entry.Shape == "Wedge" then
		local lean = entry.CutAcross * entry.CutAlong * entry.HalfWidth / entry.HalfLength
		local slope = entry.CutAcross * (direction:Dot(entry.Across) + lean * direction:Dot(entry.Axis))
		local constant = entry.CutAcross * (offset:Dot(entry.Across) + lean * offset:Dot(entry.Axis))

		if math.abs(slope) < AXIS_EPSILON then
			if constant > 0 then return nil, nil end
		elseif slope > 0 then
			maximum = math.min(maximum, -constant / slope)
		else
			minimum = math.max(minimum, -constant / slope)
		end
	end

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

local function isCorridor(entry: Entry): boolean
	return entry.Kind == "Hallway" or entry.Kind == "Connector"
end

local function openingsAlong(origin: Vector2, direction: Vector2, skip: Entry): { number }
	local intervals = {}
	for _, other in Entries do
		if other == skip or not isCorridor(other) then continue end
		local minimum, maximum = shapeInterval(origin, direction, other)
		if minimum and maximum then
			table.insert(intervals, { minimum, maximum })
		end
	end
	return mergeIntervals(intervals)
end

local function buildOpenings(entry: Entry)
	entry.Openings = {}
	entry.CapOpenings = {}

	if not isCorridor(entry) or entry.Shape ~= "Rect" then
		for _, side in { 1, -1 } do
			entry.Openings[side] = {}
			entry.CapOpenings[side] = {}
		end
		return
	end

	for _, side in { 1, -1 } do
		local wall = entry.Center + entry.Across * (side * (entry.HalfWidth + WALL_PROBE))
		entry.Openings[side] = openingsAlong(wall, entry.Axis, entry)

		if entry.ClosedCaps[side] then
			entry.CapOpenings[side] = {}
		else
			local cap = entry.Center + entry.Axis * (side * (entry.HalfLength + CAP_PROBE))
			entry.CapOpenings[side] = openingsAlong(cap, entry.Across, entry)
		end
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
			Kind = raw.Kind or (if raw.IsRoom then "Connector" else "Hallway"),
			Openings = {},
			CapOpenings = {},
			ClosedCaps = {
				[1] = raw.ClosedCapPositive == true,
				[-1] = raw.ClosedCapNegative == true,
			},
			Shape = raw.Shape or "Rect",
			CutAlong = raw.CutAlong or 0,
			CutAcross = raw.CutAcross or 0,
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
	Minimum = Vector2.new(minX, minZ)
	Maximum = Vector2.new(maxX, maxZ)

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

function MapLayoutService:AcrossRange(entry: Entry, along: number): (number, number)
	return acrossRange(entry, along)
end

local function edgeSamples(
	entry: Entry,
	head: Vector2,
	tail: Vector2,
	normal: Vector2,
	spacing: number
): { Sample }
	local span = tail - head
	local steps = math.max(math.ceil(span.Magnitude / spacing), 2)
	local samples = table.create(steps + 1)
	for step = 0, steps do
		samples[step + 1] = { Point = head + span * (step / steps), Normal = normal }
	end
	return samples
end

local function outlineEdges(entry: Entry, spacing: number): { { Sample } }
	if entry.Shape == "Round" then
		local radius = entry.HalfLength
		local steps = math.max(math.ceil(radius * 2 * math.pi / spacing), 16)
		local samples = table.create(steps + 1)
		for step = 0, steps do
			local angle = step / steps * math.pi * 2
			local normal = entry.Axis * math.cos(angle) + entry.Across * math.sin(angle)
			samples[step + 1] = { Point = entry.Center + normal * radius, Normal = normal }
		end
		return { samples }
	end

	if entry.Shape == "Wedge" then
		local along = entry.Axis * entry.HalfLength
		local across = entry.Across * entry.HalfWidth
		local right = entry.Center - along * entry.CutAlong - across * entry.CutAcross
		local alongTip = entry.Center + along * entry.CutAlong - across * entry.CutAcross
		local acrossTip = entry.Center - along * entry.CutAlong + across * entry.CutAcross

		local hypotenuse = acrossTip - alongTip
		local outward = Vector2.new(-hypotenuse.Y, hypotenuse.X).Unit
		if outward:Dot(right - alongTip) > 0 then outward = -outward end

		return {
			edgeSamples(entry, right, alongTip, -entry.Across * entry.CutAcross, spacing),
			edgeSamples(entry, right, acrossTip, -entry.Axis * entry.CutAlong, spacing),
			edgeSamples(entry, alongTip, acrossTip, outward, spacing),
		}
	end

	return {}
end

function MapLayoutService:OutlineRuns(entry: Entry, spacing: number): { { Sample } }
	local runs = {}
	for _, samples in outlineEdges(entry, spacing) do
		local run: { Sample }? = nil
		for _, sample in samples do
			local probe = sample.Point + sample.Normal * WALL_PROBE
			local open = false
			for _, other in Entries do
				if other ~= entry and isCorridor(other) and containsPoint(other, probe) then
					open = true
					break
				end
			end

			if open then
				run = nil
			else
				if not run then
					run = {}
					table.insert(runs, run)
				end
				table.insert(run :: { Sample }, sample)
			end
		end
	end
	return runs
end

function MapLayoutService:IsRoomKind(entry: Entry): boolean
	return entry.Kind == "Room" or entry.Kind == "ComputerRoom"
end

function MapLayoutService:GetBounds(): (Vector2, Vector2)
	return Minimum, Maximum
end

function MapLayoutService:IsWithin(worldX: number, worldZ: number, padding: number?): boolean
	if #Entries == 0 then return false end

	local slack = padding or 0
	return worldX >= Minimum.X - slack
		and worldX <= Maximum.X + slack
		and worldZ >= Minimum.Y - slack
		and worldZ <= Maximum.Y + slack
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
