local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local FLOOR_1_LIGHT_TAG = "Floor1Light"

type LightState = {
	Enabled: boolean,
}

type FlickerLightState = {
	Brightness: number,
}

type FlickerState = {
	ExpiresAt: number,
	Lights: { [Light]: FlickerLightState },
}

type PartState = {
	Material: Enum.Material,
}

type ParticleState = {
	Enabled: boolean,
}

type DisabledState = {
	Claims: number,
	Lights: { [Light]: LightState },
	Parts: { [BasePart]: PartState },
	Particles: { [ParticleEmitter]: ParticleState },
}

export type LightClaim = {
	Models: { Model },
	Released: boolean,
}

local LightService = {}
local DisabledModels: { [Model]: DisabledState } = {}
local FlickeringModels: { [Model]: FlickerState } = {}
local Randomizer = Random.new()

local function disable(model: Model)
	local state = DisabledModels[model]
	if state then
		state.Claims += 1
		return
	end

	state = {
		Claims = 1,
		Lights = {},
		Parts = {},
		Particles = {},
	}
	DisabledModels[model] = state

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			state.Lights[descendant] = {
				Enabled = descendant.Enabled,
			}
			descendant.Enabled = false
		elseif descendant:IsA("BasePart") and descendant:HasTag(FLOOR_1_LIGHT_TAG) then
			state.Parts[descendant] = {
				Material = descendant.Material,
			}
			descendant.Material = Enum.Material.SmoothPlastic
		elseif descendant:IsA("ParticleEmitter") then
			state.Particles[descendant] = {
				Enabled = descendant.Enabled,
			}
			descendant.Enabled = false
		end
	end
end

local function restore(model: Model)
	local state = DisabledModels[model]
	if not state then return end

	state.Claims -= 1
	if state.Claims > 0 then return end

	for light, lightState in state.Lights do
		light.Enabled = lightState.Enabled
	end
	for part, partState in state.Parts do
		part.Material = partState.Material
	end
	for emitter, particleState in state.Particles do
		emitter.Enabled = particleState.Enabled
	end
	DisabledModels[model] = nil
end

--- Disables every tagged light model whose pivot is within `radius` studs of `position`.
--- Each returned claim must be released; overlapping claims keep a light off until all release it.
function LightService:DisableNear(position: Vector3, radius: number): LightClaim
	local claim: LightClaim = {
		Models = {},
		Released = false,
	}

	for _, instance in TagService:GetTaggedOfPredicate(FLOOR_1_LIGHT_TAG, function(tagged: Instance)
		return tagged:IsA("Model")
	end) do
		local model = instance :: Model
		if (model:GetPivot().Position - position).Magnitude <= radius then
			disable(model)
			table.insert(claim.Models, model)
		end
	end

	return claim
end

function LightService:Release(claim: LightClaim)
	if claim.Released then return end
	claim.Released = true

	for _, model in claim.Models do
		restore(model)
	end
end

--- Every tagged floor-light model. Callers that plan effects along a route use the model pivots to
--- decide which lights are affected.
function LightService:GetModels(): { Model }
	local models = {}
	for _, instance in TagService:GetTaggedOfPredicate(FLOOR_1_LIGHT_TAG, function(tagged: Instance)
		return tagged:IsA("Model")
	end) do
		table.insert(models, instance :: Model)
	end
	return models
end

local function setFlickerScale(state: FlickerState, scale: number)
	for light, lightState in state.Lights do
		light.Brightness = lightState.Brightness * scale
	end
end

local function transitionFlicker(state: FlickerState, fromScale: number, toScale: number, duration: number)
	local available = state.ExpiresAt - os.clock()
	if available <= 0 then return end
	duration = math.min(duration, available)

	local startedAt = os.clock()
	repeat
		task.wait()
		local alpha = math.min((os.clock() - startedAt) / duration, 1)
		setFlickerScale(state, fromScale + (toScale - fromScale) * alpha)
	until alpha >= 1
end

--- Gives one floor-light model irregular voltage-like dips instead of a fixed on/off pulse. It only
--- varies brightness, so an active DisableNear claim remains authoritative, and restores every
--- source's exact brightness when the effect ends. A concurrent call extends the existing flicker.
function LightService:Flicker(model: Model, duration: number, interval: number)
	local existing = FlickeringModels[model]
	if existing then
		existing.ExpiresAt = math.max(existing.ExpiresAt, os.clock() + duration)
		return
	end

	local state: FlickerState = {
		ExpiresAt = os.clock() + duration,
		Lights = {},
	}
	FlickeringModels[model] = state
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			state.Lights[descendant] = {
				Brightness = descendant.Brightness,
			}
		end
	end

	local scale = 1
	while os.clock() < state.ExpiresAt do
		local roll = Randomizer:NextNumber()
		local dipScale = if roll < 0.12
			then Randomizer:NextNumber(0.03, 0.15)
			elseif roll < 0.5
			then Randomizer:NextNumber(0.2, 0.55)
			else Randomizer:NextNumber(0.6, 0.9)

		transitionFlicker(state, scale, dipScale, Randomizer:NextNumber(0.025, 0.075))
		scale = dipScale
		task.wait(math.min(Randomizer:NextNumber(0.015, 0.065), math.max(state.ExpiresAt - os.clock(), 0)))

		local recoveryScale = Randomizer:NextNumber(0.92, 1.06)
		transitionFlicker(state, scale, recoveryScale, Randomizer:NextNumber(0.04, 0.14))
		scale = recoveryScale
		task.wait(math.min(Randomizer:NextNumber(interval * 0.3, interval * 1.6), math.max(state.ExpiresAt - os.clock(), 0)))
	end

	for light, lightState in state.Lights do
		light.Brightness = lightState.Brightness
	end
	FlickeringModels[model] = nil
end

return LightService
