local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local POIConfig = require(ReplicatedStorage.Configs.POIConfig)
local AmbienceService = require(ReplicatedStorage.Services.AmbienceService)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local POIAudioService = {}

if not RunService:IsClient() then
	return POIAudioService
end

local Sound = POIConfig.Sound
local Remotes = POIConfig.Remotes

local EnterRemote = CommunicationService.Get(Remotes.Folder, Remotes.Enter) :: RemoteEvent
local OccupancyRemote = CommunicationService.Get(Remotes.Folder, Remotes.Occupancy) :: RemoteEvent

local playback: (AudioPlayer | Sound)? = nil

function POIAudioService:IsPlaying(): boolean
	if not playback or not playback.Parent then return false end
	return playback.IsPlaying
end

function POIAudioService:Play()
	if POIAudioService:IsPlaying() then return end

	local template = AudioService:FindTemplate(Sound.Name)
	if not template then return end

	playback = AudioService:Play2D(template, false, Sound.Bus)
end

EnterRemote.OnClientEvent:Connect(function(name: any)
	if type(name) ~= "string" or name == "" then return end
	POIAudioService:Play()
end)

OccupancyRemote.OnClientEvent:Connect(function(active: any)
	if type(active) ~= "boolean" then return end
	AmbienceService:SetPOIActive(active)
end)

OccupancyRemote:FireServer()

return POIAudioService
