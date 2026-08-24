local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationConfig = require(ReplicatedStorage.Configs.AnimationConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local MathService = require(ReplicatedStorage.Services.MathService)
local MimicConfig = require(ReplicatedStorage.Configs.MimicConfig)
local MimicMotion = require(ReplicatedStorage.Services.MimicMotionService)
local MotionTrail = require(ReplicatedStorage.Classes.MotionTrail)
local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)

local MimicService = {}

if not FLAGS.Enemies then
	return MimicService
end

local Mirror = CommunicationService.Get("Enemies", "Mirror") :: RemoteEvent
local Reveal = CommunicationService.Get("Enemies", "MimicReveal") :: RemoteEvent

local CHARACTER_TIMEOUT = 10

local localPlayer = Players.LocalPlayer

task.spawn(function()
	local flyAnimation = Instance.new("Animation")
	flyAnimation.AnimationId = `rbxassetid://{AnimationConfig.Animations.Fly}`
	local sting = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("MimicSting")
	local stingPlayer = sting:FindFirstChild("Player")
	pcall(ContentProvider.PreloadAsync, ContentProvider, { flyAnimation, stingPlayer or sting })
end)

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

local trail: MotionTrail.MotionTrail? = nil
local job: Job? = nil

local flatten = MathService.Horizontal
local randomRange = MathService.RandomRange

local function angleBetween(from: Vector3, to: Vector3): number
	local a, b = flatten(from), flatten(to)
	if a.Magnitude < 1e-3 or b.Magnitude < 1e-3 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

local clearParams = RaycastParams.new()
clearParams.FilterType = Enum.RaycastFilterType.Exclude
clearParams.RespectCanCollide = true
local clearFilterRoot: BasePart? = nil
local clearFilterCharacter: Model? = nil

local function isClear(root: BasePart, character: Model, direction: Vector3): boolean
	if clearFilterRoot ~= root or clearFilterCharacter ~= character then
		clearFilterRoot = root
		clearFilterCharacter = character
		clearParams.FilterDescendantsInstances = { root.Parent :: Instance, character }
	end
	return workspace:Raycast(root.Position, direction * MimicConfig.WallProbeDistance, clearParams) == nil
end

local neckCache: { [Model]: Instance } = {}
setmetatable(neckCache :: any, { __mode = "kv" })

local function getNeck(model: Model): any?
	local cached = neckCache[model]
	if cached and cached.Parent and cached:IsDescendantOf(model) then
		return cached
	end
	neckCache[model] = nil

	local head = model:FindFirstChild("Head")
	local neck = head and head:FindFirstChild("Neck")
	if neck then
		neckCache[model] = neck
	end
	return neck
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
	local eased = MathService.Smoothstep(progress)
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

	if humanoid.WalkSpeed <= 0 or humanoid.Health <= 0 then
		if active.Animator then
			active.Animator:SetMovementSpeed(0)
		end
		return
	end
	if active.Mode == "Spin" then
		driveSpin(active, own, os.clock())
		return
	end
	local animator = active.Animator
	if not animator then return end

	local offset = flatten(own.RootPart.Position - root.Position)
	if offset.Magnitude < 1e-3 then
		animator:SetMovementSpeed(0)
		return
	end
	local targetForward = offset.Unit

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
		direction = Vector3.zero
	end
	humanoid:Move(direction)
	animator:SetMovementSpeed(direction.Magnitude * humanoid.WalkSpeed)

	if direction.Magnitude > 1e-3 then
		active.NextEmoteAt = clock + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax)
	elseif clock >= active.NextEmoteAt then
		animator:PlayEmote()
		active.NextEmoteAt = clock + randomRange(MimicConfig.EmoteDelayMin, MimicConfig.EmoteDelayMax)
	end

	local watching = if sample then sample.Position else own.RootPart.Position
	local lookDirection = if active.BehindTurnAt and clock < active.BehindTurnAt
		then root.CFrame.LookVector
		else watching - root.Position
	local look = MimicMotion.Drift(lookDirection, clock, active.Seed)
	root.CFrame = MimicMotion.Turn(root.CFrame, look, deltaTime)
