local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WalkSoundService = {}

if not RunService:IsClient() then
	return WalkSoundService
end

local sourceSound = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Walk") :: Sound
type CharacterState = {
	Connection: RBXScriptConnection,
	Sound: Sound,
}

local characterStates: {[Model]: CharacterState} = {}

local function stopCharacter(character: Model)
	local state = characterStates[character]
	if not state then return end

	state.Connection:Disconnect()
	state.Sound:Stop()
	state.Sound:Destroy()
	characterStates[character] = nil
end

local function watchCharacter(player: Player, character: Model)
	stopCharacter(character)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	if player.Character ~= character or character.Parent == nil then return end

	local defaultWalkSound = rootPart:WaitForChild("Running") :: Sound
	defaultWalkSound.Volume = 0

	local sound = sourceSound:Clone()
	sound.Parent = rootPart

	local function update(speed: number)
		if speed > 0 then
			if not sound.IsPlaying then
				sound:Play()
			end
		else
			sound:Stop()
		end
	end

	local connection = humanoid.Running:Connect(update)
	characterStates[character] = {
		Connection = connection,
		Sound = sound,
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
