--- @class Chaos
--- A fast, anchored enemy with no Humanoid. Its route and warning schedule are decided before it
--- enters the map; once spawned it only has to sweep along that route and kill exposed players.

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
--- Multiple of `KillRange` within which a player who was not caught still counts as having met it.
--- Three, so the band that discovers a Chaos without killing anybody is about two corridor widths --
--- close enough that it went past you, wide enough that it does not require having nearly died.
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

--- Stops every emitter on the model and returns how long what is already in the air has left to live.
--- Disabling an emitter only stops new particles, so destroying the model in the same breath cuts the
--- trail off mid-flight; this is the wait that lets it burn out instead. Read off the emitters rather
--- than hardcoded, so retiming the effect in Studio retimes the despawn with it.
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
		-- It has no perception to spare anybody with, so this is the only place a Chaos can honour a
		-- vanish: it sweeps the corridor exactly as it would have, and whoever is not there is not hit.
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
			-- Close enough to have been the thing that nearly killed them. A Chaos travels at seventy
			-- studs a second, so there is no looking at one -- the encounter is being in the corridor
			-- it came down and not being where it went, which is why this is what discovers it rather
			-- than a sighting rule. Survivors learn it; anybody who took the warning and left the
			-- corridor entirely does not, which is the correct trade for having played it safe.
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
		-- Nothing is left to kill anybody by now: both tags are off, `Active` is false, and the model
		-- is only still in the world so the trail it already threw can finish where it was thrown.
		task.wait(linger)
		self.Model:Destroy()
	end)
end

return Chaos
