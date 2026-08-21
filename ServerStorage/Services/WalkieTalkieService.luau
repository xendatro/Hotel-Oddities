local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local VoiceActivityService = require(ServerStorage.Services.VoiceActivityService)
local NoiseService = require(ServerStorage.Services.NoiseService)

local Communication = ReplicatedStorage:WaitForChild("Communication"):WaitForChild("WalkieTalkie")

local function ensureRemote(name: string): RemoteEvent
	local existing = Communication:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = Communication
	return remote
end

local SetMode = ensureRemote("SetMode")
local TransmitSound = ensureRemote("TransmitSound")
local VoiceActivity = ensureRemote("VoiceActivity")

local WalkieTalkieService = {}

type AmbientRoute = { Fader: AudioFader, SourceWire: Wire, MixerWire: Wire }
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
	AmbientMixer: AudioChannelMixer,
	ActiveFader: AudioFader,
	RadioOutputFader: AudioFader,
	AmbientFader: AudioFader,
	ActivePlayer: AudioPlayer?,
	Source: AudioDeviceInput?,
	SourceWire: Wire?,
	OutputWires: { [Player]: { Output: AudioDeviceOutput, Wire: Wire } },
	AmbientRoutes: { [AudioEmitter]: AmbientRoute },
	Connections: { RBXScriptConnection },
	LastActiveAt: number,
	Speaking: boolean,
}

type RelayBucket = { StartedAt: number, Count: number }
type RelaySoundState = { Radio: State, Id: string, Wire: Wire, LastNoiseAt: number }

local States: { [Player]: State } = {}
local Modes: { [Player]: string } = {}
local FriendCache: { [string]: boolean } = {}
local AmbientSources: { [AudioEmitter]: AudioPlayer } = {}
local RelayBuckets: { [Player]: RelayBucket } = {}
local RelaySounds: { [AudioPlayer]: RelaySoundState } = {}
local RelayIds: { [Player]: { [string]: AudioPlayer } } = {}
local DeathConnections: { [Player]: RBXScriptConnection } = {}
local CharacterConnections: { [Player]: RBXScriptConnection } = {}
local AmbientNoiseAt: { [AudioEmitter]: number } = {}
local RadioEquippedAt: { [Player]: number } = {}
local LastRadioPosition: { [Player]: Vector3 } = {}
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

local function emitRadioNoise(state: State, source: Player?, strength: number?)
	local position = getWorldPosition(state.Emitter) or getPlayerPosition(state.Player)
	local radius = Config.RadioNoiseRadius * math.clamp(strength or 1, 0, 1)
	if position and radius > 0 then NoiseService:Emit(position, radius, source or state.Player) end
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

local function playActiveTransmission(state: State)
	local player = state.ActivePlayer
	if not player or player.IsPlaying then return end
	player.TimePosition = 0
	player:Play()
end

local function updateSpeaking(state: State, active: boolean)
	if state.Speaking == active then
		if active then
			state.LastActiveAt = os.clock()
			playActiveTransmission(state)
		end
		return
	end
	state.Speaking = active
	if active then
		state.LastActiveAt = os.clock()
		playActiveTransmission(state)
	end
end

local function disconnectAmbient(state: State, emitter: AudioEmitter)
	local route = state.AmbientRoutes[emitter]
	if not route then return end
	route.SourceWire:Destroy()
	route.MixerWire:Destroy()
	route.Fader:Destroy()
	state.AmbientRoutes[emitter] = nil
end

local function getAmbientPickupVolume(state: State, emitter: AudioEmitter): number
	local emitterPosition = getWorldPosition(emitter)
	local playerPosition = getPlayerPosition(state.Player)
	if not emitterPosition or not playerPosition then return 0 end
	local distanceAlpha = math.clamp((emitterPosition - playerPosition).Magnitude / Config.AmbientRange, 0, 1)
	return (1 - distanceAlpha) ^ Config.AmbientPickupFalloff
end

local function connectAmbient(state: State, emitter: AudioEmitter, source: AudioPlayer)
	local route = state.AmbientRoutes[emitter]
	if route then
		route.Fader.Volume = getAmbientPickupVolume(state, emitter)
		return
	end

	local fader = Instance.new("AudioFader")
	fader.Name = `AmbientPickup_{emitter.Name}`
	fader.Volume = getAmbientPickupVolume(state, emitter)
	fader.Parent = state.Audio
	state.AmbientRoutes[emitter] = {
		Fader = fader,
		SourceWire = connect(source, fader, state.Audio),
		MixerWire = connect(fader, state.AmbientMixer, state.Audio),
	}
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

