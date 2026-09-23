local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CreepConfig = require(ReplicatedStorage.Configs.CreepConfig)
local Aim = require(ReplicatedStorage.Services.AimService)
local MathService = require(ReplicatedStorage.Services.MathService)
local TweenProxyService = require(ReplicatedStorage.Services.TweenProxyService)

local StagedCreep = {}
StagedCreep.__index = StagedCreep

local TAU = MathService.TAU
local MINIMUM_DIRECTION = 1e-3
local TURN_RATE = CreepConfig.TurnRate
local SIDES = { "Left", "Right" }
local EYE_PREFIX = "Eye"
local PUPIL_PREFIX = "Pupil"
local GLOW_NAME = "EyeGlow"
local GLOW_IMAGE_NAME = "Glow"
local WISP_NAME = "DarkWisp"
local WISP_EMITTER_NAME = "Wisp"
local DISTORTION_NAME = "CreepDistortion"

local CLOSED = 0.02
local SLIT = 0.015
local DEFAULT_OPEN_TIME = 0.35
local DEFAULT_CLOSE_TIME = 0.14
local CRACK_TIME = 0.09
local BLINK_CLOSE_TIME = 0.07
local BLINK_HOLD_TIME = 0.02
local BLINK_OPEN_TIME = 0.12
local BLINK_OVERSHOOT = 1.1
local BLINK_MINIMUM = 0.5

local PUPIL_DILATED = 1.3
local PUPIL_NARROW = 0.9
local PUPIL_NARROW_TIME = 0.35
local PUPIL_SETTLE_TIME = 0.5

local BACKDROP_FADE_TIME = 0.7
local GLOW_RISE_TIME = 0.55
local GLOW_EYE_RATIO = 2.6
local GLOW_BEHIND_EYE = 0.35
local GLOW_SQUASH = 0.55
local GLOW_PULSE_PERIOD = 2.7
local GLOW_WIDEN_BRIGHTNESS = 3
local GLOW_VISIBLE = 0.01

local LIGHT_BRIGHTNESS = 0.6
local LIGHT_RANGE = 10

local WISP_RATE = 2.4
local WISP_BREATH_PERIOD = 3.1
local WISP_SPOTS = {
	CFrame.new(-1.9, 0.1, 0.4) * CFrame.Angles(0, 0, math.rad(35)),
	CFrame.new(1.9, -0.1, 0.4) * CFrame.Angles(0, 0, math.rad(-35)),
	CFrame.new(0, -1.2, 0.5),
}

local GAZE_RANGE = 0.1
local GAZE_RATE = 18
local GAZE_BIAS = 1.6
local SACCADE_MIN = 0.7
local SACCADE_MAX = 2.1
local TREMOR = 0.012
local TREMOR_SPEED = 7
local HOVER = 0.035

local DISTORTION_OVERRUN = 0.35

local TRAITS = {
	Left = { Lead = 0, Crack = 0.26, Hesitate = 0.07, Pace = 1, Overshoot = 1.4, Lag = 0 },
	Right = { Lead = 0.045, Crack = 0.19, Hesitate = 0.09, Pace = 1.08, Overshoot = 2, Lag = 0.014 },
}

type Ease = (number) -> number

type Segment = {
	Duration: number,
	Target: number,
	Ease: Ease,
}

type Curve = {
	Origin: number,
	StartedAt: number,
	Segments: { Segment },
}

type Trait = {
	Lead: number,
	Crack: number,
	Hesitate: number,
	Pace: number,
	Overshoot: number,
	Lag: number,
}

type Lens = {
	Part: BasePart,
	Mesh: SpecialMesh,
	Offset: CFrame,
	Normal: Vector3,
	Vertical: Vector3,
	Diameter: number,
	Shown: boolean,
}

type Glow = {
	Gui: BillboardGui,
	Image: ImageLabel,
	Size: UDim2,
	Transparency: number,
	Brightness: number,
}

type Eye = {
	Eye: Lens,
	Pupil: Lens?,
	Glow: Glow?,
	Lid: Curve,
	Trait: Trait,
	Seed: number,
}

type Plate = {
	Part: BasePart,
	Offset: CFrame,
	Rotation: CFrame,
	Aimed: boolean,
	Seed: number,
	Eyes: { Eye },
}

export type Options = {
	Parent: Instance,
	Template: Model,
	Effects: Folder?,
	RootCFrame: CFrame,
	BackdropCFrame: CFrame,
	BackdropSize: Vector3,
	EyeColor: Color3?,
	Distortion: BasePart?,
	EyeLight: number?,
}

