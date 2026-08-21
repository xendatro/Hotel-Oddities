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

local RunService = game:GetService("RunService")

local TARGET_HITS = 20
local MISS_LIMIT = 3
local HIT_PITCH_RISE = 0.6
local FIRST_LIFETIME = 5
local LAST_LIFETIME = 1.875

local TARGET_SIZE = 84
local RINGS = {
	{ Inset = 0, Color = "Danger" },
	{ Inset = 14, Color = "Text" },
	{ Inset = 26, Color = "Danger" },
	{ Inset = 34, Color = "Accent" },
}

local HEADER_HEIGHT = 40
local BAR_HEIGHT = 8
local BAR_GAP = 12
local MIN_TRAVEL = 200
local PLACEMENT_TRIES = 24
local URGENT = 0.8

local AimTrainer = {}
AimTrainer.__index = AimTrainer

AimTrainer.Id = "AimTrainer"
AimTrainer.Title = "AIMTRAIN.EXE"
AimTrainer.SupportsReset = true

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function AimTrainer.new(root: Frame, api: Api): any
	local self = setmetatable({}, AimTrainer)

	self.Root = root
	self.Api = api
	self.Theme = api.Theme

	self.Hits = 0
	self.Misses = 0
	self.Lifetime = FIRST_LIFETIME
	self.Remaining = FIRST_LIFETIME
	self.Won = false
	self.Last = Vector2.new(-1000, -1000)
	self.Connection = nil :: RBXScriptConnection?

	return self
end

function AimTrainer:_updateHeader()
	local theme: Theme = self.Theme

	self.HitLabel.Text = `HITS {self.Hits}/{TARGET_HITS}`
	self.MissLabel.Text = `MISS {self.Misses}/{MISS_LIMIT}`
	self.MissLabel.TextColor3 = if self.Misses > 0 then theme.Danger else theme.TextDim
end

function AimTrainer:_lifetime(): number
	local span = math.max(TARGET_HITS - 1, 1)
	local alpha = math.clamp(self.Hits / span, 0, 1)
	return FIRST_LIFETIME + (LAST_LIFETIME - FIRST_LIFETIME) * alpha
end

function AimTrainer:_updateBar()
	local theme: Theme = self.Theme
	local fraction = math.clamp(self.Remaining / self.Lifetime, 0, 1)

	self.Bar.Size = UDim2.new(fraction, 0, 1, 0)
	self.Bar.BackgroundColor3 = if self.Remaining <= URGENT then theme.Danger else theme.Primary
end

function AimTrainer:_pick(): Vector2
	local area = self.Area.AbsoluteSize
	local width = if area.X > 0 then area.X else 784
	local height = if area.Y > 0 then area.Y else 532 - HEADER_HEIGHT - BAR_HEIGHT - BAR_GAP

	local maxX = math.max(math.floor(width - TARGET_SIZE), 0)
	local maxY = math.max(math.floor(height - TARGET_SIZE), 0)

	local best = Vector2.new(math.random(0, maxX), math.random(0, maxY))
	for _ = 1, PLACEMENT_TRIES do
		local candidate = Vector2.new(math.random(0, maxX), math.random(0, maxY))
		if (candidate - self.Last).Magnitude >= MIN_TRAVEL then
			return candidate
		end
		best = candidate
	end
	return best
end

function AimTrainer:_spawn()
	local position = self:_pick()
	self.Last = position

	self.Target.Position = UDim2.fromOffset(position.X, position.Y)
	self.Target.Visible = true

	self.Lifetime = self:_lifetime()
	self.Remaining = self.Lifetime
	self:_updateBar()
end

function AimTrainer:_hit()
	if self.Won then return end

	self.Hits += 1
	self:_updateHeader()

	if self.Api.Sound then
		local climb = math.clamp((self.Hits - 1) / math.max(TARGET_HITS - 1, 1), 0, 1)
		self.Api.Sound("Hit", 1 + HIT_PITCH_RISE * climb)
	end

	if self.Hits >= TARGET_HITS then
		self.Won = true
		self.Target.Visible = false
		self.Api.Complete()
		return
	end

	self:_spawn()
end

function AimTrainer:_miss()
	if self.Won then return end

	self.Misses += 1
	if self.Api.Sound and self.Misses < MISS_LIMIT then
		self.Api.Sound("Buzz")
	end
	local wiped = self.Misses >= MISS_LIMIT
	if wiped then
		self.Misses = 0
		self.Hits = 0
	end

	self:_updateHeader()
	self:_spawn()

	if wiped and self.Api.Fail then
		self.Api.Fail("RUN WIPED")
	end
