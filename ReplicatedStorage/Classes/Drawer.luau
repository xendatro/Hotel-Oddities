local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DrawerConfig = require(ReplicatedStorage.Configs.DrawerConfig)

--- @class Drawer
--- One `Drawer`-tagged model: a box that slides straight out of the furniture it sits in and back.
--- The whole model moves, so the front, the sides and the handle travel together.
---
--- Which way is out is read off the model rather than assumed. The handle sits on the drawer's face,
--- so the pivot axis it hangs off is the axis the drawer pulls along; a drawer with no handle falls
--- back to the axis in the config.
---
--- Nothing here decides anything. The open/shut boolean belongs to the server, and this only draws
--- the journey between the two.
local Drawer = {}
Drawer.__index = Drawer

local DAMPING = DrawerConfig.DampingRatio * 2 * math.sqrt(DrawerConfig.Stiffness)

--- The pivot-space axis pointing out of the drawer's face, as a unit vector.
local function outwardAxis(model: Model): Vector3
	local pivot = model:GetPivot()
	local keyword = DrawerConfig.HandleKeyword:lower()

	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") or not descendant.Name:lower():find(keyword, 1, true) then
			continue
		end

		local offset = pivot:PointToObjectSpace(descendant.Position)
		-- Only the horizontal axes: a handle sitting high on the face says nothing about which way
		-- the drawer comes out.
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

	--- Studs out of the furniture, and how fast that is changing.
	self.Offset = 0
	self.Velocity = 0
	self.Target = 0

	return self
end

function Drawer:IsOpen(): boolean
	return self.Target > 0
end

function Drawer:IsMoving(): boolean
	return math.abs(self.Offset - self.Target) > DrawerConfig.SettleDistance
		or math.abs(self.Velocity) > DrawerConfig.SettleVelocity
end

function Drawer:_apply()
	self.Model:PivotTo(self.ClosedPivot * CFrame.new(self.Axis * self.Offset))
end

--- Opens or shuts the drawer. `immediate` puts it there without the slide or the sound, which is
--- what a player joining into a hotel with drawers already pulled out wants.
function Drawer:SetOpen(open: boolean, immediate: boolean?)
	local target = if open then DrawerConfig.OpenDistance else 0
	if self.Target == target and not immediate then return end

	self.Target = target

	if immediate then
		self.Offset = target
		self.Velocity = 0
		self:_apply()
		return
	end

end

--- Moves the slide on. Answers whether it is still going, so the caller can stop stepping a drawer
--- that has arrived.
function Drawer:Step(deltaTime: number): boolean
	if not self:IsMoving() then
		if self.Offset ~= self.Target then
			self.Offset = self.Target
			self.Velocity = 0
			self:_apply()
		end
		return false
	end

	local remaining = math.min(deltaTime, 0.1)
	while remaining > 0 do
		local step = math.min(remaining, DrawerConfig.MaxStep)
		remaining -= step

		local acceleration = (self.Target - self.Offset) * DrawerConfig.Stiffness - self.Velocity * DAMPING
		self.Velocity += acceleration * step
		self.Offset += self.Velocity * step
	end

	self:_apply()
	return true
end

function Drawer:Destroy()
	self.Model = nil
end

return Drawer
