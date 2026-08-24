local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Templates = ReplicatedStorage:WaitForChild("Sounds")
local Buses = workspace:WaitForChild("Sounds")
local WalkieTalkieConfig = require(ReplicatedStorage.Configs.WalkieTalkieConfig)

local AudioService = {}

local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local RadioTransmit: RemoteEvent? = nil
local nextRadioRelayId = 0
local function getRadioTransmit(): RemoteEvent?
	if not RunService:IsClient() then return nil end
	if RadioTransmit and RadioTransmit.Parent then return RadioTransmit end
	local remote = CommunicationService.Find("WalkieTalkie", "TransmitSound")
	if remote and remote:IsA("RemoteEvent") then
		RadioTransmit = remote
	end
	return RadioTransmit
end

local function getRadioSoundName(template: Instance): string?
	if template:HasTag("RadioAllowed") then return template.Name end
	local parent = template.Parent
	if parent and parent:IsA("AudioEmitter") and parent:HasTag("RadioAllowed") then
		return parent.Name
	end
	return nil
end

local function requestRadioRelay(template: Instance, player: AudioPlayer)
	local name = getRadioSoundName(template)
	local remote = getRadioTransmit()
	if not remote or not name then return end

	nextRadioRelayId += 1
	local relayId = tostring(nextRadioRelayId)
	remote:FireServer(
		"Start",
		relayId,
		name,
		player.Looping,
		player.TimePosition,
		player.PlaybackSpeed,
		player.Volume
	)

	local stopped = false
	local isPlayingConnection: RBXScriptConnection?
	local loopingConnection: RBXScriptConnection?
	local syncConnection: RBXScriptConnection?
	local function stopRelay()
		if stopped then return end
		stopped = true
		if isPlayingConnection then isPlayingConnection:Disconnect() end
		if loopingConnection then loopingConnection:Disconnect() end
		if syncConnection then syncConnection:Disconnect() end
		if remote.Parent then remote:FireServer("Stop", relayId) end
	end

	isPlayingConnection = player:GetPropertyChangedSignal("IsPlaying"):Connect(function()
		if not player.IsPlaying then stopRelay() end
	end)
	loopingConnection = player:GetPropertyChangedSignal("Looping"):Connect(function()
		if not stopped and remote.Parent then remote:FireServer("Loop", relayId, player.Looping) end
	end)
	local syncAccumulator = 0
	syncConnection = RunService.Heartbeat:Connect(function(deltaTime)
		syncAccumulator += deltaTime
		if stopped or syncAccumulator < WalkieTalkieConfig.RelaySyncInterval then return end
		syncAccumulator = 0
		if remote.Parent and player.IsPlaying then
			remote:FireServer(
				"Sync",
				relayId,
				player.TimePosition,
				player.PlaybackSpeed,
				player.Volume
			)
		end
	end)
	player.Ended:Once(stopRelay)
	player.Destroying:Once(stopRelay)
end

local function registerServerRadioEmitter(emitter: AudioEmitter, allowed: boolean)
	if not RunService:IsServer() or not allowed then return end
	local service = require(game:GetService("ServerStorage").Services.WalkieTalkieService)
	service:RegisterAmbientEmitter(emitter)
end

local Output: AudioDeviceOutput? = nil
type Audio3DTemplate = string | AudioEmitter
type Audio2DPlayback = AudioPlayer | Sound

local function resolve3DTemplate(template: Audio3DTemplate): AudioEmitter
	return if typeof(template) == "string" then Templates[template] :: AudioEmitter else template
end

local function bindBus(player: AudioPlayer, bus: AudioFader): RBXScriptConnection
	local baseVolume = player.Volume
	player.Volume = baseVolume * bus.Volume
	return bus:GetPropertyChangedSignal("Volume"):Connect(function()
		player.Volume = baseVolume * bus.Volume
	end)
end

local function bindLegacyBus(sound: Sound, bus: AudioFader): RBXScriptConnection
	local baseVolume = sound.Volume
	sound.Volume = baseVolume * bus.Volume
	return bus:GetPropertyChangedSignal("Volume"):Connect(function()
		sound.Volume = baseVolume * bus.Volume
	end)
end

