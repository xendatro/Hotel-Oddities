local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local InterfaceService = require(game:GetService("ReplicatedStorage").Services.InterfaceService)

local PANEL_WIDTH = 300
local ROW_HEIGHT = 34
local TRACK_HEIGHT = 10
local TRACK_OFFSET = 18
local VALUE_WIDTH = 64
local GRAPH_HEADER_HEIGHT = 14
local GRAPH_GAP = 2
local GRAPH_AXIS_WIDTH = 36

local DebugPanel = {}
DebugPanel.__index = DebugPanel

local openPanelCount = 0
local sideGuiWasEnabled: boolean? = nil

export type DebugPanel = typeof(setmetatable({} :: {
	Gui: ScreenGui,
	Panel: Frame,
	Heading: TextLabel,
	Width: number,
	_toggleKey: Enum.KeyCode,
	_order: number,
	_isOpen: boolean,
	_dragging: ((number) -> ())?,
	_connections: { RBXScriptConnection },
}, DebugPanel))

export type Graph = {
	Push: (self: Graph, value: number) -> (),
	Clear: (self: Graph) -> (),
	Frame: Frame,
	Header: TextLabel,
}

export type GraphOptions = {
	Height: number?,
	Minimum: number?,
	Maximum: number?,
	References: { number }?,
	Format: string?,
	Color: Color3?,
	ClipColor: Color3?,
	ColorFor: ((number) -> Color3)?,
}

local function getSideGui(): ScreenGui?
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local sideGui = playerGui and playerGui:FindFirstChild("SideGui")
	return if sideGui and sideGui:IsA("ScreenGui") then sideGui else nil
end

local function setOpen(self: DebugPanel, open: boolean)
	if self._isOpen == open then return end
	self._isOpen = open

	if open then
		if openPanelCount == 0 then
			local sideGui = getSideGui()
			if sideGui then
				sideGuiWasEnabled = sideGui.Enabled
				sideGui.Enabled = false
			end
		end
		openPanelCount += 1
	else
		openPanelCount = math.max(0, openPanelCount - 1)
		if openPanelCount == 0 then
			local sideGui = getSideGui()
			if sideGui and sideGuiWasEnabled ~= nil then
				sideGui.Enabled = sideGuiWasEnabled
			end
			sideGuiWasEnabled = nil
		end
	end

	self.Gui.Enabled = open
	InterfaceService:SetMouseUnlocked(openPanelCount > 0)
end

function DebugPanel.new(title: string, toggleKey: Enum.KeyCode, width: number?): DebugPanel
	local self = setmetatable({}, DebugPanel)
	local panelWidth = width or PANEL_WIDTH

	local gui = Instance.new("ScreenGui")
	gui.Name = `DebugPanel_{title}`
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0, 12, 0, 12)
	panel.Size = UDim2.new(0, panelWidth, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local heading = Instance.new("TextLabel")
	heading.Size = UDim2.new(1, 0, 0, 18)
	heading.LayoutOrder = 0
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.Code
	heading.TextSize = 14
	heading.TextColor3 = Color3.fromRGB(255, 170, 170)
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.Text = title
	heading.Parent = panel

	self.Gui = gui
	self.Panel = panel
	self.Heading = heading
	self.Width = panelWidth
	self._toggleKey = toggleKey
	self._order = 0
	self._isOpen = false
	self._dragging = nil
	self._connections = {}

	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == toggleKey then
			setOpen(self, not self._isOpen)
		end
	end))

	table.insert(self._connections, UserInputService.InputChanged:Connect(function(input)
		local dragging = self._dragging
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging(input.Position.X)
		end
	end))

	table.insert(self._connections, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = nil
		end
	end))

	return self
end

function DebugPanel:SetTitle(title: string)
	self.Heading.Text = title
end

function DebugPanel:IsOpen(): boolean
	return self._isOpen
end

function DebugPanel:_nextOrder(): number
	self._order += 1
	return self._order
end

function DebugPanel:AddLabel(text: string): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.LayoutOrder = self:_nextOrder()
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(150, 150, 160)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.Parent = self.Panel
	return label
end

