local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local PlayerOddityService = require(ServerStorage.Services.PlayerOddityService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local PlayerOddityCommandService = {}

local EFFECTS = {
	size = "Size",
	headsize = "HeadSize",
	bighead = "HeadSize",
	transparency = "Transparency",
	stare = "HeadStare",
	headstare = "HeadStare",
}

local function split(argument: string?): { string }
	local result = {}
	if not argument then return result end
	for token in argument:gmatch("%S+") do
		table.insert(result, token)
	end
	return result
end

local function findPlayer(name: string, caller: Player): (Player?, string?)
	local lowered = name:lower()
	if lowered == "me" or lowered == "self" then return caller, nil end

	for _, player in Players:GetPlayers() do
		if player.Name:lower() == lowered then return player, nil end
	end
	for _, player in Players:GetPlayers() do
		if player.DisplayName:lower() == lowered then return player, nil end
	end

	local matches = {}
	for _, player in Players:GetPlayers() do
		if player.Name:lower():sub(1, #lowered) == lowered then
			table.insert(matches, player)
		end
	end
	if #matches == 1 then return matches[1], nil end
	if #matches > 1 then return nil, `more than one player matches "{name}"` end
	return nil, `no player matches "{name}"`
end

local function run(caller: Player, argument: string?)
	local effect: string? = nil
	local playerTokens = {}

	for _, token in split(argument) do
		local normalized = EFFECTS[token:lower()]
		if normalized then
			if effect then
				warn("[oddity] choose only one effect: size, headsize, transparency, or stare")
				return
			end
			effect = normalized
		else
			table.insert(playerTokens, token)
		end
	end

	local target = caller
	local playerName = if #playerTokens > 0 then table.concat(playerTokens, " ") else nil
	if playerName then
		local found, reason = findPlayer(playerName, caller)
		if not found then
			warn(`[oddity] {reason}`)
			return
		end
		target = found
	end

	local ok, chosen, reason = PlayerOddityService:Trigger(target, effect)
	if not ok then
		warn(`[oddity] {reason}`)
		return
	end
	warn(`[oddity] applied {chosen} to {target.Name}`)
end

ChatCommandService.Register("oddity", {
	Handler = function(player: Player, argument: string?)
		run(player, argument)
	end,
})

return PlayerOddityCommandService
