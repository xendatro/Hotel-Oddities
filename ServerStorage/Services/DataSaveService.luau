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
	--- Dense inventory entries written by InventoryService. Quantity and slot order are saved along
	--- with stateful attributes such as a Pathfinder's remaining uses.
	Inventory = {},
	--- Developer-product receipts granted by ItemShopService, keyed by PurchaseId.
	ProcessedItemReceipts = {},

	--- How much of each enemy's index entry the player has earned, keyed by the same enemy id
	--- `EnemyConfigs` and `IndexConfig` use, valued 0 to 1. Owned by `EnemyDiscoveryService`, which
	--- is the only thing that should read or write it. Empty for a new player: every entry starts
	--- undiscovered, and nothing is stored at zero -- a save file only carries what has been met.
	DiscoveredEnemies = {},
}

local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)
local Profiles = {}


-- Get a player's profile (returns nil if not loaded)
function DataSaveService:Get(player: Player)
	return Profiles[player]
end

-- Wait for a player's profile to load (yields)
function DataSaveService:Wait(player: Player)
	while not Profiles[player] do
		task.wait()
	end
	return Profiles[player]
end

-- Handle player joining
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

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
	local profile = Profiles[player]
	if profile then
		profile:Release()
		Profiles[player] = nil
	end
end)

return DataSaveService
