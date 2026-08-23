local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PADS = 4
local WIN_LENGTH = 7
local MISTAKES_TO_DEMOTE = 3
local LIT_TIME = 0.42
local GAP_TIME = 0.16
local LEAD_IN = 0.6
local LOCKOUT_LEAD_IN = 1.3
local PRESS_TIME = 0.2

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

local PAD_PITCH = { 1, 1.25, 1.5, 2 }

type PadLayout = {
	Key: string,
	X: number,
	Y: number,
}

local PAD_LAYOUT: { PadLayout } = {
	{ Key = "W", X = 0.5, Y = 0.18 },
	{ Key = "D", X = 0.82, Y = 0.5 },
	{ Key = "S", X = 0.5, Y = 0.82 },
	{ Key = "A", X = 0.18, Y = 0.5 },
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

local Simon = {}
Simon.__index = Simon

function Simon.new(root: Frame, api: Api)
	local self = setmetatable({}, Simon)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.State = "playback"
	self.Completed = false
	self.Random = Random.new()

	self.Sequence = {} :: { number }
	self.EntryIndex = 1
	self.Mistakes = 0
	self.Reached = 0

	self.PlayIndex = 0
	self.Timer = LEAD_IN
	self.Lit = nil :: number?
	self.PressUntil = {} :: { [number]: number }
	self.Painted = {} :: { [number]: boolean }

	self.PadButtons = {} :: { TextButton }
	self.PadColors = {} :: { Color3 }
	self.Connections = {} :: { RBXScriptConnection }

	return self
end

function Simon:_buildBoard()
	local theme = self.Theme

	local board = newFrame(self.Root, theme.Background, theme.Primary, 4)
	board.Name = "Board"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.52)
	board.Size = UDim2.fromScale(0.92, 0.74)

	local ratio = Instance.new("UIAspectRatioConstraint")
	ratio.AspectRatio = 1
	ratio.DominantAxis = Enum.DominantAxis.Height
	ratio.Parent = board

	self.Board = board
	self.PadColors = { theme.Primary, theme.Accent, theme.Danger, theme.Text }

	for index, layout in PAD_LAYOUT do
		local button = Instance.new("TextButton")
		button.Name = "Pad" .. index
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromScale(layout.X, layout.Y)
		button.Size = UDim2.fromScale(0.32, 0.32)
		button.BackgroundColor3 = self.PadColors[index]
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Font = theme.Font
		button.Text = layout.Key
		button.TextSize = 34
		button.TextColor3 = theme.Background
		button.Parent = board

		local stroke = Instance.new("UIStroke")
		stroke.Color = theme.Grid
		stroke.Thickness = 4
		stroke.Parent = button

		self.PadButtons[index] = button
		table.insert(
			self.Connections,
			button.Activated:Connect(function()
				self:_press(index)
			end)
		)
	end

	local centre = newLabel(board, theme, "", 22)
	centre.Name = "Round"
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromScale(0.3, 0.14)
	centre.TextColor3 = theme.TextDim
	self.RoundLabel = centre
end

function Simon:_buildChrome()
	local theme = self.Theme

	local status = newFrame(self.Root, theme.Panel, theme.Grid, 3)
	status.Name = "Status"
	status.AnchorPoint = Vector2.new(0.5, 0.5)
	status.Position = UDim2.fromScale(0.5, 0.06)
	status.Size = UDim2.fromScale(0.92, 0.08)

	local progress = newLabel(status, theme, "", 24)
	progress.Name = "Progress"
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.Position = UDim2.fromScale(0.03, 0)
	progress.Size = UDim2.fromScale(0.45, 1)
	self.ProgressLabel = progress

	local message = newLabel(status, theme, "WATCH", 22)
	message.Name = "Message"
	message.TextColor3 = theme.TextDim
	message.TextXAlignment = Enum.TextXAlignment.Right
	message.Position = UDim2.fromScale(0.52, 0)
	message.Size = UDim2.fromScale(0.45, 1)
	self.MessageLabel = message
end

function Simon:_paintPads()
	local now = os.clock()

	for index, button in self.PadButtons do
		local lit = self.Lit == index or (self.PressUntil[index] or 0) > now
		if self.Painted[index] == lit then continue end

		self.Painted[index] = lit
		local color = self.PadColors[index]
		button.BackgroundColor3 = if lit then color else color:Lerp(self.Theme.Background, 0.72)
		button.TextColor3 = if lit then self.Theme.Background else color:Lerp(self.Theme.Background, 0.4)
	end
end

