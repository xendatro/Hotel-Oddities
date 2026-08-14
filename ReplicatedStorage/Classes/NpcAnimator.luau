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

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)

local MOVING_THRESHOLD = 0.1 -- studs/s of measured travel below which the NPC counts as standing still
local RUN_THRESHOLD = 12 -- studs/s of *commanded* pace at which the walk clip gives way to the run clip
local TRANSITION_TIME = 0.2
local IDLE_DELAY = 0.15 -- seconds stopped before an authored idle replaces a held locomotion pose

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
local FALLBACK_CYCLE_TIME = 1 -- stands in for a length that has not downloaded yet

-- `AnimationTrack.Length` reads 0 until the asset behind it has actually loaded, which for a clip
-- named by id is a moment after the NPC starts walking rather than before.
local LENGTH_POLL = 0.1
local LENGTH_TIMEOUT = 5
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
		Set: AnimationConfig.AnimationSet,
		Attacks: { AnimationTrack },
		Rate: number,
		MovementSpeedOverride: number?,
		Paused: boolean,
		_lastSpeed: number,
		_idleToken: number,
		_idlePending: boolean,
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

local function loadEmote(animator: Animator, container: Instance?): AnimationTrack?
	local track = loadTrack(animator, container)
	if not track then return nil end

	track.Priority = Enum.AnimationPriority.Action -- over the locomotion clip it stands in
	track.Looped = false
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
	self._lastSpeed = 0
	self._idleToken = 0
	self._idlePending = false
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

-- How fast `track` has to run for one cycle of it to carry the rig `speed` studs a second.
local function cycleRate(track: AnimationTrack, speed: number): number
	local length = if track.Length > 0 then track.Length else FALLBACK_CYCLE_TIME
	return speed * length / CYCLE_DISTANCE
end

-- Puts the rate right once a clip's real length arrives, for the tracks that were first played on the
-- fallback. Nothing is corrected if the NPC has since moved on to another clip: whatever it is doing
-- now was rated against a length that had, by then, already loaded.
function NpcAnimator:_resyncRate(track: AnimationTrack)
	task.spawn(function()
		local deadline = os.clock() + LENGTH_TIMEOUT
		while track.Length <= 0 and os.clock() < deadline do
			task.wait(LENGTH_POLL)
		end
		if track.Length > 0 and self.Current == track then
			self:_apply(self.MovementSpeedOverride
				or self.Humanoid.MoveDirection.Magnitude * self.Humanoid.WalkSpeed)
		end
	end)
end

-- The pace this NPC has been *told* to travel at, which is what decides between the walk clip and the
-- run one. `Humanoid.Running` reports what a physics step actually measured, and that is a far noisier
-- number than the gait it belongs to: a rig turning a corner, clipping a doorframe or being shoved by
-- the player it is chasing reports anything from a crawl to its full pace, several times a second.
-- Read against a fixed threshold, a Chaser told to run at 19 crosses the walk/run line repeatedly
-- within a single second, and every crossing stops one clip and starts the other from its first frame.
-- What that looks like is a chase animation restarting continuously -- worst on a Mimic, whose client
-- mirrors a player's keys and so is forever accelerating out of a standstill.
--
-- The measurement is still exactly the right number for the playback rate, which is a question about
-- ground covered rather than about intent, so that is what it stays used for. A rig wedged against
-- something while it has been told to run therefore holds the run clip and plays it as slowly as it is
-- actually travelling, rather than dropping to a walk and back the moment it works itself free.
function NpcAnimator:_gaitSpeed(): number
	return self.MovementSpeedOverride or self.Humanoid.WalkSpeed
end

