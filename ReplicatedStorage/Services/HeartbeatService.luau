local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local HeartbeatConfig = require(ReplicatedStorage.Configs.HeartbeatConfig)
local MathService = require(ReplicatedStorage.Services.MathService)
local TagService = require(ReplicatedStorage.Services.TagService)

local HeartbeatService = {}

if not RunService:IsClient() or not FLAGS.Enemies then
	return HeartbeatService
end

local ENEMY_TAG = "Enemy"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local BUS = "SFX"

local localPlayer = Players.LocalPlayer

local track: { Player: AudioPlayer, Shifter: AudioPitchShifter }? = nil
local volume = 0
local rate = HeartbeatConfig.Rate.Resting
local warned = false

local function isHeartbeatEnemy(instance: Instance): boolean
	return instance:IsA("Model") and instance:GetAttribute(ENEMY_ID_ATTRIBUTE) == HeartbeatConfig.EnemyId
end

local function getNearness(): (number, boolean)
	local root = CharacterService.GetAliveRoot(localPlayer)
	if not root then return 0, false end

	local nearest = math.huge
	local pursuing = false
	for _, instance in TagService:GetTaggedOfPredicate(ENEMY_TAG, isHeartbeatEnemy) do
		local model = instance :: Model
		local distance = (model:GetPivot().Position - root.Position).Magnitude
		if distance > HeartbeatConfig.Range then continue end
		if distance < nearest then
			nearest = distance
		end
		if model:GetAttribute(HeartbeatConfig.PursuitAttribute) == true then
			pursuing = true
		end
	end
	if nearest > HeartbeatConfig.Range then return 0, false end

	local span = math.max(HeartbeatConfig.Range - HeartbeatConfig.FullDistance, 1e-3)
	return MathService.Smoothstep((HeartbeatConfig.Range - nearest) / span), pursuing
end

local function startTrack(): boolean
	local source = AudioService:FindTemplate(HeartbeatConfig.Template)
	if not source then
		if not warned then
			warned = true
			warn(`HeartbeatService: no template "{HeartbeatConfig.Template}" in ReplicatedStorage.Sounds; staying silent`)
		end
		return false
	end

	local shifter = Instance.new("AudioPitchShifter")
	shifter.Name = "Heartbeat"
	shifter.Pitch = 1
	shifter.Parent = AudioService:GetBus(BUS).Parent
	AudioService:Wire(shifter, AudioService:GetOutput())

	track = {
		Player = AudioService:Play2D(source, true, BUS, { Volume = 0 }, shifter) :: AudioPlayer,
		Shifter = shifter,
	}
	volume = 0
	rate = HeartbeatConfig.Rate.Resting
	return true
end

local function stopTrack()
	local current = track
	if not current then return end

	track = nil
	AudioService:StopSound(current.Player)
	current.Shifter:Destroy()
end

function HeartbeatService:GetNearness(): number
	return volume
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	local nearness, pursuing = getNearness()
	if nearness <= 0 and not track then return end
	if nearness > 0 and not track and not startTrack() then return end

	local current = track
	if not current then return end

	local goalVolume = if nearness > 0
		then HeartbeatConfig.Volume.Far
			+ (HeartbeatConfig.Volume.Near - HeartbeatConfig.Volume.Far) * nearness
		else 0
	local fade = if goalVolume > volume then HeartbeatConfig.FadeInSpeed else HeartbeatConfig.FadeOutSpeed
	volume += (goalVolume - volume) * MathService.ExpAlpha(fade, deltaTime)

	local goalRate = if pursuing then HeartbeatConfig.Rate.Pursuit else HeartbeatConfig.Rate.Resting
	rate += (goalRate - rate) * MathService.ExpAlpha(HeartbeatConfig.RateSpeed, deltaTime)

	if goalVolume <= 0 and volume < HeartbeatConfig.SilenceEpsilon then
		stopTrack()
		return
	end

	current.Player.Volume = volume * AudioService:GetBus(BUS).Volume
	current.Player.PlaybackSpeed = rate
	current.Shifter.Pitch = 1 / rate
end)

return HeartbeatService
