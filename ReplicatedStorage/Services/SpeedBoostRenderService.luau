local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SpeedBoostRenderService = {}

if not RunService:IsClient() then
	return SpeedBoostRenderService
end

local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)

local player = Players.LocalPlayer

local offset = Instance.new("NumberValue")
offset.Name = "SpeedBoostFovOffset"

local color = Instance.new("ColorCorrectionEffect")
color.Name = "SpeedBoostColor"
color.Enabled = false
color.Parent = Lighting

local effectTween: Tween? = nil
local colorTween: Tween? = nil
local tweenVersion = 0

local function refresh()
	local target = player:GetAttribute("SpeedBoostFov")
	if type(target) ~= "number" then target = 0 end
	target = math.max(target, 0)

	tweenVersion += 1
	local version = tweenVersion
	if effectTween then effectTween:Cancel() end
	if colorTween then colorTween:Cancel() end

	if target > 0 then
		color.Enabled = true
	end

	local entering = target > offset.Value
	local info = TweenInfo.new(
		entering and 0.35 or 0.6,
		entering and Enum.EasingStyle.Back or Enum.EasingStyle.Quad,
		entering and Enum.EasingDirection.Out or Enum.EasingDirection.InOut
	)
	effectTween = TweenService:Create(offset, info, { Value = target })
	colorTween = TweenService:Create(color, info, {
		Saturation = target * 0.012,
		Contrast = target * 0.0025,
		TintColor = Color3.fromRGB(255, 255 - math.round(target * 0.7), 255 - math.round(target * 1.8)),
	})
	effectTween:Play()
	colorTween:Play()

	effectTween.Completed:Once(function()
		if tweenVersion ~= version or target > 0 then return end
		color.Enabled = false
	end)
end

offset.Changed:Connect(function(value)
	CameraFovService:SetOffset("SpeedBoost", value)
end)

player:GetAttributeChangedSignal("SpeedBoostFov"):Connect(refresh)

refresh()

return SpeedBoostRenderService
