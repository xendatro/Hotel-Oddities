--- @class Rush
--- A fast, anchored enemy with no Humanoid. Its route and warning schedule are decided before it
--- enters the map; once spawned it only has to sweep along that route and kill exposed players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DeathService = require(ServerStorage.Services.DeathService)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local ENEMY_TAG = "Enemy"
local RUSH_TAG = "Rush"
local MINIMUM_LEG = 1e-3

local Rush = {}
Rush.__index = Rush
Rush.ClassName = "Rush"

local function distanceToSegment(point: Vector3, origin: Vector3, destination: Vector3): number
	local offset = destination - origin
	local lengthSquared = offset:Dot(offset)
	if lengthSquared < MINIMUM_LEG then return (point - origin).Magnitude end

	local alpha = math.clamp((point - origin):Dot(offset) / lengthSquared, 0, 1)
	return (point - origin:Lerp(destination, alpha)).Magnitude
end

function Rush.new(model: Model, config, route: { Vector3 }, warningToken)
	local self = setmetatable({}, Rush)

	self.Model = model
	self.Config = config
	self.RootPart = model.Rush :: BasePart
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

function Rush:_killAlong(origin: Vector3, destination: Vector3)
	for _, player in Players:GetPlayers() do
		if RoomService:IsInRoom(player) then continue end
		-- It has no perception to spare anybody with, so this is the only place a Rush can honour a
		-- vanish: it sweeps the corridor exactly as it would have, and whoever is not there is not hit.
		if Vanished.Is(player.Character) then continue end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0
			and distanceToSegment(root.Position, origin, destination) <= self.Config.KillRange then
			DeathService:RecordCause(player, self.EnemyId)
			humanoid.Health = 0
		end
	end
end

function Rush:TravelRoute()
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

function Rush:Start()
	if self.Active then return end
	self.Active = true

	self.RootPart.Anchored = true
	self.Model:AddTag(ENEMY_TAG)
	self.Model:AddTag(RUSH_TAG)
	self.StateMachine:Start()
end

function Rush:Despawn()
	if not self.Active then return end
	self.Active = false
	self.WarningToken.Cancelled = true

	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(RUSH_TAG)

	task.defer(function()
		self.StateMachine:Stop()
		self.Model:Destroy()
	end)
end

return Rush
