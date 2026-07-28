local DataSaveService = {}

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ProfileService = require(ServerStorage.Services.ProfileService)

local PROFILE_STORE_NAME = "PlayerData"
local PROFILE_TEMPLATE = {
	Gems = 0,
	OwnedSwords = {},
	CurrentSword = "Default"
	-- Template will be expanded later
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
