local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Configs.WalkieTalkieConfig)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local SurfaceCursorService = require(ReplicatedStorage.Services.SurfaceCursorService)
local ViewmodelService = require(ReplicatedStorage.Services.ViewmodelService)
local WalkieTalkieService = require(ReplicatedStorage.Services.WalkieTalkieService)

local WalkieUIService = {}

if not RunService:IsClient() then
	return WalkieUIService
end

local UI = Config.Ui
local COLORS = UI.Colors
local STATUS = UI.Status
local BIND_NAME = "WalkieScreen"

local player = Players.LocalPlayer
local playerGui = GuiBuilderService.GetPlayerGui()

type Screen = {
	Gui: SurfaceGui,
	Part: BasePart,
	Header: Frame,
	Roster: Frame,
	List: ScrollingFrame,
	RowTemplate: Frame,
	Settings: Frame,
	SettingList: Frame,
	SettingTemplate: Frame,
	Footer: Frame,
	Off: Frame,
}

type Slider = { Element: GuiObject, Apply: (alpha: number) -> () }

local gameCursor = playerGui:FindFirstChild("Cursor") :: ScreenGui?
local screen: Screen? = nil
local rows: { [Player]: Frame } = {}
local settingRows: { [string]: Frame } = {}
local settingsOpen = false
local dragging = false
local dragPoint: Vector2? = nil
local activeSlider: Slider? = nil
local mouseUnlocked = false
local wasRaised = false

local function findScreenPart(root: Instance): BasePart?
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:FindFirstChildOfClass("SurfaceGui") then
			return descendant
		end
	end
	return nil
end

local function readScreen(part: BasePart): Screen?
	local gui = part:FindFirstChildOfClass("SurfaceGui")
	local main = gui and gui:FindFirstChild("Main")
	local body = main and main:FindFirstChild("Body")
	local roster = body and body:FindFirstChild("Roster")
	local settings = body and body:FindFirstChild("Settings")
	if not roster or not settings then return nil end

	return {
		Gui = gui :: SurfaceGui,
		Part = part,
		Header = body:FindFirstChild("Header") :: Frame,
		Roster = roster :: Frame,
		List = roster:FindFirstChild("List") :: ScrollingFrame,
		RowTemplate = roster:FindFirstChild("List").Row :: Frame,
		Settings = settings :: Frame,
		SettingList = settings:FindFirstChild("List") :: Frame,
		SettingTemplate = settings:FindFirstChild("List").SettingRow :: Frame,
		Footer = body:FindFirstChild("Footer") :: Frame,
		Off = body:FindFirstChild("Off") :: Frame,
	}
end

local function clearRows()
	for _, row in rows do
		if row.Parent then row:Destroy() end
	end
	table.clear(rows)
end

local function buildSettingRows(current: Screen)
	table.clear(settingRows)
	for _, child in current.SettingList:GetChildren() do
		if child:IsA("Frame") and child ~= current.SettingTemplate then child:Destroy() end
	end
	for index, entry in Config.Categories do
		local row = current.SettingTemplate:Clone()
		row.Name = entry.Id
		row.LayoutOrder = index
		row.Visible = true
		row.Title.Text = entry.Label
		row.Parent = current.SettingList
		settingRows[entry.Id] = row
	end
end

local lastRig: Model? = nil
local lastTool: Tool? = nil

local function rebind()
	local rig = ViewmodelService:GetRig()
	local tool = WalkieTalkieService:GetTool()
	local current = screen
	if current and current.Part.Parent and rig == lastRig and tool == lastTool then return end

	lastRig = rig
	lastTool = tool
	local part = (rig and findScreenPart(rig)) or (tool and findScreenPart(tool))
	if current and current.Part == part and current.Part.Parent then return end

	clearRows()
	table.clear(settingRows)
	activeSlider = nil
	screen = nil
	if not part then return end

	local built = readScreen(part)
	if not built then return end
	for _, child in built.List:GetChildren() do
		if child:IsA("Frame") and child ~= built.RowTemplate then child:Destroy() end
	end
	buildSettingRows(built)
	screen = built
end

local function acquireRow(current: Screen, target: Player): Frame
	local row = rows[target]
	if row and row.Parent then return row end
	row = current.RowTemplate:Clone()
	row.Name = tostring(target.UserId)
	row.Visible = true
	row.Parent = current.List
	rows[target] = row
	return row
