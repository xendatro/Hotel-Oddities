local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallwayGraph = require(ReplicatedStorage.Modules.HallwayGraph)

export type RouteNode = HallwayGraph.RouteNode

function HallwayGraph:IsFarFromPlayers(position: Vector3, distance: number): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and humanoid and humanoid.Health > 0
			and (root.Position - position).Magnitude < distance then
			return false
		end
	end
	return true
end

return HallwayGraph
