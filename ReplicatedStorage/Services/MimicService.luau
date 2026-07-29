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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	Animator: NpcAnimator.NpcAnimator,
	Delay: number,
	Seed: number,
	Forward: MimicMotion.Key,
	Right: MimicMotion.Key,
	NextEmoteAt: number,
}

local trail: MotionTrail.MotionTrail? = nil
local job: Job? = nil

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function randomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
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

local function drive(active: Job, own: MotionTrail.MotionTrail, deltaTime: number)
	local humanoid, root = active.Humanoid, active.RootPart

	-- The server zeroes the speed to hold a mimic still -- a stun, or the moment before it despawns.
	-- Driving through that would leave it swivelling on the spot while it is meant to be frozen.
	if humanoid.WalkSpeed <= 0 or humanoid.Health <= 0 then return end

	local offset = flatten(own.RootPart.Position - root.Position)
	if offset.Magnitude < 1e-3 then return end
	local forward = offset.Unit

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

	-- Waiting on you with nothing to copy, it amuses itself. The animator drops the emote the moment
	-- the rig takes a step, so the timer only has to keep them apart, not police the overlap -- and it
	-- restarts while moving so one never lands the instant it comes to a stop.
	if direction.Magnitude > 1e-3 then
		active.NextEmoteAt = clock + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax)
	elseif clock >= active.NextEmoteAt then
		active.Animator:PlayEmote()
		active.NextEmoteAt = clock + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax)
	end

	-- First person: it looks where its camera would be pointed, which is at you. It never turns to
	-- follow its own feet, so a sidestep is a sidestep rather than a pirouette. Its aim lags by the
	-- same beat its keys do, and wanders while it holds you.
	local watching = if sample then sample.Position else own.RootPart.Position
	local look = MimicMotion.Drift(watching - root.Position, clock, active.Seed)
	root.CFrame = MimicMotion.Turn(root.CFrame, look, deltaTime)
end

-- Whoever is driving the rig has to animate it: the humanoid's speed is known here on the frame it
-- changes, where the server hears about it a replication later -- long enough for a short step to be
-- finished before its clip starts. The server stops its own animator as it hands the rig over.
local function release()
	local active = job
	job = nil
	if active then
		active.Animator:Destroy()
	end
end

Mirror.OnClientEvent:Connect(function(model: Model?)
	if not model then
		release()
		return
	end
	if job and job.Model == model then return end -- already on it; keep the rhythm it has built up

	release()
	local humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
	local animator = NpcAnimator.new(model)
	animator:Start()

	job = {
		Model = model,
		Humanoid = humanoid,
		RootPart = rootPart,
		Animator = animator,
		-- Rolled per encounter, so it is never the same beat behind you twice.
		Delay = randomRange(MimicConfig.ReactionDelayMin, MimicConfig.ReactionDelayMax),
		Seed = math.random() * 100,
		Forward = MimicMotion.NewKey(),
		Right = MimicMotion.NewKey(),
		NextEmoteAt = os.clock() + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax),
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
