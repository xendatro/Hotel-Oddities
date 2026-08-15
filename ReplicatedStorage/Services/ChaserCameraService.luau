local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaserCameraConfig = require(ReplicatedStorage.Configs.ChaserCameraConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local TagService = require(ReplicatedStorage.Services.TagService)
local AudioService = require(ReplicatedStorage.Services.AudioService)

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
local RENDER_JOB = "ChaserCameraShake"
local localPlayer = Players.LocalPlayer
local chaserIntensity = 0
local ceilingIntensity = 0
local transient = nil :: { Phase: string, StartedAt: number, Duration: number }?
local lastCamera: Camera? = nil
local lastFovOffset = 0

local cameraEvent = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("CeilingDwellerCamera") :: RemoteEvent

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
	return chaserIntensity > 0.02 or ceilingIntensity > 0.02 or transient ~= nil or #getChasingModels() > 0
end

local function isCeilingDweller(instance: Instance): boolean
	return instance:GetAttribute(ENEMY_ID_ATTRIBUTE) == CEILING_DWELLER_ID
		or instance.Name == "Ceiling Dweller"
end

local function getTargetIntensities(position: Vector3): (number, number)
	local targetChaser = 0
	local targetCeiling = 0
	for _, instance in getChasingModels() do
		local model = instance :: Model
		local distance = (model:GetPivot().Position - position).Magnitude
		local proximity = getProximityIntensity(distance)
		if isCeilingDweller(model) then
			targetCeiling = math.max(targetCeiling, proximity)
		else
			targetChaser = math.max(targetChaser, proximity)
		end
	end
	return targetChaser, targetCeiling
end

local function render(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if camera ~= lastCamera then
		lastCamera = camera
		lastFovOffset = 0
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local targetChaser, targetCeiling = 0, 0
	if humanoid and humanoid.Health > 0 then
		targetChaser, targetCeiling = getTargetIntensities(camera.CFrame.Position)
	end
	local chaserSpeed = if targetChaser > chaserIntensity
		then ChaserCameraConfig.FadeInSpeed
		else ChaserCameraConfig.FadeOutSpeed
	local ceilingSpeed = if targetCeiling > ceilingIntensity
		then ChaserCameraConfig.FadeInSpeed
		else ChaserCameraConfig.FadeOutSpeed
	chaserIntensity += (targetChaser - chaserIntensity) * (1 - math.exp(-chaserSpeed * deltaTime))
	ceilingIntensity += (targetCeiling - ceilingIntensity) * (1 - math.exp(-ceilingSpeed * deltaTime))
	if chaserIntensity < 1e-3 then chaserIntensity = 0 end
	if ceilingIntensity < 1e-3 then ceilingIntensity = 0 end

	local time = os.clock() * ChaserCameraConfig.Frequency
	local rotationAmplitude = math.rad(ChaserCameraConfig.RotationAmplitude) * chaserIntensity
	local ceilingConfig = ChaserCameraConfig.CeilingDweller
	local phase = transient
	local transientFov = 0
	local transientPosition = Vector3.zero
	local transientRotation = 0
	if phase then
		local elapsed = os.clock() - phase.StartedAt
		if elapsed >= phase.Duration then
			transient = nil
		else
			local progress = math.clamp(elapsed / phase.Duration, 0, 1)
			local eased = progress * progress * (3 - 2 * progress)
			local dropConfig = ChaserCameraConfig.CeilingDwellerDrop
			if phase.Phase == "Open" then
				transientFov = dropConfig.OpeningFieldOfView * eased
			elseif phase.Phase == "Drop" then
				transientFov = dropConfig.FallStartFieldOfView
					+ (dropConfig.FallEndFieldOfView - dropConfig.FallStartFieldOfView) * eased
			else
				local wobble = math.sin(elapsed * 34) * math.exp(-elapsed * 5)
				transientFov = dropConfig.ScreamFieldOfView + wobble * 3
				transientPosition = Vector3.new(wobble, math.sin(elapsed * 28) * 0.5 * wobble, 0)
					* dropConfig.ScreamShake
				transientRotation = math.rad(dropConfig.ScreamRotation) * wobble
			end
		end
	end

	local totalFovOffset = ceilingIntensity * ceilingConfig.FieldOfView + transientFov
	if lastFovOffset ~= 0 then
		camera.FieldOfView -= lastFovOffset
	end
	lastFovOffset = totalFovOffset
	camera.FieldOfView += totalFovOffset

	if chaserIntensity < 1e-3 and ceilingIntensity < 1e-3 and not transient then return end
	local chaserPosition = Vector3.new(
		math.noise(time, 11) * ChaserCameraConfig.PositionAmplitude,
		math.noise(time, 23) * ChaserCameraConfig.PositionAmplitude,
		math.noise(time, 37) * ChaserCameraConfig.PositionAmplitude * 0.35
	) * chaserIntensity
	local ceilingPosition = Vector3.new(
		math.noise(time, 101) * ceilingConfig.PositionAmplitude,
		math.noise(time, 103) * ceilingConfig.PositionAmplitude,
		math.noise(time, 107) * ceilingConfig.PositionAmplitude * 0.35
	) * ceilingIntensity
	local rotation = rotationAmplitude
	local ceilingRotation = math.rad(ceilingConfig.RotationAmplitude) * ceilingIntensity
	local position = chaserPosition + ceilingPosition + transientPosition
	camera.CFrame *= CFrame.new(position) * CFrame.Angles(
		math.noise(time, 47) * rotation + math.noise(time, 109) * ceilingRotation + transientRotation,
		math.noise(time, 59) * rotation * 0.7 + math.noise(time, 113) * ceilingRotation * 0.7,
		math.noise(time, 71) * rotation + math.noise(time, 127) * ceilingRotation
	)
end

cameraEvent.OnClientEvent:Connect(function(phase: string, duration: number?)
	if phase ~= "Open" and phase ~= "Drop" and phase ~= "Scream" then return end
	local configuredDuration = if phase == "Scream"
		then ChaserCameraConfig.CeilingDwellerDrop.ScreamDuration
		else duration or 0.5
	transient = {
		Phase = phase,
		StartedAt = os.clock(),
		Duration = math.max(configuredDuration, 0.05),
	}
	if phase == "Scream" then
		AudioService:Play2DSound("Scream", false, "SFX", { Volume = 2 })
	end
end)

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 3, render)

return ChaserCameraService
