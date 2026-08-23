local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local FixtureFall = require(ServerStorage.Classes.FixtureFall)
local Hallways = require(ReplicatedStorage.Modules.Hallways)

local PaintingFall = FixtureFall.extend("PaintingFall", FixtureFall)

function PaintingFall.new(config: { [string]: any }?)
	return FixtureFall.new(config, PaintingFall)
end

local function shoveDirection(root: BasePart): Vector3
	local hallway = Hallways.Nearest(root.Position)
	if hallway then
		local centre = Hallways.PointAt(hallway, Hallways.Along(hallway, root.Position))
		local away = Vector3.new(centre.X - root.Position.X, 0, centre.Z - root.Position.Z)
		if away.Magnitude > 1e-3 then return away.Unit end
	end

	local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	return if facing.Magnitude > 1e-3 then facing.Unit else Vector3.xAxis
end

function PaintingFall:OnLoose(_model: Model, root: BasePart)
	local mass = root.AssemblyMass
	local direction = shoveDirection(root)
	local lift = self:Setting("ShoveLift", 4)

	root:ApplyImpulse((direction * self:Setting("ShoveSpeed", 14) + Vector3.yAxis * lift) * mass)

	local spin = self:Setting("ShoveSpin", 5)
	if spin > 0 then
		local axis = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		if axis.Magnitude > 1e-3 then
			root:ApplyAngularImpulse(axis.Unit * spin * mass)
		end
	end
end

return PaintingFall
