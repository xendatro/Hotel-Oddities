local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local PeekSpotService = require(ServerStorage.Services.PeekSpotService)

local POLL = 0.1
local ABANDON_DISTANCE_SCALE = 0.6

local Peek = {}

Peek.StateNames = { "Seek", "Lurk", "Peek", "Retreat", "Rest" }

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

function Peek.Exit(npc: any)
	if not npc.Peeking then return end
	npc.Peeking = false
	npc.Lean = 0
	npc.Spot, npc.Audience = nil, nil

	npc.RootPart.Anchored = false
	npc.Humanoid.EvaluateStateMachine = true
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
		spot, player = nil, nil
	end

	if not spot then
		player = player or getAudience(npc)
		spot = player and PeekSpotService:Find(player, Peek.GetFindOptions(npc.Config))
	end

	if not (player and spot) then
		npc.PeeksLeft -= 1
		if npc.PeeksLeft <= 0 then
			return finish(npc, "Lost")
		end
		task.wait(npc.Config.RetryInterval)
		return "Seek", npc
	end

	placeAt(npc, spot, player, 0)
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
			return finish(npc, "Seen", player)
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

		if not isArcOnScreen(npc, spot) then break end

		placeAt(npc, spot, player, 0)
		task.wait(POLL)
	end

	if not PeekSpotService:IsStillValid(spot, player, Peek.GetFindOptions(npc.Config)) then
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
	local abandonDistance = npc.Config.MinPeekDistance * ABANDON_DISTANCE_SCALE
	local walkedUp = false

	local function isCaught()
		if npc:IsObserved() then return true end

		local root = getAliveRoot(player)
		if not root or (root.Position - spot.Stand).Magnitude < abandonDistance then
			walkedUp = true
			return true
		end
		return false
	end

	local caught = not slide(npc, spot, player, npc.Config.LeanTime, 1, isCaught)
	if not caught then
		local duration = randomBetween(npc.Config.HoldTimeMin, npc.Config.HoldTimeMax)
		caught = not hold(npc, spot, player, duration, isCaught)
	end

	return "Retreat", npc, spot, player, caught, walkedUp
end

local function retreat(
	_changeState: StateMachine.ChangeState,
	npc: any,
	spot: PeekSpotService.PeekSpot,
	player: Player,
	caught: boolean,
	walkedUp: boolean?
)
	if caught then
		if not walkedUp then
			task.wait(npc.Config.SeenHoldTime or 0)
		end
		slide(npc, spot, player, npc.Config.RetreatTime, 0)
		return finish(npc, "Seen", player)
	end
	slide(npc, spot, player, npc.Config.RetreatTime, 0)

	npc.PeeksLeft -= 1
	if npc.PeeksLeft <= 0 then
		return finish(npc, "Done", player)
	end
	return "Rest", npc, player
end

local function rest(_changeState: StateMachine.ChangeState, npc: any, player: Player?)
	local expiresAt = os.clock() + randomBetween(npc.Config.RestTimeMin, npc.Config.RestTimeMax)

	while os.clock() < expiresAt do
		if npc:IsObserved() then
			return finish(npc, "Seen", player)
		end
		task.wait(POLL)
	end
	return "Seek", npc
end

Peek.States = {
	Seek = seek,
	Lurk = lurk,
	Peek = peek,
	Retreat = retreat,
	Rest = rest,
}

return Peek
