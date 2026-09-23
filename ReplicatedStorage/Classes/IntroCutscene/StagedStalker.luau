local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MathService = require(ReplicatedStorage.Services.MathService)

local StagedStalker = {}
StagedStalker.__index = StagedStalker

local TAU = MathService.TAU
local ROOT_NAME = "HumanoidRootPart"
local HEAD_NAME = "Head"
local EYE_NAMES = { "LeftEye", "RightEye" }
local GLOW_NAME = "EyeGlow"
local GLOW_IMAGE_NAME = "Glow"
local WISP_NAME = "DarkWisp"
local WISP_EMITTER_NAME = "Wisp"

local HOLD_TIME = 0
local MOTION_START = 0.5
local FREEZE_TIME = 0.95
local REVEAL_FRAMES = 2
local DIP_GRACE = 1

local BREATH_PERIOD = 3.6
local DEFAULT_BREATH_AMPLITUDE = 0.035
local MAX_BREATH_AMPLITUDE = 0.05

local GLOW_IDLE = 0.45
local GLOW_PULSE_PERIOD = 2.3
local GLOW_TOWARD_CAMERA = 0.4
local GLOW_SCALE = 0.55
local GLOW_VISIBLE = 0.01
local FLARE_ATTACK = 0.07
local FLARE_DECAY = 0.4
local FLARE_SUSTAIN = 0.3
local FLARE_GROWTH = 0.8
local FLARE_BRIGHTNESS = 0.5
local FLARE_EYE_HEAT = 0.55
local HOT_EYE = Color3.fromRGB(255, 170, 160)
local DIP_GLOW_FADE = 0.12

local WISP_DELAY = 0.05
local WISP_BURST = 7
local WISP_TRAIL_DELAY = 0.14
local WISP_TRAIL = 3
local WISP_LIFT = 0.35

type State = "Loading" | "Posing" | "Holding" | "Dipping" | "Hidden"

type Glow = {
	Gui: BillboardGui,
	Image: ImageLabel,
	Size: UDim2,
	Transparency: number,
	Brightness: number,
}

type Eye = {
	Part: BasePart,
	Color: Color3,
	Glow: Glow?,
}

export type Options = {
	Parent: Instance,
	Template: Model,
	Effects: Folder?,
	AnimationId: number,
	PeekCFrame: CFrame,
	HiddenCFrame: CFrame,
	BreathAmplitude: number?,
	EyeGlowColor: Color3?,
}

export type StagedStalker = typeof(setmetatable({} :: {
	Model: Model,
	Root: BasePart?,
	Head: BasePart?,
	Animation: Animation,
	Track: AnimationTrack?,
	Parts: { BasePart },
	Overlays: { Decal },
	Eyes: { Eye },
	WispTemplate: Attachment?,
	Stage: Instance,
	PeekCFrame: CFrame,
	HiddenCFrame: CFrame,
	BreathAmplitude: number,
	Seed: number,
	Phase: number,
	BornAt: number,
	State: State,
	PosedFrames: number,
	Visible: boolean,
	NoticedAt: number?,
	DipRequested: boolean,
	DipStartedAt: number?,
	DipRate: number,
	DipDeadline: number,
	Dipped: boolean,
	Preloading: boolean,
	Destroyed: boolean,
	ModelGone: boolean,
	Puff: BasePart?,
	Connections: { [string]: RBXScriptConnection },
}, StagedStalker))

local function stripTags(instance: Instance)
	for _, tag in instance:GetTags() do
		instance:RemoveTag(tag)
	end
end

local function sanitize(rig: Model, anchor: Instance?): ({ BasePart }, { Decal })
	for _, descendant in rig:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end

	stripTags(rig)
	local parts: { BasePart } = {}
	local overlays: { Decal } = {}
	for _, descendant in rig:GetDescendants() do
		stripTags(descendant)
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == anchor
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.LocalTransparencyModifier = 1
			table.insert(parts, descendant)
		elseif descendant:IsA("Decal") then
			descendant.LocalTransparencyModifier = 1
			table.insert(overlays, descendant)
		end
	end
	return parts, overlays
end

