local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HallwaysService = require(ReplicatedStorage.Services.HallwaysService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local Discovery = MapConfig.Discovery
local Remotes = MapConfig.Remotes

local MapDiscoveryService = {}

local SyncRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Sync)
local RevealRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Reveal)

export type Interval = { number }

type Entry = {
	Key: string,
	Hallway: HallwaysService.Hallway,
}

local Entries: { Entry } = {}
local EntrySource: { HallwaysService.Hallway }? = nil

local function getEntries(): { Entry }
	local hallways = HallwaysService.All(true)
	if EntrySource == hallways then return Entries end

	local entries = {}
	for _, hallway in hallways do
		table.insert(entries, {
			Key = string.format("%d,%d", math.round(hallway.Center.X), math.round(hallway.Center.Z)),
			Hallway = hallway,
		})
	end

	Entries = entries
	EntrySource = hallways
	return entries
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
			X = hallway.Center.X,
			Z = hallway.Center.Z,
			AxisX = hallway.Axis.X,
			AxisZ = hallway.Axis.Z,
			HalfLength = hallway.HalfLength,
			HalfWidth = hallway.HalfWidth,
			IsRoom = hallway.IsRoomFloor,
		})
	end
	return layout
end

function MapDiscoveryService:GetDiscovered(player: Player): { [string]: Interval }?
	return getStore(player)
end

function MapDiscoveryService:Sync(player: Player)
	local store = getStore(player)
	if not store then return end
	SyncRemote:FireClient(player, self:GetLayout(), store)
end

function MapDiscoveryService:Update(player: Player)
	local root = CharacterService.GetAliveRoot(player)
	if not root then return end

	local store = getStore(player)
	if not store then return end

	local position = root.Position
	for _, entry in getEntries() do
		local minimum, maximum = coveredSpan(entry.Hallway, position)
		if not minimum or not maximum then continue end

		local packed = merge(store[entry.Key] or {}, minimum, maximum)
		if packed then
			store[entry.Key] = packed
			RevealRemote:FireClient(player, entry.Key, packed)
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		DataSaveService:Wait(player)
		if player:IsDescendantOf(Players) then
			MapDiscoveryService:Sync(player)
		end
	end)
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
