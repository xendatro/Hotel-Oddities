--- Client half of the danger map's tuning tools: a heatmap you can walk around inside, and sliders
--- for the handful of numbers that decide what it looks like. Temporary -- delete alongside the
--- server half, the `DangerDebug` flag and the `Danger` remote folder once a seed has been picked.
---
--- The field is a pure function of position, so none of this needs the server. Sliders move a local
--- copy of the settings, the heatmap redraws from it immediately, and only pressing Apply sends the
--- numbers over for the population to be rebuilt against. That means seed-shopping is instant: roll,
--- look, roll again, and only commit to the one whose bad wings sit somewhere interesting.
---
--- Toggle the panel with F4.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)
local DangerField = require(ReplicatedStorage.Modules.DangerField)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local MAZE_FLOOR_TAG = "MazeFloor"
local START_TAG = "Start"

local TOGGLE_KEY = Enum.KeyCode.F4
local HEATMAP_SPACING = 24 -- studs; far coarser than the spawn pool, or the part count is unusable
local HEATMAP_LIMIT = 4000
local HEATMAP_BATCH = 250 -- parts built between yields, so a redraw does not freeze the frame
local REDRAW_DEBOUNCE = 0.15 -- seconds of a slider standing still before the map is rebuilt
local MARKER_SIZE = Vector3.new(6, 0.2, 6)
local MARKER_HEIGHT = 0.6 -- studs above the floor, clear of z-fighting with it

local PANEL_WIDTH = 300
local ROW_HEIGHT = 34

local DangerDebugService = {}

if not (FLAGS.DangerDebug and RunService:IsClient()) then
	return DangerDebugService
end

local LocalPlayer = Players.LocalPlayer

-- Resolved on its own thread rather than at the top of the file. The client bootstrap requires every
-- service in a single synchronous loop, so a `WaitForChild` here that never resolves would stop every
-- other client service from loading at all -- and a temporary debug panel must not be able to take
-- the game down with it if its remote folder has not been authored yet.
local SetConfig: RemoteEvent? = nil

local Settings: DangerField.FieldSettings
local Extent = 1
local Floors: { BasePart } = {}
local MarkerFolder: Folder? = nil
local HeatmapOn = false
local Generation = 0 -- so a redraw started while another is still batching abandons the older one
local GateOn = true -- whether the heatmap shows the gated field or the raw noise

local function getFloors(): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(floors, instance)
		end
	end
	return floors
end

local function rebuildSettings()
	Floors = getFloors()

	local extent, centre = DangerField.MeasureExtent(Floors)
	Extent = extent

	local startPart = CollectionService:GetTagged(START_TAG)[1] :: BasePart?
	Settings = DangerField.BuildSettings(if startPart then startPart.Position else centre, extent)
end

--- Green through to red. Hue runs a third of the way round the wheel, which puts calm at green, the
--- middle at yellow and the worst of it at red -- the reading everybody already has for a heatmap.
local function dangerColor(danger: number): Color3
	return Color3.fromHSV((1 - math.clamp(danger, 0, 1)) * 0.33, 1, 1)
end

local function clearHeatmap()
	if MarkerFolder then
		MarkerFolder:Destroy()
		MarkerFolder = nil
	end
end

local function drawHeatmap()
	clearHeatmap()
	if not HeatmapOn then return end

	Generation += 1
	local generation = Generation

	local folder = Instance.new("Folder")
	folder.Name = "DangerHeatmap"
	folder.Parent = workspace
	MarkerFolder = folder

	task.spawn(function()
		local points = DangerField.BakePoints(Floors, HEATMAP_SPACING, Settings)
		local built = 0

		for _, point in points do
			if generation ~= Generation then return end
			if built >= HEATMAP_LIMIT then break end

			local danger = if GateOn
				then point.Danger
				else DangerField.SampleField(point.Position, Settings)

			local marker = Instance.new("Part")
			marker.Size = MARKER_SIZE
			marker.Anchored = true
			marker.CanCollide = false
			marker.CanQuery = false
			marker.CanTouch = false
			marker.Material = Enum.Material.Neon
			marker.Color = dangerColor(danger)
			marker.Transparency = 0.35
			marker.Position = point.Position + Vector3.yAxis * MARKER_HEIGHT
			marker.Parent = folder

			built += 1
			if built % HEATMAP_BATCH == 0 then
				RunService.Heartbeat:Wait()
				if generation ~= Generation then return end
			end
		end
	end)
end

local RedrawPending = false

--- Coalesces redraws. A slider fires on every frame of a drag, and each redraw re-bakes the whole
--- field, so calling `drawHeatmap` directly from one turns a two-second drag into a hundred full
--- bakes and a locked client.
local function requestRedraw()
	if RedrawPending then return end
	RedrawPending = true

	task.delay(REDRAW_DEBOUNCE, function()
		RedrawPending = false
		drawHeatmap()
	end)
end

