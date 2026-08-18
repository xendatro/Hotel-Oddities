local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)

local Communication = ReplicatedStorage.Communication.WalkieTalkie
local SetMode = Communication.SetMode :: RemoteEvent
local TransmitSound = Communication.TransmitSound :: RemoteEvent

local WalkieTalkieService = {}

type State = {
	Player: Player,
	Tool: Tool,
	Audio: Folder,
	Emitter: AudioEmitter,
	Compressor: AudioCompressor,
	Bandpass: AudioFilter,
	Equalizer: AudioEqualizer,
	Distortion: AudioDistortion,
	Limiter: AudioLimiter,
	Mixer: AudioChannelMixer,
	ActiveFader: AudioFader,
	DeathFader: AudioFader,
	ActivePlayer: AudioPlayer?,
	Source: AudioDeviceInput?,
	SourceWire: Wire?,
	OutputWires: { [Player]: { Output: AudioDeviceOutput, Wire: Wire } },
	AmbientWires: { [AudioEmitter]: Wire },
	DeathWires: { [AudioPlayer]: Wire },
	Connections: { RBXScriptConnection },
	LastActiveAt: number,
}

type RelayBucket = { StartedAt: number, Count: number }

local States: { [Player]: State } = {}
local Modes: { [Player]: string } = {}
local FriendCache: { [string]: boolean } = {}
local AmbientSources: { [AudioEmitter]: AudioPlayer } = {}
local RelayBuckets: { [Player]: RelayBucket } = {}
local RebuildQueued = false
local ensureOutputs: (state: State) -> ()

local function voiceEligible(player: Player): boolean
	local success, enabled = pcall(
		VoiceChatService.IsVoiceEnabledForUserIdAsync,
		VoiceChatService,
		player.UserId
	)
	return success and enabled == true
end

local function cacheKey(a: Player, b: Player): string
	return `{a.UserId}:{b.UserId}`
end

local function areFriends(a: Player, b: Player): boolean
	if a == b then return true end
	local key = cacheKey(a, b)
	if FriendCache[key] ~= nil then return FriendCache[key] end

	local success, result = pcall(a.IsFriendsWith, a, b.UserId)
	local friends = success and result == true
	FriendCache[key] = friends
	FriendCache[cacheKey(b, a)] = friends
	return friends
end

local function allows(sender: Player, receiver: Player): boolean
	if (Modes[sender] or "All") ~= "Friends" then return true end
	return areFriends(sender, receiver)
end

local function getWorldPosition(instance: Instance): Vector3?
	local parent = instance.Parent
	if not parent then return nil end
	if parent:IsA("BasePart") then return parent.Position end
	if parent:IsA("Attachment") then return parent.WorldPosition end
	if parent:IsA("PVInstance") then return parent:GetPivot().Position end
	return nil
end

local function getPlayerPosition(player: Player): Vector3?
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position end
	return character:GetPivot().Position
end

local function cloneSoundPlayer(name: string, parent: Instance): AudioPlayer?
	local template = ReplicatedStorage.Sounds:FindFirstChild(name)
	local source = template and template:FindFirstChild("Player")
	if not source or not source:IsA("AudioPlayer") then return nil end

	local player = source:Clone()
	player.Name = name
	player.Parent = parent
	return player
end

local function findRadioSoundTemplate(name: string): AudioPlayer?
	for _, instance in ReplicatedStorage.Sounds:GetDescendants() do
		if instance:IsA("AudioEmitter") and instance.Name == name and instance:HasTag(Config.RadioAllowedTag) then
			local player = instance:FindFirstChild("Player")
			if player and player:IsA("AudioPlayer") then return player end
		elseif instance:IsA("AudioPlayer") and instance.Name == name and instance:HasTag(Config.RadioAllowedTag) then
			return instance
		end
	end
	return nil
end

local function connect(source: Instance, target: Instance, parent: Instance, sourceName: string?, targetName: string?): Wire
	local wire = Instance.new("Wire")
	wire.Name = `{source.Name}To{target.Name}`
	wire.SourceInstance = source
	wire.TargetInstance = target
	if sourceName then wire.SourceName = sourceName end
	if targetName then wire.TargetName = targetName end
	wire.Parent = parent
	return wire
end

local function createEffect(className: string, name: string, parent: Instance): Instance
	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = parent
	return effect
end

