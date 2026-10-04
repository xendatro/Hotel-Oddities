local CabinStage = {}
CabinStage.__index = CabinStage

local EPSILON = 1e-3
local LIT = 0.02

type Light = { Light: Light, Brightness: number }

export type Options = {
	Template: Model,
	Exit: Model,
	Threshold: BasePart,
	Parent: Instance,
	Name: string,
	LampName: string,
	DaylightName: string,
	GlowName: string,
	NeedleName: string,
	HubName: string,
	NeedleSweep: { number },
	LampOff: Color3,
}

export type CabinStage = typeof(setmetatable({} :: {
	Model: Model,
	Origin: CFrame,
	Lamp: BasePart?,
	LampColor: Color3,
	LampMaterial: Enum.Material,
	LampLights: { Light },
	LampOff: Color3,
	LampLevel: number,
	Daylight: BasePart?,
	DaylightLights: { Light },
	DaylightValue: number,
	DaylightLevel: number,
	GlowLights: { Light },
	GlowLevel: number,
	Needle: BasePart?,
	Hub: BasePart?,
	NeedleOffset: CFrame,
	NeedleSweep: { number },
	NeedleAlpha: number,
	Destroyed: boolean,
}, CabinStage))

local function findPart(model: Model, name: string): BasePart?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("BasePart") then found else nil
end

local function collectLights(part: BasePart?): { Light }
	local lights: { Light } = {}
	if not part then return lights end
	for _, descendant in part:GetDescendants() do
		if descendant:IsA("Light") then
			table.insert(lights, { Light = descendant, Brightness = descendant.Brightness })
		end
	end
	return lights
end

local function originOf(exit: Model, threshold: BasePart): CFrame
	local floor = threshold.Position + Vector3.yAxis * (threshold.Size.Y / 2)
	local look = exit:GetPivot().LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < EPSILON then
		flat = Vector3.xAxis
	end
	return CFrame.lookAt(floor, floor + flat.Unit)
end

function CabinStage.new(options: Options): CabinStage
	local model = options.Template:Clone()
	model.Name = options.Name
	model:PivotTo(options.Exit:GetPivot())

	local lamp = findPart(model, options.LampName)
	local daylight = findPart(model, options.DaylightName)
	local glow = findPart(model, options.GlowName)
	local needle = findPart(model, options.NeedleName)
	local hub = findPart(model, options.HubName)

	local self = setmetatable({
		Model = model,
		Origin = originOf(options.Exit, options.Threshold),
		Lamp = lamp,
		LampColor = if lamp then lamp.Color else Color3.new(1, 1, 1),
		LampMaterial = if lamp then lamp.Material else Enum.Material.Neon,
		LampLights = collectLights(lamp),
		LampOff = options.LampOff,
		LampLevel = -1,
		Daylight = daylight,
		DaylightLights = collectLights(daylight),
		DaylightValue = -1,
		DaylightLevel = -1,
		GlowLights = collectLights(glow),
		GlowLevel = -1,
		Needle = needle,
		Hub = hub,
		NeedleOffset = if needle and hub then hub.CFrame:ToObjectSpace(needle.CFrame) else CFrame.identity,
		NeedleSweep = options.NeedleSweep,
		NeedleAlpha = -1,
		Destroyed = false,
	}, CabinStage)

	self:SetLamp(0)
	self:SetDaylight(0, 0)
	self:SetGlow(0)
	self:SetNeedle(0)
	model.Parent = options.Parent
	return self
end

function CabinStage:ToWorld(point: Vector3): Vector3
	local origin = self.Origin
	return origin.Position + origin.RightVector * point.X + Vector3.yAxis * point.Y + origin.LookVector * point.Z
end

function CabinStage:Direction(direction: Vector3): Vector3
	local origin = self.Origin
	local world = origin.RightVector * direction.X + Vector3.yAxis * direction.Y + origin.LookVector * direction.Z
	return if world.Magnitude > EPSILON then world.Unit else origin.LookVector
