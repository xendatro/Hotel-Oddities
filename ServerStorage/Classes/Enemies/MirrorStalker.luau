local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local MirrorRoomConfig = require(ReplicatedStorage.Configs.MirrorRoomConfig)
local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)
local MirrorRoomService = require(ReplicatedStorage.Services.MirrorRoomService)
local SurfaceWalker = require(ServerStorage.Classes.SurfaceWalker)
local GazeService = require(ServerStorage.Services.GazeService)

local ENEMY_TAG = "Enemy"
local MINIMUM = 1e-3
local SNAP_DOT = -0.999
local SAMPLE_PARTS = { "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso" }

local MirrorStalker = {}
MirrorStalker.__index = MirrorStalker
MirrorStalker.ClassName = "MirrorStalker"

local function flatten(vector: Vector3): Vector3
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > MINIMUM then flat.Unit else Vector3.xAxis
end

local function setUpConnections(self)
	self.Connections = {}

	self.Connections.Step = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_update(deltaTime)
	end)
end

function MirrorStalker.new(model: Model, config, player: Player?)
	local self = setmetatable({}, MirrorStalker)

	self.Model = model
	self.Config = config
	self.Target = player
	self.Connections = {}
	self.Samples = {}
	self.Humanoid = model:FindFirstChildOfClass("Humanoid")
	self.Animator = nil
	self.Walker = nil
	self.Room = nil
	self.Contact = model:GetPivot().Position
	self.Look = nil :: Vector3?
	self.CaughtFor = 0
	self.Despawned = false
	self.OnDespawn = nil

	return self
end

function MirrorStalker:_bounds(): MirrorRoomService.Bounds?
	return if self.Room then MirrorRoomService.GetBounds(self.Room) else nil
end

function MirrorStalker:_clamp(bounds: MirrorRoomService.Bounds, position: Vector3): Vector3
	local inset = MirrorRoomConfig.Padding + self.Config.EdgeInset
	local halfX = math.max(bounds.HalfX - inset, 0)
	local halfZ = math.max(bounds.HalfZ - inset, 0)

	local offset = bounds.Frame:PointToObjectSpace(position)
	local inside = bounds.Frame:PointToWorldSpace(Vector3.new(
		math.clamp(offset.X, -halfX, halfX),
		offset.Y,
		math.clamp(offset.Z, -halfZ, halfZ)
	))

	return Vector3.new(inside.X, bounds.FloorY, inside.Z)
end

function MirrorStalker:_followPoint(bounds: MirrorRoomService.Bounds, targetRoot: BasePart, distance: number): Vector3
	local behind = targetRoot.Position - flatten(targetRoot.CFrame.LookVector) * distance
	return self:_clamp(bounds, behind)
end

function MirrorStalker:_seenBy(viewer, bounds: MirrorRoomService.Bounds, mirrored: boolean, options): boolean
	for _, part in self.Samples do
		local point = if mirrored then MirrorRoomService.MirrorPoint(bounds, part.Position) else part.Position
		if GazeService.Sees(viewer, point, options) then return true end
	end
	return false
end

function MirrorStalker:_caught(bounds: MirrorRoomService.Bounds): boolean
	local viewer = GazeService.ViewerFor(self.Target)
	if not viewer then return false end

	local lookingBehind = self:_seenBy(viewer, bounds, false, {
		Cone = self.Config.CheckCone,
		MaxDistance = self.Config.CheckDistance,
		Ignore = { self.Model },
	})
	if not lookingBehind then return false end

	return not self:_seenBy(viewer, bounds, true, {
		Cone = self.Config.ReflectionCone,
		MaxDistance = self.Config.ReflectionDistance,
		Ignore = { self.Model },
	})
end

