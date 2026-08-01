--- @class Sisters
--- Two of them, abreast, walking the middle of the corridor. Mechanically they are a slow Rush,
--- killing anybody caught out in the open along the line they sweep. Everything else about them is
--- the opposite. Rush is an event you are warned about and survive by being anywhere else; the
--- Sisters announce nothing, touch no lights, and never leave. You get all the time in the world to
--- see them coming, and the only thing that costs you is standing in a corridor when they arrive.
---
--- They are never handed a route. Rush knows its whole path before it spawns because its light
--- warnings have to be scheduled against an arrival time; the Sisters have no warnings to schedule
--- and no end to plan towards, so they pick each corner one ahead of the one they are walking:
--- straight on where they can, never into a dead end, and biased away from the corridors they have
--- just come down so they do not settle into a circuit. That bias fades, which lets a corridor come
--- back around eventually rather than being spent for good.
---
--- Neither sister is steered directly. Both walk at a point a little further down the route than they
--- have got to, one on each side of it, and their own Humanoids do the walking and the turning. That
--- one decision is what makes them read as two people rather than two props:
---   * the point is always out of reach, so neither ever arrives, stops, and drops out of her walk
---     into an idle for a frame -- which is what a Humanoid does the instant it reaches a `MoveTo`;
---   * the point runs on ahead into the next corridor before they get to the junction, so the corner
---     is a curve they walk rather than a turn they perform on the spot;
---   * nothing is ever placed by hand, so there is nothing that can jump.
--- All that is left is keeping them level with each other, and that is a trim on their walking speed:
--- whichever has got ahead takes it a little easier until her sister is beside her again.
---
--- The pair is one enemy. `EnemyService` clones the single `ReplicatedStorage.Enemies.Sister` rig for
--- us, and this class takes the second sister from that one, so the two of them are always identical,
--- which is most of the point of them.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local HallwayGraphService = require(ServerStorage.Services.HallwayGraphService)
local RoomService = require(ServerStorage.Services.RoomService)

local ENEMY_TAG = "Enemy"
local SISTERS_TAG = "Sisters"
local COLLISION_GROUP = "Sisters"
local MINIMUM_LEG = 1e-3
local DIRECTION_TIE_EPSILON = 0.05
local PROGRESS_EPSILON = 0.5 -- studs of ground that count as having got somewhere
local SLOWEST_TRIM = 0.4 -- of `WalkSpeed`: the trim slows a sister down, it never stops her walking

type RouteNode = HallwayGraphService.RouteNode

local Sisters = {}
Sisters.__index = Sisters
Sisters.ClassName = "Sisters"

local function horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function distanceToSegment(point: Vector3, origin: Vector3, destination: Vector3): number
	local offset = destination - origin
	local lengthSquared = offset:Dot(offset)
	if lengthSquared < MINIMUM_LEG then return (point - origin).Magnitude end

	local alpha = math.clamp((point - origin):Dot(offset) / lengthSquared, 0, 1)
	return (point - origin:Lerp(destination, alpha)).Magnitude
end

-- The middle of the corridor at `node`. The graph's nodes sit at the height of the floor part itself,
-- and these are rigs standing on that floor rather than a part flying over it.
local function walkPosition(node: RouteNode, config): Vector3
	return node.Position + Vector3.yAxis * config.RouteHeight
end

-- The sisters pass through each other and nothing else. They walk `SideSpacing` apart down corridors
-- narrow enough to close that up on a corner, and two Humanoids shouldering one another out of line
-- is the one drift steering them cannot answer.
local function ensureCollisionGroup()
	if PhysicsService:IsCollisionGroupRegistered(COLLISION_GROUP) then return end

	PhysicsService:RegisterCollisionGroup(COLLISION_GROUP)
	PhysicsService:CollisionGroupSetCollidable(COLLISION_GROUP, COLLISION_GROUP, false)
end

