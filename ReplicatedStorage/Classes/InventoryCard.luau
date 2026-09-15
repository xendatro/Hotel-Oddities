local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local ItemPreviewService = require(ReplicatedStorage.Services.ItemPreviewService)

local CARD = ItemShopConfig.Animation.Card
local PAGE = InventoryConfig.Page
local BADGE_FONT = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

local InventoryCard = {}
InventoryCard.__index = InventoryCard

export type Entry = {
	Slot: number,
	Name: string,
	Quantity: number,
	Icon: string?,
}

export type InventoryCard = typeof(setmetatable({} :: {
	Index: number,
	ToolName: string,
	Quantity: number,
	Holder: Frame,
	Button: ImageButton,
	Hovered: boolean,
	Pressed: boolean,
	Selected: boolean,
	Tween: Tween?,
	Connections: { [string]: RBXScriptConnection },
}, InventoryCard))

local function setUpConnections(
	self: InventoryCard,
	onSelect: (InventoryCard) -> (),
	onPress: (InventoryCard, InputObject) -> ()
)
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
			onSelect(self)
		end),
		InputBegan = button.InputBegan:Connect(function(input: InputObject)
			onPress(self, input)
		end),
	}
end

local function ensureBadge(button: ImageButton): TextLabel
	local existing = button:FindFirstChild("Quantity")
	if existing and existing:IsA("TextLabel") then return existing end

	local badge = Instance.new("TextLabel")
	badge.Name = "Quantity"
	badge.BackgroundTransparency = 1
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.fromScale(0.92, 0.92)
	badge.Size = UDim2.fromScale(0.5, 0.24)
	badge.FontFace = BADGE_FONT
	badge.TextColor3 = PAGE.Ink
	badge.TextScaled = true
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.ZIndex = button.ZIndex + 2
	badge.Parent = button
	return badge
end

function InventoryCard.new(
	template: ImageButton,
	parent: Instance,
	entry: Entry,
	order: number,
	onSelect: (InventoryCard) -> (),
	onPress: (InventoryCard, InputObject) -> (),
	size: UDim2?
): InventoryCard
	local holder = Instance.new("Frame")
	holder.Name = `Slot{entry.Slot}`
	holder.BackgroundTransparency = 1
	holder.Size = size or template.Size
	holder.LayoutOrder = order
	holder.Parent = parent

	local button = template:Clone()
	button.Name = "Card"
	button.Visible = true
	button.AutoButtonColor = false
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.5)
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = holder

	local viewport = button:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		ItemPreviewService:Render(viewport, entry.Name)
	end

	local badge = ensureBadge(button)
	badge.Text = if entry.Quantity > 1 then `x{entry.Quantity}` else ""

	local self = setmetatable({
		Index = entry.Slot,
		ToolName = entry.Name,
		Quantity = entry.Quantity,
		Holder = holder,
		Button = button,
		Hovered = false,
		Pressed = false,
		Selected = false,
		Tween = nil,
		Connections = {},
	}, InventoryCard) :: InventoryCard

	self.Connections = setUpConnections(self, onSelect, onPress)
	return self
end

function InventoryCard:Pose(override: TweenInfo?)
	local scale, lift, tilt = 1, 0, 0
	local duration = CARD.SettleTime
	local style = Enum.EasingStyle.Back

	if self.Pressed then
		scale, duration, style = CARD.PressScale, CARD.PressTime, Enum.EasingStyle.Quad
	elseif self.Hovered then
		scale, lift, tilt, duration = CARD.HoverScale, CARD.HoverLift, CARD.HoverTilt, CARD.HoverTime
	elseif self.Selected then
		scale, lift, tilt = CARD.SelectedScale, CARD.SelectedLift, CARD.SelectedTilt
	end

	if self.Tween then self.Tween:Cancel() end
	self.Tween = TweenService:Create(
		self.Button,
		override or TweenInfo.new(duration, style, Enum.EasingDirection.Out),
		{
			Size = UDim2.fromScale(scale, scale),
			Position = UDim2.fromScale(0.5, 0.5 - lift),
			Rotation = tilt,
		}
	)
	self.Tween:Play()
end

function InventoryCard:SetSelected(selected: boolean)
	if self.Selected == selected then return end
	self.Selected = selected
	self:Pose()
end

function InventoryCard:SetDragging(dragging: boolean)
	local transparency = if dragging then InventoryConfig.Transparency.Dragging else 0
	self.Button.ImageTransparency = transparency

	local viewport = self.Button:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		viewport.ImageTransparency = transparency
	end

	local badge = self.Button:FindFirstChild("Quantity")
	if badge and badge:IsA("TextLabel") then
		badge.TextTransparency = transparency
	end
end

function InventoryCard:Deal(delay: number)
	if self.Tween then self.Tween:Cancel() end

	self.Button.Size = UDim2.fromScale(CARD.EnterScale, CARD.EnterScale)
	self.Button.Position = UDim2.fromScale(0.5, 0.5 + CARD.EnterDrop)
	self.Button.Rotation = 0

	task.delay(delay, function()
		if self.Button.Parent ~= self.Holder then return end
		self:Pose(TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
	end)
end

function InventoryCard:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	if self.Tween then self.Tween:Cancel() end

	local viewport = self.Button:FindFirstChild("ViewportFrame")
	if viewport and viewport:IsA("ViewportFrame") then
		ItemPreviewService:Clear(viewport)
	end
	self.Holder:Destroy()
end

return InventoryCard
