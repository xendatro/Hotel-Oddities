local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SpeedBoostRenderService = {}

if not RunService:IsClient() then
	return SpeedBoostRenderService
end

local player = Players.LocalPlayer
local offset = Instance.new("NumberValue")
offset.Name = "SpeedBoostFovOffset"

local color = Instance.new("ColorCorrectionEffect")
color.Name = "SpeedBoostColor"
color.Enabled = false
color.Parent = Lighting

local BIND_NAME = "SpeedBoostCameraFov"
local bound = false
local lastCamera: Camera? = nil
local lastApplied = 0
local effectTween: Tween? = nil
local colorTween: Tween? = nil
local tweenVersion = 0

local function restoreCamera()
	if lastCamera and lastCamera.Parent and lastApplied ~= 0 then
		lastCamera.FieldOfView -= lastApplied
	end
	lastCamera = nil
	lastApplied = 0
end

local function render()
	local camera = workspace.CurrentCamera
	if camera ~= lastCamera then
		restoreCamera()
		lastCamera = camera
	end
	if not camera then return end

	-- Remove the offset written last frame before adding this frame's value. That makes the effect
	-- compose with camera scripts and interface tweens instead of fighting their chosen base FOV.
	local base = camera.FieldOfView - lastApplied
	lastApplied = offset.Value
	camera.FieldOfView = base + lastApplied
end

local function setBound(value: boolean)
	if bound == value then return end
	bound = value
	if value then
		RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Camera.Value + 2, render)
	else
		RunService:UnbindFromRenderStep(BIND_NAME)
		restoreCamera()
	end
end

local function refresh()
	local target = player:GetAttribute("SpeedBoostFov")
	if type(target) ~= "number" then target = 0 end
	target = math.max(target, 0)

	tweenVersion += 1
	local version = tweenVersion
	if effectTween then effectTween:Cancel() end
	if colorTween then colorTween:Cancel() end

	if target > 0 then
		setBound(true)
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
		setBound(false)
		color.Enabled = false
	end)
end

player:GetAttributeChangedSignal("SpeedBoostFov"):Connect(refresh)
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if bound then render() end
end)

refresh()

return SpeedBoostRenderService
