local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EnemyDespawnService = {}
if not RunService:IsClient() then return EnemyDespawnService end

local Config = require(ReplicatedStorage.Configs.EnemyDespawnConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local AudioService = require(ReplicatedStorage.Services.AudioService)

local soundTemplate = Instance.new("AudioEmitter")
soundTemplate.Name = "EnemyDespawnPoof"
soundTemplate:SetDistanceAttenuation({ [0] = 1, [8] = 1, [Config.SoundMaxDistance] = 0 })
local soundPlayer = Instance.new("AudioPlayer")
soundPlayer.Name = "Player"
soundPlayer.Asset = Config.SoundId
soundPlayer.Volume = Config.SoundVolume
soundPlayer.Parent = soundTemplate
AudioService:Wire(soundPlayer, soundTemplate)

function EnemyDespawnService:Emit(position: Vector3, bodySize: Vector3, body: Model?)
	local camera = workspace.CurrentCamera
	if not camera or (camera.CFrame.Position - position).Magnitude > Config.MaxDistance then return end
	local diameter = Config.ScaleMultiplier * math.min(math.max(bodySize.X, bodySize.Y, bodySize.Z) * Config.SizeFraction, Config.MaximumSize)
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
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.2, 0.28),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = holder
	local burst = emitter:Clone()
	burst.Name = "DustBurst"
	burst.Texture = Config.BurstTexture
	burst.Lifetime = NumberRange.new(0.22, 0.35)
	burst.Speed = NumberRange.new(diameter * 0.04, diameter * 0.1)
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, diameter * 0.15),
		NumberSequenceKeypoint.new(0.18, diameter * 0.6),
		NumberSequenceKeypoint.new(1, diameter * 0.72),
	})
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.35, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Parent = holder
	local powder = emitter:Clone()
	powder.Name = "PowderFlecks"
	powder.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	powder.Texture = Config.PowderTexture
	powder.Lifetime = NumberRange.new(0.25, 0.45)
	powder.Speed = NumberRange.new(diameter * 0.25, diameter * 0.45)
	powder.Drag = 5
	powder.Acceleration = Vector3.new(0, -diameter * 0.2, 0)
	powder.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, diameter * 0.1),
		NumberSequenceKeypoint.new(0.4, diameter * 0.12),
		NumberSequenceKeypoint.new(1, 0),
	})
	powder.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	powder.Parent = holder
	holder.Parent = workspace
	task.delay(0.05, function()
		if not holder.Parent then return end
		local playback = AudioService:Play3DSound(soundTemplate, holder, false, "SFX")
		playback.Ended:Once(function()
			task.delay(Config.Lifetime.Max + 0.2, function()
				holder:Destroy()
			end)
		end)
		if body and body.Parent then
			for _, part in body:GetDescendants() do
				if part:IsA("BasePart") or part:IsA("Decal") then
					TweenService:Create(part, TweenInfo.new(Config.FadeDuration, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
				end
			end
		end
		burst:Emit(Config.BurstCount)
		emitter:Emit(Config.ParticleCount)
		powder:Emit(Config.PowderCount)
	end)
	Debris:AddItem(holder, 30)
end

local remote = CommunicationService.Get("Enemies", "DespawnPoof")
remote.OnClientEvent:Connect(function(position, size, body)
	EnemyDespawnService:Emit(position, size, body)
end)

return EnemyDespawnService
