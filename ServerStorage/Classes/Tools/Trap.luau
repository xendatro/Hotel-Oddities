local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)

local Other = ReplicatedStorage.Props.Other

--- @class Trap
--- The bear trap. Activating drops an armed `TrapObject` at the player's feet and spends one.
--- Placements are a shared FIFO queue: the trap past the cap removes the oldest, so a long round
--- cannot carpet the map in them.
local Trap = ServerTool.extend("Trap")

local Placed: { Model } = {}

function Trap.new(tool: Tool)
	return ServerTool.new(tool, Trap)
end

function Trap:OnActivated()
	if not self.Character then return end

	local template = Other:FindFirstChild("Trap")
	if not template then
		warn("Trap: no Trap model in ReplicatedStorage.Props.Other")
		return
	end

	if not self:Consume(1) then return end

	self:PlaySound(self.Config.Sound, self.Tool:FindFirstChild("Handle"))

	local clone = template:Clone()
	clone:PivotTo(self.Character:GetPivot())
	clone:SetAttribute("Closed", false)
	clone.Parent = workspace

	table.insert(Placed, clone)
	while #Placed > self.Config.MaxInWorld do
		local oldest = table.remove(Placed, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

return Trap
