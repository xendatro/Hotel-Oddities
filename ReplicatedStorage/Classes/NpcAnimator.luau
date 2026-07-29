--- @class NpcAnimator
--- Drives an R15 NPC's locomotion clips. The animations come from the rig's stock `Animate` script,
--- which holds one `Animation` under each named container (`idle`, `walk`, `run`); that script is
--- disabled so it cannot fight us for control of the Animator. Driving the tracks ourselves is what
--- makes `Pause` possible -- enemies like the Weeping Angel must freeze mid-stride, not snap to idle.
---
--- Shared, because whichever machine simulates a rig has to be the one animating it. The server drives
--- its own enemies, but a `Mimic` handed to a player's client is animated there: the humanoid's speed
--- reaches the server a replication behind, which is long enough for a short step to be over before
--- its clip starts.

local MOVING_THRESHOLD = 0.1 -- studs/s below which the NPC counts as standing still
local RUN_THRESHOLD = 12 -- studs/s at which the walk clip gives way to the run clip
local BASE_SPEED = 16 -- the speed the stock clips are authored for; playback scales against it
local TRANSITION_TIME = 0.2
local EMOTE_STOP_TIME = 0.1 -- snappier than a locomotion change: it is being cut off, not blended out

-- The stock `Animate` containers worth playing on the spot. `ApplyDescription` rewrites these along
-- with everything else, so a mimic wearing someone's avatar waves with their emote pack too.
local EMOTE_CONTAINERS = { "wave", "point", "laugh", "cheer", "dance" }

local NpcAnimator = {}
NpcAnimator.__index = NpcAnimator

export type NpcAnimator = typeof(setmetatable(
	{} :: {
		Humanoid: Humanoid,
		Animator: Animator,
		Animate: Instance,
		Current: AnimationTrack?,
		Tracks: { [string]: AnimationTrack? },
		Emote: AnimationTrack?,
		Emotes: { AnimationTrack },
		Rate: number,
		Paused: boolean,
		_connections: { [string]: RBXScriptConnection? },
	},
	NpcAnimator
))

-- Destroying a track does not stop it: the clip stays on the `Animator` with nothing left holding a
-- reference to it. Harmless when the rig is about to be destroyed too, and not at all harmless when
-- it lives on -- every reload or handoff would weld another layer of animation onto the same rig.
local function unload(tracks: { [any]: AnimationTrack? })
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
end

local function loadTrack(animator: Animator, container: Instance?): AnimationTrack?
	local animation = container and container:FindFirstChildWhichIsA("Animation")
	if not animation then return nil end

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	return track
end

local function loadEmote(animator: Animator, container: Instance?): AnimationTrack?
	local track = loadTrack(animator, container)
	if not track then return nil end

	track.Priority = Enum.AnimationPriority.Action -- over the locomotion clip it stands in
	track.Looped = false
	return track
end

function NpcAnimator.new(model: Model)
	local self = setmetatable({}, NpcAnimator)

	local humanoid = model.Humanoid :: Humanoid
	self.Humanoid = humanoid
	self.Animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	self.Current = nil :: AnimationTrack?
	self.Rate = 1
	self.Paused = false
	self._connections = {}

	self.Emote = nil :: AnimationTrack?

	self.Animate = model.Animate
	self.Animate.Disabled = true
	self.Tracks = self:_loadTracks()
	self.Emotes = self:_loadEmotes()

	return self
end

function NpcAnimator:_loadTracks()
	return {
		Idle = loadTrack(self.Animator, self.Animate:FindFirstChild("idle")),
		Walk = loadTrack(self.Animator, self.Animate:FindFirstChild("walk")),
		Run = loadTrack(self.Animator, self.Animate:FindFirstChild("run")),
	}
end

function NpcAnimator:_loadEmotes()
	local emotes = {}
	for _, name in EMOTE_CONTAINERS do
		local track = loadEmote(self.Animator, self.Animate:FindFirstChild(name))
		if track then
			table.insert(emotes, track)
		end
	end
	return emotes
end

