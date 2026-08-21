local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DrawerUIService = {}

if not RunService:IsClient() then
	return DrawerUIService
end

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local DrawerService = require(ReplicatedStorage.Services.DrawerService)

local UI = DrawerConfig.UI
local COLORS = UI.Colors
local INPUT = DrawerConfig.Input
local ACTION = INPUT.TouchAction
local RENDER_JOB = "DrawerPrompt"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local cursor = playerGui:WaitForChild("Cursor", 30)
local container = cursor and cursor:WaitForChild(UI.Container, 30) :: CanvasGroup?
if not container then
	warn(`DrawerUIService: no {UI.Container} under the Cursor gui; the drawer prompt will not draw`)
	return DrawerUIService
end

local scale = container:WaitForChild("Scale") :: UIScale
local pill = container:WaitForChild("Pill") :: Frame
local key = pill:WaitForChild("Key") :: Frame
local keyScale = key:WaitForChild("Scale") :: UIScale
local keyLabel = key:WaitForChild("Label") :: TextLabel
local action = pill:WaitForChild("Action") :: TextLabel

local function layout(keyWidth: number)
	local left = UI.PillPaddingLeft + keyWidth + UI.KeyGap
	local width = left + UI.TextWidth + UI.PillPaddingRight

	container.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	pill.Size = UDim2.fromOffset(width, UI.PillHeight)
	key.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	action.Position = UDim2.new(0, left, 0.5, 0)
	action.Size = UDim2.fromOffset(UI.TextWidth, UI.KeySize)
end

local pressFlash = 0
local touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local usingGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
local bound = false

local function onAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and DrawerService:Toggle() then
		pressFlash = 1
	end
	return Enum.ContextActionResult.Pass
end

local function setBound(shouldBind: boolean, open: boolean)
	if shouldBind == bound then
		if bound and touching then
			ContextActionService:SetTitle(ACTION, (if open then UI.CloseText else UI.OpenText):upper())
		end
		return
	end
	bound = shouldBind

	if not shouldBind then
		ContextActionService:UnbindAction(ACTION)
		return
	end

	ContextActionService:BindAction(ACTION, onAction, touching, table.unpack(INPUT.Keys))
	if not touching then return end

	ContextActionService:SetTitle(ACTION, (if open then UI.CloseText else UI.OpenText):upper())
	ContextActionService:SetPosition(ACTION, INPUT.TouchButtonPosition)
	local button = ContextActionService:GetButton(ACTION)
	if button then
		button.Size = INPUT.TouchButtonSize
	end
end

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	if inputType == Enum.UserInputType.Touch then
		touching = true
	elseif inputType.Name:find("Gamepad") then
		touching = false
		usingGamepad = true
	elseif inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
	then
		touching = false
		usingGamepad = false
	end
end)

local alpha = 0
local shownOpen: boolean? = nil
local shownGamepad: boolean? = nil

local function render(deltaTime: number)
	local focused = DrawerService:GetFocused()
	local open = focused ~= nil and DrawerService:IsOpen(focused)

	setBound(focused ~= nil, open)

	local target = if focused and not touching then 1 else 0
	if alpha < target then
		alpha = math.min(alpha + deltaTime / UI.FadeInTime, target)
	elseif alpha > target then
		alpha = math.max(alpha - deltaTime / UI.FadeOutTime, target)
	end

	pressFlash *= math.exp(-UI.PressDecay * deltaTime)
	if pressFlash < 1e-3 then pressFlash = 0 end

	container.Visible = alpha > 0
	if alpha <= 0 then return end

	if focused and open ~= shownOpen then
		shownOpen = open
		action.Text = if open then UI.CloseText else UI.OpenText
	end
	if usingGamepad ~= shownGamepad then
		shownGamepad = usingGamepad
		local text = if usingGamepad then INPUT.GamepadLabel else INPUT.KeyboardLabel
		keyLabel.Text = text
		layout(if #text <= 1 then UI.KeySize else UI.KeyWideSize)
	end

	container.GroupTransparency = 1 - alpha
	container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + math.round((1 - alpha) * UI.Rise))
	scale.Scale = UI.EnterScale + (1 - UI.EnterScale) * alpha

	keyScale.Scale = 1 - UI.PressScale * pressFlash
	key.BackgroundColor3 = COLORS.Key:Lerp(COLORS.KeyPressed, pressFlash)
end

layout(UI.KeySize)
RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value, render)

return DrawerUIService
