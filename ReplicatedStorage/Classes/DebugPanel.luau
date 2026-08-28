local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local InterfaceService = require(game:GetService("ReplicatedStorage").Services.InterfaceService)

local PANEL_WIDTH = 300
local ROW_HEIGHT = 34
local TRACK_HEIGHT = 10
local TRACK_OFFSET = 18

local DebugPanel = {}
DebugPanel.__index = DebugPanel

export type DebugPanel = typeof(setmetatable({} :: {
	Gui: ScreenGui,
	Panel: Frame,
	Heading: TextLabel,
	_toggleKey: Enum.KeyCode,
	_order: number,
	_dragging: ((number) -> ())?,
	_connections: { RBXScriptConnection },
}, DebugPanel))

function DebugPanel.new(title: string, toggleKey: Enum.KeyCode): DebugPanel
	local self = setmetatable({}, DebugPanel)

	local gui = Instance.new("ScreenGui")
	gui.Name = `DebugPanel_{title}`
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0, 12, 0, 12)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 0)
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
	self._toggleKey = toggleKey
	self._order = 0
	self._dragging = nil
	self._connections = {}

	table.insert(self._connections, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == toggleKey then
			gui.Enabled = not gui.Enabled
			InterfaceService:SetMouseUnlocked(gui.Enabled)
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
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Code
	caption.TextSize = 12
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Parent = row

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

	local function display(value: number)
		fill.Size = UDim2.fromScale(math.clamp((value - minimum) / (maximum - minimum), 0, 1), 1)
		caption.Text = `{label}: {string.format(format, value)}`
	end

	local function setFromX(x: number)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local raw = minimum + (maximum - minimum) * alpha
		local value = if step > 0 then math.round(raw / step) * step else raw
		display(value)
		apply(value)
	end

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

function DebugPanel:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.Gui:Destroy()
end

return DebugPanel
