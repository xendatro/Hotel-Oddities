local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AudioService = require(ReplicatedStorage.Services.AudioService)

local LightSweep = {}
LightSweep.__index = LightSweep

local NEON_OFF_TAG = "NeonOff"
local SOUND_GROUP = "SFX"
local SOUND_SOURCE_NAME = "Player"
local EFFECT_CLASSES = { "ParticleEmitter", "Fire", "Smoke", "Sparkles" }

local DEFAULT_FLICKER_TIME = 0.4
local FIRST_INTERVAL = 0.9
local LAST_INTERVAL = 0.45
local PULSE_SPACING = 0.11
local MAX_STUTTERS = 5
local SURGE_LEVEL = 1.4
local SURGE_WHITE = 0.3
local WOBBLE_SPEED = 31
local WOBBLE_DEPTH = 0.18
local FLICKER_PITCH_SPREAD = 0.05
local OUT_PITCH_SPREAD = 0.08

local COOL_TIME = 0.3
local COOL_START = 0.45
local AMBER = Color3.fromRGB(255, 140, 60)
local AMBER_SHIFT = 0.35
local DEAD_SHADE = Color3.fromRGB(16, 14, 12)
local DEAD_TINT = 0.8
local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local DEFAULT_AMBIENT = Color3.fromRGB(3, 3, 5)

type Override = {
	Set: (self: any, instance: Instance, property: string, value: any) -> (),
	Release: (self: any, instance: Instance, property: string?) -> (),
}

type Pulse = {
	Lit: boolean,
	Length: number,
	Level: number,
}

type LightEntry = {
	Brightness: number,
	Enabled: boolean,
}

type LampState = "Live" | "Flickering" | "Cooling" | "Dead"

type Lamp = {
	Model: Model,
	Lights: { [Light]: LightEntry },
	Neon: { [BasePart]: Color3 },
	Effects: { [Instance]: boolean },
	Beams: { [Beam]: boolean },
	State: LampState,
	Pattern: { Pulse },
	Duration: number,
	StartedAt: number,
	DiedAt: number,
	Seed: number,
	Snuffed: boolean,
	FlickerSound: AudioPlayer?,
	Connections: { [string]: RBXScriptConnection },
}

type Pending = {
	Model: Model,
	At: number,
	Flicker: number,
}

export type Options = {
	Region: { Min: Vector3, Max: Vector3 },
	Tags: { string },
	Override: Override,
	Sounds: { Flicker: Instance?, Out: Instance? }?,
	Ambient: { Color3 }?,
}

export type LightSweep = typeof(setmetatable({} :: {
	Min: Vector3,
	Max: Vector3,
	Tags: { string },
	Override: Override,
	FlickerSound: Instance?,
	OutSound: Instance?,
	AmbientTarget: Color3,
	OutdoorTarget: Color3,
	AmbientBase: { Ambient: Color3, OutdoorAmbient: Color3 }?,
	Lamps: { [Model]: Lamp },
	Pending: { Pending },
	Values: { [Instance]: { [string]: any } },
	Sounds: { [AudioPlayer]: number },
	Gain: number,
	Random: Random,
	Destroyed: boolean,
	Connections: { [string]: RBXScriptConnection },
}, LightSweep))

local function isEffect(instance: Instance): boolean
	for _, className in EFFECT_CLASSES do
		if instance:IsA(className) then return true end
	end
	return false
end

local function dim(color: Color3, level: number): Color3
	if level > 1 then
		return color:Lerp(WHITE, SURGE_WHITE * math.clamp((level - 1) / (SURGE_LEVEL - 1), 0, 1))
	end
	return color:Lerp(BLACK, 1 - math.clamp(level, 0, 1))
end

local function buildPattern(random: Random, duration: number): { Pulse }
	local pulses: { Pulse } = {}
	if duration <= 0 then return pulses end

	local stutters = math.clamp(math.floor(duration / PULSE_SPACING), 1, MAX_STUTTERS)
	table.insert(pulses, { Lit = true, Length = random:NextNumber(0.1, 0.2), Level = 1 })
	for index = 1, stutters do
		local progress = index / stutters
		table.insert(pulses, {
			Lit = false,
			Length = random:NextNumber(0.03, 0.07) * (1 + progress * 1.6),
			Level = 0,
		})
		table.insert(pulses, {
			Lit = true,
			Length = random:NextNumber(0.04, 0.12) * (1.15 - progress * 0.6),
			Level = random:NextNumber(0.45, 0.95),
		})
	end
	table.insert(pulses, { Lit = false, Length = random:NextNumber(0.06, 0.1), Level = 0 })
	table.insert(pulses, { Lit = true, Length = random:NextNumber(0.05, 0.08), Level = SURGE_LEVEL })

	local total = 0
	for _, pulse in pulses do
		total += pulse.Length
	end
	local scale = duration / total
	for _, pulse in pulses do
		pulse.Length *= scale
	end
	return pulses