export type StagedCreep = typeof(setmetatable({} :: {
	Model: Model,
	Plates: { Plate },
	Eyes: { Eye },
	Backdrop: Part,
	Light: PointLight?,
	LightBrightness: number,
	Wisps: { ParticleEmitter },
	DistortionTemplate: BasePart?,
	Distortions: { BasePart },
	RootCFrame: CFrame,
	BackdropCFrame: CFrame,
	BackdropSize: Vector3,
	GlowCurve: Curve,
	Focus: Curve,
	Random: Random,
	Gaze: Vector2,
	GazeTarget: Vector2,
	NextSaccadeAt: number,
	BornAt: number,
	Opened: boolean,
	Tweens: { Tween },
	Destroyed: boolean,
	ModelGone: boolean,
	Connections: { [string]: RBXScriptConnection },
}, StagedCreep))

local function newCurve(value: number, now: number): Curve
	return { Origin = value, StartedAt = now, Segments = {} }
end

local function sample(curve: Curve, now: number): number
	local elapsed = now - curve.StartedAt
	local from = curve.Origin
	for _, segment in curve.Segments do
		if elapsed < segment.Duration then
			local alpha = if segment.Duration > 0 then math.clamp(elapsed / segment.Duration, 0, 1) else 1
			return from + (segment.Target - from) * segment.Ease(alpha)
		end
		elapsed -= segment.Duration
		from = segment.Target
	end
	return from
end

local function retarget(curve: Curve, now: number, segments: { Segment })
	curve.Origin = sample(curve, now)
	curve.StartedAt = now
	curve.Segments = segments
end

local function stripTags(instance: Instance)
	for _, tag in instance:GetTags() do
		instance:RemoveTag(tag)
	end
end

local function dominantAxis(direction: Vector3, exclude: Vector3?): Vector3
	local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
	local best, bestDot = Vector3.yAxis, -1
	for _, axis in axes do
		if exclude and axis == exclude then continue end
		local dot = math.abs(direction:Dot(axis))
		if dot > bestDot then
			best, bestDot = axis, dot
		end
	end
	return best
end

local function lensScale(lens: Lens, across: number, tall: number): Vector3
	local face = Vector3.one - lens.Normal - lens.Vertical
	return lens.Normal + lens.Vertical * tall + face * across
end

local function makeLens(part: BasePart, plateCFrame: CFrame): Lens
	local offset = plateCFrame:ToObjectSpace(part.CFrame)
	local normal = dominantAxis(offset:VectorToObjectSpace(-Vector3.zAxis))
	local vertical = dominantAxis(offset:VectorToObjectSpace(Vector3.yAxis), normal)

	for _, child in part:GetChildren() do
		if child:IsA("DataModelMesh") then
			child:Destroy()
		end
	end
	if part:IsA("Part") then
		part.Shape = Enum.PartType.Block
	end

	local mesh = Instance.new("SpecialMesh")
	mesh.Name = "Lens"
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part

	local lens: Lens = {
		Part = part,
		Mesh = mesh,
		Offset = offset,
		Normal = normal,
		Vertical = vertical,
		Diameter = math.max(part.Size:Dot(vertical), MINIMUM_DIRECTION),
		Shown = false,
	}
	mesh.Scale = lensScale(lens, 1, SLIT)
	part.LocalTransparencyModifier = 1
	return lens
end

local function show(lens: Lens, shown: boolean)
	if lens.Shown == shown then return end
	lens.Shown = shown
	lens.Part.LocalTransparencyModifier = if shown then 0 else 1
end

local function attachGlow(template: Instance?, lens: Lens, tint: Color3?): Glow?
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
	local diameter = lens.Diameter * GLOW_EYE_RATIO
	gui.Size = UDim2.fromScale(diameter, diameter)
	gui.Adornee = lens.Part
	gui.Enabled = false
	gui.StudsOffset = Vector3.new(0, 0, -GLOW_BEHIND_EYE)
	gui.Parent = lens.Part

	return {
		Gui = gui,
		Image = image,
		Size = gui.Size,
		Transparency = image.ImageTransparency,
		Brightness = gui.Brightness,
	}
end

local function findDistortion(options: Options): BasePart?
	local candidate: Instance? = options.Distortion
	if not candidate then
		local effects = ReplicatedStorage:FindFirstChild("Effects")
		candidate = effects and effects:FindFirstChild(DISTORTION_NAME)
	end
	if candidate and candidate:IsA("BasePart") then
		return candidate
	end
	return nil
