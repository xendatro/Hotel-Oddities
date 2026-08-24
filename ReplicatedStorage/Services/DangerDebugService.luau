local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DebugPanel = require(ReplicatedStorage.Classes.DebugPanel)
local DangerField = require(ReplicatedStorage.Modules.DangerField)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local MAZE_FLOOR_TAG = "MazeFloor"
local START_TAG = "Start"

local TOGGLE_KEY = Enum.KeyCode.F4
local HEATMAP_SPACING = 24
local HEATMAP_LIMIT = 4000
local HEATMAP_BATCH = 250
local REDRAW_DEBOUNCE = 0.15
local MARKER_SIZE = Vector3.new(6, 0.2, 6)
local MARKER_HEIGHT = 0.6

local READOUT_INTERVAL = 0.1

local TAG_WAIT_TIMEOUT = 20
local TAG_POLL_INTERVAL = 0.25
local TAG_SETTLE_POLLS = 4

local DangerDebugService = {}

if not (FLAGS.DangerDebug and RunService:IsClient()) then
	return DangerDebugService
end

local LocalPlayer = Players.LocalPlayer

local SetConfig: RemoteEvent? = nil

local Settings: DangerField.FieldSettings
local Extent = 1
local Floors: { BasePart } = {}
local MarkerFolder: Folder? = nil
local HeatmapOn = false
local Generation = 0
local GateOn = true

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

local function requestRedraw()
	if RedrawPending then return end
	RedrawPending = true

	task.delay(REDRAW_DEBOUNCE, function()
		RedrawPending = false
		drawHeatmap()
	end)
end

local function build()
	local debugPanel = DebugPanel.new(`danger map -- extent {math.floor(Extent)} studs`, TOGGLE_KEY)
	local gui = debugPanel.Gui
	local readout = debugPanel:AddLabel("here: --")

	task.spawn(function()
		while readout.Parent do
			task.wait(READOUT_INTERVAL)
			if not gui.Enabled then continue end

			local character = LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				readout.Text = "here: no character"
				continue
			end

			local position = root.Position
			local gate = DangerField.SampleGate(position, Settings)
			local field = DangerField.SampleField(position, Settings)
			readout.Text = string.format("here: %.2f\ngate %.2f  field %.2f  floor %d",
				gate * field, gate, field, DangerField.GetFloorIndex(position, Settings))
			readout.TextColor3 = dangerColor(gate * field)
		end
	end)

	debugPanel:AddSlider("Seed", 1, math.max(2000, Settings.Seed), Settings.Seed, 1, function(value)
		Settings.Seed = value
		requestRedraw()
	end)

	debugPanel:AddSlider("FeatureScale", Extent * 0.04, Extent * 0.5, Settings.FeatureScale, 1, function(value)
		Settings.FeatureScale = value
		requestRedraw()
	end)

	debugPanel:AddSlider("Contrast", 1, 4, Settings.Contrast, 0.1, function(value)
		Settings.Contrast = value
		requestRedraw()
	end)

	debugPanel:AddSlider("NoiseGain", 0.5, 3, Settings.NoiseGain, 0.05, function(value)
		Settings.NoiseGain = value
		requestRedraw()
	end)

	debugPanel:AddSlider("SafeRadius", 0, Extent * 0.3, Settings.SafeRadius, 1, function(value)
		Settings.SafeRadius = value
		requestRedraw()
	end)

	debugPanel:AddSlider("RampLength", 1, Extent * 0.6, Settings.RampLength, 1, function(value)
		Settings.RampLength = value
		requestRedraw()
	end)

	debugPanel:AddSlider("Octaves", 1, 4, Settings.Octaves, 1, function(value)
		Settings.Octaves = value
		requestRedraw()
	end)

	local heatmapButton
	heatmapButton = debugPanel:AddButton("heatmap: off", function()
		HeatmapOn = not HeatmapOn
		heatmapButton.Text = `heatmap: {if HeatmapOn then "on" else "off"}`
		drawHeatmap()
	end)

	local gateButton
	gateButton = debugPanel:AddButton("showing: gated field", function()
		GateOn = not GateOn
		gateButton.Text = `showing: {if GateOn then "gated field" else "raw noise"}`
		drawHeatmap()
	end)

	debugPanel:AddButton("apply to server", function()
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

	debugPanel:AddButton("reload map from tags", function()
		rebuildSettings()
		debugPanel:SetTitle(`danger map -- extent {math.floor(Extent)} studs`)
		drawHeatmap()
	end)

	debugPanel:AddLabel("sliders redraw locally. apply sends them to the server, which rebakes and clears "
		.. "everything the director owns. copy the numbers you settle on into DangerConfig.")
end

task.spawn(function()
	local deadline = os.clock() + TAG_WAIT_TIMEOUT
	local previous, settled = -1, 0

	while os.clock() < deadline do
		local count = #getFloors()
		if count > 0 and count == previous then
			settled += 1
			if settled >= TAG_SETTLE_POLLS then break end
		else
			settled = 0
		end
		previous = count
		task.wait(TAG_POLL_INTERVAL)
	end

	rebuildSettings()
	build()
end)

task.spawn(function()
	SetConfig = CommunicationService.Get("Danger", "SetConfig") :: RemoteEvent
end)

return DangerDebugService
