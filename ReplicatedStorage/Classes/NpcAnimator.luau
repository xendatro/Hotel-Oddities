--- @class NpcAnimator
--- Drives an R15 NPC's locomotion clips. By default the animations come from the rig's stock `Animate`
--- script, which holds one `Animation` under each named container (`idle`, `walk`, `run`); that script
--- is disabled so it cannot fight us for control of the Animator. Driving the tracks ourselves is what
--- makes `Pause` possible -- enemies like the Weeping Angel must freeze mid-stride, not snap to idle.
---
--- An `AnimationConfig.AnimationSet` replaces individual clips by asset id, slot by slot, and adds the
--- attack swings -- which have nowhere to live on a rig, the stock script having no notion of one.
---
--- Shared, because whichever machine simulates a rig has to be the one animating it. The server drives
--- its own enemies, but a `Mimic` handed to a player's client is animated there: the humanoid's speed
--- reaches the server a replication behind, which is long enough for a short step to be over before
--- its clip starts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)

local MOVING_THRESHOLD = 0.1 -- studs/s of *commanded* pace below which the NPC counts as standing still
-- And of *measured* travel. Well clear of what a humanoid reads while it settles onto a floor, and
-- well under any gait, so neither a stationary rig nor a walking one is ever in doubt.
local TRAVEL_THRESHOLD = 1
local RUN_THRESHOLD = 12 -- studs/s of *commanded* pace at which the walk clip gives way to the run clip
local TRANSITION_TIME = 0.2
local IDLE_DELAY = 0.15 -- seconds stopped before an authored idle replaces a held locomotion pose
-- Of the pace it was told to travel at, the slowest a gait may ever be played while it is still trying
-- to move. A rig wedged on a doorframe measures nearly no travel, and a clip rated off that measurement
-- alone stops dead on one frame of a stride -- which reads as the animation having broken rather than
-- as something shoving at a corner.
local MIN_RATE_FRACTION = 0.4

-- Every locomotion clip is one whole gait cycle: one foot out, then the other, then back to the pose
-- it started in. That is what makes a clip's own length enough to place it -- a cycle covers this much
-- ground whatever it looks like, so a long clip is a slow gait and a short one is a quick one, and the
-- playback rate that keeps the feet on the floor follows from the two numbers without anybody having
-- to say what speed the clip was authored at.
--
-- Eight studs a cycle, which is to say two paces of four. Sixteen was the arithmetic answer -- a stock
-- one-second cycle at a player's walk speed -- and it is wrong by exactly a factor of two, which is
-- what a full cycle being read as a single step looks like. Every rig runs against this, the ones
-- animating from their own clips included.
local CYCLE_DISTANCE = 8 -- studs of ground one full cycle covers
-- `AnimationTrack.Length` reads 0 until the asset behind it has loaded, which for a clip named by id is
-- a moment after the NPC starts walking rather than before. The rate is recomputed every frame, so the
-- real length is picked up on its own as soon as it arrives.
local FALLBACK_CYCLE_TIME = 1

local EMOTE_STOP_TIME = 0.1 -- snappier than a locomotion change: it is being cut off, not blended out

-- The stock `Animate` containers worth playing on the spot. `ApplyDescription` rewrites these along
-- with everything else, so a mimic wearing someone's avatar waves with their emote pack too.
local EMOTE_CONTAINERS = { "wave", "hello", "cheer", "dance", "dance2", "dance3", "laugh", "point" }

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
		Set: AnimationConfig.AnimationSet,
		Attacks: { AnimationTrack },
		Rate: number,
		MovementSpeedOverride: number?,
		Paused: boolean,
		_stoppedSince: number?,
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

