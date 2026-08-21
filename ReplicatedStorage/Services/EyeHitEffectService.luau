local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local EyeConfig = require(ReplicatedStorage.Configs.EyeConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local EyeHitEffectService = {}

if not RunService:IsClient() or not FLAGS.Enemies then
	return EyeHitEffectService
end

local player = Players.LocalPlayer
local eyeHit = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("EyeHit") :: RemoteEvent

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EyeHitEffects"
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 1000
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.BackgroundColor3 = EyeConfig.HitFlashColor
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1, 1)
flash.ZIndex = 1000
flash.Parent = screenGui

local flashToken = 0
local fovToken = 0

local function pulseFlash()
	flashToken += 1
	local token = flashToken
	local current = flash.BackgroundTransparency
	flash.BackgroundTransparency = math.min(current, EyeConfig.HitFlashTransparency)

	local brighten = TweenService:Create(
		flash,
		TweenInfo.new(EyeConfig.HitFlashInTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = EyeConfig.HitFlashTransparency }
	)
	brighten.Completed:Once(function()
		if token ~= flashToken then return end
		TweenService:Create(
			flash,
			TweenInfo.new(EyeConfig.HitFlashOutTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ BackgroundTransparency = 1 }
		):Play()
	end)
	brighten:Play()
end

local function pulseFov()
	fovToken += 1
	local token = fovToken
	CameraFovService:TweenOffset(
		"EyeHit",
		EyeConfig.HitFov,
		TweenInfo.new(EyeConfig.HitFovInTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	)

	task.delay(EyeConfig.HitFovInTime, function()
		if token ~= fovToken then return end
		CameraFovService:TweenOffset(
			"EyeHit",
			0,
			TweenInfo.new(EyeConfig.HitFovOutTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		)
	end)
end

eyeHit.OnClientEvent:Connect(function()
	pulseFlash()
	pulseFov()
end)

return EyeHitEffectService
