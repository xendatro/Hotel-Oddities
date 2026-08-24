local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local DeathService = require(ServerStorage.Services.DeathService)
local FixtureFall = require(ServerStorage.Classes.FixtureFall)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local LightService = require(ServerStorage.Services.LightService)
local OddityRemotes = require(ServerStorage.Modules.OddityRemotes)
local PropOddity = require(ServerStorage.Classes.PropOddity)
local Vanished = require(ReplicatedStorage.Modules.Vanished)

local PopRemote = OddityRemotes.Event("PaintingDwellerPop")

local PaintingDweller = PropOddity.extend("PaintingDweller", PropOddity)

function PaintingDweller.new(config: { [string]: any }?)
	local self = PropOddity.new(config, PaintingDweller)
	self.Rig = nil :: Model?
	self.Canvas = nil :: BasePart?
	self.Decals = {} :: { [Decal]: number }
	self.HoleGui = nil :: SurfaceGui?
	self.ThrashTrack = nil :: AnimationTrack?
	self.AttackTrack = nil :: AnimationTrack?
	self.PoppedAt = 0
	self.NextAttack = 0
	return self
end

local roomBoxes: { { CFrame: CFrame, Half: Vector3 } } = {}
local roomBoxesBuiltAt = -math.huge

local function getRoomBoxes()
	if os.clock() - roomBoxesBuiltAt < 30 then return roomBoxes end
	roomBoxesBuiltAt = os.clock()
	table.clear(roomBoxes)
	for _, room in CollectionService:GetTagged("Room") do
		if room:IsA("Model") and room:IsDescendantOf(workspace) then
			local cframe, size = room:GetBoundingBox()
			table.insert(roomBoxes, { CFrame = cframe, Half = size / 2 + Vector3.one * 2 })
		end
	end
	return roomBoxes
end

local function insideAnyRoom(point: Vector3): boolean
	for _, box in getRoomBoxes() do
		local offset = box.CFrame:PointToObjectSpace(point)
		if
			math.abs(offset.X) <= box.Half.X
			and math.abs(offset.Y) <= box.Half.Y
			and math.abs(offset.Z) <= box.Half.Z
		then
			return true
		end
	end
	return false
end

local function livingRoot(player: Player): BasePart?
	local root = CharacterService.GetAliveRoot(player)
	if not root then return nil end
	if Vanished.Is(player.Character) then return nil end
	return root
end

function PaintingDweller:IsCandidate(model: Model): boolean
	local settings = self.Settings or {}
	local canvas = model:FindFirstChild("Canvas")
	if not canvas or not canvas:IsA("BasePart") or not canvas.Anchored then return false end
	if canvas.Size.X < (settings.MinCanvasWidth or 6) then return false end

	local outward = canvas.CFrame.LookVector
	for _, depth in { settings.HideDepth or 8, (settings.HideDepth or 8) + 5 } do
		local behind = canvas.Position - outward * depth
		if Hallways.At(behind, true) then return false end
		if insideAnyRoom(behind) then return false end
	end
	return true
end

