-- Local-only staging for trailer shots: enemy and avatar rigs driven by script,
-- lamp control, VFX, and property overrides that all undo themselves when the
-- shot ends. Nothing here replicates; every shot builds its own Stage.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Isolation = require(ReplicatedStorage.Classes.IntroCutscene.Isolation)
local LightSweep = require(ReplicatedStorage.Classes.IntroCutscene.LightSweep)
local LocalOverride = require(ReplicatedStorage.Classes.LocalOverride)
local VfxEffect = require(ReplicatedStorage.Classes.VfxEffect)

local Stage = {}
Stage.__index = Stage

local LAMP_TAGS = { "HallwayLantern", "CeilingLight", "JunctionLight", "Floor1Light" }
local CYCLE_DISTANCE = 8

local Rig = {}
Rig.__index = Rig

function Stage.new(name: string)
	local folder = Instance.new("Model")
	folder.Name = `TrailerStage_{name}`
	folder.Parent = workspace

	local self = setmetatable({
		Folder = folder,
		Override = LocalOverride.new(),
		Bin = {},
		Rigs = {},
	}, Stage)
	return self
end

function Stage:Add(item: any)
	table.insert(self.Bin, item)
	return item
end

function Stage:Set(instance: Instance, property: string, value: any)
	self.Override:Set(instance, property, value)
end

function Stage:Isolate()
	local isolation = Isolation.new({ Override = self.Override })
	isolation:Start()
	self:Add(function()
		isolation:Stop()
		isolation:Destroy()
	end)
	return isolation
end

function Stage:Effects(): Folder?
	return ReplicatedStorage:FindFirstChild("Effects") :: Folder?
end

function Stage:Vfx(name: string, cframe: CFrame, options: { Size: Vector3?, Duration: number? }?)
	local effects = self:Effects()
	local template = effects and effects:FindFirstChild(name, true)
	if not template or not template:IsA("BasePart") then
		warn(`[Trailer] no VFX template {name}`)
		return nil
	end
	local effect = VfxEffect.new(template, cframe, self.Folder, options)
	self:Add(function()
		effect:Destroy()
	end)
	return effect
end

function Stage:Sweep(min: Vector3, max: Vector3, ambient: { Color3 }?)
	local sweep = LightSweep.new({
		Region = { Min = min, Max = max },
		Tags = LAMP_TAGS,
		Override = self.Override,
		Sounds = {},
		Ambient = ambient,
	})
	sweep:Collect()
	self:Add(function()
		sweep:Restore()
		sweep:Destroy()
	end)
	return sweep
end

function Stage:LampsIn(min: Vector3, max: Vector3): { Model }
	local found = {}
	for _, tag in LAMP_TAGS do
		for _, lamp in CollectionService:GetTagged(tag) do
			if not lamp:IsA("Model") or not lamp:IsDescendantOf(workspace) then continue end
			local position = lamp:GetPivot().Position
			if position.X >= min.X and position.X <= max.X
				and position.Y >= min.Y and position.Y <= max.Y
				and position.Z >= min.Z and position.Z <= max.Z then
				table.insert(found, lamp)
			end
		end
	end
	return found
end

function Stage:Tint(lamps: { Model }, color: Color3, brightness: number?)
	for _, lamp in lamps do
		for _, item in lamp:GetDescendants() do
			if item:IsA("Light") then
				self:Set(item, "Color", color)
				if brightness then
					self:Set(item, "Brightness", item.Brightness * brightness)
				end
			elseif item:IsA("BasePart") and item.Material == Enum.Material.Neon then
				self:Set(item, "Color", color)
			end
		end
	end
end

local function strip(model: Model)
	for _, item in model:GetDescendants() do
		if item:IsA("BaseScript") or item:IsA("ProximityPrompt") or item:IsA("Sound") or item:IsA("AudioPlayer") then
			item:Destroy()
		end
	end
	for _, tag in CollectionService:GetTags(model) do
		CollectionService:RemoveTag(model, tag)
	end
	for _, item in model:GetDescendants() do
		for _, tag in CollectionService:GetTags(item) do
			CollectionService:RemoveTag(item, tag)
		end
	end
end

local function prepareRig(model: Model): (BasePart?, Humanoid?)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = (humanoid and humanoid.RootPart) or model:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = part == root
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.AutomaticScalingEnabled = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
	return root, humanoid
end

function Stage:Rig(model: Model, cframe: CFrame)
	strip(model)
	local root, humanoid = prepareRig(model)
	if root then
		model:PivotTo(cframe * root.CFrame:Inverse() * model:GetPivot())
	else
		model:PivotTo(cframe)
	end
	model.Parent = self.Folder
	local rig = setmetatable({
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Animator = humanoid and humanoid:FindFirstChildOfClass("Animator"),
		Tracks = {},
		Offset = if root then model:GetPivot():ToObjectSpace(root.CFrame) else CFrame.identity,
	}, Rig)
	table.insert(self.Rigs, rig)
	return rig
end

function Stage:Enemy(name: string, cframe: CFrame)
	local enemies = ReplicatedStorage:FindFirstChild("Enemies")
	local template = enemies and enemies:FindFirstChild(name)
	assert(template and template:IsA("Model"), `no enemy template {name}`)
	return self:Rig(template:Clone(), cframe)
end

