local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ComputerService = {}

if not RunService:IsClient() then
	return ComputerService
end

local ComputerConfig = require(ReplicatedStorage.Configs.ComputerConfig)
local Interaction = require(ReplicatedStorage.Services.InteractionService)
local TagService = require(ReplicatedStorage.Services.TagService)

local INPUT = ComputerConfig.Input
local CAMERA = ComputerConfig.Camera
local IDLE = ComputerConfig.IdleScreen
local UI = ComputerConfig.UI

local SESSION_JOB = "ComputerSession"
local REOPEN_COOLDOWN = 0.35
local MINIGAMES_RETRY = 1

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local folder = communication and communication:WaitForChild(ComputerConfig.Remotes.Folder, 30)
local CompleteRemote = folder and folder:WaitForChild(ComputerConfig.Remotes.Complete, 30)
local SyncRemote = folder and folder:WaitForChild(ComputerConfig.Remotes.Sync, 30)

type State = {
	Model: Model,
	Gui: SurfaceGui?,
	Plate: Frame?,
	Label: TextLabel?,
	Block: Frame?,
	Title: string | false | nil,
	Pending: RBXScriptConnection?,
}

type Session = {
	Model: Model,
	Screen: BasePart,
	Camera: Camera,
	SavedCFrame: CFrame,
	SavedType: Enum.CameraType,
	SavedMouseIcon: boolean,
	SavedMouseBehavior: Enum.MouseBehavior,
	SavedCursorEnabled: boolean,
	Tween: Tween?,
	Pinned: CFrame?,
	Closed: boolean,
	Connections: { RBXScriptConnection },
}

local States: { [Model]: State } = {}
local focused: Model? = nil
local session: Session? = nil
local lastClosed = 0

local HackedSet: { [Model]: true } = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: true }

local changed = Instance.new("BindableEvent")
ComputerService.Changed = changed.Event

local minigames: any = nil
local nextMinigamesTry = 0
local minigamesWarned = false

local function getMinigames(): any?
	if minigames then return minigames end

	local now = os.clock()
	if now < nextMinigamesTry then return nil end
	nextMinigamesTry = now + MINIGAMES_RETRY

	local services = ReplicatedStorage:FindFirstChild("Services")
	local module = services and services:FindFirstChild("MinigameService")
	if not module or not module:IsA("ModuleScript") then return nil end

	local ok, result = pcall(require, module)
	if not ok or type(result) ~= "table" then
		if not minigamesWarned then
			minigamesWarned = true
			warn(`ComputerService: MinigameService would not load: {result}`)
		end
		return nil
	end
	minigames = result
	return minigames
end

local function screenOf(model: Model): BasePart?
	local instance: Instance? = model
	for _, name in ComputerConfig.ScreenPath do
		if not instance then return nil end
		instance = instance:FindFirstChild(name)
	end
	if instance and instance:IsA("BasePart") then return instance end
	return nil
end

local function isHacked(model: Model): boolean
	return HackedSet[model] == true
end

local function paintScreen(model: Model)
	local screen = screenOf(model)
	if not screen then return end

	screen.Color = if isHacked(model)
		then ComputerConfig.Colors.ScreenHacked
		else ComputerConfig.Colors.ScreenLocked
end

local function titleFor(state: State): string
	if type(state.Title) == "string" then return state.Title :: string end
	if state.Title == false then return IDLE.FallbackText end

	local framework = getMinigames()
	if not framework then return IDLE.FallbackText end

	local ok, id = pcall(function()
		return framework:ResolvedFor(state.Model)
	end)
	state.Title = if ok and type(id) == "string" then `{id:upper()}.EXE` else false
	return if type(state.Title) == "string" then state.Title :: string else IDLE.FallbackText
end

local function buildIdle(state: State): boolean
	if state.Gui then return true end

	local screen = screenOf(state.Model)
	if not screen then return false end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "ComputerIdle"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = IDLE.PixelsPerStud
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false

	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundColor3 = IDLE.Background
	plate.BackgroundTransparency = IDLE.BackgroundTransparency
	plate.BorderSizePixel = 0
	plate.Parent = gui

	local label = Instance.new("TextLabel")
	label.Name = "Line"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.44)
	label.Size = UDim2.fromScale(0.86, 0.2)
	label.Font = IDLE.Font
	label.TextColor3 = IDLE.Text
	label.TextScaled = true
	label.Text = IDLE.LockedText
	label.Parent = plate

	local block = Instance.new("Frame")
	block.Name = "Block"
	block.AnchorPoint = Vector2.new(0.5, 0.5)
	block.Position = UDim2.fromScale(0.5, 0.66)
	block.Size = UDim2.fromScale(0.07, 0.09)
	block.BackgroundColor3 = IDLE.Text
	block.BorderSizePixel = 0
	block.Parent = plate

	gui.Parent = screen

	state.Gui = gui
	state.Plate = plate
	state.Label = label
	state.Block = block
	return true