-- Hands the rig to its own Humanoid, which is what walks it, turns it and animates it. Server
-- ownership keeps both sisters simulated where their path is being swept.
local function prepare(model: Model)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CollisionGroup = COLLISION_GROUP
			if descendant:CanSetNetworkOwnership() then
				descendant:SetNetworkOwner(nil)
			end
		end
	end

	local humanoid = model.Humanoid :: Humanoid
	-- Both on purpose rather than on the template's defaults: between them they are what walks her,
	-- turns her and drives her walk clip, and a rig authored with either switched off would stand
	-- there sliding along the corridor in a T-pose.
	humanoid.EvaluateStateMachine = true
	humanoid.AutoRotate = true -- she turns to face wherever she is walking; nothing here rotates her
	-- No nameplates. Two of them, identical, is the whole idea; a pair of captions over their heads
	-- answers at a glance the question of whether there is any difference between them.
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

-- `options` narrowed to those that pass, or left exactly as it was when that would leave nothing.
-- Every preference the Sisters have is one they will break sooner than stand still for.
local function prefer(options: { RouteNode }, predicate: (RouteNode) -> boolean): { RouteNode }
	local kept = {}
	for _, option in options do
		if predicate(option) then
			table.insert(kept, option)
		end
	end
	return if #kept > 0 then kept else options
end

--- @param startNode RouteNode -- the corridor node the pair is placed on
--- @param firstNode RouteNode -- and the one it sets off towards, which fixes its opening facing
function Sisters.new(model: Model, config, startNode: RouteNode, firstNode: RouteNode)
	local self = setmetatable({}, Sisters)

	self.Model = model
	self.Config = config
	self.Models = { model }
	self.Animators = {}

	-- Which step each node was last left on, against a count of steps taken. Ages rather than a plain
	-- visited set: a corridor they walked twenty corners ago should be worth as much as any other.
	-- Set before the first corner is chosen, because choosing one reads them.
	self.VisitedAt = {} :: { [RouteNode]: number }
	self.Step = 0

	-- The leg they are walking, and the corner past it. Knowing one corner ahead is what lets them
	-- start bending into it before they reach the junction.
	self.Origin = startNode
	self.Destination = firstNode
	self.After = self:ChooseNext(firstNode, startNode)
	self.Facing = horizontal(firstNode.Position - startNode.Position).Unit
	self.Progress = -math.huge -- furthest down this leg they have got, for spotting one they have stopped getting down
	self.StalledSince = 0
	self.LastPositions = {} :: { Vector3 } -- where each sister was last frame, for the kill sweep

	self.Active = false
	self.StateMachine = StateMachine.new({
		Walk = function()
			self:Patrol()
			coroutine.yield() -- the graph offered nowhere to go; nothing here will change that
		end,
	}, {}, {}, "Walk")

	return self
end

-- How much `node` is worth avoiding for having been walked recently: full penalty on the step they
-- left it, gone by `LoopMemory` steps later.
function Sisters:_recencyPenalty(node: RouteNode): number
	local visitedAt = self.VisitedAt[node]
	if not visitedAt then return 0 end

	local age = self.Step - visitedAt
	return self.Config.LoopPenalty * math.max(0, 1 - age / self.Config.LoopMemory)
end

