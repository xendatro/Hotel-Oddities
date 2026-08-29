local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local GalleryCard = {}
GalleryCard.__index = GalleryCard

local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.97
local SELECTED_SCALE = 1.02
local HOVER_TIME = 0.16
local SETTLE_TIME = 0.24
local ENTER_SCALE = 0.86
local ENTER_DROP = 0.06

export type GalleryCard = typeof(setmetatable({} :: {
	Media: any,
	Holder: Frame,
	Button: ImageButton,
	Hovered: boolean,
	Pressed: boolean,
	Selected: boolean,
	Tween: Tween?,
	Connections: { [string]: RBXScriptConnection },
}, GalleryCard))

local function findOrMake(parent: Instance, name: string, className: string): any
	local existing = parent:FindFirstChild(name)
	if existing then return existing end

	local made = Instance.new(className)
	made.Name = name
	made.Parent = parent
	return made
end

local function dress(button: ImageButton, media: any)
	button.Image = ""
	button.BackgroundColor3 = Color3.fromRGB(22, 17, 14)
	button.BackgroundTransparency = 0

	local thumb = findOrMake(button, "Thumb", "ImageLabel") :: ImageLabel
	thumb.Size = UDim2.fromScale(1, 1)
	thumb.BackgroundTransparency = 1
	thumb.ScaleType = Enum.ScaleType.Crop
	thumb.ImageColor3 = Color3.fromRGB(226, 214, 196)
	thumb.ZIndex = 2

	if media.Kind == "Screenshot" then
		local content = CaptureGalleryService:Content(media)
		if content then
			thumb.ImageContent = content
			thumb.ImageTransparency = 0
		end
	else
		thumb.ImageTransparency = 1
	end

	local badge = findOrMake(button, "Badge", "TextLabel") :: TextLabel
	badge.AnchorPoint = Vector2.new(0, 0)
	badge.Position = UDim2.fromScale(0.06, 0.06)
	badge.Size = UDim2.fromScale(0.5, 0.14)
	badge.BackgroundTransparency = 1
	badge.Font = CaptureConfig.Overlay.Font
	badge.TextColor3 = if media.Kind == "Video"
		then CaptureConfig.Overlay.RecordColor
		else CaptureConfig.Overlay.Color
	badge.TextScaled = true
	badge.TextXAlignment = Enum.TextXAlignment.Left
	badge.Text = if media.Kind == "Video" then "\u{25B6} TAPE" else "\u{25A0} STILL"
	badge.ZIndex = 4

	local stamp = findOrMake(button, "Stamp", "TextLabel") :: TextLabel
	stamp.AnchorPoint = Vector2.new(1, 1)
	stamp.Position = UDim2.fromScale(0.94, 0.94)
	stamp.Size = UDim2.fromScale(0.8, 0.13)
	stamp.BackgroundTransparency = 1
	stamp.Font = CaptureConfig.Overlay.Font
	stamp.TextColor3 = CaptureConfig.Overlay.Color
	stamp.TextScaled = true
	stamp.TextXAlignment = Enum.TextXAlignment.Right
	stamp.ZIndex = 4

	local ok, formatted = pcall(function()
		return media.Time:FormatLocalTime(CaptureConfig.Overlay.DateFormat, "en-us")
	end)
	stamp.Text = if ok then formatted else ""

	local unsaved = findOrMake(button, "Unsaved", "Frame") :: Frame
	unsaved.AnchorPoint = Vector2.new(0.5, 0)
	unsaved.Position = UDim2.fromScale(0.5, 0)
	unsaved.Size = UDim2.new(1, 0, 0, 3)
	unsaved.BorderSizePixel = 0
	unsaved.BackgroundColor3 = CaptureConfig.Prompt.SaveColor
	unsaved.Visible = not media.Saved
	unsaved.ZIndex = 5
end

local function setUpConnections(self: GalleryCard, onSelect: (any) -> ())
	local button = self.Button

	return {
		Enter = button.MouseEnter:Connect(function()
			self.Hovered = true
			self:Pose()
		end),
		Leave = button.MouseLeave:Connect(function()
			self.Hovered = false
			self.Pressed = false
			self:Pose()
		end),
		Down = button.MouseButton1Down:Connect(function()
			self.Pressed = true
			self:Pose()
		end),
		Up = button.MouseButton1Up:Connect(function()
			self.Pressed = false
			self:Pose()
		end),
		Activated = button.Activated:Connect(function()
			onSelect(self.Media)
		end),
	}
end

function GalleryCard.new(
	template: ImageButton,
	parent: Instance,
	media: any,
	order: number,
	onSelect: (any) -> ()
): GalleryCard
	local holder = Instance.new("Frame")
	holder.Name = media.Id
	holder.BackgroundTransparency = 1
	holder.Size = template.Size
	holder.LayoutOrder = order
	holder.Parent = parent

	local button = template:Clone()
	button.Name = "Card"
	button.Visible = true
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.ClipsDescendants = true
	button.Parent = holder

	GuiBuilderService.Corner(button, UDim.new(0, 4))

	local self = setmetatable({
		Media = media,
		Holder = holder,
		Button = button,
		Hovered = false,
		Pressed = false,
		Selected = false,
		Tween = nil,
		Connections = {},
	}, GalleryCard) :: GalleryCard

	dress(button, media)

	self.Connections = setUpConnections(self, onSelect)
	return self
end

function GalleryCard:Pose(override: TweenInfo?)
	local scale = 1
	local duration = SETTLE_TIME
	local style = Enum.EasingStyle.Back

	if self.Pressed then
		scale, duration, style = PRESS_SCALE, HOVER_TIME, Enum.EasingStyle.Quad
	elseif self.Hovered then
		scale, duration = HOVER_SCALE, HOVER_TIME
	elseif self.Selected then
		scale = SELECTED_SCALE
	end

	if self.Tween then self.Tween:Cancel() end
	self.Tween = TweenService:Create(
		self.Button,
		override or TweenInfo.new(duration, style, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(scale, scale), Position = UDim2.fromScale(0.5, 0.5) }
	)
	self.Tween:Play()
end

function GalleryCard:SetSelected(selected: boolean)
	if self.Selected == selected then return end
	self.Selected = selected
	self:Pose()
end

function GalleryCard:Deal(delay: number)
	if self.Tween then self.Tween:Cancel() end

	self.Button.Size = UDim2.fromScale(ENTER_SCALE, ENTER_SCALE)
	self.Button.Position = UDim2.fromScale(0.5, 0.5 + ENTER_DROP)

	task.delay(delay, function()
		if self.Button.Parent ~= self.Holder then return end
		self:Pose(TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end)
end

function GalleryCard:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	if self.Tween then self.Tween:Cancel() end
	self.Holder:Destroy()
end

return GalleryCard
