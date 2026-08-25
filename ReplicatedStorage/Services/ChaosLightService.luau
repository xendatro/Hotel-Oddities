local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.ChaosLightConfig)
local TagService = require(ReplicatedStorage.Services.TagService)

local ChaosLightService = {}

if not RunService:IsClient() then
	return ChaosLightService
end

local LIGHT_TAG = "Floor1Light"
local RED_ATTRIBUTE = "ChaosRed"

type State = {
	Model: Model,
	Baseline: { [Light]: Color3 },
	TagCount: number,
	Red: boolean,
	AttributeConnection: RBXScriptConnection?,
	DescendantConnection: RBXScriptConnection?,
}

type Binding = {
	State: State,
}

local States: { [Model]: State } = {}

local function captureLight(state: State, light: Light)
	if state.Baseline[light] ~= nil then return end
	state.Baseline[light] = light.Color
	if state.Red then
		light.Color = Config.RedColor
	end
end

local function applyRed(state: State)
	for light in state.Baseline do
		if light.Parent then
			light.Color = Config.RedColor
		end
	end
end

local function restore(state: State)
	for light, color in state.Baseline do
		if light.Parent then
			light.Color = color
		end
	end
end

local function evaluate(state: State)
	local red = state.Model:GetAttribute(RED_ATTRIBUTE) == true
	if red == state.Red then return end

	state.Red = red
	if red then
		applyRed(state)
	else
		restore(state)
	end
end

local function bind(instance: Instance): Binding?
	local model = if instance:IsA("Model")
		then instance
		else instance:FindFirstAncestorOfClass("Model")
	if not model then return nil end

	local existing = States[model]
	if existing then
		existing.TagCount += 1
		return { State = existing }
	end

	local state: State = {
		Model = model,
		Baseline = {},
		TagCount = 1,
		Red = false,
		AttributeConnection = nil,
		DescendantConnection = nil,
	}
	States[model] = state

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Light") then
			captureLight(state, descendant)
		end
	end

	state.AttributeConnection = model:GetAttributeChangedSignal(RED_ATTRIBUTE):Connect(function()
		evaluate(state)
	end)
	state.DescendantConnection = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Light") then
			captureLight(state, descendant)
		end
	end)

	evaluate(state)
	return { State = state }
end

local function unbind(_instance: Instance, binding: Binding?)
	if not binding then return end

	local state = binding.State
	state.TagCount -= 1
	if state.TagCount > 0 then return end

	if state.AttributeConnection then
		state.AttributeConnection:Disconnect()
		state.AttributeConnection = nil
	end
	if state.DescendantConnection then
		state.DescendantConnection:Disconnect()
		state.DescendantConnection = nil
	end
	if state.Red then
		state.Red = false
		restore(state)
	end
	States[state.Model] = nil
end

function ChaosLightService:IsRed(model: Model): boolean
	local state = States[model]
	return state ~= nil and state.Red
end

TagService:Listen(LIGHT_TAG, bind, unbind, workspace)

return ChaosLightService
