local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HallwaysService = require(ReplicatedStorage.Services.HallwaysService)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local Discovery = MapConfig.Discovery
local Remotes = MapConfig.Remotes

local MapDiscoveryService = {}

local SyncRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Sync)
local RevealRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Reveal)
local LandmarkRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Landmark)

export type Interval = { number }

type Entry = {
	Key: string,
	Kind: string,
	Hallway: HallwaysService.Hallway,
}

local Entries: { Entry } = {}
local EntrySource: { HallwaysService.Hallway }? = nil

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude
RayParams.RespectCanCollide = true
RayParams.IgnoreWater = true

local function refreshRayFilter()
	local ignore = {}
	for _, other in Players:GetPlayers() do
		if other.Character then table.insert(ignore, other.Character) end
	end
	RayParams.FilterDescendantsInstances = ignore
end

local function isVisible(eye: Vector3, target: Vector3): boolean
	local offset = target - eye
	if offset.Magnitude < 1e-3 then return true end
	return workspace:Raycast(eye, offset, RayParams) == nil
end

local function visibleRuns(
	hallway: HallwaysService.Hallway,
	eye: Vector3,
	minimum: number,
	maximum: number
): { { number } }
	local step = Discovery.VisibilityStep
	local samples = math.max(math.ceil((maximum - minimum) / step), 1)
	local height = hallway.FloorY + Discovery.EyeHeight

	local runs = {}
	local runStart: number? = nil

	for index = 0, samples do
		local along = minimum + (maximum - minimum) * (index / samples)
		local centre = hallway.Center + hallway.Axis * along
		local seen = isVisible(eye, Vector3.new(centre.X, height, centre.Z))

		if seen and not runStart then
			runStart = along
		elseif not seen and runStart then
			if along - runStart >= Discovery.MinGrowth then
				table.insert(runs, { runStart, along })
			end
			runStart = nil
		end
	end

	if runStart and maximum - runStart >= Discovery.MinGrowth then
		table.insert(runs, { runStart, maximum })
	end
	return runs
end

local function addEntry(entries: { Entry }, hallway: HallwaysService.Hallway, kind: string)
	table.insert(entries, {
		Key = string.format("%d,%d", math.round(hallway.Center.X), math.round(hallway.Center.Z)),
		Kind = kind,
		Hallway = hallway,
	})
end

local function getEntries(): { Entry }
	local hallways = HallwaysService.All(true)
	if EntrySource == hallways then return Entries end

	local entries = {}
	for _, hallway in hallways do
		addEntry(entries, hallway, if hallway.IsRoomFloor then "Connector" else "Hallway")
	end

	local computerFloors = {}
	for _, floor in CollectionService:GetTagged(MapConfig.Rooms.ComputerTag) do
		computerFloors[floor] = true
	end
	for _, floor in CollectionService:GetTagged(MapConfig.Rooms.Tag) do
		if floor:IsA("BasePart") and floor:IsDescendantOf(workspace) then
			addEntry(entries, HallwaysService.FromPart(floor, true), if computerFloors[floor] then "ComputerRoom" else "Room")
		end
	end

	Entries = entries
	EntrySource = hallways
	return entries
end

local function getLandmarks(player: Player): { [string]: { [string]: boolean } }?
	local profile = DataSaveService:Get(player)
	if not profile then return nil end

	local store = profile.Data.DiscoveredLandmarks
	if not store then
		store = {}
		profile.Data.DiscoveredLandmarks = store
	end
	return store
end

local function getStore(player: Player): { [string]: Interval }?
	local profile = DataSaveService:Get(player)
	if not profile then return nil end

	local store = profile.Data.DiscoveredMap
	if not store then
		store = {}
		profile.Data.DiscoveredMap = store
	end
	return store
end

local function coverage(packed: Interval): number
	local total = 0
	for index = 1, #packed - 1, 2 do
		total += packed[index + 1] - packed[index]
	end
	return total
end

