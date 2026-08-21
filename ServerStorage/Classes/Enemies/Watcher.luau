local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local NPC = require(ServerStorage.Classes.NPC)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local POLL = 0.1
local SEEN_HOLD_TIME = 0.7
local ABANDON_DISTANCE_SCALE = 0.6

local Watcher = NPC.extend("Watcher")

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

function Watcher.GetFindOptions(config): PeekSpotService.FindOptions
	return {
		MinDistance = config.MinPeekDistance,
		MaxDistance = config.MaxPeekDistance,
		RearArc = config.RearArc,
		ViewCone = config.ViewCone,
	}
end

function Watcher:_placeAt(spot: PeekSpotService.PeekSpot, player: Player, lean: number)
	local target = getAliveRoot(player)
	self.RootPart.CFrame = PeekSpotService.PoseAt(spot, lean, target and target.Position)
	self.Lean = lean
end

function Watcher:_slide(
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	targetLean: number,
	shouldStop: (() -> boolean)?
): boolean
	local startLean = self.Lean or 0
	local travel = math.abs(targetLean - startLean)
	if travel < 1e-3 then
		self:_placeAt(spot, player, targetLean)
		return true
	end

	local startedAt = os.clock()
	local scaled = duration * travel

	while true do
		local alpha = math.clamp((os.clock() - startedAt) / scaled, 0, 1)
		self:_placeAt(spot, player, startLean + (targetLean - startLean) * alpha)
		if alpha >= 1 then return true end
		if shouldStop and shouldStop() then return false end
		RunService.Heartbeat:Wait()
	end
end

function Watcher:_hold(
	spot: PeekSpotService.PeekSpot,
	player: Player,
	duration: number,
	shouldStop: (() -> boolean)?
): boolean
	local expiresAt = os.clock() + duration

	while os.clock() < expiresAt do
		if shouldStop and shouldStop() then return false end
		self:_placeAt(spot, player, 1)
		RunService.Heartbeat:Wait()
	end
	return true
end

function Watcher:_isArcOnScreen(spot: PeekSpotService.PeekSpot): boolean
	local views = EnemyObservationService:GetViews()
	for _, lean in { 0.5, 1 } do
		for _, point in PeekSpotService.LeanPoints(spot, lean) do
			for _, view in views do
				if EnemyObservationService.IsWithinCone(view, point, self.Config.ViewCone) then
					return true
				end
			end
		end
	end
	return false
end

function Watcher:_getAudience(): Player?
	local nearest, nearestDistance = nil, math.huge
	local origin = self.RootPart.Position

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
	if npc:IsObserved() then
		return "Despawn", npc
	end

	local spot, player = npc.Spot, npc.Audience
	npc.Spot, npc.Audience = nil, nil
	if not getAliveRoot(player) then
		spot, player = nil, nil
	end

	if not spot then
		player = npc:_getAudience()
		spot = player and PeekSpotService:Find(player, Watcher.GetFindOptions(npc.Config))
	end

	if not (player and spot) then
		npc.AttemptsLeft -= 1
		if npc.AttemptsLeft <= 0 then
			return "Despawn", npc
		end
		task.wait(npc.Config.RetryInterval)
		return "Seek", npc
	end

	npc:_placeAt(spot, player, 0)
	return "Lurk", npc, spot, player
end

local function lurk(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local expiresAt = os.clock() + npc.Config.PeekWaitTime
	local abandonDistance = npc.Config.MinPeekDistance * ABANDON_DISTANCE_SCALE

	while true do
		if npc:IsObserved() then
			return "Despawn", npc
		end

		local root = getAliveRoot(player)
		if not root then
			return "Seek", npc
		end
		if (root.Position - spot.Stand).Magnitude < abandonDistance then
			return "Seek", npc
		end
		if os.clock() >= expiresAt then
			return "Seek", npc
		end

		if not npc:_isArcOnScreen(spot) then break end

		npc:_placeAt(spot, player, 0)
		task.wait(POLL)
	end

	if not PeekSpotService:IsStillValid(spot, player, Watcher.GetFindOptions(npc.Config)) then
		return "Seek", npc
	end

	return "Peek", npc, spot, player
end

local function peek(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player
)
	local function isCaught()
		return npc:IsObserved()
	end

	local caught = not npc:_slide(spot, player, npc.Config.LeanTime, 1, isCaught)
	if not caught then
		local hold = randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax)
		caught = not npc:_hold(spot, player, hold, isCaught)
	end

	return "Retreat", npc, spot, player, caught
end

local function retreat(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	caught: boolean
)
	if caught then
		task.wait(SEEN_HOLD_TIME)
		npc:_slide(spot, player, npc.Config.RetreatTime, 0)
		return "Despawn", npc
	end
	npc:_slide(spot, player, npc.Config.RetreatTime, 0)

	npc.AttemptsLeft -= 1
	if npc.AttemptsLeft <= 0 then
		return "Despawn", npc
	end
	return "Rest", npc
end

local function rest(_changeState: StateMachine.ChangeState, npc: any)
	local expiresAt = os.clock() + randomBetween(npc.Config.RestTimeMin, npc.Config.RestTimeMax)

	while os.clock() < expiresAt do
		if npc:IsObserved() then
			return "Despawn", npc
		end
		task.wait(POLL)
	end
	return "Seek", npc
end

function Watcher.new(model: Model, config, spot: PeekSpotService.PeekSpot?, player: Player?)
	local self = NPC.new(model, config, Watcher)
	self.Spot = spot
	self.Audience = player
	self.Lean = 0
	return self
end

function Watcher:Start()
	self.Humanoid.EvaluateStateMachine = false
	self.RootPart.Anchored = true
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.AttemptsLeft = math.random(self.Config.PeekCountMin, self.Config.PeekCountMax)
	NPC.Start(self)
end

function Watcher:BuildStateMachine(): StateMachine.StateMachine
	return StateMachine.new({
		Seek = seek,
		Lurk = lurk,
		Peek = peek,
		Retreat = retreat,
		Rest = rest,
		Despawn = NPC.SharedStates.Despawn,
	}, {
		Impact = {},
	}, {}, "Seek", self)
end

return Watcher
