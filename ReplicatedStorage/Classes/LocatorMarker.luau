local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PlayerLocatorConfig = require(ReplicatedStorage.Configs.PlayerLocatorConfig)

local LocatorMarker = {}
LocatorMarker.__index = LocatorMarker

local HIGHLIGHT = PlayerLocatorConfig.Highlight
local MARKER = PlayerLocatorConfig.Marker
local FOCUS = PlayerLocatorConfig.Focus
local PRESS = PlayerLocatorConfig.Press
local COLORS = PlayerLocatorConfig.Colors

local IN_INFO = TweenInfo.new(FOCUS.InTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local OUT_INFO = TweenInfo.new(FOCUS.OutTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local PRESS_INFO = TweenInfo.new(PRESS.Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CONFIRM_INFO = TweenInfo.new(PRESS.ConfirmTime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TINT_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function circle(parent: Instance, name: string, size: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size, size)
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame

	return frame
end

local function build(player: Player, parent: Instance)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = `{player.Name}Marker`
	billboard.Active = true
	billboard.AlwaysOnTop = true
	billboard.ResetOnSpawn = false
	billboard.ClipsDescendants = false
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(MARKER.Size.X, MARKER.Size.Y)
	billboard.StudsOffsetWorldSpace = MARKER.Offset
	billboard.MaxDistance = MARKER.MaxDistance
	billboard.Enabled = false
	billboard.Parent = parent

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(MARKER.Size.X, MARKER.Size.Y)
	root.BackgroundTransparency = 1
	root.Parent = billboard

	local rootScale = Instance.new("UIScale")
	rootScale.Parent = root

	local bubbleSpan = math.ceil(MARKER.BubbleSize * MARKER.HaloScale)

	local bubble = Instance.new("CanvasGroup")
	bubble.Name = "Bubble"
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Position = UDim2.new(0.5, 0, 0, MARKER.BubbleCentre)
	bubble.Size = UDim2.fromOffset(bubbleSpan, bubbleSpan)
	bubble.BackgroundTransparency = 1
	bubble.GroupTransparency = 1
	bubble.Visible = false
	bubble.Parent = root

	local bubbleScale = Instance.new("UIScale")
	bubbleScale.Scale = FOCUS.RestScale
	bubbleScale.Parent = bubble

	local halo = circle(bubble, "Halo", bubbleSpan)
	halo.BackgroundColor3 = COLORS.Halo
	halo.BackgroundTransparency = MARKER.HaloTransparency

	local haloScale = Instance.new("UIScale")
	haloScale.Parent = halo

	local face = circle(bubble, "Face", MARKER.BubbleSize)
	face.BackgroundColor3 = COLORS.Plate

	local ring = Instance.new("UIStroke")
	ring.Thickness = MARKER.RingThickness
	ring.Color = COLORS.Ring
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = face

	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.Size = UDim2.fromScale(1, 1)
	headshot.BackgroundTransparency = 1
	headshot.ScaleType = Enum.ScaleType.Fit
	headshot.Image = `rbxthumb://type=AvatarHeadShot&id={player.UserId}&w=150&h=150`
	headshot.Parent = face

	local headshotCorner = Instance.new("UICorner")
	headshotCorner.CornerRadius = UDim.new(0.5, 0)
	headshotCorner.Parent = headshot

	local button = Instance.new("ImageButton")
	button.Name = "Tap"
	button.Active = true
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromOffset(MARKER.BubbleSize, MARKER.BubbleSize)
	button.BackgroundTransparency = 1
	button.ImageTransparency = 1
	button.AutoButtonColor = false
	button.Interactable = false
	button.Parent = bubble

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.new(0.5, 0, 0, MARKER.NameIdleY)
	plate.AutomaticSize = Enum.AutomaticSize.XY
	plate.Size = UDim2.fromOffset(0, 0)
	plate.BackgroundColor3 = COLORS.Plate
	plate.BackgroundTransparency = 1
	plate.BorderSizePixel = 0
	plate.Parent = root

	local plateCorner = Instance.new("UICorner")
	plateCorner.CornerRadius = UDim.new(0, 10)
	plateCorner.Parent = plate

	local plateStroke = Instance.new("UIStroke")
	plateStroke.Color = COLORS.PlateStroke
	plateStroke.Thickness = 1
	plateStroke.Transparency = 1
	plateStroke.Parent = plate

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = plate

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 7)
	layout.Parent = plate

	local name = Instance.new("TextLabel")
	name.Name = "DisplayName"
	name.LayoutOrder = 1
	name.AutomaticSize = Enum.AutomaticSize.XY
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBold
	name.TextSize = MARKER.IdleNameSize
	name.TextColor3 = COLORS.Name
	name.TextStrokeTransparency = 0.35
	name.Text = player.DisplayName
	name.Parent = plate

	local distance = Instance.new("TextLabel")
	distance.Name = "Distance"
	distance.LayoutOrder = 2
	distance.AutomaticSize = Enum.AutomaticSize.XY
	distance.BackgroundTransparency = 1
	distance.Font = Enum.Font.GothamMedium
	distance.TextSize = MARKER.DistanceSize
	distance.TextColor3 = COLORS.Distance
	distance.TextTransparency = 1
	distance.Visible = false
	distance.Text = ""
	distance.Parent = plate

	return {
		Billboard = billboard,
		RootScale = rootScale,
		Bubble = bubble,
		BubbleScale = bubbleScale,
		HaloScale = haloScale,
		Ring = ring,
		Headshot = headshot,
		Button = button,
		Plate = plate,
		PlateStroke = plateStroke,
		Name = name,
		Distance = distance,
	}
end

function LocatorMarker.new(player: Player, parent: Instance, onActivated: (Player) -> ())
	local self = setmetatable({}, LocatorMarker)

	self.Player = player
	self.Connections = {}
	self.Focused = false
	self.Available = true
	self.Shown = false

	local parts = build(player, parent)
	for key, value in parts do
		self[key] = value
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = `{player.Name}Outline`
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = HIGHLIGHT.FillColor
	highlight.FillTransparency = HIGHLIGHT.FillTransparency
	highlight.OutlineColor = HIGHLIGHT.OutlineColor
	highlight.OutlineTransparency = HIGHLIGHT.OutlineTransparency
	highlight.Enabled = false
	highlight.Parent = parent
	self.Highlight = highlight

	task.spawn(function()
		local ok, content = pcall(
			Players.GetUserThumbnailAsync,
			Players,
			player.UserId,
			Enum.ThumbnailType.HeadShot,
			Enum.ThumbnailSize.Size150x150
		)
		if ok and content and self.Headshot.Parent then
			self.Headshot.Image = content
		end
	end)

	table.insert(self.Connections, self.Button.Activated:Connect(function()
		onActivated(player)
	end))

	table.insert(self.Connections, player.CharacterAdded:Connect(function(character)
		self:_Bind(character)
	end))
	table.insert(self.Connections, player.CharacterRemoving:Connect(function()
		self:_Bind(nil)
	end))

	self:_Bind(player.Character)

	return self
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any }): Tween
	local motion = TweenService:Create(instance, info, goal)
	motion:Play()
	return motion
end

function LocatorMarker:SetFocused(focused: boolean)
	if self.Focused == focused then return end
	self.Focused = focused

	if focused then
		self.Bubble.Visible = true
		self.Button.Interactable = true
		tween(self.Bubble, IN_INFO, { GroupTransparency = 0 })
		tween(self.BubbleScale, IN_INFO, { Scale = 1 })
		tween(self.Plate, IN_INFO, {
			Position = UDim2.new(0.5, 0, 0, MARKER.NameFocusY),
			BackgroundTransparency = 0.15,
		})
		tween(self.PlateStroke, IN_INFO, { Transparency = 0.55 })
		tween(self.Name, IN_INFO, { TextSize = MARKER.NameSize, TextStrokeTransparency = 1 })
		if MARKER.ShowDistance then
			self.Distance.Visible = true
			tween(self.Distance, IN_INFO, { TextTransparency = 0.1 })
		end
		return
	end

	self.Button.Interactable = false
	tween(self.BubbleScale, OUT_INFO, { Scale = FOCUS.RestScale })
	tween(self.Plate, OUT_INFO, {
		Position = UDim2.new(0.5, 0, 0, MARKER.NameIdleY),
		BackgroundTransparency = 1,
	})
	tween(self.PlateStroke, OUT_INFO, { Transparency = 1 })
	tween(self.Name, OUT_INFO, { TextSize = MARKER.IdleNameSize, TextStrokeTransparency = 0.35 })
	tween(self.Distance, OUT_INFO, { TextTransparency = 1 })

	local bubble = self.Bubble
	local fade = tween(bubble, OUT_INFO, { GroupTransparency = 1 })
	fade.Completed:Once(function()
		if not self.Focused then
			bubble.Visible = false
			self.Distance.Visible = false
		end
	end)
end

function LocatorMarker:Pulse(phase: number)
	if not self.Focused then
		self.HaloScale.Scale = 1
		return
	end
	self.HaloScale.Scale = 1 + math.sin(phase) * FOCUS.PulseAmount
end

function LocatorMarker:SetAvailable(available: boolean)
	if self.Available == available then return end
	self.Available = available

	tween(self.Ring, TINT_INFO, { Color = if available then COLORS.Ring else COLORS.RingCooldown })
	tween(self.Headshot, TINT_INFO, { ImageTransparency = if available then 0 else 0.45 })
	tween(self.Distance, TINT_INFO, {
		TextColor3 = if available then COLORS.Distance else COLORS.DistanceCooldown,
	})
end

function LocatorMarker:SetUiScale(scale: number)
	if self.RootScale.Scale ~= scale then
		self.RootScale.Scale = scale
	end
end

function LocatorMarker:SetDistanceText(text: string)
	if self.Distance.Text ~= text then
		self.Distance.Text = text
	end
end

function LocatorMarker:Press()
	local down = tween(self.BubbleScale, PRESS_INFO, { Scale = PRESS.Scale })
	down.Completed:Once(function()
		if self.Focused then
			tween(self.BubbleScale, IN_INFO, { Scale = 1 })
		end
	end)
end

function LocatorMarker:Confirm()
	self.Bubble.Visible = true
	tween(self.BubbleScale, CONFIRM_INFO, { Scale = PRESS.ConfirmScale })
	local fade = tween(self.Bubble, CONFIRM_INFO, { GroupTransparency = 1 })
	fade.Completed:Once(function()
		if self.Focused then return end
		self.Bubble.Visible = false
		self.BubbleScale.Scale = FOCUS.RestScale
	end)
end

function LocatorMarker:GetAnchor(): BasePart?
	return if self.Shown then self.Billboard.Adornee :: BasePart? else nil
end

function LocatorMarker:_Bind(character: Model?)
	if self.Died then
		self.Died:Disconnect()
		self.Died = nil
	end

	self.BindId = (self.BindId or 0) + 1
	local bindId = self.BindId

	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if character and (not root or not humanoid) then
		self:_SetShown(false)
		task.spawn(function()
			local part = character:WaitForChild("HumanoidRootPart", 10)
			local living = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
			if self.BindId ~= bindId or not part or not living or not character.Parent then return end
			self:_Bind(character)
		end)
		return
	end

	if not character or not root or not humanoid or humanoid.Health <= 0 then
		self:_SetShown(false)
		return
	end

	self.Highlight.Adornee = character
	self.Billboard.Adornee = root
	self:_SetShown(true)

	self.Died = humanoid.Died:Connect(function()
		self:_SetShown(false)
	end)
end

function LocatorMarker:_SetShown(shown: boolean)
	self.Shown = shown
	self.Highlight.Enabled = shown
	self.Billboard.Enabled = shown
	if not shown then
		self:SetFocused(false)
	end
end

function LocatorMarker:Destroy()
	self.BindId = (self.BindId or 0) + 1
	if self.Died then
		self.Died:Disconnect()
		self.Died = nil
	end
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	self.Highlight:Destroy()
	self.Billboard:Destroy()
end

return LocatorMarker
