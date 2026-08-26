local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local SurfaceWalker = require(ServerStorage.Classes.SurfaceWalker)

local ENEMY_TAG = "Enemy"
local SISTERS_TAG = "Sisters"
local MINIMUM_LEG = 1e-3
local CEILING_RAY = 60
local CEILING_START_OFFSET = 2
local DESTINATION_ATTEMPTS = 10
local RETRY_DELAY = 1

local Sisters = {}
Sisters.__index = Sisters
Sisters.ClassName = "Sisters"

local function flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > MINIMUM_LEG then flat.Unit else Vector3.xAxis
end

local function prepare(model: Model, config)
	local neck = model.Head.Neck :: AnimationConstraint
	neck.Attachment0 = model.UpperTorso.NeckRigAttachment
	neck.Attachment1 = model.Head.NeckRigAttachment

	local translucency = math.clamp(config.Translucency or 0.55, 0, 1)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = EnemyService.CollisionGroup
			if descendant.Name ~= "HumanoidRootPart" then
				descendant.Transparency = math.max(descendant.Transparency, translucency)
				descendant.CastShadow = false
			end
		end
	end

	local humanoid = model.Humanoid :: Humanoid
	humanoid.EvaluateStateMachine = false
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function Sisters.new(model: Model, config, startTip: Vector3, direction: Vector3, _destinationTip: Vector3?)
	local self = setmetatable({}, Sisters)

	self.Model = model
	self.Config = config
	self.Models = { model }
	self.Animators = {}
	self.Walkers = {}
	self.NeckAttachments = {}
	self.NeckAttachmentBases = {}
	self.StartPosition = startTip + direction * (config.EndInset or 0)
	self.Facing = flatten(direction)
	self.FaceConnection = nil :: RBXScriptConnection?

	self.Active = false
	self.StateMachine = StateMachine.new({
		Walk = function()
			self:Patrol()
			coroutine.yield()
		end,
	}, {}, {}, "Walk")

	return self
end

local function nearestPlayerPosition(origin: Vector3): Vector3?
	local nearest = nil
	local nearestDistance = math.huge
	for _, player in Players:GetPlayers() do
		local root = CharacterService.GetAliveRoot(player)
		if root then
			local distance = (root.Position - origin).Magnitude
			if distance < nearestDistance then
				nearest = root.Position
				nearestDistance = distance
			end
		end
	end
	return nearest
end

