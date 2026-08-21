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
local TagService = require(ReplicatedStorage.Services.TagService)

local TARGETING = ComputerConfig.Targeting
local HIGHLIGHT = ComputerConfig.Highlight
local INPUT = ComputerConfig.Input
local CAMERA = ComputerConfig.Camera
local IDLE = ComputerConfig.IdleScreen
local UI = ComputerConfig.UI
local COLORS = UI.Colors

local FOCUS_JOB = "ComputerFocus"
local PROMPT_JOB = "ComputerPrompt"
local SESSION_JOB = "ComputerSession"
local HIGHLIGHT_FADE_SPEED = 16
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
local highlightAlpha = 0
local session: Session? = nil
local lastClosed = 0

local HackedSet: { [Model]: true } = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: true }

local changed = Instance.new("BindableEvent")
ComputerService.Changed = changed.Event

local highlight = Instance.new("Highlight")
highlight.Name = "ComputerHighlight"
highlight.FillColor = HIGHLIGHT.FillColor
highlight.OutlineColor = HIGHLIGHT.OutlineColor
highlight.DepthMode = HIGHLIGHT.DepthMode
highlight.FillTransparency = 1
highlight.OutlineTransparency = 1
highlight.Enabled = false
highlight.Adornee = nil
highlight.Parent = workspace

local function resetHighlight()
	focused = nil
	highlightAlpha = 0
	highlight.Enabled = false
	highlight.Adornee = nil
	if highlight.Parent ~= workspace then
		highlight.Parent = workspace
	end
end

local function ensureHighlight()
	if highlight.Parent ~= workspace then
		highlight.Parent = workspace
	end
	if highlight.Adornee and not highlight.Adornee:IsDescendantOf(workspace) then
		highlight.Adornee = nil
		focused = nil
		highlightAlpha = 0
	end
end

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
	return state
end

local function unregister(model: Model, state: State?)
	States[model] = nil
	if not state then return end

	if state.Pending then
		state.Pending:Disconnect()
		state.Pending = nil
	end
	if state.Gui then
		state.Gui:Destroy()
	end
	if focused == model then
		focused = nil
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

local function computerOf(part: BasePart): Model?
	local instance: Instance? = part
	while instance and instance ~= workspace do
		if instance:IsA("Model") and States[instance] then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

local function alive(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then character else nil
end

local function findFocus(): Model?
	local camera = workspace.CurrentCamera
	local character = alive()
	if not camera or not character then return nil end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored: { Instance } = { character }
	params.FilterDescendantsInstances = ignored

	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector * TARGETING.Reach

	for _ = 1, TARGETING.MaxPassthrough + 1 do
		local result = workspace:Raycast(origin, direction, params)
		if not result then return nil end

		local model = computerOf(result.Instance)
		if model then
			return if isHacked(model) then nil else model
		end

		if result.Instance.CanCollide or result.Instance.Transparency < 1 then return nil end

		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end

	return nil
end

local function renderFocus(deltaTime: number)
	ensureHighlight()
	focused = if session then nil else findFocus()

	if focused then
		highlight.Adornee = focused
		highlight.Enabled = true
	end

	local target = if focused then 1 else 0
	highlightAlpha += (target - highlightAlpha) * (1 - math.exp(-HIGHLIGHT_FADE_SPEED * deltaTime))
	if math.abs(target - highlightAlpha) < 1e-3 then highlightAlpha = target end

	if highlightAlpha <= 0 then
		if highlight.Enabled then
			highlight.Enabled = false
			highlight.Adornee = nil
		end
		return
	end

	highlight.FillTransparency = 1 - (1 - HIGHLIGHT.FillTransparency) * highlightAlpha
	highlight.OutlineTransparency = 1 - (1 - HIGHLIGHT.OutlineTransparency) * highlightAlpha
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
local template = cursor and cursor:WaitForChild(UI.Container, 30)
local container: CanvasGroup? = nil

if template then
	local clone = template:Clone() :: CanvasGroup
	clone.Name = UI.Prompt
	clone.Visible = false
	clone.GroupTransparency = 1
	clone.Parent = cursor
	container = clone
else
	warn(`ComputerService: no {UI.Container} under the Cursor gui; the hack prompt will not draw`)
end

local promptScale: UIScale? = nil
local promptPill: Frame? = nil
local promptKey: Frame? = nil
local promptKeyScale: UIScale? = nil
local promptKeyLabel: TextLabel? = nil
local promptAction: TextLabel? = nil

if container then
	promptScale = container:FindFirstChild("Scale") :: UIScale
	promptPill = container:FindFirstChild("Pill") :: Frame
	promptKey = promptPill and promptPill:FindFirstChild("Key") :: Frame
	promptKeyScale = promptKey and promptKey:FindFirstChild("Scale") :: UIScale
	promptKeyLabel = promptKey and promptKey:FindFirstChild("Label") :: TextLabel
	promptAction = promptPill and promptPill:FindFirstChild("Action") :: TextLabel

	if not (promptScale and promptPill and promptKey and promptKeyScale and promptKeyLabel and promptAction) then
		warn(`ComputerService: the {UI.Container} prompt is not shaped as expected; the hack prompt will not draw`)
		container:Destroy()
		container = nil
	end
end

local function layout(keyWidth: number)
	if not (container and promptPill and promptKey and promptAction) then return end

	local left = UI.PillPaddingLeft + keyWidth + UI.KeyGap
	local width = left + UI.TextWidth + UI.PillPaddingRight

	container.Size = UDim2.fromOffset(width + UI.Padding * 2, UI.PillHeight + UI.Padding * 2)
	promptPill.Size = UDim2.fromOffset(width, UI.PillHeight)
	promptKey.Size = UDim2.fromOffset(keyWidth, UI.KeySize)
	promptAction.Position = UDim2.new(0, left, 0.5, 0)
	promptAction.Size = UDim2.fromOffset(UI.TextWidth, UI.KeySize)
end

local pressFlash = 0
local touching = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local usingGamepad = UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled
local bound = false

local function onHackAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin and ComputerService:Activate() then
		pressFlash = 1
	end
	return Enum.ContextActionResult.Pass
end

local function setBound(shouldBind: boolean)
	if shouldBind == bound then return end
	bound = shouldBind

	if not shouldBind then
		ContextActionService:UnbindAction(INPUT.TouchAction)
		return
	end

	ContextActionService:BindAction(INPUT.TouchAction, onHackAction, touching, table.unpack(INPUT.Keys))
	if not touching then return end

	ContextActionService:SetTitle(INPUT.TouchAction, UI.HackText:upper())
	ContextActionService:SetPosition(INPUT.TouchAction, INPUT.TouchButtonPosition)
	local button = ContextActionService:GetButton(INPUT.TouchAction)
	if button then
		button.Size = INPUT.TouchButtonSize
	end
end

UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
	if inputType == Enum.UserInputType.Touch then
		touching = true
	elseif inputType.Name:find("Gamepad") then
		touching = false
		usingGamepad = true
	elseif inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseMovement
	then
		touching = false
		usingGamepad = false
	end
end)

