local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)
local DrawerItemConfig = require(ReplicatedStorage.Configs.DrawerItemConfig)
local Spring = require(ReplicatedStorage.Classes.Spring)

local Drawer = {}
Drawer.__index = Drawer

local function belongsToDrawerItem(instance: Instance): boolean
	local ancestor = instance.Parent
	while ancestor and ancestor ~= workspace do
		if CollectionService:HasTag(ancestor, DrawerItemConfig.Tag) then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

local function axisFromHandle(pivot: CFrame, descendant: Instance): Vector3?
	local offset = pivot:PointToObjectSpace((descendant :: BasePart).Position)
	if math.abs(offset.X) >= math.abs(offset.Z) then
		if math.abs(offset.X) > DrawerConfig.HandleThreshold then
			return Vector3.new(math.sign(offset.X), 0, 0)
		end
	elseif math.abs(offset.Z) > DrawerConfig.HandleThreshold then
		return Vector3.new(0, 0, math.sign(offset.Z))
	end
	return nil
end

local function isHandle(descendant: Instance, keyword: string): boolean
	return descendant:IsA("BasePart")
		and not belongsToDrawerItem(descendant)
		and descendant.Name:lower():find(keyword, 1, true) ~= nil
end

local function anchorPart(model: Model): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and not belongsToDrawerItem(descendant) then
			return descendant
		end
	end
	return nil
end

local function outwardAxis(model: Model): Vector3?
	local pivot = model:GetPivot()
	local keyword = DrawerConfig.HandleKeyword:lower()

	for _, descendant in model:GetDescendants() do
		if not isHandle(descendant, keyword) then continue end

		local axis = axisFromHandle(pivot, descendant)
		if axis then return axis end
	end

	return nil
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.DescendantAdded = self.Model.DescendantAdded:Connect(function(descendant: Instance)
		if not isHandle(descendant, self.HandleKeyword) then return end

		local axis = axisFromHandle(self.ClosedPivot, descendant)
		if not axis then return end

		self.Axis = axis
		self.Connections.DescendantAdded:Disconnect()
	end)
end

function Drawer.new(model: Model)
	local self = setmetatable({}, Drawer)

	self.Model = model
	self.ClosedPivot = model:GetPivot()
	self.HandleKeyword = DrawerConfig.HandleKeyword:lower()
	self.Anchor = anchorPart(model)
	self.AnchorOffset = if self.Anchor then self.ClosedPivot:ToObjectSpace(self.Anchor.CFrame) else nil
	self.Axis = outwardAxis(model)
	self.Spring = Spring.new(DrawerConfig.Stiffness, DrawerConfig.DampingRatio, DrawerConfig.MaxStep)

	if not self.Axis then
		self.Axis = DrawerConfig.OutwardAxis.Unit
		setUpConnections(self)
	end

	return self
end

function Drawer:IsOpen(): boolean
	return self.Spring.Target > 0
end

function Drawer:IsMoving(): boolean
	return math.abs(self.Spring.Position - self.Spring.Target) > DrawerConfig.SettleDistance
		or math.abs(self.Spring.Velocity) > DrawerConfig.SettleVelocity
end

function Drawer:_apply()
	local target = self.ClosedPivot * CFrame.new(self.Axis * self.Spring.Position)
	local anchor = self.Anchor

	if anchor and anchor.Parent then
		self.Model:PivotTo(target * self.AnchorOffset * anchor.CFrame:Inverse() * self.Model:GetPivot())
		self.Model.WorldPivot = target
		return
	end

	self.Model:PivotTo(target)
end

function Drawer:SetOpen(open: boolean, immediate: boolean?)
	local target = if open then DrawerConfig.OpenDistance else 0
	if self.Spring.Target == target and not immediate then return end

	self.Spring.Target = target

	if immediate then
		self.Spring:Snap(target)
		self:_apply()
	end
end

function Drawer:Step(deltaTime: number): boolean
	if not self:IsMoving() then
		if self.Spring.Position ~= self.Spring.Target then
			self.Spring:Snap(self.Spring.Target)
			self:_apply()
		end
		return false
	end

	self.Spring:Step(deltaTime)
	self:_apply()
	return true
end

function Drawer:Destroy()
	if self.Connections then
		for _, connection in self.Connections do
			connection:Disconnect()
		end
		self.Connections = nil
	end
	self.Anchor = nil
	self.Model = nil
end

return Drawer
