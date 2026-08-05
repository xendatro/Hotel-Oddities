local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local InterfaceService = {}

if not RunService:IsClient() then
	return InterfaceService
end

local PAGE_GROUP = "Main"
local CLOSE_TIME = 0.43
local EFFECT_TIME = 0.3
local OPEN_BLUR = 18
local OPEN_FOV_OFFSET = 8
local MIN_OPEN_FOV = 45

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local xenterface = require(ReplicatedStorage.Frameworks.xenterface)
local controller = xenterface:Controller(PAGE_GROUP)
local blur = Lighting:WaitForChild("InterfaceBlur") :: BlurEffect

local pageNames = {
	Index = "IndexGui",
	Shop = "ShopUI",
	Vip = "VipPerksUI",
	Gems = "GemsUI",
}

local pageGuis: { [string]: ScreenGui } = {}
for pageId, guiName in pageNames do
	local screenGui = playerGui:WaitForChild(guiName) :: ScreenGui
	pageGuis[pageId] = screenGui
	screenGui.Enabled = false

	local design = screenGui:WaitForChild("Design") :: GuiObject
	design.Visible = false
end

type MotionState = {
	Hovered: boolean,
	Pressed: boolean,
	ScaleTween: Tween?,
	RotationTween: Tween?,
}

local wiredButtons: { [GuiButton]: boolean } = setmetatable({}, { __mode = "k" })

local function getScale(target: GuiObject): UIScale
	local scale = target:FindFirstChild("InteractionScale")
	if scale and scale:IsA("UIScale") then
		return scale
	end

	local created = Instance.new("UIScale")
	created.Name = "InteractionScale"
	created.Scale = 1
	created.Parent = target
	return created
end