end

local function updateRow(row: Frame, entry: any, raised: boolean)
	local target = entry.Player
	local isSelf = target == player
	local color = COLORS[entry.Category]
	local muted = not isSelf and WalkieTalkieService:IsMuted(target)
	local tint = if muted then COLORS.Muted else color

	row.Dot.BackgroundColor3 = tint
	row.PlayerName.Text = target.DisplayName
	row.PlayerName.TextColor3 = tint
	row.Status.Text = if isSelf
		then STATUS.Self
		elseif muted then STATUS.Muted
		else STATUS[entry.Category]
	row.Status.TextColor3 = COLORS.Dim

	local showControls = raised and not isSelf
	row.Controls.Visible = showControls
	row.Meter.Visible = not showControls and entry.Category == "Enabled"
	if row.Meter.Visible then
		row.Meter.Fill.Size = UDim2.fromScale(entry.Level, 1)
		row.Meter.Fill.BackgroundColor3 = color
	end
	if not showControls then return end

	local volume = WalkieTalkieService:GetPlayerVolume(target)
	row.Controls.Mute.Text = if muted then "X" else "M"
	row.Controls.Mute.TextColor3 = tint
	row.Controls.Volume.Fill.Size = UDim2.fromScale(volume, 1)
	row.Controls.Volume.Fill.BackgroundColor3 = tint
	row.Controls.Volume.Knob.Position = UDim2.fromScale(volume, 0.5)
	row.Controls.Volume.Knob.BackgroundColor3 = tint
end

local function refreshRoster(current: Screen, raised: boolean)
	local roster = WalkieTalkieService:GetRoster()
	local seen: { [Player]: boolean } = {}
	for index, entry in roster do
		seen[entry.Player] = true
		local row = acquireRow(current, entry.Player)
		row.LayoutOrder = index
		updateRow(row, entry, raised)
	end
	for target, row in rows do
		if seen[target] then continue end
		row:Destroy()
		rows[target] = nil
	end
	current.Roster.Empty.Visible = #roster == 0
end

local function refreshSettings()
	for id, row in settingRows do
		local value = WalkieTalkieService:GetCategory(id)
		row.Value.Text = `{math.round(value * 100)}%`
		row.Slider.Fill.Size = UDim2.fromScale(value, 1)
		row.Slider.Knob.Position = UDim2.fromScale(value, 0.5)
	end
end

local function refreshChrome(current: Screen, powered: boolean, raised: boolean)
	local header = current.Header
	header.Title.Text = if settingsOpen then "AUDIO" else "ROSTER"
	header.Mode.Text = WalkieTalkieService:GetModeLabel()
	header.Settings.Text = if settingsOpen then "BACK" else "SET"
	header.Settings.TextColor3 = if settingsOpen then COLORS.Enabled else COLORS.Dim
	header.Power.BackgroundColor3 = if powered then COLORS.Enabled else COLORS.NoVoice

	current.Roster.Visible = not settingsOpen
	current.Settings.Visible = settingsOpen

	local transmitting = WalkieTalkieService:IsTransmitting()
	current.Footer.Signal.TextColor3 = if transmitting then COLORS.NoVoice else COLORS.Idle
	current.Footer.Hint.Text = if raised
		then string.format(UI.Hints.Raised, Config.Keys.Raise.Name)
		elseif transmitting then UI.Hints.Talking
		else UI.Hints.Talk

	current.Off.Visible = not powered
	current.Off.Prompt.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then UI.OffPromptTouch
		else string.format(UI.OffPrompt, Config.Keys.Power.Name)
end

local function maxScroll(list: ScrollingFrame): number
	return math.max(list.AbsoluteCanvasSize.Y - list.AbsoluteWindowSize.Y, 0)
end

local function scroll(delta: number)
	local current = screen
	if not current then return end
	local list = current.List
	list.CanvasPosition = Vector2.new(0, math.clamp(list.CanvasPosition.Y + delta, 0, maxScroll(list)))
end

local function refreshScrollbar(current: Screen)
	local list = current.List
	local limit = maxScroll(list)
	local bar = current.Roster.Scrollbar
	bar.Visible = limit > 1
	if not bar.Visible then return end
	local fraction = math.clamp(list.AbsoluteWindowSize.Y / math.max(list.AbsoluteCanvasSize.Y, 1), 0.12, 1)
	bar.Thumb.Size = UDim2.fromScale(1, fraction)
	bar.Thumb.Position = UDim2.fromScale(0, (1 - fraction) * (list.CanvasPosition.Y / limit))
