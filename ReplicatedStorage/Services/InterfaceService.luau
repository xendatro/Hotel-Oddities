local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PresetConfig = require(ReplicatedStorage.Frameworks.xenterface.Config.PresetConfig)

local InterfaceService = {}

if not RunService:IsClient() then
	return InterfaceService
end

local PAGE_GROUP = "Main"
local PAGE_PRESET = PresetConfig.HotelPage
local EFFECT_PRESET = PresetConfig.HotelEffects
local CLOSE_TIME = PAGE_PRESET.CloseTime

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
	motionPreset
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
			targetScale = motionPreset.PressScale
			targetRotation = baseRotation - motionPreset.HoverTilt * 0.5
		elseif state.Hovered then
			targetScale = motionPreset.HoverScale
			targetRotation = baseRotation + motionPreset.HoverTilt
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
		pose(motionPreset.HoverTime, motionPreset.HoverStyle, motionPreset.HoverDirection)
	end)

	button.MouseLeave:Connect(function()
		state.Hovered = false
		state.Pressed = false
		pose(motionPreset.ReleaseTime, motionPreset.ReleaseStyle, motionPreset.ReleaseDirection)
	end)

	button.MouseButton1Down:Connect(function()
		state.Pressed = true
		pose(motionPreset.PressTime, motionPreset.PressStyle, motionPreset.PressDirection)
	end)

	button.MouseButton1Up:Connect(function()
		state.Pressed = false
		pose(motionPreset.ReleaseTime, motionPreset.ReleaseStyle, motionPreset.ReleaseDirection)
	end)
end

local function getMotionPreset(instance: Instance, fallbackName: string)
	local presetName = instance:GetAttribute("MotionPreset")
	if type(presetName) ~= "string" then
		presetName = fallbackName
	end

	local preset = PresetConfig[presetName]
	assert(preset, `Unknown interface motion preset '{presetName}' on {instance:GetFullName()}`)
	return preset
end

local function wireSideButton(instance: Instance)
	if not instance:IsA("GuiButton") or not instance:IsDescendantOf(playerGui) then return end
	wireMotion(instance, instance, getMotionPreset(instance, "HotelSideButton"))
end

local function wireCloseButton(instance: Instance)
	if not instance:IsA("GuiButton") or not instance:IsDescendantOf(playerGui) then return end

	local visual: GuiObject = instance
	if instance:GetAttribute("ScaleParent") == true and instance.Parent:IsA("GuiObject") then
		visual = instance.Parent
	end
	wireMotion(instance, visual, getMotionPreset(instance, "HotelCloseButton"))

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
		TweenInfo.new(EFFECT_PRESET.Time, EFFECT_PRESET.Style, EFFECT_PRESET.Direction),
		{ Size = open and EFFECT_PRESET.Blur or 0 }
	)
	blurTween:Play()

	local camera = workspace.CurrentCamera
	if not camera then return end
	if open then
		baseFov = camera.FieldOfView
	end

	local targetFov = open
		and math.max(EFFECT_PRESET.MinimumFieldOfView, (baseFov or camera.FieldOfView) - EFFECT_PRESET.FieldOfViewOffset)
		or (baseFov or camera.FieldOfView)
	fovTween = TweenService:Create(
		camera,
		TweenInfo.new(EFFECT_PRESET.Time, EFFECT_PRESET.Style, EFFECT_PRESET.Direction),
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
		TweenInfo.new(EFFECT_PRESET.Time, EFFECT_PRESET.Style, EFFECT_PRESET.Direction),
		{ FieldOfView = math.max(EFFECT_PRESET.MinimumFieldOfView, camera.FieldOfView - EFFECT_PRESET.FieldOfViewOffset) }
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

--- Opening a page from code ------------------------------------------------------------------------

--- Opens one of `pageNames` as though its side button had been pressed, so the page arrives through
--- the same controller, the same animation and the same blur as every other way in. Nothing else
--- should be setting `ScreenGui.Enabled` by hand -- a page switched on behind the controller's back
--- is one the controller still believes is closed, and the next press of anything closes it without
--- animating.
---
--- Exists for the index, which the game opens on the player's behalf after a death has taught them
--- something. Everything else here is driven by a button the player pressed.
function InterfaceService:Open(pageId: string)
	if not pageGuis[pageId] then
		warn(("[InterfaceService] No page named %q to open."):format(pageId))
		return
	end
	controller:Fire(pageId)
end

function InterfaceService:Close()
	controller:Fire("")
end

--- The page currently open, or an empty string while none is.
function InterfaceService:GetActive(): string
	return controller.Active
end

return InterfaceService
