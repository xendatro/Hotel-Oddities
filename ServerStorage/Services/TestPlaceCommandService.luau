local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local TEST_PLACE_ID = 100831632531280

local TestPlaceCommandService = {}

function TestPlaceCommandService:Execute(player: Player): boolean
	if RunService:IsStudio() then
		warn(`[test] teleports do not work in Studio; publish and join the live game to use /test`)
		return false
	end

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = false

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(TEST_PLACE_ID, { player }, options)
	end)
	if not ok then
		warn(`[test] could not teleport {player.Name} to {TEST_PLACE_ID}: {err}`)
		return false
	end

	warn(`[test] {player.Name} -> place {TEST_PLACE_ID}`)
	return true
end

ChatCommandService.Register("test", {
	AdminOnly = true,
	Handler = function(player: Player, argument: string?)
		if argument ~= nil then return end
		task.spawn(function()
			TestPlaceCommandService:Execute(player)
		end)
	end,
})

return TestPlaceCommandService
