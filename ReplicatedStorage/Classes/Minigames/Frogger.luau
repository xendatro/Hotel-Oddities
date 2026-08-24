local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MinigameBase = require(ReplicatedStorage.Classes.Minigames.MinigameBase)

local COLUMNS = 13
local ROWS = 9
local GOAL_ROW = 1
local START_ROW = ROWS
local MEDIAN_ROW = 5
local CROSSINGS_TO_WIN = 2
local HOP_COOLDOWN = 0.1
local HIT_FORGIVENESS = 0.2
local MESSAGE_TIME = 0.8
local LENGTH_SCALE = 0.55
local TRAFFIC_SPEED_SCALE = 1.35

export type Theme = MinigameBase.Theme
export type Api = MinigameBase.Api

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

local Frogger = MinigameBase.extend("Frogger", "FROGGER.EXE", true)

function Frogger.new(root: Frame, api: Api)
	local self = MinigameBase.new(root, api, Frogger)

	self.MessageTime = MESSAGE_TIME
	self.Crossings = 0
	self.Column = math.floor(COLUMNS / 2)
	self.Row = START_ROW
	self.LastHop = 0

	self.Lanes = {} :: { Lane }
	self.LaneByRow = {} :: { [number]: Lane }

	return self
end

local function cellPosition(column: number, row: number): UDim2
	return UDim2.fromScale(column / COLUMNS, (row - 1) / ROWS)
end

function Frogger:_buildBoard()
	local theme = self.Theme

	local board = self:BuildBoardFrame(COLUMNS / ROWS, { Clip = true })

	for row = 1, ROWS do
		local color = theme.Panel
		if row == GOAL_ROW then
			color = theme.Accent:Lerp(theme.Background, 0.78)
		elseif row == START_ROW or row == MEDIAN_ROW then
			color = theme.Grid
		end

		local strip = self:NewFrame(board, color)
		strip.Name = "Row" .. row
		strip.Position = cellPosition(0, row)
		strip.Size = UDim2.fromScale(1, 1 / ROWS)
	end

	local goal = self:NewLabel(board, "GOAL", 20)
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
			Speed = definition.Speed * TRAFFIC_SPEED_SCALE,
			Length = length,
			Span = count * definition.Gap,
			Color = colors[(index - 1) % #colors + 1],
			Cars = {},
			Frames = {},
		}

		for car = 1, count do
			lane.Cars[car] = ((car - 1) * definition.Gap + definition.Phase) % lane.Span

			local frame = self:NewFrame(self.Board, lane.Color, theme.Background, 2)
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

	local crossings = self:BuildStatusBar("Crossings", "REACH THE TOP")
	self.CrossingsLabel = crossings

	local frog = self:NewFrame(self.Board, theme.Accent, theme.Text, 2)
	frog.Name = "Frog"
	frog.ZIndex = 3
	frog.Size = UDim2.fromScale(0.8 / COLUMNS, 0.8 / ROWS)
	self.Frog = frog

	self:BuildDirectionalPad(function(x: number, y: number)
		self:_hop(x, y)
	end)
	self:_drawFrog()
	self:_refreshLabels()
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

function Frogger:IdleMessage()
	self.MessageLabel.Text = "REACH THE TOP"
	self.MessageLabel.TextColor3 = self.Theme.TextDim
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

	self:PlaySound("Hop", 1 + (START_ROW - self.Row) / ROWS * 0.5)

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
	self:PlaySound("Splat")
	self.Crossings = 0
	self:_refreshLabels()
	self:Say("SPLAT!", self.Theme.Danger)
	self:_toStart()
	self:FailRun("SPLAT")
end

function Frogger:_crossed()
	self.Crossings += 1
	self:_refreshLabels()
	self:_toStart()

	if self.Crossings >= CROSSINGS_TO_WIN then
		self:Win()
		return
	end

	self:PlaySound("Chime", 1 + (self.Crossings - 1) * 0.12)
	self:Say("CROSSED!", self.Theme.Accent)
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

	self:StepMessage()
end

function Frogger:Start(saved: any?)
	self.Crossings = self:ClampedSavedNumber(saved, "Crossings", 0, CROSSINGS_TO_WIN - 1) or self.Crossings

	self:_buildBoard()
	self:_buildLanes()
	self:_buildChrome()
	self:ConnectDirectionalKeys(function(x: number, y: number)
		self:_hop(x, y)
	end)

	self:StartHeartbeat(function(deltaTime: number)
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
	self:IdleMessage()

	for index, lane in self.Lanes do
		local definition = LANE_DEFINITIONS[index]
		for car = 1, #lane.Cars do
			lane.Cars[car] = ((car - 1) * definition.Gap + definition.Phase) % lane.Span
		end
		self:_drawLane(lane)
	end
end

return Frogger