local function playDeathBurst(sourcePlayer: Player)
	local state = States[sourcePlayer]
	local root = workspace:FindFirstChild("RadioDeathBursts")
	if not root then
		root = Instance.new("Folder")
		root.Name = "RadioDeathBursts"
		root.Parent = workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = `Burst_{sourcePlayer.UserId}_{math.floor(os.clock() * 1000)}`
	folder.Parent = root

	local player = cloneSoundPlayer("RadioDeath", folder)
	if not player then
		folder:Destroy()
		if root.Parent and #root:GetChildren() == 0 then root:Destroy() end
		return
	end
	local fader = Instance.new("AudioFader")
	fader.Name = "RadioDeathVolume"
	fader.Volume = Config.Effects.Static.DeathVolume * Config.RadioOutputVolume
	fader.Parent = folder
	local wires: { Wire } = {}
	local outputs: { AudioDeviceOutput } = {}
	local compressor = createEffect("AudioCompressor", "RadioDeathCompressor", folder) :: AudioCompressor
	compressor.Threshold = Config.Effects.Compressor.Threshold
	compressor.Ratio = Config.Effects.Compressor.Ratio
	compressor.Attack = Config.Effects.Compressor.Attack
	compressor.Release = Config.Effects.Compressor.Release
	compressor.MakeupGain = Config.Effects.Compressor.MakeupGain
	local bandpass = createEffect("AudioFilter", "RadioDeathBandpass", folder) :: AudioFilter
	bandpass.FilterType = Enum.AudioFilterType.Bandpass
	bandpass.Frequency = Config.Effects.Bandpass.Frequency
	bandpass.Q = Config.Effects.Bandpass.Q
	local equalizer = createEffect("AudioEqualizer", "RadioDeathTone", folder) :: AudioEqualizer
	equalizer.LowGain = Config.Effects.Equalizer.LowGain
	equalizer.MidGain = Config.Effects.Equalizer.MidGain
	equalizer.HighGain = Config.Effects.Equalizer.HighGain
	local distortion = createEffect("AudioDistortion", "RadioDeathStatic", folder) :: AudioDistortion
	distortion.Level = Config.Effects.DistortionLevel
	local limiter = createEffect("AudioLimiter", "RadioDeathLimiter", folder) :: AudioLimiter
	limiter.MaxLevel = Config.Effects.Limiter.MaxLevel
	limiter.Release = Config.Effects.Limiter.Release
	table.insert(wires, connect(player, compressor, folder))
	table.insert(wires, connect(compressor, bandpass, folder))
	table.insert(wires, connect(bandpass, equalizer, folder))
	table.insert(wires, connect(equalizer, distortion, folder))
	table.insert(wires, connect(distortion, limiter, folder))
	table.insert(wires, connect(limiter, fader, folder))
	local position = if state
		then getWorldPosition(state.Emitter) or getPlayerPosition(sourcePlayer)
		else LastRadioPosition[sourcePlayer] or getPlayerPosition(sourcePlayer)
	if position then NoiseService:Emit(position, Config.RadioNoiseRadius, nil) end

	for receiver in States do
		local wanted = receiver ~= sourcePlayer
			and allows(sourcePlayer, receiver)
			and allows(receiver, sourcePlayer)
		if wanted then
			local output = Instance.new("AudioDeviceOutput")
			output.Name = `RadioDeathOutput_{receiver.UserId}`
			output.Player = receiver
			output.Parent = folder
			table.insert(outputs, output)
			table.insert(wires, connect(fader, output, folder))
		end
	end

	if #outputs == 0 then
		folder:Destroy()
		if root.Parent and #root:GetChildren() == 0 then root:Destroy() end
		return
	end

	player.Looping = false
	player.Ended:Once(function()
		if player.Parent then player:Destroy() end
		if fader.Parent then fader:Destroy() end
		for _, wire in wires do
			if wire.Parent then wire:Destroy() end
		end
		for _, output in outputs do
			if output.Parent then output:Destroy() end
		end
		if folder.Parent then folder:Destroy() end
		if root.Parent and #root:GetChildren() == 0 then root:Destroy() end
	end)
	player:Play()
end

