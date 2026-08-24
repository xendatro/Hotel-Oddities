local GamepassService = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local GamepassConfigs = require(ServerStorage.Configs.GamepassConfigs)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

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
		task.spawn(function()
			local success, ownsGamepass = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
			end)

			local cache = GamepassCache[player]
			if not cache then return end

			if success then
				cache[gamepassId] = ownsGamepass
			else
				warn("Failed to check gamepass " .. gamepassId .. " for player " .. player.Name)
				cache[gamepassId] = false
			end
		end)
	end
end

CharacterService.ForEachPlayer(loadPlayerGamepasses)
CharacterService.CleanupOnLeave(GamepassCache)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
	if GamepassCache[player] then
		if wasPurchased then
			GamepassCache[player][gamepassId] = true
		end
	end
end)

return GamepassService
