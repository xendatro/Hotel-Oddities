local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local MapConfig = require(ReplicatedStorage.Configs.MapConfig)
local MapMarkerLayer = require(ReplicatedStorage.Classes.MapMarkerLayer)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MapControlService = require(ReplicatedStorage.Services.MapControlService)
local MapInkService = require(ReplicatedStorage.Services.MapInkService)
local MapLayoutService = require(ReplicatedStorage.Services.MapLayoutService)
local ComputerService = require(ReplicatedStorage.Services.ComputerService)
local xenterface = require(ReplicatedStorage.Frameworks.xenterface)

local Gui = MapConfig.Gui
local Remotes = MapConfig.Remotes

local MapService = {}

local Player = Players.LocalPlayer
local Paper: ImageLabel? = nil
local LegendPlaque: any = nil
local Layers: { MapMarkerLayer.MapMarkerLayer } = {}
local Layer: MapMarkerLayer.MapMarkerLayer? = nil
local LandmarkKinds: { [string]: string } = {}
local PendingRooms: { { Key: string, Packed: { number } } } = {}
local PendingPops: { string } = {}
local IsOpen = false
local Pending = false

local function getPaper(): ImageLabel
	if Paper then return Paper :: ImageLabel end

	local playerGui = Player:WaitForChild("PlayerGui")
	local screen = playerGui:WaitForChild(Gui.ScreenGui)
	Paper = screen:WaitForChild(Gui.Paper) :: ImageLabel
	return Paper :: ImageLabel
end

local function buildViewport(paper: ImageLabel): (CanvasGroup, Frame)
	local inset = MapConfig.Controls.Inset

	local viewport = Instance.new("CanvasGroup")
	viewport.Name = Gui.ViewportName
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.Size = UDim2.fromScale(1 - inset * 2, 1 - inset * 2)
	viewport.BackgroundTransparency = 1
	viewport.ClipsDescendants = true
	viewport.Active = true
	viewport.ZIndex = 2
	viewport.Parent = paper

	local content = Instance.new("Frame")
	content.Name = Gui.ContentName
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromScale(1, 1)
	content.BackgroundTransparency = 1
	content.ZIndex = 3
	content.Parent = viewport

	return viewport, content
end

local function buildSwatch(parent: Frame, kind: string): CanvasGroup
	local swatch = Instance.new("CanvasGroup")
	swatch.Name = kind .. "Swatch"
	swatch.Size = UDim2.fromOffset(MapConfig.Legend.SwatchSize, MapConfig.Legend.SwatchSize)
	swatch.BackgroundColor3 = if kind == "Done" then MapConfig.Markers.DoneFill else MapConfig.Markers.Fill
	swatch.BorderSizePixel = 0
	swatch.ClipsDescendants = true
	swatch.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = MapConfig.Ink.Color
	stroke.Thickness = 2
	stroke.Parent = swatch

	if kind == "Done" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = swatch

		local tick = Instance.new("TextLabel")
		tick.Size = UDim2.fromScale(1, 1)
		tick.BackgroundTransparency = 1
		tick.Font = MapConfig.Legend.Font
		tick.Text = MapConfig.Markers.DoneGlyph
		tick.TextColor3 = MapConfig.Ink.Color
		tick.TextScaled = true
		tick.Parent = swatch
		return swatch
	end

	for index = -2, 3 do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5 + index * 0.26, 0.5)
		line.Size = UDim2.fromOffset(2, MapConfig.Legend.SwatchSize * 2)
		line.Rotation = 45
		line.BackgroundColor3 = MapConfig.Ink.Color
		line.BorderSizePixel = 0
		line.Parent = swatch
	end
	return swatch
end

