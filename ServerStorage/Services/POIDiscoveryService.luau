local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local POIConfig = require(ReplicatedStorage.Configs.POIConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local TagService = require(ReplicatedStorage.Services.TagService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local Detection = POIConfig.Detection
local Remotes = POIConfig.Remotes
local Sound = POIConfig.Sound

local POIDiscoveryService = {}

local DiscoveredRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Discovered)
local EnterRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Enter)
local OccupancyRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Occupancy)
local SyncRemote = CommunicationService.Ensure(Remotes.Folder, Remotes.Sync)

local Parts: { [Instance]: string } = {}
local Discovered: { [Player]: { [string]: boolean } } = {}
local Entered: { [Player]: { [string]: number } } = {}
local Occupied: { [Player]: { [string]: boolean } } = {}

local accumulator = 0

local function boundsOf(instance: Instance): (CFrame?, Vector3?)
	if instance:IsA("BasePart") then return instance.CFrame, instance.Size end
	if instance:IsA("Model") then return instance:GetBoundingBox() end
	return nil, nil
end

local function sidePaddingOf(instance: Instance): number
	local override = instance:GetAttribute("Radius")
	local extra = if type(override) == "number" and override > 0 then override else 0
	return Detection.Padding + extra
end

local function contains(instance: Instance, position: Vector3): boolean
	local cframe, size = boundsOf(instance)
	if not (cframe and size) then return false end

	local point = cframe:PointToObjectSpace(position)
	local half = size / 2
	local side = sidePaddingOf(instance)

	if math.abs(point.X) > half.X + side then return false end
	if math.abs(point.Z) > half.Z + side then return false end
	if point.Y > half.Y + Detection.HeightWindow then return false end
	if point.Y < -half.Y - Detection.BelowWindow then return false end

	return true
end

function POIDiscoveryService:GetTotal(): number
	local names = {}
	local total = 0
	for _, name in Parts do
		if not names[name] then
			names[name] = true
			total += 1
		end
	end
	return total
end

function POIDiscoveryService:GetAll(player: Player): { [string]: boolean }
	return table.clone(Discovered[player] or {})
end

function POIDiscoveryService:Has(player: Player, name: string): boolean
	local set = Discovered[player]
	return (set and set[name]) == true
end

function POIDiscoveryService:GetCount(player: Player): number
	local count = 0
	for _ in Discovered[player] or {} do
		count += 1
	end
	return count
end

local function persist(player: Player)
	local profile = DataSaveService:Get(player)
	if not profile then return end
	profile.Data.DiscoveredPOIs = table.clone(Discovered[player] or {})
end

function POIDiscoveryService:Grant(player: Player, name: string): boolean
	local set = Discovered[player]
	if not set or set[name] then return false end

	set[name] = true
	persist(player)
	DiscoveredRemote:FireClient(player, name, POIDiscoveryService:GetCount(player), POIDiscoveryService:GetTotal())
	return true
end

function POIDiscoveryService:Clear(player: Player)
	if not Discovered[player] then return end

	Discovered[player] = {}
	persist(player)
	SyncRemote:FireClient(player, {}, 0, POIDiscoveryService:GetTotal())
end

local function sweepPlayer(player: Player)
	local set = Discovered[player]
	local entered = Entered[player]
	local occupied = Occupied[player]
	if not (set and entered and occupied) then return end

	local root = CharacterService.GetAliveRoot(player)
	if not root then
		if next(occupied) ~= nil then
			Occupied[player] = {}
			OccupancyRemote:FireClient(player, false)
		end
		return
	end

	local position = root.Position
	local inRange: { [string]: boolean } = {}

	for instance, name in Parts do
		if inRange[name] then continue end
		if not instance:IsDescendantOf(workspace) then continue end
		if not contains(instance, position) then continue end

		inRange[name] = true
	end

	local wasOccupied = next(occupied) ~= nil
	local isOccupied = next(inRange) ~= nil
	if wasOccupied ~= isOccupied then
		OccupancyRemote:FireClient(player, isOccupied)
	end
	Occupied[player] = inRange

	local now = os.clock()
	for name in inRange do
		local last = entered[name]
		if not last or now - last >= Sound.Cooldown then
			entered[name] = now
			EnterRemote:FireClient(player, name)
		end
		POIDiscoveryService:Grant(player, name)
	end
end

local function sweep()
	if next(Parts) == nil then
		for player, occupied in Occupied do
			if next(occupied) == nil then continue end
			Occupied[player] = {}
			OccupancyRemote:FireClient(player, false)
		end
		return
	end

	for _, player in Players:GetPlayers() do
		sweepPlayer(player)
	end
end

local function watchPlayer(player: Player)
	Discovered[player] = {}
	Entered[player] = {}
	Occupied[player] = {}

	task.spawn(function()
		local profile = DataSaveService:Wait(player)
		if not profile or not player:IsDescendantOf(Players) then return end

		local saved = profile.Data.DiscoveredPOIs
		local loaded = {}
		if type(saved) == "table" then
			for name, value in saved do
				if type(name) == "string" and value == true then
					loaded[name] = true
				end
			end
		end

		Discovered[player] = loaded
		SyncRemote:FireClient(player, loaded, POIDiscoveryService:GetCount(player), POIDiscoveryService:GetTotal())
	end)
end

TagService:Listen(POIConfig.Tag, function(instance: Instance)
	Parts[instance] = instance.Name
	return instance.Name
end, function(instance: Instance)
	Parts[instance] = nil
end)

RunService.Heartbeat:Connect(function(delta: number)
	accumulator += delta
	if accumulator < Detection.Interval then return end

	accumulator = 0
	sweep()
end)

SyncRemote.OnServerEvent:Connect(function(player: Player)
	local set = Discovered[player]
	if not set then return end
	SyncRemote:FireClient(player, table.clone(set), POIDiscoveryService:GetCount(player), POIDiscoveryService:GetTotal())
	OccupancyRemote:FireClient(player, next(Occupied[player] or {}) ~= nil)
end)

OccupancyRemote.OnServerEvent:Connect(function(player: Player)
	OccupancyRemote:FireClient(player, next(Occupied[player] or {}) ~= nil)
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	persist(player)
	Discovered[player] = nil
	Entered[player] = nil
	Occupied[player] = nil
end)

return POIDiscoveryService
