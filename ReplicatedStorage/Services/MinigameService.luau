local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local MinigameService = {}

if not RunService:IsClient() then
	return MinigameService
end

local TAG = "HackComputer"

local ORDER = { "Memory", "AimTrainer", "Frogger", "Snake", "Simon" }

local CANVAS = Vector2.new(800, 600)
local MARGIN = 8
local TITLE_HEIGHT = 44
local TITLE_GAP = 8
local BUTTON_SIZE = Vector2.new(96, 30)
local BUTTON_GAP = 8
local BUTTON_INSET = 140

local STRIPE_SPACING = 4
local STRIPE_HEIGHT = 2
local STRIPE_TRANSPARENCY = 0.86

local FANFARE_TIME = 1.5
local FANFARE_BLINK = 0.14

local NOTICE_TIME = 0.95

export type Theme = {
	Font: Enum.Font,
	Background: Color3,
	Panel: Color3,
	Grid: Color3,
	Primary: Color3,
	Accent: Color3,
	Danger: Color3,
	Text: Color3,
	TextDim: Color3,
}

export type Api = {
	Complete: () -> (),
	Fail: (reason: string?) -> (),
	Theme: Theme,
	Sound: (name: string, pitch: number?) -> (),
}

export type Game = {
	Start: (self: any, saved: any?) -> (),
	Serialize: (self: any) -> any?,
	Reset: (self: any) -> (),
	Destroy: (self: any) -> (),
}

export type Module = {
	Id: string,
	Title: string,
	SupportsReset: boolean,
	new: (root: Frame, api: Api) -> Game,
}

export type Callbacks = {
	OnExit: () -> (),
	OnComplete: () -> (),
}

local Theme: Theme = {
	Font = Enum.Font.Arcade,
	Background = Color3.fromRGB(6, 12, 24),
	Panel = Color3.fromRGB(12, 24, 44),
	Grid = Color3.fromRGB(24, 44, 76),
	Primary = Color3.fromRGB(0, 200, 255),
	Accent = Color3.fromRGB(96, 255, 128),
	Danger = Color3.fromRGB(255, 80, 96),
	Text = Color3.fromRGB(220, 236, 255),
	TextDim = Color3.fromRGB(120, 150, 190),
}

MinigameService.Theme = Theme

local player = Players.LocalPlayer

local MASTER_VOLUME = 0.4

local PING = "rbxasset://sounds/electronicpingshort.wav"
local TICK = "rbxasset://sounds/switch.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local THROW = "rbxasset://sounds/switch3.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local THUD = "rbxasset://sounds/bass.wav"
local SPLAT = "rbxasset://sounds/splat.wav"

type Cue = {
	Asset: string,
	Volume: number,
	Pitch: number,
	Notes: { { number } }?,
}

local CUES: { [string]: Cue } = {
	Open = { Asset = PING, Volume = 0.9, Pitch = 0.75, Notes = { { 1.5, 0.08 } } },
	Close = { Asset = PING, Volume = 0.8, Pitch = 1.4, Notes = { { 0.7, 0.08 } } },
	Click = { Asset = TICK, Volume = 1, Pitch = 1.7 },
	Win = {
		Asset = PING,
		Volume = 1,
		Pitch = 1,
		Notes = { { 1.25, 0.11 }, { 1.5, 0.22 }, { 2, 0.33 } },
	},
	Deny = {
		Asset = PING,
		Volume = 0.9,
		Pitch = 0.9,
		Notes = { { 0.72, 0.1 }, { 0.55, 0.2 } },
	},

	Blip = { Asset = TICK, Volume = 0.6, Pitch = 2.1 },
	Flag = { Asset = CLICK, Volume = 0.9, Pitch = 1.4 },
	Flip = { Asset = THROW, Volume = 0.7, Pitch = 1.5 },
	Hop = { Asset = SNAP, Volume = 0.5, Pitch = 1.8 },
	Splat = { Asset = SPLAT, Volume = 0.9, Pitch = 0.9 },
	Boom = { Asset = THUD, Volume = 1, Pitch = 0.6 },
	Hit = { Asset = PING, Volume = 0.7, Pitch = 1.5 },
	Eat = { Asset = PING, Volume = 0.6, Pitch = 1 },
	Chime = { Asset = PING, Volume = 0.7, Pitch = 1.5, Notes = { { 2, 0.07 } } },
	Buzz = { Asset = PING, Volume = 0.8, Pitch = 0.55, Notes = { { 0.42, 0.09 } } },
	Tone = { Asset = PING, Volume = 0.8, Pitch = 1 },
}

