local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local COLUMNS = 13
local ROWS = 9
local GOAL_ROW = 1
local START_ROW = ROWS
local MEDIAN_ROW = 5
local CROSSINGS_TO_WIN = 2
local HOP_COOLDOWN = 0.1
local HIT_FORGIVENESS = 0.26
local MESSAGE_TIME = 0.8
local LENGTH_SCALE = 0.55

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

type LaneDefinition = {
	Row: number,
	Direction: number,
	Speed: number,
	Length: number,
	Gap: number,
	Phase: number,
}

type Lane = {
	Row: number,
	Direction: number,
	Speed: number,
	Length: number,
	Span: number,
	Color: Color3,
	Cars: { number },
	Frames: { Frame },
}

local LANE_DEFINITIONS: { LaneDefinition } = {
	{ Row = 2, Direction = 1, Speed = 2.0, Length = 2, Gap = 6, Phase = 0 },
	{ Row = 3, Direction = -1, Speed = 1.4, Length = 3, Gap = 7, Phase = 2 },
	{ Row = 4, Direction = 1, Speed = 2.4, Length = 2, Gap = 8, Phase = 4 },
	{ Row = 6, Direction = -1, Speed = 1.6, Length = 2, Gap = 6, Phase = 1 },
	{ Row = 7, Direction = 1, Speed = 1.2, Length = 3, Gap = 6, Phase = 3 },
	{ Row = 8, Direction = -1, Speed = 2.1, Length = 2, Gap = 7, Phase = 5 },
}

local function newFrame(parent: Instance, color: Color3, strokeColor: Color3?, thickness: number?): Frame
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

local function newLabel(parent: Instance, theme: Theme, text: string, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = theme.Font
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = theme.Text
	label.Parent = parent
	return label
end

local function newButton(parent: Instance, theme: Theme, text: string): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundColor3 = theme.Panel
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = theme.Font
	button.Text = text
	button.TextSize = 26
	button.TextColor3 = theme.Primary
	button.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = theme.Primary
	stroke.Thickness = 3
	stroke.Parent = button

	return button
end

local Frogger = {}
Frogger.__index = Frogger

function Frogger.new(root: Frame, api: Api)
	local self = setmetatable({}, Frogger)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.State = "playing"
	self.Completed = false
	self.Crossings = 0
	self.Column = math.floor(COLUMNS / 2)
	self.Row = START_ROW
	self.LastHop = 0
	self.MessageUntil = 0

	self.Lanes = {} :: { Lane }
	self.LaneByRow = {} :: { [number]: Lane }
	self.Connections = {} :: { RBXScriptConnection }

	return self
end

local function cellPosition(column: number, row: number): UDim2
	return UDim2.fromScale(column / COLUMNS, (row - 1) / ROWS)
end

function Frogger:_buildBoard()
	local theme = self.Theme

	local board = newFrame(self.Root, theme.Background, theme.Primary, 4)
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.45)
	board.Size = UDim2.fromScale(0.92, 0.66)
	board.ClipsDescendants = true

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = COLUMNS / ROWS
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = board

	self.Board = board

	for row = 1, ROWS do
		local color = theme.Panel
		if row == GOAL_ROW then
			color = theme.Accent:Lerp(theme.Background, 0.78)
		elseif row == START_ROW or row == MEDIAN_ROW then
			color = theme.Grid
		end

		local strip = newFrame(board, color)
		strip.Name = "Row" .. row
		strip.Position = cellPosition(0, row)
		strip.Size = UDim2.fromScale(1, 1 / ROWS)
	end

	local goal = newLabel(board, theme, "GOAL", 20)
	goal.TextColor3 = theme.Accent
	goal.Position = cellPosition(0, GOAL_ROW)
	goal.Size = UDim2.fromScale(1, 1 / ROWS)
end

