local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Settings = require(script.Parent.Parent.Config.Settings)
local Environment = {}

function Environment.Read(options)
	local result = {
		placeId = game.PlaceId, placeVersion = game.PlaceVersion, engine = version(),
		studio = RunService:IsStudio(), streaming = workspace.StreamingEnabled,
		players = #Players:GetPlayers(), packageVersion = Settings.PackageVersion,
		build = options.build, device = options.device, graphics = "unknown", viewport = "server",
		frameCap = options.frameCap or "unknown", powerState = options.powerState or "unknown",
	}
	if RunService:IsClient() then
		local camera = workspace.CurrentCamera
		if camera then result.viewport = tostring(camera.ViewportSize) end
		local ok, quality = pcall(function() return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Name end)
		if ok then result.graphics = quality end
	end
	return result
end

return Environment