-- An `Animation` for `assetId`, owned by the track that loads it. Kept out of the rig entirely: the
-- `Animate` containers are the stock clips, and writing over them would leave a reloaded animator
-- unable to tell an authored override from what the rig came with.
local function makeAnimation(assetId: number): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{assetId}`
	return animation
end

-- Prefers the configured clip for this slot, falling back to whatever the rig carries under it.
local function loadTrack(animator: Animator, container: Instance?, assetId: number?): AnimationTrack?
	local animation = if assetId
		then makeAnimation(assetId)
		else container and container:FindFirstChildWhichIsA("Animation")
	if not animation then return nil end

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	return track
end

local function loadEmote(animator: Animator, animation: Animation): AnimationTrack
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action -- over the locomotion clip it stands in
	track.Looped = true
	return track
end

--- @param model Model
--- @param set AnimationConfig.AnimationSet? -- clips overriding the rig's own, slot by slot
function NpcAnimator.new(model: Model, set: AnimationConfig.AnimationSet?)
	local self = setmetatable({}, NpcAnimator)

	local humanoid = model.Humanoid :: Humanoid
	self.Humanoid = humanoid
	self.Animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	self.Current = nil :: AnimationTrack?
	self.Rate = 1
	self.MovementSpeedOverride = nil :: number?
	self.Paused = false
	self._stoppedSince = nil :: number?
	self._connections = {}

	self.Emote = nil :: AnimationTrack?
	self.Set = set or {}

	self.Animate = model.Animate
	self.Animate.Disabled = true
	self.Tracks = self:_loadTracks()
	self.Emotes = self:_loadEmotes()
	self.Attacks = self:_loadAttacks()

	return self
end

function NpcAnimator:_loadTracks()
	-- The rig's own idle is opt-in where its walk and run are not, because an NPC standing still holds
	-- its walk pose unless something authored says otherwise. Two things ask for it: a rig that never
	-- walks at all and so has no pose to hold, and one that must not read as an enemy in the first place.
	local rigIdle = if self.Set.UseRigIdle then self.Animate:FindFirstChild("idle") else nil
	return {
		Idle = loadTrack(self.Animator, rigIdle, self.Set.Idle),
		Walk = loadTrack(self.Animator, self.Animate:FindFirstChild("walk"), self.Set.Walk),
		Run = loadTrack(self.Animator, self.Animate:FindFirstChild("run"), self.Set.Run),
	}
end

function NpcAnimator:_loadAttacks()
	local attacks = {}
	for _, assetId in self.Set.Attacks or {} do
		local track = self.Animator:LoadAnimation(makeAnimation(assetId))
		track.Priority = Enum.AnimationPriority.Action -- a swing plays over the walk it arrives out of
		track.Looped = false
		table.insert(attacks, track)
	end
	return attacks
end

function NpcAnimator:_loadEmotes()
	local emotes = {}
	for _, name in EMOTE_CONTAINERS do
		local container = self.Animate:FindFirstChild(name)
		if container then
			for _, descendant in container:GetDescendants() do
				if descendant:IsA("Animation") then
					table.insert(emotes, loadEmote(self.Animator, descendant))
				end
			end
		end
	end
	return emotes
end

--- Plays a random emote over whatever it is standing in. Refuses while it is moving, already
--- emoting, or held still deliberately -- an emote layered onto a walk is two clips fighting for the
--- same joints, which is the whole reason this lives next to the locomotion rather than beside it.
function NpcAnimator:PlayEmote(): boolean
	if self.Paused or self.Emote or #self.Emotes == 0 then return false end
	if self:_isMoving() then return false end

	local track = self.Emotes[math.random(#self.Emotes)]
	self.Emote = track
	track:Play(TRANSITION_TIME)
	task.delay(MimicConfig.EmoteDuration, function()
		if self.Emote == track then
			self:StopEmote()
		end
	end)
	return true
end

--- Cuts any emote short. Happens on its own the moment the NPC takes a step.
function NpcAnimator:StopEmote()
	if not self.Emote then return end
	self.Emote:Stop(EMOTE_STOP_TIME)
	self.Emote = nil
end

--- Plays one of this NPC's attack swings over whatever it is standing in, chosen at random. Returns
--- false for an enemy that was given none -- the kill still lands, it simply is not animated.
---
--- Deliberately does not yield: an attack state decides how long the blow takes from its own
--- `AttackCooldown`, and a clip that ran longer than that would hold an enemy still past the point it
--- had already killed somebody.
function NpcAnimator:PlayAttack(): boolean
	if #self.Attacks == 0 then return false end

	self:StopEmote()
	self.Attacks[math.random(#self.Attacks)]:Play(TRANSITION_TIME)
	return true
end

--- Stops every clip playing on this rig that this animator did not start.
---
--- A rig handed to a client is animated there, and the tracks that client started are its own: taking
--- network ownership back does not stop them, and the client can no longer stop them either, because
--- nothing it does to a rig it does not own replicates any more. They are simply stranded, playing at
--- the same `Core` priority as the locomotion that replaces them -- two clips at equal weight, which
--- is a walk that reads as half a walk and a stop that never settles onto its idle. Whoever takes the
--- rig back is the only one left who can clear them.
function NpcAnimator:ClearForeignTracks()
	local mine = {}
	for _, track in self.Tracks do mine[track] = true end
	for _, track in self.Emotes do mine[track] = true end
	for _, track in self.Attacks do mine[track] = true end

	for _, track in self.Animator:GetPlayingAnimationTracks() do
		if not mine[track] then
			track:Stop(0)
		end
	end
end

-- How fast `track` has to run for one cycle of it to carry the rig `speed` studs a second.
local function cycleRate(track: AnimationTrack, speed: number): number
	local length = if track.Length > 0 then track.Length else FALLBACK_CYCLE_TIME
	return speed * length / CYCLE_DISTANCE
end

-- Ground actually being covered, which is the right number for a playback rate and the wrong one for
-- deciding what the NPC is doing. An explicit override *is* the travel: it comes from whoever is
-- moving the rig without humanoid physics, and their number is better than a measurement of a tween.
function NpcAnimator:_travelSpeed(): number
	if self.MovementSpeedOverride then return self.MovementSpeedOverride end

	local root = self.Humanoid.RootPart
	if not root then return 0 end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

-- The pace this NPC has been *told* to travel at, which is what decides between the walk clip and the
-- run one. A measurement is a far noisier number than the gait it belongs to: a rig turning a corner,
-- clipping a doorframe or being shoved by the player it is chasing measures anything from a crawl to
-- its full pace, several times a second. Read against a fixed threshold, a Chaser told to run at 19
-- crosses the walk/run line repeatedly within a single second, and every crossing would stop one clip
-- and start the other from its first frame.
function NpcAnimator:_gaitSpeed(): number
	return self.MovementSpeedOverride or self.Humanoid.WalkSpeed
end

-- Whether the NPC is going anywhere. Two signals, and it takes either, because neither is available
-- everywhere. `MoveDirection` is the humanoid's own intent and is exact where it can be read at all,
-- but Roblox hands an unanchored rig standing near somebody to that player's machine, and the server
-- reads a flat zero off a humanoid it is not simulating -- which is nearly every enemy, nearly all the
-- time. What still arrives is where the rig actually is, so measured travel is what carries those, and
-- intent covers the rest: a humanoid pushing into a player or a doorframe measures almost nothing
-- while it is unambiguously still walking.
function NpcAnimator:_isMoving(): boolean
	if self.MovementSpeedOverride then return self.MovementSpeedOverride >= MOVING_THRESHOLD end
	return self.Humanoid.MoveDirection.Magnitude > 1e-3 or self:_travelSpeed() >= TRAVEL_THRESHOLD
end

--- Puts the right clip on the rig for whatever it is doing this frame, and scales its playback to the
--- ground it is covering. Polled rather than driven off `Humanoid.Running`, which reports a physics
--- measurement on its own schedule: it goes quiet exactly when a rig is wedged or being pushed, and a
--- locomotion state that is only ever recomputed when that event fires can be left holding a clip that
--- no longer describes anything.
function NpcAnimator:_update()
	if self.Paused then return end

	local moving = self:_isMoving()
	if moving then
		self._stoppedSince = nil
		self:StopEmote() -- whatever else is true, an emote does not survive walking
	else
		self._stoppedSince = self._stoppedSince or os.clock()
	end

	-- A brief stop holds the pose it stopped in rather than resolving to a clip of its own: an NPC that
	-- has come to a halt in the middle of a stride may be about to carry on. After a short grace period
	-- an authored idle replaces that pose, and a rig moved by hand skips the grace entirely -- whoever
	-- is driving it said it stopped, so there is nothing to wait and see about.
	local track
	if moving then
		track = if self:_gaitSpeed() >= RUN_THRESHOLD
			then self.Tracks.Run or self.Tracks.Walk
			else self.Tracks.Walk or self.Tracks.Run
	elseif self.Tracks.Idle
		and (self.MovementSpeedOverride ~= nil
			or self.Current == nil
			or os.clock() - (self._stoppedSince :: number) >= IDLE_DELAY)
	then
		track = self.Tracks.Idle
	else
		-- Falling back to the walk covers an NPC that has not taken a step yet: the first pose of a gait
		-- cycle is a standing one, so there is nothing to see, and there is no A-pose either.
		track = self.Current or self.Tracks.Idle or self.Tracks.Walk or self.Tracks.Run
	end
	if not track then return end

	-- Some rigs deliberately use one clip for both gaits. Keep the playing copy when crossing the
	-- walk/run threshold so a speed adjustment does not visibly restart the same animation.
	if self.Current
		and track ~= self.Current
		and track.Animation.AnimationId == self.Current.Animation.AnimationId then
		track = self.Current
	end

	-- Standing still covers no ground, so nothing held there has a stride to be measured against. An
	-- authored idle plays at the pace it was made at; a held walk does not play at all -- but not yet.
	-- A rig squaring up to a waypoint measures nothing for a frame while it is still walking, and a
	-- gait stopped dead on one of those and started again reads as the animation having broken. So a
	-- gait keeps turning over for as long as the pose is being held, and only settles once the stop is.
	local rate
	if moving then
		rate = cycleRate(track, math.max(self:_travelSpeed(), self:_gaitSpeed() * MIN_RATE_FRACTION))
	elseif track ~= self.Tracks.Idle and os.clock() - (self._stoppedSince :: number) < IDLE_DELAY then
		rate = cycleRate(track, self:_gaitSpeed() * MIN_RATE_FRACTION)
	else
		rate = if track == self.Tracks.Idle then 1 else 0
	end

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
	if self._connections.Step then return end
	self.MovementSpeedOverride = nil
	self._stoppedSince = nil

	self._connections.Step = RunService.Heartbeat:Connect(function()
		self:_update()
	end)
	self:_update()
end

--- Drives locomotion for a rig moved without Humanoid physics, such as an anchored tweened model.
function NpcAnimator:SetMovementSpeed(speed: number)
	self.MovementSpeedOverride = speed
	self:_update()
end

--- Stops driving and drops the current clip, handing the rig's animation to whoever simulates it now.
--- `Start` picks it back up.
function NpcAnimator:Stop()
	if self._connections.Step then
		self._connections.Step:Disconnect()
		self._connections.Step = nil
	end

	self:StopEmote()
	if self.Current then
		self.Current:Stop(TRANSITION_TIME)
		self.Current = nil
	end
	self._stoppedSince = nil
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
	self._stoppedSince = nil
	self:_update()
end

--- Rebuilds the tracks from the rig's current animation set, keeping whatever the NPC was doing.
--- Applying a `HumanoidDescription` rewrites the ids under the `Animate` script, so an NPC that has
--- just put on a player's animation package has to reload before it actually moves like them.
function NpcAnimator:Reload()
	-- The attacks are not rebuilt with the rest: they are authored ids rather than clips read off the
	-- rig, so a new `HumanoidDescription` has nothing to say about them.
	local paused = self.Paused
	self.Emote = nil
	unload(self.Tracks)
	unload(self.Emotes)

	self.Current = nil
	self.Paused = false
	self._stoppedSince = nil
	self.Tracks = self:_loadTracks()
	self.Emotes = self:_loadEmotes()

	-- Only pick playback back up if this animator is the one driving: a rig handed to a client is
	-- animated there, and a reload here would put a second clip on it.
	if self._connections.Step then
		self:_update()
		if paused then
			self:Pause()
		end
	else
		self.Paused = paused
	end
end

function NpcAnimator:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
	unload(self.Tracks)
	unload(self.Emotes)
	unload(self.Attacks)
	self.Tracks = {}
	self.Emotes = {}
	self.Attacks = {}
	self.Current = nil
	self.Emote = nil
	self._stoppedSince = nil
end

return NpcAnimator