function Frogger:_buildLanes()
	local theme = self.Theme
	local colors = { theme.Danger, theme.Primary, theme.Text }

	for index, definition in LANE_DEFINITIONS do
		local length = math.max(1, definition.Length * LENGTH_SCALE)
		local count = math.ceil((COLUMNS + length) / definition.Gap)
		local lane: Lane = {
			Row = definition.Row,
			Direction = definition.Direction,
			Speed = definition.Speed,
			Length = length,
			Span = count * definition.Gap,
			Color = colors[(index - 1) % #colors + 1],
			Cars = {},
			Frames = {},
		}

		for car = 1, count do
			lane.Cars[car] = ((car - 1) * definition.Gap + definition.Phase) % lane.Span

			local frame = newFrame(self.Board, lane.Color, theme.Background, 2)
			frame.Name = "Car"
			frame.Size = UDim2.fromScale(lane.Length / COLUMNS, 1 / ROWS)
			lane.Frames[car] = frame
		end

		self.Lanes[index] = lane
		self.LaneByRow[lane.Row] = lane
		self:_drawLane(lane)
	end
end

function Frogger:_buildChrome()
	local theme = self.Theme

	local status = newFrame(self.Root, theme.Panel, theme.Grid, 3)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, 0.06)
	status.Size = UDim2.fromScale(0.92, 0.08)

	local crossings = newLabel(status, theme, "", 24)
	crossings.Name = "Crossings"
	crossings.TextXAlignment = Enum.TextXAlignment.Left
	crossings.Position = UDim2.fromScale(0.03, 0)
	crossings.Size = UDim2.fromScale(0.45, 1)
	self.CrossingsLabel = crossings

	local message = newLabel(status, theme, "REACH THE TOP", 22)
	message.Name = "Message"
	message.TextColor3 = theme.TextDim
	message.TextXAlignment = Enum.TextXAlignment.Right
	message.Position = UDim2.fromScale(0.52, 0)
	message.Size = UDim2.fromScale(0.45, 1)
	self.MessageLabel = message

	local frog = newFrame(self.Board, theme.Accent, theme.Text, 2)
	frog.Name = "Frog"
	frog.ZIndex = 3
	frog.Size = UDim2.fromScale(0.8 / COLUMNS, 0.8 / ROWS)
	self.Frog = frog

	self:_buildPad()
	self:_drawFrog()
	self:_refreshLabels()
end

function Frogger:_buildPad()
	local theme = self.Theme

	local pad = Instance.new("Frame")
	pad.Name = "Pad"
	pad.BackgroundTransparency = 1
	pad.AnchorPoint = Vector2.new(0.5, 0.5)
	pad.Position = UDim2.fromScale(0.5, 0.885)
	pad.Size = UDim2.fromScale(0.3, 0.2)
	pad.Parent = self.Root

	local layout = {
		{ Text = "W", Column = 1, Row = 0, DeltaColumn = 0, DeltaRow = -1 },
		{ Text = "A", Column = 0, Row = 1, DeltaColumn = -1, DeltaRow = 0 },
		{ Text = "S", Column = 1, Row = 1, DeltaColumn = 0, DeltaRow = 1 },
		{ Text = "D", Column = 2, Row = 1, DeltaColumn = 1, DeltaRow = 0 },
	}

	for _, entry in layout do
		local button = newButton(pad, theme, entry.Text)
		button.Position = UDim2.fromScale(entry.Column / 3 + 0.02, entry.Row / 2 + 0.04)
		button.Size = UDim2.fromScale(1 / 3 - 0.04, 1 / 2 - 0.08)
		table.insert(
			self.Connections,
			button.Activated:Connect(function()
				self:_hop(entry.DeltaColumn, entry.DeltaRow)
			end)
		)
	end
end

function Frogger:_drawLane(lane: Lane)
	for index, x in lane.Cars do
		local frame = lane.Frames[index]
		frame.Visible = x < COLUMNS
		if frame.Visible then
			frame.Position = cellPosition(x, lane.Row)
		end
	end
end

function Frogger:_drawFrog()
	local x = (self.Column + 0.1) / COLUMNS
	local y = (self.Row - 1 + 0.1) / ROWS
	self.Frog.Position = UDim2.fromScale(x, y)
end

function Frogger:_refreshLabels()
	self.CrossingsLabel.Text = string.format("CROSSED %d/%d", self.Crossings, CROSSINGS_TO_WIN)
end

function Frogger:_say(text: string, color: Color3)
	self.MessageLabel.Text = text
	self.MessageLabel.TextColor3 = color
	self.MessageUntil = os.clock() + MESSAGE_TIME
end

function Frogger:_toStart()
	self.Column = math.floor(COLUMNS / 2)
	self.Row = START_ROW
	self:_drawFrog()
end

