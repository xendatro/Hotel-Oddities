local RunService = game:GetService("RunService")

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

local function setUpConnections(self)
	self.Connections = {}

	local instance = self.Instance

	self.Connections.AttributeChanged = instance:GetAttributeChangedSignal("RPS"):Connect(function()
		local rps = instance:GetAttribute("RPS")
		self.Speed = if typeof(rps) == "number" then rps else 0
	end)

	self.Connections.Stepped = RunService.RenderStepped:Connect(function(deltaTime)
		if self.Speed == 0 then return end
		if not instance:IsDescendantOf(workspace) then return end

		local rotation = self.Speed * math.pi * 2 * deltaTime
		setPivot(instance, rotateAroundWorldY(getPivot(instance), rotation))
	end)
end

function Spin.new(instance: Instance)
	local self = setmetatable({}, Spin)

	self.Instance = instance
	local rps = instance:GetAttribute("RPS")
	self.Speed = if typeof(rps) == "number" then rps else 0

	setUpConnections(self)

	return self
end

function Spin:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

return Spin
