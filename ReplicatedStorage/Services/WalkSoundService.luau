local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WalkSoundService = {}

if not RunService:IsClient() then
	return WalkSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)

type CharacterState = {
	Connection: RBXScriptConnection,
	Player: AudioPlayer,
}

local characterStates: {[Model]: CharacterState} = {}

local function stopCharacter(character: Model)
	local state = characterStates[character]
	if not state then return end

	state.Connection:Disconnect()
	AudioService:StopSound(state.Player)
	characterStates[character] = nil
end

local function watchCharacter(player: Player, character: Model)
	stopCharacter(character)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	if player.Character ~= character or character.Parent == nil then return end

	-- Roblox's own footsteps, an AudioPlayer since character sounds moved to the new audio API.
	local defaultWalkSound = rootPart:WaitForChild("Running") :: AudioPlayer
	defaultWalkSound.Volume = 0

	local player = AudioService:Create3DSound("Walk", rootPart, true, "SFX")

	local function update(speed: number)
		if speed > 0 then
			if not player.IsPlaying then
				player:Play()
			end
		else
			player:Stop()
		end
	end

	local connection = humanoid.Running:Connect(update)
	characterStates[character] = {
		Connection = connection,
		Player = player,
	}
	update(humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(stopCharacter)

	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

Players.PlayerAdded:Connect(watchPlayer)

return WalkSoundService