local function attachGlow(template: Instance?, part: BasePart, tint: Color3?): Glow?
	if not template or not template:IsA("BillboardGui") then return nil end

	local gui = template:Clone()
	local image = gui:FindFirstChild(GLOW_IMAGE_NAME)
	if not image or not image:IsA("ImageLabel") then
		gui:Destroy()
		return nil
	end

	if tint then
		image.ImageColor3 = tint
	end
	local size = gui.Size
	gui.Size = UDim2.new(size.X.Scale * GLOW_SCALE, size.X.Offset, size.Y.Scale * GLOW_SCALE, size.Y.Offset)
	gui.Adornee = part
	gui.Enabled = false
	gui.StudsOffset = Vector3.new(0, 0, GLOW_TOWARD_CAMERA)
	gui.Parent = part

	return {
		Gui = gui,
		Image = image,
		Size = gui.Size,
		Transparency = image.ImageTransparency,
		Brightness = gui.Brightness,
	}
end

local function findWisp(effects: Folder?): Attachment?
	local template = effects and effects:FindFirstChild(WISP_NAME)
	if not template or not template:IsA("Attachment") then return nil end
	local emitter = template:FindFirstChild(WISP_EMITTER_NAME)
	if not emitter or not emitter:IsA("ParticleEmitter") then return nil end
	return template
end

local function orientUp(position: Vector3, up: Vector3): CFrame
	local right = up:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-3 then
		right = Vector3.xAxis
	end
	return CFrame.fromMatrix(position, right.Unit, up)
end

local function setUpConnections(self: StagedStalker)
	self.Connections = {}

	self.Connections.Pose = RunService.PreAnimation:Connect(function()
		self:_step()
	end)
	self.Connections.Destroying = self.Model.Destroying:Connect(function()
		self.ModelGone = true
		self:Destroy()
	end)
end

function StagedStalker.new(options: Options): StagedStalker
	local rig = options.Template:Clone()
	rig.Name = "StagedStalker"

	local rootInstance = rig:FindFirstChild(ROOT_NAME)
	local root = if rootInstance and rootInstance:IsA("BasePart") then rootInstance else nil
	local headInstance = rig:FindFirstChild(HEAD_NAME)
	local head = if headInstance and headInstance:IsA("BasePart") then headInstance else nil
	local humanoid = rig:FindFirstChildOfClass("Humanoid")

	local parts, overlays = sanitize(rig, root)

	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.BreakJointsOnDeath = false
	end
	if root then
		root.CFrame = options.PeekCFrame
	else
		warn("[StagedStalker] template has no HumanoidRootPart; the stalker will stay hidden")
	end

	local glowTemplate = options.Effects and options.Effects:FindFirstChild(GLOW_NAME)
	local eyes: { Eye } = {}
	for _, name in EYE_NAMES do
		local part = head and head:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(eyes, {
				Part = part,
				Color = part.Color,
				Glow = attachGlow(glowTemplate, part, options.EyeGlowColor),
			})
		end
	end

	rig.Parent = options.Parent

	local animation = Instance.new("Animation")
	animation.AnimationId = `rbxassetid://{options.AnimationId}`

	local track: AnimationTrack? = nil
	if humanoid and root then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end
		local loaded, result = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if loaded and result then
			track = result
			result.Priority = Enum.AnimationPriority.Action
			result.Looped = false
			result:Play(0)
			result:AdjustSpeed(0)
			result.TimePosition = HOLD_TIME
		else
			warn(`[StagedStalker] could not load the peek animation: {result}`)
		end
	end

	local random = Random.new()
	local self = setmetatable({
		Model = rig,
		Root = root,
		Head = head,
		Animation = animation,
		Track = track,
		Parts = parts,
		Overlays = overlays,
		Eyes = eyes,
		WispTemplate = findWisp(options.Effects),
		Stage = options.Parent,
		PeekCFrame = options.PeekCFrame,
		HiddenCFrame = options.HiddenCFrame,
		BreathAmplitude = math.clamp(options.BreathAmplitude or DEFAULT_BREATH_AMPLITUDE, 0, MAX_BREATH_AMPLITUDE),
		Seed = random:NextNumber(0, 1000) + 0.37,
		Phase = random:NextNumber(0, TAU),
		BornAt = os.clock(),
		State = "Loading" :: State,
		PosedFrames = 0,
		Visible = false,
		NoticedAt = nil :: number?,
		DipRequested = false,
		DipStartedAt = nil :: number?,
		DipRate = 1,
		DipDeadline = math.huge,
		Dipped = false,
		Preloading = false,
		Destroyed = false,
		ModelGone = false,
		Puff = nil :: BasePart?,
		Connections = {},
	}, StagedStalker)

	setUpConnections(self)
	self:_preload()

	return self
end

function StagedStalker:_preload()
	if self.Preloading or self.Destroyed then return end
	self.Preloading = true

	local animation = self.Animation
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { animation })
	end)
end