end

local function pulseAt(pattern: { Pulse }, elapsed: number): Pulse?
	local cursor = 0
	for _, pulse in pattern do
		cursor += pulse.Length
		if elapsed < cursor then return pulse end
	end
	return pattern[#pattern]
end

local function modelOf(instance: Instance): Model?
	if instance:IsA("Model") then return instance end
	return instance:FindFirstAncestorOfClass("Model")
end

local function soundPart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary and primary.Parent then return primary end

	local fallback: BasePart? = nil
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			local parent = descendant:FindFirstAncestorWhichIsA("BasePart")
			if parent then return parent end
		elseif not fallback and descendant:IsA("BasePart") then
			fallback = descendant
		end
	end
	return fallback
end

local function audioTemplate(instance: Instance?): AudioEmitter?
	if not instance or not instance:IsA("AudioEmitter") then return nil end
	local source = instance:FindFirstChild(SOUND_SOURCE_NAME)
	if not source or not source:IsA("AudioPlayer") then return nil end
	return instance
end

local function hasComponents(lamp: Lamp): boolean
	return next(lamp.Lights) ~= nil or next(lamp.Neon) ~= nil
end

local function isServerDark(lamp: Lamp): boolean
	for part in lamp.Neon do
		if part:HasTag(NEON_OFF_TAG) then return true end
	end
	return false
end

local function setUpConnections(self: LightSweep, lamp: Lamp, model: Model): { [string]: RBXScriptConnection }
	return {
		Added = model.DescendantAdded:Connect(function(descendant: Instance)
			self:_register(lamp, descendant)
		end),
		Removing = model.DescendantRemoving:Connect(function(descendant: Instance)
			self:_unregister(lamp, descendant)
		end),
		Ancestry = model.AncestryChanged:Connect(function()
			if not model:IsDescendantOf(workspace) then
				self:_untrack(model)
			end
		end),
	}
end

function LightSweep.new(options: Options): LightSweep
	assert(options.Override, "LightSweep needs a LocalOverride")

	local region = options.Region
	local sounds = options.Sounds or {}
	local ambient = options.Ambient or {}
	local ambientTarget = ambient[1] or DEFAULT_AMBIENT

	local self = setmetatable({
		Min = region.Min:Min(region.Max),
		Max = region.Min:Max(region.Max),
		Tags = table.clone(options.Tags or {}),
		Override = options.Override,
		FlickerSound = audioTemplate(sounds.Flicker),
		OutSound = audioTemplate(sounds.Out),
		AmbientTarget = ambientTarget,
		OutdoorTarget = ambient[2] or ambientTarget,
		AmbientBase = nil :: { Ambient: Color3, OutdoorAmbient: Color3 }?,
		Lamps = {},
		Pending = {},
		Values = {},
		Sounds = {},
		Gain = 1,
		Random = Random.new(),
		Destroyed = false,
		Connections = {},
	}, LightSweep)

	return self
end

function LightSweep:_set(instance: Instance, property: string, value: any)
	local values = self.Values[instance]
	if not values then
		values = {}
		self.Values[instance] = values
	end
	if values[property] == value then return end
	values[property] = value
	self.Override:Set(instance, property, value)
end

function LightSweep:_release(instance: Instance, property: string?)
	local values = self.Values[instance]
	if not values then return end

	if property then
		if values[property] == nil then return end
		values[property] = nil
		self.Override:Release(instance, property)
		if next(values) == nil then
			self.Values[instance] = nil
		end
		return
	end

	self.Values[instance] = nil
	for name in values do
		self.Override:Release(instance, name)
	end
end

function LightSweep:_contains(position: Vector3): boolean
	local minimum, maximum = self.Min, self.Max
	return position.X >= minimum.X and position.X <= maximum.X
		and position.Y >= minimum.Y and position.Y <= maximum.Y
		and position.Z >= minimum.Z and position.Z <= maximum.Z
end

function LightSweep:_register(lamp: Lamp, instance: Instance)
	if instance:IsA("Light") then
		if not lamp.Lights[instance] then
			lamp.Lights[instance] = { Brightness = instance.Brightness, Enabled = instance.Enabled }
		end
	elseif instance:IsA("BasePart") then
		if (instance.Material == Enum.Material.Neon or instance:HasTag(NEON_OFF_TAG)) and not lamp.Neon[instance] then
			lamp.Neon[instance] = instance.Color
		end
	elseif isEffect(instance) then
		if lamp.Effects[instance] == nil then
			lamp.Effects[instance] = (instance :: any).Enabled
		end
	elseif instance:IsA("Beam") then
		if lamp.Beams[instance] == nil then
			lamp.Beams[instance] = instance.Enabled
		end
	else
		return
	end

	if lamp.State == "Cooling" or lamp.State == "Dead" then
		self:_darken(lamp, lamp.State == "Dead")
	end
end

function LightSweep:_unregister(lamp: Lamp, instance: Instance)
	if instance:IsA("Light") then
		lamp.Lights[instance] = nil
	elseif instance:IsA("BasePart") then
		lamp.Neon[instance] = nil
	elseif instance:IsA("Beam") then
		lamp.Beams[instance] = nil
	else
		lamp.Effects[instance] = nil
	end
	self:_release(instance)
end

function LightSweep:_track(model: Model): Lamp
	local existing = self.Lamps[model]
	if existing then return existing end

	local lamp: Lamp = {
		Model = model,
		Lights = {},
		Neon = {},
		Effects = {},
		Beams = {},
		State = "Live",
		Pattern = {},
		Duration = 0,
		StartedAt = 0,
		DiedAt = 0,
		Seed = self.Random:NextNumber(0, 1000) + 0.29,
		Snuffed = false,
		FlickerSound = nil,
		Connections = {},
	}
	self.Lamps[model] = lamp

	for _, descendant in model:GetDescendants() do
		self:_register(lamp, descendant)
	end

	lamp.Connections = setUpConnections(self, lamp, model)

	return lamp
end

function LightSweep:_untrack(model: Model)
	local lamp = self.Lamps[model]
	if not lamp then return end
	self.Lamps[model] = nil

	for _, connection in lamp.Connections do
		connection:Disconnect()
	end
	lamp.Connections = {}

	local flickerSound = lamp.FlickerSound
	lamp.FlickerSound = nil
	if flickerSound then
		self:_stopSound(flickerSound)
	end
	for light in lamp.Lights do
		self:_release(light)
	end
	for part in lamp.Neon do
		self:_release(part)
	end
	for effect in lamp.Effects do
		self:_release(effect)
	end
	for beam in lamp.Beams do
		self:_release(beam)
	end
end

function LightSweep:Collect(): number
	if self.Destroyed then return 0 end

	for _, tag in self.Tags do
		for _, instance in CollectionService:GetTagged(tag) do
			local model = modelOf(instance)
			if model and not self.Lamps[model] and model:IsDescendantOf(workspace) and self:_contains(model:GetPivot().Position) then
				self:_track(model)
			end
		end
	end

	local count = 0
	for _, lamp in self.Lamps do
		if hasComponents(lamp) then
			count += 1
		end
	end
	return count
end

function LightSweep:Ordered(from: Vector3): { Model }
	local entries = {}
	for model, lamp in self.Lamps do
		if hasComponents(lamp) then
			table.insert(entries, { Model = model, Distance = (model:GetPivot().Position - from).Magnitude })
		end
	end
	table.sort(entries, function(first, second)
		return first.Distance > second.Distance
	end)

	local ordered = table.create(#entries)
	for index, entry in entries do
		ordered[index] = entry.Model
	end
	return ordered
end

function LightSweep:_stopSound(player: AudioPlayer)
	self.Sounds[player] = nil
	if player.Parent then
		pcall(AudioService.StopSound, AudioService, player)
	end
end

function LightSweep:_cue(lamp: Lamp, template: AudioEmitter?, spread: number): AudioPlayer?
	if not template then return nil end
	local parent = soundPart(lamp.Model)
	if not parent then return nil end

	local source = template:FindFirstChild(SOUND_SOURCE_NAME)
	if not source or not source:IsA("AudioPlayer") then return nil end
	local settings = {
		PlaybackSpeed = source.PlaybackSpeed * (1 + self.Random:NextNumber(-spread, spread)),
	}
	local played, player = pcall(AudioService.Play3DSound, AudioService, template, parent, false, SOUND_GROUP, settings)
	if not played or not player then return nil end

	self.Sounds[player] = player.Volume
	player.Volume *= self.Gain
	player.Ended:Once(function()
		self.Sounds[player] = nil
	end)
	return player
end

function LightSweep:_snuff(lamp: Lamp)
	if lamp.Snuffed then return end
	lamp.Snuffed = true

	for effect in lamp.Effects do
		if not effect.Parent then continue end
		self:_set(effect, "Enabled", false)
		if effect:IsA("ParticleEmitter") then
			effect:Clear()
		end
	end
end

function LightSweep:_light(lamp: Lamp, level: number)
	for light, entry in lamp.Lights do
		if not light.Parent then continue end
		self:_set(light, "Enabled", entry.Enabled)
		self:_set(light, "Brightness", entry.Brightness * level)
	end
	for part, color in lamp.Neon do
		if not part.Parent then continue end
		self:_set(part, "Material", Enum.Material.Neon)
		self:_set(part, "Color", dim(color, level))
	end
	for beam, enabled in lamp.Beams do
		if beam.Parent then
			self:_set(beam, "Enabled", enabled)
		end
	end
end

function LightSweep:_darken(lamp: Lamp, buried: boolean)
	for light in lamp.Lights do
		if light.Parent then
			self:_set(light, "Enabled", false)
		end
	end
	for beam in lamp.Beams do
		if beam.Parent then
			self:_set(beam, "Enabled", false)
		end
	end
	if buried or lamp.State == "Flickering" then
		for part, color in lamp.Neon do
			if not part.Parent then continue end
			self:_set(part, "Material", Enum.Material.SmoothPlastic)
			self:_set(part, "Color", color:Lerp(DEAD_SHADE, DEAD_TINT))
		end
	end
	self:_snuff(lamp)
end

function LightSweep:_cool(lamp: Lamp, alpha: number)
	local fade = (1 - alpha) * (1 - alpha)
	for part, color in lamp.Neon do
		if not part.Parent then continue end
		self:_set(part, "Material", Enum.Material.Neon)
		self:_set(part, "Color", color:Lerp(AMBER, AMBER_SHIFT):Lerp(BLACK, 1 - COOL_START * fade))
	end
end

function LightSweep:_die(lamp: Lamp, diedAt: number)
	lamp.State = "Cooling"
	lamp.DiedAt = diedAt

	self:_darken(lamp, false)
	for light in lamp.Lights do
		self:_release(light, "Brightness")
	end
	self:_cool(lamp, 0)

	local flickerSound = lamp.FlickerSound
	lamp.FlickerSound = nil
	if flickerSound then
		self:_stopSound(flickerSound)
	end
	self:_cue(lamp, self.OutSound, OUT_PITCH_SPREAD)
end

function LightSweep:_bury(lamp: Lamp)
	lamp.State = "Dead"
	self:_darken(lamp, true)
end

function LightSweep:_flicker(lamp: Lamp, elapsed: number)
	local pulse = pulseAt(lamp.Pattern, elapsed)
	if not pulse or not pulse.Lit then
		self:_darken(lamp, false)
		return
	end

	local wobble = 1 - WOBBLE_DEPTH * (0.5 + 0.5 * math.clamp(math.noise(elapsed * WOBBLE_SPEED, lamp.Seed), -1, 1))
	self:_light(lamp, pulse.Level * wobble)
end

function LightSweep:_kill(model: Model, flickerTime: number?, startedAt: number): number
	if self.Destroyed then return 0 end

	local lamp = self:_track(model)
	if lamp.State ~= "Live" then return 0 end

	local serverDark = isServerDark(lamp)
	for light, entry in lamp.Lights do
		entry.Enabled = light.Enabled or serverDark
		entry.Brightness = light.Brightness
	end
	for part in lamp.Neon do
		lamp.Neon[part] = part.Color
	end
	for beam in lamp.Beams do
		lamp.Beams[beam] = beam.Enabled
	end

	local duration = math.max(flickerTime or DEFAULT_FLICKER_TIME, 0)
	lamp.Duration = duration
	lamp.StartedAt = startedAt
	lamp.Snuffed = false
	lamp.Pattern = buildPattern(Random.new(math.floor(lamp.Seed * 1000)), duration)
	lamp.State = "Flickering"

	local elapsed = os.clock() - startedAt
	if elapsed >= duration then
		self:_die(lamp, startedAt + duration)
	else
		lamp.FlickerSound = self:_cue(lamp, self.FlickerSound, FLICKER_PITCH_SPREAD)
		self:_flicker(lamp, math.max(elapsed, 0))
	end
	self:_ensureStepping()
	return math.max(duration - elapsed, 0)
end

function LightSweep:Kill(model: Model, flickerTime: number?): number
	return self:_kill(model, flickerTime, os.clock())
end

function LightSweep:KillAll(order: { Model }, schedule: { number }?, flickerTime: number?): number
	if self.Destroyed then return 0 end

	local now = os.clock()
	local flicker = math.max(flickerTime or DEFAULT_FLICKER_TIME, 0)
	local count = #order
	local delay = 0
	local finish = 0
	for index, model in order do
		if index > 1 then
			local progress = if count > 2 then (index - 2) / (count - 2) else 1
			delay += FIRST_INTERVAL + (LAST_INTERVAL - FIRST_INTERVAL) * progress
		end
		local at = if schedule and schedule[index] then schedule[index] else delay
		delay = at
		finish = math.max(finish, at + flicker)

		if at <= 0 then
			self:_kill(model, flicker, now)
		else
			table.insert(self.Pending, { Model = model, At = now + at, Flicker = flicker })
		end
	end
	self:_ensureStepping()
	return finish
end

function LightSweep:SetAmbient(alpha: number)
	if self.Destroyed then return end

	local base = self.AmbientBase
	if not base then
		base = { Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient }
		self.AmbientBase = base
	end

	local amount = math.clamp(alpha, 0, 1)
	self:_set(Lighting, "Ambient", base.Ambient:Lerp(self.AmbientTarget, amount))
	self:_set(Lighting, "OutdoorAmbient", base.OutdoorAmbient:Lerp(self.OutdoorTarget, amount))
end

function LightSweep:SetGain(gain: number)
	self.Gain = math.clamp(gain, 0, 1)
	for player, base in self.Sounds do
		if player.Parent then
			player.Volume = base * self.Gain
		end
	end
end

function LightSweep:_step()
	local now = os.clock()

	for index = #self.Pending, 1, -1 do
		local entry = self.Pending[index]
		if now >= entry.At then
			table.remove(self.Pending, index)
			if entry.Model:IsDescendantOf(workspace) then
				self:_kill(entry.Model, entry.Flicker, entry.At)
			end
		end
	end

	local active = false
	for _, lamp in self.Lamps do
		if lamp.State == "Flickering" then
			local elapsed = now - lamp.StartedAt
			if elapsed >= lamp.Duration then
				self:_die(lamp, lamp.StartedAt + lamp.Duration)
			else
				self:_flicker(lamp, elapsed)
			end
			active = true
		elseif lamp.State == "Cooling" then
			local elapsed = now - lamp.DiedAt
			if elapsed >= COOL_TIME then
				self:_bury(lamp)
			else
				self:_cool(lamp, elapsed / COOL_TIME)
				active = true
			end
		end
	end

	if not active and #self.Pending == 0 then
		self:_stopStepping()
	end
end

function LightSweep:_ensureStepping()
	if self.Connections.Step or self.Destroyed then return end
	self.Connections.Step = RunService.RenderStepped:Connect(function()
		self:_step()
	end)
end

function LightSweep:_stopStepping()
	local connection = self.Connections.Step
	if connection then
		connection:Disconnect()
		self.Connections.Step = nil
	end
end

function LightSweep:Restore()
	self:_stopStepping()
	table.clear(self.Pending)

	for _, lamp in self.Lamps do
		lamp.State = "Live"
		lamp.Pattern = {}
		lamp.Snuffed = false
		lamp.FlickerSound = nil
	end

	local sounds = {}
	for player in self.Sounds do
		table.insert(sounds, player)
	end
	for _, player in sounds do
		self:_stopSound(player)
	end

	local values = self.Values
	self.Values = {}
	for instance, properties in values do
		for property in properties do
			self.Override:Release(instance, property)
		end
	end
	self.AmbientBase = nil

	for _, lamp in self.Lamps do
		if not isServerDark(lamp) then continue end

		for light in lamp.Lights do
			if light.Parent then
				light.Enabled = false
			end
		end
		for part in lamp.Neon do
			if part.Parent then
				part.Material = Enum.Material.SmoothPlastic
			end
		end
		for effect in lamp.Effects do
			if effect.Parent and effect:IsA("ParticleEmitter") then
				effect.Enabled = false
			end
		end
	end
end

function LightSweep:Destroy()
	if self.Destroyed then return end

	self:Restore()
	self.Destroyed = true

	for _, lamp in self.Lamps do
		for _, connection in lamp.Connections do
			connection:Disconnect()
		end
		lamp.Connections = {}
	end
	table.clear(self.Lamps)

	for _, connection in self.Connections do
		connection:Disconnect()
	end
	self.Connections = {}
end

return LightSweep
