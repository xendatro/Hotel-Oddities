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
local GRAPH_LEGEND_HEIGHT = 26

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

export type GraphSeries = {
	Name: string,
	Color: Color3,
}

export type StackedGraph = {
	Push: (self: StackedGraph, counts: { number }) -> (),
	Clear: (self: StackedGraph) -> (),
	Frame: Frame,
	Header: TextLabel,
}

export type StackedGraphOptions = {
	Height: number?,
	Maximum: number?,
	References: { number }?,
	Format: string?,
	ClipColor: Color3?,
	Series: { GraphSeries },
}

type GraphScaffold = {
	Row: Frame,
	Header: TextLabel,
	Plot: Frame,
	Strip: Frame,
	ColumnCount: number,
	Doubled: number,
}

local function buildGraphScaffold(
	self: DebugPanel,
	label: string,
	height: number,
	minimum: number,
	maximum: number,
	references: { number },
	format: string,
	legendHeight: number
): GraphScaffold
	local span = math.max(maximum - minimum, 1e-6)
	local columnCount = math.max(self.Width - 20 - GRAPH_AXIS_WIDTH, 1)
	local plotTop = GRAPH_HEADER_HEIGHT + GRAPH_GAP + legendHeight

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, plotTop + height)
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
	plot.Position = UDim2.new(0, 0, 0, plotTop)
	plot.Size = UDim2.new(1, -GRAPH_AXIS_WIDTH, 0, height)
	plot.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	plot.BackgroundTransparency = 0.1
	plot.BorderSizePixel = 0
	plot.ClipsDescendants = true
	plot.Parent = row

	local axis = Instance.new("Frame")
	axis.Position = UDim2.new(1, -GRAPH_AXIS_WIDTH, 0, plotTop)
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

	return {
		Row = row,
		Header = header,
		Plot = plot,
		Strip = strip,
		ColumnCount = columnCount,
		Doubled = columnCount * 2,
	}
end