end

function CabinStage:Frame(point: Vector3, facing: Vector3, height: number): CFrame
	local position = self:ToWorld(point) + Vector3.yAxis * height
	local direction = self:Direction(Vector3.new(facing.X, 0, facing.Z))
	return CFrame.lookAt(position, position + direction)
end

function CabinStage:Forward(position: Vector3): number
	return (position - self.Origin.Position):Dot(self.Origin.LookVector)
end

function CabinStage:Lateral(position: Vector3): number
	return (position - self.Origin.Position):Dot(self.Origin.RightVector)
end

function CabinStage:SetLamp(level: number)
	local value = math.clamp(level, 0, 1)
	if self.Destroyed or math.abs(value - self.LampLevel) < EPSILON then return end
	self.LampLevel = value

	local lamp = self.Lamp
	if lamp then
		lamp.Material = if value > LIT then self.LampMaterial else Enum.Material.SmoothPlastic
		lamp.Color = self.LampOff:Lerp(self.LampColor, value)
	end
	for _, entry in self.LampLights do
		entry.Light.Enabled = value > LIT
		entry.Light.Brightness = entry.Brightness * value
	end
end

function CabinStage:SetDaylight(level: number, opening: number)
	local value = math.clamp(level, 0, 1)
	local through = value * math.clamp(opening, 0, 1)
	if self.Destroyed then return end
	if math.abs(value - self.DaylightValue) < EPSILON and math.abs(through - self.DaylightLevel) < EPSILON then return end
	self.DaylightValue = value
	self.DaylightLevel = through

	local daylight = self.Daylight
	if daylight then
		daylight.Transparency = 1 - value
	end
	for _, entry in self.DaylightLights do
		entry.Light.Enabled = through > LIT
		entry.Light.Brightness = entry.Brightness * through
	end
end

function CabinStage:SetGlow(level: number)
	local value = math.clamp(level, 0, 1)
	if self.Destroyed or math.abs(value - self.GlowLevel) < EPSILON then return end
	self.GlowLevel = value
	for _, entry in self.GlowLights do
		entry.Light.Enabled = value > LIT
		entry.Light.Brightness = entry.Brightness * value
	end
end

function CabinStage:Burst(name: string)
	if self.Destroyed then return end
	local holder = self.Model:FindFirstChild(name, true)
	if not holder then return end
	for _, emitter in holder:GetDescendants() do
		if emitter:IsA("ParticleEmitter") then
			local count = emitter:GetAttribute("Burst")
			emitter:Emit(if type(count) == "number" then count else 10)
		end
	end
end

function CabinStage:SetEmitting(name: string, emitting: boolean)
	if self.Destroyed then return end
	local holder = self.Model:FindFirstChild(name, true)
	if not holder then return end
	for _, emitter in holder:GetDescendants() do
		if not emitter:IsA("ParticleEmitter") or emitter.Enabled == emitting then continue end
		emitter.Enabled = emitting
		local prewarm = emitter:GetAttribute("Prewarm")
		if emitting and type(prewarm) == "number" then
			emitter:Emit(prewarm)
		end
	end
end

function CabinStage:SetNeedle(alpha: number)
	local value = math.clamp(alpha, 0, 1)
	if self.Destroyed or math.abs(value - self.NeedleAlpha) < EPSILON then return end
	self.NeedleAlpha = value

	local needle, hub = self.Needle, self.Hub
	if not needle or not hub then return end
	local sweep = self.NeedleSweep
	local angle = sweep[1] + (sweep[2] - sweep[1]) * value
	needle.CFrame = hub.CFrame * CFrame.Angles(0, 0, -math.rad(angle)) * self.NeedleOffset
end

function CabinStage:Destroy()
	if self.Destroyed then return end
	self.Destroyed = true
	self.Model:Destroy()
end

return CabinStage