local function assemble(model: Model)
	model:PivotTo(CFrame.new(0, -5000, 0))
	model.Parent = workspace
	RunService.Heartbeat:Wait()
	RunService.Heartbeat:Wait()
	model.Parent = nil
end

function Stage:Avatar(username: string, cframe: CFrame, clean: ((Model) -> ())?)
	local userId = Players:GetUserIdFromNameAsync(username)
	local description = Players:GetHumanoidDescriptionFromUserIdAsync(userId)
	local model = Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	model.Name = username
	assemble(model)
	if clean then
		clean(model)
	end
	return self:Rig(model, cframe)
end

function Rig:Load(id: number, priority: Enum.AnimationPriority?): AnimationTrack?
	local cached = self.Tracks[id]
	if cached then return cached end
	if not self.Animator then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{id}`
	local track = self.Animator:LoadAnimation(animation)
	track.Priority = priority or Enum.AnimationPriority.Action
	self.Tracks[id] = track
	return track
end

function Rig:Play(id: number, options: { Speed: number?, Fade: number?, Looped: boolean?, Weight: number?, Priority: Enum.AnimationPriority? }?)
	local track = self:Load(id, options and options.Priority)
	if not track then return nil end
	if options and options.Looped ~= nil then
		track.Looped = options.Looped
	end
	track:Play(options and options.Fade or 0.15, options and options.Weight or 1, options and options.Speed or 1)
	return track
end

function Rig:Stop(id: number, fade: number?)
	local track = self.Tracks[id]
	if track then
		track:Stop(fade or 0.15)
	end
end

function Rig:Gait(id: number, speed: number, scale: number?)
	local track = self:Load(id, Enum.AnimationPriority.Movement)
	if not track then return end
	if not track.IsPlaying then
		track.Looped = true
		track:Play(0.1)
	end
	local length = if track.Length > 0 then track.Length else 1
	track:AdjustSpeed(speed * length / CYCLE_DISTANCE * (scale or 1))
end

function Rig:SetCFrame(cframe: CFrame)
	if self.Root then
		self.Root.CFrame = cframe
	else
		self.Model:PivotTo(cframe)
	end
end

function Rig:GetCFrame(): CFrame
	return if self.Root then self.Root.CFrame else self.Model:GetPivot()
end

function Rig:Joint(name: string): Motor6D?
	local joint = self.Model:FindFirstChild(name, true)
	return if joint and joint:IsA("Motor6D") then joint else nil
end

function Rig:Bend(name: string, rotation: CFrame)
	local joint = self:Joint(name)
	if not joint then return end
	self.Bases = self.Bases or {}
	local base = self.Bases[joint]
	if not base then
		base = joint.C0
		self.Bases[joint] = base
	end
	joint.C0 = base * rotation
end

function Stage:Flicker(min: Vector3, max: Vector3, seed: number?)
	local lights = {}
	for _, lamp in self:LampsIn(min, max) do
		for _, item in lamp:GetDescendants() do
			if item:IsA("Light") then
				table.insert(lights, { Light = item, Base = item.Brightness, Phase = #lights * 1.37 + (seed or 0) })
			end
		end
	end
	return function(time: number, amount: number)
		for _, entry in lights do
			local wobble = math.noise(time * 9 + entry.Phase, entry.Phase) * 0.5 + 0.5
			local drop = if math.noise(time * 3.1, entry.Phase * 2.3) > 0.18 then 0.08 else 1
			local level = 1 - amount * (1 - math.clamp(wobble * drop * 1.3, 0, 1))
			self:Set(entry.Light, "Brightness", entry.Base * level)
		end
	end
end

function Rig:Preload(ids: { number }, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 5)
	for _, id in ids do
		local track = self:Load(id)
		while track and track.Length <= 0 and os.clock() < deadline do
			task.wait()
		end
	end
	return os.clock() < deadline
end

function Stage:Path(points: { Vector3 }): { Total: number, Sample: (number) -> (Vector3, Vector3) }
	local lengths = { 0 }
	for index = 2, #points do
		lengths[index] = lengths[index - 1] + (points[index] - points[index - 1]).Magnitude
	end
	local total = lengths[#points]
	local function sample(distance: number): (Vector3, Vector3)
		distance = math.clamp(distance, 0, total)
		for index = 2, #points do
			if distance <= lengths[index] or index == #points then
				local span = lengths[index] - lengths[index - 1]
				local alpha = if span > 0 then (distance - lengths[index - 1]) / span else 0
				local from, to = points[index - 1], points[index]
				return from:Lerp(to, alpha), (to - from).Unit
			end
		end
		return points[#points], Vector3.zAxis
	end
	return { Total = total, Sample = sample }
end

function Stage:Destroy()
	for index = #self.Bin, 1, -1 do
		local item = self.Bin[index]
		local ok, err = pcall(function()
			if type(item) == "function" then
				item()
			elseif typeof(item) == "Instance" then
				item:Destroy()
			elseif typeof(item) == "RBXScriptConnection" then
				item:Disconnect()
			end
		end)
		if not ok then
			warn(`[Trailer] cleanup failed: {err}`)
		end
	end
	table.clear(self.Bin)
	for _, rig in self.Rigs do
		for _, track in rig.Tracks do
			pcall(track.Stop, track, 0)
		end
	end
	self.Override:Restore()
	self.Override:Destroy()
	self.Folder:Destroy()
end

return Stage