function PaintingDweller:OnStart(): boolean
	local model = self.Model :: Model
	if model:GetAttribute("OddityBusy") then return false end

	local canvas = model:FindFirstChild("Canvas")
	if not canvas or not canvas:IsA("BasePart") or not canvas.Anchored then return false end

	local rigName = if type(self.Config.RigModel) == "string" then self.Config.RigModel else "Ceiling Dweller"
	local enemies = ReplicatedStorage:FindFirstChild("Enemies")
	local template = enemies and enemies:FindFirstChild(rigName)
	if not template then return false end

	local rig = template:Clone() :: Model
	rig:ScaleTo(1)
	rig.Name = "PaintingDweller"
	rig:SetAttribute("EnemyId", "PaintingDweller")
	local animate = rig:FindFirstChild("Animate")
	if animate then animate:Destroy() end

	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not root or not humanoid then
		rig:Destroy()
		return false
	end

	model:SetAttribute("OddityBusy", true)
	self.Canvas = canvas

	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CollisionGroup = "Enemies"
		end
	end

	root.Anchored = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)

	local outward = canvas.CFrame.LookVector
	local anchor = canvas.Position - Vector3.yAxis * self:Setting("RootDrop", 0.5)
	local hidden = CFrame.lookAt(anchor - outward * self:Setting("HideDepth", 8), anchor + outward)

	rig.PrimaryPart = root
	rig:PivotTo(hidden)
	rig.Parent = workspace:FindFirstChild("Enemies") or workspace
	self.Rig = rig

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local function load(idKey: string): AnimationTrack?
		local id = self:Setting(idKey, 0)
		if id <= 0 then return nil end
		local animation = Instance.new("Animation")
		animation.AnimationId = `rbxassetid://{id}`
		return (animator :: Animator):LoadAnimation(animation)
	end
	self.ThrashTrack = load("ThrashAnimation")
	self.AttackTrack = load("AttackAnimation")
	if self.ThrashTrack then
		self.ThrashTrack.Looped = true
		self.ThrashTrack:Play()
	end

	local holeImage = self:Setting("HoleImage", 0)
	if holeImage > 0 then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "DwellerHole"
		gui.Face = Enum.NormalId.Front
		gui.LightInfluence = 1
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 128
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = `rbxassetid://{holeImage}`
		image.Parent = gui
		gui.Parent = canvas
		self.HoleGui = gui
	end
	for _, child in canvas:GetChildren() do
		if child:IsA("Decal") and child.Face == Enum.NormalId.Front then
			self.Decals[child] = child.Transparency
			child.Transparency = 1
		end
	end

	local pop = TweenService:Create(
		root,
		TweenInfo.new(self:Setting("PopTime", 0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = hidden + outward * self:Setting("PopDepth", 7) }
	)
	pop:Play()

	local shakeRadius = self:Setting("ShakeRadius", 32)
	for _, player in Players:GetPlayers() do
		local playerRoot = livingRoot(player)
		if playerRoot and (playerRoot.Position - canvas.Position).Magnitude <= shakeRadius then
			PopRemote:FireClient(player)
		end
	end
	LightService:FlickerNearest(
		canvas.Position,
		self:Setting("FlickerLights", 2),
		self:Setting("FlickerDuration", 1),
		0.03,
		0.08
	)

	self.PoppedAt = os.clock()

	task.spawn(function()
		while self.Active and rig.Parent do
			self:_pollAttack()
			task.wait(0.1)
		end
	end)

	return true
end

function PaintingDweller:_pollAttack()
	if os.clock() < self.NextAttack then return end

	local rig = self.Rig
	local canvas = self.Canvas
	local upper = rig and rig:FindFirstChild("UpperTorso") :: BasePart?
	if not rig or not canvas or not upper then return end

	local reach = self:Setting("AttackReach", 7)
	local outward = canvas.CFrame.LookVector
	local target: Player? = nil
	local best = reach
	for _, player in Players:GetPlayers() do
		local playerRoot = livingRoot(player)
		if not playerRoot then continue end
		local offset = playerRoot.Position - upper.Position
		if offset:Dot(outward) < 0 then continue end
		if offset.Magnitude < best then
			target = player
			best = offset.Magnitude
		end
	end
	if not target then return end

	self.NextAttack = os.clock() + self:Setting("AttackCooldown", 1.6)
	if self.AttackTrack then self.AttackTrack:Play() end
	task.delay(self:Setting("AttackHitTime", 0.38), function()
		if not self.Active then return end
		local playerRoot = livingRoot(target)
		if not playerRoot then return end
		if (playerRoot.Position - upper.Position).Magnitude > reach + 2 then return end
		DeathService:Strike(target, rig, "PaintingDweller")
	end)
end

function PaintingDweller:GroundedFor(): number
	return if self.PoppedAt > 0 then os.clock() - self.PoppedAt else 0
end

function PaintingDweller:WhyNotFixed(): string?
	if not self.Active then return "not active" end

	local model = self.Model
	if not model or not model.Parent then return "model is gone" end

	local rig = self.Rig
	if not rig or not rig.Parent then return "rig is gone" end

	return FixtureFall.DescribeNotFixed(self, rig:GetPivot().Position, rig, "retreat timer", { model, rig })
end

function PaintingDweller:IsReadyToFix(): boolean
	return self:WhyNotFixed() == nil
end

function PaintingDweller:OnStop()
	local model = self.Model
	local rig = self.Rig
	self.Rig = nil

	if rig and rig.Parent then
		if self.ThrashTrack then self.ThrashTrack:Stop(0.2) end
		local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart?
		local canvas = self.Canvas
		if root and canvas then
			local retreat = TweenService:Create(
				root,
				TweenInfo.new(self:Setting("RetreatTime", 0.4), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = root.CFrame - canvas.CFrame.LookVector * self:Setting("PopDepth", 7) }
			)
			retreat:Play()
			retreat.Completed:Wait()
		end
		rig:Destroy()
	elseif rig then
		rig:Destroy()
	end

	if self.HoleGui then
		self.HoleGui:Destroy()
		self.HoleGui = nil
	end
	for decal, transparency in self.Decals do
		if decal.Parent then decal.Transparency = transparency end
	end
	table.clear(self.Decals)
	self.Canvas = nil
	self.ThrashTrack = nil
	self.AttackTrack = nil

	if model then model:SetAttribute("OddityBusy", nil) end
end

return PaintingDweller
