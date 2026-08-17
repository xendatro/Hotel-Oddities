--- Holds an enemy that must not move while it is seen still on the frame the player's eyes land on
--- it, rather than the frame the server's agreement gets back.
---
--- The server is still the one that decides. What it cannot do is decide quickly: the client notices
--- at its own framerate, the report flies, an evaluator picks it up, the freeze replicates back. Half
--- of that is polling and half of it is the wire, and all of it happens while the player is staring
--- at a statue taking another two steps towards them -- which is the one thing the enemy is not
--- supposed to be able to do.
---
--- So the client acts on its own eyes immediately and carries the difference. Nothing here is
--- authority; it is a bridge to an answer already on its way, and every path out of it ends in the
--- server's position being restored. The difference is bounded three ways -- by the server's own
--- freeze landing a round trip later and stopping it growing, by `MaxOffset`, and by
--- `ConfirmationTimeout` for a guess the server never agreed with at all.
---
--- Two rules keep it honest. The enemy is only ever drawn *behind* where the server has it, never
--- ahead, because a pin holds a pose the player has already seen rather than inventing one. And the
--- difference is only ever paid back while the enemy is nowhere on this player's screen -- so the
--- correction, whenever it comes, is one nobody watches happen.
---
--- Purely local. Nothing here replicates, so two clients never disagree by more than each one's own
--- ping, and neither ever disagrees with the server for longer than it takes to look away.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyObservationService = require(ReplicatedStorage.Services.EnemyObservationService)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ObservedFreezeConfig = require(ReplicatedStorage.Configs.ObservedFreezeConfig)
local Sightline = require(ReplicatedStorage.Modules.Sightline)

-- Studs a restored position may differ from the one written before it is taken as somebody else's
-- work rather than our own. Well under a replication step's travel, and well over nothing.
local WRITE_EPSILON = 1e-3

local ObservedFreezeService = {}

if not FLAGS.Enemies then
	return ObservedFreezeService
end

-- How far the drawn pose sits from the replicated one, and in whose frame of reference. Held in the
-- enemy's own space rather than the world's, which is what makes the debt read as "a stride back
-- down its path" instead of "a fixed direction it happens to have been travelling in when the pin
-- went on" -- these rigs face the way they walk, so its own space is its path. It also keeps the
-- arithmetic honest: the drift is the length of this and nothing else, where a world-space delta
-- would fold the enemy's rotation into a number that is supposed to be a distance.
type State = {
	Root: BasePart,
	Displaced: boolean, -- whether this model is being drawn anywhere other than where it replicated
	Truth: CFrame, -- where the server last had it, kept apart from where it is being drawn
	Relative: CFrame, -- and the debt itself, in that pose's own space
	Rendered: CFrame, -- what was written for the frame, so a replicated overwrite can be spotted
	Pinned: boolean,
	Pose: CFrame, -- the pose a pin holds: exactly what the player laid eyes on
	PinnedAt: number,
	Confirmed: boolean,
	Suppressed: boolean, -- do not retry a rejected prediction until the player looks away
	PredictingRelease: boolean,
	ReleaseVelocity: Vector3,
	Speeds: { [AnimationTrack]: number }, -- playback rates taken away by the pin, to be handed back
}

local localPlayer = Players.LocalPlayer
local States: { [Model]: State } = {}

local function trackList(model: Model): { AnimationTrack }
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator") :: Animator?
	return if animator then animator:GetPlayingAnimationTracks() else {}
end