end

local function project(viewportPoint: Vector2): Vector2?
	local current = screen
	if not current then return nil end
	return SurfaceCursorService:Project(
		current.Part,
		current.Gui.Face,
		viewportPoint,
		current.Gui.AbsoluteSize
	)
end

local function viewportPointOf(input: InputObject): Vector2
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
	end
	return UserInputService:GetMouseLocation()
end

local function hits(element: GuiObject, point: Vector2): boolean
	return SurfaceCursorService:Contains(element, point, UI.HitPadding)
end

local function press(point: Vector2): boolean
	local current = screen
	if not current then return false end
	local header = current.Header

	if hits(header.Mode, point) then
		WalkieTalkieService:CycleMode()
		return true
	end
	if hits(header.Settings, point) then
		settingsOpen = not settingsOpen
		return true
	end

	if settingsOpen then
		for id, row in settingRows do
			if not hits(row, point) then continue end
			local slider = { Element = row.Slider, Apply = function(alpha: number)
				WalkieTalkieService:SetCategory(id, alpha)
			end }
			slider.Apply(SurfaceCursorService:GetAlpha(slider.Element, point))
			activeSlider = slider
			return true
		end
		return false
	end

	for target, row in rows do
		if not row.Controls.Visible or not hits(row, point) then continue end
		if hits(row.Controls.Mute, point) then
			WalkieTalkieService:SetMuted(target, not WalkieTalkieService:IsMuted(target))
			return true
		end
		local slider = { Element = row.Controls.Volume, Apply = function(alpha: number)
			WalkieTalkieService:SetPlayerVolume(target, alpha)
		end }
		slider.Apply(SurfaceCursorService:GetAlpha(slider.Element, point))
		activeSlider = slider
		return true
	end
	return false
end

local function setMouseUnlocked(unlocked: boolean)
	if mouseUnlocked == unlocked then return end
	mouseUnlocked = unlocked
	InterfaceService:SetMouseUnlocked(unlocked, unlocked)
	if gameCursor and gameCursor.Parent then gameCursor.Enabled = not unlocked end
end

local function isUsable(): boolean
	return WalkieTalkieService:IsPowered() and WalkieTalkieService:IsEquipped()
end

local function step()
	rebind()

	local powered = WalkieTalkieService:IsPowered()
	local raised = WalkieTalkieService:IsRaised()
	setMouseUnlocked(raised)
	if wasRaised and not raised then settingsOpen = false end
	wasRaised = raised
	if not raised then
		activeSlider = nil
		dragging = false
	end
	if not powered then settingsOpen = false end

	local current = screen
	if not current then return end

	refreshChrome(current, powered, raised)
	if not powered then
		clearRows()
		return
	end

	if settingsOpen then
		refreshSettings()
	else
		refreshRoster(current, raised)
		refreshScrollbar(current)
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject)
	if not isUsable() then return end
	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseButton1
	then
		return
	end

	local point = project(viewportPointOf(input))
	if not point then return end
	if WalkieTalkieService:IsRaised() and press(point) then return end
	dragging = true
	dragPoint = point
end)

UserInputService.InputChanged:Connect(function(input: InputObject)
	if not isUsable() then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local current = screen
		if settingsOpen or not current then return end
		scroll(-input.Position.Z * current.List.AbsoluteWindowSize.Y * UI.ScrollSpeed * 0.25)
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseMovement
	then
		return
	end
	if not dragging and not activeSlider then return end

	local point = project(viewportPointOf(input))
	if not point then return end

	local slider = activeSlider
	if slider then
		if slider.Element.Parent then
			slider.Apply(SurfaceCursorService:GetAlpha(slider.Element, point))
		else
			activeSlider = nil
		end
		return
	end

	if not dragging or not dragPoint then return end
	scroll((dragPoint.Y - point.Y) * UI.DragSpeed)
	dragPoint = point
end)

UserInputService.InputEnded:Connect(function(input: InputObject)
	if input.UserInputType ~= Enum.UserInputType.Touch
		and input.UserInputType ~= Enum.UserInputType.MouseButton1
	then
		return
	end
	activeSlider = nil
	dragging = false
	dragPoint = nil
end)

RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.Last.Value, step)

return WalkieUIService
