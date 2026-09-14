local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyDespawnService = {}
if not RunService:IsClient() then return EnemyDespawnService end

local Config = require(ReplicatedStorage.Configs.EnemyDespawnConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

function EnemyDespawnService:Emit(position: Vector3, bodySize: Vector3)
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > Config.MaxDistance then return end
	local diameter = math.min(math.max(bodySize.X, bodySize.Y, bodySize.Z) * Config.SizeFraction, Config.MaximumSize)
	if diameter <= 0 then return end
	local holder = Instance.new("Part")
	holder.Name = "EnemyDespawnPoof"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.one * diameter * 0.15
	holder.Position = position
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Powder"
	emitter.Texture = Config.Texture
	emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	emitter.FlipbookStartRandom = false
	emitter.Color = ColorSequence.new(Config.Color)
	emitter.LightEmission = 0.15
	emitter.LightInfluence = 0
	emitter.Rate = 0
	emitter.Lifetime = Config.Lifetime
	emitter.Speed = NumberRange.new(diameter * 0.08, diameter * 0.18)
	emitter.Drag = 4
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rotation = NumberRange.new(-180, 180)
	emitter.RotSpeed = NumberRange.new(-30, 30)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, diameter * 0.3),
		NumberSequenceKeypoint.new(0.2, diameter * 0.65),
		NumberSequenceKeypoint.new(1, diameter * 0.8),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	holder.Parent = workspace
	emitter:Emit(Config.ParticleCount)
	Debris:AddItem(holder, Config.Lifetime.Max + 0.2)
end

local remote = CommunicationService.Get("Enemies", "DespawnPoof")
remote.OnClientEvent:Connect(function(position, size)
	EnemyDespawnService:Emit(position, size)
end)

return EnemyDespawnService
