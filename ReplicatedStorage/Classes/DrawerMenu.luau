local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local MENU = DrawerConfig.TouchMenu
local COLORS = DrawerConfig.UI.Colors

export type Handlers = {
	Prompt: (drawer: Model) -> string?,
	Activate: (drawer: Model) -> (),
}

type Entry = {
	Button: TextButton,
	Action: TextLabel,
}

local DrawerMenu = {}
DrawerMenu.__index = DrawerMenu

local function anchorPart(furniture: Model): BasePart?
	local best: BasePart? = nil
	for _, child in furniture:GetChildren() do
		if child:IsA("BasePart") and (not best or child.Size.Magnitude > best.Size.Magnitude) then
			best = child
		end
	end
	return best or furniture:FindFirstChildWhichIsA("BasePart", true)
end

local function flat(vector: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	return if horizontal.Magnitude > 1e-3 then horizontal.Unit else Vector3.xAxis
end

local function lateralAxis(drawers: { Model }, boxCFrame: CFrame, right: Vector3): Vector3
	local axes = { flat(boxCFrame.RightVector), flat(boxCFrame.LookVector) }
	local best: Vector3? = nil
	local bestSpread = MENU.ColumnGap
	for _, axis in axes do
		local low, high = math.huge, -math.huge
		for _, drawer in drawers do
			local value = drawer:GetPivot().Position:Dot(axis)
			low, high = math.min(low, value), math.max(high, value)
		end
		if high - low > bestSpread then
			best, bestSpread = axis, high - low
		end
	end
	local axis = best
		or if math.abs(axes[1]:Dot(right)) >= math.abs(axes[2]:Dot(right)) then axes[1] else axes[2]
	return if axis:Dot(right) >= 0 then axis else -axis
end

local function columnsOf(drawers: { Model }, right: Vector3): { { Model } }
	local entries = {}
	for _, drawer in drawers do
		local position = drawer:GetPivot().Position
		table.insert(entries, { Drawer = drawer, X = position:Dot(right), Y = position.Y })
	end
	table.sort(entries, function(a, b)
		return a.X < b.X
	end)

	local columns = {}
	local lastX: number? = nil
	for _, entry in entries do
		if not lastX or entry.X - lastX > MENU.ColumnGap then
			table.insert(columns, {})
		end
		table.insert(columns[#columns], entry)
		lastX = entry.X
	end

	local result: { { Model } } = {}
	for _, column in columns do
		table.sort(column, function(a, b)
			return a.Y > b.Y
		end)
		local list = {}
		for _, entry in column do
			table.insert(list, entry.Drawer)
		end
		table.insert(result, list)
	end
	return result
end

local function label(parent: Instance, font: Font, textSize: number): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = textSize
	text.TextColor3 = COLORS.Text
	text.Parent = parent
	return text
end

local function buildButton(parent: Instance, number: number, order: number): Entry
	local button = Instance.new("TextButton")
	button.Name = `Drawer{number}`
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = false
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(MENU.ButtonSize.X, MENU.ButtonSize.Y)
	button.BackgroundColor3 = COLORS.Key
	button.Parent = parent
	GuiBuilderService.Corner(button, UDim.new(0, MENU.CornerRadius))
	GuiBuilderService.Stroke(button, COLORS.Stroke, 1)

	local name = label(button, MENU.NameFont, MENU.NameTextSize)
	name.Name = "Name"
	name.Position = UDim2.fromOffset(10, 0)
	name.Size = UDim2.new(1, -(MENU.ActionWidth + 20), 1, 0)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Text = string.format(MENU.NameFormat, number)

	local action = label(button, MENU.ActionFont, MENU.ActionTextSize)
	action.Name = "Action"
	action.AnchorPoint = Vector2.new(1, 0.5)
	action.Position = UDim2.new(1, -6, 0.5, 0)
	action.Size = UDim2.fromOffset(MENU.ActionWidth, MENU.ButtonSize.Y - 12)
	action.BackgroundTransparency = 0
	action.BackgroundColor3 = COLORS.Panel
	GuiBuilderService.Corner(action, UDim.new(0, MENU.CornerRadius - 2))

	return { Button = button, Action = action }
end

local function setUpConnections(self)
	self.Connections = {} :: { RBXScriptConnection }

	table.insert(self.Connections, RunService.RenderStepped:Connect(function()
		self:_place()
	end))

	for drawer, entry in self.Entries do
		table.insert(self.Connections, entry.Button.Activated:Connect(function()
			self:_press(drawer, entry)
		end))
	end
end

function DrawerMenu.new(furniture: Model, drawers: { Model }, handlers: Handlers, parent: Instance)
	local self = setmetatable({}, DrawerMenu)

	self.Furniture = furniture
	self.Handlers = handlers
	self.Drawers = table.clone(drawers)
	self.Entries = {} :: { [Model]: Entry }
	self.Order = {} :: { Model }

	local camera = workspace.CurrentCamera
	local boxCFrame, boxSize = furniture:GetBoundingBox()
	local right = lateralAxis(drawers, boxCFrame, if camera then camera.CFrame.RightVector else Vector3.xAxis)
	local columns = columnsOf(drawers, right)

	local rows = 0
	for _, column in columns do
		rows = math.max(rows, #column)
	end
	local width = #columns * MENU.ButtonSize.X + (#columns - 1) * MENU.Gap + MENU.Padding * 2
	local height = rows * MENU.ButtonSize.Y + (rows - 1) * MENU.Gap + MENU.Padding * 2

	local gui = Instance.new("BillboardGui")
	gui.Name = MENU.GuiName
	gui.Active = true
	gui.AlwaysOnTop = true
	gui.ClipsDescendants = false
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Size = UDim2.fromOffset(width, height)

	self.Anchor = anchorPart(furniture)
	self.Centre = boxCFrame.Position
	self.Right = right
	self.HalfWidth = (math.abs(right:Dot(boxCFrame.RightVector)) * boxSize.X
		+ math.abs(right:Dot(boxCFrame.UpVector)) * boxSize.Y
		+ math.abs(right:Dot(boxCFrame.LookVector)) * boxSize.Z) / 2
	self.Side = 1
	self.DesignWidth = width
	self.DesignHeight = height
	gui.Adornee = self.Anchor

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Size = UDim2.fromOffset(width, height)
	panel.BackgroundColor3 = COLORS.Panel
	panel.BackgroundTransparency = MENU.PanelTransparency
	panel.Parent = gui
	GuiBuilderService.Corner(panel, UDim.new(0, MENU.CornerRadius + 2))
	GuiBuilderService.Stroke(panel, COLORS.Stroke, 1)

	local scale = Instance.new("UIScale")
	scale.Parent = panel
	self.Scale = scale

	local padding = Instance.new("UIPadding")
	local inset = UDim.new(0, MENU.Padding)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight = inset, inset, inset, inset
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, MENU.Gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local number = 0
	for columnIndex, column in columns do
		local frame = Instance.new("Frame")
		frame.Name = `Column{columnIndex}`
		frame.BackgroundTransparency = 1
		frame.LayoutOrder = columnIndex
		frame.Size = UDim2.new(0, MENU.ButtonSize.X, 1, 0)
		frame.Parent = panel

		local stack = Instance.new("UIListLayout")
		stack.Padding = UDim.new(0, MENU.Gap)
		stack.SortOrder = Enum.SortOrder.LayoutOrder
		stack.Parent = frame

		for rowIndex, drawer in column do
			number += 1
			self.Entries[drawer] = buildButton(frame, number, rowIndex)
			self.Order[number] = drawer
		end
	end

	gui.Parent = parent
	self.Gui = gui
	self:_place()

	setUpConnections(self)

	return self
end

function DrawerMenu:Matches(drawers: { Model }): boolean
	if #drawers ~= #self.Drawers then return false end
	for _, drawer in drawers do
		if not self.Entries[drawer] then return false end
	end
	return true
end

function DrawerMenu:_edge(side: number): Vector3
	return self.Centre + self.Right * (self.HalfWidth + MENU.SideGap) * side
end

function DrawerMenu:_place()
	local camera = workspace.CurrentCamera
	local anchor = self.Anchor
	if not camera or not anchor then return end

	local edge = self:_edge(self.Side)
	local distance = math.max((camera.CFrame.Position - edge).Magnitude, 0.5)
	local viewport = camera.ViewportSize
	local perStud = viewport.Y / (2 * distance * math.tan(math.rad(camera.FieldOfView) / 2))
	local limit = math.min(
		viewport.Y * MENU.MaxHeightFraction / self.DesignHeight,
		viewport.X * MENU.MaxWidthFraction / self.DesignWidth
	)
	local scale = math.clamp(perStud / MENU.PixelsPerStud, MENU.MinScale, math.max(MENU.MinScale, limit))
	local width = self.DesignWidth * scale

	local screenX = camera:WorldToViewportPoint(edge).X
	local overflow = if self.Side > 0 then screenX + width - viewport.X else width - screenX
	local shift = if overflow > 0 then overflow / perStud else 0
	local offset = edge - self.Right * self.Side * shift - anchor.Position

	if math.abs(scale - self.Scale.Scale) > 1e-3 then
		self.Scale.Scale = scale
		self.Gui.Size = UDim2.fromOffset(width, self.DesignHeight * scale)
	end
	self.Gui.SizeOffset = Vector2.new(0.5 * self.Side, 0)
	if (offset - self.Gui.StudsOffsetWorldSpace).Magnitude > 1e-3 then
		self.Gui.StudsOffsetWorldSpace = offset
	end
end

function DrawerMenu:_fits(camera: Camera, side: number): boolean
	local x = camera:WorldToViewportPoint(self:_edge(side)).X
	local width = self.DesignWidth * self.Scale.Scale
	return if side > 0 then x + width <= camera.ViewportSize.X else x - width >= 0
end

function DrawerMenu:_fitSide()
	local camera = workspace.CurrentCamera
	if not camera then return end
	if self:_fits(camera, self.Side) or not self:_fits(camera, -self.Side) then return end
	self.Side = -self.Side
end

function DrawerMenu:Refresh()
	self:_fitSide()
	for drawer, entry in self.Entries do
		local text = self.Handlers.Prompt(drawer)
		entry.Action.Text = text or ""
		entry.Button.Interactable = text ~= nil
	end
end

function DrawerMenu:Press(number: number): boolean
	local drawer = self.Order[number]
	local entry = drawer and self.Entries[drawer]
	if not entry or not entry.Button.Interactable then return false end
	self:_press(drawer, entry)
	return true
end

function DrawerMenu:_press(drawer: Model, entry: Entry)
	self.Handlers.Activate(drawer)
	entry.Button.BackgroundColor3 = COLORS.KeyPressed
	TweenService:Create(entry.Button, TweenInfo.new(MENU.PressTime), { BackgroundColor3 = COLORS.Key }):Play()
	self:Refresh()
end

function DrawerMenu:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	table.clear(self.Connections)
	table.clear(self.Entries)
	table.clear(self.Order)
	self.Gui:Destroy()
end

return DrawerMenu
