--- The prompt under the cursor: what key opens the drawer being looked at, and whether that would
--- open it or shut it. It lives in the Cursor ScreenGui beside the dot, appears only while a drawer
--- is actually in front of the player, and slides up into place rather than blinking on.
---
--- Touch has no cursor to rest on anything, so it gets a ContextActionService button instead --
--- bound while a drawer is focused and dropped the moment it is not, so the screen stays clear.
---
--- Nothing here decides anything. DrawerService works out what is being looked at and what pressing
--- the key would do; this draws it and passes the press back.

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

--- Layout --------------------------------------------------------------------------------------

--- Lays the prompt out around a badge of the given width: padding, badge, gap, word, padding. The
--- word gets a fixed column rather than one measured from itself, so Open becoming Close moves
--- nothing -- a prompt that resized itself under the cursor read as a wobble. The group is the pill
--- plus the room its outline needs, since a CanvasGroup clips to its own bounds.
local function layout(keyWidth: number)
	local left = UI.PillPaddingLeft + keyWidth + UI.KeyGap
	local width = left + UI.TextWidth + UI.PillPaddingRight

	container.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	pill.Size = UDim2.fromOffset(width, UI.PillHeight)
	key.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	action.Position = UDim2.new(0, left, 0.5, 0)
	action.Size = UDim2.fromOffset(UI.TextWidth, UI.KeySize)
end

--- Input ---------------------------------------------------------------------------------------

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

--- Drawing -------------------------------------------------------------------------------------

local alpha = 0
--- What the prompt is currently saying. Held so the words are not rewritten every frame, and so a
--- drawer sliding shut under the cursor updates them the moment its state flips.
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

	-- Only ever rewritten for a drawer that is actually there. A prompt fading out should finish
	-- saying what it said, rather than flipping to Open as the drawer it is leaving slides shut.
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
	-- Rises the last few pixels into place as it fades in, and drops back out the same way.
	container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + math.round((1 - alpha) * UI.Rise))
	scale.Scale = UI.EnterScale + (1 - UI.EnterScale) * alpha

	keyScale.Scale = 1 - UI.PressScale * pressFlash
	key.BackgroundColor3 = COLORS.Key:Lerp(COLORS.KeyPressed, pressFlash)
end

layout(UI.KeySize)
RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Last.Value, render)

return DrawerUIService
