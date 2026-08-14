--- Client half of the `Mimic`. While one is stalking you, the server hands your own machine the job
--- of moving it: yours is the only one that knows your input on the frame you make it, and the only
--- one that renders the answer on the same frame it simulates it. Anything the server drives instead
--- arrives on your screen as a stepped approximation of both, which is exactly what a mimic cannot
--- afford to look like.
---
--- What it replays is your keys, not your velocity, and it holds them the way you held them. The game
--- is first person, so it also faces you the whole time and sidesteps without turning -- which is
--- what your own character does when you press A, and nothing like what an NPC usually does.
---
--- The server grants network ownership of the rig alongside the request, decides when the act ends,
--- and takes the rig back to run the chase itself. Nothing here is trusted with damage.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MimicMotion = require(ReplicatedStorage.Modules.MimicMotion)
local MotionTrail = require(ReplicatedStorage.Classes.MotionTrail)
local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)

local MimicService = {}

if not FLAGS.Enemies then
	return MimicService
end

local Mirror = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("Mirror") :: RemoteEvent

local CHARACTER_TIMEOUT = 10

local localPlayer = Players.LocalPlayer

type Job = {
	Model: Model,
	Humanoid: Humanoid,
	RootPart: BasePart,
	Animator: NpcAnimator.NpcAnimator?,
	Mode: string,
	Delay: number,
	Seed: number,
	Forward: MimicMotion.Key,
	Right: MimicMotion.Key,
	NextEmoteAt: number,
	BehindTurnAt: number?,
	SpinStartedAt: number?,
	SpinStartYaw: number?,
	SpinDelta: number?,
	SpinDirection: number,
	SpinHeight: number?,
}

type HeadTurn = {
	Applied: CFrame,
	Start: CFrame,
	Target: CFrame,
	StartedAt: number,
	Duration: number,
}

local trail: MotionTrail.MotionTrail? = nil
local job: Job? = nil
local appliedHeadTurns: { [Model]: HeadTurn } = {}

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

local function angleBetween(from: Vector3, to: Vector3): number
	local a, b = flatten(from), flatten(to)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

-- Whether the mimic can travel `direction` without walking into a wall. The person it is stalking is
-- not a wall: at these distances they are inside the probe, and treating them as one leaves the mimic
-- frozen in front of you the moment it gets close.
local function isClear(root: BasePart, character: Model, direction: Vector3): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { root.Parent :: Instance, character }
	params.RespectCanCollide = true
	return workspace:Raycast(root.Position, direction * MimicConfig.WallProbeDistance, params) == nil
end

local function getNeck(model: Model): any?
	local head = model:FindFirstChild("Head")
	return head and head:FindFirstChild("Neck")
end

local function yaw(direction: Vector3): number
	local flat = flatten(direction)
	if flat.Magnitude < 1e-3 then return 0 end
	return math.atan2(-flat.X, -flat.Z)
end

local function driveSpin(active: Job, own: MotionTrail.MotionTrail, clock: number)
	local humanoid = active.Humanoid
	local root = active.RootPart
	local toPlayer = own.RootPart.Position - root.Position
	if flatten(toPlayer).Magnitude < 1e-3 then return end

	if not active.SpinStartYaw then
		active.SpinStartYaw = yaw(root.CFrame.LookVector)
		active.SpinHeight = root.Position.Y
		local targetYaw = yaw(toPlayer)
		local shortest = math.atan2(
			math.sin(targetYaw - active.SpinStartYaw),
			math.cos(targetYaw - active.SpinStartYaw)
		)
		active.SpinDelta = shortest + active.SpinDirection * math.pi * 2
	end

	local progress = math.clamp(
		(clock - (active.SpinStartedAt :: number)) / MimicConfig.SpinDuration,
		0,
		1
	)
	local eased = progress * progress * (3 - 2 * progress)
	local angle = (active.SpinStartYaw :: number) + (active.SpinDelta :: number) * eased
	local position = root.Position
	humanoid:Move(Vector3.zero)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.new(position.X, active.SpinHeight :: number, position.Z)
		* CFrame.Angles(0, angle, 0)
end

