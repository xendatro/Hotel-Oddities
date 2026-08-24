local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local COLUMNS = 16
local ROWS = 12
local PELLETS_TO_WIN = 15
local START_LENGTH = 3
local BASE_TICK = 0.16
local TICK_PER_PELLET = 0.006
local MIN_TICK = 0.106
local MAX_QUEUED_TURNS = 2
local MESSAGE_TIME = 1
local EAT_PITCH_RISE = 0.7

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

type Cell = { X: number, Y: number }

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

local Snake = {}
Snake.__index = Snake

function Snake.new(root: Frame, api: Api)
	local self = setmetatable({}, Snake)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.State = "playing"
	self.Completed = false
	self.Random = Random.new()

	self.Body = {} :: { Cell }
	self.Direction = { X = 1, Y = 0 }
	self.TurnQueue = {} :: { Cell }
	self.Pellet = { X = 0, Y = 0 } :: Cell
	self.Pellets = 0
	self.Best = 0
	self.Grow = 0
	self.Clock = 0
	self.MessageUntil = 0

	self.SegmentFrames = {} :: { Frame }
	self.Connections = {} :: { RBXScriptConnection }

	return self
end

local function cellPosition(x: number, y: number): UDim2
	return UDim2.fromScale(x / COLUMNS, y / ROWS)
end

function Snake:_buildBoard()
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

	for column = 1, COLUMNS - 1 do
		local line = newFrame(board, theme.Grid)
		line.Name = "GridX"
		line.Position = UDim2.fromScale(column / COLUMNS, 0)
		line.Size = UDim2.new(0, 1, 1, 0)
	end
	for row = 1, ROWS - 1 do
		local line = newFrame(board, theme.Grid)
		line.Name = "GridY"
		line.Position = UDim2.fromScale(0, row / ROWS)
		line.Size = UDim2.new(1, 0, 0, 1)
	end

	local pellet = newFrame(board, theme.Danger, theme.Text, 2)
	pellet.Name = "Pellet"
	pellet.ZIndex = 2
	pellet.Size = UDim2.fromScale(0.6 / COLUMNS, 0.6 / ROWS)
	self.PelletFrame = pellet
end

function Snake:_buildChrome()
	local theme = self.Theme

	local status = newFrame(self.Root, theme.Panel, theme.Grid, 3)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, 0.06)
	status.Size = UDim2.fromScale(0.92, 0.08)

	local score = newLabel(status, theme, "", 24)
	score.Name = "Score"
	score.TextXAlignment = Enum.TextXAlignment.Left
	score.Position = UDim2.fromScale(0.03, 0)
	score.Size = UDim2.fromScale(0.45, 1)
	self.ScoreLabel = score

	local message = newLabel(status, theme, "", 22)
	message.Name = "Message"
	message.TextColor3 = theme.TextDim
	message.TextXAlignment = Enum.TextXAlignment.Right
	message.Position = UDim2.fromScale(0.52, 0)
	message.Size = UDim2.fromScale(0.45, 1)
	self.MessageLabel = message

	self:_buildPad()
end

function Snake:_buildPad()
	local theme = self.Theme

	local pad = Instance.new("Frame")
	pad.Name = "Pad"
	pad.BackgroundTransparency = 1
	pad.AnchorPoint = Vector2.new(0.5, 0.5)
	pad.Position = UDim2.fromScale(0.5, 0.885)
	pad.Size = UDim2.fromScale(0.3, 0.2)
	pad.Parent = self.Root

	local layout = {
		{ Text = "W", Column = 1, Row = 0, X = 0, Y = -1 },
		{ Text = "A", Column = 0, Row = 1, X = -1, Y = 0 },
		{ Text = "S", Column = 1, Row = 1, X = 0, Y = 1 },
		{ Text = "D", Column = 2, Row = 1, X = 1, Y = 0 },
	}

	for _, entry in layout do
		local button = newButton(pad, theme, entry.Text)
		button.Position = UDim2.fromScale(entry.Column / 3 + 0.02, entry.Row / 2 + 0.04)
		button.Size = UDim2.fromScale(1 / 3 - 0.04, 1 / 2 - 0.08)
		table.insert(
			self.Connections,
			button.Activated:Connect(function()
				self:_turn(entry.X, entry.Y)
			end)
		)
	end
