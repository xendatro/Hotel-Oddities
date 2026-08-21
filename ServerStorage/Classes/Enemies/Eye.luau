local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local DeathService = require(ServerStorage.Services.DeathService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EyeHit = require(ServerStorage.Services.EyeHitService).Remote
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local ENEMY_TAG = "Enemy"
local EYE_TAG = "Eye"
local OBSERVABLE_TAG = "Observable"
local STUNNED_ATTRIBUTE = "Stunned"
local DAMAGE_INTERVAL = 0.05

local Eye = {}
Eye.__index = Eye
Eye.ClassName = "Eye"

local ByModel: { [Model]: any } = {}

function Eye.FromModel(model: Instance?): any?
	return model and ByModel[model] or nil
end

local function damageRate(config, angle: number): number
	local nearness = math.clamp(1 - angle / config.FalloffAngle, 0, 1) ^ config.FalloffExponent
	return config.EdgeDamage + (config.CenterDamage - config.EdgeDamage) * nearness
end

local function hasVisor(character: Model): boolean
	local visor = character:FindFirstChild("Visor")
	return visor ~= nil and visor:IsA("Tool")
end

local function getVulnerable(player: Player, config): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not (character and humanoid and humanoid.Health > 0) then return nil end
	if Vanished.Is(character) then return nil end
	if hasVisor(character) then return nil end
	if config.RespectsSafeRooms and RoomService:IsInRoom(player) then return nil end
	return character
end

function Eye:GetViewAngle(player: Player): number?
	local character = getVulnerable(player, self.Config)
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end

	local boundsCFrame, boundsSize = self.Model:GetBoundingBox()
	local radius = boundsSize.Magnitude / 2
	if (boundsCFrame.Position - root.Position).Magnitude - radius > self.Config.ObservationRange then
		return nil
	end
	return EnemyObservationService:GetViewAngle(player, self.Model)
end

function Eye:_burnWatchers(deltaTime: number)
	for _, player in Players:GetPlayers() do
		local angle = self:GetViewAngle(player)
		if not angle then
			self.DamageProgress[player] = 0
			continue
		end

		local character = player.Character :: Model
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		local progress = (self.DamageProgress[player] or 0) + damageRate(self.Config, angle) * deltaTime
		local hitDamage = math.max(self.Config.HitDamage or 20, 1)
		while progress >= hitDamage and humanoid.Health > 0 do
			progress -= hitDamage
			local healthBefore = humanoid.Health
			local canKill = healthBefore <= hitDamage and not character:FindFirstChildOfClass("ForceField")
			if canKill then
				DeathService:RecordCause(player, self.EnemyId)
			end
			humanoid:TakeDamage(hitDamage)
			if humanoid.Health < healthBefore then
				EyeHit:FireClient(player, math.min(hitDamage, healthBefore))
			end
			if canKill and humanoid.Health > 0 then
				DeathService:ClearCause(player, self.EnemyId)
			end
		end
		self.DamageProgress[player] = progress
	end
end

local function stare(_changeState: StateMachine.ChangeState, eye: any)
	while true do
		local deltaTime = task.wait(DAMAGE_INTERVAL)
		eye:_burnWatchers(deltaTime)
	end
end

local function stunned(_changeState: StateMachine.ChangeState, eye: any, duration: number)
	eye.Model:SetAttribute(STUNNED_ATTRIBUTE, true)
	task.wait(duration)
	eye.Model:SetAttribute(STUNNED_ATTRIBUTE, nil)
	return "Stare", eye
end

function Eye.new(model: Model, config)
	local self = setmetatable({}, Eye)

	self.Model = model
	self.Config = config
	self.Active = false
	self.DamageProgress = {}
	self.StateMachine = StateMachine.new({
		Stare = stare,
		Stunned = stunned,
	}, {
		Impact = { "Stare" },
	}, {
		Lifetime = function()
			task.wait(self.Config.Lifetime)
			self:Despawn()
		end,
	}, "Stare", self)

	return self
end

function Eye:Start()
	if self.Active then return end
	self.Active = true

	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	self.Model:AddTag(ENEMY_TAG)
	self.Model:AddTag(EYE_TAG)
	self.Model:AddTag(OBSERVABLE_TAG)
	ByModel[self.Model] = self
	self.StateMachine:Start()
end

function Eye:Despawn()
	if not self.Active then return end
	self.Active = false
	ByModel[self.Model] = nil

	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(EYE_TAG)
	self.Model:RemoveTag(OBSERVABLE_TAG)

	task.defer(function()
		self.StateMachine:Stop()
		self.Model:Destroy()
	end)
end

return Eye