end

local function lockRotation(neck: Motor6D, targetPosition: Vector3): CFrame?
	local torso = neck.Part0
	local head = neck.Part1
	if not torso or not head then return nil end
	if (targetPosition - head.Position).Magnitude < 1e-3 then return nil end

	local desired = CFrame.lookAt(head.Position, targetPosition)
	return ((torso.CFrame * neck.C0):Inverse() * desired * neck.C1).Rotation
end

local function playerHeadPosition(userId: number): Vector3?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if not character then return nil end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head.Position end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position + Vector3.yAxis * 1.5 end
	return nil
end

type HeadLock = {
	Weight: number,
	Applied: CFrame,
	Start: CFrame?,
}
local headLocks: { [Model]: HeadLock } = {}

local TWITCH_REST_MIN = 0.5
local TWITCH_REST_MAX = 1.2
local TWITCH_ANGLE = math.rad(30)
local TWITCH_SNAPS_MIN = 2
local TWITCH_SNAPS_MAX = 4
local TWITCH_SNAP_MIN = 0.025
local TWITCH_SNAP_MAX = 0.055
local TWITCH_HOLD_MIN = 0.08
local TWITCH_HOLD_MAX = 0.16

type Twitch = {
	NextBurstAt: number,
	SnapsLeft: number,
	NextSnapAt: number,
	HoldUntil: number,
	Offset: CFrame,
}
local twitches: { [Model]: Twitch } = {}

local function updateTwitch(model: Model, neck: Motor6D, now: number)
	local twitch = twitches[model]
	if not twitch then
		twitch = {
			NextBurstAt = now + randomRange(TWITCH_REST_MIN, TWITCH_REST_MAX),
			SnapsLeft = 0,
			NextSnapAt = 0,
			HoldUntil = 0,
			Offset = CFrame.identity,
		}
		twitches[model] = twitch
	end

	if twitch.SnapsLeft > 0 then
		if now >= twitch.NextSnapAt then
			twitch.SnapsLeft -= 1
			twitch.Offset = CFrame.Angles(
				(math.random() - 0.5) * TWITCH_ANGLE,
				(math.random() - 0.5) * TWITCH_ANGLE * 2,
				(math.random() - 0.5) * TWITCH_ANGLE
			)
			twitch.NextSnapAt = now + randomRange(TWITCH_SNAP_MIN, TWITCH_SNAP_MAX)
			if twitch.SnapsLeft == 0 then
				twitch.HoldUntil = now + randomRange(TWITCH_HOLD_MIN, TWITCH_HOLD_MAX)
			end
		end
	elseif twitch.Offset ~= CFrame.identity then
		if now >= twitch.HoldUntil then
			twitch.Offset = CFrame.identity
			twitch.NextBurstAt = now + randomRange(TWITCH_REST_MIN, TWITCH_REST_MAX)
		end
	elseif now >= twitch.NextBurstAt then
		twitch.SnapsLeft = math.random(TWITCH_SNAPS_MIN, TWITCH_SNAPS_MAX)
		twitch.NextSnapAt = now
	end

	if twitch.Offset ~= CFrame.identity then
		neck.Transform = twitch.Offset * neck.Transform
	end
end

local EnemyModels: { [Model]: boolean } = {}

CollectionService:GetInstanceAddedSignal("Enemy"):Connect(function(instance)
	if instance:IsA("Model") then
		EnemyModels[instance] = true
	end
end)
CollectionService:GetInstanceRemovedSignal("Enemy"):Connect(function(instance)
	EnemyModels[instance :: Model] = nil
end)
for _, instance in CollectionService:GetTagged("Enemy") do
	if instance:IsA("Model") then
		EnemyModels[instance] = true
	end