local function stopRelaySound(source: AudioPlayer)
	local relay = RelaySounds[source]
	if not relay then return end
	RelaySounds[source] = nil

	local playerRelays = RelayIds[relay.Radio.Player]
	if playerRelays and playerRelays[relay.Id] == source then
		playerRelays[relay.Id] = nil
	end

	if source.IsPlaying then source:Stop() end
	if relay.Wire.Parent then relay.Wire:Destroy() end
	if source.Parent then source:Destroy() end
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
		AmbientNoiseAt[emitter] = nil
		for _, state in States do
			disconnectAmbient(state, emitter)
		end
	end)
	refreshAmbientSources()
end

function WalkieTalkieService:StartSound(player: Player, relayId: string, name: string, looped: boolean)
	local state = States[player]
	if not state or not relayBucketAllows(player) then return end

	local template = findRadioSoundTemplate(name)
	if not template then return end

	local playerRelays = RelayIds[player]
	if not playerRelays then
		playerRelays = {}
		RelayIds[player] = playerRelays
	end
	local existing = playerRelays[relayId]
	if existing then stopRelaySound(existing) end

	local source = template:Clone()
	source.Name = `RadioSound_{name}`
	source.Looping = looped
	source.Parent = state.Audio
	emitRadioNoise(state)
	local wire = connect(source, state.AmbientMixer, state.Audio)
	RelaySounds[source] = { Radio = state, Id = relayId, Wire = wire, LastNoiseAt = os.clock() }
	playerRelays[relayId] = source
	source.Ended:Once(function()
		stopRelaySound(source)
	end)
	source:Play()
end

function WalkieTalkieService:StopSound(player: Player, relayId: string)
	local playerRelays = RelayIds[player]
	local source = playerRelays and playerRelays[relayId]
	if source then stopRelaySound(source) end
end

function WalkieTalkieService:SetLooping(player: Player, relayId: string, looped: boolean)
	local playerRelays = RelayIds[player]
	local source = playerRelays and playerRelays[relayId]
	if source and source.Parent then source.Looping = looped end
end

function WalkieTalkieService:SetVoiceActivity(player: Player, active: boolean)
	local state = States[player]
	if state then updateSpeaking(state, active) end
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

		local wire = connect(state.RadioOutputFader, output, state.Tool)
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
	queueRebuild()
end

local function teardown(state: State)
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	for source, relay in RelaySounds do
		if relay.Radio == state then stopRelaySound(source) end
	end
	for _, route in state.OutputWires do
		route.Wire:Destroy()
		route.Output:Destroy()
	end
	for emitter in state.AmbientRoutes do
		disconnectAmbient(state, emitter)
	end
	if state.ActivePlayer and state.ActivePlayer.IsPlaying then state.ActivePlayer:Stop() end
	if state.Emitter.Parent then state.Emitter:Destroy() end
	if state.Audio.Parent then state.Audio:Destroy() end
end

local function handlePlayerDeath(player: Player)
	local state = States[player]
	local voiceState = VoiceActivityService:GetState(player)
	local now = os.clock()
	local active = (state ~= nil and state.Speaking)
		or (voiceState ~= nil and (voiceState.Active or now - voiceState.LastActiveAt <= Config.DeathActiveGrace))
	local hasRadio = state ~= nil
		or (RadioEquippedAt[player] ~= nil and now - RadioEquippedAt[player] <= Config.DeathActiveGrace)
	if hasRadio and active then playDeathBurst(player) end
end

local function bindCharacterDeath(player: Player, character: Model)
	if DeathConnections[player] then
		DeathConnections[player]:Disconnect()
		DeathConnections[player] = nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		DeathConnections[player] = humanoid.Died:Connect(function()
			handlePlayerDeath(player)
		end)
		return
	end
	local childConnection: RBXScriptConnection?
	childConnection = character.ChildAdded:Connect(function(child)
		if not child:IsA("Humanoid") then return end
		if childConnection then childConnection:Disconnect() end
		bindCharacterDeath(player, character)
	end)
end

