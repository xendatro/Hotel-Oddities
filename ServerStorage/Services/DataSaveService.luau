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

	OwnedKits = {},
	EquippedKit = "",
	KitGrant = {},
	ProcessedKitReceipts = {},

	WalkieAudio = {},
	WalkieMode = "All",

	DiscoveredEnemies = {},
	DiscoveredMap = {},
	DiscoveredLandmarks = {},
}

local ProfileStore = ProfileService.GetProfileStore(PROFILE_STORE_NAME, PROFILE_TEMPLATE)
local Profiles = {}
local Waiters: { [Player]: { thread } } = {}

function DataSaveService:Get(player: Player)
	return Profiles[player]
end

function DataSaveService:Wait(player: Player)
	local profile = Profiles[player]
	if profile then
		return profile
	end

	local list = Waiters[player]
	if not list then
		list = {}
		Waiters[player] = list
	end
	table.insert(list, coroutine.running())
	return coroutine.yield()
end

local function resolveWaiters(player: Player)
	local list = Waiters[player]
	if not list then return end
	Waiters[player] = nil

	local profile = Profiles[player]
	for _, thread in list do
		task.spawn(thread, profile)
	end
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
			resolveWaiters(player)
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
	Waiters[player] = nil
end)

return DataSaveService
