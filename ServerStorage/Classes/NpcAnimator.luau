--- @class NpcAnimator
--- Drives an R15 NPC's locomotion clips. The animations come from the rig's stock `Animate` script,
--- which holds one `Animation` under each named container (`idle`, `walk`, `run`); that script is
--- disabled so it cannot fight us for control of the Animator. Driving the tracks ourselves is what
--- makes `Pause` possible -- enemies like the Weeping Angel must freeze mid-stride, not snap to idle.

local MOVING_THRESHOLD = 0.1 -- studs/s below which the NPC counts as standing still
local RUN_THRESHOLD = 12 -- studs/s at which the walk clip gives way to the run clip
local BASE_SPEED = 16 -- the speed the stock clips are authored for; playback scales against it
local TRANSITION_TIME = 0.2

local NpcAnimator = {}
NpcAnimator.__index = NpcAnimator

local function loadTrack(animator: Animator, container: Instance?): AnimationTrack?
	local animation = container and container:FindFirstChildWhichIsA("Animation")
	if not animation then return nil end

	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
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

	local animate = model.Animate
	animate.Disabled = true

	self.Tracks = {
		Idle = loadTrack(self.Animator, animate:FindFirstChild("idle")),
		Walk = loadTrack(self.Animator, animate:FindFirstChild("walk")),
		Run = loadTrack(self.Animator, animate:FindFirstChild("run")),
	}

	return self
end

-- Swaps to the clip matching `speed` and scales its playback to match.
function NpcAnimator:_apply(speed: number)
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

--- Begins reacting to the humanoid's movement.
function NpcAnimator:Start()
	self._connections.Running = self.Humanoid.Running:Connect(function(speed: number)
		self:_apply(speed)
	end)
	self:_apply(0)
end

--- Freezes the current clip on its current pose. Movement must be stopped separately.
function NpcAnimator:Pause()
	if self.Paused then return end
	self.Paused = true
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

function NpcAnimator:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
	for _, track in self.Tracks do
		track:Destroy()
	end
	self.Current = nil
end

return NpcAnimator
