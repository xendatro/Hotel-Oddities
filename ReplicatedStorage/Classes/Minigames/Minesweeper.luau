--- Minesweeper: eight by eight, ten mines, clear every safe square to unlock the machine.
---
--- The mines are not laid until the first square is opened, and never under it or beside it. A first
--- click that loses is not a puzzle, it is a coin toss, and the opening flood is what gives the
--- board something to reason from.
---
--- Losing is not a fail state here. The board shows itself for a second and lays itself out again --
--- the computer is a lock to be picked, and being sent back to the start is the whole punishment.
---
--- Flagging is offered twice over: right-click for anyone with a second mouse button, and a FLAG
--- mode toggle for everyone else, since the screen is played on a SurfaceGui that a touch player
--- reaches with one finger.

--- Mirrors the framework's Theme. A child of a folder module cannot require its own parent without
--- going in a circle, so the shape is restated and the values are handed over at construction.
type Theme = {
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
type Api = {
	Complete: () -> (),
	Theme: Theme,
	Sound: ((name: string, pitch: number?) -> ())?,
}

local GRID = 8
local CELLS = GRID * GRID
local MINE_COUNT = 10
local SAFE_CELLS = CELLS - MINE_COUNT

local CELL = 54
local GAP = 3
local BOARD = GRID * CELL + (GRID - 1) * GAP
local HEADER_HEIGHT = 40
local HEADER_GAP = 16

--- How long the opened board is left on show before it deals itself again.
local BOOM_TIME = 1

--- Counts get their own colour so a board can be read at a glance rather than counted. Only the
--- palette the framework hands out is used, so the eight wrap around it.
local COUNT_COLORS = {
	"Primary",
	"Accent",
	"Danger",
	"Text",
	"TextDim",
	"Primary",
	"Accent",
	"Danger",
}

local Minesweeper = {}
Minesweeper.__index = Minesweeper

Minesweeper.Id = "Minesweeper"
Minesweeper.Title = "MINESWEEPER.EXE"
Minesweeper.SupportsReset = true

--- Board helpers ---------------------------------------------------------------------------------

--- Calls `visit` for each of the up to eight squares touching `index`.
local function forEachNeighbour(index: number, visit: (number) -> ())
	local row = math.floor((index - 1) / GRID)
	local column = (index - 1) % GRID

	for deltaRow = -1, 1 do
		for deltaColumn = -1, 1 do
			if deltaRow == 0 and deltaColumn == 0 then continue end

			local r, c = row + deltaRow, column + deltaColumn
			if r < 0 or r >= GRID or c < 0 or c >= GRID then continue end

			visit(r * GRID + c + 1)
		end
	end
end

--- Whether a restored snapshot is still shaped like a board. Saved state outlives nothing but the
--- session, yet a half-written one should start a fresh game rather than throw on the player.
local function isValidSave(saved: any): boolean
	if typeof(saved) ~= "table" then return false end

	for _, key in { "Mines", "Revealed", "Flags" } do
		local list = saved[key]
		if typeof(list) ~= "table" or #list ~= CELLS then return false end
	end

	return true
end

--- Drawing --------------------------------------------------------------------------------------

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function Minesweeper.new(root: Frame, api: Api): any
	local self = setmetatable({}, Minesweeper)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.Buttons = {} :: { TextButton }
	self.Strokes = {} :: { UIStroke }
	self.Mines = {} :: { boolean }
	self.Revealed = {} :: { boolean }
	self.Flags = {} :: { boolean }

	self.Placed = false
	self.Dead = false
	self.Flagging = false
	self.Opened = 0
	self.Won = false
	--- Bumped by every reset and by teardown, so a delayed re-deal that belongs to an older board
	--- knows to do nothing.
	self.Generation = 0

	return self
end

--- The look of one square, from whatever is currently true about it.
function Minesweeper:_paint(index: number)
	local theme: Theme = self.Theme
	local button: TextButton = self.Buttons[index]
	local stroke: UIStroke = self.Strokes[index]
	if not button then return end

	if self.Flags[index] and not self.Revealed[index] then
		button.BackgroundColor3 = theme.Grid
		button.Text = "F"
		button.TextColor3 = theme.Accent
		stroke.Color = theme.Accent
		return
	end

	if not self.Revealed[index] then
		button.BackgroundColor3 = theme.Grid
		button.Text = ""
		stroke.Color = theme.Panel
		return
	end

	if self.Mines[index] then
		button.BackgroundColor3 = theme.Danger
		button.Text = "*"
		button.TextColor3 = theme.Background
		stroke.Color = theme.Danger
		return
	end

	local count = self:_count(index)
	button.BackgroundColor3 = theme.Panel
	button.Text = if count > 0 then tostring(count) else ""
	button.TextColor3 = theme[COUNT_COLORS[math.max(count, 1)]]
	stroke.Color = theme.Grid
end

function Minesweeper:_repaint()
	for index = 1, CELLS do
		self:_paint(index)
	end
	self:_updateHeader()
end

function Minesweeper:_updateHeader()
	local theme: Theme = self.Theme

	local flagged = 0
	for index = 1, CELLS do
		if self.Flags[index] and not self.Revealed[index] then
			flagged += 1
		end
	end

	self.Counter.Text = `MINES {MINE_COUNT - flagged}`
	self.Message.Text = if self.Dead then "BOOM" else ""
	self.Message.TextColor3 = theme.Danger

	self.FlagButton.Text = if self.Flagging then "FLAG: ON" else "FLAG: OFF"
	local color = if self.Flagging then theme.Accent else theme.TextDim
	self.FlagButton.TextColor3 = color
	self.FlagStroke.Color = color
end

--- Rules ----------------------------------------------------------------------------------------

function Minesweeper:_count(index: number): number
	local count = 0
	forEachNeighbour(index, function(neighbour: number)
		if self.Mines[neighbour] then
			count += 1
		end
	end)
	return count
end

--- Lays the mines once the player has committed to a square, keeping that square and its ring clear
--- so the first click always opens onto something worth reading.
function Minesweeper:_place(safeIndex: number)
	local forbidden: { [number]: true } = { [safeIndex] = true }
	forEachNeighbour(safeIndex, function(neighbour: number)
		forbidden[neighbour] = true
	end)

	local pool: { number } = {}
	for index = 1, CELLS do
		if not forbidden[index] then
			table.insert(pool, index)
		end
	end

	for _ = 1, MINE_COUNT do
		local pick = math.random(1, #pool)
		self.Mines[table.remove(pool, pick) :: number] = true
	end

	self.Placed = true
end

--- Opens a square, and every square an empty one leads to. Iterative rather than recursive: an
--- eight by eight board can flood almost all of itself from one click.
function Minesweeper:_reveal(index: number)
	local stack = { index }

	while #stack > 0 do
		local at = table.remove(stack) :: number
		if self.Revealed[at] or self.Flags[at] then continue end

		self.Revealed[at] = true
		self.Opened += 1
		self:_paint(at)

		if self:_count(at) == 0 then
			forEachNeighbour(at, function(neighbour: number)
				if not self.Revealed[neighbour] and not self.Mines[neighbour] then
					table.insert(stack, neighbour)
				end
			end)
		end
	end
end

function Minesweeper:_boom()
	self.Dead = true

	-- The palette's low thud, dropped further still. Nothing else in these five games is allowed to
	-- be this heavy, which is what makes a mine feel like the one mistake that costs the board.
	if self.Api.Sound then self.Api.Sound("Boom", 0.8) end

	for index = 1, CELLS do
		if self.Mines[index] then
			self.Revealed[index] = true
		end
	end
	self:_repaint()

	local generation = self.Generation
	task.delay(BOOM_TIME, function()
		-- Only the board that blew up gets dealt again; a reset or a teardown in the meantime has
		-- already moved on.
		if self.Generation ~= generation then return end
		self:Reset()
	end)
end

function Minesweeper:_click(index: number, flagging: boolean)
	if self.Dead or self.Won then return end

	if flagging then
		if self.Revealed[index] then return end
		self.Flags[index] = not self.Flags[index] or nil
		-- Planting and pulling a flag are told apart by pitch alone; two cues for one toggle would be
		-- two things to recognise where the board only ever means one.
		if self.Api.Sound then
			self.Api.Sound("Flag", if self.Flags[index] then 1 else 0.8)
		end
		self:_paint(index)
		self:_updateHeader()
		return
	end

	if self.Flags[index] or self.Revealed[index] then return end

	if not self.Placed then
		self:_place(index)
	end

	if self.Mines[index] then
		self:_boom()
		return
	end

	-- One blip for the click, not one per square: an opening flood can turn over fifty cells, and
	-- fifty ticks in a frame is a noise rather than feedback.
	if self.Api.Sound then self.Api.Sound("Blip") end

	self:_reveal(index)
	self:_updateHeader()

	if self.Opened >= SAFE_CELLS then
		self.Won = true
		-- No sound of its own: clearing the board is a win, and the framework's jingle is the one
		-- ending every game in the set shares.
		self.Api.Complete()
	end
end

--- Building -------------------------------------------------------------------------------------

function Minesweeper:_build()
	local theme: Theme = self.Theme
	local root: Frame = self.Root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Parent = root

	local counter = Instance.new("TextLabel")
	counter.Name = "Counter"
	counter.Size = UDim2.fromOffset(200, HEADER_HEIGHT)
	counter.BackgroundTransparency = 1
	counter.Font = theme.Font
	counter.Text = `MINES {MINE_COUNT}`
	counter.TextSize = 26
	counter.TextColor3 = theme.Text
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.Parent = header
	self.Counter = counter

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 0)
	message.Position = UDim2.fromScale(0.5, 0)
	message.Size = UDim2.fromOffset(300, HEADER_HEIGHT)
	message.BackgroundTransparency = 1
	message.Font = theme.Font
	message.Text = ""
	message.TextSize = 30
	message.TextColor3 = theme.Danger
	message.Parent = header
	self.Message = message

	local flagButton = Instance.new("TextButton")
	flagButton.Name = "FlagMode"
	flagButton.AnchorPoint = Vector2.new(1, 0.5)
	flagButton.Position = UDim2.new(1, 0, 0.5, 0)
	flagButton.Size = UDim2.fromOffset(148, 32)
	flagButton.BackgroundColor3 = theme.Panel
	flagButton.BorderSizePixel = 0
	flagButton.AutoButtonColor = false
	flagButton.Font = theme.Font
	flagButton.Text = "FLAG: OFF"
	flagButton.TextSize = 22
	flagButton.TextColor3 = theme.TextDim
	flagButton.Parent = header
	self.FlagButton = flagButton
	self.FlagStroke = addStroke(flagButton, theme.TextDim, 2)

	flagButton.MouseButton1Click:Connect(function()
		self.Flagging = not self.Flagging
		self:_updateHeader()
	end)

	local board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0)
	board.Position = UDim2.new(0.5, 0, 0, HEADER_HEIGHT + HEADER_GAP)
	board.Size = UDim2.fromOffset(BOARD, BOARD)
	board.BackgroundColor3 = theme.Background
	board.BorderSizePixel = 0
	board.Parent = root

	for index = 1, CELLS do
		local row = math.floor((index - 1) / GRID)
		local column = (index - 1) % GRID

		local cell = Instance.new("TextButton")
		cell.Name = `Cell{index}`
		cell.Position = UDim2.fromOffset(column * (CELL + GAP), row * (CELL + GAP))
		cell.Size = UDim2.fromOffset(CELL, CELL)
		cell.BackgroundColor3 = theme.Grid
		cell.BorderSizePixel = 0
		cell.AutoButtonColor = false
		cell.Font = theme.Font
		cell.Text = ""
		cell.TextSize = 32
		cell.TextColor3 = theme.Text
		cell.Parent = board

		self.Buttons[index] = cell
		self.Strokes[index] = addStroke(cell, theme.Panel, 2)

		cell.MouseButton1Click:Connect(function()
			self:_click(index, self.Flagging)
		end)
		-- The second button is the classic way to flag, and costs nothing to offer alongside the
		-- toggle that everyone else uses.
		cell.MouseButton2Click:Connect(function()
			self:_click(index, true)
		end)
	end
