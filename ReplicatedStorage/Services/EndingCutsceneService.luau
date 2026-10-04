local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local EndingCutsceneService = {}

if not RunService:IsClient() then return EndingCutsceneService end

local ElevatorConfig = require(ReplicatedStorage.Configs.ElevatorConfig)
local EndingConfig = require(ReplicatedStorage.Configs.EndingConfig)
local EndingCutsceneConfig = require(ReplicatedStorage.Configs.EndingCutsceneConfig)
local AmbienceService = require(ReplicatedStorage.Services.AmbienceService)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local ChaseMusicService = require(ReplicatedStorage.Services.ChaseMusicService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local CrouchService = require(ReplicatedStorage.Services.CrouchService)
local ElevatorDoorService = require(ReplicatedStorage.Services.ElevatorDoorService)
local EndScreenService = require(ReplicatedStorage.Services.EndScreenService)
local EnemyObservationService = require(ReplicatedStorage.Services.EnemyObservationService)
local EscapeMusicService = require(ReplicatedStorage.Services.EscapeMusicService)
local GuiBuilderService = require(ReplicatedStorage.Services.GuiBuilderService)
local HeartbeatService = require(ReplicatedStorage.Services.HeartbeatService)
local InterfaceHideService = require(ReplicatedStorage.Services.InterfaceHideService)
local InterfaceService = require(ReplicatedStorage.Services.InterfaceService)
local LookService = require(ReplicatedStorage.Services.LookService)
local MathService = require(ReplicatedStorage.Services.MathService)
local ShakeService = require(ReplicatedStorage.Services.ShakeService)
local SprintService = require(ReplicatedStorage.Services.SprintService)
local ViewmodelService = require(ReplicatedStorage.Services.ViewmodelService)
local VoiceActivityService = require(ReplicatedStorage.Services.VoiceActivityService)
local WalkieTalkieService = require(ReplicatedStorage.Services.WalkieTalkieService)
local CameraTrack = require(ReplicatedStorage.Classes.CameraTrack)
local KeyPill = require(ReplicatedStorage.Classes.KeyPill)
local LocalOverride = require(ReplicatedStorage.Classes.LocalOverride)
local Isolation = require(ReplicatedStorage.Classes.IntroCutscene.Isolation)
local LightSweep = require(ReplicatedStorage.Classes.IntroCutscene.LightSweep)
local CabinStage = require(ReplicatedStorage.Classes.EndingCutscene.CabinStage)
local Cast = require(ReplicatedStorage.Classes.EndingCutscene.Cast)

local KEY = EndingCutsceneConfig.Key
local GUI = EndingCutsceneConfig.Gui
local ASSETS = EndingCutsceneConfig.Assets
local STAGE = EndingCutsceneConfig.Stage
local BLOOM = EndingCutsceneConfig.Bloom
local INPUT = EndingCutsceneConfig.Input
local SKIP = EndingCutsceneConfig.Skip
local TEXT = EndingCutsceneConfig.Text
local CAPTIONS = EndingCutsceneConfig.Captions
local SOUNDS = EndingCutsceneConfig.Sounds
local CUES = SOUNDS.Cues
local SHAKES = EndingCutsceneConfig.Shakes
local LIGHTS = EndingCutsceneConfig.Lights
local CAST = EndingCutsceneConfig.Cast
local CAMERA = EndingCutsceneConfig.Camera
local PLAYING_ATTRIBUTE = EndingCutsceneConfig.PlayingAttribute

local RENDER_JOB = "EndingCutsceneCamera"
local EPSILON = 1e-3
local MOUSE_ACTIVITY = 2
local STICK_ACTIVITY = 0.35
local SINK = Enum.ContextActionResult.Sink

local LOOPS: { [string]: { Level: string, Speed: string? } } = {
	Drone = { Level = "Drone" },
	Heartbeat = { Level = "Heart", Speed = "HeartRate" },
	Muzak = { Level = "Muzak", Speed = "MuzakSpeed" },
	Ride = { Level = "Ride" },
	Outside = { Level = "Outside" },
}

type Event = { Time: number, Name: string, Always: boolean?, Step: number?, Place: string?, Duration: number? }

type Kill = { Time: number, Model: Model, Flicker: number }

type OneShot = { Player: AudioPlayer, Volume: number }

type Loop = { Player: AudioPlayer, Base: number, Speed: number, Level: number }

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
	CaptionTransparency: number,
	TitleTransparency: number,
	Skip: CanvasGroup,
	Labels: { [string]: TextLabel },
}

