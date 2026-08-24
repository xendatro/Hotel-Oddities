local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")

local DangerField = require(ReplicatedStorage.Services.DangerFieldService)
local StatsHUDConfig = require(ReplicatedStorage.Configs.StatsHUDConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)

local StatsHUDService = {}

if not RunService:IsClient() then
	return StatsHUDService
end

local MAZE_FLOOR_TAG = "MazeFloor"
local START_TAG = "Start"

local COLORS = StatsHUDConfig.Colors

local localPlayer = Players.LocalPlayer

local DebugSnapshot = CommunicationService.Get("Enemies", "DebugSnapshot") :: RemoteEvent

local function band(value: number, good: number, fair: number, higherIsBetter: boolean): Color3
	if higherIsBetter then
		if value >= good then return COLORS.Good end
		if value >= fair then return COLORS.Fair end
	else
		if value <= good then return COLORS.Good end
		if value <= fair then return COLORS.Fair end
	end
	return COLORS.Bad
end

type Row = { Value: TextLabel }

local function buildRow(parent: Instance, order: number, caption: string): Row
	local row = Instance.new("Frame")
	row.Name = caption
	row.Size = UDim2.new(1, 0, 0, StatsHUDConfig.RowHeight)
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Parent = parent

	local captionLabel = Instance.new("TextLabel")
	captionLabel.Name = "Caption"
	captionLabel.Size = UDim2.new(0, StatsHUDConfig.CaptionWidth, 1, 0)
	captionLabel.BackgroundTransparency = 1
	captionLabel.Font = Enum.Font.Code
	captionLabel.TextSize = StatsHUDConfig.TextSize
	captionLabel.TextColor3 = COLORS.Caption
	captionLabel.TextXAlignment = Enum.TextXAlignment.Left
	captionLabel.Text = caption
	captionLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Name = "Value"
	valueLabel.Position = UDim2.fromOffset(StatsHUDConfig.CaptionWidth, 0)
	valueLabel.Size = UDim2.new(1, -StatsHUDConfig.CaptionWidth, 1, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Font = Enum.Font.Code
	valueLabel.TextSize = StatsHUDConfig.TextSize
	valueLabel.TextColor3 = COLORS.Unknown
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.Text = "--"
	valueLabel.Parent = row

	return { Value = valueLabel }
end

local screenGui = GuiBuilderService.CreateScreenGui("StatsHud", 1000, true)

local panel = Instance.new("Frame")
panel.Name = "Stats"
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, StatsHUDConfig.EdgeMargin, 1, -StatsHUDConfig.EdgeMargin)
panel.Size = UDim2.fromOffset(StatsHUDConfig.PanelWidth, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = COLORS.Background
panel.BackgroundTransparency = StatsHUDConfig.BackgroundTransparency
panel.BorderSizePixel = 0
panel.Parent = screenGui

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 6)
padding.PaddingRight = UDim.new(0, 6)
padding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local fpsRow = buildRow(panel, 1, "FPS")
local pingRow = buildRow(panel, 2, "PING")
local dangerRow = buildRow(panel, 3, "DANGER")

local EnemyConfig = StatsHUDConfig.Enemies

local enemySection = Instance.new("Frame")
enemySection.Name = "Enemies"
enemySection.LayoutOrder = 4
enemySection.Size = UDim2.new(1, 0, 0, 0)
enemySection.AutomaticSize = Enum.AutomaticSize.Y
enemySection.BackgroundTransparency = 1
enemySection.Parent = panel

local enemyLayout = Instance.new("UIListLayout")
enemyLayout.SortOrder = Enum.SortOrder.LayoutOrder
enemyLayout.Parent = enemySection

local enemyHeading = Instance.new("TextLabel")
enemyHeading.Name = "Heading"
enemyHeading.LayoutOrder = -1
enemyHeading.Size = UDim2.new(1, 0, 0, StatsHUDConfig.RowHeight)
enemyHeading.BackgroundTransparency = 1
enemyHeading.Font = Enum.Font.Code
enemyHeading.TextSize = StatsHUDConfig.TextSize
enemyHeading.TextColor3 = EnemyConfig.HeadingColor
enemyHeading.TextXAlignment = Enum.TextXAlignment.Left
enemyHeading.Text = "ENEMIES 0"
enemyHeading.Parent = enemySection

local stalkerRow = Instance.new("TextLabel")
stalkerRow.Name = "StalkerTarget"
stalkerRow.LayoutOrder = 0
stalkerRow.Size = UDim2.new(1, 0, 0, EnemyConfig.RowHeight)
stalkerRow.BackgroundTransparency = 1
stalkerRow.Font = Enum.Font.Code
stalkerRow.TextSize = EnemyConfig.TextSize
stalkerRow.TextColor3 = COLORS.Fair
stalkerRow.TextXAlignment = Enum.TextXAlignment.Left
stalkerRow.TextTruncate = Enum.TextTruncate.AtEnd
stalkerRow.Visible = false
stalkerRow.Parent = enemySection

local enemyRows: { TextLabel } = {}

local function getEnemyRow(index: number): TextLabel
	local existing = enemyRows[index]
	if existing then return existing end

	local label = Instance.new("TextLabel")
	label.Name = `Enemy{index}`
	label.LayoutOrder = index
	label.Size = UDim2.new(1, 0, 0, EnemyConfig.RowHeight)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.Code
	label.TextSize = EnemyConfig.TextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = enemySection

	enemyRows[index] = label
	return label
end

local function stateColor(id: string, state: string?): Color3
	if state and EnemyConfig.Hunting[state] then return COLORS.Bad end
	if state and EnemyConfig.Watching[state] then return COLORS.Fair end
	if EnemyConfig.AlwaysWarn[id] then return COLORS.Fair end
	return EnemyConfig.IdleColor
