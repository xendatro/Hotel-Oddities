local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MinigameBase = require(ReplicatedStorage.Classes.Minigames.MinigameBase)

local PADS = 4
local WIN_LENGTH = 7
local MISTAKES_TO_DEMOTE = 3
local LIT_TIME = 0.42
local GAP_TIME = 0.16
local LEAD_IN = 0.6
local LOCKOUT_LEAD_IN = 1.3
local PRESS_TIME = 0.2

export type Theme = MinigameBase.Theme
export type Api = MinigameBase.Api

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

local Simon = MinigameBase.extend("Simon", "SIMON.EXE", true)

function Simon.new(root: Frame, api: Api)
	local self = MinigameBase.new(root, api, Simon)

	self.State = "playback"
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

	return self
end

function Simon:_buildBoard()
	local theme = self.Theme

	local board = self:BuildBoardFrame(1, {
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.92, 0.74),
	})

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
		self:Track(button.Activated:Connect(function()
			self:_press(index)
		end))
	end

	local centre = self:NewLabel(board, "", 22)
	centre.Name = "Round"
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.Position = UDim2.fromScale(0.5, 0.5)
	centre.Size = UDim2.fromScale(0.3, 0.14)
	centre.TextColor3 = self.Theme.TextDim
	self.RoundLabel = centre
end

function Simon:_buildChrome()
	local progress = self:BuildStatusBar("Progress", "WATCH")
	self.ProgressLabel = progress
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

function Simon:_tone(pad: number)
	self:PlaySound("Tone", PAD_PITCH[pad] or 1)
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
	self:Say("WATCH", self.Theme.TextDim)
	self:_paintPads()
end

function Simon:_beginInput()
	self.State = "input"
	self.Lit = nil
	self.EntryIndex = 1
	self:Say("REPEAT", self.Theme.Primary)
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
	self:Say("GOOD", self.Theme.Accent)
end

function Simon:_wrong()
	self.Mistakes += 1

	if self.Mistakes < MISTAKES_TO_DEMOTE then
		self:PlaySound("Buzz")
	end

	if self.Mistakes >= MISTAKES_TO_DEMOTE then
		self.Mistakes = 0
		self:_reseed(1)
		self:_beginPlayback()
		self.Timer = LOCKOUT_LEAD_IN
		self:Say("LOCKOUT", self.Theme.Danger)
		self:FailRun("LOCKED OUT")
		return
	end

	self:_beginPlayback()
	self:Say(string.format("AGAIN %d/%d", self.Mistakes, MISTAKES_TO_DEMOTE), self.Theme.Danger)
end

function Simon:_win()
	if self.Completed then return end
	self.Reached = WIN_LENGTH
	self.Lit = nil
	self:_paintPads()
	self:Win()
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

function Simon:Start(saved: any?)
	local length = 1
	local reached = self:ClampedSavedNumber(saved, "Length", 0, WIN_LENGTH - 1)
	if reached then
		self.Reached = reached
		length = math.max(1, reached)
	end

	self:_buildBoard()
	self:_buildChrome()
	self:_reseed(length)
	self:ConnectKeys(KEYS, function(pad: number)
		self:_press(pad)
	end)
	self:_beginPlayback()

	self:StartHeartbeat(function(deltaTime: number)
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

function Simon:OnDestroy()
	table.clear(self.PadButtons)
end

return Simon
