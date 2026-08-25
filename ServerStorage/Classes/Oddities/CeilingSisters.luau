local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local HallwayGraph = require(ReplicatedStorage.Services.HallwayGraphService)
local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local EnemyConfigs = require(ServerStorage.Configs.EnemyConfigs)
local Oddity = require(ServerStorage.Classes.Oddity)
local SurfaceWalker = require(ServerStorage.Classes.SurfaceWalker)

local ODDITY_FOLDER_NAME = "Oddities"
local MINIMUM_LEG = 1e-3
local CEILING_RAY = 60
local CEILING_START_OFFSET = 2

local CeilingSisters = Oddity.extend("CeilingSisters")
CeilingSisters.Scope = "Map"
CeilingSisters.ConfigName = "MapOddityConfig"

local ActiveCount = 0

local function setting(class: any, name: string, fallback: number): number
	local value = class.Settings and class.Settings[name]
	return if type(value) == "number" then value else fallback
end

local function flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > MINIMUM_LEG then flat.Unit else Vector3.xAxis
end

local function oddityFolder(): Folder
	local existing = workspace:FindFirstChild(ODDITY_FOLDER_NAME)
	if existing then return existing :: Folder end

	local folder = Instance.new("Folder")
	folder.Name = ODDITY_FOLDER_NAME
	folder.Parent = workspace
	return folder
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

function CeilingSisters.new(config: { [string]: any }?)
	local self = Oddity.new(config, CeilingSisters)

	self.Folder = nil :: Folder?
	self.Models = {} :: { Model }
	self.Animators = {} :: { any }
	self.Walkers = {} :: { any }
	self.NeckAttachments = {} :: { [Model]: Attachment }
	self.NeckAttachmentBases = {} :: { [Model]: CFrame }
	self.FaceConnection = nil :: RBXScriptConnection?
	self.PatrolThread = nil :: thread?

	return self
end

function CeilingSisters.Resolve(_class: any, position: Vector3): any?
	return HallwayGraph:FindNearestNode(position)
end

function CeilingSisters.Pick(class: any): any?
	local nodes = HallwayGraph:Get()
	if #nodes == 0 then return nil end

	local minimumDistance = setting(class, "MinimumPlayerDistance", 32)
	local candidates = {}
	for _, node in nodes do
		if HallwayGraph:IsFarFromPlayers(node.Position, minimumDistance) then
			table.insert(candidates, node)
		end
	end
	if #candidates == 0 then return nil end
	return candidates[math.random(1, #candidates)]
end

function CeilingSisters:CanStart(context: any): (boolean, string?)
	if context == nil then return false, "no hallway node found there" end
	if ActiveCount > 0 then return false, "the ceiling sisters are already out" end
	return true, nil
end

function CeilingSisters:_ceilingContact(position: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true

	local excluded: { Instance } = {}
	if self.Folder then table.insert(excluded, self.Folder) end
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

function CeilingSisters:_pathFor(route: { any }, side: number): { Vector3 }
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

function CeilingSisters:_facePlayers()
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

function CeilingSisters:_buildModel(template: Model, index: number): Model
	local rig = template:Clone() :: Model
	rig.Name = `CeilingSister_{index}`
	rig:SetAttribute("EnemyId", nil)
	for _, tag in CollectionService:GetTags(rig) do
		CollectionService:RemoveTag(rig, tag)
	end
	for _, descendant in rig:GetDescendants() do
		for _, tag in CollectionService:GetTags(descendant) do
			CollectionService:RemoveTag(descendant, tag)
		end
	end

	local transparency = math.clamp(setting(self, "Translucency", 0.55), 0, 1)
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.Transparency = math.max(descendant.Transparency, transparency)
			descendant.CastShadow = false
		end
	end

	local neck = rig:FindFirstChild("Neck", true)
	if neck and neck:IsA("AnimationConstraint") then
		neck.Attachment0 = rig.UpperTorso.NeckRigAttachment
		neck.Attachment1 = rig.Head.NeckRigAttachment
	end

	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.EvaluateStateMachine = false
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	return rig
end

function CeilingSisters:_patrol(startNode: any)
	local walkSpeed = math.max(setting(self, "WalkSpeed", EnemyConfigs.Sisters.WalkSpeed or 5), 0.5)
	local sideSpacing = math.max(setting(self, "SideSpacing", EnemyConfigs.Sisters.SideSpacing or 5.5), 0)
	local sides = { -sideSpacing / 2, sideSpacing / 2 }
	local nodes = HallwayGraph:Get()
	local current = startNode

	while self.Active do
		local destination = current
		for _ = 1, 10 do
			local candidate = nodes[math.random(1, #nodes)]
			if candidate ~= current then
				destination = candidate
				break
			end
		end
		if destination == current then
			task.wait(1)
			continue
		end

		local route = HallwayGraph:FindPath(current, destination)
		if not route or #route < 2 then
			nodes = HallwayGraph:Get()
			current = HallwayGraph:FindNearestNode(current.Position) or nodes[math.random(1, #nodes)]
			task.wait(1)
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

function CeilingSisters:OnStart(startNode: any): boolean
	local templates = ReplicatedStorage:FindFirstChild("Enemies")
	local template = templates and templates:FindFirstChild(EnemyConfigs.Sisters.Model)
	if not template or not template:IsA("Model") then return false end

	ActiveCount += 1

	local folder = Instance.new("Folder")
	folder.Name = `CeilingSisters_{self.Token}`
	folder.Parent = oddityFolder()
	self.Folder = folder

	local contact = self:_ceilingContact(startNode.Position)
	for index = 1, 2 do
		local rig = self:_buildModel(template, index)
		rig:PivotTo(CFrame.new(contact))
		rig.Parent = folder
		table.insert(self.Models, rig)

		local neckAttachment = rig.UpperTorso:FindFirstChild("NeckRigAttachment") :: Attachment?
		if neckAttachment then
			self.NeckAttachments[rig] = neckAttachment
			self.NeckAttachmentBases[rig] = neckAttachment.CFrame
		end

		local animator = NpcAnimator.new(rig, EnemyConfigs.Sisters.Animations)
		animator:Start()
		table.insert(self.Animators, animator)

		local walker = SurfaceWalker.new(rig, animator, -Vector3.yAxis)
		walker:PlaceAt(contact + Vector3.new(0, 0, (index - 1.5) * 2))
		table.insert(self.Walkers, walker)
	end

	self.FaceConnection = RunService.Heartbeat:Connect(function()
		self:_facePlayers()
	end)

	self.PatrolThread = task.spawn(function()
		self:_patrol(startNode)
	end)

	return true
end

function CeilingSisters:OnStop()
	ActiveCount = math.max(ActiveCount - 1, 0)

	if self.FaceConnection then
		self.FaceConnection:Disconnect()
		self.FaceConnection = nil
	end
	if self.PatrolThread then
		task.cancel(self.PatrolThread)
		self.PatrolThread = nil
	end

	for _, walker in self.Walkers do
		walker:Destroy()
	end
	table.clear(self.Walkers)

	for _, animator in self.Animators do
		animator:Destroy()
	end
	table.clear(self.Animators)

	if self.Folder then
		self.Folder:Destroy()
		self.Folder = nil
	end
	table.clear(self.Models)
	table.clear(self.NeckAttachments)
	table.clear(self.NeckAttachmentBases)
end

return CeilingSisters