-- Swaps to the clip matching `speed` and scales its playback to match.
function NpcAnimator:_apply(speed: number, forceIdle: boolean?)
	local effectiveSpeed = self.MovementSpeedOverride or speed
	self._lastSpeed = effectiveSpeed

	-- Ahead of the pause check: whatever else is true, an emote does not survive walking.
	if effectiveSpeed >= MOVING_THRESHOLD then
		self._idleToken += 1
		self._idlePending = false
		self:StopEmote()
	end
	if self.Paused then return end

	-- A brief stop holds the pose it stopped in rather than resolving to a clip of its own: an enemy
	-- that has come to a halt in the middle of a stride may be about to carry on. After the short grace
	-- period above, an authored idle replaces that pose. Falling back to the walk covers an NPC that
	-- has not taken a step yet -- the first pose of a gait cycle is a standing one, so there is nothing
	-- to see, and there is no A-pose either.
	local moving = effectiveSpeed >= MOVING_THRESHOLD
	local explicitStop = self.MovementSpeedOverride ~= nil and not moving
	if not moving
		and not explicitStop
		and not forceIdle
		and self.Current
		and self.Tracks.Idle
		and self.Current ~= self.Tracks.Idle
	then
		local token = self._idleToken
		if not self._idlePending then
			self._idlePending = true
			task.delay(IDLE_DELAY, function()
				if self._idlePending
					and self._idleToken == token
					and not self.Paused
					and self._lastSpeed < MOVING_THRESHOLD
				then
					self._idlePending = false
					self:_apply(0, true)
				end
			end)
		end
	end

	local track = if not moving
		then if forceIdle or explicitStop
			then self.Tracks.Idle
			else self.Current or self.Tracks.Idle or self.Tracks.Walk or self.Tracks.Run
		elseif self:_gaitSpeed() >= RUN_THRESHOLD
		then self.Tracks.Run or self.Tracks.Walk
		else self.Tracks.Walk or self.Tracks.Run
	if not track then return end
	-- Some rigs deliberately use one clip for both gaits. Keep the playing copy when crossing the
	-- walk/run threshold so a speed adjustment does not visibly restart the same animation.
	if self.Current
		and track ~= self.Current
		and track.Animation.AnimationId == self.Current.Animation.AnimationId then
		track = self.Current
	end

	-- Standing still covers no ground, so nothing held there has a stride to be measured against. An
	-- authored idle plays at the pace it was made at; a held walk does not play at all.
	local rate
	if moving then
		rate = cycleRate(track, effectiveSpeed)
	else
		rate = if track == self.Tracks.Idle then 1 else 0
	end

	self.Rate = rate
	if track ~= self.Current then
		self._idlePending = false
		if self.Current then
			self.Current:Stop(TRANSITION_TIME)
		end
		self.Current = track
		track:Play(TRANSITION_TIME)
		if moving and track.Length <= 0 then
			self:_resyncRate(track)
		end
	end
	track:AdjustSpeed(rate)
end

--- Begins reacting to the humanoid's movement. Safe to call again after `Stop`.
function NpcAnimator:Start()
	if self._connections.Running then return end
	self.MovementSpeedOverride = nil

	self._connections.Running = self.Humanoid.Running:Connect(function(speed: number)
		self:_apply(speed)
	end)
	self:_apply(self.Humanoid.MoveDirection.Magnitude * self.Humanoid.WalkSpeed)
end

--- Drives locomotion for a rig moved without Humanoid physics, such as an anchored tweened model.
function NpcAnimator:SetMovementSpeed(speed: number)
	self.MovementSpeedOverride = speed
	self:_apply(speed)
end

--- Stops driving and drops the current clip, handing the rig's animation to whoever simulates it now.
--- `Start` picks it back up.
function NpcAnimator:Stop()
	self._idleToken += 1
	self._idlePending = false
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
	self._idleToken += 1
	self._idlePending = false
	self:StopEmote() -- a stunned enemy waving would be quite the tell
	if self.Current then
		self.Current:AdjustSpeed(0)
	end
end

--- Resumes playback and resyncs to whatever the humanoid is doing now.
function NpcAnimator:Resume()
	if not self.Paused then return end
	self.Paused = false
	self:_apply(self.MovementSpeedOverride
		or self.Humanoid.MoveDirection.Magnitude * self.Humanoid.WalkSpeed)
end

--- Rebuilds the tracks from the rig's current animation set, keeping whatever the NPC was doing.
--- Applying a `HumanoidDescription` rewrites the ids under the `Animate` script, so an NPC that has
--- just put on a player's animation package has to reload before it actually moves like them.
function NpcAnimator:Reload()
	-- The attacks are not rebuilt with the rest: they are authored ids rather than clips read off the
	-- rig, so a new `HumanoidDescription` has nothing to say about them.
	local paused = self.Paused
	self._idleToken += 1
	self._idlePending = false
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
	self._idleToken += 1
	self._idlePending = false
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
end

return NpcAnimator
