local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local POIConfig = require(ReplicatedStorage.Configs.POIConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local POIAudioService = {}

if not RunService:IsClient() then
	return POIAudioService
end

local Sound = POIConfig.Sound
local Remotes = POIConfig.Remotes

local EnterRemote = CommunicationService.Get(Remotes.Folder, Remotes.Enter) :: RemoteEvent

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

return POIAudioService
