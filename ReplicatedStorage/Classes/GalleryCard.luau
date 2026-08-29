local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)

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

local function dress(button: ImageButton, media: any)
	local thumb = button:FindFirstChild("Thumb") :: ImageLabel

	local content = CaptureGalleryService:Content(media)
	if content then
		thumb.ImageContent = content
		thumb.ImageTransparency = 0
	else
		thumb.ImageTransparency = 1
	end

	local badge = button:FindFirstChild("Badge") :: TextLabel
	local colorAttribute = if media.Kind == "Video" then "TapeColor" else "StillColor"
	local color = badge:GetAttribute(colorAttribute)
	if typeof(color) == "Color3" then badge.TextColor3 = color end
	badge.Text = if media.Kind == "Video" then "\u{25B6} TAPE" else "\u{25A0} STILL"

	local stamp = button:FindFirstChild("Stamp") :: TextLabel

	local ok, formatted = pcall(function()
		return media.Time:FormatLocalTime(CaptureConfig.Overlay.DateFormat, "en-us")
	end)
	stamp.Text = if ok then formatted else ""

	local unsaved = button:FindFirstChild("Unsaved") :: Frame
	unsaved.Visible = not media.Saved
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
	template: Frame,
	parent: Instance,
	media: any,
	order: number,
	onSelect: (any) -> ()
): GalleryCard
	local holder = template:Clone()
	holder.Name = (media.Id :: string):gsub("[^%w]", "")
	holder.LayoutOrder = order
	holder.Visible = true
	holder.Parent = parent

	local button = holder:FindFirstChild("Card") :: ImageButton

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
