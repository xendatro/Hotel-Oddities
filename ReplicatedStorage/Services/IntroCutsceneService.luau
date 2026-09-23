local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local IntroCutsceneService = {}

if not RunService:IsClient() then return IntroCutsceneService end

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local IntroCutsceneConfig = require(ReplicatedStorage.Configs.IntroCutsceneConfig)
local AmbienceService = require(ReplicatedStorage.Services.AmbienceService)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local CaptureGalleryService = require(ReplicatedStorage.Services.CaptureGalleryService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ComputerService = require(ReplicatedStorage.Services.ComputerService)
local CrouchService = require(ReplicatedStorage.Services.CrouchService)
local DeathScreenService = require(ReplicatedStorage.Services.DeathScreenService)
local EndScreenService = require(ReplicatedStorage.Services.EndScreenService)
local EnemyObservationService = require(ReplicatedStorage.Services.EnemyObservationService)
local GravityWarpService = require(ReplicatedStorage.Services.GravityWarpService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local HeartbeatService = require(ReplicatedStorage.Services.HeartbeatService)
local InterfaceHideService = require(ReplicatedStorage.Services.InterfaceHideService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local LookService = require(ReplicatedStorage.Services.LookService)
local MathService = require(ReplicatedStorage.Services.MathService)
local ShakeService = require(ReplicatedStorage.Services.ShakeService)
local SpawnZoneService = require(ReplicatedStorage.Services.SpawnZoneService)
local SprintService = require(ReplicatedStorage.Services.SprintService)
local VanishedService = require(ReplicatedStorage.Services.VanishedService)
local ViewmodelService = require(ReplicatedStorage.Services.ViewmodelService)
local VoiceActivityService = require(ReplicatedStorage.Services.VoiceActivityService)
local WalkieTalkieService = require(ReplicatedStorage.Services.WalkieTalkieService)
local CameraTrack = require(ReplicatedStorage.Classes.CameraTrack)
local KeyPill = require(ReplicatedStorage.Classes.KeyPill)
local LocalOverride = require(ReplicatedStorage.Classes.LocalOverride)
local Isolation = require(ReplicatedStorage.Classes.IntroCutscene.Isolation)
local LightSweep = require(ReplicatedStorage.Classes.IntroCutscene.LightSweep)
local StagedCreep = require(ReplicatedStorage.Classes.IntroCutscene.StagedCreep)
local StagedStalker = require(ReplicatedStorage.Classes.IntroCutscene.StagedStalker)

local KEY = IntroCutsceneConfig.Key
local GUI = IntroCutsceneConfig.Gui
local INPUT = IntroCutsceneConfig.Input
local PILLS = IntroCutsceneConfig.Pills
local SKIP = IntroCutsceneConfig.Skip
local TRIGGER = IntroCutsceneConfig.Trigger
local TEXT = IntroCutsceneConfig.Text
local CAPTIONS = IntroCutsceneConfig.Captions
local SOUNDS = IntroCutsceneConfig.Sounds
local CUES = SOUNDS.Cues
local EFFECTS = IntroCutsceneConfig.Effects
local MOTES = IntroCutsceneConfig.Motes
local SHAKES = IntroCutsceneConfig.Shakes
local STALKER = IntroCutsceneConfig.Stalker
local STALKER_SKIP = IntroCutsceneConfig.StalkerSkip
local CREEP = IntroCutsceneConfig.Creep
local LIGHTS = IntroCutsceneConfig.Lights
local POINTS = IntroCutsceneConfig.Points
local CAMERA = IntroCutsceneConfig.Camera
local LIGHTING = IntroCutsceneConfig.Lighting
local REMOTES = IntroCutsceneConfig.Remotes
local TRIGGERS = IntroCutsceneConfig.Triggers
local OUTCOMES = IntroCutsceneConfig.Outcomes
local SEEN_ATTRIBUTE = IntroCutsceneConfig.SeenAttribute
local PLAYING_ATTRIBUTE = IntroCutsceneConfig.PlayingAttribute

local RENDER_JOB = "IntroCutsceneCamera"
local EPSILON = 1e-3
local SAMPLE_STALE = 0.25
local STALKER_PROBE_HEIGHT = 2.5
local REPLAY_HIDE_DELAY = DrawerConfig.UI.FadeOutTime + 0.05
local SEEN_POLL = 0.1
local MOUSE_ACTIVITY = 2
local STICK_ACTIVITY = 0.35
local SINK = Enum.ContextActionResult.Sink

type Event = { Time: number, Name: string, Stalker: boolean?, Always: boolean? }

type Sample = { CFrame: CFrame, Time: number }

type Output = { CFrame: CFrame, Fov: number, Time: number }

type Kill = { Time: number, Model: Model, Flicker: number }

type OneShot = { Player: AudioPlayer, Volume: number }

type Line = {
	Label: TextLabel,
	Characters: { string },
	Start: number,
	Speed: number,
	Erase: number?,
	Until: number?,
	Shown: number,
	Count: number,
}

type Ui = {
	Gui: ScreenGui,
	Fade: Frame,
	Vignette: CanvasGroup,
	Top: Frame,
	Bottom: Frame,
	TopSize: UDim2,
	BottomSize: UDim2,
	Caption: TextLabel,
	Title: TextLabel,
	Rule: Frame,
	Subtitle: TextLabel,
	CaptionTransparency: number,
	TitleTransparency: number,
	SubtitleTransparency: number,
	RuleTransparency: number,
	RuleSize: UDim2,
	Skip: CanvasGroup,
	Pills: ScreenGui,
	Replay: CanvasGroup,
	Labels: { [string]: TextLabel },
}

type Armed = {
	Trigger: string,
	Look: Vector3,
	Character: Model,
	RefusedSince: number?,
	Tool: Tool?,
	Connections: { [string]: RBXScriptConnection },
}

type Session = {
	Trigger: string,
	Started: boolean,
	Restored: boolean,
	Returned: boolean,
	StartedAt: number,
	LastClock: number,
	ClockBase: number,
	ClockAnchor: number,
	ClockRate: number,
	TrackTime: number,
	EventIndex: number,
	Camera: Camera,
	SavedCFrame: CFrame,
	SavedFocus: CFrame,
	SavedType: Enum.CameraType,
	ReturnCFrame: CFrame,
	ReturnFocus: CFrame,
	BaseFov: number,
	FovOffset: number,
	Track: CameraTrack.CameraTrack,
	Grade: CameraTrack.CameraTrack,
	Output: Output,
	PreviousOutput: Output?,
	MotionBlur: number,
	FadeLevel: number,
	Darkness: number,
	Bars: number,
	Character: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	RootAnchored: boolean,
	Crouched: boolean,
	Tool: Tool?,
	Controls: any?,
	Hold: (() -> ())?,
	RestoreHud: (() -> ())?,
	MouseUnlocked: boolean,
	Override: LocalOverride.LocalOverride?,
	Isolation: Isolation.Isolation?,
	Stage: Model?,
	Motes: ParticleEmitter?,
	Stalker: StagedStalker.StagedStalker?,
	StalkerWanted: boolean,
	GeometryOk: boolean?,
	Creep: StagedCreep.StagedCreep?,
	Sweep: LightSweep.LightSweep?,
	Junction: Model?,
	Kills: { Kill },
	Color: ColorCorrectionEffect?,
	Blur: BlurEffect?,
	Depth: DepthOfFieldEffect?,
	Sounds: { Instance },
	OneShots: { OneShot },
	Drone: AudioPlayer?,
	DroneBase: number,
	DroneLevel: number,
	Heart: AudioPlayer?,
	HeartBase: number,
	HeartSpeed: number,
	HeartLevel: number,
	Shifter: AudioPitchShifter?,
	AudioMaster: number,
	LastTick: number,
	Lines: { Line },
	SkipReady: boolean,
	SkipHeld: { [any]: boolean },
	SkipProgress: number,
	Skipping: boolean,
	SkipStartedAt: number,
	SkipFrom: number,
	SkipFade: number?,
	SkipJumped: boolean,
	LastInputAt: number,
	Connections: { [string]: RBXScriptConnection },
}

local EVENTS: { Event } = table.clone(IntroCutsceneConfig.Events)
table.sort(EVENTS, function(a: Event, b: Event)
	return a.Time < b.Time
end)

local END_TIME = IntroCutsceneConfig.Length
for _, event in EVENTS do
	if event.Name == "End" then
		END_TIME = event.Time
	end
end

local player = Players.LocalPlayer
local playerGui = GuiBuilderService.GetPlayerGui()

local LoadingRemote = CommunicationService.Get("Elevator", "Loading") :: RemoteEvent
local ArrivalRemote = CommunicationService.Get("Elevator", ElevatorConfig.ArrivalRemoteName) :: RemoteEvent
local PrepareRemote = CommunicationService.Get(REMOTES.Folder, REMOTES.Prepare) :: RemoteEvent
local StartedRemote = CommunicationService.Get(REMOTES.Folder, REMOTES.Started) :: RemoteEvent
local FinishedRemote = CommunicationService.Get(REMOTES.Folder, REMOTES.Finished) :: RemoteEvent
local QueueRemote = CommunicationService.Get(REMOTES.Folder, REMOTES.Queue) :: RemoteEvent

local warned: { [string]: boolean } = {}

local function warnOnce(label: string, message: string)
	if warned[label] then return end
	warned[label] = true
	warn(`[IntroCutsceneService] {message}`)
end

local function attempt(label: string, callback: (...any) -> ...any, ...: any): (boolean, ...any)
	local results = table.pack(pcall(callback, ...))
	if not results[1] then
		warnOnce(label, `{label} failed: {results[2]}`)
	end
	return table.unpack(results, 1, results.n)
end

local function bindUi(): Ui?
	local gui = playerGui:WaitForChild(GUI.ScreenGui, 30)
	if not gui or not gui:IsA("ScreenGui") then return nil end
	local pills = playerGui:WaitForChild(GUI.Pills, 30)
	if not pills or not pills:IsA("ScreenGui") then return nil end

	local fade = gui:FindFirstChild(GUI.Fade)
	local vignette = gui:FindFirstChild(GUI.Vignette)
	local letterbox = gui:FindFirstChild(GUI.Letterbox)
	local top = letterbox and letterbox:FindFirstChild(GUI.LetterboxTop)
	local bottom = letterbox and letterbox:FindFirstChild(GUI.LetterboxBottom)
	local caption = gui:FindFirstChild(GUI.Caption)
	local card = gui:FindFirstChild(GUI.Card)
	local title = card and card:FindFirstChild(GUI.Title)
	local rule = card and card:FindFirstChild(GUI.Rule)
	local subtitle = card and card:FindFirstChild(GUI.Subtitle)
	local skip = gui:FindFirstChild(GUI.Skip)
	local replay = pills:FindFirstChild(GUI.Replay)

	if not (
		fade and fade:IsA("Frame")
		and vignette and vignette:IsA("CanvasGroup")
		and top and top:IsA("Frame")
		and bottom and bottom:IsA("Frame")
		and caption and caption:IsA("TextLabel")
		and title and title:IsA("TextLabel")
		and rule and rule:IsA("Frame")
		and subtitle and subtitle:IsA("TextLabel")
		and skip and skip:IsA("CanvasGroup")
		and replay and replay:IsA("CanvasGroup")
	) then
		return nil
	end

	return {
		Gui = gui,
		Fade = fade,
		Vignette = vignette,
		Top = top,
		Bottom = bottom,
		TopSize = top.Size,
		BottomSize = bottom.Size,
		Caption = caption,
		Title = title,
		Rule = rule,
		Subtitle = subtitle,
		CaptionTransparency = caption.TextTransparency,
		TitleTransparency = title.TextTransparency,
		SubtitleTransparency = subtitle.TextTransparency,
		RuleTransparency = rule.BackgroundTransparency,
		RuleSize = rule.Size,
		Skip = skip,
		Pills = pills,
		Replay = replay,
		Labels = {
			[GUI.Caption] = caption,
			[GUI.Title] = title,
			[GUI.Subtitle] = subtitle,
		},
	}
end

local ui = bindUi()
if not ui then
	warn("[IntroCutsceneService] StarterGui.IntroCutsceneGui or StarterGui.IntroCutscenePills is missing or misshapen; the intro cutscene is disabled")
	return IntroCutsceneService
end
local UI = ui :: Ui

local skipPill = KeyPill.new(UI.Skip, {
	KeyboardLabel = PILLS.Skip.Keyboard,
	GamepadLabel = PILLS.Skip.Gamepad,
	Action = TEXT.Skip,
	TouchAction = TEXT.SkipTouch,
})

local replayPill = KeyPill.new(UI.Replay, {
	KeyboardLabel = PILLS.Replay.Keyboard,
	GamepadLabel = PILLS.Replay.Gamepad,
	Action = TEXT.Replay,
	TouchAction = TEXT.ReplayTouch,
})

local function setBars(amount: number)
	local top, bottom = UI.TopSize, UI.BottomSize
	UI.Top.Size = UDim2.new(top.X.Scale, top.X.Offset, top.Y.Scale * amount, top.Y.Offset * amount)
	UI.Bottom.Size = UDim2.new(bottom.X.Scale, bottom.X.Offset, bottom.Y.Scale * amount, bottom.Y.Offset * amount)
end

local function resetUi()
	UI.Fade.BackgroundTransparency = 1
	UI.Vignette.GroupTransparency = 1
	setBars(0)
	for _, label in UI.Labels do
		label.Text = ""
		label.MaxVisibleGraphemes = -1
	end
	UI.Caption.TextTransparency = UI.CaptionTransparency
	UI.Title.TextTransparency = UI.TitleTransparency
	UI.Subtitle.TextTransparency = UI.SubtitleTransparency
	UI.Rule.BackgroundTransparency = UI.RuleTransparency
	UI.Rule.Size = UDim2.new(0, 0, UI.RuleSize.Y.Scale, UI.RuleSize.Y.Offset)
end

resetUi()
UI.Gui.Enabled = false
UI.Pills.Enabled = false

local function flat(vector: Vector3): Vector3
	local horizontal = MathService.Horizontal(vector)
	return if horizontal.Magnitude > EPSILON then horizontal.Unit else Vector3.zero
end

local function clampLength(vector: Vector3, maximum: number): Vector3
	local length = vector.Magnitude
	if length > maximum and length > 0 then
		return vector * (maximum / length)
	end
	return vector
end

local function stalkerFrames(): (CFrame, CFrame, Vector3)
	local root = STALKER.Root
	local facing = flat(STALKER.Facing)
	if facing.Magnitude < EPSILON then
		facing = Vector3.xAxis
	end

	local toShot = flat(POINTS.Look - root)
	local yaw = 0
	if toShot.Magnitude > EPSILON then
		local limit = math.rad(STALKER.MaxYaw)
		yaw = math.clamp(math.atan2(facing:Cross(toShot).Y, facing:Dot(toShot)), -limit, limit)
	end

	local direction = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(facing)
	local peek = CFrame.lookAt(root, root + direction)
	return peek, peek * CFrame.new(STALKER.HiddenShift, 0, 0), peek:PointToWorldSpace(STALKER.HeadOffset)
end

local STALKER_PEEK, STALKER_HIDDEN, STALKER_HEAD = stalkerFrames()

local function soundFolder(): Instance?
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	return sounds and sounds:FindFirstChild(SOUNDS.Folder)
end

local function effectsFolder(): Folder?
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	local folder = effects and effects:FindFirstChild(EFFECTS.Folder)
	return if folder and folder:IsA("Folder") then folder else nil
end

local function enemyTemplate(name: string): Model?
	local enemies = ReplicatedStorage:FindFirstChild("Enemies")
	local template = enemies and enemies:FindFirstChild(name)
	if template and template:IsA("Model") then return template end
	warnOnce(`Template{name}`, `ReplicatedStorage.Enemies.{name} is missing; its beat is skipped`)
	return nil
end

local function cueTemplate(name: string): (AudioEmitter?, AudioPlayer?)
	local cue = CUES[name]
	local folder = soundFolder()
	local template = cue and folder and folder:FindFirstChild(cue.Name)
	local source = template and template:FindFirstChild("Player")
	if template and template:IsA("AudioEmitter") and source and source:IsA("AudioPlayer") then
		return template, source
	end
	warnOnce(`Cue{name}`, `no "{if cue then cue.Name else name}" cue in ReplicatedStorage.Sounds.{SOUNDS.Folder}; it stays silent`)
	return nil, nil
end

local function playCue(current: Session?, name: string, extra: { [string]: any }?): AudioPlayer?
	local cue = CUES[name]
	local template, source = cueTemplate(name)
	if not cue or not template or not source then return nil end

	local settings: { [string]: any } = { Volume = source.Volume * (cue.Gain or 1) }
	if extra then
		for property, value in extra do
			settings[property] = value
		end
	end

	local ok, playback = attempt(`Play{name}`, AudioService.Play2D, AudioService, template, false, cue.Bus, settings)
	if not ok or not playback or not playback:IsA("AudioPlayer") then return nil end
	if current then
		table.insert(current.Sounds, playback)
		table.insert(current.OneShots, { Player = playback, Volume = playback.Volume })
	end
	return playback
end

local function startLoop(current: Session, name: string, target: Instance?): (AudioPlayer?, number, number)
	local cue = CUES[name]
	local template, source = cueTemplate(name)
	if not cue or not template or not source then return nil, 0, 1 end

	local ok, playback = attempt(`Loop{name}`, AudioService.Play2D, AudioService, template, true, cue.Bus, { Volume = 0 }, target)
	if not ok or not playback or not playback:IsA("AudioPlayer") then return nil, 0, 1 end
	table.insert(current.Sounds, playback)
	return playback, source.Volume * (cue.Gain or 1), source.PlaybackSpeed
end

local function controls(): any?
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module or not module:IsA("ModuleScript") then return nil end

	local ok, result = pcall(function()
		return require(module :: ModuleScript):GetControls()
	end)
	return if ok then result else nil
end

local session: Session? = nil
local armed: Armed? = nil
local queuedBy: string? = nil
local transition: { Token: number, Arrived: boolean, Look: Vector3? }? = nil
local lastSample: Sample? = nil
local previousSample: Sample? = nil
local replayShown = false
local replayToken = 0
local hideToken = 0
local preloading = false

local restore: (current: Session) -> ()
local finish: (current: Session, outcome: string) -> ()
local runEvent: (current: Session, event: Event) -> ()

local function outputMotion(current: Session): (Vector3, Vector3)
	local last, previous = current.Output, current.PreviousOutput
	if not previous then return Vector3.zero, Vector3.zero end

	local span = last.Time - previous.Time
	if span <= EPSILON then return Vector3.zero, Vector3.zero end

	local velocity = (last.CFrame.Position - previous.CFrame.Position) / span
	local spin = previous.CFrame.Rotation:VectorToWorldSpace(
		MathService.RotationVector(previous.CFrame.Rotation:ToObjectSpace(last.CFrame.Rotation))
	) / span
	return velocity, spin
end

local function liveMotion(): (Vector3, Vector3)
	local last, previous = lastSample, previousSample
	if not last or not previous or os.clock() - last.Time > SAMPLE_STALE then
		return Vector3.zero, Vector3.zero
	end

	local span = last.Time - previous.Time
	if span <= EPSILON then return Vector3.zero, Vector3.zero end

	local velocity = (last.CFrame.Position - previous.CFrame.Position) / span
	local spin = previous.CFrame.Rotation:VectorToWorldSpace(
		MathService.RotationVector(previous.CFrame.Rotation:ToObjectSpace(last.CFrame.Rotation))
	) / span
	return clampLength(velocity, CAMERA.Entry.MaxSpeed), clampLength(spin, CAMERA.Entry.MaxSpin)
end

local function sampleCamera()
	local camera = workspace.CurrentCamera
	if not camera then return end
	previousSample = lastSample
	lastSample = { CFrame = camera.CFrame, Time = os.clock() }
end

local function returnFrames(root: BasePart, humanoid: Humanoid, camera: Camera, look: Vector3): (CFrame, CFrame)
	local settings = CAMERA.Return
	local focus = camera.Focus.Position
	local height = math.clamp(
		focus.Y - root.Position.Y - humanoid.CameraOffset.Y,
		settings.MinHeight,
		settings.MaxHeight
	)
	local subject = root.Position + Vector3.yAxis * height
	local zoom = math.clamp((camera.CFrame.Position - focus).Magnitude, 0, settings.MaxZoom)
	local position = subject - look * zoom
	return CFrame.lookAt(position, position + look), CFrame.new(subject)
end

local function buildAnchors(entry: Vector3, baseFov: number, returnFrame: CFrame): { [string]: any }
	local anchors: { [string]: any } = {}
	for name, point in POINTS do
		anchors[name] = point
	end

	local shot = POINTS.Look
	local toHead = STALKER_HEAD - shot
	local direction = if toHead.Magnitude > EPSILON then toHead.Unit else Vector3.xAxis
	local aim = STALKER_HEAD + STALKER.AimOffset
	local focusDistance = CAMERA.FocusDistance
	local start = returnFrame:PointToWorldSpace(CAMERA.Return.Drift)

	anchors.Entry = entry
	anchors.BaseFov = baseFov
	anchors.Push = shot + direction * STALKER.Push
	anchors.PushDeep = shot + direction * STALKER.PushDeep
	anchors.StalkerAim = aim
	anchors.DipFollow = aim + STALKER.DipFollow
	anchors.StalkerDistance = toHead.Magnitude - STALKER.Push
	anchors.CreepDistance = (CREEP.Root - POINTS.Creep).Magnitude
	anchors.Return = returnFrame.Position
	anchors.ReturnLook = returnFrame.Position + returnFrame.LookVector * focusDistance
	anchors.ReturnStart = start
	anchors.ReturnStartLook = start + returnFrame.LookVector * focusDistance + Vector3.yAxis * CAMERA.Return.Tilt
	return anchors
end

local function characters(text: string): { string }
	local list: { string } = {}
	if not utf8.len(text) then
		table.insert(list, text)
		return list
	end
	for first, last in utf8.graphemes(text) do
		table.insert(list, string.sub(text, first, last))
	end
	return list
end

local function buildLines(trigger: string, seen: boolean): { Line }
	local lines: { Line } = {}
	for _, spec in CAPTIONS.Lines do
		local label = UI.Labels[spec.Label]
		local text = TEXT[spec.Text]
		if not label or type(text) ~= "string" then continue end

		if spec.Text == "Welcome" then
			local returning = trigger == TRIGGERS.Replay or (trigger == TRIGGERS.Command and seen)
			text = string.format(if returning then TEXT.WelcomeBack else TEXT.Welcome, player.DisplayName)
		end

		local letters = characters(text)
		local speed = math.max(spec.Speed or CAPTIONS.CharactersPerSecond, EPSILON)
		table.insert(lines, {
			Label = label,
			Characters = letters,
			Start = spec.Start,
			Speed = speed,
			Erase = if spec.Erase then math.max(spec.Erase, spec.Start + #letters / speed + CAPTIONS.MinHold) else nil,
			Until = spec.Until,
			Shown = -2,
			Count = 0,
		})
	end
	return lines
end

local function raycastParams(current: Session): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { current.Character }
	if current.Stage then
		table.insert(ignore, current.Stage)
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

local function stalkerGeometryPresent(current: Session): boolean
	local params = raycastParams(current)
	local shot = POINTS.Look
	local toHidden = STALKER_HIDDEN.Position - shot
	local blocker = workspace:Raycast(shot, toHidden, params)
	if not blocker or blocker.Distance > toHidden.Magnitude - 0.5 then return false end

	local floor = workspace:Raycast(STALKER_PEEK.Position, Vector3.yAxis * -STALKER.FloorProbe, params)
	if not floor or math.abs(floor.Distance - STALKER.RootHeight) > STALKER.FloorTolerance then return false end

	local wall = workspace:Raycast(STALKER_PEEK.Position, STALKER_PEEK.LookVector * STALKER.WallProbe, params)
	return wall ~= nil
end

local function isOffScreen(camera: Camera, point: Vector3): boolean
	local viewport = camera.ViewportSize
	local projected = camera:WorldToViewportPoint(point)
	if projected.Z <= 0 then return true end

	local marginX = viewport.X * STALKER.ScreenMargin
	local marginY = viewport.Y * STALKER.ScreenMargin
	return projected.X < -marginX
		or projected.X > viewport.X + marginX
		or projected.Y < -marginY
		or projected.Y > viewport.Y + marginY
end

local function stalkerHidden(camera: Camera): boolean
	return isOffScreen(camera, STALKER_HEAD)
		and isOffScreen(camera, STALKER_PEEK.Position)
		and isOffScreen(camera, STALKER_PEEK:PointToWorldSpace(Vector3.new(0, STALKER_PROBE_HEIGHT, 0)))
end

local function placeStalker(current: Session)
	current.StalkerWanted = false
	local stage = current.Stage
	local template = enemyTemplate(STALKER.Template)
	if not stage or not template then return end

	local ok, stalker = attempt("StagedStalker.new", StagedStalker.new, {
		Parent = stage,
		Template = template,
		Effects = effectsFolder(),
		AnimationId = STALKER.AnimationId,
		PeekCFrame = STALKER_PEEK,
		HiddenCFrame = STALKER_HIDDEN,
		BreathAmplitude = STALKER.BreathAmplitude,
		EyeGlowColor = STALKER.EyeGlowColor,
	})
	if ok and stalker then
		current.Stalker = stalker
	end
end

local function spawnMotes(current: Session)
	local stage = current.Stage
	local folder = effectsFolder()
	local template = folder and folder:FindFirstChild(EFFECTS.Motes)
	local emitterTemplate = template and template:FindFirstChild(EFFECTS.MotesEmitter)
	if not stage or not emitterTemplate or not emitterTemplate:IsA("ParticleEmitter") then
		warnOnce("Motes", `ReplicatedStorage.Effects.{EFFECTS.Folder}.{EFFECTS.Motes} is missing; no motes`)
		return
	end

	local volume = Instance.new("Part")
	volume.Name = "Motes"
	volume.Size = MOTES.Size
	volume.CFrame = CFrame.new(MOTES.Center)
	volume.Transparency = 1
	volume.Anchored = true
	volume.CanCollide = false
	volume.CanQuery = false
	volume.CanTouch = false
	volume.CastShadow = false

	local emitter = emitterTemplate:Clone()
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	if emitter.Rate <= 0 then
		emitter.Rate = MOTES.Rate
	end
	emitter.Enabled = true
	emitter.Parent = volume
	volume.Parent = stage
	emitter:Emit(MOTES.Prewarm)
	current.Motes = emitter
end

local function clearMotes(current: Session)
	local emitter = current.Motes
	current.Motes = nil
	if emitter and emitter.Parent then
		emitter.Enabled = false
		emitter:Clear()
	end
end

local function startHeartbeat(current: Session)
	if current.Heart then return end

	local output = AudioService:GetOutput()
	local shifter = Instance.new("AudioPitchShifter")
	shifter.Name = "IntroCutsceneHeartbeat"
	shifter.Pitch = 1
	shifter.Parent = output.Parent
	AudioService:Wire(shifter, output)

	local playback, base, speed = startLoop(current, "Heartbeat", shifter)
	if not playback then
		shifter:Destroy()
		return
	end

	current.Heart = playback
	current.HeartBase = base
	current.HeartSpeed = speed
	current.HeartLevel = 0
	current.Shifter = shifter
	playback.Volume = 0
	playback.PlaybackSpeed = speed * (current.Grade:Sample("HeartRate", current.TrackTime) or 1)
end

local function scheduleLights(current: Session)
	local sweep = current.Sweep
	if not sweep then return end

	attempt("LightSweep:Collect", sweep.Collect, sweep)
	local ok, ordered = attempt("LightSweep:Ordered", sweep.Ordered, sweep, current.Output.CFrame.Position)
	if not ok or type(ordered) ~= "table" then return end

	local junction: Model? = nil
	local others: { Model } = {}
	for _, model in ordered :: { Model } do
		local offset = model:GetPivot().Position - LIGHTS.Junction
		if not junction and Vector2.new(offset.X, offset.Z).Magnitude <= LIGHTS.JunctionRadius then
			junction = model
		else
			table.insert(others, model)
		end
	end
	current.Junction = junction

	if #ordered < LIGHTS.MinimumForSweep then return end

	local origin = current.Output.CFrame.Position
	local groups: { { Model } } = {}
	local groupDistance = math.huge
	for _, model in others do
		local distance = (model:GetPivot().Position - origin).Magnitude
		local group = groups[#groups]
		if not group or math.abs(distance - groupDistance) > LIGHTS.GroupTolerance then
			group = {}
			table.insert(groups, group)
			groupDistance = distance
		end
		table.insert(group, model)
	end

	local steps = LIGHTS.Steps
	local kills: { Kill } = {}
	for index, group in groups do
		local stepIndex = #steps - (#groups - index)
		local time = if stepIndex >= 1
			then steps[stepIndex]
			else math.max(steps[1] - (1 - stepIndex) * (steps[2] - steps[1]), LIGHTS.Earliest)
		for member, model in group do
			table.insert(kills, { Time = time + (member - 1) * LIGHTS.Stagger, Model = model, Flicker = LIGHTS.Flicker })
		end
	end
	table.sort(kills, function(a: Kill, b: Kill)
		return a.Time < b.Time
	end)
	current.Kills = kills
end

local function runKills(current: Session)
	local sweep = current.Sweep
	if not sweep then return end

	local kills = current.Kills
	while kills[1] and kills[1].Time <= current.TrackTime do
		local kill = table.remove(kills, 1) :: Kill
		if kill.Model:IsDescendantOf(workspace) then
			attempt("LightSweep:Kill", sweep.Kill, sweep, kill.Model, kill.Flicker)
		end
	end
end

local function cleanupStage(current: Session)
	table.clear(current.Kills)
	current.StalkerWanted = false
	current.Junction = nil
	current.Motes = nil

	local sweep = current.Sweep
	current.Sweep = nil
	if sweep then
		attempt("LightSweep:Restore", sweep.Restore, sweep)
		attempt("LightSweep:Destroy", sweep.Destroy, sweep)
	end

	local stalker = current.Stalker
	current.Stalker = nil
	if stalker then
		attempt("StagedStalker:Destroy", stalker.Destroy, stalker)
	end

	local creep = current.Creep
	current.Creep = nil
	if creep then
		attempt("StagedCreep:Destroy", creep.Destroy, creep)
	end

	local stage = current.Stage
	current.Stage = nil
	if stage then
		stage:Destroy()
	end
end

local function stageCreep(current: Session)
	local stage = current.Stage
	local template = enemyTemplate(CREEP.Template)
	if stage and template then
		local facing = Vector3.new(POINTS.Creep.X, CREEP.Root.Y, POINTS.Creep.Z)
		local backdropFacing = Vector3.new(CREEP.Backdrop.X, CREEP.Backdrop.Y, POINTS.Creep.Z)
		local ok, creep = attempt("StagedCreep.new", StagedCreep.new, {
			Parent = stage,
			Template = template,
			Effects = effectsFolder(),
			RootCFrame = CFrame.lookAt(CREEP.Root, facing),
			BackdropCFrame = CFrame.lookAt(CREEP.Backdrop, backdropFacing),
			BackdropSize = CREEP.BackdropSize,
			EyeColor = CREEP.EyeColor,
		})
		if ok and creep then
			current.Creep = creep
		end
	end

	local override = current.Override
	if not override or current.Sweep then return end

	local folder = soundFolder()
	local ok, sweep = attempt("LightSweep.new", LightSweep.new, {
		Region = LIGHTS.Region,
		Tags = LIGHTS.Tags,
		Override = override,
		Sounds = {
			Flicker = folder and folder:FindFirstChild(CUES.Flicker.Name),
			Out = folder and folder:FindFirstChild(CUES.LightOut.Name),
		},
		Ambient = LIGHTS.Ambient,
	})
	if ok and sweep then
		current.Sweep = sweep
		attempt("LightSweep:Collect", sweep.Collect, sweep)
	end
end

local function jump(current: Session, to: number, rate: number, skipped: (event: Event) -> boolean)
	while true do
		local event = EVENTS[current.EventIndex]
		if not event or event.Time >= to then break end
		current.EventIndex += 1
		if not skipped(event) then
			runEvent(current, event)
		end
	end

	current.ClockBase = to
	current.ClockAnchor = os.clock() - current.StartedAt
	current.ClockRate = rate
	current.TrackTime = to
end

local function carryLines(current: Session, shift: number)
	local time = current.TrackTime
	for _, line in current.Lines do
		if line.Start > time then continue end

		local erase = line.Erase
		local gone = if erase then erase + #line.Characters / CAPTIONS.EraseCharactersPerSecond else line.Until
		if gone and time >= gone then continue end

		line.Start += shift
		if erase then
			line.Erase = erase + shift
		end
		if line.Until then
			line.Until = (line.Until :: number) + shift
		end
	end
end

local function skipStalkerBeats(current: Session)
	current.StalkerWanted = false
	local stalker = current.Stalker
	current.Stalker = nil
	if stalker then
		attempt("StagedStalker:Destroy", stalker.Destroy, stalker)
	end

	local output = current.Output
	local velocity, spin = outputMotion(current)
	carryLines(current, STALKER_SKIP.To - current.TrackTime)
	jump(current, STALKER_SKIP.To, 1, function(event: Event): boolean
		return event.Stalker == true
	end)
	current.Track:SetEntry(
		{ CFrame = output.CFrame, Fov = output.Fov, Velocity = velocity, AngularVelocity = spin },
		STALKER_SKIP.To,
		STALKER_SKIP.Blend,
		os.clock() - current.StartedAt
	)
end

local function jumpToReturn(current: Session)
	current.SkipJumped = true
	cleanupStage(current)
	current.Track:ClearEntry()
	jump(current, SKIP.ReturnAt, SKIP.ReturnRate, function(event: Event): boolean
		return event.Always ~= true
	end)
	current.SkipFade = nil
end

local Handlers: { [string]: (current: Session) -> () } = {}

Handlers.Motes = function(current)
	spawnMotes(current)
end

Handlers.SkipIn = function(current)
	current.SkipReady = true
	current.LastInputAt = os.clock()
	skipPill:SetDimmed(false)
	skipPill:SetVisible(true)
end

Handlers.StageStalker = function(current)
	current.StalkerWanted = current.GeometryOk ~= false
end

Handlers.StalkerGate = function(current)
	local stalker = current.Stalker
	if current.GeometryOk and stalker and stalker:IsReady() then return end
	skipStalkerBeats(current)
end

Handlers.Heartbeat = function(current)
	startHeartbeat(current)
end

Handlers.Notice = function(current)
	playCue(current, "Notice")
	attempt("Notice shake", ShakeService.Impulse, ShakeService, SHAKES.Notice)
end

Handlers.Flare = function(current)
	local stalker = current.Stalker
	if stalker then
		attempt("StagedStalker:Notice", stalker.Notice, stalker)
	end
end

Handlers.Dip = function(current)
	local stalker = current.Stalker
	if stalker then
		attempt("StagedStalker:DipAsync", stalker.DipAsync, stalker, STALKER.DipDuration)
	end
	playCue(current, "Dip")
	attempt("Flinch shake", ShakeService.Impulse, ShakeService, SHAKES.Flinch)
end

Handlers.Whip = function(current)
	playCue(current, "Whip")
end

Handlers.StageCreep = function(current)
	stageCreep(current)
end

Handlers.Lights = function(current)
	scheduleLights(current)
end

Handlers.EyesSwell = function(current)
	playCue(current, "EyesOpen")
end

Handlers.EyesOpen = function(current)
	local creep = current.Creep
	if creep then
		attempt("StagedCreep:Open", creep.Open, creep, CREEP.OpenDuration)
	end
	attempt("EyesOpen shake", ShakeService.Impulse, ShakeService, SHAKES.EyesOpen)
end

Handlers.JunctionOut = function(current)
	local sweep, junction = current.Sweep, current.Junction
	if sweep and junction and junction:IsDescendantOf(workspace) then
		attempt("LightSweep:Kill", sweep.Kill, sweep, junction, LIGHTS.JunctionFlicker)
	end
end

Handlers.MotesOut = function(current)
	clearMotes(current)
end

Handlers.Blink = function(current)
	local creep = current.Creep
	if creep then
		attempt("StagedCreep:Blink", creep.Blink, creep)
	end
end

Handlers.Rush = function(current)
	local creep = current.Creep
	if creep then
		attempt("StagedCreep:LaunchDistortion", creep.LaunchDistortion, creep, current.Output.CFrame.Position, CREEP.DistortionSpeed)
	end
	playCue(current, "Rush")
end

Handlers.Impact = function(current)
	attempt("Impact shake", ShakeService.Create, ShakeService, SHAKES.Impact)
end

Handlers.SmashCut = function(current)
	playCue(current, "Blackout")
	current.MotionBlur = 0
	current.HeartLevel = 0
	local heart = current.Heart
	if heart then
		heart.Volume = 0
	end
end

Handlers.Cleanup = function(current)
	cleanupStage(current)
end

Handlers.Return = function(current)
	current.Returned = true
	current.SkipReady = false
	table.clear(current.SkipHeld)
	skipPill:SetVisible(false)
end

Handlers.End = function(current)
	finish(current, if current.Skipping then OUTCOMES.Skipped else OUTCOMES.Watched)
end

function runEvent(current: Session, event: Event)
	local handler = Handlers[event.Name]
	if handler then
		attempt(`Event{event.Name}`, handler, current)
	end
end

local function runEvents(current: Session)
	while not current.Restored do
		local event = EVENTS[current.EventIndex]
		if not event or event.Time > current.TrackTime then break end
		current.EventIndex += 1
		if not current.Skipping or event.Always then
			runEvent(current, event)
		end
	end
end

local function applyFov(current: Session, fov: number, time: number)
	local others = CameraFovService:GetOffset() - current.FovOffset
	local handBack = MathService.Smoothstep((time - SKIP.ReturnAt) / math.max(END_TIME - SKIP.ReturnAt, EPSILON))
	local offset = fov - current.BaseFov - others * (1 - handBack)
	if math.abs(offset) < EPSILON then
		offset = 0
	end
	CameraFovService:SetOffset(KEY, offset)
	current.FovOffset = offset
end

local function renderCamera(current: Session, time: number, real: number, deltaTime: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if camera ~= current.Camera then
		current.Camera = camera
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local frame, fov = current.Track:Evaluate(time, real)
	camera.CFrame = frame
	camera.Focus = current.Track:GetFocus(frame)
	applyFov(current, fov, time)

	current.PreviousOutput = current.Output
	current.Output = { CFrame = frame, Fov = fov, Time = real }

	local blur = CAMERA.MotionBlur
	local speed = current.Track:GetAngularSpeed(math.max(time - 1 / 240, 0))
	local goal = math.clamp((speed - blur.Threshold) * blur.Gain, 0, blur.Max)
	current.MotionBlur += (goal - current.MotionBlur) * MathService.ExpAlpha(blur.Speed, deltaTime)
end

local function renderGrade(current: Session, time: number)
	local grade = current.Grade
	local fade = math.clamp(math.max(grade:Sample("Fade", time) or 0, current.SkipFade or 0), 0, 1)
	current.FadeLevel = fade
	UI.Fade.BackgroundTransparency = 1 - fade
	UI.Caption.TextTransparency = 1 - (1 - UI.CaptionTransparency) * (1 - (current.SkipFade or 0))

	local bars = math.clamp(grade:Sample("Letterbox", time) or 0, 0, 1)
	if math.abs(bars - current.Bars) > 1e-4 then
		current.Bars = bars
		setBars(bars)
	end

	UI.Vignette.GroupTransparency = 1 - math.clamp(grade:Sample("Vignette", time) or 0, 0, 1)

	local color = current.Color
	if color then
		color.Saturation = grade:Sample("Saturation", time) or 0
		color.Contrast = grade:Sample("Contrast", time) or 0
		color.Brightness = grade:Sample("Brightness", time) or 0
		color.TintColor = grade:Sample("Tint", time) or Color3.new(1, 1, 1)
	end

	local depth = current.Depth
	if depth then
		local near = math.clamp(grade:Sample("DepthNear", time) or 0, 0, 1)
		local far = math.clamp(grade:Sample("DepthFar", time) or 0, 0, 1)
		depth.Enabled = near > EPSILON or far > EPSILON
		depth.NearIntensity = near
		depth.FarIntensity = far
		depth.FocusDistance = math.max(grade:Sample("DepthFocus", time) or 0, 0)
	end

	local blur = current.Blur
	if blur then
		blur.Size = math.max(grade:Sample("Blur", time) or 0, current.MotionBlur)
	end

	local sweep = current.Sweep
	local darkness = math.clamp(grade:Sample("Darkness", time) or 0, 0, 1)
	if sweep and math.abs(darkness - current.Darkness) > EPSILON then
		current.Darkness = darkness
		attempt("LightSweep:SetAmbient", sweep.SetAmbient, sweep, darkness)
	end

	local alpha = math.clamp(grade:Sample("CardAlpha", time) or 0, 0, 1)
	UI.Title.TextTransparency = 1 - alpha * (1 - UI.TitleTransparency)
	UI.Subtitle.TextTransparency = 1 - alpha * (1 - UI.SubtitleTransparency)
	UI.Rule.BackgroundTransparency = 1 - alpha * (1 - UI.RuleTransparency)
	UI.Rule.Size = UDim2.new(0, math.max(grade:Sample("RuleWidth", time) or 0, 0), UI.RuleSize.Y.Scale, UI.RuleSize.Y.Offset)
end

local function lineState(line: Line, time: number): (number?, boolean, boolean)
	if time < line.Start or (line.Until and time >= line.Until) then
		return nil, false, false
	end

	local total = #line.Characters
	local typed = math.min(math.floor((time - line.Start) * line.Speed), total)
	local erase = line.Erase
	if erase and time >= erase then
		local count = typed - math.floor((time - erase) * CAPTIONS.EraseCharactersPerSecond)
		if count <= 0 then
			return nil, false, false
		end
		return count, true, false
	end

	if typed < total then
		return typed, true, true
	end

	local done = line.Start + total / line.Speed
	return total, math.floor((time - done) / CAPTIONS.CaretBlink) % 2 == 0, false
end

local function tick(current: Session)
	local now = os.clock()
	if now - current.LastTick < CUES.Type.Interval then return end
	current.LastTick = now

	local _, source = cueTemplate("Type")
	local speed = if source then source.PlaybackSpeed else 1
	local pitch = MathService.RandomRange(CUES.Type.PitchMin, CUES.Type.PitchMax)
	playCue(current, "Type", { PlaybackSpeed = speed * pitch })
end

local function renderLines(current: Session, time: number)
	local latest: Line? = nil
	for _, line in current.Lines do
		if time >= line.Start and (not latest or line.Start > latest.Start) then
			latest = line
		end
	end

	for _, line in current.Lines do
		local count, caret, typing = lineState(line, time)
		caret = caret and line == latest
		local shown = if count then count * 2 + (if caret then 1 else 0) else -1
		if shown == line.Shown then continue end

		local previous = line.Count
		line.Shown = shown
		local label = line.Label
		if not count then
			line.Count = 0
			label.Text = ""
			label.MaxVisibleGraphemes = -1
			continue
		end

		local characters = line.Characters
		label.Text = table.concat(characters, "", 1, count) .. CAPTIONS.Caret .. table.concat(characters, "", count + 1)
		label.MaxVisibleGraphemes = count + (if caret then 1 else 0)
		line.Count = count

		local every = CAPTIONS.TickEvery
		if typing and count > previous and math.floor(count / every) > math.floor(previous / every) then
			tick(current)
		end
	end
end

local function renderAudio(current: Session, time: number, deltaTime: number)
	local grade = current.Grade
	local blend = MathService.ExpAlpha(SOUNDS.LevelSpeed, deltaTime)

	local drone = current.Drone
	if drone and drone.Parent then
		local goal = (grade:Sample("Drone", time) or 0) * current.AudioMaster
		current.DroneLevel += (goal - current.DroneLevel) * blend
		drone.Volume = current.DroneBase * current.DroneLevel * AudioService:GetBus(CUES.Drone.Bus).Volume
	end

	local tail = if time > SKIP.ReturnAt
		then math.clamp((END_TIME - time) / math.max(END_TIME - SKIP.ReturnAt, EPSILON), 0, 1)
		else 1
	local fade = tail * current.AudioMaster
	local oneShots = current.OneShots
	for index = #oneShots, 1, -1 do
		local oneShot = oneShots[index]
		if not oneShot.Player.Parent then
			table.remove(oneShots, index)
		elseif fade < 1 then
			oneShot.Player.Volume = oneShot.Volume * fade
		end
	end

	local heart = current.Heart
	if heart and heart.Parent then
		local goal = (grade:Sample("Heart", time) or 0) * current.AudioMaster
		current.HeartLevel += (goal - current.HeartLevel) * blend
		heart.Volume = current.HeartBase * current.HeartLevel * AudioService:GetBus(CUES.Heartbeat.Bus).Volume

		local rate = math.max(grade:Sample("HeartRate", time) or 1, EPSILON)
		heart.PlaybackSpeed = current.HeartSpeed * rate
		local shifter = current.Shifter
		if shifter then
			shifter.Pitch = 1 / rate
		end
	end
end

local function renderStage(current: Session, deltaTime: number, real: number)
	if current.GeometryOk == nil then
		if stalkerGeometryPresent(current) then
			current.GeometryOk = true
		elseif real >= STALKER.GeometryWait then
			current.GeometryOk = false
			current.StalkerWanted = false
		end
	end

	if current.StalkerWanted and current.GeometryOk and stalkerHidden(current.Camera) then
		placeStalker(current)
	end

	local stalker = current.Stalker
	if stalker then
		attempt("StagedStalker:Update", stalker.Update, stalker, deltaTime)
	end

	local creep = current.Creep
	if creep then
		attempt("StagedCreep:Update", creep.Update, creep, deltaTime, current.Output.CFrame.Position)
	end
end

local function beginSkip(current: Session)
	current.Skipping = true
	current.SkipStartedAt = os.clock()
	current.SkipFrom = current.FadeLevel
	current.SkipFade = current.FadeLevel
	current.StalkerWanted = false
	skipPill:Flash()
	skipPill:SetHold(1)
end

local function updateSkip(current: Session, deltaTime: number)
	if current.Skipping then
		current.AudioMaster = 1 - math.clamp((os.clock() - current.SkipStartedAt) / SKIP.FadeOut, 0, 1)
		local sweep = current.Sweep
		if sweep then
			attempt("LightSweep:SetGain", sweep.SetGain, sweep, current.AudioMaster)
		end
		if current.SkipJumped then return end

		local from = current.SkipFrom
		local duration = SKIP.FadeOut * (1 - from)
		local progress = if duration > EPSILON
			then math.clamp((os.clock() - current.SkipStartedAt) / duration, 0, 1)
			else 1
		current.SkipFade = from + (1 - from) * progress
		if progress >= 1 then
			jumpToReturn(current)
		end
		return
	end

	if not current.SkipReady then return end

	local held = next(current.SkipHeld) ~= nil
	if held then
		current.SkipProgress = math.min(current.SkipProgress + deltaTime / SKIP.Hold, 1)
	else
		current.SkipProgress = math.max(current.SkipProgress - deltaTime / SKIP.Drain, 0)
	end
	skipPill:SetHold(current.SkipProgress)
	skipPill:SetDimmed(os.clock() - current.LastInputAt >= PILLS.DimAfter)

	if current.SkipProgress >= 1 then
		beginSkip(current)
	end
end

local function step(current: Session)
	if current.Restored then return end

	local now = os.clock()
	local deltaTime = math.clamp(now - current.LastClock, 0, 0.25)
	current.LastClock = now
	local real = now - current.StartedAt

	local hold = current.Hold
	if hold then
		hold()
	end

	current.TrackTime = current.ClockBase + (real - current.ClockAnchor) * current.ClockRate
	updateSkip(current, deltaTime)
	if current.Restored then return end

	runEvents(current)
	if current.Restored then return end

	if not current.Skipping then
		runKills(current)
	end

	local time = current.TrackTime
	renderCamera(current, time, real, deltaTime)
	renderGrade(current, time)
	renderLines(current, time)
	renderAudio(current, time, deltaTime)
	renderStage(current, deltaTime, real)

	if time >= SKIP.ReturnAt then
		current.Returned = true
	end
	if time >= END_TIME then
		finish(current, if current.Skipping then OUTCOMES.Skipped else OUTCOMES.Watched)
	elseif real > IntroCutsceneConfig.Length + IntroCutsceneConfig.Watchdog then
		finish(current, OUTCOMES.Interrupted)
	end
end

local function stopAudio(current: Session)
	for _, playback in current.Sounds do
		if playback.Parent and playback:IsA("AudioPlayer") then
			attempt("StopSound", AudioService.StopSound, AudioService, playback)
		end
	end
	table.clear(current.Sounds)
	table.clear(current.OneShots)
	current.Drone = nil
	current.Heart = nil

	local shifter = current.Shifter
	current.Shifter = nil
	if shifter then
		shifter:Destroy()
	end
end

function restore(current: Session)
	if current.Restored then return end
	current.Restored = true
	if session == current then
		session = nil
		player:SetAttribute(PLAYING_ATTRIBUTE, nil)
	end

	RunService:UnbindFromRenderStep(RENDER_JOB)
	for _, connection in current.Connections do
		connection:Disconnect()
	end
	table.clear(current.Connections)

	attempt("Restore camera", function()
		local camera = workspace.CurrentCamera or current.Camera
		if current.Returned then
			camera.CFrame = current.ReturnCFrame
			camera.Focus = current.ReturnFocus
		else
			camera.CFrame = current.SavedCFrame
			camera.Focus = current.SavedFocus
		end
		camera.CameraType = current.SavedType
	end)
	attempt("Restore field of view", CameraFovService.SetOffset, CameraFovService, KEY, 0)

	local color, blur, depth = current.Color, current.Blur, current.Depth
	current.Color, current.Blur, current.Depth = nil, nil, nil
	if color then
		color:Destroy()
	end
	if blur then
		blur:Destroy()
	end
	if depth then
		depth:Destroy()
	end

	stopAudio(current)

	local isolation = current.Isolation
	current.Isolation = nil
	if isolation then
		attempt("Isolation:Stop", isolation.Stop, isolation)
		attempt("Isolation:Destroy", isolation.Destroy, isolation)
	end

	cleanupStage(current)

	local override = current.Override
	current.Override = nil
	if override then
		attempt("LocalOverride:Destroy", override.Destroy, override)
	end

	attempt("Release ambience", AmbienceService.Suppress, AmbienceService, KEY, false)
	attempt("Release observation", EnemyObservationService.SetSuspended, EnemyObservationService, KEY, false)
	attempt("Release look", LookService.SetSuspended, LookService, KEY, false)
	attempt("Release voice", VoiceActivityService.SetIncomingMuted, VoiceActivityService, KEY, false)
	attempt("Release radio", WalkieTalkieService.SetIncomingMuted, WalkieTalkieService, KEY, false)
	attempt("Release heartbeat", HeartbeatService.SetSuppressed, HeartbeatService, KEY, false)
	attempt("Release quick unlock", InterfaceService.SetQuickUnlockBlocked, InterfaceService, KEY, false)
	attempt("Release crouch", CrouchService.SetBlocked, CrouchService, KEY, false)
	if current.Crouched and current.Humanoid.Parent and current.Humanoid.Health > 0 then
		attempt("Restore crouch", CrouchService.SetCrouched, CrouchService, true)
	end
	attempt("Release sprint", SprintService.SetSprintBlocked, SprintService, KEY, false)

	current.Hold = nil
	local restoreHud = current.RestoreHud
	current.RestoreHud = nil
	if restoreHud then
		attempt("Restore interface", restoreHud)
	end
	if current.MouseUnlocked and not InterfaceService:IsMouseUnlocked() then
		attempt("Restore mouse", InterfaceService.SetMouseUnlocked, InterfaceService, true)
	end

	ContextActionService:UnbindAction(INPUT.SinkAction)
	ContextActionService:UnbindAction(INPUT.SkipAction)

	local controlModule = current.Controls
	if controlModule then
		attempt("Enable controls", function()
			controlModule:Enable()
		end)
	end

	local root = current.Root
	if root.Parent then
		root.Anchored = current.RootAnchored
	end

	local tool = current.Tool
	current.Tool = nil
	local humanoid = current.Humanoid
	local backpack = player:FindFirstChildOfClass("Backpack")
	if tool and backpack and tool.Parent == backpack and humanoid.Parent and humanoid.Health > 0 then
		attempt("Equip tool", humanoid.EquipTool, humanoid, tool)
	end

	attempt("Show viewmodel", ViewmodelService.SetCaptureHidden, ViewmodelService, false)

	skipPill:SetVisible(false)
	skipPill:SetHold(0)
	skipPill:SetDimmed(false)
	resetUi()
	UI.Gui.Enabled = false
	UI.Pills.Enabled = replayShown
end

function finish(current: Session, outcome: string)
	if current.Restored then return end
	local started = current.Started
	restore(current)
	if started then
		FinishedRemote:FireServer(outcome)
	end
end

local function onSinkAction(_action: string, _inputState: Enum.UserInputState): Enum.ContextActionResult
	return SINK
end

local function onSkipAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	local current = session
	if current then
		if inputState == Enum.UserInputState.Begin then
			current.SkipHeld.Action = true
			current.LastInputAt = os.clock()
		elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			current.SkipHeld.Action = nil
		end
	end
	return SINK
end

local function createEffects(current: Session)
	local color = Instance.new("ColorCorrectionEffect")
	color.Name = LIGHTING.Color
	color.Parent = Lighting
	current.Color = color

	local blur = Instance.new("BlurEffect")
	blur.Name = LIGHTING.Blur
	blur.Size = 0
	blur.Parent = Lighting
	current.Blur = blur

	local depth = Instance.new("DepthOfFieldEffect")
	depth.Name = LIGHTING.Depth
	depth.Enabled = false
	depth.NearIntensity = 0
	depth.FarIntensity = 0
	depth.FocusDistance = 0
	depth.InFocusRadius = LIGHTING.InFocusRadius
	depth.Parent = Lighting
	current.Depth = depth
end

local function connectSession(current: Session)
	local connections = current.Connections
	local function abort()
		finish(current, OUTCOMES.Interrupted)
	end

	connections.Died = current.Humanoid.Died:Connect(abort)
	connections.Removing = player.CharacterRemoving:Connect(abort)
	connections.Ancestry = current.Character.AncestryChanged:Connect(function()
		if not current.Character:IsDescendantOf(workspace) then
			abort()
		end
	end)
	connections.Shield = CollectionService:GetInstanceRemovedSignal(VanishedService.SafeZoneTag):Connect(function(instance: Instance)
		if instance == current.Character then
			abort()
		end
	end)

	local hit = skipPill:GetHitButton()
	if hit then
		connections.HitBegan = hit.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				current.SkipHeld[input] = true
				current.LastInputAt = os.clock()
			end
		end)
	end
	connections.InputEnded = UserInputService.InputEnded:Connect(function(input: InputObject)
		current.SkipHeld[input] = nil
	end)
	connections.Activity = UserInputService.InputBegan:Connect(function()
		current.LastInputAt = os.clock()
	end)
	connections.Motion = UserInputService.InputChanged:Connect(function(input: InputObject)
		local inputType = input.UserInputType
		local moved = (inputType == Enum.UserInputType.MouseMovement and input.Delta.Magnitude > MOUSE_ACTIVITY)
			or (inputType == Enum.UserInputType.Touch)
			or ((input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2)
				and input.Position.Magnitude > STICK_ACTIVITY)
		if moved then
			current.LastInputAt = os.clock()
		end
	end)
end

local function hideReplay()
	replayToken += 1
	if not replayShown then return end
	replayShown = false
	ContextActionService:UnbindAction(INPUT.ReplayAction)
	replayPill:SetVisible(false)

	hideToken += 1
	local token = hideToken
	task.delay(REPLAY_HIDE_DELAY, function()
		if token == hideToken and not replayShown then
			UI.Pills.Enabled = false
		end
	end)
end

local function takeOver(current: Session)
	local camera = current.Camera
	local root = current.Root
	local humanoid = current.Humanoid

	attempt("Close interface", function()
		local wasUnlocked = InterfaceService:IsMouseUnlocked()
		InterfaceService:Close()
		if InterfaceService:IsMouseUnlocked() then
			InterfaceService:SetMouseUnlocked(false)
		end
		current.MouseUnlocked = wasUnlocked and not InterfaceService:IsMouseUnlocked()
	end)
	attempt("Block quick unlock", InterfaceService.SetQuickUnlockBlocked, InterfaceService, KEY, true)

	current.Crouched = CrouchService:IsCrouching()
	attempt("Block crouch", CrouchService.SetBlocked, CrouchService, KEY, true)
	attempt("Block sprint", SprintService.SetSprintBlocked, SprintService, KEY, true)
	current.Controls = controls()
	local controlModule = current.Controls
	if controlModule then
		attempt("Disable controls", function()
			controlModule:Disable()
		end)
	end
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if current.Tool then
		attempt("Unequip tools", humanoid.UnequipTools, humanoid)
	end

	attempt("Hide viewmodel", ViewmodelService.SetCaptureHidden, ViewmodelService, true)

	resetUi()
	UI.Gui.Enabled = true
	local exclude: { LayerCollector } = { UI.Gui, UI.Pills }
	local loadingGui = playerGui:FindFirstChild(GUI.Loading)
	if loadingGui and loadingGui:IsA("LayerCollector") then
		table.insert(exclude, loadingGui)
	end
	local captured, hold, restoreHud = attempt("Hide interface", InterfaceHideService.Capture, {
		Exclude = exclude,
		HideNew = true,
	})
	if captured then
		current.Hold = hold
		current.RestoreHud = restoreHud
	end

	ContextActionService:BindActionAtPriority(
		INPUT.SinkAction,
		onSinkAction,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(INPUT.SinkKeys)
	)
	ContextActionService:BindActionAtPriority(
		INPUT.SkipAction,
		onSkipAction,
		false,
		Enum.ContextActionPriority.High.Value + 1,
		table.unpack(INPUT.SkipKeys)
	)

	attempt("Suppress ambience", AmbienceService.Suppress, AmbienceService, KEY, true)
	attempt("Suspend observation", EnemyObservationService.SetSuspended, EnemyObservationService, KEY, true)
	attempt("Suspend look", LookService.SetSuspended, LookService, KEY, true)
	attempt("Mute incoming voice", VoiceActivityService.SetIncomingMuted, VoiceActivityService, KEY, true)
	attempt("Mute radio", WalkieTalkieService.SetIncomingMuted, WalkieTalkieService, KEY, true)
	attempt("Suppress heartbeat", HeartbeatService.SetSuppressed, HeartbeatService, KEY, true)

	local override = LocalOverride.new()
	current.Override = override
	local bubbles = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if bubbles then
		override:Set(bubbles, "Enabled", false)
	end
	local isolated, isolation = attempt("Isolation.new", Isolation.new, { Override = override })
	if isolated and isolation then
		current.Isolation = isolation
		attempt("Isolation:Start", isolation.Start, isolation)
	end

	createEffects(current)

	local stage = Instance.new("Model")
	stage.Name = IntroCutsceneConfig.StageName
	stage.Parent = workspace
	current.Stage = stage

	local drone, droneBase = startLoop(current, "Drone")
	current.Drone = drone
	current.DroneBase = droneBase

	connectSession(current)

	camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value, function()
		local ok, message = pcall(step, current)
		if not ok then
			warn(`[IntroCutsceneService] the cutscene stopped: {message}`)
			finish(current, OUTCOMES.Interrupted)
		end
	end)

	StartedRemote:FireServer(current.Trigger)
	current.Started = true
end

local function begin(trigger: string, look: Vector3, tool: Tool?): boolean
	if session then return false end

	local character = player.Character
	local humanoid = CharacterService.GetAliveHumanoid(player)
	local root = CharacterService.GetAliveRoot(player)
	local camera = workspace.CurrentCamera
	if not character or not humanoid or not root or not camera then return false end

	hideReplay()

	local now = os.clock()
	local liveCFrame = camera.CFrame
	local liveFocus = camera.Focus
	local liveFov = camera.FieldOfView
	local baseFov = liveFov - CameraFovService:GetOffset()
	local velocity, spin = liveMotion()
	local entry = CAMERA.Entry
	local returnCFrame, returnFocus = returnFrames(root, humanoid, camera, look)
	local entryPoint = (liveCFrame.Position + velocity / entry.Position):Max(entry.Bounds.Min):Min(entry.Bounds.Max)
	local anchors = buildAnchors(entryPoint, baseFov, returnCFrame)

	local track = CameraTrack.new(CAMERA.Keys, {
		Handheld = CAMERA.Handheld,
		FocusDistance = CAMERA.FocusDistance,
		Anchors = anchors,
	})
	track:SetEntry(
		{ CFrame = liveCFrame, Fov = liveFov, Velocity = velocity, AngularVelocity = spin },
		0,
		{ Position = entry.Position, Rotation = entry.Rotation, Fov = entry.Fov },
		0
	)
	local grade = CameraTrack.new(IntroCutsceneConfig.Grade, { Anchors = anchors })
	local seen = player:GetAttribute(SEEN_ATTRIBUTE) == true

	local current: Session = {
		Trigger = trigger,
		Started = false,
		Restored = false,
		Returned = false,
		StartedAt = now,
		LastClock = now,
		ClockBase = 0,
		ClockAnchor = 0,
		ClockRate = 1,
		TrackTime = 0,
		EventIndex = 1,
		Camera = camera,
		SavedCFrame = liveCFrame,
		SavedFocus = liveFocus,
		SavedType = if camera.CameraType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else camera.CameraType,
		ReturnCFrame = returnCFrame,
		ReturnFocus = returnFocus,
		BaseFov = baseFov,
		FovOffset = 0,
		Track = track,
		Grade = grade,
		Output = { CFrame = liveCFrame, Fov = liveFov, Time = 0 },
		PreviousOutput = nil,
		MotionBlur = 0,
		FadeLevel = 0,
		Darkness = 0,
		Bars = -1,
		Character = character,
		Humanoid = humanoid,
		Root = root,
		RootAnchored = root.Anchored,
		Crouched = false,
		Tool = tool or character:FindFirstChildOfClass("Tool"),
		Controls = nil,
		Hold = nil,
		RestoreHud = nil,
		MouseUnlocked = false,
		Override = nil,
		Isolation = nil,
		Stage = nil,
		Motes = nil,
		Stalker = nil,
		StalkerWanted = false,
		GeometryOk = nil,
		Creep = nil,
		Sweep = nil,
		Junction = nil,
		Kills = {},
		Color = nil,
		Blur = nil,
		Depth = nil,
		Sounds = {},
		OneShots = {},
		Drone = nil,
		DroneBase = 0,
		DroneLevel = 0,
		Heart = nil,
		HeartBase = 0,
		HeartSpeed = 1,
		HeartLevel = 0,
		Shifter = nil,
		AudioMaster = 1,
		LastTick = 0,
		Lines = buildLines(trigger, seen),
		SkipReady = false,
		SkipHeld = {},
		SkipProgress = 0,
		Skipping = false,
		SkipStartedAt = 0,
		SkipFrom = 0,
		SkipFade = nil,
		SkipJumped = false,
		LastInputAt = now,
		Connections = {},
	}
	session = current
	player:SetAttribute(PLAYING_ATTRIBUTE, true)

	local ok, message = pcall(takeOver, current)
	if not ok then
		warn(`[IntroCutsceneService] the take-over failed: {message}`)
		finish(current, OUTCOMES.Interrupted)
		return false
	end
	return true
end

local function findThreshold(): BasePart?
	local map = workspace:FindFirstChild(TRIGGER.MapName)
	if not map then return nil end
	for _, spawn in CollectionService:GetTagged(ElevatorConfig.SpawnTag) do
		if spawn:IsDescendantOf(map) and spawn.Parent then
			local threshold = spawn.Parent:FindFirstChild(TRIGGER.ThresholdName)
			if threshold and threshold:IsA("BasePart") then
				return threshold
			end
		end
	end
	return nil
end

local function refused(): boolean
	local camera = workspace.CurrentCamera
	return not CharacterService.IsAlive(player.Character)
		or ComputerService:IsSessionOpen()
		or GravityWarpService.IsActive()
		or DeathScreenService:IsVisible()
		or EndScreenService:IsVisible()
		or session ~= nil
		or (camera ~= nil and camera.CameraType == Enum.CameraType.Scriptable)
		or (InterfaceService:IsMouseUnlockForced() and not WalkieTalkieService:IsRaised())
		or CaptureGalleryService:IsRecording()
end

local function shielded(character: Model, root: BasePart): boolean
	return SpawnZoneService:Contains(root.Position) and character:HasTag(VanishedService.SafeZoneTag)
end

local function interfaceSettled(): boolean
	local ok, settled = attempt("InterfaceService:IsSettled", InterfaceService.IsSettled, InterfaceService)
	return not ok or settled ~= false
end

local function disarm()
	local current = armed
	armed = nil
	if not current then return end
	for _, connection in current.Connections do
		connection:Disconnect()
	end
	table.clear(current.Connections)
end

local function watch()
	local current = armed
	if not current then return end
	sampleCamera()

	local loading = playerGui:FindFirstChild(GUI.Loading)
	if loading and loading:IsA("ScreenGui") and loading.Enabled then return end

	local root = CharacterService.GetAliveRoot(player)
	if not root or player.Character ~= current.Character then
		disarm()
		return
	end

	local threshold = findThreshold()
	if not threshold then return end

	local offset = threshold.CFrame:PointToObjectSpace(root.Position)
	local crossed = offset.Z < -TRIGGER.CrossDepth
		and offset.Z > -TRIGGER.MaxDepth
		and math.abs(offset.X) < TRIGGER.MaxLateral
		and math.abs(offset.Y) < TRIGGER.MaxHeight
	local refusedSince = current.RefusedSince
	local expired = refusedSince ~= nil and os.clock() - refusedSince >= TRIGGER.RetryWindow
	if expired or (offset.Z < -TRIGGER.CrossDepth and not crossed) then
		disarm()
		queuedBy = nil
		return
	end
	if not crossed then return end

	if not interfaceSettled() then
		local active = InterfaceService:GetActive()
		if active ~= nil and active ~= "" then
			InterfaceService:Close()
		end
		return
	end

	if refused() or not shielded(current.Character, root) then
		current.RefusedSince = current.RefusedSince or os.clock()
		return
	end

	if WalkieTalkieService:IsRaised() then
		current.RefusedSince = current.RefusedSince or os.clock()
		attempt("Lower walkie", WalkieTalkieService.SetRaised, WalkieTalkieService, false)
		return
	end

	local held = current.Character:FindFirstChildOfClass("Tool")
	if held then
		current.Tool = held
		current.RefusedSince = current.RefusedSince or os.clock()
		local humanoid = CharacterService.GetAliveHumanoid(player)
		if humanoid then
			attempt("Unequip tools", humanoid.UnequipTools, humanoid)
		end
		return
	end

	local trigger, look, tool = current.Trigger, current.Look, current.Tool
	disarm()
	queuedBy = nil
	begin(trigger, look, tool)
end

local function arm(trigger: string, look: Vector3)
	disarm()
	local character = player.Character
	local humanoid = CharacterService.GetAliveHumanoid(player)
	if not character or not humanoid then return end

	lastSample, previousSample = nil, nil
	local current: Armed = {
		Trigger = trigger,
		Look = look,
		Character = character,
		RefusedSince = nil,
		Tool = nil,
		Connections = {},
	}
	armed = current
	current.Connections.Watch = RunService.Heartbeat:Connect(watch)
	current.Connections.Died = humanoid.Died:Connect(disarm)
	current.Connections.Removing = player.CharacterRemoving:Connect(disarm)
end

local function arrivalLook(look: Vector3?): Vector3
	local flatLook = if look then flat(look) else Vector3.zero
	if flatLook.Magnitude > EPSILON then return flatLook end

	local threshold = findThreshold()
	local fromThreshold = if threshold then flat(threshold.CFrame.LookVector) else Vector3.zero
	if fromThreshold.Magnitude > EPSILON then return fromThreshold end
	return Vector3.zAxis
end

local function armWhenKnown(look: Vector3?)
	local deadline = os.clock() + TRIGGER.SeenWait
	while player:GetAttribute(SEEN_ATTRIBUTE) == nil and os.clock() < deadline do
		task.wait(SEEN_POLL)
	end
	if transition or session then return end

	local seen = player:GetAttribute(SEEN_ATTRIBUTE) == true
	if seen and not queuedBy then return end

	local trigger = if queuedBy == "Command"
		then TRIGGERS.Command
		elseif not seen then TRIGGERS.First
		else TRIGGERS.Replay
	arm(trigger, arrivalLook(look))
end

local function preload()
	if preloading then return end
	preloading = true

	task.spawn(function()
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{STALKER.AnimationId}`
		local assets: { Instance } = { animation }
		local effects = effectsFolder()
		if effects then
			table.insert(assets, effects)
		end
		local sounds = soundFolder()
		if sounds then
			table.insert(assets, sounds)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
		animation:Destroy()
		preloading = false
	end)
end

local function refreshReplay()
	if queuedBy == "Replay" then
		replayPill:SetAction(TEXT.Queued, TEXT.QueuedTouch)
	else
		replayPill:SetAction(TEXT.Replay, TEXT.ReplayTouch)
	end
end

local function toggleReplay()
	if not replayShown or queuedBy == "Command" then return end

	if queuedBy == "Replay" then
		queuedBy = nil
	else
		queuedBy = "Replay"
		PrepareRemote:FireServer()
		preload()
	end
	refreshReplay()
	replayPill:Flash()
	playCue(nil, "Toggle")
end

local function onReplayAction(_action: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		toggleReplay()
	end
	return SINK
end

local function showReplay()
	if replayShown or session then return end
	replayShown = true
	hideToken += 1

	refreshReplay()
	UI.Pills.Enabled = true
	replayPill:SetDimmed(false)
	replayPill:SetVisible(true)
	ContextActionService:BindActionAtPriority(
		INPUT.ReplayAction,
		onReplayAction,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(INPUT.ReplayKeys)
	)
end

local function onLoading(show: any, token: any)
	if typeof(token) ~= "number" then return end

	if show == true then
		disarm()
		local current = session
		if current then
			finish(current, OUTCOMES.Interrupted)
		end

		transition = { Token = token, Arrived = false, Look = nil }
		local seen = player:GetAttribute(SEEN_ATTRIBUTE)
		if seen ~= true or queuedBy ~= nil then
			PrepareRemote:FireServer()
			preload()
		end

		if seen == true and queuedBy ~= "Command" then
			replayToken += 1
			local expected = replayToken
			task.delay(PILLS.ReplayDelay, function()
				local active = transition
				if expected == replayToken and active and active.Token == token then
					showReplay()
				end
			end)
		end
	elseif show == false then
		local active = transition
		if not active or active.Token ~= token then return end
		transition = nil
		hideReplay()
		if active.Arrived then
			task.spawn(armWhenKnown, active.Look)
		end
	end
end

local function onArrival(target: any)
	local active = transition
	if not active then return end
	active.Arrived = true
	if typeof(target) == "CFrame" then
		active.Look = target.LookVector
	end
end

local replayHit = replayPill:GetHitButton()
if replayHit then
	replayHit.Activated:Connect(toggleReplay)
end

LoadingRemote.OnClientEvent:Connect(onLoading)
ArrivalRemote.OnClientEvent:Connect(onArrival)
QueueRemote.OnClientEvent:Connect(function()
	queuedBy = "Command"
end)

return IntroCutsceneService
