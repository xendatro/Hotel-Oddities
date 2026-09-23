local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Configs.AmbienceConfig)
local POIConfig = require(ReplicatedStorage.Configs.POIConfig)
local AmbienceService = require(ReplicatedStorage.Services.AmbienceService)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DeathScreenService = require(ReplicatedStorage.Services.DeathScreenService)
local LobbyService = require(ReplicatedStorage.Services.LobbyService)

local AmbienceExtrasService = {}

if not RunService:IsClient() then
	return AmbienceExtrasService
end

local Sounds = ReplicatedStorage:WaitForChild("Sounds")
local LocationFolder = Sounds:FindFirstChild("LocationAmbience")
local ExtraFolder = Sounds:FindFirstChild("ExtraAmbience")
local AMBIENCE_BUS = "Ambience"
local LocationConfig = AmbienceConfig.LocationAmbience
local ExtraConfig = AmbienceConfig.ExtraAmbience
local Bus = AudioService:GetBus(AMBIENCE_BUS)
local Randomizer = Random.new()

type Playback = AudioPlayer | Sound
type LocationTrack = {
	Name: string,
	Template: Instance,
	BaseVolume: number,
	Gain: number,
	Playback: Playback?,
}

local LocationTracks: { LocationTrack } = {}
local TracksByName: { [string]: { LocationTrack } } = {}
local POIs: { [Instance]: true } = {}
local LocationGains: { [string]: number } = {}
local ExtraSources: { Instance } = {}
local ExtraCountdown = 0
local LastExtraIndex = 0
local updateAccumulator = 0

local function isAudioTemplate(instance: Instance): boolean
	if instance:IsA("Sound") then
		return instance.SoundId ~= ""
	elseif instance:IsA("AudioPlayer") then
		return instance.Asset ~= ""
	elseif instance:IsA("AudioEmitter") then
		local player = instance:FindFirstChild("Player")
		return player ~= nil and player:IsA("AudioPlayer") and player.Asset ~= ""
	end

	return false
end

local function collectAudioTemplates(root: Instance): { Instance }
	local templates = {}

	local function visit(parent: Instance)
		for _, child in parent:GetChildren() do
			if child:IsA("AudioEmitter") then
				if isAudioTemplate(child) then
					table.insert(templates, child)
				end
			elseif child:IsA("Sound") or child:IsA("AudioPlayer") then
				if not (child.Parent and child.Parent:IsA("AudioEmitter")) and isAudioTemplate(child) then
					table.insert(templates, child)
				end
			else
				visit(child)
			end
		end
	end

	visit(root)
	return templates
end

local function getBaseVolume(template: Instance): number
	if template:IsA("Sound") or template:IsA("AudioPlayer") then
		return template.Volume
	end

	local player = template:FindFirstChild("Player")
	if player and player:IsA("AudioPlayer") then
		return player.Volume
	end

	return 1
end

local function addLocationTrack(name: string, template: Instance)
	local track: LocationTrack = {
		Name = name,
		Template = template,
		BaseVolume = getBaseVolume(template),
		Gain = 0,
		Playback = nil,
	}

	table.insert(LocationTracks, track)
	TracksByName[name] = TracksByName[name] or {}
	table.insert(TracksByName[name], track)
end

if LocationFolder then
	for _, child in LocationFolder:GetChildren() do
		local templates = if isAudioTemplate(child) then { child } else collectAudioTemplates(child)
		for _, template in templates do
			addLocationTrack(child.Name, template)
		end
	end
end

if ExtraFolder then
	ExtraSources = collectAudioTemplates(ExtraFolder)
end

local function addPOI(instance: Instance)
	if instance:IsA("BasePart") or instance:IsA("Model") then
		POIs[instance] = true
	end
end

local function removePOI(instance: Instance)
	POIs[instance] = nil
end

for _, instance in CollectionService:GetTagged(POIConfig.Tag) do
	addPOI(instance)
end
CollectionService:GetInstanceAddedSignal(POIConfig.Tag):Connect(addPOI)
CollectionService:GetInstanceRemovedSignal(POIConfig.Tag):Connect(removePOI)