end

local function buildPlates(model: Model, rootCFrame: CFrame, now: number, random: Random): ({ Plate }, BasePart?)
	local plates: { Plate } = {}
	local primary = model.PrimaryPart
	local rootPart: BasePart? = primary
	if not rootPart then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				rootPart = child
				break
			end
		end
	end
	if not rootPart then return plates, nil end

	local templateRoot = rootPart.CFrame
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") then continue end

		local templateCFrame = child.CFrame
		local eyes: { Eye } = {}
		for _, side in SIDES do
			local eyePart = child:FindFirstChild(EYE_PREFIX .. side, true)
			if not eyePart or not eyePart:IsA("BasePart") then continue end

			local pupilPart = child:FindFirstChild(PUPIL_PREFIX .. side, true)
			local pupil = if pupilPart and pupilPart:IsA("BasePart") then makeLens(pupilPart, templateCFrame) else nil
			table.insert(eyes, {
				Eye = makeLens(eyePart, templateCFrame),
				Pupil = pupil,
				Glow = nil,
				Lid = newCurve(0, now),
				Trait = TRAITS[side],
				Seed = random:NextNumber(0, 1000) + 0.41,
			})
		end

		local offset = templateRoot:ToObjectSpace(templateCFrame)
		table.insert(plates, {
			Part = child,
			Offset = offset,
			Rotation = (rootCFrame * offset).Rotation,
			Aimed = false,
			Seed = random:NextNumber(0, 1000) + 0.53,
			Eyes = eyes,
		})
	end
	return plates, rootPart
end

local function setUpConnections(self: StagedCreep)
	self.Connections = {}

	self.Connections.Destroying = self.Model.Destroying:Connect(function()
		self.ModelGone = true
		self:Destroy()
	end)
end

function StagedCreep.new(options: Options): StagedCreep
	local now = os.clock()
	local random = Random.new()
	local model = options.Template:Clone()
	model.Name = "StagedCreep"

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") or descendant:IsA("JointInstance") or descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end
	stripTags(model)
	for _, descendant in model:GetDescendants() do
		stripTags(descendant)
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end

	local plates, rootPart = buildPlates(model, options.RootCFrame, now, random)
	if #plates == 0 then
		warn("[StagedCreep] template has no parts; nothing will be staged")
	end

	local glowTemplate = options.Effects and options.Effects:FindFirstChild(GLOW_NAME)
	local eyes: { Eye } = {}
	local eyeColor: Color3? = options.EyeColor
	for _, plate in plates do
		for _, eye in plate.Eyes do
			if options.EyeColor then
				eye.Eye.Part.Color = options.EyeColor
			end
			eyeColor = eyeColor or eye.Eye.Part.Color
			eye.Glow = attachGlow(glowTemplate, eye.Eye, options.EyeColor)
			table.insert(eyes, eye)
		end
	end

	local backdrop = Instance.new("Part")
	backdrop.Name = "Backdrop"
	backdrop.Color = Color3.new(0, 0, 0)
	backdrop.Material = Enum.Material.Neon
	backdrop.Anchored = true
	backdrop.CanCollide = false
	backdrop.CanQuery = false
	backdrop.CanTouch = false
	backdrop.CastShadow = false
	backdrop.Size = options.BackdropSize
	backdrop.CFrame = options.BackdropCFrame
	backdrop.Transparency = 1
	backdrop.Parent = model

	local lightBrightness = math.max(options.EyeLight or LIGHT_BRIGHTNESS, 0)
	local light: PointLight? = nil
	if rootPart and lightBrightness > 0 then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "EyeSpill"
		pointLight.Color = eyeColor or Color3.fromRGB(190, 12, 12)
		pointLight.Range = LIGHT_RANGE
		pointLight.Brightness = 0
		pointLight.Shadows = false
		pointLight.Enabled = false
		pointLight.Parent = rootPart
		light = pointLight
	end

	local wisps: { ParticleEmitter } = {}
	local wispTemplate = options.Effects and options.Effects:FindFirstChild(WISP_NAME)
	if rootPart and wispTemplate and wispTemplate:IsA("Attachment") then
		for index, spot in WISP_SPOTS do
			local attachment = wispTemplate:Clone()
			local emitter = attachment:FindFirstChild(WISP_EMITTER_NAME)
			if not emitter or not emitter:IsA("ParticleEmitter") then
				attachment:Destroy()
				break
			end
			attachment.Name = `{WISP_NAME}{index}`
			attachment.CFrame = spot
			attachment.Parent = rootPart
			emitter.Rate = 0
			emitter.Enabled = false
			table.insert(wisps, emitter)
		end
	end

	local self = setmetatable({
		Model = model,
		Plates = plates,
		Eyes = eyes,
		Backdrop = backdrop,
		Light = light,
		LightBrightness = lightBrightness,
		Wisps = wisps,
		DistortionTemplate = findDistortion(options),
		Distortions = {},
		RootCFrame = options.RootCFrame,
		BackdropCFrame = options.BackdropCFrame,
		BackdropSize = options.BackdropSize,
		GlowCurve = newCurve(0, now),
		Focus = newCurve(PUPIL_DILATED, now),
		Random = random,
		Gaze = Vector2.zero,
		GazeTarget = Vector2.zero,
		NextSaccadeAt = now + random:NextNumber(SACCADE_MIN, SACCADE_MAX),
		BornAt = now,
		Opened = false,
		Tweens = {},
		Destroyed = false,
		ModelGone = false,
		Connections = {},
	}, StagedCreep)

	self:_render(now, 0, nil)
	model.Parent = options.Parent
	setUpConnections(self)

	return self
