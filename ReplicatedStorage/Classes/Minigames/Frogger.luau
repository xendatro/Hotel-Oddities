--- FROGGER.EXE -- one of the five terminal minigames. Hop a frog up a 13x9 board through six lanes
--- of traffic and reach the top three times over.
---
--- The lanes are written down rather than rolled. Every terminal in the hotel presents the same
--- traffic in the same order, so a player who has been flattened by the fast lane once knows what is
--- coming the next time round; a random board would make each attempt a fresh guess instead of a
--- fresh run at a known problem.
---
--- Cars live in a wrap space a little wider than the board rather than being teleported at the edge.
--- That is what lets a lane hold its spacing while a car walks off one side and reappears on the
--- other: the position is one number modulo the lane's span, and being off-board is simply a
--- position past the last column.
---
--- Nothing here reaches outside the module -- the framework hands over a root Frame and a theme and
--- takes back a Start/Serialize/Reset/Destroy shape. `Destroy` has to be safe in the middle of a
--- hop, so every connection this makes goes into one list and they all come down together.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local COLUMNS = 13
local ROWS = 9
--- Row 1 is the goal strip, row 9 the kerb the frog starts on, row 5 the median it can rest on.
local GOAL_ROW = 1
local START_ROW = ROWS
local MEDIAN_ROW = 5
local CROSSINGS_TO_WIN = 3
--- A held key should walk, not teleport, so hops are rate limited rather than repeat limited.
local HOP_COOLDOWN = 0.1
--- Cars are forgiven a sliver at each end. A pixel-perfect box would kill frogs that visibly cleared
--- the bumper, which reads as the game cheating.
local HIT_FORGIVENESS = 0.18
local MESSAGE_TIME = 0.8
--- Every car is built about a third shorter than its lane was authored. The speeds and the spacing
--- between leading edges are untouched, so the whole third that comes off a car is handed straight to
--- the hole behind it: the traffic still reads the same, there is simply more room to step into, which
--- is what a younger player needs rather than slower cars.
local LENGTH_SCALE = 0.65

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

--- `Sound` is optional so that a framework built before the sound layer existed still satisfies this
--- contract; every call site here checks for it rather than assuming it.
export type Api = {
	Complete: () -> (),
	Theme: Theme,
	Sound: ((name: string, pitch: number?) -> ())?,
}

type LaneDefinition = {
	Row: number,
	Direction: number,
	--- Cells per second.
	Speed: number,
	--- Car length in cells, as authored. What is built is this times LENGTH_SCALE.
	Length: number,
	--- Cells between the leading edges of two cars in the same lane.
	Gap: number,
	Phase: number,
}

type Lane = {
	Row: number,
	Direction: number,
	Speed: number,
	Length: number,
	--- The wrap space, always at least COLUMNS + Length so a car is fully off-board before it comes
	--- back on the other side.
	Span: number,
	Color: Color3,
	--- Leading-edge column of each car, in continuous cell units within [0, Span).
	Cars: { number },
	Frames: { Frame },
}

local LANE_DEFINITIONS: { LaneDefinition } = {
	{ Row = 2, Direction = 1, Speed = 2.7, Length = 2, Gap = 5, Phase = 0 },
	{ Row = 3, Direction = -1, Speed = 1.8, Length = 3, Gap = 6, Phase = 2 },
	{ Row = 4, Direction = 1, Speed = 3.5, Length = 2, Gap = 7, Phase = 4 },
	{ Row = 6, Direction = -1, Speed = 2.2, Length = 2, Gap = 5, Phase = 1 },
	{ Row = 7, Direction = 1, Speed = 1.5, Length = 3, Gap = 5, Phase = 3 },
	{ Row = 8, Direction = -1, Speed = 3.0, Length = 2, Gap = 6, Phase = 5 },
}

--- Building blocks ------------------------------------------------------------------------------

--- Every rectangle in these games is made the same way: flat fill, hard chunky edge, no corner
--- rounding at all, so the five minigames read as one machine rather than five.
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

--- The game ------------------------------------------------------------------------------------

local Frogger = {}
Frogger.__index = Frogger

function Frogger.new(root: Frame, api: Api)
	local self = setmetatable({}, Frogger)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	--- "playing" until the third crossing lands, then "won" -- which is also what stops input.
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

--- Layout --------------------------------------------------------------------------------------

--- Where a cell sits on the board, in scale. Columns are 0-based, rows 1-based from the top.
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
	-- Cars have to look like cars, so the cells stay square whatever height the chrome leaves.
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
		-- The shortened length is what the lane is built, drawn and tested against; the authored one
		-- only ever names the shape the lane started as. Never below a whole cell: a car the frog can
		-- stand inside is not a car.
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

--- The on-screen pad, for players on touch or a mouse. It is laid out as a real d-pad and lettered
--- with the keys that do the same thing, so the two ways in teach each other.
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

--- Drawing -------------------------------------------------------------------------------------

function Frogger:_drawLane(lane: Lane)
	for index, x in lane.Cars do
		local frame = lane.Frames[index]
		-- Past the last column is the lane's waiting room: the car exists, it just is not on the
		-- board yet. Hiding it keeps the clipped edge from showing a sliver of a car that is not
		-- really there.
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

--- Play ----------------------------------------------------------------------------------------

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

	-- The tick climbs with the row, so working up the board sounds like working up the board, and
	-- being sent back to the kerb is audible before the label has finished saying so.
	if self.Api.Sound then
		self.Api.Sound("Hop", 1 + (START_ROW - self.Row) / ROWS * 0.5)
	end

	if self.Row == GOAL_ROW then
		self:_crossed()
	elseif self:_isHit() then
		self:_splat()
	end
end

--- Whether the cell the frog is standing in overlaps a car. Both boxes are in cell units, so this
--- is one interval test per car in the frog's lane.
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
end

function Frogger:_crossed()
	self.Crossings += 1
	self:_refreshLabels()
	self:_toStart()

	if self.Crossings >= CROSSINGS_TO_WIN then
		-- Silent on the last one: the framework's jingle is already on its way, and a chime under it
		-- would only muddy the ending every game in the set shares.
		self:_win()
		return
	end

	-- A step up per crossing, so three crossings are three rungs rather than the same note thrice.
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

	-- Last, because the framework tears this game down from inside the fanfare that follows.
	self.Api.Complete()
end

function Frogger:_step(deltaTime: number)
	if self.State ~= "playing" then return end

	-- A single long frame must not let a car step over the frog, so the traffic is clamped to a
	-- sensible slice rather than trusting whatever deltaTime arrives after a hitch.
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

--- Input ---------------------------------------------------------------------------------------

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
		-- The processed flag is deliberately ignored: while a terminal is open the player's own
		-- controls are switched off and this screen owns the keyboard, so a movement key that some
		-- other listener also saw is still meant for the frog.
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local hop = HOPS[input.KeyCode]
			if hop then
				self:_hop(hop[1], hop[2])
			end
		end)
	)
end

--- Framework contract --------------------------------------------------------------------------

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

--- Only how far up the board the player got. The traffic is deterministic, so there is nothing else
--- worth carrying back into the next visit.
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