local promptAlpha = 0
local shownGamepad: boolean? = nil

local function renderPrompt(deltaTime: number)
	setBound(focused ~= nil)
	if not (container and promptScale and promptKey and promptKeyScale and promptKeyLabel and promptAction) then
		return
	end

	local target = if focused and not touching then 1 else 0
	if promptAlpha < target then
		promptAlpha = math.min(promptAlpha + deltaTime / UI.FadeInTime, target)
	elseif promptAlpha > target then
		promptAlpha = math.max(promptAlpha - deltaTime / UI.FadeOutTime, target)
	end

	pressFlash *= math.exp(-UI.PressDecay * deltaTime)
	if pressFlash < 1e-3 then pressFlash = 0 end

	container.Visible = promptAlpha > 0
	if promptAlpha <= 0 then return end

	if promptAction.Text ~= UI.HackText then
		promptAction.Text = UI.HackText
	end
	if usingGamepad ~= shownGamepad then
		shownGamepad = usingGamepad
		local text = if usingGamepad then INPUT.GamepadLabel else INPUT.KeyboardLabel
		promptKeyLabel.Text = text
		layout(if #text <= 1 then UI.KeySize else UI.KeyWideSize)
	end

	container.GroupTransparency = 1 - promptAlpha
	container.Position = UDim2.new(0.5, 0, 0.5, UI.TopMargin + math.round((1 - promptAlpha) * UI.Rise))
	promptScale.Scale = UI.EnterScale + (1 - UI.EnterScale) * promptAlpha

	promptKeyScale.Scale = 1 - UI.PressScale * pressFlash
	promptKey.BackgroundColor3 = COLORS.Key:Lerp(COLORS.KeyPressed, pressFlash)
end

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

function ComputerService:Activate(): boolean
	local model = focused
	if not model or session or not States[model] then return false end
	if isHacked(model) or os.clock() - lastClosed < REOPEN_COOLDOWN then return false end

	local screen = screenOf(model)
	if not screen then
		warn(`ComputerService: {model:GetFullName()} has no screen part to play on`)
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then return false end

	local framework = getMinigames()
	if not framework then return false end

	local current: Session = {
		Model = model,
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
	local state = States[model]
	if state and state.Gui then
		state.Gui.Enabled = false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		table.insert(current.Connections, humanoid.Died:Connect(restore))
	end
	table.insert(current.Connections, player.CharacterRemoving:Connect(restore))
	table.insert(current.Connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			restore()
		end
	end))

	local ok, err = pcall(function()
		framework:Open(model, screen, {
			OnExit = restore,
			OnComplete = function()
				onWin(model)
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

layout(UI.KeySize)

RunService:BindToRenderStep(FOCUS_JOB, Enum.RenderPriority.Camera.Value + 3, renderFocus)
RunService:BindToRenderStep(PROMPT_JOB, Enum.RenderPriority.Last.Value, renderPrompt)

player.CharacterRemoving:Connect(resetHighlight)
player.CharacterAdded:Connect(resetHighlight)

TagService:Listen(ComputerConfig.Tag, register, unregister, workspace)

return ComputerService
