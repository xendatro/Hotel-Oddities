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

type Api = {
	Complete: () -> (),
	Fail: ((reason: string?) -> ())?,
	Theme: Theme,
	Sound: ((name: string, pitch: number?) -> ())?,
}

type Glyph = {
	Char: string,
	Color: string,
}

local COLUMNS = 4
local ROWS = 4
local CARDS = COLUMNS * ROWS
local PAIRS = CARDS // 2

local GLYPHS: { Glyph } = {
	{ Char = "🐸", Color = "Primary" },
	{ Char = "🚀", Color = "Text" },
	{ Char = "💀", Color = "Danger" },
	{ Char = "🔑", Color = "TextDim" },
	{ Char = "👾", Color = "Primary" },
	{ Char = "🍕", Color = "Text" },
	{ Char = "⚡", Color = "Danger" },
	{ Char = "💾", Color = "TextDim" },
}

local BACK_CHAR = "?"

local CARD_WIDTH = 150
local CARD_HEIGHT = 104
local GAP = 14
local BOARD_WIDTH = COLUMNS * CARD_WIDTH + (COLUMNS - 1) * GAP
local BOARD_HEIGHT = ROWS * CARD_HEIGHT + (ROWS - 1) * GAP

local HEADER_HEIGHT = 40
local HEADER_GAP = 16

local FLIP_BACK_TIME = 0.7

local Memory = {}
Memory.__index = Memory

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function newLayout(): { number }
	local layout: { number } = {}
	for pair = 1, PAIRS do
		table.insert(layout, pair)
		table.insert(layout, pair)
	end

	for index = CARDS, 2, -1 do
		local swap = math.random(1, index)
		layout[index], layout[swap] = layout[swap], layout[index]
	end

	return layout
end

local function isValidSave(saved: any): boolean
	if typeof(saved) ~= "table" then return false end

	local layout = saved.Layout
	local matched = saved.Matched
	local faceUp = saved.FaceUp
	if typeof(layout) ~= "table" or typeof(matched) ~= "table" or typeof(faceUp) ~= "table" then
		return false
	end
	if #layout ~= CARDS or #matched ~= CARDS or #faceUp ~= CARDS then
		return false
	end

	local seen: { [number]: number } = {}
	for index = 1, CARDS do
		local pair = layout[index]
		if typeof(pair) ~= "number" or pair < 1 or pair > PAIRS or pair % 1 ~= 0 then
			return false
		end
		seen[pair] = (seen[pair] or 0) + 1
	end

	for pair = 1, PAIRS do
		if seen[pair] ~= 2 then return false end
	end

	return true
end

function Memory.new(root: Frame, api: Api): any
	local self = setmetatable({}, Memory)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.Buttons = {} :: { TextButton }
	self.Strokes = {} :: { UIStroke }
	self.Connections = {} :: { RBXScriptConnection }

	self.Layout = {} :: { number }
	self.Matched = {} :: { boolean }
	self.FaceUp = {} :: { boolean }

	self.Pending = nil :: number?
	self.Locked = false
	self.Found = 0
	self.Moves = 0
	self.Won = false
	self.Generation = 0

	return self
end

function Memory:_glyphColor(index: number): Color3
	local glyph = GLYPHS[self.Layout[index]]
	return if glyph then (self.Theme :: any)[glyph.Color] else self.Theme.Text
end

function Memory:_paint(index: number)
	local theme: Theme = self.Theme
	local button: TextButton? = self.Buttons[index]
	local stroke: UIStroke? = self.Strokes[index]
	if not button or not stroke then return end

	local pair = self.Layout[index]
	local glyph = GLYPHS[pair]

	if self.Matched[index] then
		button.BackgroundColor3 = theme.Accent
		button.TextColor3 = theme.Background
		button.Text = if glyph then glyph.Char else BACK_CHAR
		stroke.Color = theme.Accent
		return
	end

	if self.FaceUp[index] then
		button.BackgroundColor3 = theme.Panel
		button.TextColor3 = self:_glyphColor(index)
		button.Text = if glyph then glyph.Char else BACK_CHAR
		stroke.Color = if self.Locked then theme.Danger else self:_glyphColor(index)
		return
	end

	button.BackgroundColor3 = theme.Grid
	button.TextColor3 = theme.TextDim
	button.Text = BACK_CHAR
	stroke.Color = theme.Panel