--- The corner they take after `node`, having arrived from `previous`, or nil where there is no way
--- out at all. Straightness is scored against staleness rather than ranked above it, so carrying
--- straight on into a corridor they have just walked loses to turning off into one they have not.
function Sisters:ChooseNext(node: RouteNode, previous: RouteNode?): RouteNode?
	local options = {}
	for neighbor in node.Neighbors do
		table.insert(options, neighbor)
	end
	if #options == 0 then return nil end

	options = prefer(options, function(option: RouteNode)
		return HallwayGraphService:CountExits(option) > 1 -- never walk into something they must back out of
	end)
	options = prefer(options, function(option: RouteNode)
		return option ~= previous -- and never turn round on the spot while anywhere else is open
	end)

	local incoming = if previous then horizontal(node.Position - previous.Position).Unit else nil
	local bestScore = -math.huge
	local best = {}
	for _, option in options do
		local score = -self:_recencyPenalty(option)
		if incoming then
			score += incoming:Dot(horizontal(option.Position - node.Position).Unit)
		end

		if score > bestScore + DIRECTION_TIE_EPSILON then
			bestScore = score
			best = { option }
		elseif math.abs(score - bestScore) <= DIRECTION_TIE_EPSILON then
			table.insert(best, option)
		end
	end
	return best[math.random(1, #best)]
end

--- Halfway between the two of them: the pair's own position, taken from where they actually are
--- rather than from where anything decided they should be.
function Sisters:GetCenter(): Vector3
	local total = Vector3.zero
	for _, model in self.Models do
		total += (model.HumanoidRootPart :: BasePart).Position
	end
	return total / #self.Models
end

-- Moves them on to the next leg. Returns false at a dead end, which is the one thing that stops them.
function Sisters:_takeCorner(): boolean
	local nextNode = self.After or self:ChooseNext(self.Destination, self.Origin)
	if not nextNode then return false end

	self.Step += 1
	self.VisitedAt[self.Origin] = self.Step
	self.Origin, self.Destination = self.Destination, nextNode
	self.After = self:ChooseNext(self.Destination, self.Origin)
	-- Not zero: giving up on a blocked leg leaves them short of the corner they are now walking from,
	-- so their first honest progress down the new one is negative and still counts as getting somewhere.
	self.Progress = -math.huge
	self.StalledSince = os.clock()
	return true
end

-- The point they walk at: `LookAhead` studs further down the route than the pair has got, carried on
-- round the corner into the next corridor once the rest of this one is shorter than that. It is never
-- reachable, which is the point of it -- a Humanoid that arrives somewhere stops walking, and a
-- Humanoid that stops walking drops its walk clip for an idle until it sets off again.
function Sisters:_aimPoint(origin: Vector3, direction: Vector3, length: number, travelled: number): Vector3
	local ahead = math.max(travelled, 0) + self.Config.LookAhead
	if ahead <= length or not self.After then
		return origin + direction * ahead
	end

	local destination = origin + direction * length
	local nextLeg = horizontal(walkPosition(self.After, self.Config) - destination)
	if nextLeg.Magnitude < MINIMUM_LEG then
		return origin + direction * ahead
	end
	return destination + nextLeg.Unit * math.min(ahead - length, nextLeg.Magnitude)
end

-- Turns the pair's axis towards `direction`, by at most a frame's worth of turning. It only decides
-- which side of the aim point each sister walks on; how they themselves turn is their Humanoids'
-- business. Rate limiting it stops the two of them trading sides when the route doubles back.
function Sisters:_turnTowards(direction: Vector3, deltaTime: number)
	-- Signed, so an about-turn commits to one side instead of blending into nothing.
	local angle = math.atan2(self.Facing:Cross(direction).Y, self.Facing:Dot(direction))
	local maxTurn = math.rad(self.Config.TurnSpeed) * deltaTime
	self.Facing = (CFrame.Angles(0, math.clamp(angle, -maxTurn, maxTurn), 0) * self.Facing).Unit
end

-- Walks both sisters at `aim`, one either side of it, each trimmed to whether she is ahead of her
-- sister or behind her. The trim is what keeps them level, and it is bounded well clear of a standstill
-- so that neither of them ever stops walking to hold formation.
function Sisters:_drive(aim: Vector3, center: Vector3)
	local side = Vector3.yAxis:Cross(self.Facing).Unit * (self.Config.SideSpacing / 2)
	local marks = { aim - side, aim + side }

	for index, model in self.Models do
		local humanoid = model.Humanoid :: Humanoid
		local root = model.HumanoidRootPart :: BasePart
		local lead = horizontal(root.Position - center):Dot(self.Facing) -- studs ahead of her sister
		humanoid.WalkSpeed = math.clamp(
			self.Config.WalkSpeed - lead * self.Config.FormationTrim,
			self.Config.WalkSpeed * SLOWEST_TRIM,
			self.Config.CatchUpSpeed
		)
		humanoid:MoveTo(marks[index])
	end
end

-- Kills every exposed player either sister walked over since the last frame. A player in a room is
-- safe however close they came: the whole answer to the Sisters is to be off the corridor.
function Sisters:_sweep()
	for index, model in self.Models do
		local position = (model.HumanoidRootPart :: BasePart).Position
		local origin = self.LastPositions[index]
		self.LastPositions[index] = position

		for _, player in Players:GetPlayers() do
			if RoomService:IsInRoom(player) then continue end

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and humanoid and humanoid.Health > 0
				and distanceToSegment(root.Position, origin, position) <= self.Config.KillRange then
				humanoid.Health = 0
			end
		end
	end
end

-- One frame of walking. False once there is nowhere left to walk to.
function Sisters:_step(deltaTime: number): boolean
	local origin = walkPosition(self.Origin, self.Config)
	local leg = horizontal(walkPosition(self.Destination, self.Config) - origin)
	local length = leg.Magnitude
	local direction = if length > MINIMUM_LEG then leg.Unit else self.Facing
	local center = self:GetCenter()
	local travelled = horizontal(center - origin):Dot(direction)

	if travelled >= length then return self:_takeCorner() end

	-- A leg they have stopped getting anywhere down is one something is in the way of. Give up on it
	-- and take the next corner instead, rather than leaning on the obstacle for the rest of the round.
	if travelled > self.Progress + PROGRESS_EPSILON then
		self.Progress = travelled
		self.StalledSince = os.clock()
	elseif os.clock() - self.StalledSince > self.Config.StuckTime then
		return self:_takeCorner()
	end

	local aim = self:_aimPoint(origin, direction, length, travelled)
	local heading = horizontal(aim - center)
	if heading.Magnitude > MINIMUM_LEG then
		self:_turnTowards(heading.Unit, deltaTime)
	end
	self:_drive(aim, center)
	self:_sweep()
	return true
end

--- Corner after corner, for as long as they are in the map. They have no despawn of their own: the
--- pair leaves when something outside them clears the enemies, and not before.
function Sisters:Patrol()
	while self.Active do
		local deltaTime = RunService.Heartbeat:Wait()
		if not self.Active then return end
		if not self:_step(deltaTime) then return end
	end
end

function Sisters:Start()
	if self.Active then return end
	self.Active = true

	ensureCollisionGroup()
	local twin = self.Model:Clone()
	twin.Parent = self.Model.Parent
	table.insert(self.Models, twin)

	-- Stood on their marks, once, before either of them has taken a step. It is the only time anything
	-- here sets where a sister is.
	local side = Vector3.yAxis:Cross(self.Facing).Unit * (self.Config.SideSpacing / 2)
	local marks = { walkPosition(self.Origin, self.Config) - side, walkPosition(self.Origin, self.Config) + side }
	for index, model in self.Models do
		prepare(model)
		model:PivotTo(CFrame.lookAt(marks[index], marks[index] + self.Facing))

		local humanoid = model.Humanoid :: Humanoid
		humanoid.WalkSpeed = self.Config.WalkSpeed
		local animator = NpcAnimator.new(model)
		animator:Start()
		table.insert(self.Animators, animator)

		self.LastPositions[index] = (model.HumanoidRootPart :: BasePart).Position
		model:AddTag(ENEMY_TAG)
		model:AddTag(SISTERS_TAG)
	end

	self.StalledSince = os.clock()
	self.StateMachine:Start()
end

function Sisters:Despawn()
	if not self.Active then return end
	self.Active = false

	for _, model in self.Models do
		model:RemoveTag(ENEMY_TAG)
		model:RemoveTag(SISTERS_TAG)
	end

	task.defer(function()
		self.StateMachine:Stop()
		for _, animator in self.Animators do
			animator:Destroy()
		end
		for _, model in self.Models do
			model:Destroy()
		end
	end)
end

return Sisters