type Session = {
	Done: () -> (),
	Restored: boolean,
	HandedOff: boolean,
	StartedAt: number,
	LastClock: number,
	ClockBase: number,
	ClockAnchor: number,
	ClockRate: number,
	Running: number,
	TrackTime: number,
	EventIndex: number,
	Camera: Camera,
	SavedCFrame: CFrame,
	SavedFocus: CFrame,
	SavedType: Enum.CameraType,
	BaseFov: number,
	FovOffset: number,
	Track: CameraTrack.CameraTrack,
	Grade: CameraTrack.CameraTrack,
	Character: Model,
	Humanoid: Humanoid,
	Exit: Model,
	Stage: CabinStage.CabinStage,
	Cast: Cast.Cast?,
	Sweep: LightSweep.LightSweep?,
	Kills: { Kill },
	Controls: any?,
	Hold: (() -> ())?,
	RestoreHud: (() -> ())?,
	Override: LocalOverride.LocalOverride?,
	Isolation: Isolation.Isolation?,
	Color: ColorCorrectionEffect?,
	Blur: BlurEffect?,
	Depth: DepthOfFieldEffect?,
	Bloom: BloomEffect?,
	BloomBase: { Intensity: number, Size: number, Threshold: number }?,
	Rumble: any?,
	DoorsHeld: boolean,
	Doors: number,
	Darkness: number,
	Bars: number,
	FadeLevel: number,
	Sounds: { AudioPlayer },
	OneShots: { OneShot },
	Loops: { [string]: Loop },
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

local EVENTS: { Event } = table.clone(EndingCutsceneConfig.Events)
table.sort(EVENTS, function(a: Event, b: Event)
	return a.Time < b.Time
end)

local END_TIME = 0
for _, event in EVENTS do
	if event.Name == "End" then
		END_TIME = event.Time
	end
end

local player = Players.LocalPlayer
local playerGui = GuiBuilderService.GetPlayerGui()
local HideRemote = CommunicationService.Get(EndingConfig.Remotes.Folder, EndingConfig.Remotes.Hide) :: RemoteEvent

local warned: { [string]: boolean } = {}

local function warnOnce(label: string, message: string)
	if warned[label] then return end
	warned[label] = true
	warn(`[EndingCutsceneService] {message}`)
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

	local fade = gui:FindFirstChild(GUI.Fade)
	local vignette = gui:FindFirstChild(GUI.Vignette)
	local letterbox = gui:FindFirstChild(GUI.Letterbox)
	local top = letterbox and letterbox:FindFirstChild(GUI.LetterboxTop)
	local bottom = letterbox and letterbox:FindFirstChild(GUI.LetterboxBottom)
	local caption = gui:FindFirstChild(GUI.Caption)
	local card = gui:FindFirstChild(GUI.Card)
	local title = card and card:FindFirstChild(GUI.Title)
	local skip = gui:FindFirstChild(GUI.Skip)

	if not (
		fade and fade:IsA("Frame")
		and vignette and vignette:IsA("CanvasGroup")
		and top and top:IsA("Frame")
		and bottom and bottom:IsA("Frame")
		and caption and caption:IsA("TextLabel")
		and title and title:IsA("TextLabel")
		and skip and skip:IsA("CanvasGroup")
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
		CaptionTransparency = caption.TextTransparency,
		TitleTransparency = title.TextTransparency,
		Skip = skip,
		Labels = {
			[GUI.Caption] = caption,
			[GUI.Title] = title,
		},
	}
end

local ui = bindUi()
if not ui then
	warn("[EndingCutsceneService] StarterGui.EndingCutsceneGui is missing or misshapen; the ending cutscene is disabled")
	return EndingCutsceneService
end
local UI = ui :: Ui

local skipPill = KeyPill.new(UI.Skip, {
	KeyboardLabel = SKIP.Keyboard,
	GamepadLabel = SKIP.Gamepad,
	Action = TEXT.Skip,
	TouchAction = TEXT.SkipTouch,
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
end

resetUi()
UI.Gui.Enabled = false

local function assetsFolder(): Instance?
	local effects = ReplicatedStorage:FindFirstChild("Effects")
	return effects and effects:FindFirstChild(ASSETS.Folder)
end

local function soundFolder(): Instance?
	local sounds = ReplicatedStorage:FindFirstChild("Sounds")
	return sounds and sounds:FindFirstChild(SOUNDS.Folder)
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

local function playCue(current: Session, name: string, gain: number?, extra: { [string]: any }?): AudioPlayer?
	local cue = CUES[name]
	local template, source = cueTemplate(name)
	if not cue or not template or not source then return nil end

	local settings: { [string]: any } = { Volume = source.Volume * (cue.Gain or 1) * (gain or 1) * current.AudioMaster }
	if cue.Speed then
		settings.PlaybackSpeed = source.PlaybackSpeed * cue.Speed
	end
	if extra then
		for property, value in extra do
			settings[property] = value
		end
	end

	local ok, playback = attempt(`Play{name}`, AudioService.Play2D, AudioService, template, false, cue.Bus, settings)
	if not ok or not playback or not playback:IsA("AudioPlayer") then return nil end
	table.insert(current.Sounds, playback)
	table.insert(current.OneShots, { Player = playback, Volume = playback.Volume })
	return playback
end

local function startLoop(current: Session, name: string)
	if current.Loops[name] then return end
	local cue = CUES[name]
	local template, source = cueTemplate(name)
	if not cue or not template or not source then return end

	local ok, playback = attempt(`Loop{name}`, AudioService.Play2D, AudioService, template, true, cue.Bus, { Volume = 0 })
	if not ok or not playback or not playback:IsA("AudioPlayer") then return end
	table.insert(current.Sounds, playback)
	current.Loops[name] = {
		Player = playback,
		Base = source.Volume * (cue.Gain or 1),
		Speed = source.PlaybackSpeed,
		Level = 0,
	}
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

local function findExit(position: Vector3): (Model?, BasePart?)
	local best: Model?, bestThreshold: BasePart? = nil, nil
	local bestDistance = math.huge
	for _, model in CollectionService:GetTagged(ElevatorConfig.Tag) do
		if not model:IsA("Model") or model:GetAttribute(ElevatorConfig.TypeAttribute) ~= ElevatorConfig.ExitType then continue end
		local threshold = model:FindFirstChild(EndingCutsceneConfig.ThresholdName)
		if not threshold or not threshold:IsA("BasePart") then continue end
		local distance = (threshold.Position - position).Magnitude
		if distance < bestDistance then
			best, bestThreshold, bestDistance = model, threshold, distance
		end
	end
	return best, bestThreshold
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

local function buildLines(): { Line }
	local lines: { Line } = {}
	for _, spec in CAPTIONS.Lines do
		local label = UI.Labels[spec.Label]
		local text = TEXT[spec.Text]
		if not label or type(text) ~= "string" then continue end
		if string.find(text, "%s", 1, true) then
			text = string.format(text, player.DisplayName)
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

local function worldKeys(stage: CabinStage.CabinStage): { CameraTrack.Keyframe }
	local keys: { CameraTrack.Keyframe } = {}
	for _, key in CAMERA.Keys do
		local copy = table.clone(key)
		if typeof(copy.Position) == "Vector3" then
			copy.Position = stage:ToWorld(copy.Position)
		end
		if typeof(copy.Focus) == "Vector3" then
			copy.Focus = stage:ToWorld(copy.Focus)
		end
		table.insert(keys, copy)
	end
	return keys
end

local function worldRegion(stage: CabinStage.CabinStage): { Min: Vector3, Max: Vector3 }
	local low, high = LIGHTS.Region.Min, LIGHTS.Region.Max
	local minimum, maximum = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, x in { low.X, high.X } do
		for _, y in { low.Y, high.Y } do
			for _, z in { low.Z, high.Z } do
				local point = stage:ToWorld(Vector3.new(x, y, z))
				minimum = minimum:Min(point)
				maximum = maximum:Max(point)
			end
		end
	end
	return { Min = minimum, Max = maximum }
end

local session: Session? = nil

local restore: (current: Session) -> ()
local finish: (current: Session, showEnd: boolean) -> ()
local runEvent: (current: Session, event: Event) -> ()

local function scheduleLights(current: Session)
	local sweep = current.Sweep
	if not sweep then return end

	attempt("LightSweep:Collect", sweep.Collect, sweep)
	local stage = current.Stage
	local ok, ordered = attempt("LightSweep:Ordered", sweep.Ordered, sweep, stage.Origin.Position)
	if not ok or type(ordered) ~= "table" then return end

	local counts: { [number]: number } = {}
	local kills: { Kill } = {}
	for _, model in ordered :: { Model } do
		local forward = stage:Forward(model:GetPivot().Position)
		for index, band in LIGHTS.Bands do
			if forward > band.Beyond then
				local count = counts[index] or 0
				counts[index] = count + 1
				table.insert(kills, { Time = band.At + count * LIGHTS.Stagger, Model = model, Flicker = band.Flicker })
				break
			end
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

local function handoff(current: Session)
	if current.HandedOff then return end
	current.HandedOff = true
	current.Hold = nil
	current.SkipReady = false
	table.clear(current.SkipHeld)
	skipPill:SetVisible(false)
	attempt("Show end screen", current.Done)
end

local Handlers: { [string]: (current: Session, event: Event) -> () } = {}

Handlers.Cast = function(current)
	current.Stage.Model.Parent = workspace
	local cast = current.Cast
	if cast then
		attempt("Cast:Opening", cast.Opening, cast)
	end
end

Handlers.SkipIn = function(current)
	current.SkipReady = true
	current.LastInputAt = os.clock()
	skipPill:SetDimmed(false)
	skipPill:SetVisible(true)
end

Handlers.DoorsMove = function(current)
	playCue(current, "Doors")
end

Handlers.DuckTheme = function()
	attempt("Duck escape theme", EscapeMusicService.SetDucked, EscapeMusicService, KEY, true)
end

Handlers.Lights = function(current)
	scheduleLights(current)
end

Handlers.Sisters = function(current, event)
	local cast = current.Cast
	if cast then
		cast:SistersStep(event.Step or 1)
	end
end

Handlers.Bang = function(current)
	current.Stage:Burst(STAGE.Dust)
	playCue(current, "Bang")
	attempt("Bang shake", ShakeService.Impulse, ShakeService, SHAKES.Bang)
end

Handlers.Interior = function(current)
	table.clear(current.Kills)
	local cast = current.Cast
	if cast then
		cast:ClearCorridor()
	end
	local sweep = current.Sweep
	if sweep then
		attempt("LightSweep:Restore", sweep.Restore, sweep)
	end
	current.Darkness = 0
end

Handlers.Ride = function(current)
	startLoop(current, "Ride")
	if not current.Rumble then
		local ok, rumble = attempt("Ride rumble", ShakeService.CreateDynamicRumble, ShakeService, 0, SHAKES.Ride)
		if ok then
			current.Rumble = rumble
		end
	end
end

Handlers.Muzak = function(current)
	startLoop(current, "Muzak")
end

Handlers.LookUp = function(current)
	local cast = current.Cast
	if cast then
		cast:Look(CAST.LookUp)
	end
end

Handlers.LookDown = function(current)
	local cast = current.Cast
	if cast then
		cast:Look(CAST.LookDown)
	end
end

Handlers.Flicker = function(current)
	playCue(current, "Flicker")
end

Handlers.Double = function(current, event)
	local cast = current.Cast
	if cast and event.Place then
		cast:DoubleAt(event.Place)
	end
end

Handlers.Notice = function(current)
	playCue(current, "Notice")
end

Handlers.LampOut = function(current)
	playCue(current, "LightOut")
end

Handlers.DoubleHide = function(current)
	local cast = current.Cast
	if cast then
		cast:HideDouble()
	end
end

Handlers.Ding = function(current)
	playCue(current, "Ding")
end

Handlers.Outside = function(current)
	startLoop(current, "Outside")
end

Handlers.MotesIn = function(current)
	current.Stage:SetEmitting(STAGE.Motes, true)
end

Handlers.MotesOut = function(current)
	current.Stage:SetEmitting(STAGE.Motes, false)
end

Handlers.Walk = function(current)
	local cast = current.Cast
	if cast then
		cast:StartWalk()
	end
end

Handlers.Kept = function(current)
	local cast = current.Cast
	if cast then
		cast:Kept()
	end
end

Handlers.Spin = function(current)
	local cast = current.Cast
	if cast then
		cast:SpinDouble()
	end
	playCue(current, "Whip")
end

Handlers.Twitch = function(current, event)
	local cast = current.Cast
	if cast then
		cast:Twitch(event.Duration or 0.3)
	end
end

Handlers.Rise = function(current)
	local cast = current.Cast
	if cast then
		cast:DoubleNeck("Rise")
	end
end

Handlers.Snap = function(current)
	local cast = current.Cast
	if cast then
		cast:DoubleNeck("Snap")
		cast:FloatDouble()
	end
	playCue(current, "Crack")
	playCue(current, "Sting")
	playCue(current, "StingSub")
	attempt("Snap shake", ShakeService.Impulse, ShakeService, SHAKES.Snap)
end

Handlers.Impact = function(current)
	playCue(current, "Impact")
end

Handlers.Handoff = function(current)
	handoff(current)
end

Handlers.End = function(current)
	finish(current, true)
end

function runEvent(current: Session, event: Event)
	local handler = Handlers[event.Name]
	if handler then
		attempt(`Event{event.Name}`, handler, current, event)
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

local function jumpToHandoff(current: Session)
	current.SkipJumped = true
	table.clear(current.Kills)
	local real = os.clock() - current.StartedAt
	while true do
		local event = EVENTS[current.EventIndex]
		if not event or event.Time >= SKIP.To then break end
		current.EventIndex += 1
		if event.Always then
			runEvent(current, event)
		end
	end
	current.ClockBase = SKIP.To
	current.ClockAnchor = real
	current.ClockRate = 1
	current.TrackTime = SKIP.To
end

local function applyFov(current: Session, fov: number)
	local others = CameraFovService:GetOffset() - current.FovOffset
	local offset = fov - current.BaseFov - others
	if math.abs(offset) < EPSILON then
		offset = 0
	end
	CameraFovService:SetOffset(KEY, offset)
	current.FovOffset = offset
end

local function renderCamera(current: Session, time: number, real: number)
	local camera = workspace.CurrentCamera
	if not camera then return end
	current.Camera = camera
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local frame, fov = current.Track:Evaluate(time, real)
	camera.CFrame = frame
	camera.Focus = current.Track:GetFocus(frame)
	applyFov(current, fov)
end

local function renderBloom(current: Session, amount: number)
	local bloom, base, override = current.Bloom, current.BloomBase, current.Override
	if not bloom or not base or not override then return end
	local level = math.clamp(amount, 0, 1)
	override:Set(bloom, "Intensity", base.Intensity + (BLOOM.Intensity - base.Intensity) * level)
	override:Set(bloom, "Size", base.Size + (BLOOM.Size - base.Size) * level)
	override:Set(bloom, "Threshold", base.Threshold + (BLOOM.Threshold - base.Threshold) * level)
end

local function renderGrade(current: Session, time: number)
	local grade = current.Grade
	local fade = math.clamp(math.max(grade:Sample("Fade", time) or 0, current.SkipFade or 0), 0, 1)
	current.FadeLevel = fade
	UI.Fade.BackgroundTransparency = 1 - fade

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
		blur.Size = math.max(grade:Sample("Blur", time) or 0, 0)
	end

	local sweep = current.Sweep
	local darkness = math.clamp(grade:Sample("Darkness", time) or 0, 0, 1)
	if sweep and math.abs(darkness - current.Darkness) > EPSILON then
		current.Darkness = darkness
		attempt("LightSweep:SetAmbient", sweep.SetAmbient, sweep, darkness)
	end

	local doors = math.clamp(grade:Sample("Doors", time) or 0, 0, 1)
	if current.DoorsHeld and math.abs(doors - current.Doors) > 1e-4 then
		current.Doors = doors
		attempt("Doors", ElevatorDoorService.SetOpenness, ElevatorDoorService, current.Exit, doors)
	end

	local stage = current.Stage
	stage:SetLamp(grade:Sample("Lamp", time) or 0)
	stage:SetDaylight(grade:Sample("Daylight", time) or 0, doors)
	stage:SetGlow(grade:Sample("Glow", time) or 0)
	stage:SetNeedle(grade:Sample("Needle", time) or 0)
	renderBloom(current, grade:Sample("Bloom", time) or 0)

	local rumble = current.Rumble
	if rumble then
		attempt("Rumble", rumble.AdjustValue, rumble, (grade:Sample("Rumble", time) or 0) * current.AudioMaster)
	end

	local alpha = math.clamp(grade:Sample("CardAlpha", time) or 0, 0, 1)
	UI.Title.TextTransparency = 1 - alpha * (1 - UI.TitleTransparency)
	UI.Caption.TextTransparency = 1 - (1 - UI.CaptionTransparency) * (1 - (current.SkipFade or 0))
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
	playCue(current, "Type", nil, { PlaybackSpeed = speed * MathService.RandomRange(CUES.Type.PitchMin, CUES.Type.PitchMax) })
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

		local letters = line.Characters
		label.Text = table.concat(letters, "", 1, count) .. CAPTIONS.Caret .. table.concat(letters, "", count + 1)
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

	for name, loop in current.Loops do
		local playback = loop.Player
		if not playback.Parent then continue end
		local spec = LOOPS[name]
		local goal = (grade:Sample(spec.Level, time) or 0) * current.AudioMaster
		loop.Level += (goal - loop.Level) * blend
		playback.Volume = loop.Base * loop.Level * AudioService:GetBus(CUES[name].Bus).Volume
		if spec.Speed then
			playback.PlaybackSpeed = loop.Speed * math.max(grade:Sample(spec.Speed, time) or 1, EPSILON)
		end
	end

	local master = current.AudioMaster
	local oneShots = current.OneShots
	for index = #oneShots, 1, -1 do
		local oneShot = oneShots[index]
		if not oneShot.Player.Parent then
			table.remove(oneShots, index)
		elseif master < 1 then
			oneShot.Player.Volume = oneShot.Volume * master
		end
	end
end

local function beginSkip(current: Session)
	current.Skipping = true
	current.SkipStartedAt = os.clock()
	current.SkipFrom = current.FadeLevel
	current.SkipFade = current.FadeLevel
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
			jumpToHandoff(current)
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
	skipPill:SetDimmed(os.clock() - current.LastInputAt >= SKIP.DimAfter)

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
	local scaled = deltaTime * current.ClockRate
	if current.ClockRate > 0 then
		current.Running += deltaTime
	end
	updateSkip(current, deltaTime)
	if current.Restored then return end

	runEvents(current)
	if current.Restored then return end

	if not current.Skipping then
		runKills(current)
	end

	local time = current.TrackTime
	renderCamera(current, time, real)
	renderGrade(current, time)
	renderLines(current, time)
	renderAudio(current, time, deltaTime)

	local cast = current.Cast
	if cast then
		attempt("Cast:Update", cast.Update, cast, scaled)
	end

	if time >= END_TIME then
		finish(current, true)
	elseif current.Running > END_TIME + EndingCutsceneConfig.Watchdog then
		finish(current, true)
	end
end

local function stopAudio(current: Session)
	for _, playback in current.Sounds do
		if playback.Parent then
			attempt("StopSound", AudioService.StopSound, AudioService, playback)
		end
	end
	table.clear(current.Sounds)
	table.clear(current.OneShots)
	table.clear(current.Loops)

	local rumble = current.Rumble
	current.Rumble = nil
	if rumble then
		attempt("Stop rumble", rumble.Stop, rumble, 0.3)
	end
end

local function release(label: string, callback: (...any) -> ...any, service: any)
	attempt(label, callback, service, KEY, false)
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
		camera.CFrame = current.SavedCFrame
		camera.Focus = current.SavedFocus
		camera.CameraType = current.SavedType
	end)
	attempt("Restore field of view", CameraFovService.SetOffset, CameraFovService, KEY, 0)

	for _, effect in { current.Color, current.Blur, current.Depth } do
		if effect then
			effect:Destroy()
		end
	end
	current.Color, current.Blur, current.Depth = nil, nil, nil

	stopAudio(current)

	local isolation = current.Isolation
	current.Isolation = nil
	if isolation then
		attempt("Isolation:Stop", isolation.Stop, isolation)
		attempt("Isolation:Destroy", isolation.Destroy, isolation)
	end

	table.clear(current.Kills)
	local sweep = current.Sweep
	current.Sweep = nil
	if sweep then
		attempt("LightSweep:Destroy", sweep.Destroy, sweep)
	end

	local cast = current.Cast
	current.Cast = nil
	if cast then
		attempt("Cast:Destroy", cast.Destroy, cast)
	end
	attempt("CabinStage:Destroy", current.Stage.Destroy, current.Stage)

	local override = current.Override
	current.Override = nil
	if override then
		attempt("LocalOverride:Destroy", override.Destroy, override)
	end

	if current.DoorsHeld then
		current.DoorsHeld = false
		attempt("Release doors", ElevatorDoorService.Hold, ElevatorDoorService, current.Exit, false)
	end

	release("Release escape theme", EscapeMusicService.SetDucked, EscapeMusicService)
	release("Release chase music", ChaseMusicService.SetSuppressed, ChaseMusicService)
	release("Release ambience", AmbienceService.Suppress, AmbienceService)
	release("Release observation", EnemyObservationService.SetSuspended, EnemyObservationService)
	release("Release look", LookService.SetSuspended, LookService)
	release("Release voice", VoiceActivityService.SetIncomingMuted, VoiceActivityService)
	release("Release radio", WalkieTalkieService.SetIncomingMuted, WalkieTalkieService)
	release("Release heartbeat", HeartbeatService.SetSuppressed, HeartbeatService)
	release("Release quick unlock", InterfaceService.SetQuickUnlockBlocked, InterfaceService)
	release("Release crouch", CrouchService.SetBlocked, CrouchService)
	release("Release sprint", SprintService.SetSprintBlocked, SprintService)

	ContextActionService:UnbindAction(INPUT.SinkAction)
	ContextActionService:UnbindAction(INPUT.SkipAction)

	local controlModule = current.Controls
	if controlModule then
		attempt("Enable controls", function()
			controlModule:Enable()
		end)
	end
	attempt("Show viewmodel", ViewmodelService.SetCaptureHidden, ViewmodelService, false)

	current.Hold = nil
	local restoreHud = current.RestoreHud
	current.RestoreHud = nil
	if restoreHud then
		attempt("Restore interface", restoreHud)
	end

	skipPill:SetVisible(false)
	skipPill:SetHold(0)
	skipPill:SetDimmed(false)
	resetUi()
	UI.Gui.Enabled = false
end

function finish(current: Session, showEnd: boolean)
	if current.Restored then return end
	local handOff = showEnd and not current.HandedOff
	current.HandedOff = true
	restore(current)
	if handOff then
		attempt("Show end screen", current.Done)
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

local function cloneEffect(folder: Instance?, name: string, className: string): Instance?
	local template = folder and folder:FindFirstChild(name)
	if not template or not template:IsA(className) then
		warnOnce(`Effect{name}`, `ReplicatedStorage.Effects.{ASSETS.Folder}.{ASSETS.Grade}.{name} is missing; that grade layer is skipped`)
		return nil
	end
	local effect = template:Clone()
	effect.Parent = Lighting
	return effect
end

local function createEffects(current: Session)
	local assets = assetsFolder()
	local grade = assets and assets:FindFirstChild(ASSETS.Grade)
	current.Color = cloneEffect(grade, ASSETS.Color, "ColorCorrectionEffect") :: ColorCorrectionEffect?
	current.Blur = cloneEffect(grade, ASSETS.Blur, "BlurEffect") :: BlurEffect?
	current.Depth = cloneEffect(grade, ASSETS.Depth, "DepthOfFieldEffect") :: DepthOfFieldEffect?

	local bloom = Lighting:FindFirstChild(BLOOM.Name)
	if bloom and bloom:IsA("BloomEffect") then
		current.Bloom = bloom
		current.BloomBase = { Intensity = bloom.Intensity, Size = bloom.Size, Threshold = bloom.Threshold }
	end
end

local function connectSession(current: Session)
	local connections = current.Connections
	local function abort()
		finish(current, false)
	end

	connections.Died = current.Humanoid.Died:Connect(abort)
	connections.Removing = player.CharacterRemoving:Connect(abort)
	connections.Ancestry = current.Character.AncestryChanged:Connect(function()
		if not current.Character:IsDescendantOf(workspace) then
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

local function takeOver(current: Session)
	attempt("Close interface", function()
		InterfaceService:Close()
		if InterfaceService:IsMouseUnlocked() then
			InterfaceService:SetMouseUnlocked(false)
		end
	end)
	attempt("Block quick unlock", InterfaceService.SetQuickUnlockBlocked, InterfaceService, KEY, true)
	attempt("Block crouch", CrouchService.SetBlocked, CrouchService, KEY, true)
	attempt("Block sprint", SprintService.SetSprintBlocked, SprintService, KEY, true)
	current.Controls = controls()
	local controlModule = current.Controls
	if controlModule then
		attempt("Disable controls", function()
			controlModule:Disable()
		end)
	end
	attempt("Unequip tools", current.Humanoid.UnequipTools, current.Humanoid)
	attempt("Hide viewmodel", ViewmodelService.SetCaptureHidden, ViewmodelService, true)

	resetUi()
	UI.Gui.Enabled = true
	local exclude: { LayerCollector } = { UI.Gui }
	local endGui = playerGui:FindFirstChild(EndingConfig.Gui)
	if endGui and endGui:IsA("LayerCollector") then
		table.insert(exclude, endGui)
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

	attempt("Suppress chase music", ChaseMusicService.SetSuppressed, ChaseMusicService, KEY, true)
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

	local assets = assetsFolder()
	local animations = assets and assets:FindFirstChild(ASSETS.Animations)
	local castOk, cast = attempt("Cast.new", Cast.new, {
		Stage = current.Stage,
		Character = current.Character,
		Enemies = ReplicatedStorage:FindFirstChild("Enemies"),
		Animations = animations,
		IdleName = ASSETS.Idle,
		WalkName = ASSETS.Walk,
		Parent = current.Stage.Model,
		Settings = CAST,
	})
	if castOk and cast then
		current.Cast = cast
	end

	local sounds = soundFolder()
	local sweepOk, sweep = attempt("LightSweep.new", LightSweep.new, {
		Region = worldRegion(current.Stage),
		Tags = LIGHTS.Tags,
		Override = override,
		Sounds = {
			Flicker = sounds and sounds:FindFirstChild(CUES.Flicker.Name),
			Out = sounds and sounds:FindFirstChild(CUES.LightOut.Name),
		},
		Ambient = LIGHTS.Ambient,
	})
	if sweepOk and sweep then
		current.Sweep = sweep
		attempt("LightSweep:Collect", sweep.Collect, sweep)
	end

	local held = attempt("Hold doors", ElevatorDoorService.Hold, ElevatorDoorService, current.Exit, true)
	current.DoorsHeld = held

	startLoop(current, "Drone")
	startLoop(current, "Heartbeat")

	connectSession(current)

	current.Camera.CameraType = Enum.CameraType.Scriptable
	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value, function()
		local ok, message = pcall(step, current)
		if not ok then
			warn(`[EndingCutsceneService] the cutscene stopped: {message}`)
			finish(current, true)
		end
	end)
end

local function play(done: () -> ()): boolean
	if session then return true end

	local character = player.Character
	local humanoid = CharacterService.GetAliveHumanoid(player)
	local root = CharacterService.GetAliveRoot(player)
	local camera = workspace.CurrentCamera
	if not character or not humanoid or not root or not camera then return false end

	local exit, threshold = findExit(root.Position)
	local assets = assetsFolder()
	local template = assets and assets:FindFirstChild(ASSETS.Stage)
	if not exit or not threshold or not template or not template:IsA("Model") then
		warnOnce("Stage", "the exit elevator or ReplicatedStorage.Effects.EndingCutscene.Stage is missing; the end screen shows without the cutscene")
		return false
	end

	local stageOk, stage = attempt("CabinStage.new", CabinStage.new, {
		Template = template,
		Exit = exit,
		Threshold = threshold,
		Parent = nil,
		Name = EndingCutsceneConfig.StageName,
		LampName = STAGE.Lamp,
		DaylightName = STAGE.Daylight,
		GlowName = STAGE.Glow,
		NeedleName = STAGE.Needle,
		HubName = STAGE.Hub,
		NeedleSweep = STAGE.NeedleSweep,
		LampOff = STAGE.LampOff,
	})
	if not stageOk or not stage then return false end

	local now = os.clock()
	local liveCFrame = camera.CFrame
	local liveFov = camera.FieldOfView
	local baseFov = liveFov - CameraFovService:GetOffset()
	local anchors = {
		Live = liveCFrame.Position,
		LiveFocus = liveCFrame.Position + liveCFrame.LookVector * CAMERA.FocusDistance,
		BaseFov = baseFov,
	}

	local current: Session = {
		Done = done,
		Restored = false,
		HandedOff = false,
		StartedAt = now,
		LastClock = now,
		ClockBase = 0,
		ClockAnchor = 0,
		ClockRate = 1,
		Running = 0,
		TrackTime = 0,
		EventIndex = 1,
		Camera = camera,
		SavedCFrame = liveCFrame,
		SavedFocus = camera.Focus,
		SavedType = if camera.CameraType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else camera.CameraType,
		BaseFov = baseFov,
		FovOffset = 0,
		Track = CameraTrack.new(worldKeys(stage), {
			Handheld = CAMERA.Handheld,
			FocusDistance = CAMERA.FocusDistance,
			Anchors = anchors,
		}),
		Grade = CameraTrack.new(EndingCutsceneConfig.Grade, { Anchors = anchors }),
		Character = character,
		Humanoid = humanoid,
		Exit = exit,
		Stage = stage,
		Cast = nil,
		Sweep = nil,
		Kills = {},
		Controls = nil,
		Hold = nil,
		RestoreHud = nil,
		Override = nil,
		Isolation = nil,
		Color = nil,
		Blur = nil,
		Depth = nil,
		Bloom = nil,
		BloomBase = nil,
		Rumble = nil,
		DoorsHeld = false,
		Doors = -1,
		Darkness = 0,
		Bars = -1,
		FadeLevel = 0,
		Sounds = {},
		OneShots = {},
		Loops = {},
		AudioMaster = 1,
		LastTick = 0,
		Lines = buildLines(),
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
		warn(`[EndingCutsceneService] the take-over failed: {message}`)
		current.HandedOff = true
		restore(current)
		return false
	end
	return true
end

function EndingCutsceneService:IsPlaying(): boolean
	return session ~= nil
end

function EndingCutsceneService:GetTime(): number?
	local current = session
	return if current then current.TrackTime else nil
end

function EndingCutsceneService:SetRate(rate: number)
	local current = session
	if not current or current.Skipping then return end
	current.ClockBase = current.TrackTime
	current.ClockAnchor = os.clock() - current.StartedAt
	current.ClockRate = math.max(rate, 0)
end

HideRemote.OnClientEvent:Connect(function()
	local current = session
	if current then
		finish(current, false)
	end
end)

EndScreenService:SetPrelude(play)

task.spawn(function()
	local assets: { Instance } = {}
	local sounds = soundFolder()
	if sounds then
		table.insert(assets, sounds)
	end
	local folder = assetsFolder()
	local animations = folder and folder:FindFirstChild(ASSETS.Animations)
	if animations then
		table.insert(assets, animations)
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, assets)
end)

return EndingCutsceneService
