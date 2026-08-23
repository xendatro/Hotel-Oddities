local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaserCameraConfig = require(ReplicatedStorage.Configs.ChaserCameraConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local ShakeService = require(ReplicatedStorage.Services.ShakeService)

local ChaserCameraService = {}

function ChaserCameraService:IsActive(): boolean
	return false
end

if not FLAGS.Enemies then
	return ChaserCameraService
end

local ENEMY_TAG = "Enemy"
local CHASE_TARGET_ATTRIBUTE = "ChaseTargetUserId"
local ENEMY_ID_ATTRIBUTE = "EnemyId"
local CEILING_DWELLER_ID = "CeilingDweller"
local MIMIC_ID = "Mimic"
local RENDER_JOB = "ChaserCameraEffects"
local FOV_OFFSET_NAME = "ChaserCamera"
local SHAKE_EPSILON = 0.01

local localPlayer = Players.LocalPlayer
local ceilingFovIntensity = 0
local fovChaseAssumedUntil = 0
local Shakes: { [string]: { Rumble: any, Intensity: number } } = {}

local cameraEvent = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("CeilingDwellerCamera") :: RemoteEvent

local function getProximityIntensity(distance: number, range: number, fullIntensityDistance: number): number
	local normalized = math.clamp((range - distance) / math.max(range - fullIntensityDistance, 1e-3), 0, 1)
	return normalized * normalized * (3 - 2 * normalized)
end

local function isChasingLocalPlayer(instance: Instance): boolean
	return instance:IsA("Model")
		and instance:GetAttribute(CHASE_TARGET_ATTRIBUTE) == localPlayer.UserId
end

local function getChasingModels(): {Instance}
	return TagService:GetTaggedOfPredicate(ENEMY_TAG, isChasingLocalPlayer)
end

local function getCameraEffectModels(): { Instance }
	return TagService:GetTaggedOfPredicate(ENEMY_TAG, function(instance: Instance)
		if not instance:IsA("Model") then return false end

		local enemyId = instance:GetAttribute(ENEMY_ID_ATTRIBUTE)
		local entry = if enemyId then ChaserCameraConfig.ChaseShakes[enemyId] else nil
		return isChasingLocalPlayer(instance) or entry ~= nil and entry.AllPlayers == true
	end)
end

function ChaserCameraService:IsActive(): boolean
	return ceilingFovIntensity > 0.02 or next(Shakes) ~= nil or #getCameraEffectModels() > 0
end

local mimicChaseSince: { [Model]: number } = {}

local function isCeilingDweller(instance: Instance): boolean
	local enemyId = instance:GetAttribute(ENEMY_ID_ATTRIBUTE)
	return enemyId == CEILING_DWELLER_ID
		or enemyId == MIMIC_ID
		or instance.Name == "Ceiling Dweller"
end

local function render(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local alive = humanoid ~= nil and humanoid.Health > 0

	local targetCeilingChase = 0
	local shakeTargets: { [string]: number } = {}
	local chasingMimics: { [Model]: boolean } = {}
	if alive then
		for _, instance in getCameraEffectModels() do
			local model = instance :: Model
			local chasingLocalPlayer = isChasingLocalPlayer(model)
			if chasingLocalPlayer and isCeilingDweller(model) then
				if model:GetAttribute(ENEMY_ID_ATTRIBUTE) == MIMIC_ID then
					chasingMimics[model] = true
					local since = mimicChaseSince[model] or os.clock()
					mimicChaseSince[model] = since
					if os.clock() - since >= ChaserCameraConfig.MimicFovDelay then
						targetCeilingChase = 1
					end
				else
					targetCeilingChase = 1
				end
			end

			local enemyId = model:GetAttribute(ENEMY_ID_ATTRIBUTE)
			local entry = if enemyId then ChaserCameraConfig.ChaseShakes[enemyId] else nil
			if entry and (chasingLocalPlayer or entry.AllPlayers == true) then
				local distance = (model:GetPivot().Position - camera.CFrame.Position).Magnitude
				local proximity = getProximityIntensity(distance, entry.Range, entry.FullIntensityDistance)
				local target = entry.Intensity * proximity ^ (entry.FalloffExponent or 1)
				shakeTargets[enemyId] = math.max(shakeTargets[enemyId] or 0, target)
			end
		end
	end

	for model in mimicChaseSince do
		if not chasingMimics[model] then
			mimicChaseSince[model] = nil
		end
	end

	if alive and os.clock() < fovChaseAssumedUntil then
		targetCeilingChase = 1
	end

	local fovSpeed = if targetCeilingChase > ceilingFovIntensity
		then ChaserCameraConfig.FadeInSpeed
		else ChaserCameraConfig.FovReleaseSpeed
	ceilingFovIntensity += (targetCeilingChase - ceilingFovIntensity) * (1 - math.exp(-fovSpeed * deltaTime))
	if ceilingFovIntensity < 1e-3 then ceilingFovIntensity = 0 end

	local offset = ceilingFovIntensity * ChaserCameraConfig.CeilingDweller.FieldOfView
	CameraFovService:SetOffset(FOV_OFFSET_NAME, offset)

	for enemyId in shakeTargets do
		if not Shakes[enemyId] then
			Shakes[enemyId] = {
				Rumble = ShakeService:CreateDynamicRumble(0, ChaserCameraConfig.ChaseShakes[enemyId]),
				Intensity = 0,
			}
		end
	end
	for enemyId, shake in Shakes do
		local target = shakeTargets[enemyId] or 0
		local speed = if target > shake.Intensity
			then ChaserCameraConfig.FadeInSpeed
			else ChaserCameraConfig.FadeOutSpeed
		shake.Intensity += (target - shake.Intensity) * (1 - math.exp(-speed * deltaTime))

		if target <= 0 and shake.Intensity < SHAKE_EPSILON then
			shake.Rumble:Stop()
			Shakes[enemyId] = nil
		else
			shake.Rumble:AdjustValue(shake.Intensity)
		end
	end
end

cameraEvent.OnClientEvent:Connect(function(phase: string)
	if phase == "Open" then
		ShakeService:Create({ ID = "VentOpen", ShakeType = "Once", Preset = "Jolt" })
	elseif phase == "Scream" then
		fovChaseAssumedUntil = os.clock() + 1
		ShakeService:Create({ ID = "DwellerScream", ShakeType = "Once", Preset = "Slam" })
		AudioService:Play2DSound("Scream", false, "SFX", { Volume = 2 })
	end
end)

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 3, render)

return ChaserCameraService
