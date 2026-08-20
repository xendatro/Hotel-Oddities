--- The computers the player can break into. Every `HackComputer`-tagged model is registered here,
--- the one the cursor is resting on is worked out each frame exactly as the drawers do it, and
--- pressing the key hands the screen over to the minigame framework.
---
--- Hacking is PER PLAYER, so everything about a computer's state is local to this client: the set of
--- models THIS player has broken into is held here, the server sends it as a whole snapshot down the
--- `Sync` remote whenever it changes, and it is this file that paints the Neon screen part blue or
--- green. Two players at the same monitor genuinely see different colours, and one of them finishing
--- changes nothing on the other's screen, prompt or counter.
---
--- A win is marked here the instant the minigame reports it, before the server has answered, so the
--- screen turns green under the player's hand rather than a round trip later. The next snapshot
--- reconciles it either way -- if the server refused the claim the colour goes back.
---
--- A computer this player has already hacked is inert: it is skipped by the raycast entirely, so it
--- stops offering a prompt the moment the win lands rather than when the player next looks away.
---
--- What the rest of the client may call:
---   ComputerService:IsHacked(model): boolean
---   ComputerService.Changed: RBXScriptSignal   -- the local set changed; the HUD counts off this
---   ComputerService:GetFocused(): Model?
---   ComputerService:IsSessionOpen(): boolean
---   ComputerService:Activate(): boolean
---
--- A session is a small, reversible takeover of the client: the camera goes scriptable and rides out
--- to face the screen, the character's controls are switched off, and the mouse is handed back so it
--- can point at a gui. Every one of those is undone by a single `restore`, which is written to be
--- safe to call twice -- the EXIT button, the Q key, winning, dying and the model being destroyed
--- all end up there and none of them can be relied on to arrive alone.
---
--- The minigame framework (`MinigameService`) is required lazily and inside a pcall. It is a sibling
--- service written on its own schedule, and both of them are booted by the same loop over
--- ReplicatedStorage.Services in no particular order; this one has to register computers and draw
--- their screens whether or not the other has loaded yet.

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
--- Seconds after a session ends before the same computer can start another one. Stops a held key
--- from re-entering the moment the exit finishes.
local REOPEN_COOLDOWN = 0.35
--- Seconds between attempts to find the minigame framework while it is not there.
local MINIGAMES_RETRY = 1

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Waited for with a timeout rather than indefinitely, exactly as the drawers do it: a place file
-- without the server service should cost this client its hacking, not its whole boot. Everything
-- below treats "no snapshot yet" as "nothing hacked", so the service is usable before either of
-- these arrives and simply corrects itself when the first snapshot lands.
local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local folder = communication and communication:WaitForChild(ComputerConfig.Remotes.Folder, 30)
local CompleteRemote = folder and folder:WaitForChild(ComputerConfig.Remotes.Complete, 30)
local SyncRemote = folder and folder:WaitForChild(ComputerConfig.Remotes.Sync, 30)

type State = {
	Model: Model,
	--- The idle display on the screen. Absent while the screen part itself is.
	Gui: SurfaceGui?,
	Plate: Frame?,
	Label: TextLabel?,
	Block: Frame?,
	--- The assigned game's title, once the framework has been asked for it. False means "asked, and
	--- the framework was not there", so it is not asked again every cycle.
	Title: string | false | nil,
	--- Held only while the screen part has not arrived yet; see `buildIdleWhenReady`.
	Pending: RBXScriptConnection?,
}

type Session = {
	Model: Model,
	Screen: BasePart,
	Camera: Camera,
	--- Everything the takeover overwrote, put back in `restore`.
	SavedCFrame: CFrame,
	SavedType: Enum.CameraType,
	SavedMouseIcon: boolean,
	SavedMouseBehavior: Enum.MouseBehavior,
	SavedCursorEnabled: boolean,
	Tween: Tween?,
	--- Set once the ride out has landed, and held there for the rest of the session so nothing else
	--- can nudge the camera off the screen.
	Pinned: CFrame?,
	Closed: boolean,
	Connections: { RBXScriptConnection },
}

local States: { [Model]: State } = {}
local focused: Model? = nil
local highlightAlpha = 0
local session: Session? = nil
local lastClosed = 0

--- The computers THIS player has broken into. The server's snapshots are the source of truth; a win
--- writes into it optimistically and the next snapshot agrees or takes it back. Models are held
--- weakly so a torn-down maze does not stay pinned by a set nobody will look at again.
local HackedSet: { [Model]: true } = (setmetatable({}, { __mode = "k" }) :: any) :: { [Model]: true }

--- Fired after any change to that set, with no arguments -- the HUD recounts rather than being told
--- what moved, which is the same thing for five computers and cannot go stale.
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

--- The minigame framework -----------------------------------------------------------------------

local minigames: any = nil
local nextMinigamesTry = 0
local minigamesWarned = false