end

function AimTrainer:_build()
	local theme: Theme = self.Theme
	local root: Frame = self.Root

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Parent = root

	local hits = Instance.new("TextLabel")
	hits.Name = "Hits"
	hits.Size = UDim2.fromOffset(260, HEADER_HEIGHT)
	hits.BackgroundTransparency = 1
	hits.Font = theme.Font
	hits.Text = `HITS 0/{TARGET_HITS}`
	hits.TextSize = 26
	hits.TextColor3 = theme.Text
	hits.TextXAlignment = Enum.TextXAlignment.Left
	hits.Parent = header
	self.HitLabel = hits

	local misses = Instance.new("TextLabel")
	misses.Name = "Misses"
	misses.AnchorPoint = Vector2.new(1, 0)
	misses.Position = UDim2.fromScale(1, 0)
	misses.Size = UDim2.fromOffset(260, HEADER_HEIGHT)
	misses.BackgroundTransparency = 1
	misses.Font = theme.Font
	misses.Text = `MISS 0/{MISS_LIMIT}`
	misses.TextSize = 26
	misses.TextColor3 = theme.TextDim
	misses.TextXAlignment = Enum.TextXAlignment.Right
	misses.Parent = header
	self.MissLabel = misses

	local track = Instance.new("Frame")
	track.Name = "Clock"
	track.Position = UDim2.fromOffset(0, HEADER_HEIGHT)
	track.Size = UDim2.new(1, 0, 0, BAR_HEIGHT)
	track.BackgroundColor3 = theme.Panel
	track.BorderSizePixel = 0
	track.Parent = root
	addStroke(track, theme.Grid, 2)

	local bar = Instance.new("Frame")
	bar.Name = "Fill"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = theme.Primary
	bar.BorderSizePixel = 0
	bar.Parent = track
	self.Bar = bar

	local area = Instance.new("Frame")
	area.Name = "Area"
	area.Position = UDim2.fromOffset(0, HEADER_HEIGHT + BAR_HEIGHT + BAR_GAP)
	area.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + BAR_HEIGHT + BAR_GAP))
	area.BackgroundColor3 = theme.Panel
	area.BackgroundTransparency = 0.4
	area.BorderSizePixel = 0
	area.ClipsDescendants = true
	area.Parent = root
	addStroke(area, theme.Grid, 2)
	self.Area = area

	local target = Instance.new("TextButton")
	target.Name = "Target"
	target.Size = UDim2.fromOffset(TARGET_SIZE, TARGET_SIZE)
	target.BackgroundTransparency = 1
	target.BorderSizePixel = 0
	target.AutoButtonColor = false
	target.Text = ""
	target.Visible = false
	target.Parent = area
	self.Target = target

	for index, ring in RINGS do
		local size = TARGET_SIZE - ring.Inset * 2
		local piece = Instance.new("Frame")
		piece.Name = `Ring{index}`
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.Position = UDim2.fromScale(0.5, 0.5)
		piece.Size = UDim2.fromOffset(size, size)
		piece.BackgroundColor3 = theme[ring.Color]
		piece.BorderSizePixel = 0
		piece.Active = false
		piece.ZIndex = index + 1
		piece.Parent = target
	end

	target.MouseButton1Click:Connect(function()
		self:_hit()
	end)
end

function AimTrainer:Start(saved: any?)
	self:_build()

	if typeof(saved) == "table" and typeof(saved.Hits) == "number" then
		self.Hits = math.clamp(math.floor(saved.Hits), 0, TARGET_HITS - 1)
	end

	self:_updateHeader()
	self:_spawn()

	self.Connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if self.Won or not self.Target.Visible then return end

		self.Remaining -= deltaTime
		self:_updateBar()

		if self.Remaining <= 0 then
			self:_miss()
		end
	end)
end

function AimTrainer:Serialize(): any?
	if self.Won or self.Hits <= 0 then return nil end
	return { Hits = self.Hits }
end

function AimTrainer:Reset()
	self.Hits = 0
	self.Misses = 0
	self.Won = false
	self.Last = Vector2.new(-1000, -1000)
	self:_updateHeader()
	self:_spawn()
end

function AimTrainer:Destroy()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
	self.Root:ClearAllChildren()
end

return AimTrainer
