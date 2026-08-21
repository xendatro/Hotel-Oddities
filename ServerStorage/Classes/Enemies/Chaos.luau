local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DeathService = require(ServerStorage.Services.DeathService)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local ENEMY_TAG = "Enemy"
local CHAOS_TAG = "Chaos"
local MINIMUM_LEG = 1e-3
local NEAR_MISS_SCALE = 3

local Chaos = {}
Chaos.__index = Chaos
Chaos.ClassName = "Chaos"

local function distanceToSegment(point: Vector3, origin: Vector3, destination: Vector3): number
	local offset = destination - origin
	local lengthSquared = offset:Dot(offset)
	if lengthSquared < MINIMUM_LEG then return (point - origin).Magnitude end

	local alpha = math.clamp((point - origin):Dot(offset) / lengthSquared, 0, 1)
	return (point - origin:Lerp(destination, alpha)).Magnitude
end

local function stopParticles(model: Model): number
	local linger = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			linger = math.max(linger, descendant.Lifetime.Max)
		end
	end
	return linger
end

function Chaos.new(model: Model, config, route: { Vector3 }, warningToken)
	local self = setmetatable({}, Chaos)

	self.Model = model
	self.Config = config
	self.RootPart = model.Chaos :: BasePart
	self.Route = route
	self.WarningToken = warningToken
	self.Active = false
	self.StateMachine = StateMachine.new({
		Run = function()
			self:TravelRoute()
			return "Despawn"
		end,
		Despawn = function()
			self:Despawn()
			coroutine.yield()
		end,
	}, {}, {}, "Run")

	return self
end

function Chaos:_killAlong(origin: Vector3, destination: Vector3)
	for _, player in Players:GetPlayers() do
		if RoomService:IsInRoom(player) then continue end
		if Vanished.Is(player.Character) then continue end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and humanoid and humanoid.Health > 0) then continue end

		local distance = distanceToSegment(root.Position, origin, destination)
		if distance <= self.Config.KillRange then
			DeathService:RecordCause(player, self.EnemyId)
			humanoid.Health = 0
		elseif distance <= self.Config.KillRange * NEAR_MISS_SCALE then
			EnemyDiscoveryService:GrantEvent(player, self.EnemyId)
		end
	end
end

function Chaos:TravelRoute()
	for index = 2, #self.Route do
		if not self.Active then return end

		local origin = self.Route[index - 1]
		local destination = self.Route[index]
		local offset = destination - origin
		local duration = offset.Magnitude / self.Config.WalkSpeed
		if duration < MINIMUM_LEG then continue end

		local startedAt = os.clock()
		local previous = origin
		repeat
			RunService.Heartbeat:Wait()
			if not self.Active then return end

			local alpha = math.min((os.clock() - startedAt) / duration, 1)
			local position = origin:Lerp(destination, alpha)
			self.Model:PivotTo(CFrame.lookAt(position, position + offset))
			self:_killAlong(previous, position)
			previous = position
		until alpha >= 1
	end
end

function Chaos:Start()
	if self.Active then return end
	self.Active = true

	self.RootPart.Anchored = true
	self.Model:AddTag(ENEMY_TAG)
	self.Model:AddTag(CHAOS_TAG)
	self.StateMachine:Start()
end

function Chaos:Despawn()
	if not self.Active then return end
	self.Active = false
	self.WarningToken.Cancelled = true

	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(CHAOS_TAG)

	local linger = stopParticles(self.Model)

	task.defer(function()
		self.StateMachine:Stop()
		task.wait(linger)
		self.Model:Destroy()
	end)
end

return Chaos
