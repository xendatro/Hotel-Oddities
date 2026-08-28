local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local HumanoidStatsService = require(ReplicatedStorage.Services.HumanoidStatsService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local Sync = CommunicationService.Get("Kits", "Sync") :: RemoteEvent
local Equip = CommunicationService.Get("Kits", "Equip") :: RemoteEvent

local SOURCE = "Kit"
local HUMANOID_TIMEOUT = 10
local INVENTORY_TIMEOUT = 10

local KitService = {}

local function owned(profile): { [string]: boolean }
	local kits = profile.Data.OwnedKits
	if type(kits) ~= "table" then
		kits = {}
		profile.Data.OwnedKits = kits
	end
	kits[KitConfig.DefaultKit] = true
	return kits
end

local function grantRecord(profile): { [string]: number }
	local record = profile.Data.KitGrant
	if type(record) ~= "table" then
		record = {}
		profile.Data.KitGrant = record
	end
	return record
end

local function equippedId(profile): string
	local id = profile.Data.EquippedKit
	if type(id) ~= "string" or not KitConfig.EntriesById[id] or not owned(profile)[id] then
		id = KitConfig.DefaultKit
		profile.Data.EquippedKit = id
	end
	return id
end

function KitService:Owns(player: Player, kitId: string): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end
	return owned(profile)[kitId] == true
end

function KitService:GetEquipped(player: Player): string?
	local profile = DataSaveService:Get(player)
	return if profile then equippedId(profile) else nil
end

function KitService:Sync(player: Player, result: string?, kitId: string?)
	local profile = DataSaveService:Get(player)
	if not profile then return end

	local list = {}
	for id in owned(profile) do
		if KitConfig.EntriesById[id] then table.insert(list, id) end
	end
	table.sort(list)

	Sync:FireClient(player, list, equippedId(profile), result, kitId)
end

function KitService:Grant(player: Player, kitId: string): boolean
	local profile = DataSaveService:Get(player)
	if not profile or not KitConfig.EntriesById[kitId] then return false end

	local kits = owned(profile)
	if kits[kitId] then return false end

	kits[kitId] = true
	return true
end

function KitService:SetEquipped(player: Player, kitId: string): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end
	if not KitConfig.EntriesById[kitId] or not owned(profile)[kitId] then return false end

	profile.Data.EquippedKit = kitId
	return true
end

local function applyStats(player: Player, character: Model, kit: KitConfig.Kit)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
		or character:WaitForChild("Humanoid", HUMANOID_TIMEOUT)
	if not humanoid or not humanoid:IsA("Humanoid") then return end
	if player.Character ~= character then return end

	HumanoidStatsService:SetSource(humanoid, SOURCE, kit.Stats)
end

local function applyItems(player: Player, kit: KitConfig.Kit)
	if not InventoryService:Wait(player, INVENTORY_TIMEOUT) then return end

	local profile = DataSaveService:Get(player)
	if not profile then return end

	local previous = grantRecord(profile)
	for itemName, count in previous do
		if type(itemName) == "string" and type(count) == "number" and count > 0 then
			InventoryService:Remove(player, itemName, count)
		end
	end

	local record = {}
	profile.Data.KitGrant = record

	for itemName, count in kit.Items or {} do
		count = math.floor(tonumber(count) or 0)
		if count <= 0 then continue end
		if InventoryService:Add(player, itemName, count) then
			record[itemName] = count
		end
	end
end

function KitService:ApplyTo(player: Player, character: Model)
	local profile = DataSaveService:Wait(player)
	if not profile or player.Character ~= character then return end

	local kit = KitConfig.EntriesById[equippedId(profile)]
	if not kit then return end

	task.spawn(applyStats, player, character, kit)
	task.spawn(applyItems, player, kit)
end

Equip.OnServerEvent:Connect(function(player: Player, kitId: any)
	if type(kitId) ~= "string" then return end

	if not KitService:SetEquipped(player, kitId) then
		KitService:Sync(player, "NotOwned", kitId)
		return
	end

	KitService:Sync(player, "Equipped", kitId)
end)

Sync.OnServerEvent:Connect(function(player: Player)
	KitService:Sync(player)
end)

local function watch(player: Player)
	DataSaveService:Wait(player)
	if player.Parent ~= Players then return end

	KitService:Sync(player)
	if player.Character then
		task.spawn(KitService.ApplyTo, KitService, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		task.spawn(KitService.ApplyTo, KitService, player, character)
	end)
end

for _, player in Players:GetPlayers() do
	task.spawn(watch, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(watch, player)
end)

task.defer(function()
	for _, problem in KitConfig.Validate() do
		warn(`KitService: {problem}`)
	end
end)

return KitService
