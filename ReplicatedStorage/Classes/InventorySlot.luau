local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)
local ItemPreviewService = require(ReplicatedStorage.Services.ItemPreviewService)

local COLORS = InventoryConfig.Colors
local TRANSPARENCY = InventoryConfig.Transparency

local InventorySlot = {}
InventorySlot.__index = InventorySlot

export type InventorySlot = typeof(setmetatable({} :: {
	Index: number,
	Frame: ImageButton,
	Icon: ViewportFrame,
	Label: TextLabel,
	Quantity: TextLabel,
	Number: TextLabel?,
	ToolName: string?,
	Connections: { [string]: RBXScriptConnection },
}, InventorySlot))

local function corner(parent: Instance, radius: number?)
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, radius or InventoryConfig.CornerRadius)
	uiCorner.Parent = parent
end

local function stroke(parent: Instance)
	local uiStroke = Instance.new("UIStroke")
	uiStroke.Color = COLORS.Stroke
	uiStroke.Thickness = 1
	uiStroke.Parent = parent
end

function InventorySlot.new(index: number, showNumber: boolean): InventorySlot
	local self = setmetatable({}, InventorySlot)

	self.Index = index
	self.ToolName = nil
	self.Connections = {}

	local frame = Instance.new("ImageButton")
	frame.Name = `Slot{index}`
	frame.Size = UDim2.fromOffset(InventoryConfig.SlotSize, InventoryConfig.SlotSize)
	frame.BackgroundColor3 = COLORS.Slot
	frame.BackgroundTransparency = TRANSPARENCY.Slot
	frame.BorderSizePixel = 0
	frame.AutoButtonColor = false
	frame.Image = ""
	frame.LayoutOrder = index
	corner(frame)
	stroke(frame)
	self.Frame = frame

	local icon = Instance.new("ViewportFrame")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(0.7, 0.7)
	icon.Position = UDim2.fromScale(0.5, 0.45)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Ambient = Color3.fromRGB(190, 190, 190)
	icon.LightColor = Color3.fromRGB(255, 248, 232)
	icon.LightDirection = Vector3.new(-1, -1, -1)
	icon.Parent = frame
	self.Icon = icon

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.9, 0.34)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = Enum.Font.GothamMedium
	label.TextColor3 = COLORS.Text
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = ""
	label.Parent = frame
	self.Label = label

	local quantity = Instance.new("TextLabel")
	quantity.Name = "Quantity"
	quantity.BackgroundTransparency = 1
	quantity.Size = UDim2.fromScale(0.5, 0.26)
	quantity.Position = UDim2.fromScale(0.96, 0.94)
	quantity.AnchorPoint = Vector2.new(1, 1)
	quantity.Font = Enum.Font.GothamBold
	quantity.TextColor3 = COLORS.Text
	quantity.TextScaled = true
	quantity.TextXAlignment = Enum.TextXAlignment.Right
	quantity.Text = ""
	quantity.Parent = frame
	self.Quantity = quantity

	if showNumber then
		local number = Instance.new("TextLabel")
		number.Name = "Number"
		number.BackgroundTransparency = 1
		number.Size = UDim2.fromScale(0.4, 0.22)
		number.Position = UDim2.fromScale(0.06, 0.05)
		number.Font = Enum.Font.GothamMedium
		number.TextColor3 = COLORS.TextDim
		number.TextScaled = true
		number.TextXAlignment = Enum.TextXAlignment.Left
		number.Text = tostring(index)
		number.Parent = frame
		self.Number = number
	end

	return self
end

function InventorySlot:SetTool(toolName: string, quantity: number, icon: string?)
	local changed = self.ToolName ~= toolName
	self.ToolName = toolName
	self.Frame.BackgroundTransparency = TRANSPARENCY.Slot

	if changed then
		ItemPreviewService:Render(self.Icon, toolName)
	end
	self.Label.Text = ""
	self.Quantity.Text = quantity > 1 and `x{quantity}` or ""
end

function InventorySlot:SetEmpty()
	self.ToolName = nil
	self.Frame.BackgroundTransparency = TRANSPARENCY.SlotEmpty

	ItemPreviewService:Clear(self.Icon)
	self.Label.Text = ""
	self.Quantity.Text = ""
	self:SetEquipped(false)
end

function InventorySlot:IsEmpty(): boolean
	return self.ToolName == nil
end

local function idleColor(slot): Color3
	return if slot.ToolName then COLORS.Slot else COLORS.SlotEmpty
end

function InventorySlot:SetEquipped(equipped: boolean)
	self.Frame.BackgroundColor3 = equipped and COLORS.SlotEquipped or idleColor(self)
end

function InventorySlot:SetDropTarget(active: boolean)
	self.Frame.BackgroundColor3 = active and COLORS.SlotDropTarget or idleColor(self)
end

function InventorySlot:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Frame:Destroy()
end

return InventorySlot