function StagedStalker:IsReady(): boolean
	local track = self.Track
	return not self.Destroyed and track ~= nil and track.Length > 0
end

function StagedStalker:WaitReady(timeout: number): boolean
	if self:IsReady() then return true end
	self:_preload()

	local deadline = os.clock() + math.max(timeout, 0)
	while not self.Destroyed and not self:IsReady() and os.clock() < deadline do
		RunService.Heartbeat:Wait()
	end
	return self:IsReady()
end

function StagedStalker:_setVisible(visible: boolean)
	self.Visible = visible

	local value = if visible then 0 else 1
	for _, part in self.Parts do
		if part.Parent and part.LocalTransparencyModifier ~= value then
			part.LocalTransparencyModifier = value
		end
	end
	for _, overlay in self.Overlays do
		if overlay.Parent and overlay.LocalTransparencyModifier ~= value then
			overlay.LocalTransparencyModifier = value
		end
	end
	self:_renderGlow(os.clock())
end

function StagedStalker:_flare(now: number): number
	local noticedAt = self.NoticedAt
	if not noticedAt then return 0 end

	local elapsed = now - noticedAt
	if elapsed <= 0 then return 0 end
	if elapsed < FLARE_ATTACK then
		return MathService.Eases.OutQuad(elapsed / FLARE_ATTACK)
	end
	return FLARE_SUSTAIN + (1 - FLARE_SUSTAIN) * math.exp(-(elapsed - FLARE_ATTACK) / FLARE_DECAY)
end

function StagedStalker:_renderGlow(now: number)
	local fade = if self.Visible then 1 else 0
	local dipStartedAt = self.DipStartedAt
	if self.State == "Dipping" and dipStartedAt then
		fade *= 1 - math.clamp((now - dipStartedAt) / DIP_GLOW_FADE, 0, 1)
	elseif self.State == "Hidden" then
		fade = 0
	end

	local flare = self:_flare(now)
	local pulse = 0.5 + 0.5 * math.sin((now - self.BornAt) * TAU / GLOW_PULSE_PERIOD + self.Phase)
	local strength = math.clamp((GLOW_IDLE + (1 - GLOW_IDLE) * flare) * (0.88 + 0.12 * pulse), 0, 1) * fade
	local growth = 1 + 0.06 * pulse + FLARE_GROWTH * flare

	for _, eye in self.Eyes do
		local part = eye.Part
		if part.Parent then
			part.Color = eye.Color:Lerp(HOT_EYE, flare * FLARE_EYE_HEAT * fade)
		end

		local glow = eye.Glow
		if not glow or not glow.Gui.Parent then continue end

		local shown = strength > GLOW_VISIBLE
		if glow.Gui.Enabled ~= shown then
			glow.Gui.Enabled = shown
		end
		if shown then
			local size = glow.Size
			glow.Gui.Size = UDim2.new(size.X.Scale * growth, size.X.Offset, size.Y.Scale * growth, size.Y.Offset)
			glow.Gui.Brightness = glow.Brightness * (1 + FLARE_BRIGHTNESS * flare)
			glow.Image.ImageTransparency = 1 - (1 - glow.Transparency) * strength
		end
	end
end

function StagedStalker:_breath(now: number): CFrame
	local amplitude = self.BreathAmplitude
	if amplitude <= 0 then return CFrame.identity end

	local cycle = (now - self.BornAt) * TAU / BREATH_PERIOD + self.Phase
	local rise = amplitude * (0.8 * math.sin(cycle) + 0.2 * math.sin(2 * cycle + 0.9))
	local sway = amplitude * (0.5 * math.sin(0.5 * cycle + 1.3) + 0.15 * math.noise(cycle * 0.4, self.Seed))
	local offset = Vector3.new(sway, rise, 0)
	if offset.Magnitude > MAX_BREATH_AMPLITUDE then
		offset = offset.Unit * MAX_BREATH_AMPLITUDE
	end
	return CFrame.new(offset)
end

function StagedStalker:_conceal()
	local track = self.Track
	if track and track.IsPlaying then
		track:AdjustSpeed(0)
		if self.State == "Dipping" then
			track.TimePosition = FREEZE_TIME
		end
	end
	self.State = "Hidden"
	self:_setVisible(false)
	self.Dipped = true
end