local function watchCharacter(player: Player)
	if CharacterConnections[player] then CharacterConnections[player]:Disconnect() end
	CharacterConnections[player] = player.CharacterAdded:Connect(function(character)
		bindCharacterDeath(player, character)
	end)
	if player.Character then bindCharacterDeath(player, player.Character) end
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
	RadioEquippedAt[player] = nil
	LastRadioPosition[player] = nil
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
	local ambientMixer = createEffect("AudioChannelMixer", "RadioAmbientMix", audio) :: AudioChannelMixer
	ambientMixer.Layout = Enum.AudioChannelLayout.Mono
	local ambientFader = createEffect("AudioFader", "RadioAmbientVolume", audio) :: AudioFader
	ambientFader.Volume = Config.RadioAmbientVolume
	local taggedCompressor = createEffect("AudioCompressor", "TaggedCompressor", audio) :: AudioCompressor
	taggedCompressor.Threshold = Config.Effects.Compressor.Threshold
	taggedCompressor.Ratio = Config.Effects.Compressor.Ratio
	taggedCompressor.Attack = Config.Effects.Compressor.Attack
	taggedCompressor.Release = Config.Effects.Compressor.Release
	taggedCompressor.MakeupGain = Config.Effects.Compressor.MakeupGain
	local taggedBandpass = createEffect("AudioFilter", "TaggedBandpass", audio) :: AudioFilter
	taggedBandpass.FilterType = Enum.AudioFilterType.Bandpass
	taggedBandpass.Frequency = Config.Effects.Tagged.Bandpass.Frequency
	taggedBandpass.Q = Config.Effects.Tagged.Bandpass.Q
	local taggedEqualizer = createEffect("AudioEqualizer", "TaggedTone", audio) :: AudioEqualizer
	taggedEqualizer.LowGain = Config.Effects.Tagged.Equalizer.LowGain
	taggedEqualizer.MidGain = Config.Effects.Tagged.Equalizer.MidGain
	taggedEqualizer.HighGain = Config.Effects.Tagged.Equalizer.HighGain
	local taggedDistortion = createEffect("AudioDistortion", "TaggedStatic", audio) :: AudioDistortion
	taggedDistortion.Level = Config.Effects.Tagged.DistortionLevel
	local taggedLimiter = createEffect("AudioLimiter", "TaggedLimiter", audio) :: AudioLimiter
	taggedLimiter.MaxLevel = Config.Effects.Limiter.MaxLevel
	taggedLimiter.Release = Config.Effects.Limiter.Release
	local activeFader = createEffect("AudioFader", "RadioActiveVolume", audio) :: AudioFader
	activeFader.Volume = Config.Effects.Static.ActiveVolume
	local radioOutputFader = createEffect("AudioFader", "RadioOutputVolume", audio) :: AudioFader
	radioOutputFader.Volume = Config.RadioOutputVolume
	local physicalMixer = createEffect("AudioChannelMixer", "RadioPhysicalMix", audio) :: AudioChannelMixer
	physicalMixer.Layout = Enum.AudioChannelLayout.Mono
	local physicalFader = createEffect("AudioFader", "RadioPhysicalVolume", audio) :: AudioFader
	physicalFader.Volume = Config.RadioPhysicalVolume
	local activePlayer = cloneSoundPlayer("RadioActive", audio)
	if activePlayer then
		activePlayer.Looping = false
		connect(activePlayer, activeFader, audio)
	end

	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "RadioEmitter"
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
	connect(ambientMixer, ambientFader, audio)
	connect(ambientFader, taggedCompressor, audio)
	connect(taggedCompressor, taggedBandpass, audio)
	connect(taggedBandpass, taggedEqualizer, audio)
	connect(taggedEqualizer, taggedDistortion, audio)
	connect(taggedDistortion, taggedLimiter, audio)
	connect(limiter, mixer, audio, nil, "Input")
	connect(taggedLimiter, mixer, audio, nil, "Input")
	connect(activeFader, mixer, audio, nil, "Center")
	connect(mixer, radioOutputFader, audio)
	connect(taggedLimiter, physicalMixer, audio, nil, "Input")
	connect(activeFader, physicalMixer, audio, nil, "Center")
	connect(physicalMixer, physicalFader, audio)
	connect(physicalFader, emitter, audio)

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
		AmbientMixer = ambientMixer,
		ActiveFader = activeFader,
		RadioOutputFader = radioOutputFader,
		AmbientFader = ambientFader,
		ActivePlayer = activePlayer,
		Source = nil,
		SourceWire = nil,
		OutputWires = {},
		AmbientRoutes = {},
		Connections = {},
		LastActiveAt = -math.huge,
		Speaking = false,
	}
	States[player] = state
	RadioEquippedAt[player] = os.clock()
	LastRadioPosition[player] = getWorldPosition(emitter) or getPlayerPosition(player)
	local voiceState = VoiceActivityService:GetState(player)
	if voiceState then
		if voiceState.Active then
			updateSpeaking(state, true)
		elseif os.clock() - voiceState.LastActiveAt <= Config.TransmissionGrace then
			playActiveTransmission(state)
		end
	end
	Modes[player] = Modes[player] or "All"
	player:SetAttribute("WalkieTalkieMode", Modes[player])
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
	RadioEquippedAt[player] = os.clock()
	LastRadioPosition[player] = getWorldPosition(state.Emitter) or getPlayerPosition(player)
	teardown(state)
	States[player] = nil
	for _, other in States do
		ensureOutputs(other)
	end
	refreshAmbientSources()
	queueRebuild()
