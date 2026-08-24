local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local EyeConfig = require(ReplicatedStorage.Configs.EyeConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local MathService = require(ReplicatedStorage.Services.MathService)

local EyeHitEffectService = {}

if not RunService:IsClient() or not FLAGS.Enemies then
	return EyeHitEffectService
end

local eyeHit = CommunicationService.Get("Enemies", "EyeHit") :: RemoteEvent

local screenGui = GuiBuilderService.CreateScreenGui("EyeHitEffects", 1000, true)

local flash = Instance.new("Frame")
flash.Name = "Flash"
flash.BackgroundColor3 = EyeConfig.HitFlashColor
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.Size = UDim2.fromScale(1, 1)
flash.ZIndex = 1000
flash.Parent = screenGui

local function makeEdge(name: string, anchor: Vector2, position: UDim2, rotation: number): Frame
	local edge = Instance.new("Frame")
	edge.Name = name
	edge.AnchorPoint = anchor
	edge.Position = position
	edge.BackgroundColor3 = Color3.new(0, 0, 0)
	edge.BackgroundTransparency = 1
	edge.BorderSizePixel = 0
	edge.ZIndex = 999
	edge.Parent = screenGui

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = rotation
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = edge

	return edge
end

local gazeTop = makeEdge("GazeTop", Vector2.zero, UDim2.fromScale(0, 0), 90)
local gazeBottom = makeEdge("GazeBottom", Vector2.new(0, 1), UDim2.fromScale(0, 1), -90)
local gazeLeft = makeEdge("GazeLeft", Vector2.zero, UDim2.fromScale(0, 0), 0)
local gazeRight = makeEdge("GazeRight", Vector2.new(1, 0), UDim2.fromScale(1, 0), 180)

local function makeBlinkLid(name: string, anchor: Vector2, position: UDim2): Frame
	local lid = Instance.new("Frame")
	lid.Name = name
	lid.AnchorPoint = anchor
	lid.Position = position
	lid.Size = UDim2.fromScale(1, 0)
	lid.BackgroundColor3 = Color3.new(0, 0, 0)
	lid.BorderSizePixel = 0
	lid.ZIndex = 1001
	lid.Parent = screenGui
	return lid
end

local blinkTop = makeBlinkLid("BlinkTop", Vector2.zero, UDim2.fromScale(0, 0))
local blinkBottom = makeBlinkLid("BlinkBottom", Vector2.new(0, 1), UDim2.fromScale(0, 1))

local blur = Instance.new("BlurEffect")
blur.Name = "EyeHitBlur"
blur.Size = 0
blur.Parent = Lighting

local flashToken = 0
local fovToken = 0
local blinkToken = 0
local blurTween = nil :: Tween?
local blinkTweens: { Tween } = {}
local gazeTime = 0
local gazeIntensity = 0

local function cancelBlinkTweens()
	for _, tween in blinkTweens do
		tween:Cancel()
	end
	table.clear(blinkTweens)
end

local function playBlink()
	blinkToken += 1
	local token = blinkToken
	cancelBlinkTweens()

	local closeInfo = TweenInfo.new(EyeConfig.HitBlinkCloseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local closed = UDim2.fromScale(1, EyeConfig.HitBlinkCoverage)
	local topClose = TweenService:Create(blinkTop, closeInfo, { Size = closed })
	local bottomClose = TweenService:Create(blinkBottom, closeInfo, { Size = closed })
	blinkTweens = { topClose, bottomClose }
	topClose:Play()
	bottomClose:Play()

	topClose.Completed:Once(function(playbackState: Enum.PlaybackState)
		if token ~= blinkToken or playbackState ~= Enum.PlaybackState.Completed then return end
		task.delay(EyeConfig.HitBlinkHoldTime, function()
			if token ~= blinkToken then return end
			local openInfo = TweenInfo.new(
				EyeConfig.HitBlinkOpenTime,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			)
			local opened = UDim2.fromScale(1, 0)
			local topOpen = TweenService:Create(blinkTop, openInfo, { Size = opened })
			local bottomOpen = TweenService:Create(blinkBottom, openInfo, { Size = opened })
			blinkTweens = { topOpen, bottomOpen }
			topOpen:Play()
			bottomOpen:Play()
		end)
	end)
end

local function pulseBlur()
	if blurTween then blurTween:Cancel() end
	blur.Size = math.max(blur.Size, EyeConfig.HitBlur)
	blurTween = TweenService:Create(
		blur,
		TweenInfo.new(EyeConfig.HitBlurOutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = 0 }
	)
	blurTween:Play()
end

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

function EyeHitEffectService:UpdateGaze(strength: number, deltaTime: number)
	if strength > 0 then
		gazeTime += deltaTime
	else
		gazeTime = 0
	end

	local ramp = MathService.Smoothstep(gazeTime / EyeConfig.GazeRampTime)
	local target = strength * ramp
	local speed = if target > gazeIntensity then EyeConfig.GazeInSpeed else EyeConfig.GazeOutSpeed
	gazeIntensity += (target - gazeIntensity) * MathService.ExpAlpha(speed, deltaTime)
	if gazeIntensity < 1e-3 then gazeIntensity = 0 end

	local pulse = 0.9 + math.sin(os.clock() * math.pi * 2 / EyeConfig.GazeRollPeriod) * 0.1
	local pressure = gazeIntensity * pulse
	local transparency = 1 - EyeConfig.GazeEdgeOpacity * pressure
	gazeTop.Size = UDim2.fromScale(1, EyeConfig.GazeLidHeight * pressure)
	gazeBottom.Size = UDim2.fromScale(1, EyeConfig.GazeLidHeight * pressure)
	gazeLeft.Size = UDim2.fromScale(EyeConfig.GazeSideWidth * pressure, 1)
	gazeRight.Size = UDim2.fromScale(EyeConfig.GazeSideWidth * pressure, 1)
	gazeTop.BackgroundTransparency = transparency
	gazeBottom.BackgroundTransparency = transparency
	gazeLeft.BackgroundTransparency = transparency
	gazeRight.BackgroundTransparency = transparency

	local camera = workspace.CurrentCamera
	if camera and gazeIntensity > 0 then
		local clock = os.clock() / EyeConfig.GazeRollPeriod
		local roll = math.rad(EyeConfig.GazeRollAngle) * gazeIntensity * math.noise(clock, 0)
		local sway = EyeConfig.GazeSwayDistance * gazeIntensity
		camera.CFrame *= CFrame.new(math.noise(0, clock) * sway, math.noise(clock, clock) * sway, 0)
			* CFrame.Angles(0, 0, roll)
	end
end

eyeHit.OnClientEvent:Connect(function()
	playBlink()
	pulseBlur()
	pulseFlash()
	pulseFov()
	AudioService:Play2DSound("EyeDamage", false, "SFX")
end)

return EyeHitEffectService
