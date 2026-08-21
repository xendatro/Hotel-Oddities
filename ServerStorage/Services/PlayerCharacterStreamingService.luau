local Players = game:GetService("Players")

local PlayerCharacterStreamingService = {}

local function setPersistent(character: Model)
	character.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(setPersistent)
	if player.Character then
		setPersistent(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

Players.PlayerAdded:Connect(watchPlayer)

return PlayerCharacterStreamingService