local function bindLifetime(root: Instance, player: Audio2DPlayback, connection: RBXScriptConnection)
	root.Destroying:Once(function()
		connection:Disconnect()
	end)

	local property = "Looping"
	if player:IsA("Sound") then
		property = "Looped"
	end

	if not player[property] then
		player.Ended:Once(function()
			root:Destroy()
		end)
	end
end

local function applySettings(player: AudioPlayer, emitter: AudioEmitter?, settings: {[string]: any}?)
	if not settings then return end

	for property, value in settings do
		local applied = pcall(function()
			player[property] = value
		end)
		if not applied and emitter then
			pcall(function()
				emitter[property] = value
			end)
		end
	end
end

function AudioService:GetOutput(): AudioDeviceOutput
	if not Output then
		local output = Instance.new("AudioDeviceOutput")
		output.Name = "Output"
		output.Parent = Buses
		Output = output
	end
	return Output :: AudioDeviceOutput
end

function AudioService:GetBus(name: string): AudioFader
	return Buses[name]
end

function AudioService:Wire(source: Instance, target: Instance): Wire
	local wire = Instance.new("Wire")
	wire.SourceInstance = source
	wire.TargetInstance = target
	wire.Parent = source
	return wire
end

function AudioService:GetPlaybackBounds(player: AudioPlayer): (number, number)
	local region = player.PlaybackRegion
	local length = player.TimeLength
	local finish = if length > 0 then math.min(region.Max, length) else region.Max
	return region.Min, math.max(finish, region.Min)
end

function AudioService:Create3DSound(
	template: Audio3DTemplate,
	parent: BasePart,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?
): AudioPlayer
	local sourceTemplate = resolve3DTemplate(template)
	local radioAllowed = getRadioSoundName(sourceTemplate) ~= nil
	local emitter = sourceTemplate:Clone()
	local player = emitter.Player :: AudioPlayer
	player.Looping = looped

	emitter.Parent = parent
	registerServerRadioEmitter(emitter, radioAllowed)
	applySettings(player, emitter, settings)
	bindLifetime(emitter, player, bindBus(player, self:GetBus(soundGroup)))
	return player
end

function AudioService:Play3DSound(
	template: Audio3DTemplate,
	parent: BasePart,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?
): AudioPlayer
	local player = self:Create3DSound(template, parent, looped, soundGroup, settings)
	player:Play()
	if RunService:IsClient() then requestRadioRelay(resolve3DTemplate(template), player) end
	return player
end

function AudioService:Play2D(
	template: Instance,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?,
	target: Instance?
): Audio2DPlayback
	if template:IsA("Sound") then
		local sound = template:Clone()
		sound.Looped = looped
		applySettings(sound, nil, settings)

		sound.Parent = target or SoundService
		bindLifetime(sound, sound, bindLegacyBus(sound, self:GetBus(soundGroup)))
		sound:Play()
		return sound
	end

	local source = if template:IsA("AudioPlayer") then template else template.Player :: AudioPlayer
	local player = source:Clone()
	player.Looping = looped
	applySettings(player, nil, settings)

	player.Parent = Buses
	self:Wire(player, target or self:GetOutput())
	bindLifetime(player, player, bindBus(player, self:GetBus(soundGroup)))
	player:Play()
	if RunService:IsClient() then requestRadioRelay(template, player) end
	return player
end

function AudioService:FindTemplate(name: string): Instance?
	for _, candidate in Templates:GetChildren() do
		if candidate.Name ~= name then continue end
		local source = if candidate:IsA("Sound") or candidate:IsA("AudioPlayer")
			then candidate
			else candidate:FindFirstChild("Player")
		if source and source:IsA("Sound") and source.SoundId ~= "" then
			return candidate
		elseif source and source:IsA("AudioPlayer") and source.Asset ~= "" then
			return candidate
		end
	end
	return nil
end

function AudioService:Play2DSound(
	name: string,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?,
	target: Instance?
): Audio2DPlayback
	local template = self:FindTemplate(name) or Templates:FindFirstChild(name)
	return self:Play2D(template, looped, soundGroup, settings, target)
end

function AudioService:StopSound(player: Audio2DPlayback)
	player:Stop()

	local root = player.Parent
	if root and root:IsA("AudioEmitter") then
		root:Destroy()
	else
		player:Destroy()
	end
end

function AudioService:AdjustSoundGroup(soundGroupName: string, newVolume: number)
	self:GetBus(soundGroupName).Volume = newVolume
end

return AudioService