end

RunService.PreSimulation:Connect(function(deltaTime: number)
	local now = os.clock()
	for model in EnemyModels do
		local userId = model:GetAttribute("MimicHeadLockUserId")

		if model:GetAttribute("EnemyId") == "Mimic"
			and model:GetAttribute("ChaseTargetUserId") ~= nil
			and type(userId) ~= "number"
		then
			local neck = getNeck(model)
			if neck then
				updateTwitch(model, neck, now)
			end
		elseif twitches[model] then
			twitches[model] = nil
		end

		local state = headLocks[model]
		if type(userId) == "number" then
			local neck = getNeck(model)
			if not neck then continue end
			if not state then
				state = { Weight = 0, Applied = neck.Transform.Rotation, Start = neck.Transform.Rotation }
				headLocks[model] = state
			end

			state.Weight = math.min(state.Weight + deltaTime / MimicConfig.HeadSnapDuration, 1)
			local position = playerHeadPosition(userId)
			if position then
				local rotation = lockRotation(neck, position)
				if rotation then
					local start = state.Start
					if state.Weight < 1 and start then
						local axis, angle = (start:Inverse() * rotation):ToAxisAngle()
						if angle < 0.35 then
							axis = Vector3.yAxis
						end
						state.Applied = start * CFrame.fromAxisAngle(axis, (angle - 2 * math.pi) * state.Weight)
					else
						state.Start = nil
						state.Applied = rotation
					end
				end
			end
			neck.Transform = if state.Start then state.Applied else neck.Transform:Lerp(state.Applied, state.Weight)
		elseif state then
			state.Weight -= deltaTime / MimicConfig.HeadUnlockTime
			local neck = if model:IsDescendantOf(workspace) then getNeck(model) else nil
			if state.Weight <= 0 or not neck then
				headLocks[model] = nil
			else
				neck.Transform = neck.Transform:Lerp(state.Applied, state.Weight)
			end
		end
	end

	for model in headLocks do
		if not model:IsDescendantOf(workspace) then
			headLocks[model] = nil
		end
	end
	for model in twitches do
		if not model:IsDescendantOf(workspace) then
			twitches[model] = nil
		end
	end
end)

local stingReverb: AudioReverb? = nil
local function getStingReverb(): AudioReverb
	if stingReverb then return stingReverb end

	local reverb = Instance.new("AudioReverb")
	reverb.Name = "MimicStingReverb"
	reverb.DecayTime = MimicConfig.RevealReverbDecayTime
	reverb.WetLevel = MimicConfig.RevealReverbWetLevel
	reverb.DryLevel = MimicConfig.RevealReverbDryLevel
	reverb.Parent = workspace:WaitForChild("Sounds")
	AudioService:Wire(reverb, AudioService:GetOutput())
	stingReverb = reverb
	return reverb
end

Reveal.OnClientEvent:Connect(function(_model: Model?)
	local reverb = getStingReverb()
	AudioService:Play2DSound(
		"MimicSting",
		false,
		"SFX",
		{ Volume = MimicConfig.RevealSoundVolume },
		reverb
	)
	AudioService:Play2DSound(
		"MimicSting",
		false,
		"SFX",
		{ Volume = MimicConfig.RevealSubVolume, PlaybackSpeed = MimicConfig.RevealSubSpeed },
		reverb
	)
end)

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
	if job and job.Model == model and job.Mode == (mode or "Mirror") then return end

	release()
	local humanoid = model:WaitForChild("Humanoid") :: Humanoid
	local rootPart = model:WaitForChild("HumanoidRootPart") :: BasePart
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

	if not own or own.Humanoid.Health <= 0 then
		if active.Animator then
			active.Animator:SetMovementSpeed(0)
		end
		return
	end

	drive(active, own, deltaTime)
end)

return MimicService