-- Freezes the pose along with the position. Re-applied every frame a pin holds rather than once at
-- the start of it, because the server goes on driving locomotion until its own freeze lands and may
-- well put a fresh clip on the rig in the meantime -- and a walk cycle turning over on a rig that is
-- not going anywhere is a worse tell than the delay this exists to remove.
local function holdPose(state: State, model: Model)
	for _, track in trackList(model) do
		if state.Speeds[track] == nil and track.Speed > 0 then
			state.Speeds[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
end

-- Hands the rates back. A best guess by construction -- the server may have changed its mind about
-- what this rig should be playing while the pin held -- but a cheap one to be wrong about: the
-- server re-asserts a playback rate every frame it is not itself frozen, so a bad guess survives
-- about as long as it takes to make.
local function releasePose(state: State)
	for track, speed in state.Speeds do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
	table.clear(state.Speeds)
end

-- Puts the model back where the server has it and stops drawing it anywhere else.
local function reconcile(state: State)
	state.Displaced = false
	state.PredictingRelease = false
	state.Relative = CFrame.identity
	state.Root.CFrame = state.Truth
	state.Rendered = state.Truth
end

local function forget(model: Model)
	local state = States[model]
	if not state then return end

	releasePose(state)
	reconcile(state)
	States[model] = nil
	EnemyObservationService:SetSeen(model, nil)
end

local function stateFor(model: Model): State?
	local existing = States[model]
	if existing then
		if existing.Root.Parent then return existing end
		forget(model)
		return nil
	end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return nil end

	local state: State = {
		Root = root,
		Displaced = false,
		Truth = root.CFrame,
		Relative = CFrame.identity,
		Rendered = root.CFrame,
		Pinned = false,
		Pose = root.CFrame,
		PinnedAt = 0,
		Confirmed = false,
		Suppressed = false,
		PredictingRelease = false,
		ReleaseVelocity = Vector3.zero,
		Speeds = {},
	}
	States[model] = state
	return state
end

local function step(model: Model, camera: Camera, frustum: Sightline.Frustum, character: Model, deltaTime: number)
	local state = stateFor(model)
	if not state then return end

	-- Whatever the root reads before anything is written this frame is the server's, which holds
	-- because the pose written for the last frame was taken back at the end of it.
	local now = os.clock()
	local truth = state.Root.CFrame
	local truthDelta = truth.Position - state.Truth.Position
	state.Truth = truth

	local serverFrozen = model:GetAttribute(ObservedFreezeConfig.FrozenAttribute) == true
	if state.Pinned and serverFrozen then
		state.Confirmed = true
	end
	-- Once an unfrozen server pose advances, its real path can take over from the short straight-line
	-- guess. Until that first replicated step arrives, keep the local release moving.
	if state.PredictingRelease and not serverFrozen and truthDelta.Magnitude >= WRITE_EPSILON then
		state.PredictingRelease = false
	end
	if not state.Pinned and not state.PredictingRelease then
		if serverFrozen then
			holdPose(state, model)
		else
			releasePose(state)
		end
	end

	if state.Pinned then
		-- The pose stands still while the server's own copy carries on, so the debt is whatever has
		-- opened up between them since -- and it stops growing the moment the server freezes too.
		state.Relative = truth:ToObjectSpace(state.Pose)
		state.Rendered = state.Pose
	elseif state.PredictingRelease then
		-- Start moving at once while the server's release is in flight. This only changes the drawn
		-- pose and is bounded by the same offset limit as the predicted stop.
		state.Rendered += state.ReleaseVelocity * deltaTime
		state.Relative = truth:ToObjectSpace(state.Rendered)
	elseif state.Displaced then
		-- No longer holding a pose, but still owing the difference. The enemy travels exactly as the
		-- server says it does, simply drawn a stride back down its own path, until it goes off screen
		-- and the debt can be settled with nobody watching.
		state.Rendered = truth * state.Relative
	end

	if state.Displaced then
		state.Root.CFrame = state.Rendered
	end

	-- Asked against what is on the screen rather than what replicated, so the pin and the eyes that
	-- justify it never disagree: the enemy the player is looking at is the enemy being held still.
	local actuallySeen = Sightline.CanSee(camera, frustum, character, model)
	EnemyObservationService:SetSeen(model, actuallySeen)
	if not actuallySeen then
		state.Suppressed = false
	end
	local seen = actuallySeen and not state.Suppressed

	if seen ~= state.Pinned then
		if seen then
			state.Pinned = true
			state.Pose = state.Root.CFrame -- hold precisely the pose that was just laid eyes on
			state.PinnedAt = now
			state.Confirmed = serverFrozen
			state.PredictingRelease = false
			state.Relative = truth:ToObjectSpace(state.Pose)
			state.Rendered = state.Pose
			state.Displaced = true
		else
			state.Pinned = false
			state.PredictingRelease = state.Displaced
			state.ReleaseVelocity = state.Rendered.LookVector * ObservedFreezeConfig.ReleaseSpeed
			releasePose(state)
		end
		-- The server is a beat behind on this either way, so tell it now instead of on the next tick.
		-- It shortens the stretch the guess has to cover, and on release it is the only thing that can
		-- help at all: where the enemy walks off to next is not something this machine can predict.
		EnemyObservationService:Report()
	end

	if state.Pinned then
		holdPose(state, model)
	end

	if not state.Displaced then return end

	local drift = state.Relative.Position.Magnitude
	if drift > ObservedFreezeConfig.MaxOffset then
		-- Past this the guess was wrong rather than early, and a pop the player can see is the lesser
		-- of the two problems. See `MaxOffset` for the one it is being weighed against.
		state.Pinned = false
		state.PredictingRelease = false
		state.Suppressed = actuallySeen
		releasePose(state)
		reconcile(state)
		if serverFrozen then
			holdPose(state, model)
		end
		return
	end

	if state.Pinned
		and not state.Confirmed
		and now - state.PinnedAt > ObservedFreezeConfig.ConfirmationTimeout
	then
		state.Pinned = false
		state.PredictingRelease = false
		state.Suppressed = actuallySeen
		releasePose(state)
		reconcile(state)
	end

	if state.Pinned then return end
	if state.PredictingRelease then return end
	if drift < WRITE_EPSILON then
		reconcile(state)
		return
	end

	-- Settled only where nobody can watch it happen, which means neither the pose being drawn nor the
	-- one it is about to jump to may be anywhere in the view volume.
	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local radius = boundsSize.Magnitude / 2
	local centerOffset = boundsCFrame.Position - state.Rendered.Position
	if not Sightline.Intersects(camera, frustum, boundsCFrame.Position, radius)
		and not Sightline.Intersects(camera, frustum, truth.Position + centerOffset, radius)
	then
		reconcile(state)
	end
end

RunService.RenderStepped:Connect(function(deltaTime: number)
	local character = localPlayer.Character
	local camera = workspace.CurrentCamera
	local frustum = camera and Sightline.Frustum(camera)

	local live: { [Model]: boolean } = {}
	if character and camera and frustum then
		for _, model in CollectionService:GetTagged(ObservedFreezeConfig.Tag) do
			if model:IsA("Model") and model:IsDescendantOf(workspace) then
				live[model] = true
				step(model, camera, frustum, character, deltaTime)
			end
		end
	end

	for model in States do
		if not live[model] then
			forget(model)
		end
	end
end)

--- Takes the drawn pose back off the rig, so the next frame reads the server's position rather than
--- ours and a replicated update is never mistaken for one.
---
--- Skipped where the rig no longer holds what was written for it: that is a replicated update having
--- landed since, which is the newer truth and must not be undone. Restoring it blindly is how a
--- prediction stops being a prediction -- every packet overwritten, the last guess read back as
--- fact, and an enemy frozen locally for good.
RunService.Stepped:Connect(function()
	for model, state in States do
		if not state.Displaced then continue end
		if not state.Root.Parent then
			forget(model)
			continue
		end
		if (state.Root.CFrame.Position - state.Rendered.Position).Magnitude < WRITE_EPSILON then
			state.Root.CFrame = state.Truth
		end
	end
end)

return ObservedFreezeService
