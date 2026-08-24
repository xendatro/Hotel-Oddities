local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)
local EnemyBase = require(ServerStorage.Classes.EnemyBase)
local EnemyDiscoveryService = require(ServerStorage.Services.EnemyDiscoveryService)
local LightService = require(ServerStorage.Services.LightService)

local PROXIMITY_INTERVAL = 0.1

local Creep = EnemyBase.extend("Creep")
Creep.Tags = { "Enemy", "Creep" }

local function ambient()
	coroutine.yield()
end

local function randomColor(): Color3
	local colors = CreepConfig.EyeColors
	return colors[math.random(1, #colors)]
end

local function paint(plate: BasePart, color: Color3)
	for _, name in { "EyeLeft", "EyeRight" } do
		local eye = plate:FindFirstChild(name)
		if eye and eye:IsA("BasePart") then
			eye.Color = color
		end
	end
end

local function pickVariant()
	local variants = CreepConfig.Variants
	local total = 0
	for _, variant in variants do
		total += variant.Weight or 1
	end
	if total <= 0 then return variants[1] end

	local roll = math.random() * total
	for _, variant in variants do
		roll -= variant.Weight or 1
		if roll <= 0 then return variant end
	end
	return variants[#variants]
end

local function scatter(model: Model, plate: BasePart, variant)
	local wanted = math.random(variant.PairsMin or 1, variant.PairsMax or 1)
	local base = plate.CFrame
	local color = randomColor()
	paint(plate, color)
	if wanted <= 1 then return end

	local across = variant.SpreadAcross or 0
	local up = variant.SpreadUp or 0
	local along = variant.SpreadAlong or 0
	local spacing = CreepConfig.PairSpacing
	local tries = CreepConfig.PairPlacementTries

	local taken = { Vector3.zero }

	for _ = 2, wanted do
		local offset: Vector3? = nil

		for _ = 1, tries do
			local candidate = Vector3.new(
				(math.random() * 2 - 1) * across,
				(math.random() * 1.2 - 0.2) * up,
				(math.random() * 2 - 1) * along
			)

			local clear = true
			for _, other in taken do
				if (candidate - other).Magnitude < spacing then
					clear = false
					break
				end
			end

			if clear then
				offset = candidate
				break
			end
		end

		if not offset then continue end
		table.insert(taken, offset)

		local clone = plate:Clone()
		clone.CFrame = base * CFrame.new(offset)
		clone.Anchored = true
		if variant.MixedColors then
			paint(clone, randomColor())
		end
		clone.Parent = model
	end
end

function Creep.new(model: Model, config)
	local self = EnemyBase.new(model, config, Creep)

	self.RootPart = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	self.Variant = pickVariant()
	scatter(model, self.RootPart, self.Variant)
	self.LightClaim = nil
	self.Destroying = nil
	self.StateMachine = StateMachine.new({
		Ambient = ambient,
	}, {}, {
		Proximity = function()
			while true do
				task.wait(PROXIMITY_INTERVAL)

				for _, player in Players:GetPlayers() do
					if Vanished.Is(player.Character) then continue end
					local root = CharacterService.GetAliveRoot(player)
					if root and (root.Position - self.RootPart.Position).Magnitude <= self.Config.DespawnRange then
						EnemyDiscoveryService:GrantEvent(player, self.EnemyId)
						self:Despawn()
						return
					end
				end
			end
		end,
	}, "Ambient")

	return self
end

function Creep:OnStart()
	self.RootPart.Anchored = true
	self.LightClaim = LightService:DisableHallway(
		self.RootPart.Position,
		self.RootPart.CFrame.LookVector,
		self.Config.ConnectedHallwayLightRange,
		self.Config.DarkDistance
	)

	self.Destroying = self.Model.Destroying:Connect(function()
		LightService:Release(self.LightClaim)
	end)
end

function Creep:OnDespawn(): number?
	if self.Destroying then
		self.Destroying:Disconnect()
		self.Destroying = nil
	end
	LightService:Release(self.LightClaim)
	return nil
end

return Creep
