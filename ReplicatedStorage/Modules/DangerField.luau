local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)

type FieldSettings = DangerConfig.FieldSettings

local DangerField = {}

local function fbm(x: number, z: number, floorAxis: number, settings: FieldSettings): number
	local total, amplitude, frequency, normalizer = 0, 1, 1, 0

	for _ = 1, settings.Octaves do
		total += math.noise(x * frequency, z * frequency, floorAxis) * amplitude
		normalizer += amplitude
		amplitude *= settings.Persistence
		frequency *= 2
	end

	return total / normalizer
end

local function applyContrast(value: number, strength: number): number
	if strength <= 1 then return value end
	if value < 0.5 then
		return 0.5 * (2 * value) ^ strength
	end
	return 1 - 0.5 * (2 * (1 - value)) ^ strength
end

function DangerField.GetFloorIndex(position: Vector3, settings: FieldSettings): number
	return math.round(position.Y / settings.FloorHeight)
end

function DangerField.SampleField(position: Vector3, settings: FieldSettings): number
	local floorAxis = DangerField.GetFloorIndex(position, settings) * settings.FloorSeparation + settings.Seed
	local scale = math.max(settings.FeatureScale, 1)

	local x = position.X / scale + settings.Seed * 0.7548
	local z = position.Z / scale + settings.Seed * 0.3691

	local raw = fbm(x, z, floorAxis, settings) * settings.NoiseGain + 0.5
	return applyContrast(math.clamp(raw, 0, 1), settings.Contrast)
end

function DangerField.SampleGate(position: Vector3, settings: FieldSettings): number
	local offset = position - settings.StartPosition
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return math.clamp((distance - settings.SafeRadius) / math.max(settings.RampLength, 1), 0, 1)
end

function DangerField.Sample(position: Vector3, settings: FieldSettings): number
	local gate = DangerField.SampleGate(position, settings)
	if gate <= 0 then return 0 end
	return gate * DangerField.SampleField(position, settings)
end

export type SpawnPoint = {
	Position: Vector3,
	Danger: number,
}

function DangerField.MeasureExtent(floors: { BasePart }): (number, Vector3)
	if #floors == 0 then return 1, Vector3.zero end

	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum

	for _, floor in floors do
		local size = floor.Size
		for _, corner in {
			Vector3.new(size.X, size.Y, size.Z) / 2,
			Vector3.new(-size.X, size.Y, size.Z) / 2,
			Vector3.new(size.X, size.Y, -size.Z) / 2,
			Vector3.new(-size.X, size.Y, -size.Z) / 2,
		} do
			local world = floor.CFrame * corner
			minimum = minimum:Min(world)
			maximum = maximum:Max(world)
		end
	end

	local span = maximum - minimum
	return math.max(span.X, span.Z, 1), (minimum + maximum) / 2
end

function DangerField.BakePoints(floors: { BasePart }, spacing: number, settings: FieldSettings): { SpawnPoint }
	local points = {}

	for _, floor in floors do
		local halfLength = floor.Size.X / 2
		local halfWidth = floor.Size.Z / 2
		local top = floor.Size.Y / 2

		local lengthSteps = math.max(1, math.floor(floor.Size.X / spacing))
		local widthSteps = math.max(1, math.floor(floor.Size.Z / spacing))

		for lengthIndex = 1, lengthSteps do
			local along = -halfLength + ((lengthIndex - 0.5) / lengthSteps) * floor.Size.X

			for widthIndex = 1, widthSteps do
				local across = -halfWidth + ((widthIndex - 0.5) / widthSteps) * floor.Size.Z
				local position = floor.CFrame * Vector3.new(along, top, across)
				table.insert(points, {
					Position = position,
					Danger = DangerField.Sample(position, settings),
				})
			end
		end
	end

	return points
end

function DangerField.BuildSettings(startPosition: Vector3, extent: number, overrides: { [string]: any }?): FieldSettings
	local config = DangerConfig
	local settings: FieldSettings = {
		Seed = config.Seed,
		FeatureScale = extent * config.FeatureScaleFraction,
		Octaves = config.Octaves,
		Persistence = config.Persistence,
		NoiseGain = config.NoiseGain,
		Contrast = config.Contrast,
		FloorHeight = config.FloorHeight,
		FloorSeparation = config.FloorSeparation,
		StartPosition = startPosition,
		SafeRadius = extent * config.SafeRadiusFraction,
		RampLength = extent * config.RampLengthFraction,
	}

	if overrides then
		for key, value in overrides do
			(settings :: any)[key] = value
		end
	end

	return settings
end

return DangerField