function Frogger:_hop(deltaColumn: number, deltaRow: number)
	if self.State ~= "playing" then return end

	local now = os.clock()
	if now - self.LastHop < HOP_COOLDOWN then return end
	self.LastHop = now

	self.Column = math.clamp(self.Column + deltaColumn, 0, COLUMNS - 1)
	self.Row = math.clamp(self.Row + deltaRow, GOAL_ROW, START_ROW)
	self:_drawFrog()

	if self.Api.Sound then
		self.Api.Sound("Hop", 1 + (START_ROW - self.Row) / ROWS * 0.5)
	end

	if self.Row == GOAL_ROW then
		self:_crossed()
	elseif self:_isHit() then
		self:_splat()
	end
end

function Frogger:_isHit(): boolean
	local lane = self.LaneByRow[self.Row]
	if not lane then return false end

	local left = self.Column + HIT_FORGIVENESS
	local right = self.Column + 1 - HIT_FORGIVENESS

	for _, x in lane.Cars do
		if x < right and left < x + lane.Length then
			return true
		end
	end

	return false
end

function Frogger:_splat()
	if self.Api.Sound then self.Api.Sound("Splat") end
	self:_say("SPLAT!", self.Theme.Danger)
	self:_toStart()
	if self.Api.Fail then self.Api.Fail("SPLAT") end
end

function Frogger:_crossed()
	self.Crossings += 1
	self:_refreshLabels()
	self:_toStart()

	if self.Crossings >= CROSSINGS_TO_WIN then
		self:_win()
		return
	end

	if self.Api.Sound then
		self.Api.Sound("Chime", 1 + (self.Crossings - 1) * 0.12)
	end
	self:_say("CROSSED!", self.Theme.Accent)
end

function Frogger:_win()
	if self.Completed then return end
	self.Completed = true
	self.State = "won"

	self:_say("BREACHED", self.Theme.Accent)
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	self.Api.Complete()
end

function Frogger:_step(deltaTime: number)
	if self.State ~= "playing" then return end

	local step = math.min(deltaTime, 0.05)

	for _, lane in self.Lanes do
		local travel = lane.Direction * lane.Speed * step
		for index, x in lane.Cars do
			lane.Cars[index] = (x + travel) % lane.Span
		end
		self:_drawLane(lane)
	end

	if self:_isHit() then
		self:_splat()
	end

	if self.MessageUntil > 0 and os.clock() >= self.MessageUntil then
		self.MessageUntil = 0
		self.MessageLabel.Text = "REACH THE TOP"
		self.MessageLabel.TextColor3 = self.Theme.TextDim
	end
end

local HOPS: { [Enum.KeyCode]: { number } } = {
	[Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.D] = { 1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 },
}

function Frogger:_connectInput()
	table.insert(
		self.Connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local hop = HOPS[input.KeyCode]
			if hop then
				self:_hop(hop[1], hop[2])
			end
		end)
	)
end

function Frogger:Start(saved: any?)
	if type(saved) == "table" and type(saved.Crossings) == "number" then
		self.Crossings = math.clamp(saved.Crossings, 0, CROSSINGS_TO_WIN - 1)
	end

	self:_buildBoard()
	self:_buildLanes()
	self:_buildChrome()
	self:_connectInput()

	self.Heartbeat = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end)
end

function Frogger:Serialize(): any?
	if self.Crossings <= 0 then return nil end
	return { Crossings = self.Crossings }
end

function Frogger:Reset()
	if self.State == "won" then return end

	self.Crossings = 0
	self.MessageUntil = 0
	self:_toStart()
	self:_refreshLabels()
	self.MessageLabel.Text = "REACH THE TOP"
	self.MessageLabel.TextColor3 = self.Theme.TextDim

	for index, lane in self.Lanes do
		local definition = LANE_DEFINITIONS[index]
		for car = 1, #lane.Cars do
			lane.Cars[car] = ((car - 1) * definition.Gap + definition.Phase) % lane.Span
		end
		self:_drawLane(lane)
	end
end

function Frogger:Destroy()
	self.State = "dead"

	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	self.Root:ClearAllChildren()
end

return {
	Id = "Frogger",
	Title = "FROGGER.EXE",
	SupportsReset = true,
	new = function(root: Frame, api: Api)
		return Frogger.new(root, api)
	end,
}