end

function Snake:_draw()
	local theme = self.Theme

	for index, cell in self.Body do
		local frame = self.SegmentFrames[index]
		if not frame then
			frame = newFrame(self.Board, theme.Primary, theme.Background, 2)
			frame.Name = "Segment"
			frame.ZIndex = 3
			frame.Size = UDim2.fromScale(1 / COLUMNS, 1 / ROWS)
			self.SegmentFrames[index] = frame
		end

		frame.Visible = true
		frame.BackgroundColor3 = if index == 1 then theme.Accent else theme.Primary
		frame.Position = cellPosition(cell.X, cell.Y)
	end

	for index = #self.Body + 1, #self.SegmentFrames do
		self.SegmentFrames[index].Visible = false
	end

	self.PelletFrame.Position =
		UDim2.fromScale((self.Pellet.X + 0.2) / COLUMNS, (self.Pellet.Y + 0.2) / ROWS)
end

function Snake:_refreshLabels()
	self.ScoreLabel.Text = string.format("PELLETS %d/%d", self.Pellets, PELLETS_TO_WIN)
end

function Snake:_say(text: string, color: Color3)
	self.MessageLabel.Text = text
	self.MessageLabel.TextColor3 = color
	self.MessageUntil = os.clock() + MESSAGE_TIME
end

function Snake:_idleMessage()
	if self.Best > 0 then
		self.MessageLabel.Text = string.format("BEST %d", self.Best)
	else
		self.MessageLabel.Text = "EAT FIFTEEN"
	end
	self.MessageLabel.TextColor3 = self.Theme.TextDim
end

function Snake:_occupied(x: number, y: number): boolean
	for _, cell in self.Body do
		if cell.X == x and cell.Y == y then
			return true
		end
	end
	return false
end

function Snake:_placePellet()
	for _ = 1, 200 do
		local x = self.Random:NextInteger(0, COLUMNS - 1)
		local y = self.Random:NextInteger(0, ROWS - 1)
		if not self:_occupied(x, y) then
			self.Pellet = { X = x, Y = y }
			return
		end
	end

	for y = 0, ROWS - 1 do
		for x = 0, COLUMNS - 1 do
			if not self:_occupied(x, y) then
				self.Pellet = { X = x, Y = y }
				return
			end
		end
	end
end

function Snake:_respawn()
	local y = math.floor(ROWS / 2)
	local x = math.floor(COLUMNS / 4)

	self.Body = {}
	for index = 1, START_LENGTH do
		self.Body[index] = { X = x - (index - 1), Y = y }
	end

	self.Direction = { X = 1, Y = 0 }
	table.clear(self.TurnQueue)
	self.Grow = 0
	self.Clock = 0
	self:_placePellet()
end

function Snake:_turn(x: number, y: number)
	if self.State ~= "playing" then return end

	local queueLength = #self.TurnQueue
	local replacing = queueLength >= MAX_QUEUED_TURNS
	local previous = if replacing
		then self.TurnQueue[queueLength - 1] or self.Direction
		else self.TurnQueue[queueLength] or self.Direction

	if x == -previous.X and y == -previous.Y then return end
	if not replacing and x == previous.X and y == previous.Y then return end

	local turn = { X = x, Y = y }
	if replacing then
		self.TurnQueue[queueLength] = turn
	else
		table.insert(self.TurnQueue, turn)
	end
end

function Snake:_interval(): number
	return math.max(MIN_TICK, BASE_TICK - self.Pellets * TICK_PER_PELLET)
end

function Snake:_crash()
	if self.Pellets > self.Best then
		self.Best = self.Pellets
	end

	self.Pellets = 0
	self:_respawn()
	self:_refreshLabels()
	self:_say("CRASHED", self.Theme.Danger)
	self:_draw()
	if self.Api.Fail then self.Api.Fail("CRASHED") end
