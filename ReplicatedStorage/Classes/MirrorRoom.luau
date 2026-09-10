local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LookConfig = require(ReplicatedStorage.Configs.LookConfig)
local MirrorRoomConfig = require(ReplicatedStorage.Configs.MirrorRoomConfig)
local LookService = require(ReplicatedStorage.Services.LookService)
local MathService = require(ReplicatedStorage.Services.MathService)

local MirrorRoom = {}
MirrorRoom.__index = MirrorRoom

local player = Players.LocalPlayer

local ID_ATTRIBUTE = "MirrorPartId"

export type Bounds = {
	Frame: CFrame,
	HalfX: number,
	HalfZ: number,
	FloorY: number,
	MirrorY: number,
}

type Reflection = {
	Clone: Model,
	Pairs: { { BasePart } },
	Head: { [BasePart]: boolean },
	Upper: { [BasePart]: boolean },
	Neck: Instance?,
	Waist: Instance?,
	Opaque: boolean,
	Pitch: number,
	Yaw: number,
	Dirty: boolean,
	Connections: { [string]: RBXScriptConnection },
}

function MirrorRoom.GetBounds(model: Model): Bounds?
	local floor = model:FindFirstChild("Floor")
	local ceiling = model:FindFirstChild("Ceiling")
	if not floor or not floor:IsA("BasePart") then return nil end
	if not ceiling or not ceiling:IsA("BasePart") then return nil end

	local floorY = floor.Position.Y + floor.Size.Y * 0.5
	local ceilingY = ceiling.Position.Y - ceiling.Size.Y * 0.5

	return {
		Frame = floor.CFrame,
		HalfX = floor.Size.X * 0.5 + MirrorRoomConfig.Padding,
		HalfZ = floor.Size.Z * 0.5 + MirrorRoomConfig.Padding,
		FloorY = floorY,
		MirrorY = (floorY + ceilingY) * 0.5,
	}
end

function MirrorRoom.IsInside(bounds: Bounds, position: Vector3): boolean
	if position.Y < bounds.FloorY - MirrorRoomConfig.FloorTolerance then return false end
	if position.Y > bounds.MirrorY then return false end

	local offset = bounds.Frame:PointToObjectSpace(position)
	return math.abs(offset.X) <= bounds.HalfX and math.abs(offset.Z) <= bounds.HalfZ
end

function MirrorRoom.MirrorPoint(bounds: Bounds, position: Vector3): Vector3
	return Vector3.new(position.X, bounds.MirrorY * 2 - position.Y, position.Z)
end

local function reflect(root: BasePart, mirrorY: number): CFrame
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local axis = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
	local pivot = CFrame.new(root.Position.X, mirrorY, root.Position.Z)

	return pivot * CFrame.fromAxisAngle(axis, math.pi) * pivot:Inverse()
end

