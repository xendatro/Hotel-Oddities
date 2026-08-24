local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MinigameBase = require(ReplicatedStorage.Classes.Minigames.MinigameBase)

export type Theme = MinigameBase.Theme
export type Api = MinigameBase.Api

local GRID = 8
local CELLS = GRID * GRID
local MINE_COUNT = 10
local SAFE_CELLS = CELLS - MINE_COUNT

local CELL = 54
local GAP = 3
local BOARD = GRID * CELL + (GRID - 1) * GAP
local HEADER_HEIGHT = 40
local HEADER_GAP = 16

local BOOM_TIME = 1

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

local Minesweeper = MinigameBase.extend("Minesweeper", "MINESWEEPER.EXE", true)

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

local function isValidSave(saved: any): boolean
	if typeof(saved) ~= "table" then return false end

	for _, key in { "Mines", "Revealed", "Flags" } do
		local list = saved[key]
		if typeof(list) ~= "table" or #list ~= CELLS then return false end
	end

	return true
end

function Minesweeper.new(root: Frame, api: Api)
	local self = MinigameBase.new(root, api, Minesweeper)

	self.Buttons = {} :: { TextButton }
	self.Strokes = {} :: { UIStroke }
	self.Mines = {} :: { boolean }
	self.Revealed = {} :: { boolean }
	self.Flags = {} :: { boolean }

	self.Placed = false
	self.Dead = false
	self.Flagging = false
	self.Opened = 0
	self.Generation = 0

	return self
end

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

function Minesweeper:_count(index: number): number
	local count = 0
	forEachNeighbour(index, function(neighbour: number)
		if self.Mines[neighbour] then
			count += 1
		end
	end)
	return count
end

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

	self:PlaySound("Boom", 0.8)

	for index = 1, CELLS do
		if self.Mines[index] then
			self.Revealed[index] = true
		end
	end
	self:_repaint()

	local generation = self.Generation
	task.delay(BOOM_TIME, function()
		if self.Generation ~= generation then return end
		self:Reset()
	end)
end

function Minesweeper:_click(index: number, flagging: boolean)
	if self.Dead or self.Completed then return end

	if flagging then
		if self.Revealed[index] then return end
		self.Flags[index] = not self.Flags[index] or nil
		self:PlaySound("Flag", if self.Flags[index] then 1 else 0.8)
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

	self:PlaySound("Blip")

	self:_reveal(index)
	self:_updateHeader()

	if self.Opened >= SAFE_CELLS then
		self.Completed = true
		self.State = "won"
		self.Api.Complete()
	end
end

function Minesweeper:_build()
	local theme: Theme = self.Theme
	local root: Frame = self.Root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Parent = root

	local counter = self:NewLabel(header, `MINES {MINE_COUNT}`, 26)
	counter.Name = "Counter"
	counter.Size = UDim2.fromOffset(200, HEADER_HEIGHT)
	counter.TextXAlignment = Enum.TextXAlignment.Left
	self.Counter = counter

	local message = self:NewLabel(header, "", 30)
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 0)
	message.Position = UDim2.fromScale(0.5, 0)
	message.Size = UDim2.fromOffset(300, HEADER_HEIGHT)
	message.TextColor3 = theme.Danger
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
	self.FlagStroke = self:AddStroke(flagButton, theme.TextDim, 2)

	self:Track(flagButton.MouseButton1Click:Connect(function()
		self.Flagging = not self.Flagging
		self:_updateHeader()
	end))

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
		self.Strokes[index] = self:AddStroke(cell, theme.Panel, 2)

		self:Track(cell.MouseButton1Click:Connect(function()
			self:_click(index, self.Flagging)
		end))
		self:Track(cell.MouseButton2Click:Connect(function()
			self:_click(index, true)
		end))
	end
end

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
	if self.Dead or self.Completed or (not self.Placed and self.Opened == 0) then
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
	self.Completed = false
	self.State = "playing"
	self.Opened = 0
	table.clear(self.Mines)
	table.clear(self.Revealed)
	table.clear(self.Flags)
	self:_repaint()
end

function Minesweeper:OnDestroy()
	self.Generation += 1

	table.clear(self.Buttons)
	table.clear(self.Strokes)
end

return Minesweeper
