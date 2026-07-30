local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local AudioService = require(ReplicatedStorage.Services.AudioService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local Other = ReplicatedStorage.Props.Other

local MAX_TRAPS_IN_WORLD = 10

--- @class Trap
--- The bear trap tool. Activating it drops an armed `TrapObject` at the player's feet and spends
--- one from the stack. Placements are a FIFO queue: the eleventh trap in the world removes the
--- first, so a server can never be carpeted in them.
local Trap = {}
Trap.__index = Trap

local PlacedTraps: { Model } = {}

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Equipped = self.Trap.Equipped:Connect(function()
		self.Character = self.Trap.Parent
	end)

	self.Connections.Activated = self.Trap.Activated:Connect(function()
		self:Activated()
	end)
end

function Trap.new(trap: Tool)
	local self = setmetatable({}, Trap)

	self.Trap = trap
	self.Character = nil

	setUpConnections(self)

	return self
end

function Trap:Activated()
	if not self.Character then return end

	local player = Players:GetPlayerFromCharacter(self.Character)
	if not player then return end

	AudioService:Play3DSound("PlaceTrap", self.Trap.Handle, false, "SFX")

	local clone = Other.Trap:Clone()
	clone:PivotTo(self.Character:GetPivot())
	clone:SetAttribute("Closed", false)
	clone.Parent = workspace

	table.insert(PlacedTraps, clone)
	while #PlacedTraps > MAX_TRAPS_IN_WORLD do
		local oldest = table.remove(PlacedTraps, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	InventoryService:Remove(player, self.Trap.Name, 1)
end

function Trap:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Trap
