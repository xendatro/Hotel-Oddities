local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DeathSoundService = {}

if not RunService:IsClient() then
	return DeathSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local DIED_VOLUME = 2

local function watchCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not humanoid or not rootPart then return end
	if player.Character ~= character or character.Parent == nil then return end

	task.spawn(function()
		local defaultDiedSound = rootPart:WaitForChild("Died", 10)
		if defaultDiedSound and defaultDiedSound:IsA("AudioPlayer") then
			defaultDiedSound.Volume = 0
		end
	end)

	humanoid.Died:Once(function()
		AudioService:Play3DSound(ReplicatedStorage.Sounds.PlayerDied, rootPart, false, "SFX", {
			Volume = DIED_VOLUME,
		})
	end)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)

	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

CharacterService.ForEachPlayer(watchPlayer)

return DeathSoundService