local EQ_LOW_GAIN = -8
local EQ_MID_GAIN = 3
local EQ_HIGH_GAIN = -5

local VOICES_PER_CLIP = 4
local VOICE_HOLD = 2.5

type Voice = {
	Player: AudioPlayer,
	FreeAt: number,
}

local audioRoot: Folder? = nil
local audioInput: AudioEqualizer? = nil
local voices: { [string]: { Voice } } = {}
local sfxBus: AudioFader? = nil

local function busVolume(): number
	if not sfxBus or not sfxBus.Parent then
		local buses = workspace:FindFirstChild("Sounds")
		local fader = buses and buses:FindFirstChild("SFX")
		sfxBus = if fader and fader:IsA("AudioFader") then fader else nil
	end
	return if sfxBus then (sfxBus :: AudioFader).Volume else 1
end

local function voiceFor(asset: string, target: AudioEqualizer): AudioPlayer?
	local pool = voices[asset]
	if not pool then
		pool = {}
		voices[asset] = pool
	end

	local now = os.clock()
	local oldest: Voice? = nil

	for _, voice in pool do
		if voice.FreeAt <= now then
			voice.FreeAt = now + VOICE_HOLD
			return voice.Player
		end
		if not oldest or voice.FreeAt < (oldest :: Voice).FreeAt then
			oldest = voice
		end
	end

	if #pool < VOICES_PER_CLIP then
		local audioPlayer = Instance.new("AudioPlayer")
		audioPlayer.Asset = asset
		audioPlayer.Parent = audioRoot

		local wire = Instance.new("Wire")
		wire.SourceInstance = audioPlayer
		wire.TargetInstance = target
		wire.Parent = audioPlayer

		table.insert(pool, { Player = audioPlayer, FreeAt = now + VOICE_HOLD })
		return audioPlayer
	end

	if oldest then
		local voice = oldest :: Voice
		voice.FreeAt = now + VOICE_HOLD
		return voice.Player
	end
	return nil
end

local function audioTarget(): AudioEqualizer?
	if audioInput then return audioInput end

	local ok, result = pcall(function(): AudioEqualizer
		local root = Instance.new("Folder")
		root.Name = "MinigameAudio"

		local equalizer = Instance.new("AudioEqualizer")
		equalizer.LowGain = EQ_LOW_GAIN
		equalizer.MidGain = EQ_MID_GAIN
		equalizer.HighGain = EQ_HIGH_GAIN
		equalizer.Parent = root

		local output = Instance.new("AudioDeviceOutput")
		output.Parent = root

		local wire = Instance.new("Wire")
		wire.SourceInstance = equalizer
		wire.TargetInstance = output
		wire.Parent = equalizer

		root.Parent = SoundService
		audioRoot = root
		return equalizer
	end)

	if not ok then
		warn(`MinigameService: no audio graph -- {result}`)
		return nil
	end

	audioInput = result :: AudioEqualizer

	for _, cue in CUES do
		if voices[cue.Asset] then continue end
		voiceFor(cue.Asset, audioInput :: AudioEqualizer)
		local pool = voices[cue.Asset]
		if pool and pool[1] then
			pool[1].FreeAt = 0
		end
	end

	return audioInput
end

local function playNote(asset: string, volume: number, pitch: number)
	local target = audioTarget()
	if not target then return end

	local audioPlayer = voiceFor(asset, target)
	if not audioPlayer then return end

	audioPlayer:Stop()
	audioPlayer.Volume = volume
	audioPlayer.PlaybackSpeed = math.clamp(pitch, 0.2, 4)
	audioPlayer.TimePosition = 0
	audioPlayer:Play()
end

local function playCue(name: string, pitch: number?)
	local cue = CUES[name]
	if not cue then return end

	local ok, err = pcall(function()
		local volume = MASTER_VOLUME * cue.Volume * busVolume()
		local base = cue.Pitch * (pitch or 1)

		playNote(cue.Asset, volume, base)

		local notes = cue.Notes
		if not notes then return end
		for _, note in notes do
			task.delay(note[2], function()
				pcall(playNote, cue.Asset, volume, base * note[1])
			end)
		end
	end)

	if not ok then
		warn(`MinigameService: cue {name} failed -- {err}`)
	end
end

local function safe(label: string, fn: () -> any): (boolean, any)
	local ok, result = pcall(fn)
	if not ok then
		warn(`MinigameService: {label} failed -- {result}`)
	end
	return ok, result
end

local Modules: { [string]: Module } = {}
local List: { string } = {}

local classes = ReplicatedStorage.Classes:FindFirstChild("Minigames")

