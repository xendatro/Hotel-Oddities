--- The hacking minigames: one CRT screen, one 800x600 canvas, five games that know nothing about
--- each other. This service owns everything that is the same on every screen -- the SurfaceGui, the
--- title bar, EXIT and RESET, the scanlines and the ACCESS GRANTED fanfare -- so a game class only
--- ever has to fill a rectangle and say when it was beaten. The games themselves live in
--- `ReplicatedStorage.Classes.Minigames`, one class per game.
---
--- Which game a computer runs is worked out from where it stands rather than stored on it. Sorting
--- the tagged computers of a maze by their room name and dealing the list out in order guarantees
--- all five appear once per maze without anything having to be authored, and gives the same answer
--- on every machine and after every rejoin.
---
--- Progress is kept in memory, keyed by the model, so a player who backs out of a half-solved board
--- comes back to it. It is deliberately not persisted: the hack is a room-scale puzzle, not a save
--- file, and a server restart is meant to wipe it.
---
--- Games are required in pcall and dropped from the list if they fault. Five modules written apart
--- will not all be healthy at the same moment, and one bad file should cost its own screen rather
--- than every computer in the hotel.
---
--- Minesweeper sits on the bench: MEMORY.EXE was promoted into the deal for every device, because
--- pairs are a friendlier hack than mines whatever the player is holding. The class stays on disk --
--- putting it back is one edit to ORDER -- and `ResolvedFor` remains the seam where any future
--- device-specific swap would go.
---
--- Sound is a palette of named cues rather than a file per noise. Seven built-in `rbxasset://sounds`
--- clips, all verified to load, are pitched into fifteen cues by PlaybackSpeed alone -- which is both
--- how a real 8-bit machine made a scale out of one oscillator and the reason a game can ask for
--- `api.Sound("Tone", 1.5)` and get a note rather than a second asset. Games reach it only through
--- `api.Sound`, so a game class still requires nothing and still knows nothing about the framework.
---
--- What the rest of the game may call:
---   MinigameService.List: { string }            -- the games that loaded, in dealing order
---   MinigameService.Theme: Theme                -- the only palette the games may use
---   MinigameService:GameFor(model): string      -- the game this computer was DEALT
---   MinigameService:ResolvedFor(model): string  -- the game it will actually PLAY on this device
---   MinigameService:Open(model, screen, callbacks)
---   MinigameService:Close()
---   MinigameService:IsOpen(): boolean

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local MinigameService = {}

if not RunService:IsClient() then
	return MinigameService
end

--- Duplicated from ComputerConfig on purpose: the framework and its games are self-contained, so
--- that a minigame can be dropped into any place without dragging the interaction service with it.
local TAG = "HackComputer"

--- The canonical order. `MinigameService.List` is this filtered down to the modules that actually loaded.
local ORDER = { "Memory", "AimTrainer", "Frogger", "Snake", "Simon" }

local CANVAS = Vector2.new(800, 600)
local MARGIN = 8
local TITLE_HEIGHT = 44
local TITLE_GAP = 8
local BUTTON_SIZE = Vector2.new(96, 30)
local BUTTON_GAP = 8
--- How far in from the RIGHT edge of the title bar the buttons stop. Not the few pixels the look would
--- ask for: the CRT bezel mesh stands in front of the screen part and swallows the mouse ray over the
--- outer edges of the canvas -- past roughly 85% of the way across at the top, and the far side and
--- corners with it -- so a button parked in the corner never receives a MouseEnter, let alone a click.
--- At this inset EXIT occupies canvas x 556-652 and RESET x 452-548, both well inside live glass.
local BUTTON_INSET = 140

--- Scanlines: a dark stripe every few rows, faint enough to read through. Drawn as real Frames
--- because there is no texture to lean on and the canvas is small enough to afford them.
local STRIPE_SPACING = 4
local STRIPE_HEIGHT = 2
local STRIPE_TRANSPARENCY = 0.86

--- How long ACCESS GRANTED holds the screen before the session hands back, and how fast it blinks.
local FANFARE_TIME = 1.5
local FANFARE_BLINK = 0.14

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

