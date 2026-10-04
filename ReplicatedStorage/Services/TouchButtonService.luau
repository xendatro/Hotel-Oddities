local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TouchButtonConfig = require(ReplicatedStorage.Configs.TouchButtonConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local TouchButtonService = {}

if not RunService:IsClient() then
	return TouchButtonService
end

type Painted = {
	Stroke: UIStroke,
	Active: boolean,
}

local COLORS = TouchButtonConfig.Colors
local TRANSPARENCY = TouchButtonConfig.Transparency

local area: Frame? = nil
local painted: { [TextButton]: Painted } = {}

local function refreshArea()
	if area then
		area.Visible = UserInputService.PreferredInput == Enum.PreferredInput.Touch
	end
end

local function getArea(): Frame
	if area then return area end

	local screenGui = GuiBuilderService.CreateScreenGui(TouchButtonConfig.Gui, TouchButtonConfig.DisplayOrder)
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets

	local frame = Instance.new("Frame")
	frame.Name = "Area"
	frame.AnchorPoint = Vector2.new(1, 1)
	frame.Position = UDim2.fromScale(1, 1)
	frame.Size = UDim2.fromScale(1, 1)
	frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	area = frame
	refreshArea()
	return frame
end

local function paint(button: TextButton, state: Painted)
	local active = state.Active
	button.BackgroundColor3 = if active then COLORS.ActiveBackground else COLORS.Background
	button.BackgroundTransparency = if active then 0 else TRANSPARENCY.Background
	button.TextColor3 = if active then COLORS.ActiveText else COLORS.Text
	state.Stroke.Color = if active then COLORS.ActiveStroke else COLORS.Stroke
	state.Stroke.Transparency = if active then 0 else TRANSPARENCY.Stroke
end

function TouchButtonService:IsAvailable(): boolean
	return UserInputService.TouchEnabled
end

function TouchButtonService:Create(slot: string, text: string): TextButton
	local centre = TouchButtonConfig.Slots[slot]
	assert(centre, `TouchButtonService: no slot named {slot} in TouchButtonConfig.Slots`)

	local button = Instance.new("TextButton")
	button.Name = slot
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(1 + centre.X, 1 + centre.Y)
	button.Size = UDim2.fromScale(TouchButtonConfig.Size, TouchButtonConfig.Size)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = text
	button.TextScaled = true
	button.TextWrapped = false
	button.FontFace = Font.fromEnum(TouchButtonConfig.Font)

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = button

	local bounds = Instance.new("UISizeConstraint")
	bounds.MinSize = Vector2.new(TouchButtonConfig.MinPixels, TouchButtonConfig.MinPixels)
	bounds.MaxSize = Vector2.new(TouchButtonConfig.MaxPixels, TouchButtonConfig.MaxPixels)
	bounds.Parent = button

	local textSize = Instance.new("UITextSizeConstraint")
	textSize.MinTextSize = TouchButtonConfig.MinTextSize
	textSize.MaxTextSize = TouchButtonConfig.MaxTextSize
	textSize.Parent = button

	local padding = Instance.new("UIPadding")
	local inset = UDim.new(TouchButtonConfig.TextPadding, 0)
	padding.PaddingLeft = inset
	padding.PaddingRight = inset
	padding.Parent = button

	GuiBuilderService.Corner(button, TouchButtonConfig.CornerRadius)
	local stroke = GuiBuilderService.Stroke(button, COLORS.Stroke, TouchButtonConfig.StrokeThickness)

	local state = { Stroke = stroke, Active = false }
	painted[button] = state
	paint(button, state)

	button.Destroying:Connect(function()
		painted[button] = nil
	end)
	button.Parent = getArea()

	return button
end

function TouchButtonService:SetActive(button: TextButton, active: boolean)
	local state = painted[button]
	if not state or state.Active == active then return end
	state.Active = active
	paint(button, state)
end

UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(refreshArea)

return TouchButtonService
