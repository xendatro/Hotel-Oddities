local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaosWarningSoundService = {}

if not RunService:IsClient() then
	return ChaosWarningSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local TagService = require(ReplicatedStorage.Services.TagService)

local LIGHT_TAG = "Floor1Light"
local RED = Color3.fromRGB(255, 0, 0)
local SOUND_DISTANCE = 35
local SOURCE_SETTLE_TIME = 0.08
local REARM_TIME = 0.75
local CHECK_INTERVAL = 0.1

type LightState = {
	Model: Model,
	Connections: { RBXScriptConnection },
	LightConnections: { [Instance]: RBXScriptConnection },
	Lights: { [Instance]: boolean },
	SourceParts: { [BasePart]: boolean },
	Red: boolean,
}

local localPlayer = Players.LocalPlayer
local States: { [Model]: LightState } = {}
local RedModels: { [Model]: LightState } = {}
local warningActive = false
local clearStartedAt = 0
local evaluationVersion = 0
local timeSinceCheck = CHECK_INTERVAL

local function isRed(light: Instance): boolean
	return light:IsA("Light") and light.Color == RED
end

local function sourcePart(light: Instance): BasePart?
	return light:FindFirstAncestorWhichIsA("BasePart")
end

local function rebuildSourceParts(state: LightState)
	table.clear(state.SourceParts)
	for light in state.Lights do
		local part = sourcePart(light)
		if part then
			state.SourceParts[part] = true
		end
	end
end

local function hasSightline(root: BasePart, source: BasePart): boolean
	local character = localPlayer.Character
	if not character then return false end

	local origin = root.Position + Vector3.yAxis * 2
	local direction = source.Position - origin
	if direction.Magnitude <= 1e-3 then return true end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(origin, direction, params)
	if not result then return true end

	local model = source:FindFirstAncestorOfClass("Model")
	return result.Instance == source or (model ~= nil and result.Instance:IsDescendantOf(model))
end

local function nearestSource(root: BasePart, requireSightline: boolean): (BasePart?, number)
	local closest: BasePart? = nil
	local closestDistance = SOUND_DISTANCE
	local position = root.Position

	for model, state in RedModels do
		if model.Parent == nil then
			continue
		end

		for part in state.SourceParts do
			if part.Parent == nil then
				continue
			end

			local distance = (part.Position - position).Magnitude
			if distance < closestDistance
				and (not requireSightline or hasSightline(root, part))
			then
				closest = part
				closestDistance = distance
			end
		end
	end

	return closest, closestDistance
end

local function playWarning()
	AudioService:Play2DSound("ChaosIncoming", false, "SFX")
end

local function getRoot(): BasePart?
	local character = localPlayer.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return nil
	end

	return root
end

local function updateRed(state: LightState)
	local wasRed = state.Red
	local red = false
	for light in state.Lights do
		if light.Parent and isRed(light) then
			red = true
			break
		end
	end
	state.Red = red

	if red then
		RedModels[state.Model] = state
	elseif wasRed then
		RedModels[state.Model] = nil
	end
end

local function scheduleEvaluation()
	evaluationVersion += 1
	local version = evaluationVersion
	task.delay(SOURCE_SETTLE_TIME, function()
		if version ~= evaluationVersion then return end

		local root = getRoot()
		if not root then return end

		local source = nearestSource(root, true)
		if source then
			clearStartedAt = 0
			if not warningActive then
				warningActive = true
				playWarning()
			end
		end
	end)
end

local function registerLight(state: LightState, light: Instance)
	if not light:IsA("Light") or state.LightConnections[light] then return end

	state.Lights[light] = true
	local connection = light:GetPropertyChangedSignal("Color"):Connect(function()
		local wasRed = state.Red
		updateRed(state)
		if state.Red and not wasRed then
			scheduleEvaluation()
		end
	end)
	state.LightConnections[light] = connection

	local part = sourcePart(light)
	if part then
		state.SourceParts[part] = true
	end
end

local function unregisterLight(state: LightState, light: Instance)
	local connection = state.LightConnections[light]
	if not connection then return end

	connection:Disconnect()
	state.LightConnections[light] = nil
	state.Lights[light] = nil
	rebuildSourceParts(state)
	updateRed(state)
end

local function watchModel(model: Instance): LightState?
	if not model:IsA("Model") then return nil end

	local state: LightState = {
		Model = model,
		Connections = {},
		LightConnections = {},
		Lights = {},
		SourceParts = {},
		Red = false,
	}
	States[model] = state

	for _, descendant in model:GetDescendants() do
		registerLight(state, descendant)
	end

	table.insert(state.Connections, model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Light") then
			registerLight(state, descendant)
			local wasRed = state.Red
			updateRed(state)
			if state.Red and not wasRed then
				scheduleEvaluation()
			end
		end
	end))
	table.insert(state.Connections, model.DescendantRemoving:Connect(function(descendant)
		unregisterLight(state, descendant)
	end))

	local wasRed = state.Red
	updateRed(state)
	if state.Red and not wasRed then
		scheduleEvaluation()
	end

	return state
end

local function unwatchModel(model: Instance, state: LightState?)
	if not model:IsA("Model") then return end
	state = state or States[model]
	if not state then return end

	for _, connection in state.Connections do
		connection:Disconnect()
	end
	for _, connection in state.LightConnections do
		connection:Disconnect()
	end

	RedModels[model] = nil
	States[model] = nil
end

local function resetWarning()
	warningActive = false
	clearStartedAt = 0
end

TagService:Listen(LIGHT_TAG, watchModel, unwatchModel, workspace)

localPlayer.CharacterAdded:Connect(resetWarning)
localPlayer.CharacterRemoving:Connect(resetWarning)

RunService.Heartbeat:Connect(function(deltaTime)
	timeSinceCheck += deltaTime
	if timeSinceCheck < CHECK_INTERVAL then return end
	timeSinceCheck = 0

	local root = getRoot()
	if not root then
		resetWarning()
		return
	end

	local source = nearestSource(root, true)
	if source then
		clearStartedAt = 0
		return
	end

	if not warningActive then return end
	if clearStartedAt == 0 then
		clearStartedAt = os.clock()
	elseif os.clock() - clearStartedAt >= REARM_TIME then
		resetWarning()
	end
end)

return ChaosWarningSoundService
