local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local Sync = CommunicationService.Get("Gems", "Sync") :: RemoteEvent

local ATTRIBUTE = "Gems"

local GemService = {}

local function read(profile): number
	local gems = tonumber(profile.Data.Gems) or 0
	return math.max(0, math.floor(gems))
end

function GemService:Get(player: Player): number
	local profile = DataSaveService:Get(player)
	return if profile then read(profile) else 0
end

function GemService:Sync(player: Player, result: string?)
	local profile = DataSaveService:Get(player)
	if not profile then return end

	local gems = read(profile)
	profile.Data.Gems = gems
	player:SetAttribute(ATTRIBUTE, gems)
	Sync:FireClient(player, gems, result)
end

function GemService:Award(player: Player, amount: number): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false end

	profile.Data.Gems = read(profile) + amount
	GemService:Sync(player)
	return true
end

function GemService:Spend(player: Player, amount: number): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount < 0 then return false end

	local gems = read(profile)
	if gems < amount then return false end

	profile.Data.Gems = gems - amount
	return true
end

Sync.OnServerEvent:Connect(function(player: Player)
	GemService:Sync(player)
end)

local function publish(player: Player)
	DataSaveService:Wait(player)
	if player.Parent == Players then GemService:Sync(player) end
end

for _, player in Players:GetPlayers() do
	task.spawn(publish, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(publish, player)
end)

return GemService