function DebugPanel:AddTextBox(text: string): TextBox
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, 0)
	box.AutomaticSize = Enum.AutomaticSize.Y
	box.LayoutOrder = self:_nextOrder()
	box.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	box.BackgroundTransparency = 0.1
	box.BorderSizePixel = 0
	box.ClearTextOnFocus = false
	box.Font = Enum.Font.Code
	box.MultiLine = true
	box.Selectable = true
	box.Text = text
	box.TextColor3 = Color3.fromRGB(220, 220, 230)
	box.TextSize = 10
	box.TextWrapped = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextYAlignment = Enum.TextYAlignment.Top
	box.Parent = self.Panel
	return box
end

function DebugPanel:AddButton(text: string, activated: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Modal = false
	button.Size = UDim2.new(1, 0, 0, 26)
	button.LayoutOrder = self:_nextOrder()
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 13
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = self.Panel
	table.insert(self._connections, button.Activated:Connect(activated))
	return button
end

function DebugPanel:AddSlider(
	label: string,
	minimum: number,
	maximum: number,
	initial: number,
	step: number,
	apply: (number) -> ()
): (number) -> ()
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = self:_nextOrder()
	row.BackgroundTransparency = 1
	row.Parent = self.Panel

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, -(VALUE_WIDTH + 6), 0, 14)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Code
	caption.TextSize = 12
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = label
	caption.Parent = row

	local valueBox = Instance.new("TextBox")
	valueBox.Name = "Value"
	valueBox.Position = UDim2.new(1, -VALUE_WIDTH, 0, 0)
	valueBox.Size = UDim2.fromOffset(VALUE_WIDTH, 14)
	valueBox.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	valueBox.BackgroundTransparency = 0.1
	valueBox.BorderSizePixel = 0
	valueBox.ClearTextOnFocus = true
	valueBox.Font = Enum.Font.Code
	valueBox.TextSize = 11
	valueBox.TextColor3 = Color3.new(1, 1, 1)
	valueBox.TextXAlignment = Enum.TextXAlignment.Right
	valueBox.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 0, 0, TRACK_OFFSET)
	track.Size = UDim2.new(1, 0, 0, TRACK_HEIGHT)
	track.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(190, 90, 90)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local format = if step >= 1 then "%d" else "%.2f"
	local currentValue = initial

	local function normalize(value: number): number
		value = math.clamp(value, minimum, maximum)
		if step > 0 then
			value = math.round(value / step) * step
			value = math.clamp(value, minimum, maximum)
		end
		return value
	end

	local function display(value: number)
		currentValue = value
		fill.Size = UDim2.fromScale(math.clamp((value - minimum) / (maximum - minimum), 0, 1), 1)
		valueBox.Text = string.format(format, value)
	end

	local function setValue(value: number)
		value = normalize(value)
		display(value)
		apply(value)
	end

	local function setFromX(x: number)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		setValue(minimum + (maximum - minimum) * alpha)
	end

	table.insert(self._connections, valueBox.FocusLost:Connect(function()
		local value = tonumber(valueBox.Text)
		if not value or value ~= value or value == math.huge or value == -math.huge then
			display(currentValue)
			return
		end
		setValue(value)
	end))

	table.insert(self._connections, track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			self._dragging = setFromX
			setFromX(input.Position.X)
		end
	end))

	display(initial)
	return display
end

