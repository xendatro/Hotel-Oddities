local DataSaveService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileService = require(ServerStorage.Services.ProfileService)
local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)

local PROFILE_STORE_NAME = "PlayerData"
local PROFILE_TEMPLATE = {
	Gems = 0,
	Coins = ItemShopConfig.StartingCoins,
	OwnedSwords = {},
	CurrentSword = "Default",
	Inventory = {},
	ProcessedItemReceipts = {},

	DiscoveredEnemies = {},
}

local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)
local Profiles = {}

function DataSaveService:Get(player: Player)
	return Profiles[player]
end

function DataSaveService:Wait(player: Player)
	while not Profiles[player] do
		task.wait()
	end
	return Profiles[player]
end

Players.PlayerAdded:Connect(function(player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile then
		profile:AddUserId(player.UserId)
		profile:Reconcile()

		profile:ListenToRelease(function()
			Profiles[player] = nil
			player:Kick("Profile released")
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile
		else
			profile:Release()
		end
	else
		player:Kick("Failed to load data")
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile then
		profile:Release()
		Profiles[player] = nil
	end
end)

return DataSaveService
