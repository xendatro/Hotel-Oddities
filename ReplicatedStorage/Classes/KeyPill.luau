local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local MathService = require(ReplicatedStorage.Services.MathService)

local KeyPill = {}
KeyPill.__index = KeyPill

local UI = DrawerConfig.UI

local DIMMED_ALPHA = 0.42
local DIM_SPEED = 5
local KEY_TEXT_SIZE = 14
local ACTION_TEXT_SIZE = 15
local KEY_PADDING = 16
local ACTION_PADDING = 4
local CHARACTER_WIDTH = 8
local TOUCH_INSET = 5
local MEASURE_WIDTH = 2000
local SETTLED = 1e-3
local HOLD_KEY_TINT = 0.45

export type Options = {
	KeyboardLabel: string,
	GamepadLabel: string,
	Action: string,
	TouchAction: string?,
}

type Mode = "Keyboard" | "Gamepad" | "Touch"

type Parts = {
	Scale: UIScale,
	Pill: Frame,
	Key: Frame,
	KeyScale: UIScale,
	KeyLabel: TextLabel,
	Action: TextLabel,
	Hold: Frame,
	Hit: GuiButton?,
}

type Applied = {
	Alpha: number,
	Dim: number,
	Press: number,
	Hold: number,
}

export type KeyPill = typeof(setmetatable({} :: {
	Root: CanvasGroup,
	Parts: Parts?,
	KeyboardLabel: string,
	GamepadLabel: string,
	ActionText: string,
	TouchText: string?,
	Mode: Mode,
	BasePosition: UDim2,
	KeyColor: Color3,
	Alpha: number,
	Target: number,
	Dim: number,
	Dimmed: boolean,
	Press: number,
	HoldAlpha: number,
	Applied: Applied?,
	Destroyed: boolean,
	Connections: { [string]: RBXScriptConnection },
}, KeyPill))

local Measured: { [string]: number } = {}
local Waiting: { [string]: { () -> () } } = {}

local function modeFor(inputType: Enum.UserInputType): Mode?
	if inputType == Enum.UserInputType.Touch then
		return "Touch"
	end
	if inputType.Name:find("Gamepad") then
		return "Gamepad"
	end
	if inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
		or inputType == Enum.UserInputType.MouseWheel
	then
		return "Keyboard"
	end
	return nil
end

local function initialMode(): Mode
	local fromLast = modeFor(UserInputService:GetLastInputType())
	if fromLast then return fromLast end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "Gamepad"
	end
	return "Keyboard"
end

local function measure(label: TextLabel, size: number, text: string, onMeasured: () -> ()): number?
	local font = label.FontFace
	local key = `{font.Family}|{font.Weight.Name}|{font.Style.Name}|{size}|{text}`
	local cached = Measured[key]
	if cached then return cached end

	local waiters = Waiting[key]
	if waiters then
		table.insert(waiters, onMeasured)
		return nil
	end

	Waiting[key] = { onMeasured }
	task.spawn(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = font
		params.Size = size
		params.Width = MEASURE_WIDTH
		local ok, bounds = pcall(TextService.GetTextBoundsAsync, TextService, params)
		params:Destroy()

		local callbacks = Waiting[key] or {}
		Waiting[key] = nil
		if not ok or typeof(bounds) ~= "Vector2" then return end

		Measured[key] = math.ceil(bounds.X)
		for _, callback in callbacks do
			task.spawn(callback)
		end
	end)
	return nil
end

