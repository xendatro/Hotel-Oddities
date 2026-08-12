--- @class Creep
--- A stationary ambient enemy with no Humanoid. It extinguishes floor lights along its hallway and
--- disappears as soon as a player comes close.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local LightService = require(ServerStorage.Services.LightService)

local ENEMY_TAG = "Enemy"
local CREEP_TAG = "Creep"
local PROXIMITY_INTERVAL = 0.1

local Creep = {}
Creep.__index = Creep
Creep.ClassName = "Creep"

local function ambient()
	coroutine.yield()
end

function Creep.new(model: Model, config)
	local self = setmetatable({}, Creep)

	self.Model = model
	self.Config = config
	self.RootPart = model:FindFirstChildWhichIsA("BasePart", true) :: BasePart
	self.Active = false
	self.LightClaim = nil
	self.Destroying = nil
	self.StateMachine = StateMachine.new({
		Ambient = ambient,
	}, {}, {
		Proximity = function()
			while true do
				task.wait(PROXIMITY_INTERVAL)

				for _, player in Players:GetPlayers() do
					local character = player.Character
					local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and (root.Position - self.RootPart.Position).Magnitude <= self.Config.DespawnRange then
						self:Despawn()
						return
					end
				end
			end
		end,
	}, "Ambient")

	return self
end

function Creep:Start()
	if self.Active then return end
	self.Active = true

	self.RootPart.Anchored = true
	self.Model:AddTag(ENEMY_TAG)
	self.Model:AddTag(CREEP_TAG)
	self.LightClaim = LightService:DisableAlongHallway(self.RootPart.Position, self.Config.LightRange)

	-- A Creep is the one enemy holding something that outlives it: a stretch of hallway it has turned
	-- off. Going through `Despawn` hands that back, but anything that destroys the model without
	-- asking -- and the model outliving its object is exactly what `EnemyService` watches for -- would
	-- otherwise leave those lamps dark for the rest of the round with nothing left alive to claim them.
	-- Releasing twice is a no-op, so this costs the ordinary path nothing.
	self.Destroying = self.Model.Destroying:Connect(function()
		LightService:Release(self.LightClaim)
	end)

	self.StateMachine:Start()
end

function Creep:Despawn()
	if not self.Active then return end
	self.Active = false

	self.Model:RemoveTag(ENEMY_TAG)
	self.Model:RemoveTag(CREEP_TAG)
	if self.Destroying then
		self.Destroying:Disconnect()
		self.Destroying = nil
	end
	LightService:Release(self.LightClaim)

	task.defer(function()
		self.StateMachine:Stop()
		self.Model:Destroy()
	end)
end

return Creep