end

--- Contract -------------------------------------------------------------------------------------

function Minesweeper:Start(saved: any?)
	self:_build()

	if isValidSave(saved) then
		self.Placed = saved.Placed == true
		self.Opened = 0

		for index = 1, CELLS do
			self.Mines[index] = saved.Mines[index] == true or nil
			self.Flags[index] = saved.Flags[index] == true or nil
			self.Revealed[index] = saved.Revealed[index] == true or nil
			if self.Revealed[index] then
				self.Opened += 1
			end
		end

		self.Flagging = saved.Flagging == true
	end

	self:_repaint()
end

function Minesweeper:Serialize(): any?
	-- An untouched board and one that just blew up are both worth nothing to come back to.
	if self.Dead or self.Won or (not self.Placed and self.Opened == 0) then
		return nil
	end

	local mines, revealed, flags = {}, {}, {}
	for index = 1, CELLS do
		mines[index] = self.Mines[index] == true
		revealed[index] = self.Revealed[index] == true
		flags[index] = self.Flags[index] == true
	end

	return {
		Placed = self.Placed,
		Flagging = self.Flagging,
		Mines = mines,
		Revealed = revealed,
		Flags = flags,
	}
end

function Minesweeper:Reset()
	self.Generation += 1
	self.Placed = false
	self.Dead = false
	self.Won = false
	self.Opened = 0
	table.clear(self.Mines)
	table.clear(self.Revealed)
	table.clear(self.Flags)
	self:_repaint()
end

function Minesweeper:Destroy()
	-- Stops any pending re-deal from touching a board that is no longer on screen.
	self.Generation += 1

	table.clear(self.Buttons)
	table.clear(self.Strokes)
	-- The connections all hang off instances under the root, so clearing it takes them with it.
	self.Root:ClearAllChildren()
end

return Minesweeper