--- The framework, or nil while it does not exist. Required on demand rather than at the top of the
--- file: MinigameService is a sibling service written on its own schedule, and a missing or broken
--- one must cost this service a prompt that does nothing, not its whole registration pass.
---
--- Retried on a timer rather than latched off after one miss, because "not there" and "not there
--- YET" look identical from here -- a module still replicating would otherwise disable hacking for
--- the whole session.
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

--- Registration ---------------------------------------------------------------------------------

--- The glowing face of `model`, or nil while the models are still being fitted with one.
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

--- Colours the Neon face for what THIS player has done to this computer.
---
--- Written locally on every client rather than once on the server, because there is no one answer:
--- the same monitor is green for the player who cracked it and blue for the player beside them. A
--- Color3 written on the client never replicates, so nobody else's screen moves.
local function paintScreen(model: Model)
	local screen = screenOf(model)
	if not screen then return end

	screen.Color = if isHacked(model)
		then ComputerConfig.Colors.ScreenHacked
		else ComputerConfig.Colors.ScreenLocked
end

--- The second line the idle screen alternates onto: what the framework has decided this computer
--- runs. Asked for once and remembered, since the answer cannot change while the maze stands.
local function titleFor(state: State): string
	if type(state.Title) == "string" then return state.Title :: string end
	-- False means the framework was there and had no answer; that will not change, so stop asking.
	if state.Title == false then return IDLE.FallbackText end

	local framework = getMinigames()
	if not framework then return IDLE.FallbackText end

	local ok, id = pcall(function()
		-- Resolved rather than dealt: on a phone the computer dealt Minesweeper actually plays Memory,
		-- and a screen advertising a game the player is never going to be given is worse than one that
		-- says nothing. Asked once, so a device that changes hands mid-session keeps the first answer.
		return framework:ResolvedFor(state.Model)
	end)
	state.Title = if ok and type(id) == "string" then `{id:upper()}.EXE` else false
	return if type(state.Title) == "string" then state.Title :: string else IDLE.FallbackText
end

--- Draws the little "there is something here" display on the screen part itself. Display only: it
--- takes no input, and the real minigame arrives as a separate gui adorned to the same part. Answers
--- whether there was a screen to draw on, which is what the retry below waits for.
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

	-- The blinking block under the words, which is the whole reason this reads as a terminal rather
	-- than as a sign.
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

--- Repaints the idle display for whatever the local set now says.
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

