local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SistersVertigoService = {}

if not RunService:IsClient() then
	return SistersVertigoService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local ShakeService = require(ReplicatedStorage.Services.ShakeService)
local SistersConfig = require(ReplicatedStorage.Configs.SistersConfig)

local Config = SistersConfig.Vertigo
local EFFECT_NAME = "SistersVertigo"

local screenGui = GuiBuilderService.CreateScreenGui(EFFECT_NAME, 1000, true)

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.BackgroundColor3 = Config.FlashColor
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1, 1)
flash.ZIndex = 1000
flash.Parent = screenGui

type Ring = {
	Frame: Frame,
	Stroke: UIStroke,
}

local rings: { Ring } = {}
for index = 1, Config.RingCount do
	local frame = Instance.new("Frame")
	frame.Name = "Ring" .. index
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 1001
	frame.Parent = screenGui

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.DominantAxis = Enum.DominantAxis.Height
	aspect.Parent = frame

	GuiBuilderService.Corner(frame, UDim.new(1, 0))
	local stroke = GuiBuilderService.Stroke(frame, Config.RingColor, Config.RingThickness)
	stroke.Transparency = 1

	rings[index] = { Frame = frame, Stroke = stroke }
end

local colorCorrection = Instance.new("ColorCorrectionEffect")
colorCorrection.Name = EFFECT_NAME .. "Color"
colorCorrection.Saturation = 0
colorCorrection.Contrast = 0
colorCorrection.TintColor = Color3.new(1, 1, 1)
colorCorrection.Parent = Lighting

local blur = Instance.new("BlurEffect")
blur.Name = EFFECT_NAME .. "Blur"
blur.Size = 0
blur.Parent = Lighting

local token = 0
local tweens: { Tween } = {}

local function play(instance: Instance, tweenInfo: TweenInfo, goal: { [string]: any }): Tween
	local tween = TweenService:Create(instance, tweenInfo, goal)
	table.insert(tweens, tween)
	tween:Play()
	return tween
end

local function cancelTweens()
	for _, tween in tweens do
		tween:Cancel()
	end
	table.clear(tweens)
end

local function release(time: number)
	local info = TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	play(colorCorrection, info, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
	play(blur, info, { Size = 0 })
	CameraFovService:TweenOffset(EFFECT_NAME, 0, info)
end

local function playRing(ring: Ring, delayTime: number, myToken: number)
	task.delay(delayTime, function()
		if myToken ~= token then return end
		ring.Frame.Size = UDim2.fromScale(Config.RingStartScale, Config.RingStartScale)
		ring.Stroke.Transparency = 1 - Config.RingOpacity
		local info = TweenInfo.new(Config.RingTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		play(ring.Frame, info, { Size = UDim2.fromScale(Config.RingEndScale, Config.RingEndScale) })
		play(ring.Stroke, info, { Transparency = 1 })
	end)
end

function SistersVertigoService:Play(leadTime: number?)
	token += 1
	local myToken = token
	cancelTweens()

	flash.BackgroundTransparency = Config.FlashTransparency
	play(
		flash,
		TweenInfo.new(Config.FlashOutTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)

	blur.Size = Config.Blur
	play(blur, TweenInfo.new(Config.BlurOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = 0 })

	local drainInfo = TweenInfo.new(Config.DrainInTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	play(colorCorrection, drainInfo, {
		Saturation = Config.Saturation,
		Contrast = Config.Contrast,
		TintColor = Config.TintColor,
	})
	CameraFovService:TweenOffset(EFFECT_NAME, Config.FovPull, drainInfo)

	for index, ring in rings do
		playRing(ring, (index - 1) * Config.RingInterval, myToken)
	end

	if Config.Shake then
		ShakeService:Create({ ID = EFFECT_NAME, ShakeType = "Once", Preset = Config.Shake })
	end
	if Config.Sound then
		AudioService:Play2DSound(Config.Sound, false, "SFX")
	end

	task.delay(leadTime or Config.LeadTime, function()
		if myToken ~= token then return end
		release(Config.ReleaseTime)
	end)
end

function SistersVertigoService:Stop()
	token += 1
	cancelTweens()
	flash.BackgroundTransparency = 1
	for _, ring in rings do
		ring.Stroke.Transparency = 1
	end
	release(Config.StopTime)
end

return SistersVertigoService