--- Plays a random emote over whatever it is standing in. Refuses while it is moving, already
--- emoting, or held still deliberately -- an emote layered onto a walk is two clips fighting for the
--- same joints, which is the whole reason this lives next to the locomotion rather than beside it.
function NpcAnimator:PlayEmote(): boolean
	if self.Paused or self.Emote or #self.Emotes == 0 then return false end
	if self.Humanoid.MoveDirection.Magnitude > 0 then return false end

	local track = self.Emotes[math.random(#self.Emotes)]
	self.Emote = track
	track.Stopped:Once(function()
		if self.Emote == track then
			self.Emote = nil
		end
	end)
	track:Play(TRANSITION_TIME)
	return true
end

--- Cuts any emote short. Happens on its own the moment the NPC takes a step.
function NpcAnimator:StopEmote()
	if not self.Emote then return end
	self.Emote:Stop(EMOTE_STOP_TIME)
	self.Emote = nil
end

-- Swaps to the clip matching `speed` and scales its playback to match.
function NpcAnimator:_apply(speed: number)
	-- Ahead of the pause check: whatever else is true, an emote does not survive walking.
	if speed >= MOVING_THRESHOLD then
		self:StopEmote()
	end
	if self.Paused then return end

	local track, rate
	if speed < MOVING_THRESHOLD then
		track, rate = self.Tracks.Idle, 1
	elseif speed >= RUN_THRESHOLD then
		track, rate = self.Tracks.Run, speed / BASE_SPEED
	else
		track, rate = self.Tracks.Walk, speed / BASE_SPEED
	end
	if not track then return end

	self.Rate = rate
	if track ~= self.Current then
		if self.Current then
			self.Current:Stop(TRANSITION_TIME)
		end
		self.Current = track
		track:Play(TRANSITION_TIME)
	end
	track:AdjustSpeed(rate)
end

--- Begins reacting to the humanoid's movement. Safe to call again after `Stop`.
function NpcAnimator:Start()
	if self._connections.Running then return end

	self._connections.Running = self.Humanoid.Running:Connect(function(speed: number)
		self:_apply(speed)
	end)
	self:_apply(self.Humanoid.MoveDirection.Magnitude * self.Humanoid.WalkSpeed)
end

--- Stops driving and drops the current clip, handing the rig's animation to whoever simulates it now.
--- `Start` picks it back up.
function NpcAnimator:Stop()
	if self._connections.Running then
		self._connections.Running:Disconnect()
		self._connections.Running = nil
	end

	self:StopEmote()
	if self.Current then
		self.Current:Stop(TRANSITION_TIME)
		self.Current = nil
	end
end

--- Freezes the current clip on its current pose. Movement must be stopped separately.
function NpcAnimator:Pause()
	if self.Paused then return end
	self.Paused = true
	self:StopEmote() -- a stunned enemy waving would be quite the tell
	if self.Current then
		self.Current:AdjustSpeed(0)
	end
end

--- Resumes playback and resyncs to whatever the humanoid is doing now.
function NpcAnimator:Resume()
	if not self.Paused then return end
	self.Paused = false
	self:_apply(self.Humanoid.MoveDirection.Magnitude * self.Humanoid.WalkSpeed)
end

--- Rebuilds the tracks from the rig's current animation set, keeping whatever the NPC was doing.
--- Applying a `HumanoidDescription` rewrites the ids under the `Animate` script, so an NPC that has
--- just put on a player's animation package has to reload before it actually moves like them.
function NpcAnimator:Reload()
	local paused = self.Paused
	self.Emote = nil
	unload(self.Tracks)
	unload(self.Emotes)

	self.Current = nil
	self.Paused = false
	self.Tracks = self:_loadTracks()
	self.Emotes = self:_loadEmotes()

	-- Only pick playback back up if this animator is the one driving: a rig handed to a client is
	-- animated there, and a reload here would put a second clip on it.
	if self._connections.Running then
		self:_apply(self.Humanoid.MoveDirection.Magnitude * self.Humanoid.WalkSpeed)
		if paused then
			self:Pause()
		end
	end
end

function NpcAnimator:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
	unload(self.Tracks)
	unload(self.Emotes)
	self.Tracks = {}
	self.Emotes = {}
	self.Current = nil
	self.Emote = nil
end

return NpcAnimator