local function getPOIDistance(instance: Instance, position: Vector3): number?
	local success, frame, size = pcall(function()
		if instance:IsA("BasePart") then
			return instance.CFrame, instance.Size
		elseif instance:IsA("Model") then
			return instance:GetBoundingBox()
		end

		return nil, nil
	end)
	if not success or typeof(frame) ~= "CFrame" or typeof(size) ~= "Vector3" then return nil end

	local padding = POIConfig.Detection.Padding
	local radius = instance:GetAttribute("Radius")
	if type(radius) == "number" and radius > 0 then
		padding += radius
	end

	local localPosition = frame:PointToObjectSpace(position)
	local outsideX = math.max(math.abs(localPosition.X) - size.X / 2 - padding, 0)
	local outsideZ = math.max(math.abs(localPosition.Z) - size.Z / 2 - padding, 0)
	local lowerY = -size.Y / 2 - POIConfig.Detection.BelowWindow
	local upperY = size.Y / 2 + POIConfig.Detection.HeightWindow
	local outsideY = math.max(lowerY - localPosition.Y, localPosition.Y - upperY, 0)

	return Vector3.new(outsideX, outsideY, outsideZ).Magnitude
end

local function refreshLocationGains(root: BasePart?)
	table.clear(LocationGains)
	if not root then return end

	local fadeDistance = math.max(LocationConfig.FadeDistance, 0.01)
	for instance in POIs do
		if not instance:IsDescendantOf(workspace) or not TracksByName[instance.Name] then continue end

		local distance = getPOIDistance(instance, root.Position)
		if not distance or distance > fadeDistance then continue end

		local gain = 1 - distance / fadeDistance
		LocationGains[instance.Name] = math.max(LocationGains[instance.Name] or 0, gain)
	end
end

local function startLocationTrack(track: LocationTrack)
	local playback = AudioService:Play2D(track.Template, true, AMBIENCE_BUS, { Volume = 0 })
	track.Playback = playback
	playback.Destroying:Once(function()
		if track.Playback == playback then
			track.Playback = nil
		end
	end)
end

local function stopLocationTrack(track: LocationTrack)
	local playback = track.Playback
	track.Playback = nil
	track.Gain = 0
	if playback then
		AudioService:StopSound(playback)
	end
end

local function updateLocationTrack(track: LocationTrack, deltaTime: number, blocked: boolean)
	local targetGain = if blocked then 0 else LocationGains[track.Name] or 0
	if targetGain > 0 and not track.Playback then
		startLocationTrack(track)
	end

	local fadeTime = math.max(LocationConfig.FadeTime, 0.01)
	local maxChange = deltaTime / fadeTime
	if targetGain > track.Gain then
		track.Gain = math.min(targetGain, track.Gain + maxChange)
	else
		track.Gain = math.max(targetGain, track.Gain - maxChange)
	end

	local playback = track.Playback
	if playback and playback.Parent then
		playback.Volume = track.BaseVolume * Bus.Volume * math.max(LocationConfig.Volume, 0) * track.Gain
	elseif playback then
		track.Playback = nil
	end

	if track.Playback and targetGain <= 0 and track.Gain <= 0.001 then
		stopLocationTrack(track)
	end
end

local function getNextExtraInterval(): number
	local minimum = math.max(ExtraConfig.MinInterval, 0)
	local maximum = math.max(ExtraConfig.MaxInterval, minimum)
	return Randomizer:NextNumber(minimum, maximum)
end

local function playRandomExtra()
	if #ExtraSources == 0 then return end

	local index = Randomizer:NextInteger(1, #ExtraSources)
	if #ExtraSources > 1 and index == LastExtraIndex then
		index = index % #ExtraSources + 1
	end
	LastExtraIndex = index
	AudioService:Play2D(ExtraSources[index], false, AMBIENCE_BUS)
end

ExtraCountdown = getNextExtraInterval()

RunService.Heartbeat:Connect(function(deltaTime: number)
	local root = CharacterService.GetAliveRoot(Players.LocalPlayer)
	local blocked = not root
		or DeathScreenService:IsVisible()
		or LobbyService:IsPlayerOnLobbyFloor()
		or AmbienceService:IsSuppressed()

	updateAccumulator += deltaTime
	if blocked or updateAccumulator >= AmbienceConfig.UpdateInterval then
		updateAccumulator = 0
		refreshLocationGains(if blocked then nil else root)
	end

	for _, track in LocationTracks do
		updateLocationTrack(track, deltaTime, blocked)
	end

	if #ExtraSources == 0 then return end

	ExtraCountdown -= deltaTime
	if ExtraCountdown > 0 then return end

	ExtraCountdown = getNextExtraInterval()
	if not blocked then
		playRandomExtra()
	end
end)

return AmbienceExtrasService
