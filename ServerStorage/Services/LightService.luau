local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local FLOOR_1_LIGHT_TAG = "Floor1Light"

type LightState = {
	Enabled: boolean,
}

type RedLightState = {
	Color: Color3,
}

type RedState = {
	ExpiresAt: number,
	Lights: { [Light]: RedLightState },
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
local RedModels: { [Model]: RedState } = {}
local RED_COLOR = Color3.fromRGB(255, 0, 0)

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

--- Turns every light in one floor-light model red for `duration`, restoring its original color
--- afterward. A concurrent warning extends the existing red effect.
function LightService:WarnRed(model: Model, duration: number)
	if duration <= 0 then return end

	local existing = RedModels[model]
	if existing then
		existing.ExpiresAt = math.max(existing.ExpiresAt, os.clock() + duration)
		return
	end

	local state: RedState = {
		ExpiresAt = os.clock() + duration,
		Lights = {},
	}
	RedModels[model] = state
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			state.Lights[descendant] = {
				Color = descendant.Color,
			}
			descendant.Color = RED_COLOR
		end
	end

	task.spawn(function()
		while true do
			local remaining = state.ExpiresAt - os.clock()
			if remaining <= 0 then break end
			task.wait(remaining)
		end

		if RedModels[model] ~= state then return end
		for light, lightState in state.Lights do
			light.Color = lightState.Color
		end
		RedModels[model] = nil
	end)
end

return LightService
