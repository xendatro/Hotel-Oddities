local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local ChatCommandService = require(ServerStorage.Services.ChatCommandService)

local DEFAULT_ZOOM = 0.5
local MAX_ZOOM = 128

local CameraCommandService = {}

local function setZoom(player: Player, distance: number)
	player.CameraMaxZoomDistance = distance
	warn(`[camera] {player.Name} max zoom is now {distance}`)
end

local function initialize(player: Player)
	player.CameraMaxZoomDistance = DEFAULT_ZOOM
end

ChatCommandService.Register("camera", {
	Aliases = { "cam" },
	Handler = function(player: Player)
		local distance = if player.CameraMaxZoomDistance == DEFAULT_ZOOM then MAX_ZOOM else DEFAULT_ZOOM
		setZoom(player, distance)
	end,
})

Players.PlayerAdded:Connect(initialize)
for _, player in Players:GetPlayers() do
	initialize(player)
end

return CameraCommandService
