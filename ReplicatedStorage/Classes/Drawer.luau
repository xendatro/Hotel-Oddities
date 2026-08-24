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

local function outwardAxis(model: Model): Vector3
	local pivot = model:GetPivot()
	local keyword = DrawerConfig.HandleKeyword:lower()

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart")
			or belongsToDrawerItem(descendant)
			or not descendant.Name:lower():find(keyword, 1, true)
		then
			continue
		end

		local offset = pivot:PointToObjectSpace(descendant.Position)
		if math.abs(offset.X) >= math.abs(offset.Z) then
			if math.abs(offset.X) > DrawerConfig.HandleThreshold then
				return Vector3.new(math.sign(offset.X), 0, 0)
			end
		elseif math.abs(offset.Z) > DrawerConfig.HandleThreshold then
			return Vector3.new(0, 0, math.sign(offset.Z))
		end
	end

	return DrawerConfig.OutwardAxis.Unit
end

function Drawer.new(model: Model)
	local self = setmetatable({}, Drawer)

	self.Model = model
	self.ClosedPivot = model:GetPivot()
	self.Axis = outwardAxis(model)
	self.Spring = Spring.new(DrawerConfig.Stiffness, DrawerConfig.DampingRatio, DrawerConfig.MaxStep)

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
	self.Model:PivotTo(self.ClosedPivot * CFrame.new(self.Axis * self.Spring.Position))
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
	self.Model = nil
end

return Drawer
