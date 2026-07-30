local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local InventoryService = require(ServerStorage.Services.InventoryService)

--- @class Healer
--- Shared body of every consumable that restores health. Subclasses supply only how much it heals
--- and which sound it plays; activation, spend and the heal itself are identical.
local Healer = {}
Healer.__index = Healer

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Activated = self.Healer.Activated:Connect(function()
		local character = self.Healer.Parent
		local player = Players:GetPlayerFromCharacter(character)
		if not player then return end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end

		AudioService:Play3DSound(self.Sound, character.PrimaryPart, false, "SFX")

		InventoryService:Remove(player, self.Healer.Name, 1)
		humanoid.Health = math.min(humanoid.Health + self.Amount, humanoid.MaxHealth)
	end)
end

--- @param healer Tool
--- @param amount number -- health restored per use
--- @param sound string -- name of a Sound under `ReplicatedStorage.Sounds`
function Healer.new(healer: Tool, amount: number, sound: string)
	local self = setmetatable({}, Healer)

	self.Healer = healer
	self.Amount = amount
	self.Sound = sound

	setUpConnections(self)

	return self
end

function Healer:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Healer