local function updateSpeaking(state: State, active: boolean)
	if active then
		state.LastActiveAt = os.clock()
	end
	if not state.ActivePlayer then return end
	if active then
		if not state.ActivePlayer.IsPlaying then state.ActivePlayer:Play() end
	elseif state.ActivePlayer.IsPlaying then
		state.ActivePlayer:Stop()
	end
end

local function disconnectAmbient(state: State, emitter: AudioEmitter)
	local wire = state.AmbientWires[emitter]
	if not wire then return end
	wire:Destroy()
	state.AmbientWires[emitter] = nil
end

local function connectAmbient(state: State, emitter: AudioEmitter, source: AudioPlayer)
	if state.AmbientWires[emitter] then return end
	state.AmbientWires[emitter] = connect(source, state.Compressor, state.Audio)
end

local function refreshAmbientSources()
	for emitter, source in AmbientSources do
		local owner: State? = nil
		local closestDistance = math.huge
		local emitterPosition = getWorldPosition(emitter)
		if emitterPosition then
			for _, state in States do
				local playerPosition = getPlayerPosition(state.Player)
				if playerPosition then
					local distance = (playerPosition - emitterPosition).Magnitude
					if distance <= Config.AmbientRange and distance < closestDistance then
						owner = state
						closestDistance = distance
					end
				end
			end
		end

		for _, state in States do
			if state == owner then
				connectAmbient(state, emitter, source)
			else
				disconnectAmbient(state, emitter)
			end
		end
	end
end

local function playDeathBurst(state: State)
	if not state.Audio.Parent then return end
	local player = cloneSoundPlayer("RadioDeath", state.Audio)
	if not player then return end
	player.Looping = false
	local wire = connect(player, state.DeathFader, state.Audio, nil, "Center")
	state.DeathWires[player] = wire
	player.Ended:Once(function()
		local current = state.DeathWires[player]
		if current then
			current:Destroy()
			state.DeathWires[player] = nil
		end
		if player.Parent then player:Destroy() end
	end)
	player:Play()
end

local function relayBucketAllows(player: Player): boolean
	local now = os.clock()
	local bucket = RelayBuckets[player]
	if not bucket or now - bucket.StartedAt >= 1 then
		RelayBuckets[player] = { StartedAt = now, Count = 1 }
		return true
	end
	if bucket.Count >= 8 then return false end
	bucket.Count += 1
	return true
end

function WalkieTalkieService:RegisterAmbientEmitter(emitter: AudioEmitter)
	if not emitter:IsDescendantOf(workspace) then return end
	if AmbientSources[emitter] then return end
	local source = emitter:FindFirstChild("Player")
	if not source or not source:IsA("AudioPlayer") then return end

	AmbientSources[emitter] = source
	emitter.Destroying:Once(function()
		AmbientSources[emitter] = nil
		for _, state in States do
			disconnectAmbient(state, emitter)
		end
	end)
	refreshAmbientSources()
end

function WalkieTalkieService:TransmitSound(player: Player, name: string)
	local state = States[player]
	if not state or not relayBucketAllows(player) then return end

	local template = findRadioSoundTemplate(name)
	if not template then return end
	local source = template:Clone()
	source.Name = `RadioSound_{name}`
	source.Looping = false
	source.Parent = state.Audio
	local wire = connect(source, state.Compressor, state.Audio)
	source.Ended:Once(function()
		if wire.Parent then wire:Destroy() end
		if source.Parent then source:Destroy() end
	end)
	source:Play()
end

local function queueRebuild()
	if RebuildQueued then return end
	RebuildQueued = true
	task.defer(function()
		RebuildQueued = false
		for _, state in States do
			ensureOutputs(state)
		end
	end)
end

ensureOutputs = function(state: State)
	for receiver in States do
		local wanted = receiver ~= state.Player and allows(state.Player, receiver) and allows(receiver, state.Player)
		local existing = state.OutputWires[receiver]
		if not wanted then
			if existing then
				existing.Wire:Destroy()
				existing.Output:Destroy()
				state.OutputWires[receiver] = nil
			end
			continue
		end
		if existing then continue end

		local output = Instance.new("AudioDeviceOutput")
		output.Name = `RadioOutput_{receiver.UserId}`
		output.Player = receiver
		output.Parent = state.Tool

		local wire = connect(state.Mixer, output, state.Tool)
		state.OutputWires[receiver] = { Output = output, Wire = wire }
	end

	for receiver, route in state.OutputWires do
		if States[receiver] then continue end
		route.Wire:Destroy()
		route.Output:Destroy()
		state.OutputWires[receiver] = nil
	end
end

