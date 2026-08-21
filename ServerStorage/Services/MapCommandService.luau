local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local ElevatorService = require(ServerStorage.Services.ElevatorService)

local MapCommandService = {}

local ALLOWED_USER_IDS = {
	[265199502] = true,
	[1936118388] = true,
}

function MapCommandService:Execute(player: Player): boolean
	if not RunService:IsStudio() and not ALLOWED_USER_IDS[player.UserId] then
		warn(`[map] {player.Name} ({player.UserId}) is not allowed to use /map`)
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		warn(`[map] {player.Name} has no living character to send anywhere`)
		return false
	end

	local started = os.clock()
	if not ElevatorService:SendToMap(player, true) then
		warn(`[map] could not send {player.Name} into the map`)
		return false
	end

	warn(`[map] {player.Name} -> map spawn in {string.format("%.1f", os.clock() - started)}s`)
	return true
end

local function watch(player: Player)
	player.Chatted:Connect(function(message: string)
		local command = message:match("^/(%S+)%s*$")
		if not command or command:lower() ~= "map" then return end
		task.spawn(function()
			MapCommandService:Execute(player)
		end)
	end)
end

Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return MapCommandService
