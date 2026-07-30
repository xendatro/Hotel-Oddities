local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local FLOOR_1_LIGHT_TAG = "Floor1Light"

type LightState = {
	Enabled: boolean,
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

return LightService
