local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaserCameraConfig = require(ReplicatedStorage.Configs.ChaserCameraConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)

local ChaserCameraService = {}

function ChaserCameraService:IsActive(): boolean
	return false
end

if not FLAGS.Enemies then
	return ChaserCameraService
end

local ENEMY_TAG = "Enemy"
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"
local RENDER_JOB = "ChaserCameraShake"
local localPlayer = Players.LocalPlayer
local intensity = 0

local function getProximityIntensity(distance: number): number
	local range = ChaserCameraConfig.EffectRange
	local fullIntensityDistance = ChaserCameraConfig.FullIntensityDistance
	local normalized = math.clamp(
		(range - distance) / (range - fullIntensityDistance),
		0,
		1
	)
	return normalized * normalized * (3 - 2 * normalized)
end

local function isChasingLocalPlayer(instance: Instance): boolean
	return instance:IsA("Model")
		and instance:GetAttribute(CHASE_TARGET_ATTRIBUTE) == localPlayer.UserId
end

local function getChasingModels(): {Instance}
	return TagService:GetTaggedOfPredicate(ENEMY_TAG, isChasingLocalPlayer)
end

function ChaserCameraService:IsActive(): boolean
	return intensity > 0.02 or #getChasingModels() > 0
end

local function getTargetIntensity(position: Vector3): number
	local targetIntensity = 0
	for _, instance in getChasingModels() do
		local model = instance :: Model
		local distance = (model:GetPivot().Position - position).Magnitude
		targetIntensity = math.max(targetIntensity, getProximityIntensity(distance))
	end
	return targetIntensity
end

local function render(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local targetIntensity = if humanoid and humanoid.Health > 0
		then getTargetIntensity(camera.CFrame.Position)
		else 0
	local speed = if targetIntensity > intensity
		then ChaserCameraConfig.FadeInSpeed
		else ChaserCameraConfig.FadeOutSpeed
	intensity += (targetIntensity - intensity) * (1 - math.exp(-speed * deltaTime))
	if intensity < 1e-3 then
		intensity = 0
		return
	end

	local time = os.clock() * ChaserCameraConfig.Frequency
	local position = Vector3.new(
		math.noise(time, 11) * ChaserCameraConfig.PositionAmplitude,
		math.noise(time, 23) * ChaserCameraConfig.PositionAmplitude,
		math.noise(time, 37) * ChaserCameraConfig.PositionAmplitude * 0.35
	) * intensity
	local rotation = math.rad(ChaserCameraConfig.RotationAmplitude) * intensity
	camera.CFrame *= CFrame.new(position) * CFrame.Angles(
		math.noise(time, 47) * rotation,
		math.noise(time, 59) * rotation * 0.7,
		math.noise(time, 71) * rotation
	)
end

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 3, render)

return ChaserCameraService