local function findParts(root: CanvasGroup): Parts?
	local scale = root:FindFirstChild("Scale")
	local pill = root:FindFirstChild("Pill")
	local key = pill and pill:FindFirstChild("Key")
	local keyScale = key and key:FindFirstChild("Scale")
	local keyLabel = key and key:FindFirstChild("Label")
	local action = pill and pill:FindFirstChild("Action")
	local hit = root:FindFirstChild("Hit")

	if not (
		scale and scale:IsA("UIScale")
		and pill and pill:IsA("Frame")
		and key and key:IsA("Frame")
		and keyScale and keyScale:IsA("UIScale")
		and keyLabel and keyLabel:IsA("TextLabel")
		and action and action:IsA("TextLabel")
	) then
		return nil
	end

	local hold = pill:FindFirstChild("Hold")
	if not hold or not hold:IsA("Frame") then
		local fill = Instance.new("Frame")
		fill.Name = "Hold"
		fill.AnchorPoint = Vector2.new(0, 0.5)
		fill.Position = UDim2.fromScale(0, 0.5)
		fill.BackgroundColor3 = UI.Colors.KeyPressed
		fill.BackgroundTransparency = UI.HoldFillTransparency
		fill.BorderSizePixel = 0
		fill.ZIndex = 0

		local pillCorner = pill:FindFirstChildOfClass("UICorner")
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if pillCorner then pillCorner.CornerRadius else UDim.new(0, 10)
		corner.Parent = fill
		fill.Parent = pill
		hold = fill
	end

	return {
		Scale = scale :: UIScale,
		Pill = pill :: Frame,
		Key = key :: Frame,
		KeyScale = keyScale :: UIScale,
		KeyLabel = keyLabel :: TextLabel,
		Action = action :: TextLabel,
		Hold = hold :: Frame,
		Hit = if hit and hit:IsA("GuiButton") then hit else nil,
	}
end

local function setUpConnections(self: KeyPill): { [string]: RBXScriptConnection }
	return {
		InputType = UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
			local mode = modeFor(inputType)
			if not mode or mode == self.Mode then return end
			self.Mode = mode
			self:_layout()
		end),
		Render = RunService.RenderStepped:Connect(function(deltaTime: number)
			self:_render(deltaTime)
		end),
	}
end

function KeyPill.new(root: CanvasGroup, options: Options): KeyPill
	local parts = findParts(root)
	if not parts then
		warn(`KeyPill: {root:GetFullName()} is not shaped like Cursor.Interact (Scale, Pill.Key.Scale, Pill.Key.Label, Pill.Action); it will not draw`)
	end

	local self = setmetatable({
		Root = root,
		Parts = parts,
		KeyboardLabel = options.KeyboardLabel,
		GamepadLabel = options.GamepadLabel,
		ActionText = options.Action,
		TouchText = options.TouchAction,
		Mode = initialMode(),
		BasePosition = root.Position,
		KeyColor = if parts then parts.Key.BackgroundColor3 else UI.Colors.Key,
		Alpha = 0,
		Target = 0,
		Dim = 0,
		Dimmed = false,
		Press = 0,
		HoldAlpha = 0,
		Applied = nil :: Applied?,
		Destroyed = false,
		Connections = {},
	}, KeyPill)

	root.GroupTransparency = 1
	root.Visible = false
	if parts then
		parts.Hold.Size = UDim2.fromScale(0, 1)
		parts.Hold.Visible = false
		self:_layout()
		self.Connections = setUpConnections(self)
	end

	return self
end

