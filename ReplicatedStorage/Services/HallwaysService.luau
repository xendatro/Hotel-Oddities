local CollectionService = game:GetService("CollectionService")

local HALLWAY_TAG = "MazeFloor"
local HALLWAY_ROOM_TAG = "HallwayRoomFloor"
local HEIGHT_WINDOW = 24
local BELOW_WINDOW = 4
local VERTICAL_CONNECTION_DISTANCE = 4
local SPAN_CONNECTION_EPSILON = 0.75
local AXIS_EPSILON = 1e-4

export type Hallway = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	HalfLength: number,
	HalfWidth: number,
	FloorY: number,
	IsRoomFloor: boolean,
	Part: BasePart,
}

export type StraightSpan = {
	Start: Vector3,
	Finish: Vector3,
	Center: Vector3,
	Axis: Vector3,
	Length: number,
	HalfWidth: number?,
}

type Interval = {
	Min: number,
	Max: number,
}

local Hallways = {}

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getTags(includeRoomFloors: boolean?): { string }
	return if includeRoomFloors then { HALLWAY_TAG, HALLWAY_ROOM_TAG } else { HALLWAY_TAG }
end

local function toHallway(part: BasePart, isRoomFloor: boolean): Hallway
	local frame = part.CFrame
	local size = part.Size
	local directions = { frame.RightVector, frame.UpVector, frame.LookVector }
	local extents = { size.X, size.Y, size.Z }

	local thickness = 1
	for index = 2, 3 do
		if math.abs(directions[index].Y) > math.abs(directions[thickness].Y) then
			thickness = index
		end
	end

	local long, short = nil, nil
	for index = 1, 3 do
		if index == thickness then continue end
		if not long then
			long = index
		elseif extents[index] > extents[long :: number] then
			short = long
			long = index
		else
			short = index
		end
	end

	local flat = horizontal(directions[long :: number])
	local axis = if flat.Magnitude > AXIS_EPSILON then flat.Unit else Vector3.xAxis

	return {
		Center = part.Position,
		Axis = axis,
		Across = Vector3.yAxis:Cross(axis).Unit,
		HalfLength = extents[long :: number] / 2,
		HalfWidth = extents[short :: number] / 2,
		FloorY = part.Position.Y + extents[thickness] / 2,
		IsRoomFloor = isRoomFloor,
		Part = part,
	}
end

function Hallways.FromPart(part: BasePart, isRoomFloor: boolean?): Hallway
	return toHallway(part, isRoomFloor == true)
end

local Cached: { [boolean]: { Hallway } } = {}
local CachedSpans: { StraightSpan }? = nil

function Hallways.Invalidate()
	table.clear(Cached)
	CachedSpans = nil
end

function Hallways.All(includeRoomFloors: boolean?): { Hallway }
	local key = includeRoomFloors == true
	local cached = Cached[key]
	if cached then return cached end

	local hallways = {}
	for _, tag in getTags(includeRoomFloors) do
		for _, instance in CollectionService:GetTagged(tag) do
			if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
				table.insert(hallways, toHallway(instance :: BasePart, tag == HALLWAY_ROOM_TAG))
			end
		end
	end
	Cached[key] = hallways
	return hallways
end

local REBUILD_SETTLE = 0.5
local invalidatePending = false

local function scheduleInvalidate()
	if invalidatePending then return end
	invalidatePending = true
	task.delay(REBUILD_SETTLE, function()
		invalidatePending = false
		Hallways.Invalidate()
	end)
end

for _, tag in { HALLWAY_TAG, HALLWAY_ROOM_TAG } do
	CollectionService:GetInstanceAddedSignal(tag):Connect(scheduleInvalidate)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(scheduleInvalidate)
end

local function contains(hallway: Hallway, position: Vector3): boolean
	local height = position.Y - hallway.FloorY
	if height > HEIGHT_WINDOW or height < -BELOW_WINDOW then return false end

	local offset = position - hallway.Center
	return math.abs(offset:Dot(hallway.Axis)) <= hallway.HalfLength
		and math.abs(offset:Dot(hallway.Across)) <= hallway.HalfWidth
end

function Hallways.At(position: Vector3, includeRoomFloors: boolean?): Hallway?
	for _, hallway in Hallways.All(includeRoomFloors) do
		if contains(hallway, position) then return hallway end
	end
	return nil
end

function Hallways.ClosestPoint(hallway: Hallway, position: Vector3): Vector3
	local surface = Vector3.new(hallway.Center.X, hallway.FloorY, hallway.Center.Z)
	local offset = position - surface
	local along = math.clamp(offset:Dot(hallway.Axis), -hallway.HalfLength, hallway.HalfLength)
	local across = math.clamp(offset:Dot(hallway.Across), -hallway.HalfWidth, hallway.HalfWidth)
	return surface + hallway.Axis * along + hallway.Across * across
end

function Hallways.Nearest(position: Vector3): Hallway?
	local nearest = nil :: Hallway?
	local best = math.huge

	for _, hallway in Hallways.All() do
		local distance = (position - Hallways.ClosestPoint(hallway, position)).Magnitude
		if distance < best then
			nearest, best = hallway, distance
		end
	end
	return nearest
end

function Hallways.Along(hallway: Hallway, position: Vector3): number
	return (position - hallway.Center):Dot(hallway.Axis)
end

function Hallways.PointAt(hallway: Hallway, along: number): Vector3
	local center = hallway.Center + hallway.Axis * along
	return Vector3.new(center.X, hallway.FloorY, center.Z)
