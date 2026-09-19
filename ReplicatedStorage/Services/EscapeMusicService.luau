local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local EscapeMusicConfig = require(ReplicatedStorage.Configs.EscapeMusicConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MathService = require(ReplicatedStorage.Services.MathService)
local TagService = require(ReplicatedStorage.Services.TagService)

local EscapeMusicService = {}

if not RunService:IsClient() then
	return EscapeMusicService
end

local localPlayer = Players.LocalPlayer
local exitUnlocked = false
local receivedProgress = false
local track: AudioPlayer? = nil
local volume = 0
local warnedMissing = false

local function isExitElevator(instance: Instance): boolean
	return instance:IsA("Model") and instance:GetAttribute(ElevatorConfig.TypeAttribute) == ElevatorConfig.ExitType
end

local function nearestExitDistance(position: Vector3): number?
	local nearest: number? = nil
	for _, instance in TagService:GetTaggedOfPredicate(ElevatorConfig.Tag, isExitElevator) do
		local pivot = CharacterService.GetStreamedPivot(instance :: Model)
		if not pivot then continue end
		local distance = (pivot.Position - position).Magnitude
		if not nearest or distance < nearest then nearest = distance end
	end
	return nearest
end

local function targetVolume(): number
	if not exitUnlocked then return 0 end

	local position = CharacterService.GetPosition(localPlayer)
	if not position or not CharacterService.GetAliveHumanoid(localPlayer) then return 0 end

	local distance = nearestExitDistance(position)
	if not distance or distance > EscapeMusicConfig.Range then return 0 end

	local span = math.max(EscapeMusicConfig.Range - EscapeMusicConfig.FullVolumeDistance, 1e-3)
	local closeness = MathService.Smoothstep((EscapeMusicConfig.Range - distance) / span)
	return EscapeMusicConfig.Volume * closeness
end

local function startTrack(): boolean
	local template = AudioService:FindTemplate(EscapeMusicConfig.Template)
	if not template then
		if not warnedMissing then
			warnedMissing = true
			warn(`EscapeMusicService: no template "{EscapeMusicConfig.Template}" in ReplicatedStorage.Sounds; staying silent`)
		end
		return false
	end

	track = AudioService:Play2D(template, true, EscapeMusicConfig.Bus, { Volume = 0 })
	volume = 0
	return true
end

local function stopTrack()
	if not track then return end
	AudioService:StopSound(track)
	track = nil
	volume = 0
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	local goal = targetVolume()
	if goal <= 0 and not track then return end
	if goal > 0 and not track and not startTrack() then return end

	local current = track
	if not current then return end

	local speed = if goal > volume then EscapeMusicConfig.FadeInSpeed else EscapeMusicConfig.FadeOutSpeed
	volume += (goal - volume) * MathService.ExpAlpha(speed, deltaTime)

	if goal <= 0 and volume < EscapeMusicConfig.SilenceEpsilon then
		stopTrack()
		return
	end

	current.Volume = volume * AudioService:GetBus(EscapeMusicConfig.Bus).Volume
end)

task.spawn(function()
	local sync = CommunicationService.Get(ComputerConfig.Remotes.Folder, ComputerConfig.Remotes.Sync)
	sync.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		receivedProgress = true
		exitUnlocked = payload.ExitUnlocked == true
	end)
	repeat
		sync:FireServer()
		task.wait(EscapeMusicConfig.SyncRetryInterval)
	until receivedProgress
end)

return EscapeMusicService
