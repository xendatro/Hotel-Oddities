local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Hallways = require(ReplicatedStorage.Services.HallwaysService)

local WALL_TAG = "HallwayWall"
local EPSILON = 0.05
local FLOOR_Y_EPSILON = 2
local AXIS_ALIGNMENT = 0.95
local SIDE_BAND = 4
local MAXIMUM_THICKNESS = 3
local HEIGHT_WINDOW = 24
local BELOW_WINDOW = 4
local CUT_MERGE = 0.5

local HallwayWallService = {}

export type Interval = {
	Minimum: number,
	Maximum: number,
}

export type Frame = {
	Center: Vector3,
	Axis: Vector3,
	Across: Vector3,
	CFrame: CFrame,
	HalfWidth: number,
	Minimum: number,
	Maximum: number,
	FloorY: number,
}

export type Mouth = {
	Minimum: number,
	Maximum: number,
	Sign: number,
}

export type Wall = {
	Part: BasePart,
	Sign: number,
	Minimum: number,
	Maximum: number,
	Offset: number,
	Thickness: number,
	ThicknessAxis: Vector3,
	LengthAxis: Vector3,
	LengthSign: number,
}

local function horizontal(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
end

local function projected(hallway: Hallways.Hallway, direction: Vector3): number
	return hallway.HalfLength * math.abs(hallway.Axis:Dot(direction))
		+ hallway.HalfWidth * math.abs(hallway.Across:Dot(direction))
end

local function merge(intervals: { Interval }): { Interval }
	table.sort(intervals, function(first: Interval, second: Interval)
		return first.Minimum < second.Minimum
	end)

	local merged = {}
	for _, interval in intervals do
		local last = merged[#merged]
		if last and interval.Minimum <= last.Maximum + EPSILON then
			last.Maximum = math.max(last.Maximum, interval.Maximum)
		else
			table.insert(merged, { Minimum = interval.Minimum, Maximum = interval.Maximum })
		end
	end
	return merged
end

local function coveredInterval(frame: Frame): Interval?
	local intervals = {}
	for _, hallway in Hallways.All() do
		if math.abs(hallway.FloorY - frame.FloorY) > FLOOR_Y_EPSILON then continue end

		local offset = hallway.Center - frame.Center
		if math.abs(offset:Dot(frame.Across)) > projected(hallway, frame.Across) + EPSILON then continue end

		local along = offset:Dot(frame.Axis)
		local reach = projected(hallway, frame.Axis)
		table.insert(intervals, { Minimum = along - reach, Maximum = along + reach })
	end

	for _, interval in merge(intervals) do
		if interval.Minimum <= EPSILON and interval.Maximum >= -EPSILON then return interval end
	end
	return nil
end

function HallwayWallService.Frame(span: Hallways.StraightSpan): Frame?
	local hallway = Hallways.Nearest(span.Center)
	if not hallway then return nil end

	local axis = horizontal(span.Axis)
	local center = Vector3.new(span.Center.X, hallway.FloorY, span.Center.Z)
	local frame: Frame = {
		Center = center,
		Axis = axis,
		Across = Vector3.yAxis:Cross(axis).Unit,
		CFrame = CFrame.lookAt(center, center + axis, Vector3.yAxis),
		HalfWidth = hallway.HalfWidth,
		Minimum = -span.Length / 2,
		Maximum = span.Length / 2,
		FloorY = hallway.FloorY,
	}

	local covered = coveredInterval(frame)
	if not covered then return nil end
	frame.Minimum = math.max(frame.Minimum, covered.Minimum)
	frame.Maximum = math.min(frame.Maximum, covered.Maximum)
	if frame.Maximum - frame.Minimum <= EPSILON then return nil end
	return frame
end

function HallwayWallService.Length(frame: Frame): number
	return frame.Maximum - frame.Minimum
end

HallwayWallService.HeightWindow = HEIGHT_WINDOW
HallwayWallService.BelowWindow = BELOW_WINDOW

function HallwayWallService.Merge(intervals: { Interval }, gap: number?): { Interval }
	local slack = gap or 0
	local sorted = table.clone(intervals)
	table.sort(sorted, function(first: Interval, second: Interval)
		return first.Minimum < second.Minimum
	end)

	local merged = {}
	for _, interval in sorted do
		local last = merged[#merged]
		if last and interval.Minimum <= last.Maximum + slack then
			last.Maximum = math.max(last.Maximum, interval.Maximum)
		else
			table.insert(merged, { Minimum = interval.Minimum, Maximum = interval.Maximum })
		end
	end
	return merged
end

function HallwayWallService.Intersect(first: { Interval }, second: { Interval }): { Interval }
	local overlaps = {}
	for _, left in first do
		for _, right in second do
			local minimum = math.max(left.Minimum, right.Minimum)
			local maximum = math.min(left.Maximum, right.Maximum)
			if maximum - minimum > EPSILON then
				table.insert(overlaps, { Minimum = minimum, Maximum = maximum })
			end
		end
	end
	return overlaps
end

function HallwayWallService.Inset(intervals: { Interval }, amount: number): { Interval }
	local inset = {}
	for _, interval in intervals do
		local minimum = interval.Minimum + amount
		local maximum = interval.Maximum - amount
		if maximum - minimum > EPSILON then
			table.insert(inset, { Minimum = minimum, Maximum = maximum })
		end
	end
	return inset
end

function HallwayWallService.Contains(frame: Frame, position: Vector3, margin: number?): boolean
	local slack = margin or 0
	local height = position.Y - frame.FloorY
	if height > HEIGHT_WINDOW or height < -BELOW_WINDOW then return false end

	local offset = position - frame.Center
	local along = offset:Dot(frame.Axis)
	return along >= frame.Minimum - slack
		and along <= frame.Maximum + slack
		and math.abs(offset:Dot(frame.Across)) <= frame.HalfWidth + slack
end

function HallwayWallService.Mouths(frame: Frame): { Mouth }
	local mouths = {}
	for _, hallway in Hallways.All(true) do
		if math.abs(hallway.FloorY - frame.FloorY) > FLOOR_Y_EPSILON then continue end

		local offset = hallway.Center - frame.Center
		local along = offset:Dot(frame.Axis)
		local alongReach = projected(hallway, frame.Axis)
		if along - alongReach > frame.Maximum - EPSILON or along + alongReach < frame.Minimum + EPSILON then
			continue
		end

		local across = offset:Dot(frame.Across)
		local acrossReach = projected(hallway, frame.Across)
		local acrossMinimum = across - acrossReach
		local acrossMaximum = across + acrossReach

		local minimum = math.max(along - alongReach, frame.Minimum)
		local maximum = math.min(along + alongReach, frame.Maximum)
		if acrossMaximum > frame.HalfWidth + EPSILON and acrossMinimum < frame.HalfWidth + EPSILON then
			table.insert(mouths, { Minimum = minimum, Maximum = maximum, Sign = 1 })
		end
		if acrossMinimum < -frame.HalfWidth - EPSILON and acrossMaximum > -frame.HalfWidth - EPSILON then
			table.insert(mouths, { Minimum = minimum, Maximum = maximum, Sign = -1 })
		end
	end
	return mouths
end

function HallwayWallService.Closing(frame: Frame): { Interval }
	local blocked = {}
	for _, mouth in HallwayWallService.Mouths(frame) do
		table.insert(blocked, { Minimum = mouth.Minimum, Maximum = mouth.Maximum })
	end

	local open = {}
	local cursor = frame.Minimum
	for _, interval in HallwayWallService.Merge(blocked, 0) do
		if interval.Minimum - cursor > EPSILON then
			table.insert(open, { Minimum = cursor, Maximum = interval.Minimum })
		end
		cursor = math.max(cursor, interval.Maximum)
	end
	if frame.Maximum - cursor > EPSILON then
		table.insert(open, { Minimum = cursor, Maximum = frame.Maximum })
	end
	return open
end

function HallwayWallService.CutPoints(frame: Frame): { number }
	local raw = { frame.Minimum, frame.Maximum }
	for _, mouth in HallwayWallService.Mouths(frame) do
		table.insert(raw, mouth.Minimum)
		table.insert(raw, mouth.Maximum)
	end
	table.sort(raw)

	local cuts = {}
	for _, value in raw do
		local clamped = math.clamp(value, frame.Minimum, frame.Maximum)
		local last = cuts[#cuts]
		if last == nil or clamped - last > CUT_MERGE then
			table.insert(cuts, clamped)
		end
	end
	if #cuts >= 2 then cuts[#cuts] = frame.Maximum end
	return cuts
end

function HallwayWallService.Limit(frame: Frame, position: Vector3, maximumLength: number): Frame
	local cuts = HallwayWallService.CutPoints(frame)
	if #cuts < 3 or maximumLength <= 0 then return frame end

	local along = math.clamp((position - frame.Center):Dot(frame.Axis), frame.Minimum, frame.Maximum)
	local low = 1
	for index = 1, #cuts - 1 do
		if along >= cuts[index] then low = index end
	end
	local high = low + 1

	while true do
		local canGrowLow = low > 1 and cuts[high] - cuts[low - 1] <= maximumLength
		local canGrowHigh = high < #cuts and cuts[high + 1] - cuts[low] <= maximumLength
		if canGrowLow and (not canGrowHigh or cuts[low] - cuts[low - 1] <= cuts[high + 1] - cuts[high]) then
			low -= 1
		elseif canGrowHigh then
			high += 1
		else
			break
		end
	end

	local limited = table.clone(frame)
	limited.Minimum = cuts[low]
	limited.Maximum = cuts[high]
	return limited
end

function HallwayWallService.Walls(frame: Frame): { Wall }
	local walls = {}
	for _, instance in CollectionService:GetTagged(WALL_TAG) do
		if not instance:IsA("BasePart") or not instance:IsDescendantOf(workspace) then continue end

		local part = instance :: BasePart
		local height = part.Position.Y - frame.FloorY
		if height > HEIGHT_WINDOW or height < -BELOW_WINDOW then continue end

		local right = part.CFrame.RightVector
		local look = part.CFrame.LookVector
		local lengthAxis, thicknessAxis, thicknessWorld, length, thickness, lengthSign
		if math.abs(right:Dot(frame.Axis)) >= AXIS_ALIGNMENT then
			lengthAxis, thicknessAxis = Vector3.xAxis, Vector3.zAxis
			thicknessWorld = look
			length, thickness = part.Size.X, part.Size.Z
			lengthSign = if right:Dot(frame.Axis) >= 0 then 1 else -1
		elseif math.abs(look:Dot(frame.Axis)) >= AXIS_ALIGNMENT then
			lengthAxis, thicknessAxis = Vector3.zAxis, Vector3.xAxis
			thicknessWorld = right
			length, thickness = part.Size.Z, part.Size.X
			lengthSign = if look:Dot(frame.Axis) >= 0 then 1 else -1
		else
			continue
		end
		if math.abs(thicknessWorld:Dot(frame.Across)) < AXIS_ALIGNMENT then continue end
		if thickness > MAXIMUM_THICKNESS then continue end

		local offset = part.Position - frame.Center
		local across = offset:Dot(frame.Across)
		local inner = math.abs(across) - thickness / 2
		if inner < frame.HalfWidth - SIDE_BAND or inner > frame.HalfWidth + SIDE_BAND then continue end

		local along = offset:Dot(frame.Axis)
		local minimum = along - length / 2
		local maximum = along + length / 2
		if maximum <= frame.Minimum + EPSILON or minimum >= frame.Maximum - EPSILON then continue end

		table.insert(walls, {
			Part = part,
			Sign = if across >= 0 then 1 else -1,
			Minimum = minimum,
			Maximum = maximum,
			Offset = across,
			Thickness = thickness,
			ThicknessAxis = thicknessAxis,
			LengthAxis = lengthAxis,
			LengthSign = lengthSign,
		})
	end
	return walls
end

function HallwayWallService.Fixtures(frame: Frame, tag: string, margin: number?): { Instance }
	local slack = margin or 0
	local fixtures = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if not instance:IsDescendantOf(workspace) then continue end

		local position = if instance:IsA("BasePart")
			then (instance :: BasePart).Position
			elseif instance:IsA("Model") then (instance :: Model):GetPivot().Position
			else nil
		if position and HallwayWallService.Contains(frame, position, slack) then
			table.insert(fixtures, instance)
		end
	end
	return fixtures
end

return HallwayWallService
