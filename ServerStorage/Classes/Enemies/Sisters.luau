local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local NpcAnimator = require(ReplicatedStorage.Classes.NpcAnimator)
local StateMachine = require(ReplicatedStorage.Classes.StateMachine)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local MathService = require(ReplicatedStorage.Services.MathService)
local DeathService = require(ServerStorage.Services.DeathService)
local EnemyObservationService = require(ServerStorage.Services.EnemyObservationService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local LightService = require(ServerStorage.Services.LightService)
local RoomService = require(ServerStorage.Services.RoomService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)

local ENEMY_TAG = "Enemy"
local SISTERS_TAG = "Sisters"
local MINIMUM_LEG = 1e-3
local SIGHT_INTERVAL = 0.5
local HEAD_TWITCH_MIN = 0.5
local HEAD_TWITCH_MAX = 1.2
local HEAD_TWITCH_ANGLE = math.rad(30)
local HEAD_GLITCH_SNAPS_MIN = 2
local HEAD_GLITCH_SNAPS_MAX = 4
local HEAD_GLITCH_SNAP_MIN = 0.025
local HEAD_GLITCH_SNAP_MAX = 0.055
local HEAD_GLITCH_HOLD_MIN = 0.08
local HEAD_GLITCH_HOLD_MAX = 0.16

local Sisters = {}
Sisters.__index = Sisters
Sisters.ClassName = "Sisters"

local horizontal = MathService.Horizontal
local distanceToSegment = MathService.DistanceToSegment

local function prepare(model: Model)
	local neck = model.Head.Neck :: AnimationConstraint
	neck.Attachment0 = model.UpperTorso.NeckRigAttachment
	neck.Attachment1 = model.Head.NeckRigAttachment

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant.Name == "HumanoidRootPart"
			descendant.CollisionGroup = EnemyService.CollisionGroup
		end
	end

	local humanoid = model.Humanoid :: Humanoid
	humanoid.EvaluateStateMachine = false
	humanoid.AutoRotate = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
end

function Sisters.new(model: Model, config, startTip: Vector3, direction: Vector3, destinationTip: Vector3)
	local self = setmetatable({}, Sisters)

	self.Model = model
	self.Config = config
	self.Models = { model }
	self.Animators = {}
	self.StartPosition = startTip
		+ direction * config.EndInset
		+ Vector3.yAxis * config.RouteHeight
	self.DestinationTip = destinationTip
	self.Facing = direction
	self.FloorDistance = horizontal(self.DestinationTip - self.StartPosition):Dot(self.Facing)
	self.LastPositions = {}
	self.NeckAttachments = {}
	self.NeckAttachmentBases = {}
	self.HeadTwitches = {}
	self.HeadTwitchOffsets = {}
	self.NextHeadTwitch = 0
	self.NextLightFlicker = 0
	self._movementValue = nil :: NumberValue?
	self._movementTween = nil :: Tween?
	self._movementConnection = nil :: RBXScriptConnection?

	self.HasBeenSeen = false
	self.UnseenSince = nil :: number?
	self.ForgetRolled = false
	self.NextSightCheck = 0

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

function Sisters:_facePlayers()
	for _, model in self.Models do
		local torso = model.UpperTorso :: BasePart
		local head = model.Head :: BasePart
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

		self.NeckAttachments[model].CFrame = self.NeckAttachmentBases[model]
			* tracking
			* (self.HeadTwitchOffsets[model] or CFrame.identity)
	end
end

function Sisters:GetCenter(): Vector3
	local total = Vector3.zero
	for _, model in self.Models do
		total += (model.HumanoidRootPart :: BasePart).Position
	end
	return total / #self.Models
end

function Sisters:_place(distance: number)
	local side = Vector3.yAxis:Cross(self.Facing).Unit * (self.Config.SideSpacing / 2)
	local center = self.StartPosition + self.Facing * distance
	local marks = { center - side, center + side }
	for index, model in self.Models do
		model:PivotTo(CFrame.lookAt(marks[index], marks[index] + self.Facing))
	end
end

function Sisters:_sweep()
	local center = self:GetCenter()
	for index, model in self.Models do
		local position = (model.HumanoidRootPart :: BasePart).Position
		local origin = self.LastPositions[index]
		self.LastPositions[index] = position

		for _, player in Players:GetPlayers() do
			if RoomService:IsInRoom(player) then continue end
			if Vanished.Is(player.Character) then continue end

			local root = CharacterService.GetAliveRoot(player)
			local humanoid = if root then CharacterService.GetHumanoid(root.Parent :: Model) else nil
			if root and humanoid
				and distanceToSegment(root.Position, origin, position) <= self.Config.KillRange
			then
				DeathService:RecordCause(player, self.EnemyId)
				humanoid.Health = 0
			end
		end
	end

	local now = os.clock()
	if now >= self.NextLightFlicker then
		self.NextLightFlicker = now + (self.Config.LightFlickerInterval or 1)
		LightService:FlickerAlongHallway(center, self.Config.LightFlickerDuration)
	end
end

function Sisters:_twitchHeads(now: number)
	if now < self.NextHeadTwitch then return end
	self.NextHeadTwitch = now + HEAD_TWITCH_MIN + math.random() * (HEAD_TWITCH_MAX - HEAD_TWITCH_MIN)

	for _, model in self.Models do
		local attachment = self.NeckAttachments[model]
		local twitch = (self.HeadTwitches[model] or 0) + 1
		self.HeadTwitches[model] = twitch

		task.spawn(function()
			task.wait(math.random() * HEAD_GLITCH_SNAP_MAX)
			for _ = 1, math.random(HEAD_GLITCH_SNAPS_MIN, HEAD_GLITCH_SNAPS_MAX) do
				if self.HeadTwitches[model] ~= twitch or not attachment.Parent then return end
				self.HeadTwitchOffsets[model] = CFrame.Angles(
					(math.random() - 0.5) * HEAD_TWITCH_ANGLE,
					(math.random() - 0.5) * HEAD_TWITCH_ANGLE * 2,
					(math.random() - 0.5) * HEAD_TWITCH_ANGLE
				)
				task.wait(HEAD_GLITCH_SNAP_MIN
					+ math.random() * (HEAD_GLITCH_SNAP_MAX - HEAD_GLITCH_SNAP_MIN))
			end

			task.wait(HEAD_GLITCH_HOLD_MIN
				+ math.random() * (HEAD_GLITCH_HOLD_MAX - HEAD_GLITCH_HOLD_MIN))
			if self.HeadTwitches[model] == twitch and attachment.Parent then
				self.HeadTwitchOffsets[model] = CFrame.identity
			end
		end)
	end
end

function Sisters:_step(): boolean
	local center = self:GetCenter()
	local travelled = horizontal(center - self.StartPosition):Dot(self.Facing)

	if travelled >= self.FloorDistance + self.Config.DespawnPastEnd then
		self:Despawn()
		return false
	end

	self:_sweep()
	self:_facePlayers()
	self:_twitchHeads(os.clock())
	return true
end

function Sisters:_isSeen(): boolean
	local filter = { table.unpack(self.Models) }
	for _, player in Players:GetPlayers() do
		if player.Character then table.insert(filter, player.Character) end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = filter
	params.RespectCanCollide = true

	for _, eye in EnemyObservationService:GetEyes() do
		for _, model in self.Models do
			local target = (model.HumanoidRootPart :: BasePart).Position
			local offset = target - eye
			if offset.Magnitude < MINIMUM_LEG or workspace:Raycast(eye, offset, params) == nil then
				return true
			end
		end
	end
	return false
end

function Sisters:_shouldForget(now: number): boolean
	if now < self.NextSightCheck then return false end
	self.NextSightCheck = now + SIGHT_INTERVAL

	if self:_isSeen() then
		self.HasBeenSeen = true
		self.UnseenSince = nil
		self.ForgetRolled = false
		return false
	end

	if not self.HasBeenSeen or self.ForgetRolled then return false end
	if not self.UnseenSince then
		self.UnseenSince = now
		return false
	end
	if now - self.UnseenSince < (self.Config.ForgetDelay or math.huge) then return false end

	self.ForgetRolled = true
	return math.random() < (self.Config.ForgetChance or 0)
end

function Sisters:Patrol()
	while self.Active do
		RunService.Heartbeat:Wait()
		if not self.Active then return end

		if self:_shouldForget(os.clock()) then
			self:Despawn()
			return
		end
		if not self:_step() then return end
	end
end

function Sisters:Start()
	if self.Active then return end
	self.Active = true

	EnemyService:EnsureCollisionGroup()
	local twin = self.Model:Clone()
	twin.Parent = self.Model.Parent
	table.insert(self.Models, twin)

	for _, model in self.Models do
		prepare(model)

		local animator = NpcAnimator.new(model, self.Config.Animations)
		animator:SetMovementSpeed(self.Config.WalkSpeed)
		table.insert(self.Animators, animator)

		local neckAttachment = model.UpperTorso.NeckRigAttachment :: Attachment
		self.NeckAttachments[model] = neckAttachment
		self.NeckAttachmentBases[model] = neckAttachment.CFrame
		self.HeadTwitchOffsets[model] = CFrame.identity
		model:AddTag(ENEMY_TAG)
		model:AddTag(SISTERS_TAG)
	end
	self:_place(0)
	for index, model in self.Models do
		self.LastPositions[index] = (model.HumanoidRootPart :: BasePart).Position
	end

	local targetDistance = self.FloorDistance + self.Config.WalkOffDistance
	local movementValue = Instance.new("NumberValue")
	self._movementValue = movementValue
	self._movementConnection = movementValue.Changed:Connect(function(distance)
		self:_place(distance)
	end)
	local tween = TweenService:Create(
		movementValue,
		TweenInfo.new(targetDistance / self.Config.WalkSpeed, Enum.EasingStyle.Linear),
		{ Value = targetDistance }
	)
	self._movementTween = tween
	tween.Completed:Once(function(state)
		if state == Enum.PlaybackState.Completed and self.Active then
			self:Despawn()
		end
	end)
	tween:Play()

	self.StateMachine:Start()
end

function Sisters:Despawn()
	if not self.Active then return end
	self.Active = false
	if self._movementTween then self._movementTween:Cancel() end
	if self._movementConnection then self._movementConnection:Disconnect() end
	if self._movementValue then self._movementValue:Destroy() end
	self._movementTween = nil
	self._movementConnection = nil
	self._movementValue = nil

	for _, model in self.Models do
		self.HeadTwitches[model] = (self.HeadTwitches[model] or 0) + 1
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
