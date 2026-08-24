local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local PerfLog = require(ReplicatedStorage.Modules.PerfLog)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)
local DangerMapService = require(ServerStorage.Services.DangerMapService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local TagService = require(ReplicatedStorage.Services.TagService)

local VENT_TAG = "CeilingVent"
local PROGRAMMATIC_ATTRIBUTE = "ProgrammaticVent"
local CEILING_SLAB_NAME = "CeilingSlab"
local HALLWAY_STATION_NAME = "HallwayStation"
local CEILING_BEAM_NAME = "CeilingBeam"
local VENT_VISUAL_OFFSET = Vector3.new(0, -0.55, 0)
local CEILING_CLEARANCE = 0.05
local MAX_PLAYER_DISTANCE = 26

local Config = DangerConfig.ProgrammaticVents
local Template = ReplicatedStorage.Props.Other:FindFirstChild("Vent")
local ActiveFolder = Instance.new("Folder")
ActiveFolder.Name = "ProgrammaticVents"
ActiveFolder.Parent = workspace

type ManagedVent = {
	Model: Model,
	ExpiresAt: number,
}

local Managed: { ManagedVent } = {}
local SpawnAccumulator = 0
local InitialSpawnAccumulator = 0
local DespawnAccumulator = 0

local GEOMETRY_CACHE_TTL = 1

local CachedSlabs: { BasePart }? = nil
local CachedBeams: { BasePart }? = nil
local SlabsCachedAt = -math.huge
local BeamsCachedAt = -math.huge

local function getSlabs(): { BasePart }
	local now = os.clock()
	if CachedSlabs and now - SlabsCachedAt < GEOMETRY_CACHE_TTL then
		return CachedSlabs
	end

	local slabs = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and instance.Name == CEILING_SLAB_NAME then
			table.insert(slabs, instance)
		end
	end
	CachedSlabs = slabs
	SlabsCachedAt = now
	return slabs
end

local function getStationBeams(): { BasePart }
	local now = os.clock()
	if CachedBeams and now - BeamsCachedAt < GEOMETRY_CACHE_TTL then
		return CachedBeams
	end

	local beams = {}
	for _, instance in workspace:GetDescendants() do
		if not instance:IsA("BasePart") then continue end
		local station = instance:FindFirstAncestorWhichIsA("Model")
		if station
			and station.Name == HALLWAY_STATION_NAME
			and (instance.Name == CEILING_BEAM_NAME or station.PrimaryPart == instance)
		then
			table.insert(beams, instance)
		end
	end
	CachedBeams = beams
	BeamsCachedAt = now
	return beams
end

local function pointInsideSlab(point: Vector3, slab: BasePart, margin: Vector3): boolean
	local localPoint = slab.CFrame:PointToObjectSpace(point)
	local half = slab.Size / 2
	return math.abs(localPoint.X) <= half.X - margin.X
		and math.abs(localPoint.Z) <= half.Z - margin.Z
		and point.Y < slab.Position.Y + slab.Size.Y
end

local function findSlab(point: Vector3, margin: Vector3): BasePart?
	local best: BasePart? = nil
	local bestHeight = math.huge
	for _, slab in getSlabs() do
		if slab.Position.Y > point.Y and slab.Position.Y < bestHeight and pointInsideSlab(point, slab, margin) then
			best = slab
			bestHeight = slab.Position.Y
		end
	end
	return best
end

local function getRotation(cframe: CFrame): CFrame
	return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector)
end

local function getVentCFrame(
	point: Vector3,
	slab: BasePart,
	template: Model,
	relativeBounds: CFrame,
	boundsSize: Vector3
): CFrame
	local rotation = getRotation(slab.CFrame) * getRotation(template:GetPivot())
	local centered = CFrame.new(Vector3.new(point.X, slab.Position.Y, point.Z)) * rotation
	local bounds = centered * relativeBounds
	local top = bounds.Position + bounds.UpVector * (boundsSize.Y / 2)
	local topOffset = (top - centered.Position):Dot(slab.CFrame.UpVector)
	local drop = -slab.Size.Y / 2 - CEILING_CLEARANCE - topOffset
	return CFrame.new(centered.Position + slab.CFrame.UpVector * drop) * rotation
end

local function visualPoints(modelCFrame: CFrame, boundsSize: Vector3): { Vector3 }
	local half = boundsSize / 2
	local points = { modelCFrame:PointToWorldSpace(VENT_VISUAL_OFFSET) }
	for _, x in { -half.X * 0.8, half.X * 0.8 } do
		for _, z in { -half.Z * 0.8, half.Z * 0.8 } do
			table.insert(points, modelCFrame:PointToWorldSpace(Vector3.new(x, VENT_VISUAL_OFFSET.Y, z)))
		end
	end
	return points
end