end

local function refreshIdle(state: State)
	local label, plate, block = state.Label, state.Plate, state.Block
	if not label or not plate or not block then return end

	if isHacked(state.Model) then
		label.Text = IDLE.HackedText
		label.TextColor3 = IDLE.HackedTextColor
		plate.BackgroundTransparency = IDLE.HackedBackgroundTransparency
		block.Visible = false
	else
		label.TextColor3 = IDLE.Text
		plate.BackgroundTransparency = IDLE.BackgroundTransparency
		block.Visible = true
	end
end

local SCREEN_NAME = ComputerConfig.ScreenPath[#ComputerConfig.ScreenPath]

local function buildIdleWhenReady(state: State)
	if buildIdle(state) then return end

	state.Pending = state.Model.DescendantAdded:Connect(function(instance: Instance)
		if instance.Name ~= SCREEN_NAME then return end
		if not buildIdle(state) then return end

		refreshIdle(state)
		paintScreen(state.Model)

		local pending = state.Pending
		state.Pending = nil
		if pending then
			pending:Disconnect()
		end
	end)
end

local restore: () -> ()

local function register(model: Model): State?
	if not model:IsA("Model") then return nil end

	local state: State = {
		Model = model,
		Gui = nil,
		Plate = nil,
		Label = nil,
		Block = nil,
		Title = nil,
		Pending = nil,
	}

	buildIdleWhenReady(state)
	refreshIdle(state)
	paintScreen(model)

	States[model] = state
	Interaction:Register(model, {
		Prompt = UI.HackText,
		TextWidth = UI.TextWidth,
		Reach = ComputerConfig.Targeting.Reach,
		CanSelect = function(target: Model)
			return not session and not isHacked(target)
		end,
		OnActivated = function(target: Model)
			return ComputerService:Activate(target)
		end,
	})
	return state
end

local function unregister(model: Model, state: State?)
	States[model] = nil
	Interaction:Unregister(model)
	if not state then return end

	if state.Pending then
		state.Pending:Disconnect()
		state.Pending = nil
	end
	if state.Gui then
		state.Gui:Destroy()
	end
	if session and session.Model == model then
		restore()
	end
end

local function applyState()
	for model, state in States do
		refreshIdle(state)
		paintScreen(model)
	end

	if focused and isHacked(focused) then
		focused = nil
	end

	changed:Fire()
end

local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then return end

	local list = snapshot :: { any }

	table.clear(HackedSet)
	for _, model in list do
		if typeof(model) == "Instance" and model:IsA("Model") then
			HackedSet[model] = true
		end
	end

	applyState()
end

local function markHacked(model: Model)
	if HackedSet[model] then return end
	HackedSet[model] = true
	applyState()
end

if SyncRemote then
	(SyncRemote :: RemoteEvent).OnClientEvent:Connect(applySnapshot)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local showTitle = (now % (IDLE.CycleTime * 2)) >= IDLE.CycleTime
	local blink = (now % IDLE.BlinkTime) < IDLE.BlinkTime * 0.5

	for model, state in States do
		local label, block = state.Label, state.Block
		if not label or not block or isHacked(model) then continue end

		local text = if showTitle then titleFor(state) else IDLE.LockedText
		if label.Text ~= text then
			label.Text = text
		end
		block.BackgroundTransparency = if blink then 0 else 1
	end
end)

local cursor = playerGui:WaitForChild("Cursor", 30) :: ScreenGui?

local function controls(): any?
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end

	local ok, result = pcall(function()
		return require(module :: ModuleScript):GetControls()
	end)
	return if ok then result else nil
end

local function setControlsEnabled(enabled: boolean)
	local controlModule = controls()
	if not controlModule then return end
	pcall(function()
		if enabled then
			controlModule:Enable()
		else
			controlModule:Disable()
		end
	end)
end

local function cameraDistance(screen: BasePart, camera: Camera): number
	local size = screen.Size

	local tanVertical = math.tan(math.rad(camera.FieldOfView) / 2)
	if tanVertical <= 0 then return CAMERA.MinDistance end

	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 1
	local tanHorizontal = tanVertical * aspect

	local fill = CAMERA.FillFraction
	local byHeight = (size.Y / 2) / tanVertical / fill
	local byWidth = (size.X / 2) / tanHorizontal / fill

	return math.max(math.max(byHeight, byWidth) + size.Z, CAMERA.MinDistance)
