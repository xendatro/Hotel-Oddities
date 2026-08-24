local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DeathScreenService = require(ReplicatedStorage.Services.DeathScreenService)

local RecordPlayerAudioService = {}

if not RunService:IsClient() then
	return RecordPlayerAudioService
end

local RECORD_TAG = "RecordPlayer"
local LOADING_MUFFLE_TIME = 2.5
local LOADING_VOLUME_FADE_TIME = 3
local LOADING_RESTORE_TIME = 1
local LOADING_MID_GAIN = -10
local LOADING_HIGH_GAIN = -30
local DEATH_VOLUME_FADE_TIME = 1
local DEATH_MUFFLE_FADE_TIME = 1

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local Loading = CommunicationService.Get("Elevator", "Loading") :: RemoteEvent

type RecordState = {
	Emitter: AudioEmitter,
	Player: AudioPlayer,
	TerminalWire: Wire,
	Muffle: AudioEqualizer,
	OutputWire: Wire,
	BaseVolume: number,
	VolumeAlpha: number,
	MuffleAlpha: number,
}

type TrackedModel = {
	Emitters: { [AudioEmitter]: boolean },
	Added: RBXScriptConnection,
	Removing: RBXScriptConnection,
}

local states: { [AudioEmitter]: RecordState } = {}
local trackedModels: { [Instance]: TrackedModel } = {}
local activeToken: number? = nil
local loading = false
local loadingStartedAt: number? = nil
local deathActive = false
local deathRecoveryStartedAt: number? = nil
local deathEndedAt: number? = nil

local function restoreState(state: RecordState)
	if state.Emitter.Parent == nil then
		states[state.Emitter] = nil
		return
	end

	state.Player.Volume = state.BaseVolume
	state.TerminalWire.TargetInstance = state.Emitter
	state.OutputWire:Destroy()
	state.Muffle:Destroy()
	states[state.Emitter] = nil
end

local function approach(value: number, target: number, deltaTime: number, duration: number): number
	local step = deltaTime / duration
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function updateState(state: RecordState, deltaTime: number)
	if deathActive then
		if deathRecoveryStartedAt then
			state.VolumeAlpha = math.clamp(
				1 - (os.clock() - deathRecoveryStartedAt) / DEATH_VOLUME_FADE_TIME,
				0,
				1
			)
		else
			state.VolumeAlpha = 1
		end

		if deathEndedAt then
			state.MuffleAlpha = math.clamp(
				1 - (os.clock() - deathEndedAt) / DEATH_MUFFLE_FADE_TIME,
				0,
				1
			)
		else
			state.MuffleAlpha = 1
		end
	elseif loading and loadingStartedAt then
		local elapsed = os.clock() - loadingStartedAt
		state.MuffleAlpha = math.clamp(elapsed / LOADING_MUFFLE_TIME, 0, 1)
		state.VolumeAlpha = math.clamp(
			(elapsed - LOADING_MUFFLE_TIME) / LOADING_VOLUME_FADE_TIME,
			0,
			1
		)
	else
		state.VolumeAlpha = approach(state.VolumeAlpha, 0, deltaTime, LOADING_RESTORE_TIME)
		state.MuffleAlpha = approach(state.MuffleAlpha, 0, deltaTime, LOADING_RESTORE_TIME)
	end

	state.Player.Volume = state.BaseVolume * (1 - state.VolumeAlpha)
	state.Muffle.MidGain = LOADING_MID_GAIN * state.MuffleAlpha
	state.Muffle.HighGain = LOADING_HIGH_GAIN * state.MuffleAlpha

	if not loading and not deathActive and state.VolumeAlpha <= 0 and state.MuffleAlpha <= 0 then
		restoreState(state)
	end
end

