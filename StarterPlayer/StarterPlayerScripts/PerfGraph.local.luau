local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TOGGLE_KEY = Enum.KeyCode.F8
local PANEL_WIDTH = 660
local GRAPH_HEIGHT = 110
local AXIS_WIDTH = 36
local HEADER_HEIGHT = 14
local LEGEND_HEIGHT = 26
local GAP = 2
local COLUMN_COUNT = PANEL_WIDTH - 20 - AXIS_WIDTH
local DOUBLED = COLUMN_COUNT * 2
local COLUMN_WIDTH = 1 / DOUBLED

local FPS_MAXIMUM = 120
local FPS_REFERENCES = { 30, 60, 90 }
local FPS_WARN = 45
local FPS_BAD = 25
local FPS_GOOD_COLOR = Color3.fromRGB(120, 200, 120)
local FPS_WARN_COLOR = Color3.fromRGB(230, 190, 80)
local FPS_BAD_COLOR = Color3.fromRGB(220, 80, 80)

local CHURN_MAXIMUM = 500
local CHURN_REFERENCES = { 100, 200, 300, 400 }
local CLIP_COLOR = Color3.fromRGB(255, 255, 255)

local CATEGORIES = {
	{ Name = "parts", Color = Color3.fromRGB(110, 160, 230), Classes = { "BasePart" } },
	{ Name = "models/folders", Color = Color3.fromRGB(200, 200, 90), Classes = { "Model", "Folder", "Configuration" } },
	{ Name = "scripts", Color = Color3.fromRGB(230, 90, 90), Classes = { "LuaSourceContainer" } },
	{ Name = "lights", Color = Color3.fromRGB(255, 215, 120), Classes = { "Light" } },
	{ Name = "effects", Color = Color3.fromRGB(255, 140, 60), Classes = { "ParticleEmitter", "Beam", "Trail", "Smoke", "Fire", "Sparkles", "Highlight", "Explosion" } },
	{ Name = "textures/meshes", Color = Color3.fromRGB(180, 120, 220), Classes = { "SurfaceAppearance", "Texture", "Decal", "DataModelMesh" } },
	{ Name = "audio", Color = Color3.fromRGB(80, 200, 180), Classes = { "Sound", "SoundGroup", "SoundEffect", "AudioEmitter", "AudioListener", "AudioPlayer", "AudioFader", "AudioDeviceInput", "AudioDeviceOutput", "Wire" } },
	{ Name = "joints/attachments", Color = Color3.fromRGB(160, 160, 160), Classes = { "Constraint", "JointInstance", "Attachment", "WeldConstraint" } },
	{ Name = "gui", Color = Color3.fromRGB(255, 120, 200), Classes = { "GuiBase", "UIBase", "LayerCollector" } },
	{ Name = "values/attrs", Color = Color3.fromRGB(120, 220, 120), Classes = { "ValueBase" } },
	{ Name = "characters/anim", Color = Color3.fromRGB(220, 180, 130), Classes = { "Humanoid", "Accoutrement", "Clothing", "BodyColors", "CharacterMesh", "Animator", "AnimationController", "Animation", "Motor6D" } },
	{ Name = "other", Color = Color3.fromRGB(90, 90, 110), Classes = {} },
}
local CATEGORY_COUNT = #CATEGORIES