function Simon:_refreshLabels()
	self.ProgressLabel.Text = string.format("ROUND %d/%d", #self.Sequence, WIN_LENGTH)
	self.RoundLabel.Text = string.format("%d", #self.Sequence)
end

function Simon:_say(text: string, color: Color3)
	self.MessageLabel.Text = text
	self.MessageLabel.TextColor3 = color
end

function Simon:_tone(pad: number)
	if self.Api.Sound then
		self.Api.Sound("Tone", PAD_PITCH[pad] or 1)
	end
end

function Simon:_extend()
	table.insert(self.Sequence, self.Random:NextInteger(1, PADS))
end

function Simon:_beginPlayback()
	self.State = "playback"
	self.PlayIndex = 0
	self.Timer = LEAD_IN
	self.Lit = nil
	self.EntryIndex = 1
	self:_refreshLabels()
	self:_say("WATCH", self.Theme.TextDim)
	self:_paintPads()
end

function Simon:_beginInput()
	self.State = "input"
	self.Lit = nil
	self.EntryIndex = 1
	self:_say("REPEAT", self.Theme.Primary)
end

function Simon:_reseed(length: number)
	self.Sequence = {}
	for _ = 1, math.max(1, length) do
		self:_extend()
	end
end

function Simon:_press(pad: number)
	if self.State ~= "input" then return end

	self.PressUntil[pad] = os.clock() + PRESS_TIME
	self:_paintPads()
	self:_tone(pad)

	if self.Sequence[self.EntryIndex] ~= pad then
		self:_wrong()
		return
	end

	self.EntryIndex += 1
	if self.EntryIndex <= #self.Sequence then return end

	self.Reached = math.max(self.Reached, #self.Sequence)
	self.Mistakes = 0

	if #self.Sequence >= WIN_LENGTH then
		self:_win()
		return
	end

	self:_extend()
	self:_beginPlayback()
	self:_say("GOOD", self.Theme.Accent)
end

function Simon:_wrong()
	self.Mistakes += 1

	if self.Api.Sound and self.Mistakes < MISTAKES_TO_DEMOTE then
		self.Api.Sound("Buzz")
	end

	if self.Mistakes >= MISTAKES_TO_DEMOTE then
		self.Mistakes = 0
		self:_reseed(1)
		self:_beginPlayback()
		self.Timer = LOCKOUT_LEAD_IN
		self:_say("LOCKOUT", self.Theme.Danger)
		if self.Api.Fail then self.Api.Fail("LOCKED OUT") end
		return
	end

	self:_beginPlayback()
	self:_say(string.format("AGAIN %d/%d", self.Mistakes, MISTAKES_TO_DEMOTE), self.Theme.Danger)
end

function Simon:_win()
	if self.Completed then return end
	self.Completed = true
	self.State = "won"
	self.Reached = WIN_LENGTH

	self.Lit = nil
	self:_paintPads()
	self:_say("BREACHED", self.Theme.Accent)

	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	self.Api.Complete()
end

function Simon:_step(deltaTime: number)
	if self.State == "won" or self.State == "dead" then return end

	if self.State == "playback" then
		self.Timer -= deltaTime
		if self.Timer <= 0 then
			if self.Lit then
				self.Lit = nil
				self.Timer = GAP_TIME
				if self.PlayIndex >= #self.Sequence then
					self:_beginInput()
				end
			else
				self.PlayIndex += 1
				self.Lit = self.Sequence[self.PlayIndex]
				self.Timer = LIT_TIME
				if self.Lit then self:_tone(self.Lit) end
			end
		end
	end

	self:_paintPads()
end

local KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.W] = 1,
	[Enum.KeyCode.Up] = 1,
	[Enum.KeyCode.D] = 2,
	[Enum.KeyCode.Right] = 2,
	[Enum.KeyCode.S] = 3,
	[Enum.KeyCode.Down] = 3,
	[Enum.KeyCode.A] = 4,
	[Enum.KeyCode.Left] = 4,
}

function Simon:_connectInput()
	table.insert(
		self.Connections,
		UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			local pad = KEYS[input.KeyCode]
			if pad then
				self:_press(pad)
			end
		end)
	)
end

function Simon:Start(saved: any?)
	local length = 1
	if type(saved) == "table" and type(saved.Length) == "number" then
		self.Reached = math.clamp(math.floor(saved.Length), 0, WIN_LENGTH - 1)
		length = math.max(1, self.Reached)
	end

	self:_buildBoard()
	self:_buildChrome()
	self:_reseed(length)
	self:_connectInput()
	self:_beginPlayback()

	self.Heartbeat = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end)
end

function Simon:Serialize(): any?
	if self.Reached <= 0 then return nil end
	return { Length = self.Reached }
end

function Simon:Reset()
	if self.State == "won" then return end

	self.Mistakes = 0
	self.Reached = 0
	table.clear(self.PressUntil)
	self:_reseed(1)
	self:_beginPlayback()
end

function Simon:Destroy()
	self.State = "dead"

	if self.Heartbeat then
		self.Heartbeat:Disconnect()
		self.Heartbeat = nil
	end

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)

	table.clear(self.PadButtons)
	self.Root:ClearAllChildren()
end

return {
	Id = "Simon",
	Title = "SIMON.EXE",
	SupportsReset = true,
	new = function(root: Frame, api: Api)
		return Simon.new(root, api)
	end,
}