local function merge(packed: Interval, minimum: number, maximum: number): Interval?
	local intervals = { { math.round(minimum), math.round(maximum) } }
	for index = 1, #packed - 1, 2 do
		table.insert(intervals, { packed[index], packed[index + 1] })
	end
	table.sort(intervals, function(first, second)
		return first[1] < second[1]
	end)

	local merged = {}
	for _, interval in intervals do
		local last = merged[#merged]
		if last and interval[1] <= last[2] + Discovery.MinGrowth then
			last[2] = math.max(last[2], interval[2])
		else
			table.insert(merged, interval)
		end
	end

	local result = {}
	for _, interval in merged do
		table.insert(result, interval[1])
		table.insert(result, interval[2])
	end

	if coverage(result) - coverage(packed) < Discovery.MinGrowth then return nil end
	return result
end

local function coveredSpan(hallway: HallwaysService.Hallway, position: Vector3): (number?, number?)
	local height = position.Y - hallway.FloorY
	if height > Discovery.HeightWindow or height < -Discovery.BelowWindow then return nil, nil end

	local offset = position - hallway.Center
	local lateral = math.max(math.abs(offset:Dot(hallway.Across)) - hallway.HalfWidth, 0)
	if lateral >= Discovery.Radius then return nil, nil end

	local reach = math.sqrt(Discovery.Radius * Discovery.Radius - lateral * lateral)
	local along = offset:Dot(hallway.Axis)
	local minimum = math.max(along - reach, -hallway.HalfLength)
	local maximum = math.min(along + reach, hallway.HalfLength)
	if maximum <= minimum then return nil, nil end

	return minimum, maximum
end

function MapDiscoveryService:GetLayout(): { any }
	local layout = {}
	for _, entry in getEntries() do
		local hallway = entry.Hallway
		table.insert(layout, {
			Key = entry.Key,
			Kind = entry.Kind,
			X = hallway.Center.X,
			Z = hallway.Center.Z,
			AxisX = hallway.Axis.X,
			AxisZ = hallway.Axis.Z,
			HalfLength = hallway.HalfLength,
			HalfWidth = hallway.HalfWidth,
			IsRoom = entry.Kind ~= "Hallway",
		})
	end
	return layout
end

function MapDiscoveryService:GetDiscovered(player: Player): { [string]: Interval }?
	return getStore(player)
end

function MapDiscoveryService:Sync(player: Player)
	local store = getStore(player)
	local landmarks = getLandmarks(player)
	if not store or not landmarks then return end
	SyncRemote:FireClient(player, self:GetLayout(), store, landmarks)
end

function MapDiscoveryService:UpdateLandmarks(player: Player, position: Vector3)
	local landmarks = getLandmarks(player)
	if not landmarks then return end

	for kind, settings in MapConfig.Landmarks do
		local found = landmarks[kind]
		if not found then
			found = {}
			landmarks[kind] = found
		end

		for _, instance in CollectionService:GetTagged(settings.Tag) do
			if not instance:IsDescendantOf(workspace) then continue end

			local pivot = if instance:IsA("Model") then instance:GetPivot().Position elseif instance:IsA("BasePart") then instance.Position else nil
			if not pivot then continue end
			if (pivot - position).Magnitude > settings.Radius then continue end

			local key = string.format("%d,%d", math.round(pivot.X), math.round(pivot.Z))
			if found[key] then continue end

			found[key] = true
			LandmarkRemote:FireClient(player, kind, key)
		end
	end
end

function MapDiscoveryService:Update(player: Player)
	local root = CharacterService.GetAliveRoot(player)
	if not root then return end

	local store = getStore(player)
	if not store then return end

	local position = root.Position
	self:UpdateLandmarks(player, position)

	local eye = position + Vector3.new(0, Discovery.EyeHeight, 0)
	refreshRayFilter()

	for _, entry in getEntries() do
		local minimum, maximum = coveredSpan(entry.Hallway, position)
		if not minimum or not maximum then continue end

		local known = store[entry.Key] or {}
		local changed = false

		if entry.Kind ~= "Hallway" then
			local half = math.round(entry.Hallway.HalfLength)
			if #known == 2 and known[1] <= -half and known[2] >= half then continue end
			if #visibleRuns(entry.Hallway, eye, minimum, maximum) == 0 then continue end

			known = { -half, half }
			changed = true
		else
			for _, fresh in MapLayoutService:Subtract(minimum, maximum, known) do
				if fresh[2] - fresh[1] < Discovery.MinGrowth then continue end

				for _, run in visibleRuns(entry.Hallway, eye, fresh[1], fresh[2]) do
					local packed = merge(known, run[1], run[2])
					if packed then
						known = packed
						changed = true
					end
				end
			end
		end

		if changed then
			store[entry.Key] = known
			RevealRemote:FireClient(player, entry.Key, known)
		end
	end
end

CharacterService.ForEachPlayer(function(player)
	DataSaveService:Wait(player)
	if player:IsDescendantOf(Players) then
		MapDiscoveryService:Sync(player)
	end
end)

local Elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	Elapsed += deltaTime
	if Elapsed < Discovery.Interval then return end
	Elapsed = 0

	for _, player in Players:GetPlayers() do
		MapDiscoveryService:Update(player)
	end
end)

return MapDiscoveryService
