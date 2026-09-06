local CollectionService = game:GetService("CollectionService")
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
	Position: Vector3,
	Baseline: { [Light]: Color3 },
	TagCount: number,
	Red: boolean,
	Engaged: boolean,
	Passed: boolean,
	AttributeConnection: RBXScriptConnection?,
	DescendantConnection: RBXScriptConnection?,
}

type Binding = {
	State: State,
}

type Mover = {
	Position: Vector3,
	Look: Vector3,
}

local States: { [Model]: State } = {}
local Warned: { [Model]: State } = {}
local Listeners: { (Model, boolean) -> () } = {}
local TimeSincePass = 0

local function announce(model: Model, red: boolean)
	for _, listener in Listeners do
		task.spawn(listener, model, red)
	end
end

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
		else
			state.Baseline[light] = nil
		end
	end
end

local function restore(state: State)
	for light, color in state.Baseline do
		if light.Parent then
			light.Color = color
		else
			state.Baseline[light] = nil
		end
	end
end

local function evaluate(state: State)
	local warned = state.Model:GetAttribute(RED_ATTRIBUTE) == true
	if not warned then
		state.Engaged = false
		state.Passed = false
	end

	local red = warned and not state.Passed
	Warned[state.Model] = if red then state else nil
	if red == state.Red then return end

	state.Red = red
	if red then
		applyRed(state)
	else
		restore(state)
	end
	announce(state.Model, red)
end

local function movers(): { Mover }
	local found = {}
	for _, instance in CollectionService:GetTagged(Config.ChaosTag) do
		if not instance:IsA("Model") or not instance:IsDescendantOf(workspace) then continue end

		local pivot = instance:GetPivot()
		table.insert(found, {
			Position = pivot.Position,
			Look = pivot.LookVector,
		})
	end
	return found
end

local function stepPasses()
	if not next(Warned) then return end

	local chasing = movers()
	if #chasing == 0 then return end

	for _, state in Warned do
		for _, mover in chasing do
			local offset = state.Position - mover.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if flat.Magnitude <= Config.PassEngageRange then
				state.Engaged = true
			end
			if state.Engaged and flat:Dot(mover.Look) <= 0 then
				state.Passed = true
				evaluate(state)
				break
			end
		end
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
		Position = model:GetPivot().Position,
		Baseline = {},
		TagCount = 1,
		Red = false,
		Engaged = false,
		Passed = false,
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
		announce(state.Model, false)
	end
	table.clear(state.Baseline)
	Warned[state.Model] = nil
	States[state.Model] = nil
end

function ChaosLightService:IsRed(model: Model): boolean
	local state = States[model]
	return state ~= nil and state.Red
end

function ChaosLightService:OnRedChanged(listener: (Model, boolean) -> ()): () -> ()
	table.insert(Listeners, listener)
	return function()
		local index = table.find(Listeners, listener)
		if index then
			table.remove(Listeners, index)
		end
	end
end

TagService:Listen(LIGHT_TAG, bind, unbind, workspace)

RunService.Heartbeat:Connect(function(deltaTime: number)
	TimeSincePass += deltaTime
	if TimeSincePass < Config.PassCheckInterval then return end

	TimeSincePass = 0
	stepPasses()
end)

return ChaosLightService