function MirrorStalker:_move(bounds: MirrorRoomService.Bounds, targetRoot: BasePart, deltaTime: number)
	local goal = self:_followPoint(bounds, targetRoot, self.Config.FollowDistance)

	local offset = goal - self.Contact
	local distance = offset.Magnitude

	local step = 0
	if distance > self.Config.FollowSlack then
		step = math.min(self.Config.WalkSpeed * deltaTime, distance)
		self.Contact += offset.Unit * step
	end

	local desired = flatten(targetRoot.Position - self.Contact)
	local look = self.Look or desired
	if look:Dot(desired) <= SNAP_DOT then
		look = desired
	else
		look = flatten(look:Lerp(desired, MathService.ExpAlpha(self.Config.TurnRate, deltaTime)))
	end
	self.Look = look

	self.Walker:PlaceAt(self.Contact, look)

	local travelled = if deltaTime > MINIMUM then step / deltaTime else 0
	self.Animator:SetMovementSpeed(math.max(travelled, self.Config.MinGaitSpeed))
end

function MirrorStalker:_update(deltaTime: number)
	if self.Despawned then return end

	local target = self.Target
	local bounds = self:_bounds()
	local targetRoot = if target and target.Parent == Players then CharacterService.GetAliveRoot(target) else nil
	if not (bounds and targetRoot) then
		self:Despawn()
		return
	end
	if not MirrorRoomService.IsInside(bounds, targetRoot.Position) then
		self:Despawn()
		return
	end

	self:_move(bounds, targetRoot, deltaTime)

	if not self:_caught(bounds) then
		self.CaughtFor = 0
		return
	end

	self.CaughtFor += deltaTime
	if self.CaughtFor >= self.Config.CheckHold then
		self:Despawn()
	end
end

function MirrorStalker:Start()
	local target = self.Target
	local targetRoot = if target then CharacterService.GetAliveRoot(target) else nil

	local room, bounds = nil, nil
	if targetRoot then
		room, bounds = MirrorRoomService.GetRoomAt(targetRoot.Position)
	end

	if not (target and room and bounds and targetRoot and self.Humanoid) then
		warn(`[mirrorstalker] {if target then target.Name else "nobody"} is not standing in a mirror room`)
		self:Despawn()
		return
	end

	self.Room = room
	self.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	self.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	self.Humanoid.EvaluateStateMachine = false

	for _, descendant in self.Model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute(MirrorRoomConfig.TransparencyAttribute, descendant.Transparency)
			descendant.Transparency = 1
			descendant.CastShadow = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant:SetAttribute(MirrorRoomConfig.TransparencyAttribute, descendant.Transparency)
			descendant.Transparency = 1
		end
	end

	for _, name in SAMPLE_PARTS do
		local part = self.Model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(self.Samples, part)
		end
	end

	self.Animator = NpcAnimator.new(self.Model, self.Config.Animations)
	self.Animator:Start()
	self.Animator:SetMovementTrack("Walk")
	self.Animator:SetMovementSpeed(self.Config.MinGaitSpeed)

	self.Walker = SurfaceWalker.new(self.Model, self.Animator, Vector3.yAxis)
	self.Contact = self:_followPoint(bounds, targetRoot, self.Config.SpawnDistance)
	self.Look = flatten(targetRoot.Position - self.Contact)
	self.Walker:PlaceAt(self.Contact, self.Look)

	self.Model:SetAttribute(MirrorRoomConfig.ViewerAttribute, target.UserId)
	self.Model:AddTag(MirrorRoomConfig.OpaqueTag)
	self.Model:AddTag(ENEMY_TAG)

	setUpConnections(self)
end

function MirrorStalker:Despawn()
	if self.Despawned then return end
	self.Despawned = true

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	if self.Walker then
		self.Walker:Destroy()
		self.Walker = nil
	end
	if self.Animator then
		self.Animator:Destroy()
		self.Animator = nil
	end

	local callback = self.OnDespawn
	self.OnDespawn = nil
	if callback then callback(self) end

	self.Model:Destroy()
end

return MirrorStalker
