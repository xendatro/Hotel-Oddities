local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EyeConfig = require(ReplicatedStorage.Configs.EyeConfig)

local EyeEncounterEffectService = {}

if not RunService:IsClient() then
	return EyeEncounterEffectService
end

local AmbienceService = require(ReplicatedStorage.Services.AmbienceService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)

local color = Instance.new("ColorCorrectionEffect")
color.Name = "EyeEncounterColor"
color.Enabled = false
color.Parent = Lighting

local intensity = 0
local seenTime = 0

local function numberEffectValue(neutral: number, startValue: number, maxValue: number): number
	if intensity <= EyeConfig.EncounterStartIntensity then
		local alpha = intensity / EyeConfig.EncounterStartIntensity
		return neutral + (startValue - neutral) * alpha
	end

	local alpha = (intensity - EyeConfig.EncounterStartIntensity)
		/ (1 - EyeConfig.EncounterStartIntensity)
	return startValue + (maxValue - startValue) * alpha
end

local function colorEffectValue(startValue: Color3, maxValue: Color3): Color3
	if intensity <= EyeConfig.EncounterStartIntensity then
		return Color3.new(1, 1, 1):Lerp(startValue, intensity / EyeConfig.EncounterStartIntensity)
	end

	local alpha = (intensity - EyeConfig.EncounterStartIntensity)
		/ (1 - EyeConfig.EncounterStartIntensity)
	return startValue:Lerp(maxValue, alpha)
end

local function apply()
	color.Enabled = intensity > 1e-3
	color.TintColor = colorEffectValue(EyeConfig.EncounterTintStart, EyeConfig.EncounterTintMax)
	color.Saturation = numberEffectValue(
		0,
		EyeConfig.EncounterSaturationStart,
		EyeConfig.EncounterSaturationMax
	)
	color.Brightness = numberEffectValue(
		0,
		EyeConfig.EncounterBrightnessStart,
		EyeConfig.EncounterBrightnessMax
	)
	color.Contrast = numberEffectValue(
		0,
		EyeConfig.EncounterContrastStart,
		EyeConfig.EncounterContrastMax
	)
	CameraFovService:SetOffset(
		"EyeEncounter",
		numberEffectValue(0, EyeConfig.EncounterFovStart, EyeConfig.EncounterFovMax)
	)
	AmbienceService:SetEyeMuffle(
		numberEffectValue(1, EyeConfig.EncounterMuffleStart, EyeConfig.EncounterMuffleMax)
	)
end

function EyeEncounterEffectService:Update(seen: boolean, deltaTime: number)
	if seen then
		seenTime += deltaTime
	else
		seenTime = 0
	end

	local target = if seen
		then math.max(
			EyeConfig.EncounterStartIntensity,
			math.clamp(seenTime / EyeConfig.EncounterRampTime, 0, 1)
		)
		else 0
	local speed = if target > intensity
		then EyeConfig.EncounterInSpeed
		else EyeConfig.EncounterOutSpeed
	local alpha = 1 - math.exp(-speed * deltaTime)
	intensity += (target - intensity) * alpha
	if math.abs(target - intensity) < 1e-3 then
		intensity = target
	end

	apply()
end

return EyeEncounterEffectService