function KeyPill:_layout()
	local parts = self.Parts
	if not parts or self.Destroyed then return end

	local mode = self.Mode
	local keyShown = mode ~= "Touch"
	local keyText = if mode == "Gamepad" then self.GamepadLabel else self.KeyboardLabel
	local actionText = if mode == "Touch" then (self.TouchText or self.ActionText) else self.ActionText

	local function relayout()
		self:_layout()
	end

	local keyWidth = UI.KeySize
	if (utf8.len(keyText) or #keyText) > 1 then
		local measuredKey = measure(parts.KeyLabel, KEY_TEXT_SIZE, keyText, relayout)
		keyWidth = math.max(UI.KeyWideSize, (measuredKey or #keyText * CHARACTER_WIDTH) + KEY_PADDING)
	end

	local measuredAction = measure(parts.Action, ACTION_TEXT_SIZE, actionText, relayout)
	local textWidth = math.max(UI.TextWidth, (measuredAction or #actionText * CHARACTER_WIDTH) + ACTION_PADDING)

	local left = UI.PillPaddingLeft + (if keyShown then keyWidth + UI.KeyGap else TOUCH_INSET)
	local width = left + textWidth + UI.PillPaddingRight

	parts.KeyLabel.Text = keyText
	parts.Action.Text = actionText
	parts.Key.Visible = keyShown
	self.Root.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	parts.Pill.Size = UDim2.fromOffset(width, UI.PillHeight)
	parts.Key.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	parts.Action.Position = UDim2.new(0, left, 0.5, 0)
	parts.Action.Size = UDim2.fromOffset(textWidth, UI.KeySize)
end

function KeyPill:_render(deltaTime: number)
	local parts = self.Parts
	if not parts or self.Destroyed then return end

	local target = self.Target
	if self.Alpha < target then
		self.Alpha = math.min(self.Alpha + deltaTime / UI.FadeInTime, target)
	elseif self.Alpha > target then
		self.Alpha = math.max(self.Alpha - deltaTime / UI.FadeOutTime, target)
	end

	local dimGoal = if self.Dimmed then 1 else 0
	self.Dim += (dimGoal - self.Dim) * MathService.ExpAlpha(DIM_SPEED, deltaTime)
	if math.abs(dimGoal - self.Dim) < SETTLED then
		self.Dim = dimGoal
	end

	self.Press *= math.exp(-UI.PressDecay * deltaTime)
	if self.Press < SETTLED then
		self.Press = 0
	end

	local applied = self.Applied
	if applied
		and applied.Alpha == self.Alpha
		and applied.Dim == self.Dim
		and applied.Press == self.Press
		and applied.Hold == self.HoldAlpha
	then
		return
	end
	self.Applied = { Alpha = self.Alpha, Dim = self.Dim, Press = self.Press, Hold = self.HoldAlpha }

	local root = self.Root
	root.Visible = self.Alpha > 0
	if self.Alpha <= 0 then
		root.GroupTransparency = 1
		return
	end

	local shown = self.Alpha * (1 - (1 - DIMMED_ALPHA) * self.Dim)
	root.GroupTransparency = 1 - shown
	root.Position = self.BasePosition + UDim2.fromOffset(0, math.round((1 - self.Alpha) * UI.Rise))
	parts.Scale.Scale = UI.EnterScale + (1 - UI.EnterScale) * self.Alpha
	parts.KeyScale.Scale = 1 - UI.PressScale * self.Press
	parts.Key.BackgroundColor3 = self.KeyColor:Lerp(UI.Colors.KeyPressed, math.max(self.Press, HOLD_KEY_TINT * self.HoldAlpha))
	parts.Hold.Visible = self.HoldAlpha > 0
	parts.Hold.Size = UDim2.new(self.HoldAlpha, 0, 1, 0)
end

function KeyPill:SetVisible(visible: boolean)
	self.Target = if visible then 1 else 0
end

function KeyPill:SetAction(text: string, touchText: string?)
	local touch = if touchText ~= nil then touchText else self.TouchText
	if text == self.ActionText and touch == self.TouchText then return end
	self.ActionText = text
	self.TouchText = touch
	self:_layout()
end

function KeyPill:SetHold(alpha: number)
	self.HoldAlpha = math.clamp(alpha, 0, 1)
end

function KeyPill:Flash()
	self.Press = 1
end

function KeyPill:SetDimmed(dimmed: boolean)
	self.Dimmed = dimmed
end

function KeyPill:GetHitButton(): GuiButton?
	local parts = self.Parts
	return if parts then parts.Hit else nil
end

function KeyPill:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	local parts = self.Parts
	if parts then
		parts.Hold.Visible = false
		parts.Hold.Size = UDim2.fromScale(0, 1)
		parts.KeyScale.Scale = 1
		parts.Key.BackgroundColor3 = self.KeyColor
	end
	self.Root.GroupTransparency = 1
	self.Root.Visible = false
	self.Root.Position = self.BasePosition
end

return KeyPill