--- The last step of ScreenPath -- the name of the part the idle display is drawn on.
local SCREEN_NAME = ComputerConfig.ScreenPath[#ComputerConfig.ScreenPath]

--- Builds the idle display now if the screen part is there, and otherwise waits for it to turn up and
--- builds it then.
---
--- It usually is not there. With streaming on, a computer registers the moment its tag replicates and
--- the model's parts arrive afterwards, in whatever order the stream feels like -- so the first look
--- finds nothing, and a service that gave up there would leave every screen in the hotel dark for the
--- rest of the session. The listener is per-computer and comes down the moment it has done its job, or
--- when the computer is unregistered, whichever is first.
local function buildIdleWhenReady(state: State)
	if buildIdle(state) then return end

	state.Pending = state.Model.DescendantAdded:Connect(function(instance: Instance)
		if instance.Name ~= SCREEN_NAME then return end
		if not buildIdle(state) then return end

		refreshIdle(state)
		-- The part only exists as of now, so the colour written at registration went nowhere.
		paintScreen(state.Model)

		local pending = state.Pending
		state.Pending = nil
		if pending then
			pending:Disconnect()
		end
	end)
end

--- Declared ahead of everything that reaches for it: unregistering a computer, leaving, winning and
--- dying are all written before the one function that undoes a session.
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
	-- A place file can have been saved with a green screen part on it, and a snapshot can already have
	-- arrived for a computer that has only just streamed in. Either way the colour is settled here.
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

--- The local set --------------------------------------------------------------------------------

--- Puts every registered computer back in step with the set, and lets the HUD know. Cheap enough to
--- run over the lot rather than tracking which model moved: a hotel holds five of them.
local function applyState()
	for model, state in States do
		refreshIdle(state)
		paintScreen(model)
	end

	-- A computer that has just become hacked must stop offering its prompt this frame rather than the
	-- next time the player looks away from it.
	if focused and isHacked(focused) then
		focused = nil
	end

	changed:Fire()
end

--- Replaces the set with the server's, which is the whole array of models this player has hacked.
--- Anything the server did not name is unhacked, so a rejected optimistic win is undone here without
--- the server having to say anything about it.
local function applySnapshot(snapshot: any)
	if type(snapshot) ~= "table" then return end

	local list = snapshot :: { any }

	table.clear(HackedSet)
	for _, model in list do
		-- A computer streamed out of this client does not arrive as an instance at all; there is
		-- nothing on screen to colour, and the next snapshot will carry it again.
		if typeof(model) == "Instance" and model:IsA("Model") then
			HackedSet[model] = true
		end
	end

	applyState()
end

--- Marks a computer hacked before the server has confirmed it. The win is the player's own and has
--- already been celebrated on their screen; making them wait a round trip for the colour would read
--- as the game not having noticed.
local function markHacked(model: Model)
	if HackedSet[model] then return end
	HackedSet[model] = true
	applyState()
end

if SyncRemote then
	(SyncRemote :: RemoteEvent).OnClientEvent:Connect(applySnapshot)
end

--- Targeting ------------------------------------------------------------------------------------

--- The tagged model a part belongs to, if any.
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
		-- A hacked computer is not looked past, it is simply not offered: the desk it sits on is
		-- still solid, and walking round it should not suddenly find a drawer through the monitor.
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

--- The idle screens -----------------------------------------------------------------------------

-- One clock for every screen in the hotel rather than one timer each, so a row of computers blinks
-- together. It costs a loop over at most a handful of models a frame.
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

--- The prompt -----------------------------------------------------------------------------------

-- Cloned rather than shared: the drawers own the original, and two systems fading one CanvasGroup
-- in opposite directions would flicker. A place file without the Cursor gui simply gets no prompt.
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

--- Lays the prompt out around a badge of the given width: padding, badge, gap, word, padding. The
--- word gets a fixed column rather than one measured from itself, so nothing moves as the badge
--- swaps between the keyboard and console labels. The group is the pill plus the room its outline
--- needs, since a CanvasGroup clips to its own bounds.
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

--- Input ----------------------------------------------------------------------------------------

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

--- Drawing the prompt ---------------------------------------------------------------------------

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

--- Sessions -------------------------------------------------------------------------------------

--- The character's own controls, if the PlayerModule is where it always is. Wrapped because a
--- module that has not replicated yet must cost a locked player, not a thrown error mid-takeover.
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

--- How far out along the screen's normal the camera has to stand for the face to fill
--- `CAMERA.FillFraction` of the viewport's LIMITING side.
---
--- Worked out per session rather than authored as one number, because there is no one number: the
--- field of view is the vertical angle, so the horizontal half-angle depends on the shape of the
--- window, and a phone held upright and a widescreen monitor want distances that differ by half again.
--- Both candidates are computed and the larger wins -- the one that keeps the whole screen in shot.
--- The part's own depth is added back because the distance is measured from its centre while the glass
--- the player is reading sits in front of that, and the result is floored so a tiny screen part or a
--- daft field of view cannot push the camera inside the monitor.
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

--- Runs after the camera every frame for as long as a session is up. The default camera module and
--- the first-person service both want the mouse locked and hidden, and they want it again every
--- frame, so it is taken back from them every frame rather than once on the way in.
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

--- Puts back everything a session took. Safe to call from anywhere and safe to call twice: winning,
--- leaving, dying and the computer being destroyed all end here, and more than one of them can be
--- true in the same frame.
function restore()
	local current = session
	if not current or current.Closed then return end
	current.Closed = true
	session = nil
	lastClosed = os.clock()

	for _, connection in current.Connections do
		connection:Disconnect()
	end

	-- Close is idempotent and never calls OnExit back, which is what lets every way out of a session
	-- -- the button, the key, winning, dying, the maze being rebuilt -- come through here and leave
	-- exactly one teardown behind.
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
		-- Put the old view back before handing control over, so the frame in which the camera module
		-- takes the wheel is already looking the right way.
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
	-- Marked here first and told to the server second: the screen is green, the prompt is gone and the
	-- counter has ticked before the remote has even left, and the server's snapshot lands behind it
	-- agreeing. Nobody else's screen moves -- this computer is only hacked for this player.
	markHacked(model)
	if CompleteRemote then
		(CompleteRemote :: RemoteEvent):FireServer(model)
	end
	restore()
end

--- Reading the state ----------------------------------------------------------------------------

--- Whether THIS player has broken into `model`.
function ComputerService:IsHacked(model: Model): boolean
	return isHacked(model)
end

--- The computer the cursor is resting on, or nil.
function ComputerService:GetFocused(): Model?
	return focused
end

--- Whether a minigame is up on this client.
function ComputerService:IsSessionOpen(): boolean
	return session ~= nil
end

--- Hands the screen of the computer being looked at over to the minigame framework. Answers whether
--- a session actually started, which is what the prompt flashes on.
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

	-- Front is the face the gui is drawn on, and a part's LookVector points straight out of it, so
	-- this is the one place the camera can stand and see the whole canvas square-on. How far out is
	-- measured against this player's actual viewport, now, rather than assumed.
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
		-- The framework's own gui is about to adorn this part; two guis on one face is one too many.
		state.Gui.Enabled = false
	end

	-- A death, a teleport or a maze rebuild during a minigame all leave the player stranded in a
	-- scriptable camera otherwise, so each of them is wired straight to the same restore.
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

--- Stepping -------------------------------------------------------------------------------------

layout(UI.KeySize)

RunService:BindToRenderStep(FOCUS_JOB, Enum.RenderPriority.Camera.Value + 3, renderFocus)
RunService:BindToRenderStep(PROMPT_JOB, Enum.RenderPriority.Last.Value, renderPrompt)

TagService:Listen(ComputerConfig.Tag, register, unregister, workspace)

return ComputerService


