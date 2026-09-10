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
local CORNERS = { Vector2.new(1, 1), Vector2.new(1, -1), Vector2.new(-1, 1), Vector2.new(-1, -1) }

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
	self.Phase = "Follow"
	self.Connections = {}
	self.Samples = {}
	self.Humanoid = model:FindFirstChildOfClass("Humanoid")
	self.Animator = nil
	self.Walker = nil
	self.Room = nil
	self.Contact = model:GetPivot().Position
	self.Look = nil :: Vector3?
	self.CheckedFor = 0
	self.SeenFor = 0
	self.UnseenFor = 0
	self.LeaveAt = 0
	self.ExpiresAt = 0
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

function MirrorStalker:_exitPoint(bounds: MirrorRoomService.Bounds, targetRoot: BasePart): Vector3
	local inset = MirrorRoomConfig.Padding + self.Config.EdgeInset
	local halfX = math.max(bounds.HalfX - inset, 0)
	local halfZ = math.max(bounds.HalfZ - inset, 0)

	local best, bestDistance = self.Contact, -1
	for _, corner in CORNERS do
		local point = bounds.Frame:PointToWorldSpace(Vector3.new(corner.X * halfX, 0, corner.Y * halfZ))
		local candidate = Vector3.new(point.X, bounds.FloorY, point.Z)
		local distance = (candidate - targetRoot.Position).Magnitude
		if distance > bestDistance then
			best, bestDistance = candidate, distance
		end
	end

	return best
end

function MirrorStalker:_seenBy(viewer, bounds: MirrorRoomService.Bounds, mirrored: boolean, options): boolean
	for _, part in self.Samples do
		local point = if mirrored then MirrorRoomService.MirrorPoint(bounds, part.Position) else part.Position
		if GazeService.Sees(viewer, point, options) then return true end
	end
	return false
end

function MirrorStalker:_checkedBehind(bounds: MirrorRoomService.Bounds): boolean
	local viewer = GazeService.ViewerFor(self.Target)
	if not viewer then return false end

	return self:_seenBy(viewer, bounds, false, {
		Cone = self.Config.CheckCone,
		MaxDistance = self.Config.CheckDistance,
		Ignore = { self.Model },
	})
end

function MirrorStalker:_reflectionSeen(bounds: MirrorRoomService.Bounds): boolean
	local options = {
		Cone = self.Config.ReflectionCone,
		MaxDistance = self.Config.ReflectionDistance,
		Ignore = { self.Model },
	}

	for _, viewer in GazeService.Viewers() do
		if self:_seenBy(viewer, bounds, true, options) then return true end
	end

	return false
end

function MirrorStalker:_hasCompany(bounds: MirrorRoomService.Bounds, targetRoot: BasePart): boolean
	for _, other in Players:GetPlayers() do
		if other == self.Target then continue end

		local root = CharacterService.GetAliveRoot(other)
		if not root then continue end
		if MirrorRoomService.IsInside(bounds, root.Position) then return true end
		if (root.Position - targetRoot.Position).Magnitude <= self.Config.CompanyDistance then return true end
	end

	return false
end

function MirrorStalker:_move(bounds: MirrorRoomService.Bounds, targetRoot: BasePart, deltaTime: number)
	local leaving = self.Phase == "Leave"
	local goal = if leaving
		then self:_exitPoint(bounds, targetRoot)
		else self:_followPoint(bounds, targetRoot, self.Config.FollowDistance)

	local offset = goal - self.Contact
	local distance = offset.Magnitude
	local slack = if leaving then 0 else self.Config.FollowSlack
	local speed = if leaving then self.Config.LeaveSpeed else self.Config.WalkSpeed

	local step = 0
	if distance > slack then
		step = math.min(speed * deltaTime, distance)
		self.Contact += offset.Unit * step
	end

	local desired = if leaving then flatten(offset) else flatten(targetRoot.Position - self.Contact)
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

	local now = os.clock()
	if self.Phase ~= "Leave" and (now >= self.ExpiresAt or self:_hasCompany(bounds, targetRoot)) then
		self.Phase = "Leave"
		self.LeaveAt = now
	end

	self:_move(bounds, targetRoot, deltaTime)

	if self.Phase == "Follow" then
		if self:_checkedBehind(bounds) then
			self.CheckedFor += deltaTime
			if self.CheckedFor >= self.Config.CheckHold then
				self.Phase = "Checked"
			end
		else
			self.CheckedFor = 0
		end
		return
	end

	if self:_reflectionSeen(bounds) then
		self.UnseenFor = 0
		self.SeenFor += deltaTime
		if self.Phase == "Checked" and self.SeenFor >= self.Config.SeenPatience then
			self.Phase = "Leave"
			self.LeaveAt = now
		elseif self.Phase == "Leave" and now - self.LeaveAt >= self.Config.LeaveTimeout then
			self:Despawn()
		end
		return
	end

	self.SeenFor = 0
	self.UnseenFor += deltaTime
	if self.UnseenFor >= self.Config.UnseenHold then
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

	if not (room and bounds and targetRoot and self.Humanoid) then
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

	self.Model:AddTag(MirrorRoomConfig.OpaqueTag)
	self.Model:AddTag(ENEMY_TAG)

	self.ExpiresAt = os.clock() + self.Config.Lifetime
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
