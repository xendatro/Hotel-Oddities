local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathService = require(ReplicatedStorage.Services.MathService)

local StagedRig = {}
StagedRig.__index = StagedRig

local ROOT_NAME = "HumanoidRootPart"
local REMOVED_CLASSES = {
	"LuaSourceContainer",
	"Tool",
	"ForceField",
	"Sound",
	"AudioPlayer",
	"AudioEmitter",
	"AudioListener",
	"AudioDeviceInput",
	"AudioAnalyzer",
	"BillboardGui",
	"Highlight",
	"ProximityPrompt",
	"BodyMover",
	"AlignPosition",
	"AlignOrientation",
	"VectorForce",
	"LinearVelocity",
	"AngularVelocity",
	"Torque",
	"LineForce",
}

type Aim = {
	Joint: Instance,
	From: CFrame,
	To: CFrame,
	Current: CFrame,
	StartedAt: number,
	Duration: number,
}

export type StagedRig = typeof(setmetatable({} :: {
	Model: Model,
	Root: BasePart?,
	Humanoid: Humanoid?,
	Animator: Animator?,
	Parts: { BasePart },
	Overlays: { Decal },
	Fade: number,
	Tracks: { [Animation]: AnimationTrack },
	Joints: { [string]: Instance },
	Bases: { [Instance]: CFrame },
	Aims: { [string]: Aim },
	Offsets: { [string]: CFrame },
	Clock: number,
	Destroyed: boolean,
}, StagedRig))

local function isRemoved(instance: Instance): boolean
	for _, className in REMOVED_CLASSES do
		if instance:IsA(className) then return true end
	end
	return false
end

local function stripTags(instance: Instance)
	for _, tag in instance:GetTags() do
		instance:RemoveTag(tag)
	end
end

function StagedRig.CloneCharacter(character: Model): Model?
	local archivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(character.Clone, character)
	character.Archivable = archivable
	if ok and copy then return copy end
	return nil
end

function StagedRig.new(model: Model, parent: Instance): StagedRig
	for _, descendant in model:GetDescendants() do
		if descendant.Parent and isRemoved(descendant) then
			descendant:Destroy()
		end
	end

	local rootInstance = model:FindFirstChild(ROOT_NAME)
	local root = if rootInstance and rootInstance:IsA("BasePart") then rootInstance else model.PrimaryPart
	local humanoid = model:FindFirstChildOfClass("Humanoid")

	stripTags(model)
	local parts: { BasePart } = {}
	local overlays: { Decal } = {}
	for _, descendant in model:GetDescendants() do
		stripTags(descendant)
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == root
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.LocalTransparencyModifier = 1
			table.insert(parts, descendant)
		elseif descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 1
			table.insert(overlays, descendant)
		end
	end

	local animator: Animator? = nil
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		animator = humanoid:FindFirstChildOfClass("Animator")
	end

	model.Parent = parent

	return setmetatable({
		Model = model,
		Root = root,
		Humanoid = humanoid,
		Animator = animator,
		Parts = parts,
		Overlays = overlays,
		Fade = 1,
		Tracks = {},
		Joints = {},
		Bases = {},
		Aims = {},
		Offsets = {},
		Clock = 0,
		Destroyed = false,
	}, StagedRig)
end

function StagedRig:RootHeight(): number
	local root = self.Root
	local humanoid = self.Humanoid
	if not root then return 3 end
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y * 1.5
end

function StagedRig:Place(cframe: CFrame)
	if self.Destroyed then return end
	local root = self.Root
	if root then
		root.CFrame = cframe
	else
		self.Model:PivotTo(cframe)
	end
end

function StagedRig:GetCFrame(): CFrame
	local root = self.Root
	return if root then root.CFrame else self.Model:GetPivot()
end

function StagedRig:SetFade(fade: number)
	if self.Destroyed then return end
	local value = math.clamp(fade, 0, 1)
	if value == self.Fade then return end
	self.Fade = value
	for _, part in self.Parts do
		if part.Parent then
			part.LocalTransparencyModifier = value
		end
	end
	for _, overlay in self.Overlays do
		if overlay.Parent then
			overlay.LocalTransparencyModifier = value
		end
	end
