local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local MathService = require(ReplicatedStorage.Services.MathService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local POLL = 0.1
local ABANDON_DISTANCE_SCALE = 0.6
local FLOOR_PROBE_UP = 2
local FLOOR_PROBE_DEPTH = 12

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

function Peek.GetFindOptions(config): PeekSpotService.FindOptions
	return {
		MinDistance = config.MinPeekDistance,
		MaxDistance = config.MaxPeekDistance,
		RearArc = config.RearArc,
		ViewCone = config.ViewCone,
		FogFraction = config.PeekFogFraction,
	}
end

function Peek.Enter(npc: any)
	if npc.Peeking then return end
	npc.Peeking = true
	npc.Target = nil
	npc.Lean = 0
	npc.PeeksLeft = math.random(npc.Config.PeekCountMin, npc.Config.PeekCountMax)

	npc:StopMoving()
	npc:SetSpeed(0)
	npc.Animator:SetMovementTrack(nil)
	npc.Humanoid.EvaluateStateMachine = false
	npc.RootPart.Anchored = true
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
	npc.Lean = 0
	npc.Spot, npc.Audience = nil, nil

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

local function placeAt(npc: any, spot: PeekSpotService.PeekSpot, player: Player, lean: number)
	local target = getAliveRoot(player)
	npc.RootPart.CFrame = PeekSpotService.PoseAt(spot, lean, target and target.Position)
	npc.Lean = lean
end

local function slide(
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	targetLean: number,
	shouldStop: (() -> boolean)?
): boolean
	local startLean = npc.Lean or 0
	local travel = math.abs(targetLean - startLean)
	if travel < 1e-3 then
		placeAt(npc, spot, player, targetLean)
		return true
	end

	local startedAt = os.clock()
	local scaled = duration * travel

	while true do
		local alpha = math.clamp((os.clock() - startedAt) / scaled, 0, 1)
		placeAt(npc, spot, player, startLean + (targetLean - startLean) * alpha)
		if alpha >= 1 then return true end
		if shouldStop and shouldStop() then return false end
		RunService.Heartbeat:Wait()
	end
end

local function hold(
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	shouldStop: (() -> boolean)?
): boolean
	local expiresAt = os.clock() + duration

	while os.clock() < expiresAt do
		if shouldStop and shouldStop() then return false end
		placeAt(npc, spot, player, 1)
		RunService.Heartbeat:Wait()
	end
	return true
end

local function isArcOnScreen(npc: any, spot: PeekSpotService.PeekSpot): boolean
	local views = EnemyObservationService:GetViews()
	for _, lean in { 0.5, 1 } do
		for _, point in PeekSpotService.LeanPoints(spot, lean) do
			for _, view in views do
				if EnemyObservationService.IsWithinCone(view, point, npc.Config.ViewCone) then
					return true
				end
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

	placeAt(npc, spot, player, 0)
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
				placeAt(npc, spot, player, 0)
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

		if not isArcOnScreen(npc, spot) then break end

		placeAt(npc, spot, player, 0)
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

	local leanedOut = slide(npc, spot, player, npc.Config.LeanTime, 1, shouldStop)
	if leanedOut then
		local duration = randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax)
		hold(npc, spot, player, duration, shouldStop)
	end

	return "Retreat", npc, spot, player, caught, walkedUp, lost, leanedOut
end

local function retreat(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	caught: boolean,
	walkedUp: boolean,
	lost: boolean,
	leanedOut: boolean
)
	if caught then
		if not walkedUp then
			task.wait(npc.Config.SeenHoldTime or 0)
		end
		slide(npc, spot, player, npc.Config.RetreatTime, 0)
		return finish(npc, "Seen", player)
	end
	slide(npc, spot, player, npc.Config.RetreatTime, 0)

	if leanedOut then
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
