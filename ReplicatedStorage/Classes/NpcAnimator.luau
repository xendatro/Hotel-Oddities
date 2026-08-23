local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)

local MOVING_THRESHOLD = 0.1
local TRAVEL_THRESHOLD = 1
local RUN_THRESHOLD = 12
local TRANSITION_TIME = 0.2
local IDLE_DELAY = 0.15
local MIN_RATE_FRACTION = 0.4

local CYCLE_DISTANCE = 8
local FALLBACK_CYCLE_TIME = 1

local EMOTE_STOP_TIME = 0.1

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
		EmoteTracks: { [string]: { AnimationTrack } },
		Set: AnimationConfig.AnimationSet,
		Attacks: { AnimationTrack },
		Override: AnimationTrack?,
		OverrideAssetId: number?,
		OverrideTracks: { [number]: AnimationTrack },
		Rate: number,
		MovementSpeedOverride: number?,
	MovementTrackOverride: "Walk" | "Run"?,
		Paused: boolean,
		_stoppedSince: number?,
		_connections: { [string]: RBXScriptConnection? },
	},
	NpcAnimator
))

local function unload(tracks: { [any]: AnimationTrack? })
	for _, track in tracks do
		track:Stop(0)
		track:Destroy()
	end
end

local function makeAnimation(assetId: number): Animation
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{assetId}`
	return animation
end

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
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	return track
end

function NpcAnimator.new(model: Model, set: AnimationConfig.AnimationSet?)
	local self = setmetatable({}, NpcAnimator)

	local humanoid = model.Humanoid :: Humanoid
	self.Humanoid = humanoid
	self.Animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	self.Current = nil :: AnimationTrack?
	self.Rate = 1
	self.MovementSpeedOverride = nil :: number?
	self.MovementTrackOverride = nil
	self.Paused = false
	self._stoppedSince = nil :: number?
	self._connections = {}

	self.Emote = nil :: AnimationTrack?
	self.Override = nil :: AnimationTrack?
	self.OverrideAssetId = nil :: number?
	self.OverrideTracks = {} :: { [number]: AnimationTrack }
	self.Hold = nil :: AnimationTrack?
	self.HoldAssetId = nil :: number?
	self.HoldTracks = {} :: { [number]: AnimationTrack }
	self.Set = set or {}

	self.Animate = model.Animate
	self.Animate.Disabled = true
	self.Tracks = self:_loadTracks()
	self.Emotes, self.EmoteTracks = self:_loadEmotes()
	self.Attacks = self:_loadAttacks()

	return self
end

function NpcAnimator:_loadTracks()
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
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = false
		table.insert(attacks, track)
	end
	return attacks
end

function NpcAnimator:_loadEmotes()
	local emotes = {}
	local byName = {}
	for _, name in EMOTE_CONTAINERS do
		local container = self.Animate:FindFirstChild(name)
		if container then
			local named = {}
			for _, descendant in container:GetDescendants() do
				if descendant:IsA("Animation") then
					local track = loadEmote(self.Animator, descendant)
					table.insert(emotes, track)
					table.insert(named, track)
				end
			end
			if #named > 0 then byName[name] = named end
		end
	end
	return emotes, byName
end

function NpcAnimator:PlayEmote(name: string?): boolean
	if self.Paused or self.Emote or #self.Emotes == 0 then return false end
	if self:_isMoving() then return false end

	local choices = if name then self.EmoteTracks[name] else self.Emotes
	if not choices or #choices == 0 then return false end
	local track = choices[math.random(#choices)]
	self.Emote = track
	track:Play(TRANSITION_TIME)
	task.delay(MimicConfig.EmoteDuration, function()
		if self.Emote == track then
			self:StopEmote()
		end
	end)
	return true
end

function NpcAnimator:StopEmote()
	if not self.Emote then return end
	self.Emote:Stop(EMOTE_STOP_TIME)
	self.Emote = nil
end

function NpcAnimator:PlayAttack(): boolean
	if #self.Attacks == 0 then return false end

	self:StopEmote()
	self.Attacks[math.random(#self.Attacks)]:Play(TRANSITION_TIME)
	return true
end

function NpcAnimator:_overrideTrack(assetId: number): AnimationTrack
	local track = self.OverrideTracks[assetId]
	if not track then
		track = self.Animator:LoadAnimation(makeAnimation(assetId))
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		self.OverrideTracks[assetId] = track
	end
	return track
end

function NpcAnimator:PreloadOverride(assetId: number)
	self:_overrideTrack(assetId)
end

function NpcAnimator:PlayOverride(assetId: number)
	if self.Override and self.OverrideAssetId == assetId then return end

	self:StopOverride()
	local track = self:_overrideTrack(assetId)
	self.Override = track
	self.OverrideAssetId = assetId
	track:Play(TRANSITION_TIME)
end

function NpcAnimator:StopOverride()
	local track = self.Override
	if not track then return end

	self.Override = nil
	self.OverrideAssetId = nil
	track:Stop(TRANSITION_TIME)
end

--- A hold is a pose that layers over whatever the body is already doing rather
--- than replacing it -- the tool-carry arm, for instance. It survives Reload and
--- is left alone by StopOverride, so it stays put across an identity swap.
function NpcAnimator:PlayHold(assetId: number)
	if self.Hold and self.HoldAssetId == assetId then return end
	self:StopHold()

	local track = self.HoldTracks[assetId]
	if not track then
		track = self.Animator:LoadAnimation(makeAnimation(assetId))
		track.Priority = Enum.AnimationPriority.Action
		track.Looped = true
		self.HoldTracks[assetId] = track
	end

	self.Hold = track
	self.HoldAssetId = assetId
	track:Play(TRANSITION_TIME)
end

function NpcAnimator:StopHold()
	local track = self.Hold
	if not track then return end

	self.Hold = nil
	self.HoldAssetId = nil
	track:Stop(TRANSITION_TIME)
end

function NpcAnimator:ClearForeignTracks()
	local mine = {}
	for _, track in self.Tracks do mine[track] = true end
	for _, track in self.Emotes do mine[track] = true end
	for _, track in self.Attacks do mine[track] = true end
	for _, track in self.OverrideTracks do mine[track] = true end
	for _, track in self.HoldTracks do mine[track] = true end

	for _, track in self.Animator:GetPlayingAnimationTracks() do
		if not mine[track] then
			track:Stop(0)
		end
	end
end

local function cycleRate(track: AnimationTrack, speed: number): number
	local length = if track.Length > 0 then track.Length else FALLBACK_CYCLE_TIME
	return speed * length / CYCLE_DISTANCE
end

function NpcAnimator:_rateScale(): number
	return self.Set.RateMultiplier or 1
end

function NpcAnimator:_travelSpeed(): number
	if self.MovementSpeedOverride then return self.MovementSpeedOverride end

	local root = self.Humanoid.RootPart
	if not root then return 0 end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

function NpcAnimator:_gaitSpeed(): number
	return self.MovementSpeedOverride or self.Humanoid.WalkSpeed
end

function NpcAnimator:_isMoving(): boolean
	if self.MovementSpeedOverride then return self.MovementSpeedOverride >= MOVING_THRESHOLD end
	return self.Humanoid.MoveDirection.Magnitude > 1e-3 or self:_travelSpeed() >= TRAVEL_THRESHOLD
end

function NpcAnimator:_update()
	if self.Paused then return end

	local moving = self:_isMoving()
	if moving then
		self._stoppedSince = nil
		self:StopEmote()
	else
		self._stoppedSince = self._stoppedSince or os.clock()
	end

	local track
	if moving then
		track = if self.MovementTrackOverride
			then self.Tracks[self.MovementTrackOverride]
			else if self:_gaitSpeed() >= RUN_THRESHOLD
				then self.Tracks.Run or self.Tracks.Walk
				else self.Tracks.Walk or self.Tracks.Run
	elseif self.Tracks.Idle
		and (self.MovementSpeedOverride ~= nil
			or self.Current == nil
			or os.clock() - (self._stoppedSince :: number) >= IDLE_DELAY)
	then
		track = self.Tracks.Idle
	else
		track = self.Current or self.Tracks.Idle or self.Tracks.Walk or self.Tracks.Run
	end
	if not track then return end

	if self.Current
		and track ~= self.Current
		and track.Animation.AnimationId == self.Current.Animation.AnimationId then
		track = self.Current
	end

	local rate
	if moving then
		rate = cycleRate(track, math.max(self:_travelSpeed(), self:_gaitSpeed() * MIN_RATE_FRACTION)) * self:_rateScale()
	elseif track ~= self.Tracks.Idle and os.clock() - (self._stoppedSince :: number) < IDLE_DELAY then
		rate = cycleRate(track, self:_gaitSpeed() * MIN_RATE_FRACTION) * self:_rateScale()
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

function NpcAnimator:Start()
	if self._connections.Step then return end
	self.MovementSpeedOverride = nil
	self._stoppedSince = nil

	self._connections.Step = RunService.Heartbeat:Connect(function()
		self:_update()
	end)
	self:_update()
end

function NpcAnimator:SetMovementSpeed(speed: number)
	self.MovementSpeedOverride = speed
	self:_update()
end

function NpcAnimator:SetMovementTrack(trackName: "Walk" | "Run"?)
	self.MovementTrackOverride = trackName
	self:_update()
end

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

function NpcAnimator:Pause()
	if self.Paused then return end
	self.Paused = true
	self:StopEmote()
	if self.Current then
		self.Current:AdjustSpeed(0)
	end
end

function NpcAnimator:Resume()
	if not self.Paused then return end
	self.Paused = false
	self._stoppedSince = nil
	self:_update()
end

function NpcAnimator:Reload()
	local paused = self.Paused
	self.Emote = nil
	unload(self.Tracks)
	unload(self.Emotes)

	self.Current = nil
	self.Paused = false
	self._stoppedSince = nil
	self.Tracks = self:_loadTracks()
	self.Emotes, self.EmoteTracks = self:_loadEmotes()

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
	self.Override = nil
	self.OverrideAssetId = nil
	unload(self.OverrideTracks)
	self.OverrideTracks = {}
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
