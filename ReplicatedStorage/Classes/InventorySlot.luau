local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryConfig = require(ReplicatedStorage.Configs.InventoryConfig)

local COLORS = InventoryConfig.Colors
local TRANSPARENCY = InventoryConfig.Transparency

--- @class InventorySlot
--- One square of the inventory. Owns its frame and nothing else: it does not know what a tool is,
--- how equipping works, or where it sits in the layout. `InventoryUIService` drives it by calling
--- `SetTool`/`SetEmpty`/`SetEquipped`, which keeps every piece of input handling in one place
--- rather than scattered across dozens of per-slot connections.
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

local function clearViewport(viewport: ViewportFrame)
	viewport:ClearAllChildren()
	viewport.CurrentCamera = nil
end

-- Draws the real tool model instead of relying on a separate icon asset. The copy lives only in a
-- WorldModel, with scripts, sounds and live effects stripped so an inventory preview stays inert.
local function renderTool(viewport: ViewportFrame, toolName: string)
	clearViewport(viewport)

	local template = ReplicatedStorage.Tools:FindFirstChild(toolName)
	if not template or not template:IsA("Tool") then return end

	local world = Instance.new("WorldModel")
	world.Name = "Preview"
	world.Parent = viewport

	local clone = template:Clone()
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("AudioEmitter") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end
	clone.Parent = world

	local boundsCFrame, boundsSize = world:GetBoundingBox()
	if boundsSize.Magnitude < 1e-3 then return end

	local camera = Instance.new("Camera")
	camera.Name = "Camera"
	camera.FieldOfView = 35
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local direction = Vector3.new(1, 0.65, 1).Unit
	local distance = math.max(boundsSize.Magnitude * 1.15, 2)
	camera.CFrame = CFrame.lookAt(boundsCFrame.Position + direction * distance, boundsCFrame.Position)
end

--- Builds an empty slot.
--- @param index number -- position in the overall layout, 1-based
--- @param showNumber boolean -- whether to draw the keyboard hint (hotbar slots only)
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

	-- Stands in for the icon until real art exists, so a slot is never blank.
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

--- Fills the slot in. Passing a quantity of 1 or less clears the count rather than leaving a stale
--- one behind -- the specific thing FFM's version never did, so a spent stack kept reading "x3".
function InventorySlot:SetTool(toolName: string, quantity: number, icon: string?)
	local changed = self.ToolName ~= toolName
	self.ToolName = toolName
	self.Frame.Visible = true

	if changed then
		renderTool(self.Icon, toolName)
	end
	self.Label.Text = ""
	self.Quantity.Text = quantity > 1 and `x{quantity}` or ""
end

--- Empties the slot, clearing every label with it.
function InventorySlot:SetEmpty()
	self.ToolName = nil
	self.Frame.Visible = false

	clearViewport(self.Icon)
	self.Label.Text = ""
	self.Quantity.Text = ""
	self:SetEquipped(false)
end

function InventorySlot:IsEmpty(): boolean
	return self.ToolName == nil
end

function InventorySlot:SetEquipped(equipped: boolean)
	self.Frame.BackgroundColor3 = equipped and COLORS.SlotEquipped or COLORS.Slot
end

--- Highlights the slot a drag is currently hovering over.
function InventorySlot:SetDropTarget(active: boolean)
	self.Frame.BackgroundColor3 = active and COLORS.SlotDropTarget or COLORS.Slot
end

function InventorySlot:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Frame:Destroy()
end

return InventorySlot