local function updateDeathState(now: number)
	local visible = DeathScreenService:IsVisible()

	if visible then
		if not deathActive then
			deathActive = true
			deathRecoveryStartedAt = nil
			deathEndedAt = nil
		end

		local timeUntilEnd = DeathScreenService:GetTimeUntilEnd()
		if timeUntilEnd and timeUntilEnd <= DEATH_VOLUME_FADE_TIME and not deathRecoveryStartedAt then
			deathRecoveryStartedAt = now - math.max(DEATH_VOLUME_FADE_TIME - timeUntilEnd, 0)
		end
	elseif deathActive then
		if not deathEndedAt then
			deathEndedAt = now
		elseif now - deathEndedAt >= DEATH_MUFFLE_FADE_TIME then
			deathActive = false
			deathRecoveryStartedAt = nil
			deathEndedAt = nil
		end
	end
end

local function findTerminalWire(emitter: AudioEmitter): Wire?
	for _, descendant in emitter:GetDescendants() do
		if descendant:IsA("Wire") and descendant.TargetInstance == emitter then
			return descendant
		end
	end
	return nil
end

local function createState(emitter: AudioEmitter): RecordState?
	local player = emitter:FindFirstChild("Player")
	local terminalWire = findTerminalWire(emitter)
	if not player or not player:IsA("AudioPlayer") or not terminalWire then return nil end

	local muffle = Instance.new("AudioEqualizer")
	muffle.Name = "LoadingMuffle"
	muffle.LowGain = 0
	muffle.MidGain = 0
	muffle.HighGain = 0
	muffle.Parent = emitter

	terminalWire.TargetInstance = muffle

	local outputWire = Instance.new("Wire")
	outputWire.Name = "LoadingMuffleWire"
	outputWire.SourceInstance = muffle
	outputWire.TargetInstance = emitter
	outputWire.Parent = muffle

	local state: RecordState = {
		Emitter = emitter,
		Player = player,
		TerminalWire = terminalWire,
		Muffle = muffle,
		OutputWire = outputWire,
		BaseVolume = player.Volume,
		VolumeAlpha = 0,
		MuffleAlpha = 0,
	}
	states[emitter] = state
	emitter.Destroying:Once(function()
		states[emitter] = nil
	end)
	return state
end

local function trackModel(model: Instance)
	if trackedModels[model] then return end

	local emitters: { [AudioEmitter]: boolean } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("AudioEmitter") then
			emitters[descendant] = true
		end
	end

	trackedModels[model] = {
		Emitters = emitters,
		Added = model.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("AudioEmitter") then
				emitters[descendant] = true
			end
		end),
		Removing = model.DescendantRemoving:Connect(function(descendant)
			if descendant:IsA("AudioEmitter") then
				emitters[descendant] = nil
			end
		end),
	}
end

local function untrackModel(model: Instance)
	local entry = trackedModels[model]
	if not entry then return end
	entry.Added:Disconnect()
	entry.Removing:Disconnect()
	trackedModels[model] = nil
end

CollectionService:GetInstanceAddedSignal(RECORD_TAG):Connect(trackModel)
CollectionService:GetInstanceRemovedSignal(RECORD_TAG):Connect(untrackModel)
for _, model in CollectionService:GetTagged(RECORD_TAG) do
	trackModel(model)
end

local function refresh(deltaTime: number)
	if loading or deathActive then
		for model, entry in trackedModels do
			if not model:IsDescendantOf(workspace) then continue end

			for emitter in entry.Emitters do
				if not states[emitter] and emitter.Parent then
					createState(emitter)
				end
			end
		end
	end

	for _, state in states do
		if state.Emitter.Parent then
			updateState(state, deltaTime)
		else
			states[state.Emitter] = nil
		end
	end
end

function RecordPlayerAudioService:SetLoading(value: boolean, token: number)
	if value then
		if activeToken == token and loading then
			refresh(0)
			return
		end

		activeToken = token
		loading = true
		loadingStartedAt = os.clock()
		refresh(0)
		return
	end

	if activeToken ~= token then return end
	activeToken = nil
	loading = false
	loadingStartedAt = nil
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	local now = os.clock()
	updateDeathState(now)
	refresh(deltaTime)
end)

Loading.OnClientEvent:Connect(function(show: any, token: any)
	if typeof(token) ~= "number" then return end
	RecordPlayerAudioService:SetLoading(show == true, token)
end)

return RecordPlayerAudioService