local function buildLegend(paper: ImageLabel): Frame
	local legend = Instance.new("Frame")
	legend.Name = Gui.LegendName
	legend.AnchorPoint = Vector2.new(0, 0)
	legend.Position = UDim2.fromScale(MapConfig.Controls.Inset, MapConfig.Controls.Inset)
	legend.Size = UDim2.fromOffset(MapConfig.Legend.Width, MapConfig.Legend.Height)
	legend.BackgroundTransparency = 1
	legend.BorderSizePixel = 0
	legend.ZIndex = 30
	legend.Parent = paper

	if LegendPlaque then LegendPlaque:Destroy() end
	LegendPlaque = MapInkService:CreatePlaque(MapConfig.Legend.Width, MapConfig.Legend.Height, "legend")

	local extent = math.max(MapConfig.Legend.Width, MapConfig.Legend.Height)
	local border = Instance.new("ImageLabel")
	border.Name = "Border"
	border.BackgroundTransparency = 1
	border.Position = UDim2.fromOffset(0, 0)
	border.Size = UDim2.fromOffset(extent, extent)
	border.ScaleType = Enum.ScaleType.Stretch
	border.ImageContent = LegendPlaque.Content
	border.ZIndex = 32
	border.Parent = legend

	local rows = Instance.new("Frame")
	rows.Name = "Rows"
	rows.Size = UDim2.fromScale(1, 1)
	rows.BackgroundTransparency = 1
	rows.ZIndex = 33
	rows.Parent = legend

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, MapConfig.Legend.Padding)
	padding.PaddingBottom = UDim.new(0, MapConfig.Legend.Padding)
	padding.PaddingLeft = UDim.new(0, MapConfig.Legend.Padding)
	padding.PaddingRight = UDim.new(0, MapConfig.Legend.Padding)
	padding.Parent = rows

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.Padding = UDim.new(0, MapConfig.Legend.Spacing)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = rows

	for index, row in MapConfig.Legend.Rows do
		local line = Instance.new("Frame")
		line.Name = row.Kind
		line.LayoutOrder = index
		line.AutomaticSize = Enum.AutomaticSize.X
		line.Size = UDim2.fromOffset(0, MapConfig.Legend.SwatchSize)
		line.BackgroundTransparency = 1
		line.ZIndex = 33
		line.Parent = rows

		local rowList = Instance.new("UIListLayout")
		rowList.FillDirection = Enum.FillDirection.Horizontal
		rowList.VerticalAlignment = Enum.VerticalAlignment.Center
		rowList.Padding = UDim.new(0, MapConfig.Legend.Padding)
		rowList.Parent = line

		local swatch = buildSwatch(line, row.Kind)
		swatch.LayoutOrder = 1
		swatch.ZIndex = 34

		local label = Instance.new("TextLabel")
		label.LayoutOrder = 2
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.fromOffset(0, MapConfig.Legend.SwatchSize)
		label.BackgroundTransparency = 1
		label.Font = MapConfig.Legend.Font
		label.Text = row.Label
		label.TextColor3 = MapConfig.Ink.Color
		label.TextSize = MapConfig.Legend.TextSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.ZIndex = 34
		label.Parent = line
	end

	return legend
end

function MapService:GetPaper(): ImageLabel?
	return Paper
end

function MapService:ToPaperScale(worldX: number, worldZ: number): UDim2
	local canvas = MapLayoutService:ToCanvas(worldX, worldZ)
	local resolution = MapConfig.Canvas.Resolution
	return UDim2.fromScale(canvas.X / resolution, canvas.Y / resolution)
end

function MapService:RegisterLayer(layer: MapMarkerLayer.MapMarkerLayer)
	table.insert(Layers, layer)

	for key, kind in LandmarkKinds do
		layer:PlaceLandmark(kind, key)
	end
	MapService:RefreshComputers()
end

function MapService:UnregisterLayer(layer: MapMarkerLayer.MapMarkerLayer)
	local index = table.find(Layers, layer)
	if index then table.remove(Layers, index) end
end

local function placeLandmark(kind: string, key: string, pop: boolean)
	if LandmarkKinds[key] or not MapLayoutService:IsLoaded() then return end

	LandmarkKinds[key] = kind
	for _, layer in Layers do
		layer:PlaceLandmark(kind, key)
	end

	if not pop then return end
	for _, layer in Layers do
		layer:Pop(key)
	end
	if not IsOpen then
		table.insert(PendingPops, key)
	end