local function connectSource(state: State)
	local source = state.Player:FindFirstChild("AudioDeviceInput")
	if not source or not source:IsA("AudioDeviceInput") then return end
	if state.Source == source and state.SourceWire then return end
	if state.SourceWire then state.SourceWire:Destroy() end

	state.Source = source
	state.SourceWire = connect(source, state.Compressor, state.Tool)
	table.insert(state.Connections, source:GetPropertyChangedSignal("Active"):Connect(function()
		updateSpeaking(state, source.Active and not source.Muted)
	end))
	table.insert(state.Connections, source:GetPropertyChangedSignal("Muted"):Connect(function()
		updateSpeaking(state, source.Active and not source.Muted)
	end))
	updateSpeaking(state, source.Active and not source.Muted)
	queueRebuild()
end

local function teardown(state: State)
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	for _, route in state.OutputWires do
		route.Wire:Destroy()
		route.Output:Destroy()
	end
	for emitter in state.AmbientWires do
		disconnectAmbient(state, emitter)
	end
	for player, wire in state.DeathWires do
		wire:Destroy()
		if player.Parent then player:Destroy() end
		state.DeathWires[player] = nil
	end
	if state.ActivePlayer and state.ActivePlayer.IsPlaying then state.ActivePlayer:Stop() end
	if state.Emitter.Parent then state.Emitter:Destroy() end
	if state.Audio.Parent then state.Audio:Destroy() end
end

function WalkieTalkieService:SetMode(player: Player, mode: string)
	if mode ~= "All" and mode ~= "Friends" then return end
	Modes[player] = mode
	player:SetAttribute("WalkieTalkieMode", mode)
	queueRebuild()
end

function WalkieTalkieService:Equip(player: Player, tool: Tool)
	if States[player] then
		teardown(States[player])
		States[player] = nil
	end
	if not voiceEligible(player) then return end

	local audio = Instance.new("Folder")
	audio.Name = "RadioAudio"
	audio.Parent = tool

	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		audio:Destroy()
		return
	end

	local compressor = createEffect("AudioCompressor", "Compressor", audio) :: AudioCompressor
	compressor.Threshold = Config.Effects.Compressor.Threshold
	compressor.Ratio = Config.Effects.Compressor.Ratio
	compressor.Attack = Config.Effects.Compressor.Attack
	compressor.Release = Config.Effects.Compressor.Release
	compressor.MakeupGain = Config.Effects.Compressor.MakeupGain

	local bandpass = createEffect("AudioFilter", "RadioBandpass", audio) :: AudioFilter
	bandpass.FilterType = Enum.AudioFilterType.Bandpass
	bandpass.Frequency = Config.Effects.Bandpass.Frequency
	bandpass.Q = Config.Effects.Bandpass.Q

	local equalizer = createEffect("AudioEqualizer", "RadioTone", audio) :: AudioEqualizer
	equalizer.LowGain = Config.Effects.Equalizer.LowGain
	equalizer.MidGain = Config.Effects.Equalizer.MidGain
	equalizer.HighGain = Config.Effects.Equalizer.HighGain

	local distortion = createEffect("AudioDistortion", "RadioStatic", audio) :: AudioDistortion
	distortion.Level = Config.Effects.DistortionLevel

	local limiter = createEffect("AudioLimiter", "RadioLimiter", audio) :: AudioLimiter
	limiter.MaxLevel = Config.Effects.Limiter.MaxLevel
	limiter.Release = Config.Effects.Limiter.Release

	local mixer = createEffect("AudioChannelMixer", "RadioMix", audio) :: AudioChannelMixer
	mixer.Layout = Enum.AudioChannelLayout.Mono
	local activeFader = createEffect("AudioFader", "RadioActiveVolume", audio) :: AudioFader
	activeFader.Volume = Config.Effects.Static.ActiveVolume
	local deathFader = createEffect("AudioFader", "RadioDeathVolume", audio) :: AudioFader
	deathFader.Volume = Config.Effects.Static.DeathVolume
	local activePlayer = cloneSoundPlayer("RadioActive", audio)
	if activePlayer then
		activePlayer.Looping = true
		connect(activePlayer, activeFader, audio)
	end

	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "RadioEmitter"
	-- Keep the default listener group so the handheld radio can be heard in the world.
	emitter.AudioInteractionGroup = ""
	emitter.AcousticSimulationEnabled = true
	emitter.OcclusionEnabled = Enum.SimulationMode.Enabled
	emitter:SetDistanceAttenuation({
		[0] = 1,
		[Config.PhysicalRange * 0.8] = 0.65,
		[Config.PhysicalRange] = 0,
	})
	emitter.Parent = handle

	connect(compressor, bandpass, audio)
	connect(bandpass, equalizer, audio)
	connect(equalizer, distortion, audio)
	connect(distortion, limiter, audio)
	connect(limiter, mixer, audio, nil, "Input")
	connect(activeFader, mixer, audio, nil, "Center")
	connect(deathFader, mixer, audio, nil, "Center")
	connect(mixer, emitter, audio)

	local state: State = {
		Player = player,
		Tool = tool,
		Audio = audio,
		Emitter = emitter,
		Compressor = compressor,
		Bandpass = bandpass,
		Equalizer = equalizer,
		Distortion = distortion,
		Limiter = limiter,
		Mixer = mixer,
		ActiveFader = activeFader,
		DeathFader = deathFader,
		ActivePlayer = activePlayer,
		Source = nil,
		SourceWire = nil,
		OutputWires = {},
		AmbientWires = {},
		DeathWires = {},
		Connections = {},
		LastActiveAt = -math.huge,
	}
	States[player] = state
	Modes[player] = Modes[player] or "All"
	player:SetAttribute("WalkieTalkieMode", Modes[player])
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(state.Connections, humanoid.Died:Connect(function()
			local activelySpeaking = state.Source ~= nil and state.Source.Active and not state.Source.Muted
			if activelySpeaking or os.clock() - state.LastActiveAt <= Config.DeathActiveGrace then
				playDeathBurst(state)
			end
		end))
	end

	table.insert(state.Connections, player.ChildAdded:Connect(function(child)
		if child.Name == "AudioDeviceInput" then
			connectSource(state)
			ensureOutputs(state)
			queueRebuild()
		end
	end))
	table.insert(state.Connections, player.ChildRemoved:Connect(function(child)
		if child == state.Source then
			if state.SourceWire then state.SourceWire:Destroy() end
			state.SourceWire = nil
			state.Source = nil
			queueRebuild()
		end
	end))
	connectSource(state)
	for _, other in States do
		ensureOutputs(other)
	end
	refreshAmbientSources()
	queueRebuild()