local gui = Instance.new("ScreenGui")
gui.Name = "PerfGraph"
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

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function addText(text: string, size: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.LayoutOrder = nextOrder()
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = text
	label.Parent = panel
	return label
end

local function addButton(text: string, activated: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Modal = true
	button.Size = UDim2.new(1, 0, 0, 26)
	button.LayoutOrder = nextOrder()
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 13
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = panel
	button.Activated:Connect(activated)
	return button
end

local function colorToHex(color: Color3): string
	return string.format("#%02x%02x%02x", math.round(color.R * 255), math.round(color.G * 255), math.round(color.B * 255))
end

local function buildScaffold(label: string, maximum: number, references: { number }, format: string, legendHeight: number)
	local plotTop = HEADER_HEIGHT + GAP + legendHeight

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, plotTop + GRAPH_HEIGHT)
	row.LayoutOrder = nextOrder()
	row.BackgroundTransparency = 1
	row.Parent = panel

	local header = Instance.new("TextLabel")
	header.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	header.BackgroundTransparency = 1
	header.Font = Enum.Font.Code
	header.TextSize = 12
	header.TextColor3 = Color3.new(1, 1, 1)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.Text = label
	header.Parent = row

	local plot = Instance.new("Frame")
	plot.Position = UDim2.new(0, 0, 0, plotTop)
	plot.Size = UDim2.new(1, -AXIS_WIDTH, 0, GRAPH_HEIGHT)
	plot.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
	plot.BackgroundTransparency = 0.1
	plot.BorderSizePixel = 0
	plot.ClipsDescendants = true
	plot.Parent = row

	local axis = Instance.new("Frame")
	axis.Position = UDim2.new(1, -AXIS_WIDTH, 0, plotTop)
	axis.Size = UDim2.new(0, AXIS_WIDTH, 0, GRAPH_HEIGHT)
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
		local alpha = math.clamp(reference / maximum, 0, 1)
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
	addAxisLabel(0, 0)

	local strip = Instance.new("Frame")
	strip.Size = UDim2.fromScale(2, 1)
	strip.BackgroundTransparency = 1
	strip.Parent = plot

	return row, header, strip
end

local function fpsColor(fps: number): Color3
	if fps < FPS_BAD then
		return FPS_BAD_COLOR
	elseif fps < FPS_WARN then
		return FPS_WARN_COLOR
	end
	return FPS_GOOD_COLOR
end

local fpsHeader, fpsStrip
do
	local _, header, strip = buildScaffold("FPS", FPS_MAXIMUM, FPS_REFERENCES, "%.0f", 0)
	fpsHeader, fpsStrip = header, strip
end

local fpsColumnsA: { Frame } = table.create(COLUMN_COUNT)
local fpsColumnsB: { Frame } = table.create(COLUMN_COUNT)
for copy = 0, 1 do
	local target = if copy == 0 then fpsColumnsA else fpsColumnsB
	for index = 1, COLUMN_COUNT do
		local column = Instance.new("Frame")
		column.AnchorPoint = Vector2.new(0, 1)
		column.Position = UDim2.fromScale((copy * COLUMN_COUNT + index - 1) / DOUBLED, 1)
		column.Size = UDim2.fromScale(COLUMN_WIDTH, 0)
		column.BackgroundColor3 = FPS_GOOD_COLOR
		column.BorderSizePixel = 0
		column.Parent = fpsStrip
		target[index] = column
	end
end

local fpsHead = 0
local fpsMin = math.huge
local fpsMax = -math.huge

local function pushFps(fps: number)
	fpsHead = fpsHead % COLUMN_COUNT + 1
	fpsMin = math.min(fpsMin, fps)
	fpsMax = math.max(fpsMax, fps)
	local alpha = fps / FPS_MAXIMUM
	local color = fpsColor(fps)
	if alpha > 1 then
		alpha = 1
		color = CLIP_COLOR
	end
	if alpha > 0 and alpha < 1 / GRAPH_HEIGHT then
		alpha = 1 / GRAPH_HEIGHT
	end
	local size = UDim2.fromScale(COLUMN_WIDTH, math.clamp(alpha, 0, 1))
	local a, b = fpsColumnsA[fpsHead], fpsColumnsB[fpsHead]
	a.Size = size
	b.Size = size
	a.BackgroundColor3 = color
	b.BackgroundColor3 = color
	fpsStrip.Position = UDim2.fromScale(-fpsHead / COLUMN_COUNT, 0)
	fpsHeader.Text = string.format("FPS  now %.0f  min %.0f  max %.0f", fps, fpsMin, fpsMax)
end

local function clearFps()
	fpsHead = 0
	fpsMin = math.huge
	fpsMax = -math.huge
	for index = 1, COLUMN_COUNT do
		fpsColumnsA[index].Size = UDim2.fromScale(COLUMN_WIDTH, 0)
		fpsColumnsB[index].Size = UDim2.fromScale(COLUMN_WIDTH, 0)
	end
	fpsStrip.Position = UDim2.fromScale(0, 0)
	fpsHeader.Text = "FPS"
end

local churnRow, churnHeader, churnStrip = buildScaffold("instances streamed in + out per frame", CHURN_MAXIMUM, CHURN_REFERENCES, "%d", LEGEND_HEIGHT)

local legendParts = {}
for _, category in CATEGORIES do
	table.insert(legendParts, string.format('<font color="%s">■</font> %s', colorToHex(category.Color), category.Name))
end
table.insert(legendParts, string.format('<font color="%s">■</font> over %d', colorToHex(CLIP_COLOR), CHURN_MAXIMUM))

local legend = Instance.new("TextLabel")
legend.Position = UDim2.new(0, 0, 0, HEADER_HEIGHT)
legend.Size = UDim2.new(1, 0, 0, LEGEND_HEIGHT)
legend.BackgroundTransparency = 1
legend.Font = Enum.Font.Code
legend.TextSize = 10
legend.TextColor3 = Color3.fromRGB(200, 200, 210)
legend.TextXAlignment = Enum.TextXAlignment.Left
legend.TextYAlignment = Enum.TextYAlignment.Top
legend.TextWrapped = true
legend.RichText = true
legend.Text = table.concat(legendParts, "   ")
legend.Parent = churnRow

local segmentsA: { { Frame } } = table.create(COLUMN_COUNT)
local segmentsB: { { Frame } } = table.create(COLUMN_COUNT)
local churnValues: { { number }? } = table.create(COLUMN_COUNT)
for index = 1, COLUMN_COUNT do
	segmentsA[index] = {}
	segmentsB[index] = {}
end

local function segmentAt(list: { Frame }, slot: number): Frame
	local segment = list[slot]
	if not segment then
		segment = Instance.new("Frame")
		segment.AnchorPoint = Vector2.new(0, 1)
		segment.BorderSizePixel = 0
		segment.Parent = churnStrip
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

local function paintChurn(index: number)
	local counts = churnValues[index]
	local listA, listB = segmentsA[index], segmentsB[index]
	if not counts then
		hideFrom(listA, 1)
		hideFrom(listB, 1)
		return
	end

	local xA = (index - 1) * COLUMN_WIDTH
	local xB = (COLUMN_COUNT + index - 1) * COLUMN_WIDTH
	local total = 0
	local dominant = 1
	for categoryIndex = 1, CATEGORY_COUNT do
		local count = counts[categoryIndex]
		total += count
		if count > counts[dominant] then
			dominant = categoryIndex
		end
	end

	local slot = 1
	local function place(alpha: number, bottom: number, color: Color3)
		local size = UDim2.fromScale(COLUMN_WIDTH, alpha)
		local a = segmentAt(listA, slot)
		a.Position = UDim2.fromScale(xA, 1 - bottom)
		a.Size = size
		a.BackgroundColor3 = color
		local b = segmentAt(listB, slot)
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

	if total / CHURN_MAXIMUM < 1 / GRAPH_HEIGHT then
		place(1 / GRAPH_HEIGHT, 0, CATEGORIES[dominant].Color)
	else
		local bottom = 0
		for categoryIndex = 1, CATEGORY_COUNT do
			local count = counts[categoryIndex]
			if count <= 0 or bottom >= 1 then continue end
			local alpha = math.min(count / CHURN_MAXIMUM, 1 - bottom)
			place(alpha, bottom, CATEGORIES[categoryIndex].Color)
			bottom += alpha
		end
		if total > CHURN_MAXIMUM then
			place(2 / GRAPH_HEIGHT, 1 - 2 / GRAPH_HEIGHT, CLIP_COLOR)
		end
	end
	hideFrom(listA, slot)
	hideFrom(listB, slot)
end

local churnHead = 0
local churnMax = 0

local function pushChurn(counts: { number })
	churnHead = churnHead % COLUMN_COUNT + 1
	local total = 0
	for categoryIndex = 1, CATEGORY_COUNT do
		total += counts[categoryIndex]
	end
	churnValues[churnHead] = if total > 0 then table.clone(counts) else nil
	churnMax = math.max(churnMax, total)
	paintChurn(churnHead)
	churnStrip.Position = UDim2.fromScale(-churnHead / COLUMN_COUNT, 0)
	churnHeader.Text = string.format("instances streamed in + out per frame  now %d  max %d", total, churnMax)
end

local function clearChurn()
	churnHead = 0
	churnMax = 0
	for index = 1, COLUMN_COUNT do
		churnValues[index] = nil
		paintChurn(index)
	end
	churnStrip.Position = UDim2.fromScale(0, 0)
	churnHeader.Text = "instances streamed in + out per frame"
end

local paused = false
local pauseButton: TextButton
pauseButton = addButton("pause", function()
	paused = not paused
	pauseButton.Text = if paused then "resume" else "pause"
end)

addButton("clear", function()
	clearFps()
	clearChurn()
end)

addText("F8 toggles. newest frame is at the right edge. bars above the top of a graph clip and are capped in white. this script is standalone and needs nothing else running.", 11, Color3.fromRGB(150, 150, 160))

local counts: { number } = table.create(CATEGORY_COUNT, 0)

local function categoryOf(instance: Instance): number
	for index, category in CATEGORIES do
		for _, className in category.Classes do
			if instance:IsA(className) then
				return index
			end
		end
	end
	return CATEGORY_COUNT
end

local function record(instance: Instance)
	counts[categoryOf(instance)] += 1
end

workspace.DescendantAdded:Connect(record)
workspace.DescendantRemoving:Connect(record)

RunService.RenderStepped:Connect(function(deltaTime: number)
	if not paused then
		pushFps(1 / math.max(deltaTime, 1e-6))
		pushChurn(counts)
	end
	for index = 1, CATEGORY_COUNT do
		counts[index] = 0
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == TOGGLE_KEY then
		gui.Enabled = not gui.Enabled
	end
end)