end

local function slabInterval(offset: number, slope: number, halfSize: number): (number?, number?)
	if math.abs(slope) < AXIS_EPSILON then
		if math.abs(offset) > halfSize then return nil, nil end
		return -math.huge, math.huge
	end

	local first = (-halfSize - offset) / slope
	local second = (halfSize - offset) / slope
	return math.min(first, second), math.max(first, second)
end

local function lineInterval(hallway: Hallway, origin: Vector3, direction: Vector3): Interval?
	local offset = origin - hallway.Center
	local alongMin, alongMax = slabInterval(
		offset:Dot(hallway.Axis),
		direction:Dot(hallway.Axis),
		hallway.HalfLength
	)
	if not alongMin or not alongMax then return nil end

	local acrossMin, acrossMax = slabInterval(
		offset:Dot(hallway.Across),
		direction:Dot(hallway.Across),
		hallway.HalfWidth
	)
	if not acrossMin or not acrossMax then return nil end

	local minimum = math.max(alongMin, acrossMin)
	local maximum = math.min(alongMax, acrossMax)
	return if minimum <= maximum then { Min = minimum, Max = maximum } else nil
end

local function chooseAxis(source: Hallway, preferredDirection: Vector3?): Vector3
	local axis = source.Axis
	local preferred = preferredDirection and horizontal(preferredDirection)
	if preferred and preferred.Magnitude > AXIS_EPSILON then
		preferred = preferred.Unit
		if source.IsRoomFloor and math.abs(source.Across:Dot(preferred)) > math.abs(axis:Dot(preferred)) then
			axis = source.Across
		end
		if axis:Dot(preferred) < 0 then axis = -axis end
	end
	return axis
end

local function straightSpan(
	source: Hallway,
	position: Vector3,
	preferredDirection: Vector3?,
	allHallways: { Hallway }
): StraightSpan?
	local axis = chooseAxis(source, preferredDirection)
	local along = horizontal(position - source.Center):Dot(axis)
	local origin = source.Center + axis * along
	local intervals = {}

	for _, hallway in allHallways do
		if math.abs(hallway.FloorY - source.FloorY) > VERTICAL_CONNECTION_DISTANCE then continue end
		local interval = lineInterval(hallway, origin, axis)
		if interval then table.insert(intervals, interval) end
	end
	if #intervals == 0 then return nil end

	table.sort(intervals, function(first: Interval, second: Interval)
		return first.Min < second.Min
	end)

	local merged = {}
	for _, interval in intervals do
		local last = merged[#merged]
		if last and interval.Min <= last.Max + SPAN_CONNECTION_EPSILON then
			last.Max = math.max(last.Max, interval.Max)
		else
			table.insert(merged, table.clone(interval))
		end
	end

	for _, interval in merged do
		if interval.Min <= 0 and interval.Max >= 0 then
			local start = origin + axis * interval.Min
			local finish = origin + axis * interval.Max
			return {
				Start = start,
				Finish = finish,
				Center = start:Lerp(finish, 0.5),
				Axis = axis,
				Length = interval.Max - interval.Min,
			}
		end
	end
	return nil
end

function Hallways.StraightSpanAt(position: Vector3, preferredDirection: Vector3?): StraightSpan?
	local allHallways = Hallways.All(true)
	local preferred = preferredDirection and horizontal(preferredDirection)
	if preferred and preferred.Magnitude > AXIS_EPSILON then
		preferred = preferred.Unit
	else
		preferred = nil
	end

	local bestSpan = nil :: StraightSpan?
	local bestAlignment = -1
	local bestDistance = math.huge
	for _, hallway in allHallways do
		if contains(hallway, position) then
			local span = straightSpan(hallway, position, preferredDirection, allHallways)
			if span then
				local alignment = if preferred then math.abs(span.Axis:Dot(preferred)) else 0
				local offset = position - span.Center
				local distance = math.abs(offset:Dot(Vector3.yAxis:Cross(span.Axis).Unit))
				if alignment > bestAlignment + AXIS_EPSILON
					or (math.abs(alignment - bestAlignment) <= AXIS_EPSILON and distance < bestDistance)
				then
					bestSpan = span
					bestAlignment = alignment
					bestDistance = distance
				end
			end
		end
	end
	return bestSpan
end

local function sameSpan(first: StraightSpan, second: StraightSpan): boolean
	local sameDirection = (first.Start - second.Start).Magnitude <= SPAN_CONNECTION_EPSILON
		and (first.Finish - second.Finish).Magnitude <= SPAN_CONNECTION_EPSILON
	local oppositeDirection = (first.Start - second.Finish).Magnitude <= SPAN_CONNECTION_EPSILON
		and (first.Finish - second.Start).Magnitude <= SPAN_CONNECTION_EPSILON
	return sameDirection or oppositeDirection
end

function Hallways.StraightSpans(): { StraightSpan }
	if CachedSpans then return CachedSpans end

	local allHallways = Hallways.All(true)
	local spans = {}
	for _, source in Hallways.All() do
		local span = straightSpan(source, source.Center, source.Axis, allHallways)
		if not span then continue end

		local match: StraightSpan? = nil
		for _, existing in spans do
			if sameSpan(span, existing) then
				match = existing
				break
			end
		end
		if match then
			match.HalfWidth = math.max(match.HalfWidth or 0, source.HalfWidth)
		else
			span.HalfWidth = source.HalfWidth
			table.insert(spans, span)
		end
	end
	CachedSpans = spans
	return spans
end

return Hallways