end

local Snapshot: { { Id: string, State: string, Position: Vector3 } } = {}
local StalkerTargetName: string? = nil

DebugSnapshot.OnClientEvent:Connect(function(entries: any, stalkerName: any)
	if type(entries) == "table" then Snapshot = entries end
	StalkerTargetName = if type(stalkerName) == "string" then stalkerName else nil
end)

local function collectEnemies(): { { Id: string, State: string, Distance: number } }
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	local entries = {}
	for _, entry in Snapshot do
		table.insert(entries, {
			Id = entry.Id,
			State = entry.State,
			Distance = if root then (entry.Position - root.Position).Magnitude else math.huge,
		})
	end

	table.sort(entries, function(a, b)
		if a.Id ~= b.Id then return a.Id < b.Id end
		return a.Distance < b.Distance
	end)
	return entries
end

local function refreshEnemies()
	local entries = collectEnemies()
	enemyHeading.Text = `ENEMIES {#entries}`

	local name = StalkerTargetName
	stalkerRow.Text = if name then `STALKER > {name}` else ""
	stalkerRow.Visible = name ~= nil

	for index, entry in entries do
		local row = getEnemyRow(index)
		local distance = if entry.Distance < math.huge then tostring(math.floor(entry.Distance)) else "?"
		row.Text = `{entry.Id} {entry.State} {distance}`
		row.TextColor3 = stateColor(entry.Id, entry.State)
		row.Visible = true
	end

	for index = #entries + 1, #enemyRows do
		enemyRows[index].Visible = false
	end
end

local frames, elapsed = 0, 0

RunService.RenderStepped:Connect(function(deltaTime: number)
	frames += 1
	elapsed += deltaTime
	if elapsed < StatsHUDConfig.Fps.SampleWindow then return end

	local fps = frames / elapsed
	frames, elapsed = 0, 0

	fpsRow.Value.Text = string.format("%d", math.floor(fps + 0.5))
	fpsRow.Value.TextColor3 = band(fps, StatsHUDConfig.Fps.Good, StatsHUDConfig.Fps.Fair, true)
end)

local function readPing(): number?
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if not ok or typeof(value) ~= "number" or value <= 0 then
		return nil
	end
	return value
end

local function refreshPing()
	local ping = readPing()
	if ping then
		pingRow.Value.Text = string.format("%d ms", math.floor(ping + 0.5))
		pingRow.Value.TextColor3 = band(ping, StatsHUDConfig.Ping.Good, StatsHUDConfig.Ping.Fair, false)
	else
		pingRow.Value.Text = "--"
		pingRow.Value.TextColor3 = COLORS.Unknown
	end
end

local Settings: DangerField.FieldSettings? = nil

local function getFloors(): { BasePart }
	local floors = {}
	for _, instance in CollectionService:GetTagged(MAZE_FLOOR_TAG) do
		if instance:IsA("BasePart") and instance:IsDescendantOf(workspace) then
			table.insert(floors, instance)
		end
	end
	return floors
end

local function refreshDanger()
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if Settings and root then
		local danger = DangerField.Sample(root.Position, Settings)
		dangerRow.Value.Text = string.format("%d%%", math.floor(danger * 100 + 0.5))
		dangerRow.Value.TextColor3 =
			band(danger, StatsHUDConfig.Danger.Good, StatsHUDConfig.Danger.Fair, false)
	else
		dangerRow.Value.Text = "--"
		dangerRow.Value.TextColor3 = COLORS.Unknown
	end
end

local settleDeadline = os.clock() + StatsHUDConfig.TagWaitTimeout
local settlePrevious, settleCount = -1, 0
local settleDone = false

local function pollSettle()
	if settleDone then return end

	local finished = false
	if os.clock() >= settleDeadline then
		finished = true
	else
		local count = #getFloors()
		if count > 0 and count == settlePrevious then
			settleCount += 1
			if settleCount >= StatsHUDConfig.TagSettlePolls then
				finished = true
			end
		else
			settleCount = 0
		end
		settlePrevious = count
	end

	if not finished then return end
	settleDone = true

	local floors = getFloors()
	if #floors == 0 then
		return
	end

	local extent, centre = DangerField.MeasureExtent(floors)
	local startPart = CollectionService:GetTagged(START_TAG)[1] :: BasePart?
	Settings = DangerField.BuildSettings(if startPart then startPart.Position else centre, extent)
end

local enemyAccumulator = EnemyConfig.Interval
local pingAccumulator = StatsHUDConfig.Ping.Interval
local dangerAccumulator = StatsHUDConfig.Danger.Interval
local settleAccumulator = StatsHUDConfig.TagPollInterval
local pollConnection: RBXScriptConnection

pollConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
	if not screenGui.Parent then
		pollConnection:Disconnect()
		return
	end

	enemyAccumulator += deltaTime
	if enemyAccumulator >= EnemyConfig.Interval then
		enemyAccumulator = 0
		refreshEnemies()
	end

	pingAccumulator += deltaTime
	if pingAccumulator >= StatsHUDConfig.Ping.Interval then
		pingAccumulator = 0
		refreshPing()
	end

	dangerAccumulator += deltaTime
	if dangerAccumulator >= StatsHUDConfig.Danger.Interval then
		dangerAccumulator = 0
		refreshDanger()
	end

	if not settleDone then
		settleAccumulator += deltaTime
		if settleAccumulator >= StatsHUDConfig.TagPollInterval then
			settleAccumulator = 0
			pollSettle()
		end
	end
end)

return StatsHUDService