end

local function playPending()
	local rooms = PendingRooms
	PendingRooms = {}
	for index, entry in rooms do
		task.delay((index - 1) * 0.18, function()
			MapInkService:RevealAnimated(entry.Key, entry.Packed, MapConfig.Ink.RevealTime)
		end)
	end

	local pops = PendingPops
	PendingPops = {}
	for index, key in pops do
		task.delay((index - 1) * 0.18 + MapConfig.Ink.RevealTime * 0.55, function()
			for _, layer in Layers do
				layer:Pop(key)
			end
		end)
	end
end

function MapService:RefreshComputers()
	if not MapLayoutService:IsLoaded() then return end

	for _, model in CollectionService:GetTagged(ComputerConfig.Tag) do
		if not model:IsA("Model") then continue end

		local pivot = model:GetPivot().Position
		local key = string.format("%d,%d", math.round(pivot.X), math.round(pivot.Z))
		local complete = ComputerService:IsHacked(model)
		for _, layer in Layers do
			layer:SetComplete(key, complete)
		end
	end
end

local function onSync(layout: { any }, store: { [string]: { number } }, landmarks: { [string]: { [string]: boolean } })
	local paper = getPaper()

	MapLayoutService:Load(layout)

	table.clear(LandmarkKinds)
	for _, existing in Layers do
		existing:ClearLandmarks()
	end

	if Layer then
		MapService:UnregisterLayer(Layer)
		Layer:Destroy()
		Layer = nil
	end

	for _, name in { Gui.ViewportName, Gui.LegendName } do
		local existing = paper:FindFirstChild(name)
		if existing then existing:Destroy() end
	end

	local viewport, content = buildViewport(paper)

	MapInkService:Attach(content)

	local marks = MapMarkerLayer.new(content)
	Layer = marks
	MapService:RegisterLayer(marks)

	MapControlService:Attach(viewport, content)
	buildLegend(paper)

	for kind, found in landmarks do
		for key in found do
			placeLandmark(kind, key, false)
		end
	end

	task.spawn(function()
		MapInkService:LoadDiscovered(store)
	end)
end

local function onReveal(key: string, packed: { number })
	if not MapInkService:IsAttached() then return end

	local entry = MapLayoutService:Get(key)
	if entry and entry.Kind == "ComputerRoom" and not MapInkService:IsDrawn(key) then
		if IsOpen then
			MapInkService:RevealAnimated(key, packed, MapConfig.Ink.RevealTime)
		else
			table.insert(PendingRooms, { Key = key, Packed = packed })
		end
		return
	end

	if not MapInkService:Reveal(key, packed) then return end

	if Pending then return end
	Pending = true
	task.defer(function()
		Pending = false
		MapInkService:Flush()
	end)
end

CommunicationService.Get(Remotes.Folder, Remotes.Sync).OnClientEvent:Connect(onSync)
CommunicationService.Get(Remotes.Folder, Remotes.Reveal).OnClientEvent:Connect(onReveal)
CommunicationService.Get(Remotes.Folder, Remotes.Landmark).OnClientEvent:Connect(function(kind: string, key: string)
	placeLandmark(kind, key, true)
end)

xenterface:Controller(Gui.PageGroup).Fired:Connect(function(data)
	local opened = data.ActiveId == Gui.PageId
	if opened == IsOpen then return end

	IsOpen = opened
	if not opened then return end

	MapControlService:Reset(true)
	MapService:RefreshComputers()
	playPending()
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or input.KeyCode ~= MapConfig.Controls.ToggleKey then return end

	local controller = xenterface:Controller(Gui.PageGroup)
	controller:Fire(if controller.Active == Gui.PageId then "" else Gui.PageId)
end)

ComputerService.Changed:Connect(function()
	MapService:RefreshComputers()
end)

RunService.RenderStepped:Connect(function()
	if not MapLayoutService:IsLoaded() then return end

	for _, layer in Layers do
		layer:Update()
	end
end)

return MapService
