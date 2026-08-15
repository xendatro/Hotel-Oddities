local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Templates = ReplicatedStorage:WaitForChild("Sounds")
local Buses = workspace:WaitForChild("Sounds")

--- @class AudioService
--- Plays audio through the new audio API, so every sound is acoustically simulated: occluded by
--- walls, diffracted around corners, and reverberated by the room it is in.
---
--- A 3D template in `ReplicatedStorage.Sounds` is an `AudioEmitter` holding an `AudioPlayer` named
--- `Player` and the `Wire` between them. Playing one clones the emitter and parents it to a part,
--- exactly where the old `Sound` went. From there the engine's own camera `AudioListener` picks it
--- up, so nothing has to build a listener. A 2D template is a bare `AudioPlayer`, with no emitter to
--- place it in the world; it wires straight to the speakers instead.
local AudioService = {}

local Output: AudioDeviceOutput? = nil
type Audio3DTemplate = string | AudioEmitter

local function resolve3DTemplate(template: Audio3DTemplate): AudioEmitter
	return if typeof(template) == "string" then Templates[template] :: AudioEmitter else template
end

--- The bus faders under `workspace.Sounds` are volume stores rather than wired mixer nodes. A 3D
--- sound reaches the ear through its own emitter and the shared listener, so there is no node
--- downstream of the player that belongs to one bus alone. Bus volume is folded into each player
--- and kept in step while it plays.
local function bindBus(player: AudioPlayer, bus: AudioFader): RBXScriptConnection
	local baseVolume = player.Volume
	player.Volume = baseVolume * bus.Volume
	return bus:GetPropertyChangedSignal("Volume"):Connect(function()
		player.Volume = baseVolume * bus.Volume
	end)
end

local function bindLifetime(root: Instance, player: AudioPlayer, connection: RBXScriptConnection)
	root.Destroying:Once(function()
		connection:Disconnect()
	end)

	if not player.Looping then
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

--- The client's speakers. 3D audio reaches them through the engine's camera listener, so only 2D
--- playback wires itself here.
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

--- Carries audio from one node to the next. The wire lives under its source so destroying the
--- source takes the connection with it.
function AudioService:Wire(source: Instance, target: Instance): Wire
	local wire = Instance.new("Wire")
	wire.SourceInstance = source
	wire.TargetInstance = target
	wire.Parent = source
	return wire
end

--- Returns the effective start and end positions, in seconds, for a player. These come from
--- `PlaybackRegion`, which the engine already honours: playback starts at the minimum and `Ended`
--- fires at the maximum.
function AudioService:GetPlaybackBounds(player: AudioPlayer): (number, number)
	local region = player.PlaybackRegion
	local length = player.TimeLength
	local finish = if length > 0 then math.min(region.Max, length) else region.Max
	return region.Min, math.max(finish, region.Min)
end

--[[
Builds a 3D sound at `parent` without starting it, by cloning an AudioEmitter template from
ReplicatedStorage.Sounds. A template instance can be supplied for sounds stored in a subfolder.
Use this when playback has to be driven later; `Play3DSound` is the one-shot form.

Returns the AudioPlayer inside the emitter. The emitter is destroyed for you once a non-looping
sound ends; a looping one is yours to stop with `StopSound`.
]]
function AudioService:Create3DSound(
	template: Audio3DTemplate,
	parent: BasePart,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?
): AudioPlayer
	local emitter = resolve3DTemplate(template):Clone()
	local player = emitter.Player :: AudioPlayer
	player.Looping = looped

	emitter.Parent = parent
	-- Apply emitter settings after parenting. In the new audio API, attenuation is evaluated by the
	-- live emitter/listener graph, and changing these properties before the emitter enters that graph
	-- can leave the runtime attenuation state stale even though the property reads back correctly.
	applySettings(player, emitter, settings)
	bindLifetime(emitter, player, bindBus(player, self:GetBus(soundGroup)))
	return player
end

--- Plays a 3D spatial sound at `parent`. See `Create3DSound` for the returned object's lifetime.
function AudioService:Play3DSound(
	template: Audio3DTemplate,
	parent: BasePart,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?
): AudioPlayer
	local player = self:Create3DSound(template, parent, looped, soundGroup, settings)
	player:Play()
	return player
end

--[[
Plays a template with no position, straight into the speakers. Client only -- 2D audio ends at a
device the server does not have.

`target` defaults to the output, and is there for callers that need a node of their own in the
chain, such as a fader they intend to duck.
]]
function AudioService:Play2D(
	template: Instance,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?,
	target: Instance?
): AudioPlayer
	local source = if template:IsA("AudioPlayer") then template else template.Player :: AudioPlayer
	local player = source:Clone()
	player.Looping = looped
	applySettings(player, nil, settings)

	player.Parent = Buses
	self:Wire(player, target or self:GetOutput())
	bindLifetime(player, player, bindBus(player, self:GetBus(soundGroup)))
	player:Play()
	return player
end

--- Plays a 2D sound by template name. Client only.
function AudioService:Play2DSound(
	name: string,
	looped: boolean,
	soundGroup: string,
	settings: {[string]: any}?
): AudioPlayer
	local template = Templates:FindFirstChild(name)
	-- Studio can briefly contain an empty synced duplicate while an audio asset is being uploaded.
	-- Prefer a same-named template whose player has a real asset, rather than silently playing nothing.
	for _, candidate in Templates:GetChildren() do
		if candidate.Name ~= name then continue end
		local source = if candidate:IsA("AudioPlayer") then candidate else candidate:FindFirstChild("Player")
		if source and source:IsA("AudioPlayer") and source.Asset ~= "" then
			template = candidate
			break
		end
	end
	return self:Play2D(template, looped, soundGroup, settings)
end

--- Stops a sound this service started and removes the graph it was playing through.
function AudioService:StopSound(player: AudioPlayer)
	player:Stop()

	local root = player.Parent
	if root and root:IsA("AudioEmitter") then
		root:Destroy()
	else
		player:Destroy()
	end
end

--- Changes the volume of a bus in workspace.Sounds, including for sounds already playing on it.
function AudioService:AdjustSoundGroup(soundGroupName: string, newVolume: number)
	self:GetBus(soundGroupName).Volume = newVolume
end

return AudioService
