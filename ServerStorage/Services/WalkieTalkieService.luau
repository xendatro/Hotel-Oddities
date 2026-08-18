local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VoiceChatService = game:GetService("VoiceChatService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)

local Communication = ReplicatedStorage.Communication.WalkieTalkie
local SetMode = Communication.SetMode :: RemoteEvent

local WalkieTalkieService = {}

type State = {
	Player: Player,
	Tool: Tool,
	Emitter: AudioEmitter,
	Compressor: AudioCompressor,
	Bandpass: AudioFilter,
	Equalizer: AudioEqualizer,
	Distortion: AudioDistortion,
	Limiter: AudioLimiter,
	Source: AudioDeviceInput?,
	SourceWire: Wire?,
	OutputWires: { [Player]: { Output: AudioDeviceOutput, Wire: Wire } },
	Connections: { RBXScriptConnection },
}

local States: { [Player]: State } = {}
local Modes: { [Player]: string } = {}
local FriendCache: { [string]: boolean } = {}
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

local function connect(source: Instance, target: Instance, parent: Instance): Wire
	local wire = Instance.new("Wire")
	wire.Name = `{source.Name}To{target.Name}`
	wire.SourceInstance = source
	wire.TargetInstance = target
	wire.Parent = parent
	return wire
end

local function createEffect(className: string, name: string, parent: Instance): Instance
	local effect = Instance.new(className)
	effect.Name = name
	effect.Parent = parent
	return effect
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

		local wire = connect(state.Limiter, output, state.Tool)
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
	for _, route in state.OutputWires do
		route.Wire:Destroy()
		route.Output:Destroy()
	end
	if state.Emitter.Parent then state.Emitter:Destroy() end
	if state.Tool.Parent then
		for _, child in state.Tool:GetChildren() do
			if child.Name == "RadioAudio" then child:Destroy() end
		end
	end
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
	connect(limiter, emitter, audio)

	local state: State = {
		Player = player,
		Tool = tool,
		Emitter = emitter,
		Compressor = compressor,
		Bandpass = bandpass,
		Equalizer = equalizer,
		Distortion = distortion,
		Limiter = limiter,
		Source = nil,
		SourceWire = nil,
		OutputWires = {},
		Connections = {},
	}
	States[player] = state
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
	queueRebuild()
end

SetMode.OnServerEvent:Connect(function(player: Player, mode: any)
	if type(mode) == "string" then WalkieTalkieService:SetMode(player, mode) end
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
	for key in FriendCache do
		if string.find(key, tostring(player.UserId), 1, true) then FriendCache[key] = nil end
	end
	for _, other in States do
		ensureOutputs(other)
	end
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