end

function StagedCreep:_updateGaze(now: number, deltaTime: number)
	if now >= self.NextSaccadeAt then
		local random = self.Random
		local angle = random:NextNumber(0, TAU)
		local reach = GAZE_RANGE * random:NextNumber() ^ GAZE_BIAS
		self.GazeTarget = Vector2.new(math.cos(angle), math.sin(angle)) * reach
		self.NextSaccadeAt = now + random:NextNumber(SACCADE_MIN, SACCADE_MAX)
	end
	self.Gaze = self.Gaze:Lerp(self.GazeTarget, MathService.ExpAlpha(GAZE_RATE, deltaTime))
end

function StagedCreep:_renderEye(eye: Eye, plateCFrame: CFrame, now: number, glowLevel: number, focus: number, pulse: number)
	local open = math.max(sample(eye.Lid, now), 0)
	local shown = open >= CLOSED
	local lens = eye.Eye

	lens.Part.CFrame = plateCFrame * lens.Offset
	lens.Mesh.Scale = lensScale(lens, 1, math.max(open, SLIT))
	show(lens, shown)

	local pupil = eye.Pupil
	if pupil then
		local tall = math.min(focus, lens.Diameter * open / pupil.Diameter)
		local room = math.max((lens.Diameter * open - pupil.Diameter * tall) / 2, 0)
		local elapsed = now - self.BornAt
		local tremorX = math.noise(elapsed * TREMOR_SPEED, eye.Seed) * TREMOR
		local tremorY = math.noise(eye.Seed, elapsed * TREMOR_SPEED) * TREMOR
		local driftX = math.clamp(self.Gaze.X + tremorX, -GAZE_RANGE, GAZE_RANGE)
		local driftY = math.clamp(self.Gaze.Y + tremorY, -math.min(room, GAZE_RANGE), math.min(room, GAZE_RANGE))

		pupil.Part.CFrame = plateCFrame * CFrame.new(driftX, driftY, 0) * pupil.Offset
		pupil.Mesh.Scale = lensScale(pupil, focus, math.max(tall, SLIT))
		show(pupil, shown and tall >= CLOSED)
	end

	local glow = eye.Glow
	if glow and glow.Gui.Parent then
		local strength = glowLevel * math.clamp(open, 0, 1) * pulse
		local visible = strength > GLOW_VISIBLE
		if glow.Gui.Enabled ~= visible then
			glow.Gui.Enabled = visible
		end
		if visible then
			local widen = math.max(open - 1, 0)
			local tall = (1 - GLOW_SQUASH) + GLOW_SQUASH * open
			local size = glow.Size
			glow.Gui.Size = UDim2.new(size.X.Scale, size.X.Offset, size.Y.Scale * tall, size.Y.Offset)
			glow.Gui.Brightness = glow.Brightness * (1 + GLOW_WIDEN_BRIGHTNESS * widen)
			glow.Image.ImageTransparency = 1 - (1 - glow.Transparency) * math.clamp(strength, 0, 1)
		end
	end
end