local function drive(active: Job, own: MotionTrail.MotionTrail, deltaTime: number)
	local humanoid, root = active.Humanoid, active.RootPart

	-- The server zeroes the speed to hold a mimic still -- a stun, or the moment before it despawns.
	-- Driving through that would leave it swivelling on the spot while it is meant to be frozen.
	if humanoid.WalkSpeed <= 0 or humanoid.Health <= 0 then
		return
	end
	if active.Mode == "Spin" then
		driveSpin(active, own, os.clock())
		return
	end
	local animator = active.Animator
	if not animator then return end

	local offset = flatten(own.RootPart.Position - root.Position)
	if offset.Magnitude < 1e-3 then return end
	local targetForward = offset.Unit

	-- Locked on, it has no will of its own: no closing the gap, no shifting its weight, nothing but
	-- your keys played back late. Standing perfectly still while you stand still is the point -- it is
	-- what someone copying you would do, and it is what makes testing it inconclusive.
	local clock = os.clock()
	local sample = own:At(active.Delay)
	local wantForward, wantRight = 0, 0

	if sample then
		local playerForward, playerRight = MimicMotion.Keys(sample, own.Humanoid.WalkSpeed)
		wantForward, wantRight = MimicMotion.MirrorKeys(playerForward, playerRight)

		if sample.Jumping and humanoid.FloorMaterial ~= Enum.Material.Air then
			humanoid.Jump = true
		end
	end

	local behind = angleBetween(root.CFrame.LookVector, targetForward) >= MimicConfig.BehindAngle
	if behind then
		if not active.BehindTurnAt then
			active.BehindTurnAt = clock + if math.random() < MimicConfig.ImmediateBehindTurnChance
				then 0
				else randomRange(MimicConfig.BehindTurnDelayMin, MimicConfig.BehindTurnDelayMax)
		end
	elseif active.BehindTurnAt then
		active.BehindTurnAt = nil
	end

	local forward = if active.BehindTurnAt and clock < active.BehindTurnAt
		then flatten(root.CFrame.LookVector).Unit
		else targetForward

	local direction = MimicMotion.Direction(
		forward,
		MimicMotion.HoldKey(active.Forward, wantForward, clock),
		MimicMotion.HoldKey(active.Right, wantRight, clock)
	)

	local character = own.RootPart.Parent :: Model
	if direction.Magnitude > 1e-3 and not isClear(root, character, direction) then
		direction = Vector3.zero -- it would sooner stand than scrape along a wall
	end
	humanoid:Move(direction)
	-- This rig is moved directly on the owning client, so Humanoid.Running is not a reliable source
	-- for its locomotion state. Feed the same command to the animator explicitly.
	animator:SetMovementSpeed(direction.Magnitude * humanoid.WalkSpeed)

	-- Waiting on you with nothing to copy, it amuses itself. The animator drops the emote the moment
	-- the rig takes a step, so the timer only has to keep them apart, not police the overlap -- and it
	-- restarts while moving so one never lands the instant it comes to a stop.
	if direction.Magnitude > 1e-3 then
		active.NextEmoteAt = clock + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax)
	elseif clock >= active.NextEmoteAt then
		animator:PlayEmote()
		active.NextEmoteAt = clock + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax)
	end

	-- First person: it looks where its camera would be pointed, which is at you. It never turns to
	-- follow its own feet, so a sidestep is a sidestep rather than a pirouette. Its aim lags by the
	-- same beat its keys do, and wanders while it holds you.
	local watching = if sample then sample.Position else own.RootPart.Position
	local lookDirection = if active.BehindTurnAt and clock < active.BehindTurnAt
		then root.CFrame.LookVector
		else watching - root.Position
	local look = MimicMotion.Drift(lookDirection, clock, active.Seed)
	root.CFrame = MimicMotion.Turn(root.CFrame, look, deltaTime)
end

RunService.PreAnimation:Connect(function()
	for model, state in appliedHeadTurns do
		if model:IsDescendantOf(workspace) then
			local neck = getNeck(model)
			if neck then neck.Transform = state.Applied:Inverse() * neck.Transform end
		else
			appliedHeadTurns[model] = nil
		end
	end
end)

