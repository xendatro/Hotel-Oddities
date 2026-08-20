--- MEMORY.EXE -- sixteen face-down cards, eight pairs, turn them all up to open the lock.
---
--- This is the touch player's Minesweeper. A minefield asks for a fingertip on a 54-pixel square and
--- for a second mouse button nobody carrying a phone has; a memory board asks for one tap on a card
--- the size of a thumb and nothing else at all. So the cards are deliberately enormous -- the grid is
--- only four by four precisely so that each cell can be huge -- and there is no keyboard input, no
--- modifier, no second button and no drag. Every interaction in this game is "tap a card".
---
--- The mismatch pause is the one piece of time in the game, and it is a `task.delay` guarded by a
--- generation counter rather than a Heartbeat state machine: there is exactly one timer, it exists at
--- most once, and a reset or a teardown that lands inside it simply moves the generation on so the
--- callback finds a board it no longer belongs to and returns. Input is locked for its duration --
--- letting a third card turn while two are still deciding is how a memory game gets an unwinnable
--- board.
---
--- Colour is decoration here and the glyph is the identity. The framework hands out four colours that
--- read at a glance against the panel, so eight glyphs share them two apiece; no two cards that share
--- a colour ever share a character, and green is spent entirely on "matched" so that a solved pair
--- reads as solved from across the room.

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

type Glyph = {
	Char: string,
	--- Which entry of the handed-out palette paints this glyph. Never "Accent": that colour means
	--- matched, and a card must not wear the win state before it has earned it.
	Color: string,
}

local COLUMNS = 4
local ROWS = 4
local CARDS = COLUMNS * ROWS
local PAIRS = CARDS // 2

--- Eight characters that are unmistakable from each other at a glance and that the Arcade font
--- actually draws: four letters/digits and four symbols, so a wrong guess is obvious even to someone
--- who has stopped reading and is going on shape alone.
local GLYPHS: { Glyph } = {
	{ Char = "A", Color = "Primary" },
	{ Char = "7", Color = "Text" },
	{ Char = "#", Color = "Danger" },
	{ Char = "X", Color = "TextDim" },
	{ Char = "O", Color = "Primary" },
	{ Char = "%", Color = "Text" },
	{ Char = "+", Color = "Danger" },
	{ Char = "=", Color = "TextDim" },
}

--- What the back of a card says. One character, so it centres the same way the faces do.
local BACK_CHAR = "?"

--- Big on purpose: the whole reason this game exists instead of Minesweeper is that a finger can hit
--- it. 150x104 with a 14 gap fills 642x458 of the 784x532 the framework gives us, leaving the header
--- its band and a comfortable margin all round.
local CARD_WIDTH = 150
local CARD_HEIGHT = 104
local GAP = 14
local BOARD_WIDTH = COLUMNS * CARD_WIDTH + (COLUMNS - 1) * GAP
local BOARD_HEIGHT = ROWS * CARD_HEIGHT + (ROWS - 1) * GAP

local HEADER_HEIGHT = 40
local HEADER_GAP = 16

--- How long a mismatched pair stays face up before it turns back. Long enough to memorise both
--- cards, short enough that it never feels like being told off.
local FLIP_BACK_TIME = 0.7

local Memory = {}
Memory.__index = Memory

--- Helpers --------------------------------------------------------------------------------------

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	-- Border rather than Contextual: the chunky outside edge is the look the whole set shares.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

--- A fresh deal: each of the eight glyphs twice, shuffled in place. Fisher-Yates over `math.random`
--- is plenty -- nothing here needs a reproducible stream, only an unpredictable one.
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

--- Whether a restored snapshot is still a board this game can deal. Saved state outlives nothing but
--- the session, but a truncated or hand-edited one should quietly start a new game rather than throw
--- on the player or hand them a board with three of one glyph on it.
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

--- Construction ---------------------------------------------------------------------------------

function Memory.new(root: Frame, api: Api): any
	local self = setmetatable({}, Memory)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.Buttons = {} :: { TextButton }
	self.Strokes = {} :: { UIStroke }
	self.Connections = {} :: { RBXScriptConnection }

	--- Which glyph sits on each card, whether that card is solved, and whether it is currently
	--- turned over. Three flat arrays of sixteen, which is also exactly what gets serialised.
	self.Layout = {} :: { number }
	self.Matched = {} :: { boolean }
	self.FaceUp = {} :: { boolean }

	--- The one unresolved card, if the player is mid-guess.
	self.Pending = nil :: number?
	--- True only while a mismatched pair is on show; taps do nothing until it clears.
	self.Locked = false
	self.Found = 0
	self.Moves = 0
	self.Won = false
	--- Bumped by every reset and by teardown, so a flip-back that belongs to an older board knows to
	--- do nothing when it finally fires.
	self.Generation = 0

	return self
end