end

function Memory:_repaint()
	for index = 1, CARDS do
		self:_paint(index)
	end
	self:_updateHeader()
end

function Memory:_updateHeader()
	if not self.PairsLabel then return end

	self.PairsLabel.Text = `PAIRS {self.Found}/{PAIRS}`
	self.MovesLabel.Text = `MOVES {self.Moves}`

	if self.Won then
		self.Message.Text = "MATCHED"
		self.Message.TextColor3 = self.Theme.Accent
	elseif self.Locked then
		self.Message.Text = "NO MATCH"
		self.Message.TextColor3 = self.Theme.Danger
	else
		self.Message.Text = ""
		self.Message.TextColor3 = self.Theme.TextDim
	end
end

function Memory:_flipBack()
	self.Locked = false

	for index = 1, CARDS do
		if self.FaceUp[index] and not self.Matched[index] then
			self.FaceUp[index] = nil
			self:_paint(index)
		end
	end

	self.Pending = nil
	self:_updateHeader()
end

function Memory:_tap(index: number)
	if self.Won or self.Locked then return end
	if self.Matched[index] or self.FaceUp[index] then return end

	self.FaceUp[index] = true
	self:_paint(index)
	if self.Api.Sound then
		self.Api.Sound("Flip", if self.Pending then 1.12 else 1)
	end

	local first = self.Pending
	if not first then
		self.Pending = index
		return
	end

	self.Pending = nil
	self.Moves += 1

	if self.Layout[first] == self.Layout[index] then
		self.Matched[first] = true
		self.Matched[index] = true
		self.Found += 1
		if self.Api.Sound then
			self.Api.Sound("Chime", 1 + (self.Found - 1) * 0.06)
		end
		self:_paint(first)
		self:_paint(index)
		self:_updateHeader()

		if self.Found >= PAIRS then
			self:_win()
		end
		return
	end

	if self.Api.Sound then self.Api.Sound("Buzz") end

	self.Locked = true
	self:_paint(first)
	self:_paint(index)
	self:_updateHeader()

	local generation = self.Generation
	task.delay(FLIP_BACK_TIME, function()
		if self.Generation ~= generation then return end
		self:_flipBack()
	end)
end

function Memory:_win()
	if self.Won then return end
	self.Won = true

	self.Generation += 1
	self.Locked = false
	self.Pending = nil
	self:_updateHeader()

	self.Api.Complete()
end

