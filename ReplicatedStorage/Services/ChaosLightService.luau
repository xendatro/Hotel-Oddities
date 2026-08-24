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
local CHAOS_TAG = "Chaos"
local RED_ATTRIBUTE = "ChaosRed"

type State = {
	Model: Model,
	Baseline: { [Light]: Color3 },
	TagCount: number,
	Red: boolean,
	ServerReleased: boolean,
	ReleasedAt: number?,
	Near: boolean,
	BestDistance: number,
	ActiveIndex: number?,
	AttributeConnection: RBXScriptConnection?,
	DescendantConnection: RBXScriptConnection?,
}

type Binding = {
	State: State,
}

local States: { [Model]: State } = {}
local ActiveStates: { State } = {}
local heartbeatConnection: RBXScriptConnection? = nil

local function horizontalDistance(first: Vector3, second: Vector3): number
	local offset = first - second
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

local function applyRed(state: State)
	for light in state.Baseline do
		if light.Parent then
			light.Color = Config.RedColor
		end
	end
end

local function captureLight(state: State, light: Light)
	if state.Baseline[light] then return end
	state.Baseline[light] = light.Color
	if state.Red then
		light.Color = Config.RedColor
	end
end

local function restore(state: State)
	for light, color in state.Baseline do
		if light.Parent then
			light.Color = color
		end
	end
end

local function stopLoopIfIdle()
	if #ActiveStates == 0 and heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function removeActive(state: State)
	local index = state.ActiveIndex
	if not index then return end

	local last = ActiveStates[#ActiveStates]
	ActiveStates[index] = last
	ActiveStates[#ActiveStates] = nil
	state.ActiveIndex = nil
	if last ~= state then
		last.ActiveIndex = index
	end
	stopLoopIfIdle()
end

local function deactivate(state: State)
	if not state.Red then return end
	state.Red = false
	restore(state)
	removeActive(state)
end

local function update(now: number)
	for index = #ActiveStates, 1, -1 do
		local state = ActiveStates[index]
		if state.Model.Parent == nil then
			deactivate(state)
			continue
		end

		local lightPosition = state.Model:GetPivot().Position
		local nearestDistance = math.huge
		for _, instance in CollectionService:GetTagged(CHAOS_TAG) do
			if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
				nearestDistance = math.min(
					nearestDistance,
					horizontalDistance(instance:GetPivot().Position, lightPosition)
				)
			end
		end

		if nearestDistance <= Config.TrackDistance then
			if not state.Near then
				state.Near = true
				state.BestDistance = nearestDistance
			elseif nearestDistance < state.BestDistance then
				state.BestDistance = nearestDistance
			elseif nearestDistance > state.BestDistance + Config.PassRecession then
				deactivate(state)
			end
		elseif state.ServerReleased
			and state.ReleasedAt
			and now - state.ReleasedAt >= Config.ServerReleaseGrace
		then
			deactivate(state)
		end
	end
end

local function startLoop()
	if heartbeatConnection then return end
	heartbeatConnection = RunService.Heartbeat:Connect(update)
end

local function activate(state: State)
	if state.Red then
		state.ServerReleased = false
		state.ReleasedAt = nil
		return
	end

	state.Red = true
	state.ServerReleased = false
	state.ReleasedAt = nil
	state.Near = false
	state.BestDistance = math.huge
	applyRed(state)

	if not state.ActiveIndex then
		table.insert(ActiveStates, state)
		state.ActiveIndex = #ActiveStates
	end
	startLoop()
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
		ServerReleased = true,
		ReleasedAt = nil,
		Near = false,
		BestDistance = math.huge,
		ActiveIndex = nil,
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
		if model:GetAttribute(RED_ATTRIBUTE) == true then
			activate(state)
		else
			state.ServerReleased = true
			state.ReleasedAt = os.clock()
		end
	end)
	state.DescendantConnection = model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Light") then
			captureLight(state, descendant)
		end
	end)

	if model:GetAttribute(RED_ATTRIBUTE) == true then
		activate(state)
	end

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
	deactivate(state)
	States[state.Model] = nil
end

function ChaosLightService:IsRed(model: Model): boolean
	local state = States[model]
	return state ~= nil and state.Red
end

TagService:Listen(LIGHT_TAG, bind, unbind, workspace)

return ChaosLightService
