local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WalkSoundService = {}

if not RunService:IsClient() then
	return WalkSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local WalkSoundConfig = require(ReplicatedStorage.Configs.WalkSoundConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local ENEMY_TAG = "Enemy"
local DEFAULT_WALK_SPEED = 16
local DEFAULT_ANIMATION_CYCLE_TIME = 1
local STEPS_PER_ANIMATION_CYCLE = 2
local DEFAULT_STEP_INTERVAL = DEFAULT_ANIMATION_CYCLE_TIME / STEPS_PER_ANIMATION_CYCLE
local ENEMY_MAX_DISTANCE = 45
local MOVEMENT_THRESHOLD = 0.05
local ENEMY_WALK_ATTENUATION = {
	[0] = 1,
	[10] = 1,
	[25] = 0.85,
	[40] = 0.55,
	[ENEMY_MAX_DISTANCE] = 0,
}

type CharacterState = {
	Connections: { RBXScriptConnection },
}

local FootstepTemplates: { AudioEmitter } = {}
for _, child in ReplicatedStorage.Sounds.Footsteps:GetChildren() do
	if child:IsA("AudioEmitter") then
		table.insert(FootstepTemplates, child)
	end
end

local CharacterStates: {[Model]: CharacterState} = {}

local function getStepInterval(humanoid: Humanoid, speed: number): number
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local locomotionTrack: AnimationTrack? = nil
	local highestWeight = 0
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			if track.IsPlaying
				and track.Looped
				and track.Priority == Enum.AnimationPriority.Core
				and track.WeightCurrent > highestWeight
			then
				locomotionTrack = track
				highestWeight = track.WeightCurrent
			end
		end
	end

	if locomotionTrack and locomotionTrack.Length > 0 and locomotionTrack.Speed > 0 then
		return locomotionTrack.Length / locomotionTrack.Speed / STEPS_PER_ANIMATION_CYCLE
	end
	return DEFAULT_STEP_INTERVAL * DEFAULT_WALK_SPEED / speed
end

local function configureEnemyAttenuation(audioPlayer: AudioPlayer)
	local emitter = audioPlayer.Parent :: AudioEmitter
	emitter.DistanceAttenuationBounds = NumberRange.new(0, ENEMY_MAX_DISTANCE)
	emitter.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Custom
	emitter:SetDistanceAttenuation(ENEMY_WALK_ATTENUATION)
end

local function stopModel(model: Model, state: CharacterState?)
	state = state or CharacterStates[model]
	if not state then return end

	for _, connection in state.Connections do
		connection:Disconnect()
	end
	CharacterStates[model] = nil
end

local function watchModel(
	model: Model,
	humanoid: Humanoid,
	rootPart: BasePart,
	silenceDefault: boolean,
	audioSettings: {[string]: any}?,
	trackRootMovement: boolean
): CharacterState
	stopModel(model)

	if silenceDefault then
		-- Roblox's own footsteps, an AudioPlayer since character sounds moved to the new audio API.
		local defaultWalkSound = rootPart:WaitForChild("Running") :: AudioPlayer
		defaultWalkSound.Volume = 0
	else
		local defaultWalkSound = rootPart:FindFirstChild("Running")
		if defaultWalkSound and defaultWalkSound:IsA("AudioPlayer") then
			defaultWalkSound.Volume = 0
		end
	end

	local isMoving = false
	local currentSpeed = 0
	local timeUntilStep = 0
	local stepInterval = DEFAULT_STEP_INTERVAL

	local function playFootstep()
		local template = FootstepTemplates[math.random(#FootstepTemplates)]
		local audioPlayer = AudioService:Play3DSound(template, rootPart, false, "SFX", audioSettings)
		if trackRootMovement then
			configureEnemyAttenuation(audioPlayer)
		end
	end

	local function update(speed: number)
		if speed > MOVEMENT_THRESHOLD then
			if not isMoving then
				timeUntilStep = 0
			end
			isMoving = true
			currentSpeed = speed
		else
			isMoving = false
			currentSpeed = 0
			timeUntilStep = 0
		end
	end

	local lastPosition = rootPart.Position
	local connections = {
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			update(humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed)
		end),
		RunService.Heartbeat:Connect(function(deltaTime)
			if trackRootMovement then
				local position = rootPart.Position
				local speed = (position - lastPosition).Magnitude / deltaTime
				lastPosition = position
				update(if speed > MOVEMENT_THRESHOLD then humanoid.WalkSpeed else 0)
			end

			if not isMoving then return end
			local frequencyMultiplier = if trackRootMovement then 1 else WalkSoundConfig.PlayerStepFrequencyMultiplier
			local newStepInterval = getStepInterval(humanoid, currentSpeed) / frequencyMultiplier
			if math.abs(newStepInterval - stepInterval) > 0.001 then
				if timeUntilStep > 0 then
					timeUntilStep *= newStepInterval / stepInterval
				end
				stepInterval = newStepInterval
			end
			timeUntilStep -= deltaTime
			if timeUntilStep > 0 then return end

			playFootstep()
			timeUntilStep = stepInterval
		end),
	}
	if not trackRootMovement then
		table.insert(connections, humanoid.Running:Connect(update))
	end
	local state = {
		Connections = connections,
	}
	CharacterStates[model] = state
	update(humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed)
	return state
end

local function watchCharacter(player: Player, character: Model)
	stopModel(character)

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local rootPart = character:WaitForChild("HumanoidRootPart") :: BasePart
	if player.Character ~= character or character.Parent == nil then return end

	watchModel(character, humanoid, rootPart, true, nil, false)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	player.CharacterRemoving:Connect(function(character)
		stopModel(character)
	end)

	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
end

local function watchEnemy(instance: Instance): CharacterState?
	if not instance:IsA("Model") then return nil end

	-- The Enemy tag can replicate before the model's rig descendants do. Wait at this replication
	-- boundary so a tagged patrol is not missed just because its Humanoid arrived one packet later.
	local humanoid = instance:WaitForChild("Humanoid", 5) :: Humanoid?
	local rootPart = instance:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not humanoid or not rootPart or not humanoid.EvaluateStateMachine then return nil end

	return watchModel(instance, humanoid, rootPart, false, {
		DistanceAttenuationBounds = NumberRange.new(0, ENEMY_MAX_DISTANCE),
		DistanceAttenuationMode = Enum.DistanceAttenuationMode.Custom,
	}, true)
end

local function unwatchEnemy(instance: Instance, state: CharacterState?)
	if instance:IsA("Model") then
		stopModel(instance, state)
	end
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

Players.PlayerAdded:Connect(watchPlayer)
TagService:Listen(ENEMY_TAG, watchEnemy, unwatchEnemy)

return WalkSoundService