end

function Snake:_tick()
	local turn = table.remove(self.TurnQueue, 1)
	if turn then
		self.Direction = turn
	end

	local head = self.Body[1]
	local x = head.X + self.Direction.X
	local y = head.Y + self.Direction.Y

	if x < 0 or x >= COLUMNS or y < 0 or y >= ROWS then
		self:_crash()
		return
	end

	local eating = x == self.Pellet.X and y == self.Pellet.Y
	local last = if eating then #self.Body else #self.Body - 1
	for index = 1, last do
		local cell = self.Body[index]
		if cell.X == x and cell.Y == y then
			self:_crash()
			return
		end
	end

	table.insert(self.Body, 1, { X = x, Y = y })
	if eating then
		self.Pellets += 1
		if self.Api.Sound then
			local climb = math.clamp((self.Pellets - 1) / math.max(PELLETS_TO_WIN - 1, 1), 0, 1)
			self.Api.Sound("Eat", 1 + EAT_PITCH_RISE * climb)
		end
		self:_refreshLabels()
		self:_placePellet()
		self:_say("+1", self.Theme.Accent)
	else
		table.remove(self.Body)
	end

	self:_draw()

	if eating and self.Pellets >= PELLETS_TO_WIN then
		self:_win()
	end
end

function Snake:_win()
	if self.Completed then return end
	self.Completed = true
	self.State = "won"
	self.Best = math.max(self.Best, self.Pellets)

	self:_say("BREACHED", self.Theme.Accent)
	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	self.Api.Complete()
end

function Snake:_step(deltaTime: number)
	if self.State ~= "playing" then return end

	if self.MessageUntil > 0 and os.clock() >= self.MessageUntil then
		self.MessageUntil = 0
		self:_idleMessage()
	end

	self.Clock += math.min(deltaTime, 0.1)

	local interval = self:_interval()
	while self.State == "playing" and self.Clock >= interval do
		self.Clock -= interval
		self:_tick()
		interval = self:_interval()
	end
end

local TURNS: { [Enum.KeyCode]: { number } } = {
	[Enum.KeyCode.W] = { 0, -1 },
	[Enum.KeyCode.Up] = { 0, -1 },
	[Enum.KeyCode.S] = { 0, 1 },
	[Enum.KeyCode.Down] = { 0, 1 },
	[Enum.KeyCode.A] = { -1, 0 },
	[Enum.KeyCode.Left] = { -1, 0 },
	[Enum.KeyCode.D] = { 1, 0 },
	[Enum.KeyCode.Right] = { 1, 0 },
}

function Snake:_connectInput()
	table.insert(
		self.Connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local turn = TURNS[input.KeyCode]
			if turn then
				self:_turn(turn[1], turn[2])
			end
		end)
	)
end

function Snake:Start(saved: any?)
	if type(saved) == "table" and type(saved.Best) == "number" then
		self.Best = math.clamp(math.floor(saved.Best), 0, PELLETS_TO_WIN)
	end

	self:_buildBoard()
	self:_buildChrome()
	self:_respawn()
	self:_refreshLabels()
	self:_idleMessage()
	self:_draw()
	self:_connectInput()

	self.Heartbeat = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end)
end

function Snake:Serialize(): any?
	if self.Best <= 0 then return nil end
	return { Best = self.Best }
end

function Snake:Reset()
	if self.State == "won" then return end

	if self.Pellets > self.Best then
		self.Best = self.Pellets
	end
	self.Pellets = 0
	self.MessageUntil = 0
	self:_respawn()
	self:_refreshLabels()
	self:_idleMessage()
	self:_draw()
end

function Snake:Destroy()
	self.State = "dead"

	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	table.clear(self.SegmentFrames)
	self.Root:ClearAllChildren()
end

return {
	Id = "Snake",
	Title = "SNAKE.EXE",
	SupportsReset = true,
	new = function(root: Frame, api: Api)
		return Snake.new(root, api)
	end,
}