--- Drawing --------------------------------------------------------------------------------------

--- The colour a face-up, not-yet-matched card wears.
function Memory:_glyphColor(index: number): Color3
	local glyph = GLYPHS[self.Layout[index]]
	return if glyph then (self.Theme :: any)[glyph.Color] else self.Theme.Text
end

--- The look of one card, from whatever is currently true about it. Called per card rather than per
--- board wherever only one card changed, so a tap repaints one thing.
function Memory:_paint(index: number)
	local theme: Theme = self.Theme
	local button: TextButton? = self.Buttons[index]
	local stroke: UIStroke? = self.Strokes[index]
	if not button or not stroke then return end

	local pair = self.Layout[index]
	local glyph = GLYPHS[pair]

	if self.Matched[index] then
		-- Solved cards are filled, not outlined: eight blocks of green is the win state announcing
		-- itself before the fanfare ever gets a chance to.
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
		-- While a wrong pair is being shown both of its cards wear the danger edge, which is the only
		-- feedback the mismatch gets and the only reason the pause reads as deliberate.
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

--- Rules ----------------------------------------------------------------------------------------

--- Turns the pending mismatched pair back over. Only ever reached through the guarded delay below.
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
	-- Everything that makes a tap meaningless, in one place: the game is over, a mismatch is still on
	-- show, the card is already solved, or it is the card the player just turned.
	if self.Won or self.Locked then return end
	if self.Matched[index] or self.FaceUp[index] then return end

	self.FaceUp[index] = true
	self:_paint(index)
	-- The second card of a guess turns a shade higher than the first, so the pair reads as a pair
	-- before either the match chime or the buzz has said which kind it was.
	if self.Api.Sound then
		self.Api.Sound("Flip", if self.Pending then 1.12 else 1)
	end

	local first = self.Pending
	if not first then
		self.Pending = index
		return
	end

	-- A move is a guess, not a tap: the counter ticks when the second card lands.
	self.Pending = nil
	self.Moves += 1

	if self.Layout[first] == self.Layout[index] then
		self.Matched[first] = true
		self.Matched[index] = true
		self.Found += 1
		-- A step up per pair, so a board that is nearly solved sounds nearly solved. The eighth pair
		-- gets no extra ending of its own: the framework's jingle is already following it.
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
		-- A reset or a teardown in the meantime has already turned these cards over, or thrown the
		-- whole board away; either way this timer belongs to a game that no longer exists.
		if self.Generation ~= generation then return end
		self:_flipBack()
	end)
end

function Memory:_win()
	if self.Won then return end
	self.Won = true

	-- Nothing is left to tap and no timer is outstanding, but bumping the generation makes that true
	-- by construction rather than by argument.
	self.Generation += 1
	self.Locked = false
	self.Pending = nil
	self:_updateHeader()

	-- Last, because the framework tears this game down from inside the fanfare that follows.
	self.Api.Complete()
end

--- Building -------------------------------------------------------------------------------------

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

		-- `Activated` rather than `MouseButton1Click`: it is the one signal that a touch, a click and
		-- a gamepad button all arrive on, and this game deliberately accepts nothing else.
		table.insert(
			self.Connections,
			card.Activated:Connect(function()
				self:_tap(index)
			end)
		)
	end
end

--- Contract -------------------------------------------------------------------------------------

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
		-- Found counts cards, not pairs, until here; a snapshot with an odd count is impossible from
		-- `Serialize` but costs nothing to survive.
		self.Found //= 2

		if typeof(saved.Moves) == "number" then
			self.Moves = math.max(0, math.floor(saved.Moves))
		end

		-- At most one unsolved card may come back face up. Two would be a guess frozen mid-air with
		-- no timer left to resolve it, so the pair is simply returned to the deck.
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
	-- A board that was never played is not worth coming back to, and a solved one has nothing left to
	-- come back to. Both hand back nothing so the framework clears the slot.
	if self.Won or #self.Layout ~= CARDS then return nil end
	if self.Moves == 0 and self.Found == 0 and not self.Pending then return nil end

	local layout, matched, faceUp = {}, {}, {}
	for index = 1, CARDS do
		layout[index] = self.Layout[index]
		matched[index] = self.Matched[index] == true
		-- A mismatched pair caught mid-pause is written down face down: it was a tenth of a second
		-- from turning over anyway, and remembering it would resume a guess nobody can finish.
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
	-- Retires any outstanding flip-back before the board underneath it changes.
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
	-- Stops a pending flip-back from touching a board that is no longer on screen, and any further
	-- tap from being counted.
	self.Generation += 1
	self.Won = true
	self.Locked = true

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	table.clear(self.Buttons)
	table.clear(self.Strokes)

	-- Teardown can arrive on a half-built game -- a fault partway through `Start` still gets closed
	-- down -- so nothing here assumes a label, a board or a card ever existed.
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