local function wireMotion(
	button: GuiButton,
	visual: GuiObject,
	hoverScale: number,
	pressScale: number,
	hoverTilt: number
)
	if wiredButtons[button] then return end
	wiredButtons[button] = true

	local scale = getScale(visual)
	local baseRotation = visual.Rotation
	local state: MotionState = {
		Hovered = false,
		Pressed = false,
		ScaleTween = nil,
		RotationTween = nil,
	}

	local function pose(duration: number, style: Enum.EasingStyle, direction: Enum.EasingDirection)
		local targetScale = 1
		local targetRotation = baseRotation
		if state.Pressed then
			targetScale = pressScale
			targetRotation = baseRotation - hoverTilt * 0.5
		elseif state.Hovered then
			targetScale = hoverScale
			targetRotation = baseRotation + hoverTilt
		end

		if state.ScaleTween then state.ScaleTween:Cancel() end
		if state.RotationTween then state.RotationTween:Cancel() end

		state.ScaleTween = TweenService:Create(
			scale,
			TweenInfo.new(duration, style, direction),
			{ Scale = targetScale }
		)
		state.RotationTween = TweenService:Create(
			visual,
			TweenInfo.new(duration, style, direction),
			{ Rotation = targetRotation }
		)
		state.ScaleTween:Play()
		state.RotationTween:Play()
	end

	button.MouseEnter:Connect(function()
		state.Hovered = true
		pose(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	end)

	button.MouseLeave:Connect(function()
		state.Hovered = false
		state.Pressed = false
		pose(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)

	button.MouseButton1Down:Connect(function()
		state.Pressed = true
		pose(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end)

	button.MouseButton1Up:Connect(function()
		state.Pressed = false
		pose(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

local function wireSideButton(instance: Instance)
	if not instance:IsA("GuiButton") or not instance:IsDescendantOf(playerGui) then return end
	wireMotion(instance, instance, 1.08, 0.9, -2)
end

local function wireCloseButton(instance: Instance)
	if not instance:IsA("GuiButton") or not instance:IsDescendantOf(playerGui) then return end

	local visual: GuiObject = instance
	if instance:GetAttribute("ScaleParent") == true and instance.Parent:IsA("GuiObject") then
		visual = instance.Parent
	end
	wireMotion(instance, visual, 1.1, 0.86, 3)

	instance.Activated:Connect(function()
		controller:Fire("", instance)
	end)
end

for _, instance in CollectionService:GetTagged("SideButton") do
	wireSideButton(instance)
end
CollectionService:GetInstanceAddedSignal("SideButton"):Connect(wireSideButton)

for _, instance in CollectionService:GetTagged("InterfaceCloseButton") do
	wireCloseButton(instance)
end
CollectionService:GetInstanceAddedSignal("InterfaceCloseButton"):Connect(wireCloseButton)

local blurTween: Tween? = nil
local fovTween: Tween? = nil
local interfaceOpen = false
local baseFov: number? = nil

local function tweenEffects(open: boolean)
	if interfaceOpen == open then return end
	interfaceOpen = open

	if blurTween then blurTween:Cancel() end
	if fovTween then fovTween:Cancel() end

	blurTween = TweenService:Create(
		blur,
		TweenInfo.new(EFFECT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = open and OPEN_BLUR or 0 }
	)
	blurTween:Play()

	local camera = workspace.CurrentCamera
	if not camera then return end
	if open then
		baseFov = camera.FieldOfView
	end

	local targetFov = open
		and math.max(MIN_OPEN_FOV, (baseFov or camera.FieldOfView) - OPEN_FOV_OFFSET)
		or (baseFov or camera.FieldOfView)
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(EFFECT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ FieldOfView = targetFov }
	)
	fovTween:Play()

	if not open then
		baseFov = nil
	end
end

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if not interfaceOpen then return end
	local camera = workspace.CurrentCamera
	if not camera then return end

	baseFov = camera.FieldOfView
	if fovTween then fovTween:Cancel() end
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(EFFECT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ FieldOfView = math.max(MIN_OPEN_FOV, camera.FieldOfView - OPEN_FOV_OFFSET) }
	)
	fovTween:Play()
end)

controller.Fired:Connect(function(data)
	local activeId = data.ActiveId
	local inactiveId = data.InactiveId
	local activeGui = pageGuis[activeId]
	local inactiveGui = pageGuis[inactiveId]

	if activeGui then
		activeGui.Enabled = true
	end

	if inactiveGui and inactiveGui ~= activeGui then
		task.delay(CLOSE_TIME + 0.04, function()
			if controller.Active ~= inactiveId then
				inactiveGui.Enabled = false
			end
		end)
	end

	tweenEffects(activeGui ~= nil)
end)

local mouseUnlockGui = Instance.new("ScreenGui")
mouseUnlockGui.Name = "MouseUnlockGui"
mouseUnlockGui.DisplayOrder = -100
mouseUnlockGui.IgnoreGuiInset = true
mouseUnlockGui.ResetOnSpawn = false
mouseUnlockGui.Enabled = false
mouseUnlockGui.Parent = playerGui

local mouseUnlockBlocker = Instance.new("ImageButton")
mouseUnlockBlocker.Name = "MouseUnlockBlocker"
mouseUnlockBlocker.BackgroundTransparency = 1
mouseUnlockBlocker.ImageTransparency = 1
mouseUnlockBlocker.AutoButtonColor = false
mouseUnlockBlocker.Active = true
mouseUnlockBlocker.Interactable = true
mouseUnlockBlocker.Modal = false
mouseUnlockBlocker.Selectable = false
mouseUnlockBlocker.Size = UDim2.fromScale(1, 1)
mouseUnlockBlocker.Parent = mouseUnlockGui

local mouseUnlocked = false
local lockedMouseBehavior = UserInputService.MouseBehavior
local lockedMouseIconEnabled = UserInputService.MouseIconEnabled

local function setMouseUnlocked(unlocked: boolean)
	if mouseUnlocked == unlocked then return end
	mouseUnlocked = unlocked

	if unlocked then
		lockedMouseBehavior = UserInputService.MouseBehavior
		lockedMouseIconEnabled = UserInputService.MouseIconEnabled
		mouseUnlockGui.Enabled = true
		mouseUnlockBlocker.Modal = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		mouseUnlockBlocker.Modal = false
		mouseUnlockGui.Enabled = false
		UserInputService.MouseBehavior = lockedMouseBehavior
		UserInputService.MouseIconEnabled = lockedMouseIconEnabled
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= Enum.KeyCode.Q then return end
	setMouseUnlocked(not mouseUnlocked)
end)

return InterfaceService