function Memory:_build()
	local theme: Theme = self.Theme
	local root: Frame = self.Root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Parent = root

	local pairsLabel = Instance.new("TextLabel")
	pairsLabel.Name = "Pairs"
	pairsLabel.Size = UDim2.fromOffset(220, HEADER_HEIGHT)
	pairsLabel.BackgroundTransparency = 1
	pairsLabel.Font = theme.Font
	pairsLabel.Text = `PAIRS 0/{PAIRS}`
	pairsLabel.TextSize = 26
	pairsLabel.TextColor3 = theme.Text
	pairsLabel.TextXAlignment = Enum.TextXAlignment.Left
	pairsLabel.Parent = header
	self.PairsLabel = pairsLabel

	local message = Instance.new("TextLabel")
	message.Name = "Message"
	message.AnchorPoint = Vector2.new(0.5, 0)
	message.Position = UDim2.fromScale(0.5, 0)
	message.Size = UDim2.fromOffset(300, HEADER_HEIGHT)
	message.BackgroundTransparency = 1
	message.Font = theme.Font
	message.Text = ""
	message.TextSize = 28
	message.TextColor3 = theme.TextDim
	message.Parent = header
	self.Message = message

	local movesLabel = Instance.new("TextLabel")
	movesLabel.Name = "Moves"
	movesLabel.AnchorPoint = Vector2.new(1, 0)
	movesLabel.Position = UDim2.fromScale(1, 0)
	movesLabel.Size = UDim2.fromOffset(220, HEADER_HEIGHT)
	movesLabel.BackgroundTransparency = 1
	movesLabel.Font = theme.Font
	movesLabel.Text = "MOVES 0"
	movesLabel.TextSize = 26
	movesLabel.TextColor3 = theme.TextDim
	movesLabel.TextXAlignment = Enum.TextXAlignment.Right
	movesLabel.Parent = header
	self.MovesLabel = movesLabel

	local board = Instance.new("Frame")
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0)
	board.Position = UDim2.new(0.5, 0, 0, HEADER_HEIGHT + HEADER_GAP)
	board.Size = UDim2.fromOffset(BOARD_WIDTH, BOARD_HEIGHT)
	board.BackgroundTransparency = 1
	board.BorderSizePixel = 0
	board.Parent = root
	self.Board = board

	for index = 1, CARDS do
		local row = (index - 1) // COLUMNS
		local column = (index - 1) % COLUMNS

		local card = Instance.new("TextButton")
		card.Name = `Card{index}`
		card.Position = UDim2.fromOffset(column * (CARD_WIDTH + GAP), row * (CARD_HEIGHT + GAP))
		card.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
		card.BackgroundColor3 = theme.Grid
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Font = theme.Font
		card.Text = BACK_CHAR
		card.TextSize = 64
		card.TextColor3 = theme.TextDim
		card.Parent = board

		self.Buttons[index] = card
		self.Strokes[index] = addStroke(card, theme.Panel, 3)

		table.insert(
			self.Connections,
			card.Activated:Connect(function()
				self:_tap(index)
			end)
		)
	end
end

function Memory:Start(saved: any?)
	self:_build()

	if isValidSave(saved) then
		for index = 1, CARDS do
			self.Layout[index] = saved.Layout[index]
			self.Matched[index] = saved.Matched[index] == true or nil
			if self.Matched[index] then
				self.Found += 1
			end
		end
		self.Found //= 2

		if typeof(saved.Moves) == "number" then
			self.Moves = math.max(0, math.floor(saved.Moves))
		end

		local up: number? = nil
		local count = 0
		for index = 1, CARDS do
			if saved.FaceUp[index] == true and not self.Matched[index] then
				count += 1
				up = index
			end
		end
		if count == 1 and up then
			self.FaceUp[up] = true
			self.Pending = up
		end
	else
		self.Layout = newLayout()
	end

	self:_repaint()
end

function Memory:Serialize(): any?
	if self.Won or #self.Layout ~= CARDS then return nil end
	if self.Moves == 0 and self.Found == 0 and not self.Pending then return nil end

	local layout, matched, faceUp = {}, {}, {}
	for index = 1, CARDS do
		layout[index] = self.Layout[index]
		matched[index] = self.Matched[index] == true
		faceUp[index] = self.FaceUp[index] == true and not self.Locked
	end

	return {
		Layout = layout,
		Matched = matched,
		FaceUp = faceUp,
		Moves = self.Moves,
	}
end

function Memory:Reset()
	self.Generation += 1

	self.Layout = newLayout()
	table.clear(self.Matched)
	table.clear(self.FaceUp)
	self.Pending = nil
	self.Locked = false
	self.Found = 0
	self.Moves = 0
	self.Won = false

	self:_repaint()
end

function Memory:Destroy()
	self.Generation += 1
	self.Won = true
	self.Locked = true

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	table.clear(self.Buttons)
	table.clear(self.Strokes)

	self.PairsLabel = nil
	self.MovesLabel = nil
	self.Message = nil
	self.Board = nil
	self.Root:ClearAllChildren()
end

return {
	Id = "Memory",
	Title = "MEMORY.EXE",
	SupportsReset = true,
	new = function(root: Frame, api: Api)
		return Memory.new(root, api)
	end,
}