end

function StagedRig:SetVisible(visible: boolean)
	self:SetFade(if visible then 0 else 1)
end

function StagedRig:IsVisible(): boolean
	return self.Fade < 1
end

function StagedRig:Play(animation: Animation?, priority: Enum.AnimationPriority?, fade: number?): AnimationTrack?
	local animator = self.Animator
	if self.Destroyed or not animation or not animator then return nil end

	local track = self.Tracks[animation]
	if not track then
		local ok, loaded = pcall(animator.LoadAnimation, animator, animation)
		if not ok or not loaded then return nil end
		track = loaded
		self.Tracks[animation] = loaded
	end
	local playing = track :: AnimationTrack
	playing.Priority = priority or Enum.AnimationPriority.Idle
	playing.Looped = true
	if not playing.IsPlaying then
		playing:Play(fade or 0.2)
	end
	return playing
end

function StagedRig:Stop(animation: Animation?, fade: number?)
	local track = animation and self.Tracks[animation]
	if track and track.IsPlaying then
		track:Stop(fade or 0.2)
	end
end

function StagedRig:_joint(name: string): Instance?
	local cached = self.Joints[name]
	if cached and cached.Parent then return cached end
	for _, descendant in self.Model:GetDescendants() do
		if descendant.Name == name and (descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint")) then
			self.Joints[name] = descendant
			return descendant
		end
	end
	return nil
end

function StagedRig:_write(joint: Instance, rotation: CFrame)
	if joint:IsA("Motor6D") then
		local base = self.Bases[joint] or joint.C0
		self.Bases[joint] = base
		joint.C0 = base * rotation
		return
	end

	local attachment = (joint :: AnimationConstraint).Attachment0
	if not attachment then return end
	local base = self.Bases[attachment] or attachment.CFrame
	self.Bases[attachment] = base
	attachment.CFrame = base * rotation
end

function StagedRig:Bend(name: string, pitch: number, yaw: number, roll: number, duration: number?)
	if self.Destroyed then return end
	local joint = self:_joint(name)
	if not joint then return end

	local target = CFrame.fromEulerAnglesYXZ(math.rad(pitch), math.rad(yaw), math.rad(roll))
	local aim = self.Aims[name]
	local current = if aim then aim.Current else CFrame.identity
	local time = duration or 0
	if time <= 0 then
		self.Aims[name] = { Joint = joint, From = target, To = target, Current = target, StartedAt = self.Clock, Duration = 0 }
		self:_write(joint, target * (self.Offsets[name] or CFrame.identity))
		return
	end
	self.Aims[name] = { Joint = joint, From = current, To = target, Current = current, StartedAt = self.Clock, Duration = time }
end

function StagedRig:SetOffset(name: string, offset: CFrame)
	if self.Destroyed then return end
	local joint = self:_joint(name)
	if not joint then return end
	self.Offsets[name] = offset
	local aim = self.Aims[name]
	self:_write(joint, (if aim then aim.Current else CFrame.identity) * offset)
end

function StagedRig:Update(deltaTime: number)
	if self.Destroyed then return end
	self.Clock += deltaTime
	for name, aim in self.Aims do
		if aim.Duration <= 0 then continue end
		local alpha = math.clamp((self.Clock - aim.StartedAt) / aim.Duration, 0, 1)
		aim.Current = if alpha >= 1 then aim.To else aim.From:Lerp(aim.To, MathService.Eases.InOutSine(alpha))
		if alpha >= 1 then
			aim.Duration = 0
		end
		if aim.Joint.Parent then
			self:_write(aim.Joint, aim.Current * (self.Offsets[name] or CFrame.identity))
		end
	end
end

function StagedRig:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	for _, track in self.Tracks do
		pcall(track.Stop, track, 0)
		pcall(track.Destroy, track)
	end
	table.clear(self.Tracks)
	table.clear(self.Aims)
	table.clear(self.Offsets)
	self.Model:Destroy()
end

return StagedRig
