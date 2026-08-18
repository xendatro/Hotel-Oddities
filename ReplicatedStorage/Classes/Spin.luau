local RunService = game:GetService("RunService")

--- @class Spin
--- Rotates a tagged part or model locally at the object's RPS attribute.
local Spin = {}
Spin.__index = Spin

local function getPivot(instance: Instance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	return instance:GetPivot()
end

local function setPivot(instance: Instance, pivot: CFrame)
	if instance:IsA("BasePart") then
		instance.CFrame = pivot
	else
		instance:PivotTo(pivot)
	end
end

local function rotateAroundWorldY(pivot: CFrame, angle: number): CFrame
	local position = pivot.Position
	local orientation = CFrame.fromMatrix(Vector3.zero, pivot.XVector, pivot.YVector, pivot.ZVector)
	return CFrame.new(position) * CFrame.Angles(0, angle, 0) * orientation
end

function Spin.new(instance: Instance)
	local self = setmetatable({}, Spin)
	self.Instance = instance
	self.Connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not instance:IsDescendantOf(workspace) then return end

		local rps = instance:GetAttribute("RPS")
		if typeof(rps) ~= "number" or rps == 0 then return end
		local rotation = rps * math.pi * 2 * deltaTime
		setPivot(instance, rotateAroundWorldY(getPivot(instance), rotation))
	end)
	return self
end

function Spin:Destroy()
	if self.Connection then
		self.Connection:Disconnect()
		self.Connection = nil
	end
end

return Spin
