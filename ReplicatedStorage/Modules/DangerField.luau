--- The danger field itself: a pure function from a position to how dangerous that spot is, 0..1.
---
--- Nothing in here reads the world or holds any state, which is the whole point. The server bakes it
--- over the tagged floors to decide where things spawn, and the debug client evaluates the identical
--- function to draw a heatmap, without either of them having to tell the other anything.
---
--- Two pieces multiplied together:
---
---  * A **gate** that opens with distance from the entrance. Zero inside the safe radius and one past
---    the ramp, so nothing the noise says can make the lobby dangerous.
---  * A **field** of Perlin noise, contrasted so it has distinct regions rather than gentle texture.
---
--- Multiplied rather than added. Adding a radial term would put a floor under danger everywhere far
--- from the door, so nowhere distant could ever be calm -- and a hotel where the far half is
--- uniformly bad is a hotel with one interesting decision in it. Multiplying means a cold pocket
--- five hundred studs out is genuinely cold, and finding one is worth something.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DangerConfig = require(ReplicatedStorage.Configs.DangerConfig)

type FieldSettings = DangerConfig.FieldSettings

local DangerField = {}

--- Fractional Brownian motion over `math.noise`. Roughly -0.5..0.5 before gain.
---
--- `math.noise` has no seed parameter and returns exactly zero on integer lattice points, so the seed
--- arrives as an offset on the sample coordinates and carries a fractional part -- otherwise a map
--- authored on round stud values would sample dead spots in a grid.
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

--- An S-curve about the midpoint. Values near 0.5 are pushed outwards, so the field resolves into
--- regions that are clearly hot or clearly cold instead of a continuum of "somewhat".
local function applyContrast(value: number, strength: number): number
	if strength <= 1 then return value end
	if value < 0.5 then
		return 0.5 * (2 * value) ^ strength
	end
	return 1 - 0.5 * (2 * (1 - value)) ^ strength
end

--- Which storey a point is on. Only used to decorrelate the noise between floors, so it does not
--- have to agree with anything the map calls a floor -- it only has to be stable and different.
function DangerField.GetFloorIndex(position: Vector3, settings: FieldSettings): number
	return math.round(position.Y / settings.FloorHeight)
end

--- The noise landscape at a point, 0..1, with no regard for the entrance. Exposed on its own because
--- the debug heatmap is much easier to read when the gate can be switched off and the raw field
--- inspected -- otherwise every seed looks identical near the door.
function DangerField.SampleField(position: Vector3, settings: FieldSettings): number
	local floorAxis = DangerField.GetFloorIndex(position, settings) * settings.FloorSeparation + settings.Seed
	local scale = math.max(settings.FeatureScale, 1)

	-- The seed shifts the sample point as well as the floor axis, so two seeds are two different
	-- landscapes rather than the same landscape read at a different height.
	local x = position.X / scale + settings.Seed * 0.7548
	local z = position.Z / scale + settings.Seed * 0.3691

	local raw = fbm(x, z, floorAxis, settings) * settings.NoiseGain + 0.5
	return applyContrast(math.clamp(raw, 0, 1), settings.Contrast)
end

--- How far the gate has opened at a point, 0..1. Zero anywhere inside the safe radius of the
--- entrance, one once the ramp is behind you.
function DangerField.SampleGate(position: Vector3, settings: FieldSettings): number
	local offset = position - settings.StartPosition
	local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return math.clamp((distance - settings.SafeRadius) / math.max(settings.RampLength, 1), 0, 1)
end

--- How dangerous a spot is, 0..1. This is the number every other system asks for.
function DangerField.Sample(position: Vector3, settings: FieldSettings): number
	local gate = DangerField.SampleGate(position, settings)
	if gate <= 0 then return 0 end
	return gate * DangerField.SampleField(position, settings)
end

export type SpawnPoint = {
	Position: Vector3, -- standing position on top of the floor
	Danger: number,
}

--- The bounding box of every tagged floor, as its longest horizontal side and its middle. Every
--- distance in `DangerConfig` is a fraction of that side, so a second hotel of a different size needs
--- no re-tuning by hand.
function DangerField.MeasureExtent(floors: { BasePart }): (number, Vector3)
	if #floors == 0 then return 1, Vector3.zero end

	local minimum = Vector3.new(math.huge, math.huge, math.huge)
	local maximum = -minimum

	for _, floor in floors do
		local size = floor.Size
		-- Corner to corner in world space, so a rotated corridor still contributes its true reach.
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

--- Candidate points laid across the top surfaces of `floors`, every `spacing` studs, each carrying
--- the danger at that spot. The server draws spawns from this; the debug heatmap draws itself from a
--- coarser one. Always produces at least the centre of each part, so a corridor narrower or shorter
--- than the spacing is still somewhere something can be.
function DangerField.BakePoints(floors: { BasePart }, spacing: number, settings: FieldSettings): { SpawnPoint }
	local points = {}

	for _, floor in floors do
		local halfLength = floor.Size.X / 2
		local halfWidth = floor.Size.Z / 2
		local top = floor.Size.Y / 2

		local lengthSteps = math.max(1, math.floor(floor.Size.X / spacing))
		local widthSteps = math.max(1, math.floor(floor.Size.Z / spacing))

		for lengthIndex = 1, lengthSteps do
			-- Cell centres rather than edges, so nothing lands exactly on the seam between two floors.
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

--- Resolves the fraction-of-the-map values in `DangerConfig` against a real map, producing the
--- settings table every sample call needs. `extent` is the longest horizontal side of the tagged
--- floors' bounding box.
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

	-- The debug UI pushes whole resolved settings rather than fractions, so a slider can move
	-- `FeatureScale` in studs and see the result without having to know the map's extent.
	if overrides then
		for key, value in overrides do
			(settings :: any)[key] = value
		end
	end

	return settings
end

return DangerField
