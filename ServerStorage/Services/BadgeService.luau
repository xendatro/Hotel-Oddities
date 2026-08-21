local BadgeService = {}

local Players = game:GetService("Players")
local _BadgeService = game:GetService("BadgeService")
local ServerStorage = game:GetService("ServerStorage")

local BadgeConfigs = require(ServerStorage.Configs.BadgeConfigs)

local BadgeCache = {}

function BadgeService:AwardBadge(player: Player, id: number)
	local isValidBadge = false
	for _, badgeId in ipairs(BadgeConfigs) do
		if badgeId == id then
			isValidBadge = true
			break
		end
	end

	if not isValidBadge then
		warn("Attempted to award badge " .. id .. " which is not in BadgeConfigs")
		return false
	end

	if BadgeCache[player] and BadgeCache[player][id] then
		return false
	end

	local success, result = pcall(function()
		_BadgeService:AwardBadgeAsync(player.UserId, id)
	end)

	if success then
		if BadgeCache[player] then
			BadgeCache[player][id] = true
		end
		return true
	else
		warn("Failed to award badge " .. id .. " to " .. player.Name .. ": " .. tostring(result))
		return false
	end
end

function BadgeService:GetBadges(player: Player)
	if not BadgeCache[player] then
		return {}
	end

	return BadgeCache[player]
end

function BadgeService:OwnsBadge(player: Player, id: number): boolean
	if not BadgeCache[player] then
		return false
	end

	return BadgeCache[player][id] == true
end

local function loadPlayerBadges(player: Player)
	BadgeCache[player] = {}

	for _, badgeId in ipairs(BadgeConfigs) do
		local success, ownsBadge = pcall(function()
			return _BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
		end)

		if success then
			BadgeCache[player][badgeId] = ownsBadge
		else
			warn("Failed to check badge " .. badgeId .. " for player " .. player.Name)
			BadgeCache[player][badgeId] = false
		end
	end
end

Players.PlayerAdded:Connect(function(player)
	loadPlayerBadges(player)
end)

Players.PlayerRemoving:Connect(function(player)
	BadgeCache[player] = nil
end)

return BadgeService
