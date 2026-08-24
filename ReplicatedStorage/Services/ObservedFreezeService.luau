local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyObservationService = require(ReplicatedStorage.Services.EnemyObservationService)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local ObservedFreezeConfig = require(ReplicatedStorage.Configs.ObservedFreezeConfig)
local Sightline = require(ReplicatedStorage.Modules.Sightline)

local WRITE_EPSILON = 1e-3
local VISIBILITY_INTERVAL = 0.05

local ObservedFreezeService = {}

if not FLAGS.Enemies then
	return ObservedFreezeService
end

type State = {
	Root: BasePart,
	Displaced: boolean,
	Truth: CFrame,
	Relative: CFrame,
	Rendered: CFrame,
	Pinned: boolean,
	Pose: CFrame,
	PinnedAt: number,
	Confirmed: boolean,
	Suppressed: boolean,
	PredictingRelease: boolean,
	ReleaseVelocity: Vector3,
	Speeds: { [AnimationTrack]: number },
	LastSeen: boolean,
}

local localPlayer = Players.LocalPlayer
local States: { [Model]: State } = {}
local FrozenModels: { Model } = {}
local FrozenIndices: { [Model]: number } = {}

local function addFrozen(instance: Instance)
	if not instance:IsA("Model") or FrozenIndices[instance] then return end
	table.insert(FrozenModels, instance)
	FrozenIndices[instance] = #FrozenModels
end

local function trackList(model: Model): { AnimationTrack }
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator") :: Animator?
	return if animator then animator:GetPlayingAnimationTracks() else {}
end

local function holdPose(state: State, model: Model)
	for _, track in trackList(model) do
		if state.Speeds[track] == nil and track.Speed > 0 then
			state.Speeds[track] = track.Speed
			track:AdjustSpeed(0)
		end
	end
end

local function releasePose(state: State)
	for track, speed in state.Speeds do
		if track.IsPlaying then
			track:AdjustSpeed(speed)
		end
	end
	table.clear(state.Speeds)
end

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

local function removeFrozen(instance: Instance)
	if not instance:IsA("Model") then return end
	local index = FrozenIndices[instance]
	if not index then return end

	local last = FrozenModels[#FrozenModels]
	FrozenModels[index] = last
	FrozenModels[#FrozenModels] = nil
	FrozenIndices[instance] = nil
	if last ~= instance then FrozenIndices[last] = index end
	forget(instance)
end

CollectionService:GetInstanceAddedSignal(ObservedFreezeConfig.Tag):Connect(addFrozen)
CollectionService:GetInstanceRemovedSignal(ObservedFreezeConfig.Tag):Connect(removeFrozen)
for _, instance in CollectionService:GetTagged(ObservedFreezeConfig.Tag) do
	addFrozen(instance)
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
		LastSeen = false,
	}
	States[model] = state
	return state
end

local function step(model: Model, camera: Camera, frustum: Sightline.Frustum?, character: Model, deltaTime: number)
	local state = stateFor(model)
	if not state then return end

	local now = os.clock()
	local truth = state.Root.CFrame
	local truthDelta = truth.Position - state.Truth.Position
	state.Truth = truth

	local serverFrozen = model:GetAttribute(ObservedFreezeConfig.FrozenAttribute) == true
	if state.Pinned and serverFrozen then
		state.Confirmed = true
	end
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
		state.Relative = truth:ToObjectSpace(state.Pose)
		state.Rendered = state.Pose
	elseif state.PredictingRelease then
		state.Rendered += state.ReleaseVelocity * deltaTime
		state.Relative = truth:ToObjectSpace(state.Rendered)
	elseif state.Displaced then
		state.Rendered = truth * state.Relative
	end

	if state.Displaced then
		state.Root.CFrame = state.Rendered
	end

	local actuallySeen = state.LastSeen
	if frustum then
		actuallySeen = Sightline.CanSee(camera, frustum, character, model)
		state.LastSeen = actuallySeen
		EnemyObservationService:SetSeen(model, actuallySeen)
	end
	if not actuallySeen then
		state.Suppressed = false
	end
	local seen = actuallySeen and not state.Suppressed

	if seen ~= state.Pinned then
		if seen then
			state.Pinned = true
			state.Pose = state.Root.CFrame
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
		EnemyObservationService:Report()
	end

	if state.Pinned then
		holdPose(state, model)
	end

	if not state.Displaced then return end

	local drift = state.Relative.Position.Magnitude
	if drift > ObservedFreezeConfig.MaxOffset then
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
	if not frustum then return end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local radius = boundsSize.Magnitude / 2
	local centerOffset = boundsCFrame.Position - state.Rendered.Position
	if not Sightline.Intersects(camera, frustum, boundsCFrame.Position, radius)
		and not Sightline.Intersects(camera, frustum, truth.Position + centerOffset, radius)
	then
		reconcile(state)
	end
end

local sinceVisibility = VISIBILITY_INTERVAL

RunService.RenderStepped:Connect(function(deltaTime: number)
	local character = localPlayer.Character
	local camera = workspace.CurrentCamera

	sinceVisibility += deltaTime
	local frustum = nil
	if sinceVisibility >= VISIBILITY_INTERVAL and camera then
		sinceVisibility = 0
		frustum = Sightline.Frustum(camera)
	end

	if character and camera then
		for _, model in FrozenModels do
			if model:IsDescendantOf(workspace) then
				step(model, camera, frustum, character, deltaTime)
			else
				forget(model)
			end
		end
	else
		for model in States do
			forget(model)
		end
	end
end)

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
