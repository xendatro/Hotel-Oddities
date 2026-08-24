local ServerStorage = game:GetService("ServerStorage")

local ElevatorService = require(ServerStorage.Services.ElevatorService)
local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local MapCommandService = {}

function MapCommandService:Execute(player: Player): boolean
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

ChatCommandService.Register("map", {
	AdminOnly = true,
	Handler = function(player: Player, argument: string?)
		if argument ~= nil then return end
		task.spawn(function()
			MapCommandService:Execute(player)
		end)
	end,
})

return MapCommandService
