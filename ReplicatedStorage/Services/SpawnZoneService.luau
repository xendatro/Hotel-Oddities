local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpawnZoneConfig = require(ReplicatedStorage.Configs.SpawnZoneConfig)

local SpawnZoneService = {}

local Zones: { BasePart } = {}

local AXES = { "X", "Y", "Z" }

local function refreshZones()
	table.clear(Zones)
	for _, instance in CollectionService:GetTagged(SpawnZoneConfig.Tag) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(Zones, instance)
		end
	end
end

function SpawnZoneService:GetZones(): { BasePart }
	return Zones
end

local function halfExtents(zone: BasePart): Vector3
	local half = zone.Size / 2
	return Vector3.new(half.X, half.Y + SpawnZoneConfig.VerticalPad, half.Z)
end

function SpawnZoneService:Contains(position: Vector3): boolean
	for _, zone in Zones do
		local offset = zone.CFrame:PointToObjectSpace(position)
		local half = halfExtents(zone)
		if math.abs(offset.X) <= half.X
			and math.abs(offset.Y) <= half.Y
			and math.abs(offset.Z) <= half.Z then
			return true
		end
	end
	return false
end

function SpawnZoneService:IntersectsSegment(from: Vector3, to: Vector3): boolean
	for _, zone in Zones do
		local origin = zone.CFrame:PointToObjectSpace(from)
		local delta = zone.CFrame:PointToObjectSpace(to) - origin
		local half = halfExtents(zone)
		local enter, exit = 0, 1
		local separated = false

		for _, axis in AXES do
			local start = (origin :: any)[axis]
			local travel = (delta :: any)[axis]
			local extent = (half :: any)[axis]
			if math.abs(travel) < 1e-6 then
				if start < -extent or start > extent then
					separated = true
					break
				end
			else
				local first = (-extent - start) / travel
				local second = (extent - start) / travel
				if first > second then
					first, second = second, first
				end
				enter = math.max(enter, first)
				exit = math.min(exit, second)
				if enter > exit then
					separated = true
					break
				end
			end
		end

		if not separated then
			return true
		end
	end
	return false
end

refreshZones()
CollectionService:GetInstanceAddedSignal(SpawnZoneConfig.Tag):Connect(refreshZones)
CollectionService:GetInstanceRemovedSignal(SpawnZoneConfig.Tag):Connect(refreshZones)

return SpawnZoneService
