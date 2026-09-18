local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaserCameraConfig = require(ReplicatedStorage.Configs.ChaserCameraConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MathService = require(ReplicatedStorage.Services.MathService)
local ShakeService = require(ReplicatedStorage.Services.ShakeService)
local WalkSoundService = require(ReplicatedStorage.Services.WalkSoundService)

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
local MAD_GUEST_FOV_NAME = "MadGuestChase"
local SHAKE_EPSILON = 0.01
local MAD_GUEST = ChaserCameraConfig.MadGuest

local localPlayer = Players.LocalPlayer
local ceilingFovIntensity = 0
local fovChaseAssumedUntil = 0
local Shakes: { [string]: { Rumble: any, Intensity: number } } = {}
local madGuestFov = 0
local madGuestPunch = 0
local lastMadGuestSting = -math.huge
local madGuestChasing: { [Model]: boolean } = {}
local chasingMadGuests: { [Model]: boolean } = {}

local cameraEvent = CommunicationService.Get("Enemies", "CeilingDwellerCamera") :: RemoteEvent

local function getProximityIntensity(distance: number, range: number, fullIntensityDistance: number): number
	return MathService.Smoothstep((range - distance) / math.max(range - fullIntensityDistance, 1e-3))
end

local function isChasingLocalPlayer(instance: Instance): boolean
	return instance:IsA("Model")
		and instance:GetAttribute(CHASE_TARGET_ATTRIBUTE) == localPlayer.UserId
end

local EnemyModels: { [Instance]: boolean } = {}

CollectionService:GetInstanceAddedSignal(ENEMY_TAG):Connect(function(instance)
	EnemyModels[instance] = true
end)

CollectionService:GetInstanceRemovedSignal(ENEMY_TAG):Connect(function(instance)
	EnemyModels[instance] = nil
end)

for _, instance in CollectionService:GetTagged(ENEMY_TAG) do
	EnemyModels[instance] = true
end

local function isCameraEffectModel(instance: Instance): boolean
	if not instance:IsA("Model") then return false end

	local enemyId = instance:GetAttribute(ENEMY_ID_ATTRIBUTE)
	local entry = if enemyId then ChaserCameraConfig.ChaseShakes[enemyId] else nil
	return isChasingLocalPlayer(instance) or entry ~= nil and entry.AllPlayers == true
end

function ChaserCameraService:IsActive(): boolean
	return ceilingFovIntensity > 0.02 or madGuestFov > 0.02 or next(Shakes) ~= nil
end

local function playMadGuestSting()
	local now = os.clock()
	if now - lastMadGuestSting < MAD_GUEST.Sting.Cooldown then return end
	lastMadGuestSting = now
	madGuestPunch = 1
	ShakeService:Create({ ID = "MadGuestSting", ShakeType = "Once", Preset = MAD_GUEST.Sting.Shake })
	local template = AudioService:FindTemplate(MAD_GUEST.Sting.Sound)
	if template then
		AudioService:Play2D(template, false, "SFX")
	end
end

local function updateMadGuestFov(chased: boolean, proximity: number, deltaTime: number): number
	local fov = MAD_GUEST.FieldOfView
	local target = if chased then fov.Far + (fov.Near - fov.Far) * proximity else 0
	local speed = if target > madGuestFov then fov.Speed else ChaserCameraConfig.FovReleaseSpeed
	madGuestFov += (target - madGuestFov) * MathService.ExpAlpha(speed, deltaTime)
	if madGuestFov < 1e-3 then madGuestFov = 0 end
	madGuestPunch *= 1 - MathService.ExpAlpha(MAD_GUEST.Punch.DecaySpeed, deltaTime)
	if madGuestPunch < 1e-3 then madGuestPunch = 0 end
	return madGuestFov + madGuestPunch * MAD_GUEST.Punch.FieldOfView
end

local mimicChaseSince: { [Model]: number } = {}
local shakeTargets: { [string]: number } = {}
local chasingMimics: { [Model]: boolean } = {}

local function isCeilingDweller(instance: Instance): boolean
	local enemyId = instance:GetAttribute(ENEMY_ID_ATTRIBUTE)
	return enemyId == CEILING_DWELLER_ID
		or enemyId == MIMIC_ID
		or instance.Name == "Ceiling Dweller"
end

local function render(deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local alive = CharacterService.GetAliveHumanoid(localPlayer) ~= nil
	if not alive then
		ceilingFovIntensity = 0
		fovChaseAssumedUntil = 0
		table.clear(mimicChaseSince)
		madGuestPunch = 0
	end

	local targetCeilingChase = 0
	table.clear(shakeTargets)
	table.clear(chasingMimics)
	table.clear(chasingMadGuests)
	local madGuestProximity = 0
	if alive then
		for instance in EnemyModels do
			if not isCameraEffectModel(instance) then continue end
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
			local pivot = CharacterService.GetStreamedPivot(model)
			local distance = if pivot then (pivot.Position - camera.CFrame.Position).Magnitude else math.huge
			if chasingLocalPlayer and enemyId == MAD_GUEST.EnemyId then
				chasingMadGuests[model] = true
				if not madGuestChasing[model] then
					playMadGuestSting()
				end
				local proximity = getProximityIntensity(distance, MAD_GUEST.Range, MAD_GUEST.FullIntensityDistance)
				madGuestProximity = math.max(madGuestProximity, proximity)
			end

			local entry = if enemyId then ChaserCameraConfig.ChaseShakes[enemyId] else nil
			if entry and pivot and (chasingLocalPlayer or entry.AllPlayers == true) then
				local proximity = getProximityIntensity(distance, entry.Range, entry.FullIntensityDistance)
				local target = entry.Intensity * proximity ^ (entry.FalloffExponent or 1)
				shakeTargets[enemyId] = math.max(shakeTargets[enemyId] or 0, target)
			end
		end
	end

	table.clear(madGuestChasing)
	for model in chasingMadGuests do
		madGuestChasing[model] = true
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
	ceilingFovIntensity += (targetCeilingChase - ceilingFovIntensity) * MathService.ExpAlpha(fovSpeed, deltaTime)
	if ceilingFovIntensity < 1e-3 then ceilingFovIntensity = 0 end

	local offset = ceilingFovIntensity * ChaserCameraConfig.CeilingDweller.FieldOfView
	CameraFovService:SetOffset(FOV_OFFSET_NAME, offset)
	CameraFovService:SetOffset(
		MAD_GUEST_FOV_NAME,
		updateMadGuestFov(next(madGuestChasing) ~= nil, madGuestProximity, deltaTime)
	)

	for enemyId, target in shakeTargets do
		if target > 0 and not Shakes[enemyId] then
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
		shake.Intensity += (target - shake.Intensity) * MathService.ExpAlpha(speed, deltaTime)

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

WalkSoundService:OnEnemyStep(function(model: Model)
	if not madGuestChasing[model] then return end
	local camera = workspace.CurrentCamera
	local pivot = CharacterService.GetStreamedPivot(model)
	if not camera or not pivot then return end

	local stomp = MAD_GUEST.Stomp
	local distance = (pivot.Position - camera.CFrame.Position).Magnitude
	local proximity = getProximityIntensity(distance, stomp.Range, stomp.FullIntensityDistance)
	if proximity > 0 then
		ShakeService:Impulse(stomp, proximity)
	end
end)

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 3, render)

return ChaserCameraService
