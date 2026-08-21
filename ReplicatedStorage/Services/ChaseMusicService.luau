local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaseMusicConfig = require(ReplicatedStorage.Configs.ChaseMusicConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)
local AudioService = require(ReplicatedStorage.Services.AudioService)

local ChaseMusicService = {}

if not RunService:IsClient() or not FLAGS.Enemies then
	return ChaseMusicService
end

local ENEMY_TAG = "Enemy"
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local MUSIC_BUS = "Music"
local SILENCE_EPSILON = 0.005

local localPlayer = Players.LocalPlayer
local Templates = ReplicatedStorage:WaitForChild("Sounds")

local Tracks: { [string]: { Player: AudioPlayer, Volume: number } } = {}
local WarnedMissing: { [string]: boolean } = {}

local function isHunting(instance: Instance): boolean
	return instance:IsA("Model") and instance:GetAttribute(CHASE_TARGET_ATTRIBUTE) ~= nil
end

local function getProximityFactor(distance: number, range: number, fullVolumeDistance: number): number
	local normalized = math.clamp((range - distance) / math.max(range - fullVolumeDistance, 1e-3), 0, 1)
	return normalized * normalized * (3 - 2 * normalized)
end

local function findTemplate(name: string): Instance?
	for _, candidate in Templates:GetChildren() do
		if candidate.Name ~= name then continue end
		local source = if candidate:IsA("AudioPlayer") then candidate else candidate:FindFirstChild("Player")
		if source and source:IsA("AudioPlayer") and source.Asset ~= "" then
			return candidate
		end
	end
	return nil
end

local function getTargetVolumes(position: Vector3): { [string]: number }
	local targets: { [string]: number } = {}

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 then return targets end

	for _, instance in TagService:GetTaggedOfPredicate(ENEMY_TAG, isHunting) do
		local model = instance :: Model
		local entry = ChaseMusicConfig.Enemies[model:GetAttribute(ENEMY_ID_ATTRIBUTE)]
		if not entry then continue end
		local layers = if entry[1] then entry else { entry }

		local distance = (model:GetPivot().Position - position).Magnitude
		for _, layer in layers do
			if distance <= layer.Range then
				local volume = layer.Volume * getProximityFactor(distance, layer.Range, layer.FullVolumeDistance)
				targets[layer.Template] = math.max(targets[layer.Template] or 0, volume)
			end
		end
	end
	return targets
end

local function startTrack(template: string): boolean
	local source = findTemplate(template)
	if not source then
		if not WarnedMissing[template] then
			WarnedMissing[template] = true
			warn(`ChaseMusicService: no template "{template}" in ReplicatedStorage.Sounds; staying silent`)
		end
		return false
	end

	Tracks[template] = {
		Player = AudioService:Play2D(source, true, MUSIC_BUS, { Volume = 0 }),
		Volume = 0,
	}
	return true
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local targets = getTargetVolumes(camera.CFrame.Position)
	for template in targets do
		if not Tracks[template] and not startTrack(template) then
			targets[template] = nil
		end
	end

	local bus = AudioService:GetBus(MUSIC_BUS)
	for template, track in Tracks do
		local goal = targets[template] or 0
		local speed = if goal > track.Volume then ChaseMusicConfig.FadeInSpeed else ChaseMusicConfig.FadeOutSpeed
		track.Volume += (goal - track.Volume) * (1 - math.exp(-speed * deltaTime))

		if goal <= 0 and track.Volume < SILENCE_EPSILON then
			Tracks[template] = nil
			AudioService:StopSound(track.Player)
		else
			track.Player.Volume = track.Volume * bus.Volume
		end
	end
end)

return ChaseMusicService