local function isVisible(points: { Vector3 }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local excluded = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then table.insert(excluded, character) end
	end
	params.FilterDescendantsInstances = excluded

	for _, eye in EnemyObservationService:GetEyes() do
		for _, point in points do
			local offset = point - eye
			if offset.Magnitude < 1e-3 or workspace:Raycast(eye, offset, params) == nil then
				return true
			end
		end
	end
	return false
end

local function isNearPlayer(position: Vector3): boolean
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root then
			local offset = root.Position - position
			if MathService.HorizontalMagnitude(offset) <= MAX_PLAYER_DISTANCE and offset.Y <= 2 and offset.Y >= -24 then
				return true
			end
		end
	end
	return false
end

local function overlapsWorldGeometry(cframe: CFrame, size: Vector3): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = false
	params.MaxParts = 1

	local excluded = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	params.FilterDescendantsInstances = excluded
	return #workspace:GetPartBoundsInBox(cframe, size, params) > 0
end

local function overlapsStationBeam(cframe: CFrame, size: Vector3, beams: { BasePart }): boolean
	if #beams == 0 then return false end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = beams
	overlap.MaxParts = 1
	return #workspace:GetPartBoundsInBox(cframe, size, overlap) > 0
end

local function isTooClose(position: Vector3): boolean
	for _, entry in Managed do
		if entry.Model.Parent and (entry.Model:GetPivot().Position - position).Magnitude < Config.MinimumSpacing then
			return true
		end
	end
	for _, vent in CollectionService:GetTagged(VENT_TAG) do
		if not vent:IsA("Model") or not vent:IsDescendantOf(workspace) then continue end
		if (vent:GetPivot().Position - position).Magnitude < Config.MinimumSpacing then return true end
	end
	return false
end

local function trySpawn(): boolean
	if not Template or not Template:IsA("Model") or #Managed >= Config.MaxAlive then return false end
	local template = Template :: Model
	local templateBoundsCFrame, templateBounds = template:GetBoundingBox()
	local relativeBounds = template:GetPivot():ToObjectSpace(templateBoundsCFrame)
	local footprint = math.max(templateBounds.X, templateBounds.Z)
	local placementSize = Vector3.new(footprint, templateBounds.Y, footprint)
	local slabMargin = Vector3.new(footprint / 2 + 0.5, 0, footprint / 2 + 0.5)
	local beams = getStationBeams()
	--- Bias 0 weights every point equally, so placement is uniform across the map.
	--- Danger no longer decides where a vent goes, only how fast it arms.
	local point = DangerMapService:PickPoint(0, function(candidate)
		if isTooClose(candidate.Position) or isNearPlayer(candidate.Position) then return false end

		local slab = findSlab(candidate.Position, slabMargin)
		if not slab then return false end
		local target = getVentCFrame(candidate.Position, slab, template, relativeBounds, templateBounds)
		local boundsCFrame = target * relativeBounds
		if overlapsWorldGeometry(boundsCFrame, templateBounds) then return false end
		if overlapsStationBeam(boundsCFrame, templateBounds, beams) then return false end
		return not isVisible(visualPoints(boundsCFrame, templateBounds))
	end, Config.PlacementAttempts)
	if not point then return false end

	local slab = findSlab(point.Position, slabMargin)
	if not slab then return false end
	local target = getVentCFrame(point.Position, slab, template, relativeBounds, templateBounds)
	local vent = template:Clone()
	vent.Name = "ProgrammaticVent"
	vent:SetAttribute(PROGRAMMATIC_ATTRIBUTE, true)
	vent:PivotTo(target)
	local boundsCFrame, actualBounds = vent:GetBoundingBox()
	if overlapsWorldGeometry(boundsCFrame, actualBounds)
		or isNearPlayer(point.Position)
		or isVisible(visualPoints(boundsCFrame, actualBounds))
	then
		vent:Destroy()
		PerfLog.Log("Vent", "placement discarded")
		return false
	end
	vent.Parent = ActiveFolder
	PerfLog.Log("Vent", "spawn")
	table.insert(Managed, { Model = vent, ExpiresAt = os.clock() + Config.Lifetime })
	return true
end

local function canRemove(entry: ManagedVent, now: number): boolean
	local model = entry.Model
	if not model.Parent then return true end

	local state = nil
	if table.find(TagService:GetListenedTags(), VENT_TAG) then
		state = TagService:GetApplied(VENT_TAG, model)
	end

	-- Mid-drop: the door is opening or the dweller has not landed yet.
	if state and state.Triggered and not state.Spent then return false end
	-- A spent vent can never fire again, so it goes as soon as nobody can see it.
	local expired = (state ~= nil and state.Spent) or now >= entry.ExpiresAt
	if not expired then return false end

	if isNearPlayer(model:GetPivot().Position) then return false end
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	return not isVisible(visualPoints(boundsCFrame, boundsSize))
end

local function sweepDespawn(now: number)
	for index = #Managed, 1, -1 do
		local entry = Managed[index]
		if not entry.Model.Parent then
			table.remove(Managed, index)
			continue
		end
		if canRemove(entry, now) then
			entry.Model:Destroy()
			table.remove(Managed, index)
			PerfLog.Log("Vent", "despawn")
		end
	end
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	SpawnAccumulator += deltaTime
	InitialSpawnAccumulator += deltaTime
	DespawnAccumulator += deltaTime
	if #Managed < math.min(Config.InitialAlive, Config.MaxAlive)
		and InitialSpawnAccumulator >= Config.InitialSpawnInterval
	then
		InitialSpawnAccumulator = 0
		SpawnAccumulator = 0
		trySpawn()
	elseif SpawnAccumulator >= Config.SpawnInterval then
		SpawnAccumulator = 0
		trySpawn()
	end
	if DespawnAccumulator >= Config.DespawnInterval then
		DespawnAccumulator = 0
		sweepDespawn(os.clock())
	end
end)

return {}
