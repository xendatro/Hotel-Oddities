local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)
local DeathService = require(ServerStorage.Services.DeathService)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local EnemyBase = require(ServerStorage.Classes.EnemyBase)
local RoomService = require(ServerStorage.Services.RoomService)

local MINIMUM_LEG = 1e-3
local NEAR_MISS_SCALE = 3

local Chaos = EnemyBase.extend("Chaos")
Chaos.Tags = { "Enemy", "Chaos" }

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
	local self = EnemyBase.new(model, config, Chaos)

	self.RootPart = model.Chaos :: BasePart
	self.Route = route
	self.WarningToken = warningToken
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

		local root = CharacterService.GetAliveRoot(player)
		local humanoid = if root then CharacterService.GetHumanoid(root.Parent :: Model) else nil
		if not (root and humanoid) then continue end

		local distance = MathService.DistanceToSegment(root.Position, origin, destination)
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
		local alpha = 0
		repeat
			RunService.Heartbeat:Wait()
			if not self.Active then return end

			alpha = math.min((os.clock() - startedAt) / duration, 1)
			local position = origin:Lerp(destination, alpha)
			self.Model:PivotTo(CFrame.lookAt(position, position + offset))
			self:_killAlong(previous, position)
			previous = position
		until alpha >= 1
	end
end

function Chaos:OnStart()
	self.RootPart.Anchored = true
end

function Chaos:OnDespawn(): number?
	self.WarningToken.Cancelled = true
	return stopParticles(self.Model)
end

return Chaos
