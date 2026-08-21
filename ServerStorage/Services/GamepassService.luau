local GamepassService = {}

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")

local GamepassConfigs = require(ServerStorage.Configs.GamepassConfigs)

local GamepassCache = {}

function GamepassService:UserOwnsGamepass(player: Player, id: number): boolean
	if not GamepassCache[player] then
		return false
	end

	return GamepassCache[player][id] == true
end

local function loadPlayerGamepasses(player: Player)
	GamepassCache[player] = {}

	for _, gamepassId in ipairs(GamepassConfigs) do
		local success, ownsGamepass = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
		end)

		if success then
			GamepassCache[player][gamepassId] = ownsGamepass
		else
			warn("Failed to check gamepass " .. gamepassId .. " for player " .. player.Name)
			GamepassCache[player][gamepassId] = false
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	loadPlayerGamepasses(player)
end)

Players.PlayerRemoving:Connect(function(player)
	GamepassCache[player] = nil
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
	if GamepassCache[player] then
		if wasPurchased then
			GamepassCache[player][gamepassId] = true
		end
	end
end)

return GamepassService
