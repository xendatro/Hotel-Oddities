local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local MathService = require(ReplicatedStorage.Services.MathService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local PeekPoseConfig = require(ServerStorage.Configs.PeekPoseConfig)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local POLL = 0.1
local ABANDON_DISTANCE_SCALE = 0.6
local FLOOR_PROBE_UP = 2
local FLOOR_PROBE_DEPTH = 12
local DEFAULT_ROOT_HEIGHT = 3
local WITHDRAW_GRACE = 0.5
local POSE_KEYS = { "PeekLeft", "PeekRight" }

local Peek = {}

Peek.StateNames = { "Seek", "Follow", "Lurk", "Peek", "Retreat", "Rest" }

local function randomBetween(minimum: number, maximum: number): number
	return math.random() * (maximum - minimum) + minimum
end

local function getAliveRoot(player: Player?): BasePart?
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and humanoid and humanoid.Health > 0 then return root end
	return nil
end

local function rigMetrics(config): (number, number)
	local enemies = ReplicatedStorage:FindFirstChild("Enemies")
	local template = enemies and enemies:FindFirstChild(config.Model)
	if not template or not template:IsA("Model") then return 1, DEFAULT_ROOT_HEIGHT end

	local humanoid = template:FindFirstChildOfClass("Humanoid")
	local root = template:FindFirstChild("HumanoidRootPart")
	local rootHeight = if humanoid and root and root:IsA("BasePart")
		then humanoid.HipHeight + root.Size.Y / 2
		else DEFAULT_ROOT_HEIGHT
	return template:GetScale(), rootHeight
end

function Peek.GetFindOptions(config): PeekSpotService.FindOptions
	local scale, rootHeight = rigMetrics(config)
	return {
		MinDistance = config.MinPeekDistance,
		MaxDistance = config.MaxPeekDistance,
		RearArc = config.RearArc,
		ViewCone = config.ViewCone,
		FogFraction = config.PeekFogFraction,
		Exposure = config.PeekExposure,
		Scale = scale,
		RootHeight = rootHeight,
	}
end

local function poseId(npc: any, side: string): number?
	local set = npc.Config.Animations
	local id = if set then set[if side == "Right" then "PeekRight" else "PeekLeft"] else nil
	return if type(id) == "number" then id else nil
end

function Peek.Enter(npc: any)
	if npc.Peeking then return end
	npc.Peeking = true
	npc.Target = nil
	npc.PeeksLeft = math.random(npc.Config.PeekCountMin, npc.Config.PeekCountMax)

	npc:StopMoving()
	npc:SetSpeed(0)
	npc.Animator:SetMovementTrack(nil)
	npc.Humanoid.EvaluateStateMachine = false
	npc.RootPart.Anchored = true

	local set = npc.Config.Animations
	if set then
		for _, key in POSE_KEYS do
			if type(set[key]) == "number" then
				npc.Animator:PreloadPose(set[key])
			end
		end
	end
end

local function standUpright(npc: any)
	local root = npc.RootPart
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { npc.Model }
	params.RespectCanCollide = true
	params.CollisionGroup = root.CollisionGroup

	local origin = root.Position
	local hit = workspace:Raycast(origin + Vector3.yAxis * FLOOR_PROBE_UP, Vector3.yAxis * -FLOOR_PROBE_DEPTH, params)
	local height = npc.Humanoid.HipHeight + root.Size.Y / 2
	local position = if hit then Vector3.new(origin.X, hit.Position.Y + height, origin.Z) else origin

	local look = MathService.Horizontal(root.CFrame.LookVector)
	if look.Magnitude < 1e-3 then
		look = Vector3.zAxis
	end
	root.CFrame = CFrame.lookAt(position, position + look.Unit)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function Peek.Exit(npc: any)
	if not npc.Peeking then return end
	npc.Peeking = false
	npc.Spot, npc.Audience = nil, nil

	npc.Animator:EndPose(0)
	standUpright(npc)
	npc.RootPart.Anchored = false
	npc.Humanoid.EvaluateStateMachine = true
	npc.Humanoid:ChangeState(Enum.HumanoidStateType.Running)
	npc:SetSpeed(npc.Config.WalkSpeed)
end

local function finish(npc: any, reason: string, player: Player?)
	Peek.Exit(npc)
	return npc:OnPeekFinished(reason, player)
end

local function placeHidden(npc: any, spot: PeekSpotService.PeekSpot)
	npc.RootPart.CFrame = spot.HiddenRoot
end

local function placePeeking(npc: any, spot: PeekSpotService.PeekSpot): boolean
	local id = poseId(npc, spot.Side)
	npc.RootPart.CFrame = spot.Root
	if not id then return false end
	npc.Animator:HoldPose(id, 0)
	return true
end

local function withdraw(npc: any, spot: PeekSpotService.PeekSpot, stare: boolean)
	if npc.Animator:PoseTime() then
		npc.Animator:PlayPose(if stare then nil else PeekPoseConfig.MotionStart)
		local deadline = os.clock() + PeekPoseConfig.Length + WITHDRAW_GRACE
		while os.clock() < deadline do
			local time = npc.Animator:PoseTime()
			if not time or time >= PeekPoseConfig.Settled then break end
			RunService.Heartbeat:Wait()
		end
	end
	placeHidden(npc, spot)
	npc.Animator:EndPose(0)
end

local function hold(duration: number, shouldStop: (() -> boolean)?): boolean
	local expiresAt = os.clock() + duration

	while os.clock() < expiresAt do
		if shouldStop and shouldStop() then return false end
		RunService.Heartbeat:Wait()
	end
	return true
end

local function isPeekOnScreen(npc: any, spot: PeekSpotService.PeekSpot): boolean
	local views = EnemyObservationService:GetViews()
	for _, point in PeekSpotService.PeekPoints(spot) do
		for _, view in views do
			if EnemyObservationService.IsWithinCone(view, point, npc.Config.ViewCone) then
				return true
			end
		end
	end
	return false
end

local function watchSight(npc: any, spot: PeekSpotService.PeekSpot, player: Player): () -> boolean
	local options = Peek.GetFindOptions(npc.Config)
	local checkedAt, lostSince = -math.huge, nil :: number?

	return function(): boolean
		local now = os.clock()
		if now - checkedAt >= POLL then
			checkedAt = now
			if PeekSpotService:IsInSight(spot, player, options) then
				lostSince = nil
			else
				lostSince = lostSince or now
			end
		end
		return lostSince ~= nil and now - lostSince >= npc.Config.FollowLostTime
	end
end

local function getAudience(npc: any): Player?
	local nearest, nearestDistance = nil, math.huge
	local origin = npc.RootPart.Position

	for _, player in Players:GetPlayers() do
		local root = getAliveRoot(player)
		if root then
			local distance = (root.Position - origin).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = player, distance
			end
		end
	end
	return nearest
end

local function seek(_changeState: StateMachine.ChangeState, npc: any)
	Peek.Enter(npc)

	if npc:IsObserved() then
		return finish(npc, "Seen")
	end

	local spot, player = npc.Spot, npc.Audience
	npc.Spot, npc.Audience = nil, nil
	if not getAliveRoot(player) then
		spot, player = nil, getAudience(npc)
	end

	if not player then
		return finish(npc, "Lost")
	end
	if not spot then
		return "Follow", npc, player, 0
	end

	placeHidden(npc, spot)
	return "Lurk", npc, spot, player
end

local function follow(_changeState: StateMachine.ChangeState, npc: any, player: Player, delay: number)
	local config = npc.Config
	local options = Peek.GetFindOptions(config)
	local startedAt = os.clock()
	local searchAt = startedAt + delay

	while true do
		if npc:IsObserved() then
			return finish(npc, "Seen", player)
		end
		if not getAliveRoot(player) then
			return finish(npc, "Lost")
		end

		local now = os.clock()
		if now - startedAt >= config.FollowGiveUpTime then
			return finish(npc, "Lost", player)
		end

		if now >= searchAt then
			local spot = PeekSpotService:Find(player, options)
			if spot and not npc:IsObserved() then
				placeHidden(npc, spot)
				return "Lurk", npc, spot, player
			end
			searchAt = os.clock() + config.FollowRetryInterval
		end
		task.wait(POLL)
	end
end

local function lurk(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local config = npc.Config
	local expiresAt = os.clock() + config.PeekWaitTime
	local abandonDistance = config.MinPeekDistance * ABANDON_DISTANCE_SCALE
	local isLost = watchSight(npc, spot, player)

	while true do
		if npc:IsObserved() then
			return finish(npc, "Seen", player)
		end

		local root = getAliveRoot(player)
		if not root then
			return "Seek", npc
		end
		if (root.Position - spot.Stand).Magnitude < abandonDistance or os.clock() >= expiresAt then
			return "Follow", npc, player, 0
		end
		if isLost() then
			return "Follow", npc, player, config.FollowDelay
		end

		if not isPeekOnScreen(npc, spot) then break end

		placeHidden(npc, spot)
		task.wait(POLL)
	end

	if not PeekSpotService:IsStillValid(spot, player, Peek.GetFindOptions(config)) then
		return "Follow", npc, player, 0
	end

	return "Peek", npc, spot, player
end

local function peek(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local abandonDistance = npc.Config.MinPeekDistance * ABANDON_DISTANCE_SCALE
	local isLost = watchSight(npc, spot, player)
	local caught, walkedUp, lost = false, false, false

	local function shouldStop(): boolean
		if npc:IsObserved() then
			caught = true
			return true
		end

		local root = getAliveRoot(player)
		if not root or (root.Position - spot.Stand).Magnitude < abandonDistance then
			caught, walkedUp = true, true
			return true
		end

		lost = isLost()
		return lost
	end

	local posed = placePeeking(npc, spot)
	hold(randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax), shouldStop)

	return "Retreat", npc, spot, player, caught, walkedUp, lost, posed
end

local function retreat(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	caught: boolean,
	walkedUp: boolean,
	lost: boolean,
	posed: boolean
)
	if caught then
		if not walkedUp then
			task.wait(npc.Config.SeenHoldTime or 0)
		end
		withdraw(npc, spot, not walkedUp)
		return finish(npc, "Seen", player)
	end
	withdraw(npc, spot, false)

	if posed then
		npc.PeeksLeft -= 1
	end
	if npc.PeeksLeft <= 0 then
		return finish(npc, "Done", player)
	end
	if lost then
		return "Follow", npc, player, npc.Config.FollowDelay
	end
	return "Rest", npc, spot, player
end

local function rest(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local config = npc.Config
	local expiresAt = os.clock() + randomBetween(config.RestTimeMin, config.RestTimeMax)
	local isLost = watchSight(npc, spot, player)

	while os.clock() < expiresAt do
		if npc:IsObserved() then
			return finish(npc, "Seen", player)
		end
		if isLost() then
			return "Follow", npc, player, config.FollowDelay
		end
		task.wait(POLL)
	end
	return "Follow", npc, player, 0
end

Peek.States = {
	Seek = seek,
	Follow = follow,
	Lurk = lurk,
	Peek = peek,
	Retreat = retreat,
	Rest = rest,
}

return Peek
