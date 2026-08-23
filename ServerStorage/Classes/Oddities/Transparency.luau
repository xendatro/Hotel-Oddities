local ServerStorage = game:GetService("ServerStorage")

local HallwayOddity = require(ServerStorage.Classes.HallwayOddity)

local Transparency = HallwayOddity.extend("Transparency", HallwayOddity)

type Claim = {
	Original: number,
	Count: number,
}

local claims: { [BasePart]: Claim } = {}

local function isCharacterPart(part: BasePart): boolean
	local model = part:FindFirstAncestorOfClass("Model")
	return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
end

local function isEligible(part: BasePart): boolean
	return part:IsDescendantOf(workspace)
		and not part:HasTag("TransparencyIgnore")
		and not isCharacterPart(part)
end

local function overlapFraction(part: BasePart, cframe: CFrame, size: Vector3): number
	local relative = cframe:ToObjectSpace(part.CFrame)
	local half = part.Size / 2
	local extent = Vector3.new(
		math.abs(relative.RightVector.X) * half.X
			+ math.abs(relative.UpVector.X) * half.Y
			+ math.abs(relative.LookVector.X) * half.Z,
		math.abs(relative.RightVector.Y) * half.X
			+ math.abs(relative.UpVector.Y) * half.Y
			+ math.abs(relative.LookVector.Y) * half.Z,
		math.abs(relative.RightVector.Z) * half.X
			+ math.abs(relative.UpVector.Z) * half.Y
			+ math.abs(relative.LookVector.Z) * half.Z
	)
	local partMinimum = relative.Position - extent
	local partMaximum = relative.Position + extent
	local boxHalf = size / 2
	local overlap = Vector3.new(
		math.max(0, math.min(partMaximum.X, boxHalf.X) - math.max(partMinimum.X, -boxHalf.X)),
		math.max(0, math.min(partMaximum.Y, boxHalf.Y) - math.max(partMinimum.Y, -boxHalf.Y)),
		math.max(0, math.min(partMaximum.Z, boxHalf.Z) - math.max(partMinimum.Z, -boxHalf.Z))
	)
	local volume = extent.X * extent.Y * extent.Z * 8
	return if volume > 0 then overlap.X * overlap.Y * overlap.Z / volume else 0
end

function Transparency.new(config: { [string]: any }?)
	local self = HallwayOddity.new(config, Transparency)

	self.Parts = {} :: { [BasePart]: boolean }
	self.Added = nil :: RBXScriptConnection?

	return self
end

function Transparency:_apply(part: BasePart)
	if self.Parts[part] or not isEligible(part) then return end

	local level = self:Setting("HallwayTransparency", 0.02)
	local minimumFraction = self:Setting("MinimumPartHallwayFraction", 0.5)
	if overlapFraction(part, self.BoxCFrame, self.BoxSize) < minimumFraction then return end

	local claim = claims[part]
	if not claim then
		local original = part.Transparency
		if original >= level then return end
		claim = { Original = original, Count = 0 }
		claims[part] = claim
	end

	claim.Count += 1
	self.Parts[part] = true
	part.Transparency = level
end

function Transparency:OnStart()
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = {}

	local seen: { [BasePart]: boolean } = {}
	for _, part in workspace:GetPartBoundsInBox(self.BoxCFrame, self.BoxSize, overlap) do
		seen[part] = true
		self:_apply(part)
	end

	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and not seen[instance] and not instance.CanQuery then
			self:_apply(instance)
		end
	end

	self.Added = workspace.DescendantAdded:Connect(function(instance: Instance)
		if instance:IsA("BasePart") then
			self:_apply(instance)
		end
	end)
	return true
end

function Transparency:OnStop()
	if self.Added then
		self.Added:Disconnect()
		self.Added = nil
	end

	local level = self:Setting("HallwayTransparency", 0.02)
	for part in self.Parts do
		local claim = claims[part]
		if claim then
			claim.Count -= 1
			if claim.Count <= 0 then
				if part.Parent and part.Transparency == level then
					part.Transparency = claim.Original
				end
				claims[part] = nil
			end
		end
	end
	table.clear(self.Parts)
end

return Transparency
