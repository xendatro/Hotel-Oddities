local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathService = require(ReplicatedStorage.Services.MathService)

local TURN_RESPONSIVENESS = 10
local SNAP_DOT = -0.999
local CEILING_RAY = 60
local CEILING_START_OFFSET = 2

local SurfaceWalker = {}
SurfaceWalker.__index = SurfaceWalker

local function anyPerpendicular(normal: Vector3): Vector3
	local candidate = normal:Cross(Vector3.zAxis)
	if candidate.Magnitude < 1e-3 then
		candidate = normal:Cross(Vector3.xAxis)
	end
	return candidate.Unit
end

local function projectLook(normal: Vector3, direction: Vector3): Vector3?
	local projected = direction - normal * direction:Dot(normal)
	if projected.Magnitude < 1e-3 then return nil end
	return projected.Unit
end

local function surfaceCFrame(self, contact: Vector3, look: Vector3): CFrame
	local up = self.Normal
	local zAxis = -look
	local xAxis = up:Cross(zAxis).Unit
	local position = contact + up * self.StandingHeight
	return CFrame.fromMatrix(position, xAxis, up, zAxis)
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Removing = self.Model.AncestryChanged:Connect(function()
		if not self.Model:IsDescendantOf(workspace) then
			self:Destroy()
		end
	end)
end

function SurfaceWalker.CeilingContact(position: Vector3, exclusions: { Instance }, fallbackY: number?): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local excluded = table.clone(exclusions)
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	params.FilterDescendantsInstances = excluded

	local origin = position + Vector3.yAxis * CEILING_START_OFFSET
	local result = workspace:Raycast(origin, Vector3.yAxis * CEILING_RAY, params)
	if result then
		return result.Position
	end
	return Vector3.new(position.X, fallbackY or position.Y + CEILING_RAY, position.Z)
end

function SurfaceWalker.CeilingRoute(
	route: { any },
	exclusions: { Instance },
	lateralOffset: number?,
	fallbackY: number?
): { Vector3 }
	local side = lateralOffset or 0
	local points = {}
	for index, node in route do
		local position = node.Position
		if side ~= 0 then
			local previous = route[math.max(index - 1, 1)]
			local following = route[math.min(index + 1, #route)]
			local direction = Vector3.new(
				following.Position.X - previous.Position.X,
				0,
				following.Position.Z - previous.Position.Z
			)
			local flat = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.xAxis
			position += Vector3.yAxis:Cross(flat).Unit * side
		end
		points[index] = SurfaceWalker.CeilingContact(position, exclusions, fallbackY)
	end
	return points
end

function SurfaceWalker.new(model: Model, animator: any?, surfaceNormal: Vector3)
	local self = setmetatable({}, SurfaceWalker)

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = (humanoid and humanoid.RootPart or model:FindFirstChild("HumanoidRootPart")) :: BasePart

	self.Model = model
	self.Animator = animator
	self.Normal = surfaceNormal.Unit
	self.Humanoid = humanoid
	self.RootPart = root
	self.StandingHeight = humanoid.HipHeight + root.Size.Y / 2
	self.Look = nil :: Vector3?
	self.WalkToken = 0
	self.Destroyed = false

	self.SavedCollisions = {} :: { [BasePart]: boolean }
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			self.SavedCollisions[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	self.SavedAnchored = root.Anchored
	self.SavedAutoRotate = humanoid.AutoRotate
	self.SavedPlatformStand = humanoid.PlatformStand

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.Anchored = true
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	setUpConnections(self)

	return self
end

function SurfaceWalker:PlaceAt(contact: Vector3, direction: Vector3?)
	if self.Destroyed then return end

	local look = direction and projectLook(self.Normal, direction)
		or self.Look
		or anyPerpendicular(self.Normal)
	self.Look = look
	self.RootPart.CFrame = surfaceCFrame(self, contact, look)
end

function SurfaceWalker:Stop()
	self.WalkToken += 1
	if self.Animator then
		self.Animator:SetMovementSpeed(0)
	end
end

function SurfaceWalker:WalkAlong(points: { Vector3 }, speed: number, gait: ("Walk" | "Run")?): boolean
	if self.Destroyed or #points == 0 or speed <= 0 then return false end

	self.WalkToken += 1
	local token = self.WalkToken

	local position = points[1]
	self:PlaceAt(position, if #points > 1 then points[2] - points[1] else nil)
	if #points == 1 then return true end

	if self.Animator then
		self.Animator:SetMovementTrack(gait or "Walk")
		self.Animator:SetMovementSpeed(speed)
	end

	local index = 1
	while index < #points do
		local deltaTime = RunService.Heartbeat:Wait()
		if self.Destroyed or self.WalkToken ~= token or not self.Model.Parent then
			return false
		end

		local remaining = speed * deltaTime
		while remaining > 0 and index < #points do
			local target = points[index + 1]
			local offset = target - position
			local distance = offset.Magnitude
			if distance <= remaining then
				position = target
				index += 1
				remaining -= distance
			else
				position += offset.Unit * remaining
				remaining = 0
			end
		end

		local segmentEnd = points[math.min(index + 1, #points)]
		local segmentStart = points[math.min(index, #points - 1)]
		local desired = projectLook(self.Normal, segmentEnd - segmentStart)
		local look = self.Look or desired or anyPerpendicular(self.Normal)
		if desired then
			if look:Dot(desired) <= SNAP_DOT then
				look = desired
			else
				local blended = look:Lerp(desired, MathService.ExpAlpha(TURN_RESPONSIVENESS, deltaTime))
				look = projectLook(self.Normal, blended) or desired
			end
		end
		self.Look = look
		self.RootPart.CFrame = surfaceCFrame(self, position, look)
	end

	if self.Animator and self.WalkToken == token then
		self.Animator:SetMovementSpeed(0)
	end
	return true
end

function SurfaceWalker:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.WalkToken += 1

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	if self.Model.Parent then
		for part, canCollide in self.SavedCollisions do
			if part.Parent then
				part.CanCollide = canCollide
			end
		end
		self.RootPart.Anchored = self.SavedAnchored
		self.Humanoid.AutoRotate = self.SavedAutoRotate
		self.Humanoid.PlatformStand = self.SavedPlatformStand
	end
end

return SurfaceWalker