function StagedCreep:_render(now: number, deltaTime: number, cameraPosition: Vector3?)
	local glowLevel = math.clamp(sample(self.GlowCurve, now), 0, 1)
	local focus = sample(self.Focus, now)
	local elapsed = now - self.BornAt
	local pulse = 0.92 + 0.08 * math.sin(elapsed * TAU / GLOW_PULSE_PERIOD)

	local openSum, openCount = 0, 0
	for _, plate in self.Plates do
		local base = self.RootCFrame * plate.Offset
		local hover = Vector3.new(
			math.noise(elapsed * 0.23, plate.Seed) * HOVER,
			math.noise(elapsed * 0.19, plate.Seed + 17.3) * HOVER,
			0
		)
		local position = base.Position + plate.Rotation:VectorToWorldSpace(hover)

		if cameraPosition and (cameraPosition - position).Magnitude > MINIMUM_DIRECTION then
			local goal = Aim.Toward(position, cameraPosition)
			plate.Rotation = if plate.Aimed then Aim.Ease(plate.Rotation, goal, TURN_RATE, deltaTime) else goal
			plate.Aimed = true
		end

		local plateCFrame = plate.Rotation + position
		plate.Part.CFrame = plateCFrame
		for _, eye in plate.Eyes do
			self:_renderEye(eye, plateCFrame, now, glowLevel, focus, pulse)
			openSum += math.clamp(sample(eye.Lid, now), 0, 1)
			openCount += 1
		end
	end

	local light = self.Light
	if light then
		local open = if openCount > 0 then openSum / openCount else 0
		local brightness = self.LightBrightness * glowLevel * open * pulse
		local lit = brightness > 0.01
		if light.Enabled ~= lit then
			light.Enabled = lit
		end
		light.Brightness = brightness
	end

	local breath = 0.55 + 0.45 * math.sin(elapsed * TAU / WISP_BREATH_PERIOD)
	for _, wisp in self.Wisps do
		wisp.Rate = if wisp.Enabled then WISP_RATE * breath * glowLevel else 0
	end
end

function StagedCreep:Update(deltaTime: number, cameraPosition: Vector3)
	if self.Destroyed then return end

	local now = os.clock()
	local step = math.max(deltaTime, 0)
	self:_updateGaze(now, step)
	self:_render(now, step, cameraPosition)
end

function StagedCreep:_play(tween: Tween)
	table.insert(self.Tweens, tween)
	tween.Completed:Once(function()
		local index = table.find(self.Tweens, tween)
		if index then
			table.remove(self.Tweens, index)
		end
	end)
	tween:Play()
end

function StagedCreep:_setWisps(enabled: boolean)
	for _, wisp in self.Wisps do
		if wisp.Parent then
			wisp.Enabled = enabled
		end
	end
end

function StagedCreep:Open(duration: number?)
	if self.Destroyed then return end

	local now = os.clock()
	local openTime = if duration and duration > 0 then duration else DEFAULT_OPEN_TIME
	local latest = 0
	for _, eye in self.Eyes do
		local trait = eye.Trait
		local current = sample(eye.Lid, now)
		local segments: { Segment } = {}
		local total = 0
		if trait.Lead > 0 then
			table.insert(segments, { Duration = trait.Lead, Target = current, Ease = MathService.Eases.Linear })
			total += trait.Lead
		end
		if current < trait.Crack then
			table.insert(segments, { Duration = CRACK_TIME, Target = trait.Crack, Ease = MathService.Eases.OutQuad })
			table.insert(segments, { Duration = trait.Hesitate, Target = trait.Crack * 1.1, Ease = MathService.Eases.InOutSine })
			total += CRACK_TIME + trait.Hesitate
		end
		table.insert(segments, { Duration = openTime * trait.Pace, Target = 1, Ease = MathService.BackOut(trait.Overshoot) })
		total += openTime * trait.Pace
		latest = math.max(latest, total)
		retarget(eye.Lid, now, segments)
	end

	retarget(self.GlowCurve, now, {
		{ Duration = GLOW_RISE_TIME, Target = 1, Ease = MathService.Eases.OutSine },
	})
	local focus = sample(self.Focus, now)
	retarget(self.Focus, now, {
		{ Duration = latest * 0.8, Target = focus, Ease = MathService.Eases.Linear },
		{ Duration = PUPIL_NARROW_TIME, Target = PUPIL_NARROW, Ease = MathService.Eases.OutQuad },
		{ Duration = PUPIL_SETTLE_TIME, Target = 1, Ease = MathService.Eases.InOutSine },
	})

	self.Opened = true
	self:_setWisps(true)
	if self.Backdrop.Parent then
		self:_play(TweenService:Create(
			self.Backdrop,
			TweenInfo.new(BACKDROP_FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Transparency = 0 }
		))
	end
