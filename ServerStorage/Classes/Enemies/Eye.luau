local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local EyeConfig = require(ReplicatedStorage.Configs.EyeConfig)
local DeathService = require(ServerStorage.Services.DeathService)
local EnemyBase = require(ServerStorage.Classes.EnemyBase)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EyeHit = require(ServerStorage.Services.EyeHitService).Remote
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local STUNNED_ATTRIBUTE = "Stunned"
local DAMAGE_INTERVAL = 0.05
local IDLE_ANIMATION_NAME = "eye_idle"

local Eye = EnemyBase.extend("Eye")
Eye.Tags = { "Enemy", "Eye", "Observable" }

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
	if not character or not CharacterService.IsAlive(character) then return nil end
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
	local fogStart, fogEnd = EnemyObservationService:GetFogRange(player)
	local damageDistance = self.Config.ObservationRange
	if fogStart and fogEnd then
		damageDistance = fogStart + (fogEnd - fogStart) * EyeConfig.DamageFogFraction
	end
	local eye = EnemyObservationService:GetView(player)
	if (boundsCFrame.Position - (eye or root.Position)).Magnitude - radius > damageDistance then
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
	local self = EnemyBase.new(model, config, Eye)

	self.AnimationTrack = nil :: AnimationTrack?
	self.DamageProgress = {}
	self.StateMachine = StateMachine.new({
		Stare = stare,
		Stunned = stunned,
	}, {
		Impact = { "Stare" },
	}, {}, "Stare", self)

	return self
end

function Eye:OnStart()
	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local controller = self.Model:WaitForChild("AnimationController") :: AnimationController
	local animator = controller:WaitForChild("Animator") :: Animator
	local animations = ReplicatedStorage:WaitForChild("Animations")
	local animation = animations:WaitForChild(IDLE_ANIMATION_NAME) :: Animation
	local track = animator:LoadAnimation(animation)
	track.Looped = true
	track:Play()
	self.AnimationTrack = track

	ByModel[self.Model] = self
end

function Eye:OnDespawn(): number?
	ByModel[self.Model] = nil

	if self.AnimationTrack then
		self.AnimationTrack:Stop()
		self.AnimationTrack:Destroy()
		self.AnimationTrack = nil
	end
	return nil
end

return Eye
