local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MinigameBase = {}
MinigameBase.__index = MinigameBase

export type Theme = {
	Font: Enum.Font,
	Background: Color3,
	Panel: Color3,
	Grid: Color3,
	Primary: Color3,
	Accent: Color3,
	Danger: Color3,
	Text: Color3,
	TextDim: Color3,
}

export type Api = {
	Complete: () -> (),
	Fail: ((reason: string?) -> ())?,
	Theme: Theme,
	Sound: ((name: string, pitch: number?) -> ())?,
}

MinigameBase.Directions = {
	[Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.D] = { 1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 },
} :: { [Enum.KeyCode]: { number } }

local PAD_LAYOUT = {
	{ Text = "W", Column = 1, Row = 0, X = 0, Y = -1 },
	{ Text = "A", Column = 0, Row = 1, X = -1, Y = 0 },
	{ Text = "S", Column = 1, Row = 1, X = 0, Y = 1 },
	{ Text = "D", Column = 2, Row = 1, X = 1, Y = 0 },
}

function MinigameBase.extend(id: string, title: string, supportsReset: boolean)
	local class = setmetatable({}, { __index = MinigameBase })
	class.__index = class
	class.Id = id
	class.Title = title
	class.SupportsReset = supportsReset
	return class
end

local function setUpConnections(self)
	self.Connections = {} :: { RBXScriptConnection }
end

function MinigameBase.new(root: Frame, api: Api, class: any?)
	local self = setmetatable({}, class or MinigameBase)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme
	self.State = "playing"
	self.Completed = false
	self.MessageUntil = 0
	self.MessageTime = 1
	self.Heartbeat = nil :: RBXScriptConnection?

	setUpConnections(self)

	return self
end

function MinigameBase:Track(connection: RBXScriptConnection): RBXScriptConnection
	table.insert(self.Connections, connection)
	return connection
end

function MinigameBase:NewFrame(parent: Instance, color: Color3, strokeColor: Color3?, thickness: number?): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent

	if strokeColor then
		local stroke = Instance.new("UIStroke")
		stroke.Color = strokeColor
		stroke.Thickness = thickness or 3
		stroke.Parent = frame
	end

	return frame
end

function MinigameBase:NewLabel(parent: Instance, text: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = self.Theme.Font
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = self.Theme.Text
	label.Parent = parent
	return label
end

function MinigameBase:NewButton(parent: Instance, text: string): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = self.Theme.Panel
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = self.Theme.Font
	button.Text = text
	button.TextSize = 26
	button.TextColor3 = self.Theme.Primary
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = self.Theme.Primary
	stroke.Thickness = 3
	stroke.Parent = button

	return button
end

function MinigameBase:AddStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function MinigameBase:BuildBoardFrame(aspectRatio: number, options: { Position: UDim2?, Size: UDim2?, Clip: boolean? }?): Frame
	local board = self:NewFrame(self.Root, self.Theme.Background, self.Theme.Primary, 4)
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = (options and options.Position) or UDim2.fromScale(0.5, 0.45)
	board.Size = (options and options.Size) or UDim2.fromScale(0.92, 0.66)
	if options and options.Clip then
		board.ClipsDescendants = true
	end

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = aspectRatio
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = board

	self.Board = board
	return board
end

function MinigameBase:BuildStatusBar(leftName: string, initialMessage: string): (TextLabel, TextLabel)
	local status = self:NewFrame(self.Root, self.Theme.Panel, self.Theme.Grid, 3)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, 0.06)
	status.Size = UDim2.fromScale(0.92, 0.08)

	local left = self:NewLabel(status, "", 24)
	left.Name = leftName
	left.TextXAlignment = Enum.TextXAlignment.Left
	left.Position = UDim2.fromScale(0.03, 0)
	left.Size = UDim2.fromScale(0.45, 1)

	local message = self:NewLabel(status, initialMessage, 22)
	message.Name = "Message"
	message.TextColor3 = self.Theme.TextDim
	message.TextXAlignment = Enum.TextXAlignment.Right
	message.Position = UDim2.fromScale(0.52, 0)
	message.Size = UDim2.fromScale(0.45, 1)
	self.MessageLabel = message

	return left, message
end

function MinigameBase:BuildDirectionalPad(callback: (x: number, y: number) -> ())
	local pad = Instance.new("Frame")
	pad.Name = "Pad"
	pad.BackgroundTransparency = 1
	pad.AnchorPoint = Vector2.new(0.5, 0.5)
	pad.Position = UDim2.fromScale(0.5, 0.885)
	pad.Size = UDim2.fromScale(0.3, 0.2)
	pad.Parent = self.Root

	for _, entry in PAD_LAYOUT do
		local button = self:NewButton(pad, entry.Text)
		button.Position = UDim2.fromScale(entry.Column / 3 + 0.02, entry.Row / 2 + 0.04)
		button.Size = UDim2.fromScale(1 / 3 - 0.04, 1 / 2 - 0.08)
		self:Track(button.Activated:Connect(function()
			callback(entry.X, entry.Y)
		end))
	end
end

function MinigameBase:ConnectDirectionalKeys(callback: (x: number, y: number) -> ())
	self:Track(UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local direction = MinigameBase.Directions[input.KeyCode]
		if direction then
			callback(direction[1], direction[2])
		end
	end))
end

function MinigameBase:ConnectKeys(map: { [Enum.KeyCode]: any }, callback: (value: any) -> ())
	self:Track(UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local value = map[input.KeyCode]
		if value ~= nil then
			callback(value)
		end
	end))
end

function MinigameBase:PlaySound(name: string, pitch: number?)
	if self.Api.Sound then
		self.Api.Sound(name, pitch)
	end
end

function MinigameBase:FailRun(reason: string?)
	if self.Api.Fail then
		self.Api.Fail(reason)
	end
end

function MinigameBase:Climb(count: number, total: number): number
	return math.clamp((count - 1) / math.max(total - 1, 1), 0, 1)
end

function MinigameBase:Say(text: string, color: Color3)
	self.MessageLabel.Text = text
	self.MessageLabel.TextColor3 = color
	self.MessageUntil = os.clock() + self.MessageTime
end

function MinigameBase:StepMessage()
	if self.MessageUntil > 0 and os.clock() >= self.MessageUntil then
		self.MessageUntil = 0
		self:IdleMessage()
	end
end

function MinigameBase:IdleMessage() end

function MinigameBase:StartHeartbeat(callback: (deltaTime: number) -> ())
	self.Heartbeat = RunService.Heartbeat:Connect(callback)
end

function MinigameBase:StopHeartbeat()
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end
end

function MinigameBase:ClampedSavedNumber(saved: any, field: string, minimum: number, maximum: number): number?
	if type(saved) == "table" and type(saved[field]) == "number" then
		return math.clamp(math.floor(saved[field]), minimum, maximum)
	end
	return nil
end

function MinigameBase:Win()
	if self.Completed then return end
	self.Completed = true
	self.State = "won"

	if self.MessageLabel then
		self:Say("BREACHED", self.Theme.Accent)
	end
	self:StopHeartbeat()
	self.Api.Complete()
end

function MinigameBase:OnDestroy() end

function MinigameBase:Destroy()
	self.State = "dead"
	self:StopHeartbeat()

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	self:OnDestroy()
	self.Root:ClearAllChildren()
end

return MinigameBase