local function getRoot(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

local function neuter(humanoid: Humanoid)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
end

local function restored(descendant: Instance): number
	local saved = descendant:GetAttribute(MirrorRoomConfig.TransparencyAttribute)
	return if type(saved) == "number" then saved else 0
end

local function strip(clone: Model, opaque: boolean)
	for _, tag in CollectionService:GetTags(clone) do
		CollectionService:RemoveTag(clone, tag)
	end

	for _, descendant in clone:GetDescendants() do
		local stripped = false
		for _, className in MirrorRoomConfig.StripClasses do
			if descendant:IsA(className) then
				descendant:Destroy()
				stripped = true
				break
			end
		end
		if stripped then continue end

		for _, tag in CollectionService:GetTags(descendant) do
			CollectionService:RemoveTag(descendant, tag)
		end

		if descendant:IsA("Humanoid") then
			neuter(descendant)
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			descendant.CastShadow = MirrorRoomConfig.CastShadow
			descendant.LocalTransparencyModifier = 0
			if opaque then
				descendant.Transparency = restored(descendant)
			end
		elseif opaque and (descendant:IsA("Decal") or descendant:IsA("Texture")) then
			descendant.Transparency = restored(descendant)
		end
	end
end

local function jointParts(joint: Instance): (BasePart?, BasePart?)
	if joint:IsA("Motor6D") or joint:IsA("Weld") or joint:IsA("WeldConstraint") then
		return joint.Part0, joint.Part1
	end
	if joint:IsA("AnimationConstraint") or joint:IsA("RigidConstraint") then
		local first, second = joint.Attachment0, joint.Attachment1
		local part0 = first and first.Parent
		local part1 = second and second.Parent
		return
			(if part0 and part0:IsA("BasePart") then part0 else nil),
			(if part1 and part1:IsA("BasePart") then part1 else nil)
	end
	return nil, nil
end

local function jointNeighbours(model: Model): { [BasePart]: { BasePart } }
	local map = {}

	local function link(from: BasePart, to: BasePart)
		local list = map[from]
		if not list then
			list = {}
			map[from] = list
		end
		table.insert(list, to)
	end

	for _, descendant in model:GetDescendants() do
		local part0, part1 = jointParts(descendant)
		if not part0 or not part1 then continue end
		link(part0, part1)
		link(part1, part0)
	end

	return map
end

local function collectSubtree(part: BasePart?, map: { [BasePart]: { BasePart } }, visited: { [BasePart]: boolean })
	if not part or visited[part] then return end
	visited[part] = true
	for _, child in map[part] or {} do
		collectSubtree(child, map, visited)
	end
end

local function subtreeAbove(model: Model, from: string, stops: { string }): { [BasePart]: boolean }
	local map = jointNeighbours(model)
	local visited: { [BasePart]: boolean } = {}

	for _, name in stops do
		local stop = model:FindFirstChild(name)
		if stop and stop:IsA("BasePart") then
			visited[stop] = true
		end
	end

	local start = model:FindFirstChild(from)
	local seeded = table.clone(visited)
	collectSubtree(if start and start:IsA("BasePart") then start else nil, map, visited)

	for stop in seeded do
		visited[stop] = nil
	end
	return visited
end

local function getJoint(model: Model, partName: string, jointName: string): Instance?
	local part = model:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

local function jointDelta(joint: Instance?, angles: CFrame): CFrame?
	if not joint then return nil end

	local frame
	if joint:IsA("Motor6D") then
		local part0 = joint.Part0
		frame = if part0 then part0.CFrame * joint.C0 else nil
	else
		local attachment = (joint :: AnimationConstraint).Attachment0
		frame = if attachment then attachment.WorldCFrame else nil
	end
	if not frame then return nil end

	return frame * angles * frame:Inverse()
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Render = RunService.PreRender:Connect(function(deltaTime: number)
		self:_update(deltaTime)
	end)
end

function MirrorRoom.new(instance: Model)
	local self = setmetatable({}, MirrorRoom)

	self.Instance = instance
	self.Reflections = {} :: { [Model]: Reflection }
	self.Failed = {} :: { [Model]: number }

	self.Folder = Instance.new("Folder")
	self.Folder.Name = instance.Name .. "Reflections"
	self.Folder.Parent = workspace

	setUpConnections(self)

	return self
end

local function cloneTwinned(model: Model): (Model?, { { BasePart } })
	local sources: { BasePart } = {}
	local locked: { Instance } = {}
	if not model.Archivable then
		table.insert(locked, model)
	end

	for _, descendant in model:GetDescendants() do
		if not descendant.Archivable then
			table.insert(locked, descendant)
		end
		if descendant:IsA("BasePart") then
			table.insert(sources, descendant)
			descendant:SetAttribute(ID_ATTRIBUTE, #sources)
		end
	end

	for _, instance in locked do
		instance.Archivable = true
	end
	local clone = model:Clone()
	for _, instance in locked do
		instance.Archivable = false
	end
	for _, part in sources do
		part:SetAttribute(ID_ATTRIBUTE, nil)
	end

	if not clone then return nil, {} end

	local parts: { { BasePart } } = {}
	for _, descendant in clone:GetDescendants() do
		if not descendant:IsA("BasePart") then continue end
		local id = descendant:GetAttribute(ID_ATTRIBUTE)
		descendant:SetAttribute(ID_ATTRIBUTE, nil)
		local source = if type(id) == "number" then sources[id] else nil
		if source then
			table.insert(parts, { source, descendant })
		end
	end

	return clone, parts
end

function MirrorRoom:_build(model: Model): Reflection?
	local clone, parts = cloneTwinned(model)
	if not clone then return nil end
	if #parts == 0 then
		clone:Destroy()
		return nil
	end

	local opaque = model:HasTag(MirrorRoomConfig.OpaqueTag)
	strip(clone, opaque)
	clone.Name = model.Name
	clone.Parent = self.Folder

	local reflection: Reflection = {
		Clone = clone,
		Pairs = parts,
		Head = subtreeAbove(model, "Head", { "UpperTorso", "LowerTorso", "HumanoidRootPart" }),
		Upper = subtreeAbove(model, "UpperTorso", { "LowerTorso", "HumanoidRootPart" }),
		Neck = getJoint(model, "Head", "Neck"),
		Waist = getJoint(model, "UpperTorso", "Waist"),
		Opaque = opaque,
		Pitch = 0,
		Yaw = 0,
		Dirty = false,
		Connections = {},
	}

	local function markDirty(descendant: Instance)
		if descendant:IsA("BasePart") then
			reflection.Dirty = true
		end
	end
	reflection.Connections.Added = model.DescendantAdded:Connect(markDirty)
	reflection.Connections.Removing = model.DescendantRemoving:Connect(markDirty)

	self.Reflections[model] = reflection
	return reflection
end

function MirrorRoom:_remove(model: Model)
	local reflection = self.Reflections[model]
	if not reflection then return end

	for _, connection in reflection.Connections do
		connection:Disconnect()
	end
	reflection.Clone:Destroy()
	self.Reflections[model] = nil
end

function MirrorRoom:_clear()
	for model in self.Reflections do
		self:_remove(model)
	end
end

function MirrorRoom:_render(model: Model, root: BasePart, bounds: Bounds, alpha: number)
	local reflection = self.Reflections[model]
	if reflection and reflection.Dirty then
		self:_remove(model)
		reflection = nil
	end
	if not reflection then
		local retryAt = self.Failed[model]
		if retryAt and os.clock() < retryAt then return end

		reflection = self:_build(model)
		if not reflection then
			self.Failed[model] = os.clock() + MirrorRoomConfig.RetryDelay
			return
		end
		self.Failed[model] = nil
	end

	local neckDelta, waistDelta
	if MirrorRoomConfig.BendLocalLook and model == player.Character then
		local pitch, yaw = LookService.Local(root)
		reflection.Pitch += (pitch - reflection.Pitch) * alpha
		reflection.Yaw += (yaw - reflection.Yaw) * alpha

		local neck, waist = LookConfig.Neck, LookConfig.Waist
		neckDelta = jointDelta(reflection.Neck, CFrame.Angles(reflection.Pitch * neck.Pitch, reflection.Yaw * neck.Yaw, 0))
		waistDelta = jointDelta(reflection.Waist, CFrame.Angles(reflection.Pitch * waist.Pitch, reflection.Yaw * waist.Yaw, 0))
	end

	local transform = reflect(root, bounds.MirrorY)

	for _, entry in reflection.Pairs do
		local source, target = entry[1], entry[2]
		local cframe = source.CFrame

		if neckDelta and reflection.Head[source] then
			cframe = neckDelta * cframe
		end
		if waistDelta and reflection.Upper[source] then
			cframe = waistDelta * cframe
		end

		target.CFrame = transform * cframe
		if reflection.Opaque then
			continue
		end
		if target.Transparency ~= source.Transparency then
			target.Transparency = source.Transparency
		end
	end
end

function MirrorRoom:_subjects(): { Model }
	local models = {}

	for _, other in Players:GetPlayers() do
		local character = other.Character
		if character and character:IsDescendantOf(workspace) then
			table.insert(models, character)
		end
	end

	if MirrorRoomConfig.ReflectEnemies then
		for _, enemy in CollectionService:GetTagged("Enemy") do
			if enemy:IsA("Model") and enemy:IsDescendantOf(workspace) then
				table.insert(models, enemy)
			end
		end
	end

	return models
end

function MirrorRoom:_update(deltaTime: number)
	local bounds = MirrorRoom.GetBounds(self.Instance)
	local character = player.Character
	local localRoot = if character then getRoot(character) else nil

	if not bounds or not localRoot or not MirrorRoom.IsInside(bounds, localRoot.Position) then
		self:_clear()
		return
	end

	local alpha = MathService.ExpAlpha(LookConfig.Smoothing, deltaTime)
	local seen: { [Model]: boolean } = {}

	for _, model in self:_subjects() do
		local root = getRoot(model)
		if root and MirrorRoom.IsInside(bounds, root.Position) then
			seen[model] = true
			self:_render(model, root, bounds, alpha)
		end
	end

	for model in self.Reflections do
		if not seen[model] then
			self:_remove(model)
		end
	end
	for model in self.Failed do
		if not seen[model] then
			self.Failed[model] = nil
		end
	end
end

function MirrorRoom:Destroy()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	self:_clear()
	table.clear(self.Failed)
	self.Folder:Destroy()
end

return MirrorRoom