function Sisters:_ceilingContact(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local excluded: { Instance } = {}
	for _, model in self.Models do
		table.insert(excluded, model)
	end
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
	return position + Vector3.yAxis * CEILING_RAY
end

function Sisters:_pathFor(route: { any }, side: number): { Vector3 }
	local points = {}
	for index, node in route do
		local previous = route[math.max(index - 1, 1)]
		local following = route[math.min(index + 1, #route)]
		local direction = flatten(following.Position - previous.Position)
		local across = Vector3.yAxis:Cross(direction).Unit
		points[index] = self:_ceilingContact(node.Position + across * side)
	end
	return points
end

function Sisters:_facePlayers()
	for _, model in self.Models do
		local torso = model:FindFirstChild("UpperTorso") :: BasePart?
		local head = model:FindFirstChild("Head") :: BasePart?
		local attachment = self.NeckAttachments[model]
		if not torso or not head or not attachment then continue end

		local target = nearestPlayerPosition(head.Position)
		local tracking = CFrame.identity
		if target then
			local offset = target - head.Position
			local localDirection = torso.CFrame:VectorToObjectSpace(
				if offset.Magnitude > MINIMUM_LEG then offset.Unit else torso.CFrame.LookVector
			)
			local yaw = math.atan2(-localDirection.X, -localDirection.Z)
			local pitch = math.atan2(
				localDirection.Y,
				Vector2.new(localDirection.X, localDirection.Z).Magnitude
			)
			tracking = CFrame.Angles(pitch, yaw, 0)
		end

		attachment.CFrame = self.NeckAttachmentBases[model] * tracking
	end
end

function Sisters:GetCenter(): Vector3
	local total = Vector3.zero
	for _, model in self.Models do
		total += (model.HumanoidRootPart :: BasePart).Position
	end
	return total / #self.Models
end

function Sisters:Patrol()
	local walkSpeed = math.max(self.Config.WalkSpeed or 5, 0.5)
	local sideSpacing = math.max(self.Config.SideSpacing or 5.5, 0)
	local sides = { -sideSpacing / 2, sideSpacing / 2 }
	local nodes = HallwayGraph:Get()
	local current = HallwayGraph:FindNearestNode(self.StartPosition)

	while self.Active do
		if not current or #nodes < 2 then
			task.wait(RETRY_DELAY)
			if not self.Active then return end
			nodes = HallwayGraph:Get()
			current = HallwayGraph:FindNearestNode(self.StartPosition)
			continue
		end

		local destination = current
		for _ = 1, DESTINATION_ATTEMPTS do
			local candidate = nodes[math.random(1, #nodes)]
			if candidate ~= current then
				destination = candidate
				break
			end
		end
		if destination == current then
			task.wait(RETRY_DELAY)
			continue
		end

		local route = HallwayGraph:FindPath(current, destination)
		if not route or #route < 2 then
			nodes = HallwayGraph:Get()
			current = HallwayGraph:FindNearestNode(self:GetCenter())
			task.wait(RETRY_DELAY)
			continue
		end

		local finished = 0
		for index, walker in self.Walkers do
			local points = self:_pathFor(route, sides[index])
			task.spawn(function()
				walker:WalkAlong(points, walkSpeed)
				finished += 1
			end)
		end
		while self.Active and finished < #self.Walkers do
			RunService.Heartbeat:Wait()
		end
		if not self.Active then return end

		current = destination
	end
end

function Sisters:Start()
	if self.Active then return end
	self.Active = true

	EnemyService:EnsureCollisionGroup()
	local twin = self.Model:Clone()
	twin.Parent = self.Model.Parent
	table.insert(self.Models, twin)

	local contact = self:_ceilingContact(self.StartPosition)
	local across = Vector3.yAxis:Cross(self.Facing).Unit
	local sideSpacing = math.max(self.Config.SideSpacing or 5.5, 0)
	local sides = { -sideSpacing / 2, sideSpacing / 2 }

	for index, model in self.Models do
		prepare(model, self.Config)

		local animator = NpcAnimator.new(model, self.Config.Animations)
		animator:Start()
		table.insert(self.Animators, animator)

		local neckAttachment = model.UpperTorso.NeckRigAttachment :: Attachment
		self.NeckAttachments[model] = neckAttachment
		self.NeckAttachmentBases[model] = neckAttachment.CFrame
		model:AddTag(ENEMY_TAG)
		model:AddTag(SISTERS_TAG)

		local walker = SurfaceWalker.new(model, animator, -Vector3.yAxis)
		walker:PlaceAt(self:_ceilingContact(self.StartPosition + across * sides[index]), self.Facing)
		table.insert(self.Walkers, walker)
	end

	self.FaceConnection = RunService.Heartbeat:Connect(function()
		self:_facePlayers()
	end)

	self.StateMachine:Start()
end

function Sisters:Despawn()
	if not self.Active then return end
	self.Active = false

	if self.FaceConnection then
		self.FaceConnection:Disconnect()
		self.FaceConnection = nil
	end

	for _, walker in self.Walkers do
		walker:Destroy()
	end
	table.clear(self.Walkers)

	for _, model in self.Models do
		local attachment = self.NeckAttachments[model]
		if attachment then attachment.CFrame = self.NeckAttachmentBases[model] end
		model:RemoveTag(ENEMY_TAG)
		model:RemoveTag(SISTERS_TAG)
	end

	task.defer(function()
		self.StateMachine:Stop()
		for _, animator in self.Animators do
			animator:Destroy()
		end
		for _, model in self.Models do
			model:Destroy()
		end
	end)
end

return Sisters