end

function StagedCreep:Blink()
	if self.Destroyed then return end

	local now = os.clock()
	for _, eye in self.Eyes do
		local current = sample(eye.Lid, now)
		if current < BLINK_MINIMUM then continue end

		local trait = eye.Trait
		local segments: { Segment } = {}
		if trait.Lag > 0 then
			table.insert(segments, { Duration = trait.Lag, Target = current, Ease = MathService.Eases.Linear })
		end
		table.insert(segments, { Duration = BLINK_CLOSE_TIME, Target = 0, Ease = MathService.Eases.InQuad })
		table.insert(segments, { Duration = BLINK_HOLD_TIME, Target = 0, Ease = MathService.Eases.Linear })
		table.insert(segments, { Duration = BLINK_OPEN_TIME * trait.Pace, Target = 1, Ease = MathService.BackOut(BLINK_OVERSHOOT) })
		retarget(eye.Lid, now, segments)
	end
end

function StagedCreep:Close(duration: number?)
	if self.Destroyed then return end

	local now = os.clock()
	local closeTime = if duration and duration > 0 then duration else DEFAULT_CLOSE_TIME
	for _, eye in self.Eyes do
		local trait = eye.Trait
		local current = sample(eye.Lid, now)
		local segments: { Segment } = {}
		if trait.Lag > 0 then
			table.insert(segments, { Duration = trait.Lag, Target = current, Ease = MathService.Eases.Linear })
		end
		table.insert(segments, { Duration = closeTime * trait.Pace, Target = 0, Ease = MathService.Eases.InQuad })
		retarget(eye.Lid, now, segments)
	end
	retarget(self.GlowCurve, now, {
		{ Duration = closeTime * 1.2, Target = 0, Ease = MathService.Eases.InQuad },
	})

	self.Opened = false
	self:_setWisps(false)
end

function StagedCreep:LaunchDistortion(towards: Vector3, speed: number): number
	local template = self.DistortionTemplate
	if self.Destroyed or not template or speed <= 0 then return 0 end

	local backdropCFrame = self.BackdropCFrame
	local backdropPosition = backdropCFrame.Position
	local axis = backdropCFrame.LookVector
	local plateRoot = self.RootCFrame.Position
	local start = backdropPosition + axis * (plateRoot - backdropPosition):Dot(axis)

	local reach = (towards - start):Dot(axis)
	local direction = axis
	if math.abs(reach) > MINIMUM_DIRECTION then
		if reach < 0 then
			direction = -axis
			reach = -reach
		end
	else
		local offset = towards - start
		if offset.Magnitude <= MINIMUM_DIRECTION then return 0 end
		direction = offset.Unit
		reach = offset.Magnitude
	end

	local arrival = reach / speed
	local finish = start + direction * (reach + speed * DISTORTION_OVERRUN)

	local effect = template:Clone()
	for _, descendant in effect:GetDescendants() do
		stripTags(descendant)
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	stripTags(effect)
	effect.Size = self.BackdropSize
	effect.CFrame = backdropCFrame.Rotation + start
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanQuery = false
	effect.CanTouch = false
	effect.CastShadow = false
	effect.Parent = self.Model
	table.insert(self.Distortions, effect)

	local tween = TweenService:Create(
		effect,
		TweenInfo.new(arrival + DISTORTION_OVERRUN, Enum.EasingStyle.Linear),
		{ CFrame = backdropCFrame.Rotation + finish }
	)
	tween.Completed:Once(function(state: Enum.PlaybackState)
		if state ~= Enum.PlaybackState.Completed then return end
		local index = table.find(self.Distortions, effect)
		if index then
			table.remove(self.Distortions, index)
		end
		effect:Destroy()
	end)
	self:_play(tween)

	return arrival
end

function StagedCreep:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}

	local tweens = table.clone(self.Tweens)
	table.clear(self.Tweens)
	TweenProxyService.CancelAll(tweens)

	local distortions = table.clone(self.Distortions)
	table.clear(self.Distortions)
	for _, effect in distortions do
		effect:Destroy()
	end

	if not self.ModelGone then
		self.Model:Destroy()
	end
end

return StagedCreep