function StagedStalker:_step()
	if self.Destroyed then return end
	local track = self.Track
	if not track then return end

	local state = self.State
	if state == "Loading" then
		if track.Length > 0 then
			if not track.IsPlaying then
				track:Play(0)
			end
			track:AdjustSpeed(0)
			track.TimePosition = HOLD_TIME
			self.State = "Posing"
			self.PosedFrames = 0
		end
	elseif state == "Posing" then
		if not track.IsPlaying then
			self.State = "Loading"
			return
		end
		track.TimePosition = HOLD_TIME
		self.PosedFrames += 1
		if self.PosedFrames >= REVEAL_FRAMES then
			self.State = "Holding"
			self:_setVisible(true)
		end
	elseif state == "Holding" then
		if not track.IsPlaying then
			self:_conceal()
		end
	elseif state == "Dipping" then
		if not track.IsPlaying then
			self:_conceal()
			return
		end

		local now = os.clock()
		local elapsed = now - (self.DipStartedAt or now)
		local time = math.min(MOTION_START + elapsed * self.DipRate, FREEZE_TIME)
		track.TimePosition = time
		if time >= FREEZE_TIME or now >= self.DipDeadline then
			self:_conceal()
		else
			self:_renderGlow(now)
		end
	end
end

function StagedStalker:Update(_deltaTime: number)
	if self.Destroyed then return end

	local now = os.clock()
	local root = self.Root
	if root and (self.State == "Posing" or self.State == "Holding") then
		root.CFrame = self.PeekCFrame * self:_breath(now)
	end
	self:_renderGlow(now)
end

function StagedStalker:Notice()
	if self.Destroyed then return end
	self.NoticedAt = os.clock()
	self:_renderGlow(os.clock())
end

function StagedStalker:_puff(length: number)
	local template = self.WispTemplate
	if not template then return end

	local head = self.Head
	local origin = if head and head.Parent then head.Position else self.PeekCFrame.Position
	local away = MathService.Horizontal(self.HiddenCFrame.Position - self.PeekCFrame.Position)
	local direction = if away.Magnitude > 1e-3
		then (away.Unit * (1 - WISP_LIFT) + Vector3.yAxis * WISP_LIFT).Unit
		else Vector3.yAxis

	local holder = Instance.new("Part")
	holder.Name = "DipWisp"
	holder.Size = Vector3.one * 0.2
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.CFrame = orientUp(origin, direction)

	local attachment = template:Clone()
	attachment.CFrame = CFrame.identity
	attachment.Parent = holder
	holder.Parent = self.Stage
	self.Puff = holder

	local emitter = attachment:FindFirstChild(WISP_EMITTER_NAME) :: ParticleEmitter
	local pace = length / (FREEZE_TIME - MOTION_START)
	task.delay(WISP_DELAY * pace, function()
		if self.Destroyed or not emitter.Parent then return end
		emitter:Emit(WISP_BURST)
	end)
	task.delay(WISP_TRAIL_DELAY * pace, function()
		if self.Destroyed or not emitter.Parent then return end
		emitter:Emit(WISP_TRAIL)
	end)
end

function StagedStalker:DipAsync(duration: number?)
	if self.Destroyed or self.DipRequested then return end
	self.DipRequested = true

	local root, track = self.Root, self.Track
	if self.State ~= "Holding" or not root or not track or not track.IsPlaying then
		self:_conceal()
		return
	end

	local length = if duration and duration > 0 then duration else FREEZE_TIME - MOTION_START
	local now = os.clock()
	self.DipRate = (FREEZE_TIME - MOTION_START) / length
	self.DipStartedAt = now
	self.DipDeadline = now + length + DIP_GRACE
	self.State = "Dipping"

	root.CFrame = self.PeekCFrame
	track:AdjustSpeed(0)
	track.TimePosition = MOTION_START
	self:_puff(length)
end

function StagedStalker:GetHeadPosition(): Vector3
	local head = self.Head
	if head and head.Parent then
		return head.Position
	end
	return self.PeekCFrame.Position
end

function StagedStalker:GetEyePositions(): (Vector3, Vector3)
	local fallback = self:GetHeadPosition()
	local positions = {}
	for _, eye in self.Eyes do
		if eye.Part.Parent then
			positions[eye.Part.Name] = eye.Part.Position
		end
	end
	return positions[EYE_NAMES[1]] or fallback, positions[EYE_NAMES[2]] or fallback
end

function StagedStalker:Destroy()
	if self.Destroyed then return end

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	if not self.ModelGone then
		self:_setVisible(false)
	end
	self.Destroyed = true

	local track = self.Track
	if track then
		self.Track = nil
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	self.Animation:Destroy()

	local puff = self.Puff
	if puff then
		self.Puff = nil
		puff:Destroy()
	end
	if not self.ModelGone then
		self.Model:Destroy()
	end
end

return StagedStalker
