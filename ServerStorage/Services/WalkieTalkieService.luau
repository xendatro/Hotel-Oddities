local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local NoiseService = require(ServerStorage.Services.NoiseService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local SetMode = CommunicationService.Ensure("WalkieTalkie", "SetMode")
local SetPower = CommunicationService.Ensure("WalkieTalkie", "SetPower")
local SetTransmit = CommunicationService.Ensure("WalkieTalkie", "SetTransmit")
local SetAudio = CommunicationService.Ensure("WalkieTalkie", "SetAudio")
local TransmitSound = CommunicationService.Ensure("WalkieTalkie", "TransmitSound")

local WalkieTalkieService = {}

type AmbientRoute = { Fader: AudioFader, SourceWire: Wire, MixerWire: Wire }
type Receiver = {
	Output: AudioDeviceOutput,
	Mixer: AudioChannelMixer,
	Voice: AudioFader,
	Monster: AudioFader,
	Noise: AudioFader,
	Wires: { Wire },
}
type State = {
	Player: Player,
	Tool: Tool,
	Audio: Folder,
	Emitter: AudioEmitter,
	Compressor: AudioCompressor,
	Limiter: AudioLimiter,
	TaggedLimiter: AudioLimiter,
	AmbientMixer: AudioChannelMixer,
	VoiceGate: AudioFader,
	AmbientGate: AudioFader,
	ActiveFader: AudioFader,
	PhysicalFader: AudioFader,
	ActivePlayer: AudioPlayer?,
	Source: AudioDeviceInput?,
	SourceWire: Wire?,
	Receivers: { [Player]: Receiver },
	AmbientRoutes: { [AudioEmitter]: AmbientRoute },
	Connections: { RBXScriptConnection },
	LastRadioVoiceAt: number,
}

type RelayBucket = { StartedAt: number, Count: number }
type RelaySoundState = { Radio: State, Id: string, Wire: Wire }
type AudioSettings = { [string]: number }

local States: { [Player]: State } = {}
local Modes: { [Player]: string } = {}
local Powered: { [Player]: boolean } = {}
local Transmitting: { [Player]: boolean } = {}
local Settings: { [Player]: AudioSettings } = {}
local FriendCache: { [string]: boolean } = {}
local AmbientSources: { [AudioEmitter]: AudioPlayer } = {}
local RelayBuckets: { [Player]: RelayBucket } = {}
local RelaySounds: { [AudioPlayer]: RelaySoundState } = {}
local RelayIds: { [Player]: { [string]: AudioPlayer } } = {}
local DeathConnections: { [Player]: RBXScriptConnection } = {}
local CharacterConnections: { [Player]: RBXScriptConnection } = {}
local DeadPlayers: { [Player]: boolean } = {}
local LastRadioPosition: { [Player]: Vector3 } = {}
local RebuildQueued = false
local ensureReceivers: (state: State) -> ()
local reconcile: (player: Player) -> ()
local RADIO_NOISE_INTERVAL = 0.4

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function defaultSettings(): AudioSettings
	local settings: AudioSettings = {}
	for _, entry in Config.Categories do
		settings[entry.Id] = 1
	end
	return settings
end

local function getSettings(player: Player): AudioSettings
	local settings = Settings[player]
	if not settings then
		settings = defaultSettings()
		Settings[player] = settings
	end
	return settings
end

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

local function emitRadioNoise(
	state: State,
	source: Player?,
	strength: number?,
	ignoreSourceInterval: boolean?
): boolean
	local position = getWorldPosition(state.Emitter) or getPlayerPosition(state.Player)
	local radius = Config.RadioNoiseRadius * math.clamp(strength or 1, 0, 1)
	if not position or radius <= 0 then return false end
	return NoiseService:Emit(position, radius, source or state.Player, ignoreSourceInterval) ~= nil
end

local function emitRadioVoiceNoise(state: State)
	if not Transmitting[state.Player] then return end
	local now = os.clock()

	for receiver in state.Receivers do
		local receiverState = States[receiver]
		if receiverState and now - receiverState.LastRadioVoiceAt >= RADIO_NOISE_INTERVAL then
			if emitRadioNoise(receiverState, receiver, nil, true) then
				receiverState.LastRadioVoiceAt = now
			end
		end
	end
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

local function applyReceiverVolumes(state: State, receiver: Player, route: Receiver)
	local settings = getSettings(receiver)
	local global = settings.Global or 1
	route.Voice.Volume = Config.VoiceVolume * global * (settings.Voices or 1)
	route.Monster.Volume = Config.TaggedSoundVolume * global * (settings.Monster or 1)
	route.Noise.Volume = global * (settings.Noise or 1)
end

local function updateTransmitting(state: State, active: boolean)
	local gate = if active then 1 else 0
	state.VoiceGate.Volume = gate
	state.AmbientGate.Volume = gate

	local player = state.ActivePlayer
	if not player then return end
	if active then
		if player.IsPlaying then return end
		player.TimePosition = 0
		player:Play()
	elseif player.IsPlaying then
		player:Stop()
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
	local distanceAlpha = math.clamp((emitterPosition - playerPosition).Magnitude / Config.TaggedSoundDistance, 0, 1)
	return (1 - distanceAlpha) ^ Config.TaggedSoundPickupFalloff
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
				if not Transmitting[state.Player] then continue end
				local playerPosition = getPlayerPosition(state.Player)
				if playerPosition then
					local distance = (playerPosition - emitterPosition).Magnitude
					if distance <= Config.TaggedSoundDistance and distance < closestDistance then
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
	fader.Volume = Config.Effects.Static.DeathVolume * Config.VoiceVolume
	fader.Parent = folder
	local wires: { Wire } = {}
	local outputs: { Instance } = {}
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

	for _, receiver in Players:GetPlayers() do
		local wanted = receiver ~= sourcePlayer
			and Powered[receiver]
			and not DeadPlayers[receiver]
			and allows(sourcePlayer, receiver)
			and allows(receiver, sourcePlayer)
		if not wanted then continue end

		local settings = getSettings(receiver)
		local gain = createEffect("AudioFader", `RadioDeathGain_{receiver.UserId}`, folder) :: AudioFader
		gain.Volume = (settings.Global or 1) * (settings.Noise or 1)
		local output = Instance.new("AudioDeviceOutput")
		output.Name = `RadioDeathOutput_{receiver.UserId}`
		output.Player = receiver
		output.Parent = folder
		table.insert(outputs, gain)
		table.insert(outputs, output)
		table.insert(wires, connect(fader, gain, folder))
		table.insert(wires, connect(gain, output, folder))
	end

	if #outputs == 0 then
		folder:Destroy()
		if root.Parent and #root:GetChildren() == 0 then root:Destroy() end
		return
	end

	player.Looping = false
	player.Ended:Once(function()
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
		for _, state in States do
			disconnectAmbient(state, emitter)
		end
	end)
	refreshAmbientSources()
end

function WalkieTalkieService:StartSound(
	player: Player,
	relayId: string,
	name: string,
	looped: boolean,
	timePosition: number?,
	playbackSpeed: number?,
	volume: number?
)
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
	source.TimePosition = math.max(timePosition or 0, 0)
	source.PlaybackSpeed = math.clamp(playbackSpeed or source.PlaybackSpeed, 0.05, 20)
	source.Volume = math.clamp(volume or source.Volume, 0, 10)
	source.Parent = state.Audio
	if Transmitting[player] then emitRadioNoise(state) end
	local wire = connect(source, state.AmbientMixer, state.Audio)
	RelaySounds[source] = { Radio = state, Id = relayId, Wire = wire }
	playerRelays[relayId] = source
	source.Ended:Once(function()
		stopRelaySound(source)
	end)
	source:Play()
end

function WalkieTalkieService:SyncSound(
	player: Player,
	relayId: string,
	timePosition: number,
	playbackSpeed: number,
	volume: number
)
	if not relayBucketAllows(player) then return end
	local playerRelays = RelayIds[player]
	local source = playerRelays and playerRelays[relayId]
	if not source or not source.Parent then return end

	source.TimePosition = math.max(timePosition, 0)
	source.PlaybackSpeed = math.clamp(playbackSpeed, 0.05, 20)
	source.Volume = math.clamp(volume, 0, 10)
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

function WalkieTalkieService:ApplyVolumes()
	for _, state in States do
		state.ActiveFader.Volume = Config.Effects.Static.ActiveVolume * Config.VoiceVolume
		state.PhysicalFader.Volume = Config.RadioPhysicalVolume
		for receiver, route in state.Receivers do
			applyReceiverVolumes(state, receiver, route)
		end
	end
end

function WalkieTalkieService:SetAudioSettings(player: Player, incoming: { [string]: any })
	local settings = getSettings(player)
	for _, entry in Config.Categories do
		local value = incoming[entry.Id]
		if isFiniteNumber(value) then
			settings[entry.Id] = math.clamp(value, 0, entry.Maximum or 1)
		end
	end

	for _, state in States do
		local route = state.Receivers[player]
		if route then applyReceiverVolumes(state, player, route) end
	end

	local profile = DataSaveService:Get(player)
	if profile then profile.Data.WalkieAudio = table.clone(settings) end
end

function WalkieTalkieService:SetTransmitting(player: Player, active: boolean)
	local wanted = active == true and Powered[player] == true and not DeadPlayers[player]
	if Transmitting[player] == wanted then return end
	Transmitting[player] = wanted or nil
	player:SetAttribute(Config.TransmitAttribute, wanted)

	local state = States[player]
	if state then updateTransmitting(state, wanted) end
	refreshAmbientSources()
end

local function queueRebuild()
	if RebuildQueued then return end
	RebuildQueued = true
	task.defer(function()
		RebuildQueued = false
		for _, state in States do
			ensureReceivers(state)
		end
	end)
end

local function destroyReceiver(state: State, receiver: Player)
	local route = state.Receivers[receiver]
	if not route then return end
	for _, wire in route.Wires do
		if wire.Parent then wire:Destroy() end
	end
	route.Voice:Destroy()
	route.Monster:Destroy()
	route.Noise:Destroy()
	route.Mixer:Destroy()
	route.Output:Destroy()
	state.Receivers[receiver] = nil
end

ensureReceivers = function(state: State)
	local sender = state.Player
	for _, receiver in Players:GetPlayers() do
		local wanted = receiver ~= sender
			and Powered[sender] == true
			and Powered[receiver] == true
			and not DeadPlayers[sender]
			and not DeadPlayers[receiver]
			and allows(sender, receiver)
			and allows(receiver, sender)
		local existing = state.Receivers[receiver]
		if not wanted then
			destroyReceiver(state, receiver)
			continue
		end
		if existing then
			applyReceiverVolumes(state, receiver, existing)
			continue
		end

		local suffix = tostring(receiver.UserId)
		local voice = createEffect("AudioFader", `RadioVoice_{suffix}`, state.Tool) :: AudioFader
		local monster = createEffect("AudioFader", `RadioMonster_{suffix}`, state.Tool) :: AudioFader
		local noise = createEffect("AudioFader", `RadioNoise_{suffix}`, state.Tool) :: AudioFader
		local mixer = createEffect("AudioChannelMixer", `RadioMix_{suffix}`, state.Tool) :: AudioChannelMixer
		mixer.Layout = Enum.AudioChannelLayout.Mono
		local output = Instance.new("AudioDeviceOutput")
		output.Name = `RadioOutput_{suffix}`
		output.Player = receiver
		output.Parent = state.Tool

		local route: Receiver = {
			Output = output,
			Mixer = mixer,
			Voice = voice,
			Monster = monster,
			Noise = noise,
			Wires = {
				connect(state.VoiceGate, voice, state.Tool),
				connect(state.TaggedLimiter, monster, state.Tool),
				connect(state.ActiveFader, noise, state.Tool),
				connect(voice, mixer, state.Tool, nil, "Input"),
				connect(monster, mixer, state.Tool, nil, "Input"),
				connect(noise, mixer, state.Tool, nil, "Center"),
				connect(mixer, output, state.Tool),
			},
		}
		state.Receivers[receiver] = route
		applyReceiverVolumes(state, receiver, route)
	end

	for receiver in state.Receivers do
		if receiver.Parent then continue end
		destroyReceiver(state, receiver)
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
	for receiver in state.Receivers do
		destroyReceiver(state, receiver)
	end
	for emitter in state.AmbientRoutes do
		disconnectAmbient(state, emitter)
	end
	if state.ActivePlayer and state.ActivePlayer.IsPlaying then state.ActivePlayer:Stop() end
	if state.SourceWire and state.SourceWire.Parent then state.SourceWire:Destroy() end
	if state.Emitter.Parent then state.Emitter:Destroy() end
	if state.Audio.Parent then state.Audio:Destroy() end
end

local function findTool(player: Player): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, root in { player.Character, backpack } do
		if not root then continue end
		local tool = root:FindFirstChild(Config.ToolName)
		if tool and tool:IsA("Tool") then return tool end
	end
	return nil
end

local function build(player: Player, tool: Tool)
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

	local voiceGate = createEffect("AudioFader", "RadioVoiceGate", audio) :: AudioFader
	voiceGate.Volume = 0

	local ambientMixer = createEffect("AudioChannelMixer", "RadioAmbientMix", audio) :: AudioChannelMixer
	ambientMixer.Layout = Enum.AudioChannelLayout.Mono
	local ambientGate = createEffect("AudioFader", "RadioTaggedGate", audio) :: AudioFader
	ambientGate.Volume = 0
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
	activeFader.Volume = Config.Effects.Static.ActiveVolume * Config.VoiceVolume
	local physicalMixer = createEffect("AudioChannelMixer", "RadioPhysicalMix", audio) :: AudioChannelMixer
	physicalMixer.Layout = Enum.AudioChannelLayout.Mono
	local physicalFader = createEffect("AudioFader", "RadioPhysicalVolume", audio) :: AudioFader
	physicalFader.Volume = Config.RadioPhysicalVolume
	local activePlayer = cloneSoundPlayer("RadioActive", audio)
	if activePlayer then
		activePlayer.Looping = true
		connect(activePlayer, activeFader, audio)
	end

	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "RadioEmitter"
	emitter.AudioInteractionGroup = ""
	emitter.AcousticSimulationEnabled = true
	emitter.OcclusionEnabled = Enum.SimulationMode.Enabled
	emitter.DistanceAttenuationBounds = NumberRange.new(0, Config.PhysicalDistance)
	emitter.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Custom
	emitter:SetDistanceAttenuation({
		[0] = 1,
		[Config.PhysicalDistance * 0.8] = 0.65,
		[Config.PhysicalDistance] = 0,
	})
	emitter.Parent = handle

	connect(compressor, bandpass, audio)
	connect(bandpass, equalizer, audio)
	connect(equalizer, distortion, audio)
	connect(distortion, limiter, audio)
	connect(limiter, voiceGate, audio)
	connect(ambientMixer, ambientGate, audio)
	connect(ambientGate, taggedCompressor, audio)
	connect(taggedCompressor, taggedBandpass, audio)
	connect(taggedBandpass, taggedEqualizer, audio)
	connect(taggedEqualizer, taggedDistortion, audio)
	connect(taggedDistortion, taggedLimiter, audio)
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
		Limiter = limiter,
		TaggedLimiter = taggedLimiter,
		AmbientMixer = ambientMixer,
		VoiceGate = voiceGate,
		AmbientGate = ambientGate,
		ActiveFader = activeFader,
		PhysicalFader = physicalFader,
		ActivePlayer = activePlayer,
		Source = nil,
		SourceWire = nil,
		Receivers = {},
		AmbientRoutes = {},
		Connections = {},
		LastRadioVoiceAt = -math.huge,
	}
	States[player] = state
	LastRadioPosition[player] = getWorldPosition(emitter) or getPlayerPosition(player)
	updateTransmitting(state, Transmitting[player] == true)

	table.insert(state.Connections, player.ChildAdded:Connect(function(child)
		if child.Name == "AudioDeviceInput" then
			connectSource(state)
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
	refreshAmbientSources()
	queueRebuild()
end

reconcile = function(player: Player)
	local state = States[player]
	local wanted = Powered[player] == true
		and not DeadPlayers[player]
		and player:GetAttribute(Config.VoiceAttribute) ~= false
	local tool = if wanted then findTool(player) else nil

	if state and (not wanted or state.Tool ~= tool or not state.Tool.Parent) then
		LastRadioPosition[player] = getWorldPosition(state.Emitter) or getPlayerPosition(player)
		teardown(state)
		States[player] = nil
		state = nil
	end
	if wanted and not state and tool then
		build(player, tool)
	end
	queueRebuild()
end

function WalkieTalkieService:Reconcile(player: Player)
	reconcile(player)
end

function WalkieTalkieService:SetPower(player: Player, on: boolean)
	local wanted = on == true and player:GetAttribute(Config.VoiceAttribute) ~= false
	if Powered[player] == wanted then return end
	Powered[player] = wanted or nil
	player:SetAttribute(Config.PowerAttribute, wanted)
	if not wanted then WalkieTalkieService:SetTransmitting(player, false) end
	reconcile(player)
	for _, other in Players:GetPlayers() do
		if other ~= player and States[other] then ensureReceivers(States[other]) end
	end
end

function WalkieTalkieService:SetMode(player: Player, mode: string)
	if mode ~= "All" and mode ~= "Friends" then return end
	Modes[player] = mode
	player:SetAttribute("WalkieTalkieMode", mode)
	local profile = DataSaveService:Get(player)
	if profile then profile.Data.WalkieMode = mode end
	queueRebuild()
end

local function handlePlayerDeath(player: Player)
	if DeadPlayers[player] then return end
	local wasTransmitting = Transmitting[player] == true
	local state = States[player]
	DeadPlayers[player] = true
	WalkieTalkieService:SetTransmitting(player, false)

	if state then
		LastRadioPosition[player] = getWorldPosition(state.Emitter) or getPlayerPosition(player)
		if wasTransmitting then playDeathBurst(player) end
		teardown(state)
		States[player] = nil
	end
	for _, senderState in States do
		destroyReceiver(senderState, player)
	end
	queueRebuild()
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
		if humanoid.Health <= 0 then handlePlayerDeath(player) end
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
		DeadPlayers[player] = nil
		task.defer(reconcile, player)
		bindCharacterDeath(player, character)
		queueRebuild()
	end)
	if player.Character then bindCharacterDeath(player, player.Character) end
end

local function loadProfile(player: Player)
	local profile = DataSaveService:Wait(player)
	if not profile or not player.Parent then return end

	local settings = getSettings(player)
	local saved = profile.Data.WalkieAudio
	if type(saved) == "table" then
		for _, entry in Config.Categories do
			local value = saved[entry.Id]
			if isFiniteNumber(value) then
				settings[entry.Id] = math.clamp(value, 0, entry.Maximum or 1)
			end
		end
	end
	local mode = profile.Data.WalkieMode
	if mode == "All" or mode == "Friends" then
		Modes[player] = mode
		player:SetAttribute("WalkieTalkieMode", mode)
	end
	SetAudio:FireClient(player, table.clone(settings), Modes[player] or "All")
end

local function watchPlayer(player: Player)
	Modes[player] = Modes[player] or "All"
	player:SetAttribute("WalkieTalkieMode", Modes[player])
	player:SetAttribute(Config.PowerAttribute, false)
	player:SetAttribute(Config.TransmitAttribute, false)
	getSettings(player)
	watchCharacter(player)
	task.spawn(function()
		local eligible = voiceEligible(player)
		if not player.Parent then return end
		player:SetAttribute(Config.VoiceAttribute, eligible)
		if not eligible then WalkieTalkieService:SetPower(player, false) end
	end)
	task.spawn(loadProfile, player)
	queueRebuild()
end

if RunService:IsServer() then
	SetMode.OnServerEvent:Connect(function(player: Player, mode: any)
		if type(mode) == "string" then WalkieTalkieService:SetMode(player, mode) end
	end)

	SetPower.OnServerEvent:Connect(function(player: Player, on: any)
		if type(on) == "boolean" then WalkieTalkieService:SetPower(player, on) end
	end)

	SetTransmit.OnServerEvent:Connect(function(player: Player, active: any)
		if type(active) == "boolean" then WalkieTalkieService:SetTransmitting(player, active) end
	end)

	SetAudio.OnServerEvent:Connect(function(player: Player, incoming: any)
		if type(incoming) == "table" then WalkieTalkieService:SetAudioSettings(player, incoming) end
	end)

	TransmitSound.OnServerEvent:Connect(function(
		player: Player,
		action: any,
		relayId: any,
		value1: any,
		value2: any,
		value3: any,
		value4: any,
		value5: any
	)
		if action == "Start"
			and type(relayId) == "string"
			and type(value1) == "string"
			and type(value2) == "boolean"
			and isFiniteNumber(value3)
			and isFiniteNumber(value4)
			and isFiniteNumber(value5)
		then
			WalkieTalkieService:StartSound(player, relayId, value1, value2, value3, value4, value5)
		elseif action == "Stop" and type(relayId) == "string" then
			WalkieTalkieService:StopSound(player, relayId)
		elseif action == "Loop" and type(relayId) == "string" and type(value1) == "boolean" then
			WalkieTalkieService:SetLooping(player, relayId, value1)
		elseif action == "Sync"
			and type(relayId) == "string"
			and isFiniteNumber(value1)
			and isFiniteNumber(value2)
			and isFiniteNumber(value3)
		then
			WalkieTalkieService:SyncSound(player, relayId, value1, value2, value3)
		elseif type(action) == "string" then
			WalkieTalkieService:StartSound(player, tostring(os.clock()), action, false)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(Config.RadioAllowedTag):Connect(function(instance)
	if instance:IsA("AudioEmitter") then WalkieTalkieService:RegisterAmbientEmitter(instance) end
end)

for _, instance in CollectionService:GetTagged(Config.RadioAllowedTag) do
	if instance:IsA("AudioEmitter") then WalkieTalkieService:RegisterAmbientEmitter(instance) end
end

local NOISE_TICK_INTERVAL = 0.05
local noiseAccumulator = 0
local ambientAccumulator = 0
RunService.Heartbeat:Connect(function(deltaTime)
	noiseAccumulator += deltaTime
	ambientAccumulator += deltaTime

	if noiseAccumulator >= NOISE_TICK_INTERVAL then
		noiseAccumulator = 0

		for player, state in States do
			local position = getWorldPosition(state.Emitter) or getPlayerPosition(player)
			if position then LastRadioPosition[player] = position end
		end

		for source, relay in RelaySounds do
			if not source.Parent then
				stopRelaySound(source)
			elseif Transmitting[relay.Radio.Player] then
				emitRadioNoise(relay.Radio)
			end
		end

		for _, state in States do
			emitRadioVoiceNoise(state)
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
				emitRadioNoise(owner, nil, route.Fader.Volume)
			end
		end
	end

	if ambientAccumulator < 0.2 then return end
	ambientAccumulator = 0
	refreshAmbientSources()
end)

Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player)
	local state = States[player]
	if state then teardown(state) end
	if DeathConnections[player] then DeathConnections[player]:Disconnect() end
	if CharacterConnections[player] then CharacterConnections[player]:Disconnect() end
	States[player] = nil
	Modes[player] = nil
	Powered[player] = nil
	Transmitting[player] = nil
	Settings[player] = nil
	RelayBuckets[player] = nil
	RelayIds[player] = nil
	LastRadioPosition[player] = nil
	DeathConnections[player] = nil
	CharacterConnections[player] = nil
	DeadPlayers[player] = nil
	local userId = tostring(player.UserId)
	for key in FriendCache do
		local first, second = key:match("^(%d+):(%d+)$")
		if first == userId or second == userId then FriendCache[key] = nil end
	end
	refreshAmbientSources()
	queueRebuild()
end)

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end

return WalkieTalkieService
