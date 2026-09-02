local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallwaysService = require(ReplicatedStorage.Services.HallwaysService)
local TagService = require(ReplicatedStorage.Services.TagService)

local HolePlacementService = {}

local FLOOR_TAGS = { "MazeFloor", "HallwayRoomFloor" }
local SURFACE_OFFSET = 0.5
local RAYCAST_HEIGHT = 16
local RAYCAST_DEPTH = 32
local SURFACE_TOLERANCE = 4
local FOOTPRINT_PADDING = 0.05
local RANDOM_ATTEMPTS = 80

local function getRaycastParams(floors: { BasePart }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = floors
	return params
end

function HolePlacementService.GetFloors(ancestor: Instance): { BasePart }
	local floors = {}
	local seen = {}

	for _, tag in FLOOR_TAGS do
		for _, instance in TagService:GetTaggedOfAncestor(ancestor, tag) do
			if instance:IsA("BasePart") and not seen[instance] then
				seen[instance] = true
				table.insert(floors, instance)
			end
		end
	end

	return floors
end

function HolePlacementService.FindGround(
	origin: Vector3,
	depth: number,
	floors: { BasePart },
	params: RaycastParams?
): RaycastResult?
	if #floors == 0 then return nil end
	return workspace:Raycast(
		origin,
		Vector3.new(0, -depth, 0),
		params or getRaycastParams(floors)
	)
end

local function getOrientation(model: Model): CFrame
	local x, y, z = model:GetPivot():ToOrientation()
	return CFrame.fromOrientation(x, y, z)
end

local function getFootprintPoints(model: Model, position: Vector3, scale: number): { Vector3 }?
	local boxCFrame, boxSize = model:GetBoundingBox()
	local pivot = model:GetPivot()
	local relativeBox = pivot:ToObjectSpace(boxCFrame)
	local orientation = getOrientation(model)
	local axes = { relativeBox.RightVector, relativeBox.UpVector, relativeBox.LookVector }
	local sizes = { boxSize.X, boxSize.Y, boxSize.Z }
	local horizontal = {}

	for index, axis in axes do
		if math.abs(orientation:VectorToWorldSpace(axis).Y) < 0.5 then
			table.insert(horizontal, { Axis = axis, Half = sizes[index] * scale / 2 + FOOTPRINT_PADDING })
		end
	end
	if #horizontal ~= 2 then return nil end

	local center = relativeBox.Position * scale
	local points = {}
	for _, along in { -1, 0, 1 } do
		for _, across in { -1, 0, 1 } do
			local localPoint = center
				+ horizontal[1].Axis * horizontal[1].Half * along
				+ horizontal[2].Axis * horizontal[2].Half * across
			table.insert(points, position + orientation:VectorToWorldSpace(localPoint))
		end
	end
	return points
end

function HolePlacementService.IsFootprintSupported(
	position: Vector3,
	model: Model,
	floors: { BasePart },
	scale: number?,
	surfaceY: number?
): boolean
	if #floors == 0 then return false end

	local points = getFootprintPoints(model, position, scale or 1)
	if not points then return false end

	local expectedY = surfaceY or position.Y - SURFACE_OFFSET
	local params = getRaycastParams(floors)
	for _, point in points do
		local origin = Vector3.new(point.X, expectedY + RAYCAST_HEIGHT, point.Z)
		local hit = workspace:Raycast(origin, Vector3.new(0, -RAYCAST_DEPTH, 0), params)
		if not hit or math.abs(hit.Position.Y - expectedY) > SURFACE_TOLERANCE then
			return false
		end
	end
	return true
end

function HolePlacementService.FindRandomPosition(
	model: Model,
	floors: { BasePart },
	scale: number?
): Vector3?
	if #floors == 0 then return nil end

	local params = getRaycastParams(floors)
	local function resolve(point: Vector3, floorY: number): Vector3?
		local rayOrigin = Vector3.new(point.X, floorY + RAYCAST_HEIGHT, point.Z)
		local ground = HolePlacementService.FindGround(rayOrigin, RAYCAST_DEPTH, floors, params)
		if not ground then return nil end

		local position = ground.Position + Vector3.new(0, SURFACE_OFFSET, 0)
		return if HolePlacementService.IsFootprintSupported(position, model, floors, scale, ground.Position.Y)
			then position
			else nil
	end

	for _ = 1, RANDOM_ATTEMPTS do
		local floor = floors[math.random(1, #floors)]
		local hallway = HallwaysService.FromPart(floor, floor:HasTag("HallwayRoomFloor"))
		local along = (math.random() * 2 - 1) * hallway.HalfLength
		local across = (math.random() * 2 - 1) * hallway.HalfWidth
		local point = hallway.Center + hallway.Axis * along + hallway.Across * across
		local position = resolve(point, hallway.FloorY)
		if position then return position end
	end

	for _, floor in floors do
		local hallway = HallwaysService.FromPart(floor, floor:HasTag("HallwayRoomFloor"))
		local position = resolve(hallway.Center, hallway.FloorY)
		if position then return position end
	end
	return nil
end

return HolePlacementService