end

local function renderSession()
	local current = session
	if not current then return end

	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	if current.Pinned then
		current.Camera.CFrame = current.Pinned
	end
end

local function onExitAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
	restore()
	return Enum.ContextActionResult.Sink
end

function restore()
	local current = session
	if not current or current.Closed then return end
	current.Closed = true
	session = nil
	lastClosed = os.clock()

	for _, connection in current.Connections do
		connection:Disconnect()
	end

	if minigames then
		pcall(function()
			minigames:Close()
		end)
	end

	if current.Tween then
		current.Tween:Cancel()
	end

	RunService:UnbindFromRenderStep(SESSION_JOB)
	ContextActionService:UnbindAction(INPUT.ExitAction)

	local camera = current.Camera
	if camera.Parent then
		camera.CFrame = current.SavedCFrame
		camera.CameraType = current.SavedType
	end

	UserInputService.MouseIconEnabled = current.SavedMouseIcon
	UserInputService.MouseBehavior = current.SavedMouseBehavior
	if cursor and UI.HideCursorInSession then
		cursor.Enabled = current.SavedCursorEnabled
	end

	setControlsEnabled(true)

	local state = States[current.Model]
	if state and state.Gui then
		state.Gui.Enabled = true
	end
end

local function onWin(model: Model)
	markHacked(model)
	if CompleteRemote then
		(CompleteRemote :: RemoteEvent):FireServer(model)
	end
	restore()
end

function ComputerService:IsHacked(model: Model): boolean
	return isHacked(model)
end

function ComputerService:GetFocused(): Model?
	return focused
end

function ComputerService:IsSessionOpen(): boolean
	return session ~= nil
end

function ComputerService:Activate(model: Model?): boolean
	local target = model or focused
	if not target or session or not States[target] then return false end
	if isHacked(target) or os.clock() - lastClosed < REOPEN_COOLDOWN then return false end

	local screen = screenOf(target)
	if not screen then
		warn(`ComputerService: {target:GetFullName()} has no screen part to play on`)
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then return false end

	local framework = getMinigames()
	if not framework then return false end

	local current: Session = {
		Model = target,
		Screen = screen,
		Camera = camera,
		SavedCFrame = camera.CFrame,
		SavedType = camera.CameraType,
		SavedMouseIcon = UserInputService.MouseIconEnabled,
		SavedMouseBehavior = UserInputService.MouseBehavior,
		SavedCursorEnabled = if cursor then cursor.Enabled else false,
		Tween = nil,
		Pinned = nil,
		Closed = false,
		Connections = {},
	}
	session = current
	focused = nil

	local distance = cameraDistance(screen, camera)
	local target = CFrame.lookAt(screen.Position + screen.CFrame.LookVector * distance, screen.Position)

	camera.CameraType = Enum.CameraType.Scriptable
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(CAMERA.TweenTime, CAMERA.EasingStyle, CAMERA.EasingDirection),
		{ CFrame = target }
	)
	current.Tween = tween
	table.insert(current.Connections, tween.Completed:Connect(function()
		if session == current then
			current.Pinned = target
		end
	end))
	tween:Play()

	setControlsEnabled(false)
	RunService:BindToRenderStep(SESSION_JOB, Enum.RenderPriority.Camera.Value + 4, renderSession)
	ContextActionService:BindAction(INPUT.ExitAction, onExitAction, false, table.unpack(INPUT.ExitKeys))

	if cursor and UI.HideCursorInSession then
		cursor.Enabled = false
	end
	local state = States[target]
	if state and state.Gui then
		state.Gui.Enabled = false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(current.Connections, humanoid.Died:Connect(restore))
	end
	table.insert(current.Connections, player.CharacterRemoving:Connect(restore))
	table.insert(current.Connections, target.AncestryChanged:Connect(function()
		if not target:IsDescendantOf(workspace) then
			restore()
		end
	end))

	local ok, err = pcall(function()
		framework:Open(target, screen, {
			OnExit = restore,
			OnComplete = function()
				onWin(target)
			end,
		})
	end)
	if not ok then
		warn(`ComputerService: the minigame would not open: {err}`)
		restore()
		return false
	end

	return true
end

Interaction.Selected:Connect(function(model: Model?)
	focused = if model and States[model] then model else nil
end)

TagService:Listen(ComputerConfig.Tag, register, unregister, workspace)

return ComputerService