--- What a game is handed. Nothing else of the framework is reachable from inside a game: no config,
--- no player, no model -- only a rectangle to draw in, the palette, a speaker, and the way to say
--- "won".
export type Api = {
	Complete: () -> (),
	Theme: Theme,
	--- Plays one cue from CUES by name, optionally multiplied in pitch -- 2 is an octave up, 0.5 an
	--- octave down. Fire and forget: it never yields, never errors out into the caller, never returns
	--- a handle, and overlapping plays of the same cue are expected rather than tolerated. A name that
	--- is not in the palette is silently ignored, so a game may ask for a cue that does not exist yet.
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

--- The only colours and the only font any of the five games may use. Consistency across the set is
--- worth more than any one game's flourish, so the palette is handed out rather than chosen.
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

--- Sound ----------------------------------------------------------------------------------------

--- What the whole palette is scaled to before a cue's own weighting and the place's effects bus are
--- folded in. These are feedback for a screen the player is standing at, not events in the room:
--- loud enough to read a click by, quiet enough to be talked over. One number moves the lot.
local MASTER_VOLUME = 0.4

--- The engine's own clips. Every one was loaded through an AudioPlayer in Studio and watched until
--- `IsReady` came back true before anything was written against it, because a cue that silently
--- fails to load is worse than no cue at all; the lengths are what the engine then reported. All of
--- them are short and percussive on purpose, since every one gets pitch-shifted rather than replaced.
---   electronicpingshort  0.72s  the terminal bleep -- carries every tone, jingle and buzz here
---   switch               0.24s  a dry tick
---   clickfast            0.29s  a rounder, softer tick
---   switch3              0.37s  a heavier throw
---   snap                 0.42s  a hard snap
---   bass                 1.01s  a low thud, the only clip in the set with any weight to it
---   splat                0.50s  exactly what it says
local PING = "rbxasset://sounds/electronicpingshort.wav"
local TICK = "rbxasset://sounds/switch.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"
local THROW = "rbxasset://sounds/switch3.wav"
local SNAP = "rbxasset://sounds/snap.wav"
local THUD = "rbxasset://sounds/bass.wav"
local SPLAT = "rbxasset://sounds/splat.wav"

type Cue = {
	Asset: string,
	--- Weight against MASTER_VOLUME, so one cue can be sat under another without moving the whole set.
	Volume: number,
	Pitch: number,
	--- The notes after the first, each `{ pitch multiplier, seconds late }`. This is where the jingles
	--- live: one clip, a few PlaybackSpeeds and a couple of delays make an arpeggio, which is how the
	--- machines these screens are pretending to be made music out of one oscillator in the first place.
	Notes: { { number } }?,
}

--- The named cues, and the only vocabulary a game has. Deliberately generic names -- a game asks for
--- a Chime, not for its own chime -- so that five games written apart still sound like one machine.
local CUES: { [string]: Cue } = {
	--- The framework's own four.
	Open = { Asset = PING, Volume = 0.9, Pitch = 0.75, Notes = { { 1.5, 0.08 } } },
	Close = { Asset = PING, Volume = 0.8, Pitch = 1.4, Notes = { { 0.7, 0.08 } } },
	Click = { Asset = TICK, Volume = 1, Pitch = 1.7 },
	--- Four notes up a major arpeggio, under the blinking ACCESS GRANTED. Every game's win is this
	--- one, which is why no game plays a victory sound of its own.
	Win = {
		Asset = PING,
		Volume = 1,
		Pitch = 1,
		Notes = { { 1.25, 0.11 }, { 1.5, 0.22 }, { 2, 0.33 } },
	},

	--- The games'.
	Blip = { Asset = TICK, Volume = 0.6, Pitch = 2.1 },
	Flag = { Asset = CLICK, Volume = 0.9, Pitch = 1.4 },
	Flip = { Asset = THROW, Volume = 0.7, Pitch = 1.5 },
	Hop = { Asset = SNAP, Volume = 0.5, Pitch = 1.8 },
	Splat = { Asset = SPLAT, Volume = 0.9, Pitch = 0.9 },
	Boom = { Asset = THUD, Volume = 1, Pitch = 0.6 },
	Hit = { Asset = PING, Volume = 0.7, Pitch = 1.5 },
	Eat = { Asset = PING, Volume = 0.6, Pitch = 1 },
	--- Two notes up: something small went right.
	Chime = { Asset = PING, Volume = 0.7, Pitch = 1.5, Notes = { { 2, 0.07 } } },
	--- Two notes down, and low enough to be felt rather than heard as a pitch: something went wrong.
	Buzz = { Asset = PING, Volume = 0.8, Pitch = 0.55, Notes = { { 0.42, 0.09 } } },
	--- The bare bleep, for the one game that wants to choose its own notes. SIMON.EXE pitches this by
	--- 1, 1.25, 1.5 and 2 to give its four pads four voices out of a single clip.
	Tone = { Asset = PING, Volume = 0.8, Pitch = 1 },
}

--- The graph, in the new audio API rather than Sound instances:
---
---   AudioPlayer (several per clip) --Wire--> AudioEqualizer --Wire--> AudioDeviceOutput
---
--- The equalizer is the retro voice and the reason there is a mixing stage at all. Scooping the bass
--- out and rolling the top off leaves the mids, which is what a bleep coming out of a small cheap
--- speaker in a beige box actually sounds like -- and it costs one instance for the whole palette
--- instead of a differently-mangled clip per cue.
local EQ_LOW_GAIN = -8
local EQ_MID_GAIN = 3
local EQ_HIGH_GAIN = -5

--- How many players one clip may have sounding at once, and how long a player is held busy after it
--- starts. The hold is comfortably past the longest cue at the lowest pitch anything asks for, so a
--- voice is only ever stolen from someone genuinely hammering one sound.
local VOICES_PER_CLIP = 4
local VOICE_HOLD = 2.5

type Voice = {
	Player: AudioPlayer,
	--- When this player may be handed out again, on the `os.clock` scale.
	FreeAt: number,
}

local audioRoot: Folder? = nil
local audioInput: AudioEqualizer? = nil
local voices: { [string]: { Voice } } = {}
local sfxBus: AudioFader? = nil

--- The player's own effects volume, if this place keeps a mixer. Read fresh per cue rather than
--- subscribed to: these are one-shots a fraction of a second long, so the value at the moment one
--- starts is the only value it will ever need. No bus means full volume, which is what keeps the
--- framework droppable into a place that has no mixer at all.
local function busVolume(): number
	if not sfxBus or not sfxBus.Parent then
		local buses = workspace:FindFirstChild("Sounds")
		local fader = buses and buses:FindFirstChild("SFX")
		sfxBus = if fader and fader:IsA("AudioFader") then fader else nil
	end
	return if sfxBus then (sfxBus :: AudioFader).Volume else 1
end

--- A player already holding `asset`, free or freeable. The pools are per clip rather than one shared
--- pool because a player handed a new Asset throws away the clip it had decoded, and the next click
--- would get silence while it loaded again.
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
		-- The wire lives under its source, so a player that ever goes takes its connection with it.
		wire.Parent = audioPlayer

		table.insert(pool, { Player = audioPlayer, FreeAt = now + VOICE_HOLD })
		return audioPlayer
	end

	-- Every voice is still sounding, so the one nearest the end of its hold gives way. Cutting the
	-- oldest note of a chord is what the hardware being imitated did about this too.
	if oldest then
		local voice = oldest :: Voice
		voice.FreeAt = now + VOICE_HOLD
		return voice.Player
	end
	return nil
end

--- Builds the graph on the first cue and hands back the node every player wires into. Lazy, because
--- a client who never walks up to a computer should never own any of this; kept afterwards, because
--- tearing it down between sessions would mean decoding every clip again on the next one.
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
		-- Nothing is pointed at a player here: `AudioDeviceOutput.Player` is read-only, and an output
		-- built on the client is already this client's speakers. The server never reaches this file.
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

	-- Every clip in the palette gets a player the moment the graph exists and is handed straight back
	-- to the pool, so the first click of a session is not the one that has to wait for a decode.
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

	-- Stop first: a stolen voice is still sounding, and restarting it from the top is the point.
	audioPlayer:Stop()
	audioPlayer.Volume = volume
	-- Pitch and speed are one knob on a sampler, which is the whole trick here: the bleep becomes a
	-- scale, and the thud dropped most of an octave becomes an explosion. Clamped because the pitch a
	-- game passes in is usually a streak counter, and a streak has no upper bound.
	audioPlayer.PlaybackSpeed = math.clamp(pitch, 0.2, 4)
	audioPlayer.TimePosition = 0
	audioPlayer:Play()
end

--- Plays one named cue. Never yields and never throws: audio is the one part of this framework that
--- is allowed to fail quietly, because a screen that has lost its speakers must still be playable.
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

--- Loading the games ----------------------------------------------------------------------------

--- Runs something a game module owns without letting a fault in it take the session with it. The
--- player must always be able to walk away from a computer, however badly the game behaves.
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

--- One game class, or nil if it is missing, still being written, or throws on require. Every game is
--- loaded through here, the substitute included, so a half-written file costs its own screen and
--- nothing else.
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
	-- A module that would not load simply is not dealt out.
	if not module then continue end

	Modules[id] = module
	table.insert(List, id)
end

MinigameService.List = List

--- Saved state ----------------------------------------------------------------------------------

--- Session-lifetime progress, keyed by the computer it belongs to and then by the game that produced
--- it. Weak keys on the outer table so a maze that is torn down takes its half-finished boards with it
--- instead of pinning the models forever.
---
--- The second key means one computer can hold snapshots for different games at once, so a future
--- device-specific swap (or a reshuffled deal) can never hand one game's board to another.
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

--- Assignment ------------------------------------------------------------------------------------

--- The maze a computer belongs to, or the workspace when it stands outside one. Everything dealt
--- from the same ancestor gets a different game, which is what makes "all five, once each" true.
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

--- What a computer sorts by: the room it stands in. Room names are unique and stable, so every
--- machine deals the same hand without anyone having to agree on anything first.
local function sortKey(model: Model): string
	local parent = model.Parent
	return if parent then parent.Name else model.Name
end

--- Which game `model` is DEALT. Deterministic: same answer on every client, every join, forever, and
--- deliberately unaffected by what the device in front of it can play -- see `ResolvedFor` for that.
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

	-- A computer asked about before the server's tag has replicated still deserves an answer, and
	-- the same one it will get a moment later once it is in the list.
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

--- Which game `model` actually plays here and now. Today that is simply the deal -- every game in
--- ORDER is playable on every device -- but this stays the seam for any future device-specific swap,
--- so read this rather than `GameFor` anywhere a player is about to be shown something.
function MinigameService:ResolvedFor(model: Model): string
	return self:GameFor(model)
end

--- Chrome ---------------------------------------------------------------------------------------

local function addStroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	-- Border rather than Contextual: a chunky edge that stays outside the fill is the whole look.
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

	-- Inverting on hover reads as a press on a screen with no shadows and no gradients to lean on.
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

--- The stripe overlay. Never `Active`, and neither are its stripes, so every click falls straight
--- through to the game underneath it.
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

--- Sessions -------------------------------------------------------------------------------------

type Session = {
	Model: Model,
	--- The game actually being played, which is not always the one the computer was dealt. Progress is
	--- filed under it rather than under the model alone.
	Id: string,
	Callbacks: Callbacks,
	Gui: SurfaceGui,
	Game: Game?,
	Connections: { RBXScriptConnection },
	Fanfare: Frame,
	FanfareLabel: TextLabel,
	--- Set the moment the fanfare starts: the board is finished, so nothing about it is worth
	--- keeping and a teardown mid-fanfare must not write it back over the cleared slot.
	Won: boolean,
}

local current: Session? = nil

--- ACCESS GRANTED, held for a beat and then handed back. Only ever the player's own win: hacking is
--- per player, so nobody else can finish this board out from under them.
local function beginFanfare(session: Session)
	if session.Won then return end
	session.Won = true

	-- The one victory sound in the set, played here rather than by the game that earned it, so that
	-- no game has to own an ending and none of them can double up on this one.
	playCue("Win")

	session.Fanfare.Visible = true
	-- The overlay is Active, so the last click of a won game cannot land on a game that is over.
	session.Fanfare.Active = true

	local blink = 0
	table.insert(
		session.Connections,
		RunService.Heartbeat:Connect(function(deltaTime: number)
			blink += deltaTime
			session.FanfareLabel.Visible = (blink % (FANFARE_BLINK * 2)) < FANFARE_BLINK
		end)
	)

	task.delay(FANFARE_TIME, function()
		-- A session that ended on its own -- death, teardown, the player leaving -- has already had
		-- its callbacks settled, and must not get a second ending here.
		if current ~= session then return end

		local onComplete = session.Callbacks.OnComplete
		MinigameService:Close()
		onComplete()
	end)
end

--- Whether a computer's screen is currently being played.
function MinigameService:IsOpen(): boolean
	return current ~= nil
end

--- Tears the session down and remembers where the game had got to. Deliberately silent: the caller
--- that asked for this already knows, and the exit callback belongs to the player's own choice.
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
			-- A computer this player has hacked is inert from here on; there is nothing left to resume,
			-- on any device.
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

--- Puts a game on `screen` and plays it. `callbacks.OnExit` fires when the player walks away,
--- `callbacks.OnComplete` after the win has finished being celebrated; both arrive with the screen
--- already torn down, so the caller only has to give the camera back.
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

	-- Resolved, not dealt: the phone standing in front of this computer may not be able to play what it
	-- was dealt, and the answer is settled here, once, for everything the session then does with it.
	local id = self:ResolvedFor(model)
	local module = Modules[id]
	if not module then
		warn(`MinigameService: {id} is not loaded, nothing to play on {model:GetFullName()}`)
		callbacks.OnExit()
		return
	end

	--- The surface ------------------------------------------------------------------------------

	local gui = Instance.new("SurfaceGui")
	gui.Name = "MinigameGui"
	gui.Adornee = screen
	-- The screen part is authored with its Front pointing out at the player.
	gui.Face = Enum.NormalId.Front
	-- Fixed pixels rather than pixels-per-stud: the games are laid out against an exact 800x600, and
	-- a screen part that is resized later should stretch that canvas, not crop it.
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	-- Only read if the sizing mode is ever flipped back; sized for the ~2.25-stud-wide screen.
	gui.PixelsPerStud = 356
	-- Drawn over everything for the length of a session. Normally a screen is a real object in the room
	-- and should be occluded by the wall in front of it, but while this gui exists the camera is pinned
	-- a stud from the glass with nothing between the two, so there is nothing left for occlusion to do
	-- -- and this is what keeps the hotel's darkness and its post-processing from dimming a board the
	-- player is being asked to read. LightInfluence 0 alone does not survive the colour correction.
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	-- Lifted a hair off the Neon face so the two do not fight over the same pixels.
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

	--- Title bar --------------------------------------------------------------------------------

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

	-- The title bar reads: title from the left, then RESET, then EXIT, with the last BUTTON_INSET
	-- pixels of the bar left empty because the bezel in front of the screen eats input there.
	local exit = makeButton("Exit", "EXIT", Theme.Danger)
	exit.Position = UDim2.new(1, -BUTTON_INSET, 0.5, 0)
	exit.ZIndex = 3
	exit.Parent = titleBar

	--- The game --------------------------------------------------------------------------------

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

	--- The fanfare -----------------------------------------------------------------------------

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

	--- Wiring ----------------------------------------------------------------------------------

	local session: Session = {
		Model = model,
		Id = id,
		Callbacks = callbacks,
		Gui = gui,
		Game = nil,
		Connections = {},
		Fanfare = fanfare,
		FanfareLabel = granted,
		Won = false,
	}
	current = session

	exit.MouseButton1Click:Connect(function()
		if current ~= session or session.Won then return end
		-- Before the teardown, not after: `Close` is silent by design, and this cue belongs to the
		-- button the player pressed rather than to the session ending.
		playCue("Close")
		local onExit = session.Callbacks.OnExit
		self:Close()
		onExit()
	end)

	local api: Api = {
		Theme = Theme,
		Complete = function()
			-- Late or repeated wins are ignored rather than trusted; the fanfare guards itself too.
			if current ~= session then return end
			beginFanfare(session)
		end,
		Sound = function(name: string, pitch: number?)
			-- A game torn down mid-hop can still have a queued callback holding this closure, and a
			-- noise from a screen that is no longer on the wall would be a ghost.
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
			playCue("Click")
			safe(`{id}.Reset`, function()
				playing:Reset()
			end)
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

	-- The terminal waking up, and the first thing to build the audio graph on this client. Only once
	-- the game is actually on the screen: a session that faulted its way back out never made a sound.
	playCue("Open")
end

return MinigameService