local function colorToHex(color: Color3): string
	return string.format("#%02x%02x%02x", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

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
	local span = math.max(maximum - minimum, 1e-6)
	local minimumAlpha = 1 / height

	local scaffold = buildGraphScaffold(self, label, height, minimum, maximum, references, format, 0)
	local row, header, strip = scaffold.Row, scaffold.Header, scaffold.Strip
	local columnCount, doubled = scaffold.ColumnCount, scaffold.Doubled

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

function DebugPanel:AddStackedGraph(label: string, options: StackedGraphOptions): StackedGraph
	local height = options.Height or 80
	local maximum = options.Maximum or 100
	local references = options.References or {}
	local format = options.Format or "%d"
	local clipColor = options.ClipColor or Color3.fromRGB(255, 255, 255)
	local series = options.Series
	local seriesCount = #series
	local span = math.max(maximum, 1e-6)
	local minimumAlpha = 1 / height
	local capAlpha = 2 / height

	local scaffold = buildGraphScaffold(self, label, height, 0, maximum, references, format, GRAPH_LEGEND_HEIGHT)
	local row, header, strip = scaffold.Row, scaffold.Header, scaffold.Strip
	local columnCount, doubled = scaffold.ColumnCount, scaffold.Doubled
	local columnWidth = 1 / doubled

	local legendParts = table.create(seriesCount + 1)
	for _, entry in series do
		table.insert(legendParts, string.format('<font color="%s">■</font> %s', colorToHex(entry.Color), entry.Name))
	end
	table.insert(legendParts, string.format('<font color="%s">■</font> over %s', colorToHex(clipColor), string.format(format, maximum)))

	local legend = Instance.new("TextLabel")
	legend.Position = UDim2.new(0, 0, 0, GRAPH_HEADER_HEIGHT)
	legend.Size = UDim2.new(1, 0, 0, GRAPH_LEGEND_HEIGHT)
	legend.BackgroundTransparency = 1
	legend.Font = Enum.Font.Code
	legend.TextSize = 10
	legend.TextColor3 = Color3.fromRGB(200, 200, 210)
	legend.TextXAlignment = Enum.TextXAlignment.Left
	legend.TextYAlignment = Enum.TextYAlignment.Top
	legend.TextWrapped = true
	legend.RichText = true
	legend.Text = table.concat(legendParts, "   ")
	legend.Parent = row

	local segmentsA: { { Frame } } = table.create(columnCount)
	local segmentsB: { { Frame } } = table.create(columnCount)
	local values: { { number }? } = table.create(columnCount)
	for index = 1, columnCount do
		segmentsA[index] = {}
		segmentsB[index] = {}
	end

	local function segmentAt(list: { Frame }, slot: number, x: number): Frame
		local segment = list[slot]
		if not segment then
			segment = Instance.new("Frame")
			segment.AnchorPoint = Vector2.new(0, 1)
			segment.BorderSizePixel = 0
			segment.Parent = strip
			list[slot] = segment
		end
		segment.Visible = true
		return segment
	end

	local function hideFrom(list: { Frame }, slot: number)
		for extra = slot, #list do
			list[extra].Visible = false
		end
	end

	local function paint(index: number)
		local counts = values[index]
		local listA, listB = segmentsA[index], segmentsB[index]
		if not counts then
			hideFrom(listA, 1)
			hideFrom(listB, 1)
			return
		end

		local xA = (index - 1) * columnWidth
		local xB = (columnCount + index - 1) * columnWidth
		local total = 0
		local dominant = 1
		for seriesIndex = 1, seriesCount do
			local count = counts[seriesIndex] or 0
			total += count
			if count > (counts[dominant] or 0) then
				dominant = seriesIndex
			end
		end

		local slot = 1
		local function place(alpha: number, bottom: number, color: Color3)
			local size = UDim2.fromScale(columnWidth, alpha)
			local a = segmentAt(listA, slot, xA)
			a.Position = UDim2.fromScale(xA, 1 - bottom)
			a.Size = size
			a.BackgroundColor3 = color
			local b = segmentAt(listB, slot, xB)
			b.Position = UDim2.fromScale(xB, 1 - bottom)
			b.Size = size
			b.BackgroundColor3 = color
			slot += 1
		end

		if total <= 0 then
			hideFrom(listA, 1)
			hideFrom(listB, 1)
			return
		end

		if total / span < minimumAlpha then
			place(minimumAlpha, 0, series[dominant].Color)
		else
			local bottom = 0
			for seriesIndex = 1, seriesCount do
				local count = counts[seriesIndex] or 0
				if count <= 0 or bottom >= 1 then continue end
				local alpha = math.min(count / span, 1 - bottom)
				place(alpha, bottom, series[seriesIndex].Color)
				bottom += alpha
			end
			if total > maximum then
				place(capAlpha, 1 - capAlpha, clipColor)
			end
		end
		hideFrom(listA, slot)
		hideFrom(listB, slot)
	end

	local head = 0
	local seenMax = 0

	local graph = {} :: any
	graph.Frame = row
	graph.Header = header

	function graph.Push(_, counts: { number })
		head = head % columnCount + 1
		local total = 0
		for seriesIndex = 1, seriesCount do
			total += counts[seriesIndex] or 0
		end
		values[head] = if total > 0 then table.clone(counts) else nil
		seenMax = math.max(seenMax, total)
		paint(head)
		strip.Position = UDim2.fromScale(-head / columnCount, 0)
		header.Text = string.format("%s  now " .. format .. "  max " .. format, label, total, seenMax)
	end

	function graph.Clear(_)
		head = 0
		seenMax = 0
		for index = 1, columnCount do
			values[index] = nil
			paint(index)
		end
		strip.Position = UDim2.fromScale(0, 0)
		header.Text = label
	end

	return graph :: StackedGraph
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
