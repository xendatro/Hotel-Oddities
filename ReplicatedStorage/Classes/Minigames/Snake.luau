local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MinigameBase = require(ReplicatedStorage.Classes.Minigames.MinigameBase)

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

export type Theme = MinigameBase.Theme
export type Api = MinigameBase.Api

type Cell = { X: number, Y: number }

local Snake = MinigameBase.extend("Snake", "SNAKE.EXE", true)

function Snake.new(root: Frame, api: Api)
	local self = MinigameBase.new(root, api, Snake)

	self.Random = Random.new()
	self.MessageTime = MESSAGE_TIME

	self.Body = {} :: { Cell }
	self.Direction = { X = 1, Y = 0 }
	self.TurnQueue = {} :: { Cell }
	self.Pellet = { X = 0, Y = 0 } :: Cell
	self.Pellets = 0
	self.Best = 0
	self.Grow = 0
	self.Clock = 0

	self.SegmentFrames = {} :: { Frame }

	return self
end

local function cellPosition(x: number, y: number): UDim2
	return UDim2.fromScale(x / COLUMNS, y / ROWS)
end

function Snake:_buildBoard()
	local theme = self.Theme

	local board = self:BuildBoardFrame(COLUMNS / ROWS, { Clip = true })

	for column = 1, COLUMNS - 1 do
		local line = self:NewFrame(board, theme.Grid)
		line.Name = "GridX"
		line.Position = UDim2.fromScale(column / COLUMNS, 0)
		line.Size = UDim2.new(0, 1, 1, 0)
	end
	for row = 1, ROWS - 1 do
		local line = self:NewFrame(board, theme.Grid)
		line.Name = "GridY"
		line.Position = UDim2.fromScale(0, row / ROWS)
		line.Size = UDim2.new(1, 0, 0, 1)
	end

	local pellet = self:NewFrame(board, theme.Danger, theme.Text, 2)
	pellet.Name = "Pellet"
	pellet.ZIndex = 2
	pellet.Size = UDim2.fromScale(0.6 / COLUMNS, 0.6 / ROWS)
	self.PelletFrame = pellet
end

function Snake:_buildChrome()
	local score = self:BuildStatusBar("Score", "")
	self.ScoreLabel = score

	self:BuildDirectionalPad(function(x: number, y: number)
		self:_turn(x, y)
	end)
end

function Snake:_draw()
	local theme = self.Theme

	for index, cell in self.Body do
		local frame = self.SegmentFrames[index]
		if not frame then
			frame = self:NewFrame(self.Board, theme.Primary, theme.Background, 2)
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

function Snake:IdleMessage()
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
	self:Say("CRASHED", self.Theme.Danger)
	self:_draw()
	self:FailRun("CRASHED")
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
		self:PlaySound("Eat", 1 + EAT_PITCH_RISE * self:Climb(self.Pellets, PELLETS_TO_WIN))
		self:_refreshLabels()
		self:_placePellet()
		self:Say("+1", self.Theme.Accent)
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
	self.Best = math.max(self.Best, self.Pellets)
	self:Win()
end

function Snake:_step(deltaTime: number)
	if self.State ~= "playing" then return end

	self:StepMessage()

	self.Clock += math.min(deltaTime, 0.1)

	local interval = self:_interval()
	while self.State == "playing" and self.Clock >= interval do
		self.Clock -= interval
		self:_tick()
		interval = self:_interval()
	end
end

function Snake:Start(saved: any?)
	self.Best = self:ClampedSavedNumber(saved, "Best", 0, PELLETS_TO_WIN) or self.Best

	self:_buildBoard()
	self:_buildChrome()
	self:_respawn()
	self:_refreshLabels()
	self:IdleMessage()
	self:_draw()
	self:ConnectDirectionalKeys(function(x: number, y: number)
		self:_turn(x, y)
	end)

	self:StartHeartbeat(function(deltaTime: number)
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
	self:IdleMessage()
	self:_draw()
end

function Snake:OnDestroy()
	table.clear(self.SegmentFrames)
end

return Snake