local function loadModule(id: string): Module?
	local ok, module = pcall(function()
		return require((classes :: any)[id]) :: Module
	end)

	if not ok then
		warn(`MinigameService: {id} could not be loaded -- {module}`)
		return nil
	end
	if typeof(module) ~= "table" or typeof(module.new) ~= "function" then
		warn(`MinigameService: {id} does not look like a game module`)
		return nil
	end

	return module
end

for _, id in ORDER do
	local module = loadModule(id)
	if not module then continue end

	Modules[id] = module
	table.insert(List, id)
end

MinigameService.List = List

local Saved: { [Model]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any

local function savedFor(model: Model, id: string): any
	local byGame = Saved[model]
	return if byGame then byGame[id] else nil
end

local function setSaved(model: Model, id: string, snapshot: any)
	local byGame = Saved[model]
	if not byGame then
		if snapshot == nil then return end
		byGame = {}
		Saved[model] = byGame
	end
	byGame[id] = snapshot
end

local function mazeOf(model: Instance): Instance
	local instance: Instance? = model
	while instance and instance ~= workspace do
		if instance.Name:match("^Maze%d+") then
			return instance
		end
		instance = instance.Parent
	end
	return workspace
end

local function sortKey(model: Model): string
	local parent = model.Parent
	return if parent then parent.Name else model.Name
end

function MinigameService:GameFor(model: Model): string
	if #List == 0 then
		return ORDER[1]
	end

	local maze = mazeOf(model)
	local peers: { Model } = {}
	local listed = false

	for _, tagged in CollectionService:GetTagged(TAG) do
		if not tagged:IsA("Model") or not tagged:IsDescendantOf(maze) then continue end
		table.insert(peers, tagged)
		if tagged == model then
			listed = true
		end
	end

	if not listed then
		table.insert(peers, model)
	end

	table.sort(peers, function(a: Model, b: Model): boolean
		local left, right = sortKey(a), sortKey(b)
		if left == right then
			return a:GetFullName() < b:GetFullName()
		end
		return left < right
	end)

	local index = table.find(peers, model) or 1
	return List[(index - 1) % #List + 1]
end

function MinigameService:ResolvedFor(model: Model): string
	return self:GameFor(model)
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

local function makeButton(name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(BUTTON_SIZE.X, BUTTON_SIZE.Y)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.BackgroundColor3 = Theme.Background
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Theme.Font
	button.Text = text
	button.TextSize = 22
	button.TextColor3 = color
	addStroke(button, color, 2)

	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = color
		button.TextColor3 = Theme.Background
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Theme.Background
		button.TextColor3 = color
	end)

	return button
end

local function buildScanlines(parent: Frame): Frame
	local overlay = Instance.new("Frame")
	overlay.Name = "Scanlines"
	overlay.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
	overlay.BackgroundTransparency = 1
	overlay.Active = false
	overlay.ZIndex = 5
	overlay.Parent = parent

	for y = 0, CANVAS.Y - STRIPE_HEIGHT, STRIPE_SPACING do
		local stripe = Instance.new("Frame")
		stripe.Name = "Line"
		stripe.Position = UDim2.fromOffset(0, y)
		stripe.Size = UDim2.fromOffset(CANVAS.X, STRIPE_HEIGHT)
		stripe.BackgroundColor3 = Color3.new(0, 0, 0)
		stripe.BackgroundTransparency = STRIPE_TRANSPARENCY
		stripe.BorderSizePixel = 0
		stripe.Active = false
		stripe.ZIndex = 5
		stripe.Parent = overlay
	end

	return overlay
end

type Session = {
	Model: Model,
	Id: string,
	Callbacks: Callbacks,
	Gui: SurfaceGui,
	Game: Game?,
	Connections: { RBXScriptConnection },
	Fanfare: Frame,
	FanfareLabel: TextLabel,
	Notice: Frame,
	NoticeTitle: TextLabel,
	NoticeReason: TextLabel,
	NoticeGeneration: number,
	Won: boolean,
}

local current: Session? = nil

local function showNotice(session: Session, title: string, reason: string)
	if session.Won then return end

	playCue("Deny")

	session.NoticeTitle.Text = title
	session.NoticeReason.Text = reason
	session.Notice.Visible = true
	session.Notice.Active = true

	session.NoticeGeneration += 1
	local generation = session.NoticeGeneration

	task.delay(NOTICE_TIME, function()
		if current ~= session or session.NoticeGeneration ~= generation then return end
		session.Notice.Visible = false
		session.Notice.Active = false
	end)
end

local function beginFanfare(session: Session)
	if session.Won then return end
	session.Won = true

	playCue("Win")

	session.NoticeGeneration += 1
	session.Notice.Visible = false
	session.Notice.Active = false

	session.Fanfare.Visible = true
	session.Fanfare.Active = true

	local blink = 0
	table.insert(
		session.Connections,
		RunService.Heartbeat:Connect(function(deltaTime: number)
			blink += deltaTime
			session.FanfareLabel.Visible = (blink % (FANFARE_BLINK * 2)) < FANFARE_BLINK
		end)
	)

	task.spawn(session.Callbacks.OnComplete)

	task.delay(FANFARE_TIME, function()
		if current ~= session then return end

		local onExit = session.Callbacks.OnExit
		MinigameService:Close()
		onExit()
	end)
end

function MinigameService:IsOpen(): boolean
	return current ~= nil
end

function MinigameService:Close()
	local session = current
	if not session then return end
	current = nil

	for _, connection in session.Connections do
		connection:Disconnect()
	end
	table.clear(session.Connections)

	local instance = session.Game
	if instance then
		if session.Won then
			Saved[session.Model] = nil
		else
			local ok, snapshot = safe("Serialize", function()
				return instance:Serialize()
			end)
			setSaved(session.Model, session.Id, if ok then snapshot else nil)
		end

		safe("Destroy", function()
			instance:Destroy()
		end)
	end

	session.Gui:Destroy()
end

function MinigameService:Open(model: Model, screen: BasePart, callbacks: Callbacks)
	self:Close()

	if not player then
		warn("MinigameService: Open is client-only")
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
		or player:WaitForChild("PlayerGui", 10) :: PlayerGui?
	if not playerGui then
		warn("MinigameService: no PlayerGui to draw on")
		callbacks.OnExit()
		return
	end

	local id = self:ResolvedFor(model)
	local module = Modules[id]
	if not module then
		warn(`MinigameService: {id} is not loaded, nothing to play on {model:GetFullName()}`)
		callbacks.OnExit()
		return
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "MinigameGui"
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	gui.PixelsPerStud = 356
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ZOffset = 0.01
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ResetOnSpawn = false
	gui.Parent = playerGui

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
	backdrop.BackgroundColor3 = Theme.Background
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 1
	backdrop.Parent = gui

	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Position = UDim2.fromOffset(MARGIN, MARGIN)
	titleBar.Size = UDim2.fromOffset(CANVAS.X - MARGIN * 2, TITLE_HEIGHT)
	titleBar.BackgroundColor3 = Theme.Panel
	titleBar.BorderSizePixel = 0
	titleBar.ZIndex = 2
	titleBar.Parent = backdrop
	addStroke(titleBar, Theme.Grid, 2)

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Position = UDim2.fromOffset(12, 0)
	title.Size = UDim2.new(1, -12, 1, 0)
	title.BackgroundTransparency = 1
	title.Font = Theme.Font
	title.Text = module.Title
	title.TextSize = 24
	title.TextColor3 = Theme.Primary
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	title.Parent = titleBar

	local exit = makeButton("Exit", "EXIT", Theme.Danger)
	exit.Position = UDim2.new(1, -BUTTON_INSET, 0.5, 0)
	exit.ZIndex = 3
	exit.Parent = titleBar

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(MARGIN, MARGIN + TITLE_HEIGHT + TITLE_GAP)
	content.Size = UDim2.fromOffset(
		CANVAS.X - MARGIN * 2,
		CANVAS.Y - MARGIN * 2 - TITLE_HEIGHT - TITLE_GAP
	)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.ZIndex = 2
	content.Parent = backdrop

	buildScanlines(backdrop)

	local fanfare = Instance.new("Frame")
	fanfare.Name = "Fanfare"
	fanfare.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
	fanfare.BackgroundColor3 = Theme.Background
	fanfare.BackgroundTransparency = 0.08
	fanfare.BorderSizePixel = 0
	fanfare.Visible = false
	fanfare.Active = false
	fanfare.ZIndex = 10
	fanfare.Parent = backdrop

	local fanfarePanel = Instance.new("Frame")
	fanfarePanel.Name = "Panel"
	fanfarePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	fanfarePanel.Position = UDim2.fromScale(0.5, 0.5)
	fanfarePanel.Size = UDim2.fromOffset(620, 160)
	fanfarePanel.BackgroundColor3 = Theme.Panel
	fanfarePanel.BorderSizePixel = 0
	fanfarePanel.ZIndex = 11
	fanfarePanel.Parent = fanfare
	addStroke(fanfarePanel, Theme.Accent, 3)

	local granted = Instance.new("TextLabel")
	granted.Name = "Granted"
	granted.Size = UDim2.new(1, 0, 0, 96)
	granted.BackgroundTransparency = 1
	granted.Font = Theme.Font
	granted.Text = "ACCESS GRANTED"
	granted.TextSize = 62
	granted.TextColor3 = Theme.Accent
	granted.ZIndex = 12
	granted.Parent = fanfarePanel

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Position = UDim2.fromOffset(0, 96)
	subtitle.Size = UDim2.new(1, 0, 0, 48)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Theme.Font
	subtitle.Text = "SYSTEM COMPROMISED"
	subtitle.TextSize = 24
	subtitle.TextColor3 = Theme.TextDim
	subtitle.ZIndex = 12
	subtitle.Parent = fanfarePanel

	local notice = Instance.new("Frame")
	notice.Name = "Notice"
	notice.Size = UDim2.fromOffset(CANVAS.X, CANVAS.Y)
	notice.BackgroundColor3 = Theme.Background
	notice.BackgroundTransparency = 0.4
	notice.BorderSizePixel = 0
	notice.Visible = false
	notice.Active = false
	notice.ZIndex = 8
	notice.Parent = backdrop

	local noticePanel = Instance.new("Frame")
	noticePanel.Name = "Panel"
	noticePanel.AnchorPoint = Vector2.new(0.5, 0.5)
	noticePanel.Position = UDim2.fromScale(0.5, 0.5)
	noticePanel.Size = UDim2.fromOffset(620, 160)
	noticePanel.BackgroundColor3 = Theme.Panel
	noticePanel.BorderSizePixel = 0
	noticePanel.ZIndex = 9
	noticePanel.Parent = notice
	addStroke(noticePanel, Theme.Danger, 3)

	local denied = Instance.new("TextLabel")
	denied.Name = "Denied"
	denied.Size = UDim2.new(1, 0, 0, 96)
	denied.BackgroundTransparency = 1
	denied.Font = Theme.Font
	denied.Text = "ACCESS DENIED"
	denied.TextSize = 62
	denied.TextColor3 = Theme.Danger
	denied.ZIndex = 9
	denied.Parent = noticePanel

	local noticeReason = Instance.new("TextLabel")
	noticeReason.Name = "Reason"
	noticeReason.Position = UDim2.fromOffset(0, 96)
	noticeReason.Size = UDim2.new(1, 0, 0, 48)
	noticeReason.BackgroundTransparency = 1
	noticeReason.Font = Theme.Font
	noticeReason.Text = "PROGRESS RESET"
	noticeReason.TextSize = 24
	noticeReason.TextColor3 = Theme.TextDim
	noticeReason.ZIndex = 9
	noticeReason.Parent = noticePanel

	local session: Session = {
		Model = model,
		Id = id,
		Callbacks = callbacks,
		Gui = gui,
		Game = nil,
		Connections = {},
		Fanfare = fanfare,
		FanfareLabel = granted,
		Notice = notice,
		NoticeTitle = denied,
		NoticeReason = noticeReason,
		NoticeGeneration = 0,
		Won = false,
	}
	current = session

	exit.MouseButton1Click:Connect(function()
		if current ~= session or session.Won then return end
		playCue("Close")
		local onExit = session.Callbacks.OnExit
		self:Close()
		onExit()
	end)

	local api: Api = {
		Theme = Theme,
		Complete = function()
			if current ~= session then return end
			beginFanfare(session)
		end,
		Fail = function(reason: string?)
			if current ~= session then return end
			showNotice(session, "ACCESS DENIED", reason or "PROGRESS RESET")
		end,
		Sound = function(name: string, pitch: number?)
			if current ~= session then return end
			playCue(name, pitch)
		end,
	}

	local ok, instance = safe(`{id}.new`, function()
		return module.new(content, api)
	end)
	if not ok or typeof(instance) ~= "table" then
		self:Close()
		callbacks.OnExit()
		return
	end

	local playing = instance :: Game
	session.Game = playing

	if module.SupportsReset then
		local reset = makeButton("Reset", "RESET", Theme.Primary)
		reset.Position = UDim2.new(1, -(BUTTON_INSET + BUTTON_SIZE.X + BUTTON_GAP), 0.5, 0)
		reset.ZIndex = 3
		reset.Parent = titleBar

		reset.MouseButton1Click:Connect(function()
			if current ~= session or session.Won then return end
			safe(`{id}.Reset`, function()
				playing:Reset()
			end)
			showNotice(session, "SYSTEM RESET", "PROGRESS CLEARED")
		end)
	end

	local started = safe(`{id}.Start`, function()
		playing:Start(savedFor(model, id))
	end)
	if not started then
		self:Close()
		callbacks.OnExit()
		return
	end

	playCue("Open")
end

return MinigameService