end

if RunService:IsServer() then
	SetMode.OnServerEvent:Connect(function(player: Player, mode: any)
		if type(mode) == "string" then WalkieTalkieService:SetMode(player, mode) end
	end)

	TransmitSound.OnServerEvent:Connect(function(player: Player, action: any, relayId: any, name: any, looped: any)
		if action == "Start" and type(relayId) == "string" and type(name) == "string" and type(looped) == "boolean" then
			WalkieTalkieService:StartSound(player, relayId, name, looped)
		elseif action == "Stop" and type(relayId) == "string" then
			WalkieTalkieService:StopSound(player, relayId)
		elseif action == "Loop" and type(relayId) == "string" and type(looped) == "boolean" then
			WalkieTalkieService:SetLooping(player, relayId, looped)
		elseif type(action) == "string" then
			WalkieTalkieService:StartSound(player, tostring(os.clock()), action, false)
		end
	end)

	VoiceActivity.OnServerEvent:Connect(function(player: Player, active: any)
		if type(active) == "boolean" then WalkieTalkieService:SetVoiceActivity(player, active) end
	end)
end

CollectionService:GetInstanceAddedSignal(Config.RadioAllowedTag):Connect(function(instance)
	if instance:IsA("AudioEmitter") then WalkieTalkieService:RegisterAmbientEmitter(instance) end
end)

for _, instance in CollectionService:GetTagged(Config.RadioAllowedTag) do
	if instance:IsA("AudioEmitter") then WalkieTalkieService:RegisterAmbientEmitter(instance) end
end

local ambientAccumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	local now = os.clock()
	for player, state in States do
		local position = getWorldPosition(state.Emitter) or getPlayerPosition(player)
		if position then LastRadioPosition[player] = position end
		local voiceState = VoiceActivityService:GetState(player)
		if state.Speaking and (not voiceState or not voiceState.Active) then updateSpeaking(state, false) end
	end

	for source, relay in RelaySounds do
		if not source.Parent then
			stopRelaySound(source)
		elseif now - relay.LastNoiseAt >= Config.NoiseInterval then
			emitRadioNoise(relay.Radio)
			relay.LastNoiseAt = now
		end
	end

	for emitter, source in AmbientSources do
		local owner: State? = nil
		local route: AmbientRoute? = nil
		for _, state in States do
			if state.AmbientRoutes[emitter] then
				owner = state
				route = state.AmbientRoutes[emitter]
				break
			end
		end
		if owner and route and source.IsPlaying then
			local lastNoiseAt = AmbientNoiseAt[emitter] or -math.huge
			if now - lastNoiseAt >= Config.NoiseInterval then
				emitRadioNoise(owner, nil, route.Fader.Volume)
				AmbientNoiseAt[emitter] = now
			end
		else
			AmbientNoiseAt[emitter] = nil
		end
	end

	ambientAccumulator += deltaTime
	if ambientAccumulator < 0.2 then return end
	ambientAccumulator = 0
	refreshAmbientSources()
end)

Players.PlayerAdded:Connect(function(player)
	Modes[player] = "All"
	player:SetAttribute("WalkieTalkieMode", "All")
	watchCharacter(player)
	queueRebuild()
end)

Players.PlayerRemoving:Connect(function(player)
	local state = States[player]
	if state then teardown(state) end
	if DeathConnections[player] then DeathConnections[player]:Disconnect() end
	if CharacterConnections[player] then CharacterConnections[player]:Disconnect() end
	States[player] = nil
	Modes[player] = nil
	RelayBuckets[player] = nil
	RelayIds[player] = nil
	RadioEquippedAt[player] = nil
	LastRadioPosition[player] = nil
	DeathConnections[player] = nil
	CharacterConnections[player] = nil
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
	watchCharacter(player)
end

return WalkieTalkieService