RunService.PreSimulation:Connect(function(_deltaTime: number)
	local seen = {}
	local now = os.clock()
	for _, model in CollectionService:GetTagged("Enemy") do
		if not model:GetAttribute("MimicHeadTurn") then continue end
		local neck = getNeck(model)
		if not neck then seen[model] = true continue end

		local target = model:GetAttribute("MimicHeadTurnTarget")
		if typeof(target) ~= "CFrame" then target = CFrame.identity end

		local duration = model:GetAttribute("MimicHeadTurnDuration")
		if type(duration) ~= "number" then duration = MimicConfig.HeadTurnDefaultDuration end

		local state = appliedHeadTurns[model]
		if not state then
			state = {
				Applied = CFrame.identity,
				Start = CFrame.identity,
				Target = target :: CFrame,
				StartedAt = now,
				Duration = duration,
			}
			appliedHeadTurns[model] = state
		elseif target ~= state.Target then
			if now >= state.StartedAt + state.Duration then
				state.Start = state.Applied
				state.StartedAt = now
			end
			state.Target = target :: CFrame
			state.Duration = duration
		elseif duration ~= state.Duration then
			if now >= state.StartedAt + state.Duration then
				state.Start = state.Applied
				state.StartedAt = now
			end
			state.Duration = duration
		end

		local progress = math.clamp((now - state.StartedAt) / state.Duration, 0, 1)
		local eased = progress * 0.88 + progress * progress * (3 - 2 * progress) * 0.12
		state.Applied = state.Start:Lerp(state.Target, eased)

		neck.Transform = state.Applied * neck.Transform
		seen[model] = true
	end

	for model in appliedHeadTurns do
		if not seen[model] then
			appliedHeadTurns[model] = nil
		end
	end
end)

-- Whoever is driving the rig has to animate it: the humanoid's speed is known here on the frame it
-- changes, where the server hears about it a replication later -- long enough for a short step to be
-- finished before its clip starts. The server stops its own animator as it hands the rig over.
local function release()
	local active = job
	job = nil
	if active and active.Animator then
		active.Animator:Destroy()
	end
end

Mirror.OnClientEvent:Connect(function(model: Model?, mode: string?)
	if not model then
		release()
		return
	end
	if job and job.Model == model then return end -- already on it; keep the rhythm it has built up

	release()
	local humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
	-- The set is read here rather than sent with the handoff: `EnemyConfigs` is server-only, but what a
	-- Mimic animates with is authored shared, so this side can look its own up by name.
	local animator = nil
	if mode ~= "Spin" then
		animator = NpcAnimator.new(model, AnimationConfig.Sets.Mimic)
		animator:Start()
	end

	job = {
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		Animator = animator,
		Mode = mode or "Mirror",
		-- Rolled per encounter, so it is never the same beat behind you twice.
		Delay = randomRange(MimicConfig.ReactionDelayMin, MimicConfig.ReactionDelayMax),
		Seed = math.random() * 100,
		Forward = MimicMotion.NewKey(),
		Right = MimicMotion.NewKey(),
		NextEmoteAt = os.clock() + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax),
		SpinStartedAt = if mode == "Spin" then os.clock() else nil,
		SpinDirection = if math.random() < 0.5 then -1 else 1,
		SpinHeight = nil,
	}
end)

local function onCharacter(character: Model)
	trail = nil

	local humanoid = character:WaitForChild("Humanoid", CHARACTER_TIMEOUT) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", CHARACTER_TIMEOUT) :: BasePart?
	-- Respawning during that wait leaves this character stale; the newer one has its own call coming.
	if not humanoid or not rootPart or localPlayer.Character ~= character then return end

	trail = MotionTrail.new(humanoid, rootPart)
end

if localPlayer.Character then
	onCharacter(localPlayer.Character)
end
localPlayer.CharacterAdded:Connect(onCharacter)

RunService.Heartbeat:Connect(function(deltaTime: number)
	local own = trail
	if own then
		own:Record()
	end

	local active = job
	if not active then return end
	if not active.Model:IsDescendantOf(workspace) then
		release()
		return
	end

	-- Dying, or waiting on a respawn, is a pause rather than the end of the job. The server decides
	-- when the act is over and says so; dropping it here instead would hand the rig back to nobody --
	-- the server has already let go of it, so it would stand frozen for the rest of the stalk.
	if not own or own.Humanoid.Health <= 0 then return end

	drive(active, own, deltaTime)
end)

return MimicService