end

function WalkieTalkieService:Unequip(player: Player, tool: Tool)
	local state = States[player]
	if not state or state.Tool ~= tool then return end
	teardown(state)
	States[player] = nil
	for _, other in States do
		ensureOutputs(other)
	end
	refreshAmbientSources()
	queueRebuild()
end

SetMode.OnServerEvent:Connect(function(player: Player, mode: any)
	if type(mode) == "string" then WalkieTalkieService:SetMode(player, mode) end
end)

TransmitSound.OnServerEvent:Connect(function(player: Player, name: any)
	if type(name) == "string" then WalkieTalkieService:TransmitSound(player, name) end
end)

CollectionService:GetInstanceAddedSignal(Config.RadioAllowedTag):Connect(function(instance)
	if instance:IsA("AudioEmitter") then WalkieTalkieService:RegisterAmbientEmitter(instance) end
end)

for _, instance in CollectionService:GetTagged(Config.RadioAllowedTag) do
	if instance:IsA("AudioEmitter") then WalkieTalkieService:RegisterAmbientEmitter(instance) end
end

local ambientAccumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	ambientAccumulator += deltaTime
	if ambientAccumulator < 0.2 then return end
	ambientAccumulator = 0
	refreshAmbientSources()
end)

Players.PlayerAdded:Connect(function(player)
	Modes[player] = "All"
	player:SetAttribute("WalkieTalkieMode", "All")
	player.ChildAdded:Connect(function(child)
		if child.Name == "AudioDeviceInput" then queueRebuild() end
	end)
	queueRebuild()
end)

Players.PlayerRemoving:Connect(function(player)
	local state = States[player]
	if state then teardown(state) end
	States[player] = nil
	Modes[player] = nil
	RelayBuckets[player] = nil
	for key in FriendCache do
		if string.find(key, tostring(player.UserId), 1, true) then FriendCache[key] = nil end
	end
	for _, other in States do
		ensureOutputs(other)
	end
	refreshAmbientSources()
	queueRebuild()
end)

for _, player in Players:GetPlayers() do
	Modes[player] = "All"
	player:SetAttribute("WalkieTalkieMode", "All")
	player.ChildAdded:Connect(function(child)
		if child.Name == "AudioDeviceInput" then queueRebuild() end
	end)
end

return WalkieTalkieService