function DebugPanel:AddGraph(label: string, options: GraphOptions?): Graph
	local opts: GraphOptions = options or {}
	local height = opts.Height or 80
	local minimum = opts.Minimum or 0
	local maximum = opts.Maximum or 100
	local references = opts.References or {}
	local format = opts.Format or "%.0f"
	local baseColor = opts.Color or Color3.fromRGB(120, 200, 120)
	local clipColor = opts.ClipColor or Color3.fromRGB(255, 255, 255)
	local colorFor = opts.ColorFor
	local columnCount = math.max(self.Width - 20 - GRAPH_AXIS_WIDTH, 1)
	local span = math.max(maximum - minimum, 1e-6)
	local minimumAlpha = 1 / height

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, GRAPH_HEADER_HEIGHT + GRAPH_GAP + height)
	row.LayoutOrder = self:_nextOrder()
	row.BackgroundTransparency = 1
	row.Parent = self.Panel

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, GRAPH_HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.Code
	header.TextSize = 12
	header.TextColor3 = Color3.new(1, 1, 1)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = label
	header.Parent = row

	local plot = Instance.new("Frame")
	plot.Position = UDim2.new(0, 0, 0, GRAPH_HEADER_HEIGHT + GRAPH_GAP)
	plot.Size = UDim2.new(1, -GRAPH_AXIS_WIDTH, 0, height)
	plot.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	plot.BackgroundTransparency = 0.1
	plot.BorderSizePixel = 0
	plot.ClipsDescendants = true
	plot.Parent = row

	local axis = Instance.new("Frame")
	axis.Position = UDim2.new(1, -GRAPH_AXIS_WIDTH, 0, GRAPH_HEADER_HEIGHT + GRAPH_GAP)
	axis.Size = UDim2.new(0, GRAPH_AXIS_WIDTH, 0, height)
	axis.BackgroundTransparency = 1
	axis.Parent = row

	local function addAxisLabel(value: number, alpha: number)
		local tick = Instance.new("TextLabel")
		tick.AnchorPoint = Vector2.new(0, 0.5)
		tick.Position = UDim2.new(0, 4, 1 - alpha, 0)
		tick.Size = UDim2.new(1, -4, 0, 12)
		tick.BackgroundTransparency = 1
		tick.Font = Enum.Font.Code
		tick.TextSize = 10
		tick.TextColor3 = Color3.fromRGB(170, 170, 180)
		tick.TextXAlignment = Enum.TextXAlignment.Left
		tick.Text = string.format(format, value)
		tick.Parent = axis
	end

	for _, reference in references do
		local alpha = math.clamp((reference - minimum) / span, 0, 1)
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.new(0, 0, 1 - alpha, 0)
		line.Size = UDim2.new(1, 0, 0, 1)
		line.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		line.BackgroundTransparency = 0.25
		line.BorderSizePixel = 0
		line.ZIndex = 3
		line.Parent = plot
		addAxisLabel(reference, alpha)
	end
	addAxisLabel(maximum, 1)
	addAxisLabel(minimum, 0)

	local strip = Instance.new("Frame")
	strip.Size = UDim2.fromScale(2, 1)
	strip.BackgroundTransparency = 1
	strip.Parent = plot

	local doubled = columnCount * 2
	local columnsA: { Frame } = table.create(columnCount)
	local columnsB: { Frame } = table.create(columnCount)
	local values: { number } = table.create(columnCount, minimum)
	for copy = 0, 1 do
		local target = if copy == 0 then columnsA else columnsB
		for index = 1, columnCount do
			local column = Instance.new("Frame")
			column.AnchorPoint = Vector2.new(0, 1)
			column.Position = UDim2.fromScale((copy * columnCount + index - 1) / doubled, 1)
			column.Size = UDim2.fromScale(1 / doubled, 0)
			column.BackgroundColor3 = baseColor
			column.BorderSizePixel = 0
			column.Parent = strip
			target[index] = column
		end
	end

	local head = 0
	local seenMin = math.huge
	local seenMax = -math.huge

	local function paint(index: number)
		local value = values[index]
		local alpha = (value - minimum) / span
		local color = baseColor
		if alpha > 1 then
			alpha = 1
			color = clipColor
		elseif colorFor then
			color = colorFor(value)
		end
		if alpha > 0 and alpha < minimumAlpha then
			alpha = minimumAlpha
		end
		local size = UDim2.fromScale(1 / doubled, math.clamp(alpha, 0, 1))
		local a, b = columnsA[index], columnsB[index]
		a.Size = size
		b.Size = size
		a.BackgroundColor3 = color
		b.BackgroundColor3 = color
	end

	local function repaintAll()
		for index = 1, columnCount do
			paint(index)
		end
	end

	local graph = {} :: any
	graph.Frame = row
	graph.Header = header

	function graph.Push(_, value: number)
		head = head % columnCount + 1
		values[head] = value
		seenMin = math.min(seenMin, value)
		seenMax = math.max(seenMax, value)
		paint(head)
		strip.Position = UDim2.fromScale(-head / columnCount, 0)
		header.Text = string.format("%s  now " .. format .. "  min " .. format .. "  max " .. format,
			label, value, seenMin, seenMax)
	end

	function graph.Clear(_)
		head = 0
		seenMin = math.huge
		seenMax = -math.huge
		for index = 1, columnCount do
			values[index] = minimum
		end
		repaintAll()
		strip.Position = UDim2.fromScale(0, 0)
		header.Text = label
	end

	return graph :: Graph
end

function DebugPanel:Destroy()
	setOpen(self, false)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.Gui:Destroy()
end

return DebugPanel
