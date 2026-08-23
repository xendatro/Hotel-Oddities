local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WalkSoundService = {}

if not RunService:IsClient() then
	return WalkSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CrouchConfig = require(ReplicatedStorage.Configs.CrouchConfig)
local WalkSoundConfig = require(ReplicatedStorage.Configs.WalkSoundConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local STEALTH = CrouchConfig.Stealth

local ENEMY_TAG = "Enemy"
local DEFAULT_WALK_SPEED = 16
local DEFAULT_ANIMATION_CYCLE_TIME = 1
local STEPS_PER_ANIMATION_CYCLE = 2
local DEFAULT_STEP_INTERVAL = DEFAULT_ANIMATION_CYCLE_TIME / STEPS_PER_ANIMATION_CYCLE
local ENEMY_MAX_DISTANCE = 45
local MOVEMENT_THRESHOLD = 0.05
local TRACK_REFRESH_INTERVAL = 0.25
local ENEMY_WALK_ATTENUATION = {
	[0] = 1,
	[10] = 1,
	[25] = 0.85,
	[40] = 0.55,
	[ENEMY_MAX_DISTANCE] = 0,
}

type CharacterState = {
	Connections: { RBXScriptConnection },
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	TrackRootMovement: boolean,
	AudioSettings: { [string]: any }?,
	StepVolume: number?,
	IsMoving: boolean,
	CurrentSpeed: number,
	TimeUntilStep: number,
	StepInterval: number,
	LastPosition: Vector3,
	LocomotionTrack: AnimationTrack?,
	NextTrackRefresh: number,
}

local FootstepTemplates: { AudioEmitter } = {}
for _, child in ReplicatedStorage.Sounds.Footsteps:GetChildren() do
	if child:IsA("AudioEmitter") then
		table.insert(FootstepTemplates, child)
	end
end

local CharacterStates: {[Model]: CharacterState} = {}

local function refreshLocomotionTrack(state: CharacterState, now: number)
	local animator = state.Humanoid:FindFirstChildOfClass("Animator")
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
	state.LocomotionTrack = locomotionTrack
	state.NextTrackRefresh = now + TRACK_REFRESH_INTERVAL
end

local function getStepInterval(state: CharacterState, speed: number, now: number): number
	local locomotionTrack = state.LocomotionTrack
	if now >= state.NextTrackRefresh or not locomotionTrack or not locomotionTrack.IsPlaying then
		refreshLocomotionTrack(state, now)
		locomotionTrack = state.LocomotionTrack
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

local function isCrouching(state: CharacterState): boolean
	return state.Model:GetAttribute(STEALTH.Attribute) == true
end

local function updateMovement(state: CharacterState, speed: number)
	if speed > MOVEMENT_THRESHOLD then
		if not state.IsMoving then state.TimeUntilStep = 0 end
		state.IsMoving = true
		state.CurrentSpeed = speed
	else
		state.IsMoving = false
		state.CurrentSpeed = 0
		state.TimeUntilStep = 0
	end
end

local function playFootstep(state: CharacterState)
	local template = FootstepTemplates[math.random(#FootstepTemplates)]
	local crouching = isCrouching(state)
	local settings = if crouching
		then {
			Volume = STEALTH.StepVolume,
			PlaybackSpeed = STEALTH.StepPlaybackSpeed,
			DistanceAttenuationBounds = NumberRange.new(0, STEALTH.StepMaxDistance),
		}
		else state.AudioSettings

	if state.StepVolume and not crouching then
		local source = template:FindFirstChild("Player") :: AudioPlayer?
		settings = table.clone(settings or {})
		settings.Volume = (if source then source.Volume else 1) * state.StepVolume
	end
	local audioPlayer = AudioService:Play3DSound(template, state.RootPart, false, "SFX", settings)
	if state.TrackRootMovement then configureEnemyAttenuation(audioPlayer) end
end

local function stepState(state: CharacterState, deltaTime: number, now: number)
	if state.TrackRootMovement then
		local position = state.RootPart.Position
		local speed = (position - state.LastPosition).Magnitude / deltaTime
		state.LastPosition = position
		updateMovement(state, if speed > MOVEMENT_THRESHOLD then state.Humanoid.WalkSpeed else 0)
	end

	if not state.IsMoving then return end
	local frequencyMultiplier = if state.TrackRootMovement
		then 1
		else WalkSoundConfig.PlayerStepFrequencyMultiplier
	if isCrouching(state) then
		frequencyMultiplier *= STEALTH.StepFrequencyMultiplier
	end
	local newStepInterval = getStepInterval(state, state.CurrentSpeed, now) / frequencyMultiplier
	if math.abs(newStepInterval - state.StepInterval) > 0.001 then
		if state.TimeUntilStep > 0 then
			state.TimeUntilStep *= newStepInterval / state.StepInterval
		end
		state.StepInterval = newStepInterval
	end
	state.TimeUntilStep -= deltaTime
	if state.TimeUntilStep > 0 then return end

	playFootstep(state)
	state.TimeUntilStep = state.StepInterval
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
		local defaultWalkSound = rootPart:WaitForChild("Running") :: AudioPlayer
		defaultWalkSound.Volume = 0
	else
		local defaultWalkSound = rootPart:FindFirstChild("Running")
		if defaultWalkSound and defaultWalkSound:IsA("AudioPlayer") then
			defaultWalkSound.Volume = 0
		end
	end

	local state: CharacterState = {
		Connections = {},
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		TrackRootMovement = trackRootMovement,
		AudioSettings = audioSettings,
		StepVolume = WalkSoundConfig.EnemyStepVolume[model:GetAttribute("EnemyId")],
		IsMoving = false,
		CurrentSpeed = 0,
		TimeUntilStep = 0,
		StepInterval = DEFAULT_STEP_INTERVAL,
		LastPosition = rootPart.Position,
		LocomotionTrack = nil,
		NextTrackRefresh = 0,
	}
	state.Connections = {
		humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			updateMovement(state, humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed)
		end),
	}
	if not trackRootMovement then
		table.insert(state.Connections, humanoid.Running:Connect(function(speed)
			updateMovement(state, speed)
		end))
	end
	CharacterStates[model] = state
	updateMovement(state, humanoid.MoveDirection.Magnitude * humanoid.WalkSpeed)
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

RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()
	for _, state in CharacterStates do
		if state.Model:IsDescendantOf(workspace) and state.RootPart.Parent then
			stepState(state, deltaTime, now)
		end
	end
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

Players.PlayerAdded:Connect(watchPlayer)
TagService:Listen(ENEMY_TAG, watchEnemy, unwatchEnemy)

return WalkSoundService
