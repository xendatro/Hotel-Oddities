local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ShopkeeperUIService = {}

if not RunService:IsClient() then
	return ShopkeeperUIService
end

local ShopkeeperConfig = require(ReplicatedStorage.Configs.ShopkeeperConfig)
local ShopkeeperService = require(ReplicatedStorage.Services.ShopkeeperService)

local UI = ShopkeeperConfig.UI
local COLORS = UI.Colors
local INPUT = ShopkeeperConfig.Input
local ACTION = INPUT.TouchAction
local PROMPT_JOB = "ShopkeeperPrompt"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local cursor = playerGui:WaitForChild("Cursor", 30)
local template = cursor and cursor:WaitForChild(UI.Container, 30)
local container: CanvasGroup? = nil

if template then
	local clone = template:Clone() :: CanvasGroup
	clone.Name = UI.Prompt
	clone.Visible = false
	clone.GroupTransparency = 1
	clone.Parent = cursor
	container = clone
else
	warn(`ShopkeeperUIService: no {UI.Container} under the Cursor gui; the shopkeeper prompt will not draw`)
	return ShopkeeperUIService
end

local scale = container:FindFirstChild("Scale") :: UIScale
local pill = container:FindFirstChild("Pill") :: Frame
local key = pill and pill:FindFirstChild("Key") :: Frame
local keyScale = key and key:FindFirstChild("Scale") :: UIScale
local keyLabel = key and key:FindFirstChild("Label") :: TextLabel
local action = pill and pill:FindFirstChild("Action") :: TextLabel

if not (scale and pill and key and keyScale and keyLabel and action) then
	warn(`ShopkeeperUIService: the {UI.Container} prompt is not shaped as expected; the shopkeeper prompt will not draw`)
	container:Destroy()
	return ShopkeeperUIService
end

local function layout(keyWidth: number, textWidth: number)
	local left = UI.PillPaddingLeft + keyWidth + UI.KeyGap
	local width = left + textWidth + UI.PillPaddingRight

	container.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	pill.Size = UDim2.fromOffset(width, UI.PillHeight)
	key.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	action.Position = UDim2.new(0, left, 0.5, 0)
	action.Size = UDim2.fromOffset(textWidth, UI.KeySize)
end

local pressFlash = 0
local touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local usingGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
local bound = false
local shownGamepad: boolean? = nil
local shownText = ""
local shownTouchTitle = ""

local function promptText(): string?
	local pageId = ShopkeeperService:GetPageId()
	return if pageId then `Open {pageId}` else nil
end

local function onAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and ShopkeeperService:Open() then
		pressFlash = 1
	end
	return Enum.ContextActionResult.Pass
end

local function setBound(shouldBind: boolean, title: string)
	if shouldBind == bound then
		if bound and touching and title ~= shownTouchTitle then
			shownTouchTitle = title
			ContextActionService:SetTitle(ACTION, title:upper())
		end
		return
	end

	bound = shouldBind
	if not shouldBind then
		shownTouchTitle = ""
		ContextActionService:UnbindAction(ACTION)
		return
	end

	ContextActionService:BindAction(ACTION, onAction, touching, table.unpack(INPUT.Keys))
	if not touching then return end

	shownTouchTitle = title
	ContextActionService:SetTitle(ACTION, title:upper())
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

local function render(deltaTime: number)
	local text = promptText()
	setBound(text ~= nil, text or "")

	local target = if text and not touching then 1 else 0
	if alpha < target then
		alpha = math.min(alpha + deltaTime / UI.FadeInTime, target)
	elseif alpha > target then
		alpha = math.max(alpha - deltaTime / UI.FadeOutTime, target)
	end

	pressFlash *= math.exp(-UI.PressDecay * deltaTime)
	if pressFlash < 1e-3 then pressFlash = 0 end

	container.Visible = alpha > 0
	if alpha <= 0 then return end

	if text and text ~= shownText then
		shownText = text
		action.Text = shownText
		layout(UI.KeySize, math.max(UI.TextWidth, #shownText * 8))
	end
	if usingGamepad ~= shownGamepad then
		shownGamepad = usingGamepad
		local keyText = if usingGamepad then INPUT.GamepadLabel else INPUT.KeyboardLabel
		keyLabel.Text = keyText
		layout(if #keyText <= 1 then UI.KeySize else UI.KeyWideSize, math.max(UI.TextWidth, #shownText * 8))
	end

	container.GroupTransparency = 1 - alpha
	container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + math.round((1 - alpha) * UI.Rise))
	scale.Scale = UI.EnterScale + (1 - UI.EnterScale) * alpha

	keyScale.Scale = 1 - UI.PressScale * pressFlash
	key.BackgroundColor3 = COLORS.Key:Lerp(COLORS.KeyPressed, pressFlash)
end

layout(UI.KeySize, UI.TextWidth)
RunService:BindToRenderStep(PROMPT_JOB, Enum.RenderPriority.Last.Value, render)

return ShopkeeperUIService
