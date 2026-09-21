local BadgeService = {}

local _BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BadgeConfig = require(ReplicatedStorage.Configs.BadgeConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local BadgeCache = {}
local ValidIds: { [number]: true } = {}
local AllIds: { number } = {}

local function collect(value: any)
	if type(value) == "number" then
		if value > 0 and not ValidIds[value] then
			ValidIds[value] = true
			table.insert(AllIds, value)
		end
	elseif type(value) == "table" then
		for _, nested in value do
			collect(nested)
		end
	end
end

collect(BadgeConfig.Joined)
collect(BadgeConfig.Escaped)
collect(BadgeConfig.Escapes.Badge)
collect(BadgeConfig.Rooms)
collect(BadgeConfig.Computers)
collect(BadgeConfig.Deaths)

function BadgeService:AwardBadge(player: Player, id: number)
	if not ValidIds[id] then
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

	for _, badgeId in AllIds do
		task.spawn(function()
			local success, ownsBadge = pcall(function()
				return _BadgeService:UserHasBadgeAsync(player.UserId, badgeId)
			end)

			local cache = BadgeCache[player]
			if not cache then return end

			if success then
				cache[badgeId] = ownsBadge
			else
				warn("Failed to check badge " .. badgeId .. " for player " .. player.Name)
				cache[badgeId] = false
			end
		end)
	end
end

CharacterService.ForEachPlayer(loadPlayerBadges)
CharacterService.CleanupOnLeave(BadgeCache)

return BadgeService