--- One labelled slider. `apply` receives the new value; the caller decides what that means.
local function buildSlider(
	parent: Instance,
	order: number,
	label: string,
	minimum: number,
	maximum: number,
	initial: number,
	step: number,
	apply: (number) -> ()
)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, ROW_HEIGHT)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Parent = parent

	local caption = Instance.new("TextLabel")
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.Code
	caption.TextSize = 12
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.TextXAlignment = Enum.TextXAlignment.Left
	caption.Text = `{label}: {initial}`
	caption.Parent = row

	local track = Instance.new("Frame")
	track.Position = UDim2.new(0, 0, 0, 18)
	track.Size = UDim2.new(1, 0, 0, 10)
	track.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	track.BorderSizePixel = 0
	track.Parent = row

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale((initial - minimum) / (maximum - minimum), 1)
	fill.BackgroundColor3 = Color3.fromRGB(190, 90, 90)
	fill.BorderSizePixel = 0
	fill.Parent = track

	local dragging = false

	local function setFromX(x: number)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		local raw = minimum + (maximum - minimum) * alpha
		local value = if step > 0 then math.round(raw / step) * step else raw

		fill.Size = UDim2.fromScale((value - minimum) / (maximum - minimum), 1)
		caption.Text = `{label}: {string.format(if step >= 1 then "%d" else "%.2f", value)}`
		apply(value)
	end

	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging
			and (input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function buildButton(parent: Instance, order: number, text: string, activated: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 0, 26)
	button.LayoutOrder = order
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.Code
	button.TextSize = 13
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = parent
	button.Activated:Connect(activated)
	return button
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DangerDebug"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.Position = UDim2.new(0, 12, 0, 12)
	panel.Size = UDim2.new(0, PANEL_WIDTH, 0, 560)
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	panel.BackgroundTransparency = 0.1
	panel.BorderSizePixel = 0
	panel.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 18)
	title.LayoutOrder = 0
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.Code
	title.TextSize = 14
	title.TextColor3 = Color3.fromRGB(255, 170, 170)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = `danger map -- extent {math.floor(Extent)} studs`
	title.Parent = panel

	-- Whole studs, because the seed is a number you shop for rather than interpolate through: every
	-- step is a completely different hotel and there is no sense in which 4.5 sits between 4 and 5.
	buildSlider(panel, 1, "Seed", 1, 200, Settings.Seed, 1, function(value)
		Settings.Seed = value
		requestRedraw()
	end)

	buildSlider(panel, 2, "FeatureScale", Extent * 0.04, Extent * 0.5, Settings.FeatureScale, 1, function(value)
		Settings.FeatureScale = value
		requestRedraw()
	end)

	buildSlider(panel, 3, "Contrast", 1, 4, Settings.Contrast, 0.1, function(value)
		Settings.Contrast = value
		requestRedraw()
	end)

	buildSlider(panel, 4, "NoiseGain", 0.5, 3, Settings.NoiseGain, 0.05, function(value)
		Settings.NoiseGain = value
		requestRedraw()
	end)

	buildSlider(panel, 5, "SafeRadius", 0, Extent * 0.3, Settings.SafeRadius, 1, function(value)
		Settings.SafeRadius = value
		requestRedraw()
	end)

	buildSlider(panel, 6, "RampLength", 1, Extent * 0.6, Settings.RampLength, 1, function(value)
		Settings.RampLength = value
		requestRedraw()
	end)

	buildSlider(panel, 7, "Octaves", 1, 4, Settings.Octaves, 1, function(value)
		Settings.Octaves = value
		requestRedraw()
	end)

	local heatmapButton
	heatmapButton = buildButton(panel, 8, "heatmap: off", function()
		HeatmapOn = not HeatmapOn
		heatmapButton.Text = `heatmap: {if HeatmapOn then "on" else "off"}`
		drawHeatmap()
	end)

	local gateButton
	gateButton = buildButton(panel, 9, "showing: gated field", function()
		GateOn = not GateOn
		gateButton.Text = `showing: {if GateOn then "gated field" else "raw noise"}`
		drawHeatmap()
	end)

	buildButton(panel, 10, "apply to server", function()
		if not SetConfig then
			warn("[danger] no Communication/Danger/SetConfig remote yet; sliders are local only")
			return
		end
		SetConfig:FireServer({
			Seed = Settings.Seed,
			FeatureScale = Settings.FeatureScale,
			Contrast = Settings.Contrast,
			NoiseGain = Settings.NoiseGain,
			SafeRadius = Settings.SafeRadius,
			RampLength = Settings.RampLength,
			Octaves = Settings.Octaves,
			Persistence = Settings.Persistence,
			FloorHeight = Settings.FloorHeight,
			FloorSeparation = Settings.FloorSeparation,
		})
	end)

	buildButton(panel, 11, "reload map from tags", function()
		rebuildSettings()
		title.Text = `danger map -- extent {math.floor(Extent)} studs`
		drawHeatmap()
	end)

	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.new(1, 0, 0, 60)
	hint.LayoutOrder = 12
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Code
	hint.TextSize = 11
	hint.TextColor3 = Color3.fromRGB(150, 150, 160)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextYAlignment = Enum.TextYAlignment.Top
	hint.TextWrapped = true
	hint.Text = "sliders redraw locally. apply sends them to the server, which rebakes and clears "
		.. "everything the director owns. copy the numbers you settle on into DangerConfig."
	hint.Parent = panel

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == TOGGLE_KEY then
			gui.Enabled = not gui.Enabled
		end
	end)
end

rebuildSettings()
build()

task.spawn(function()
	SetConfig = ReplicatedStorage
		:WaitForChild("Communication")
		:WaitForChild("Danger")
		:WaitForChild("SetConfig") :: RemoteEvent
end)

return DangerDebugService
