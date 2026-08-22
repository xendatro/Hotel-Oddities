local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ChaosWarningSoundService = {}

if not RunService:IsClient() then
	return ChaosWarningSoundService
end

local AudioService = require(ReplicatedStorage.Services.AudioService)
local Hallways = require(ReplicatedStorage.Modules.Hallways)
local TagService = require(ReplicatedStorage.Services.TagService)

local LIGHT_TAG = "Floor1Light"
local RED = Color3.fromRGB(255, 0, 0)
local SOUND_DISTANCE = 35
local AMBIENCE_FOLDER = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("ChaosHallwayAmbience")
local AMBIENCE_BUS = "SFX"
local AMBIENCE_FULL_DISTANCE = 8
local AMBIENCE_SILENT_DISTANCE = SOUND_DISTANCE
local AMBIENCE_FADE_TIME = 1
local SPAN_EPSILON = 0.75
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

type AmbienceSound = {
	Player: AudioPlayer,
	BaseVolume: number,
}

local localPlayer = Players.LocalPlayer
local States: { [Model]: LightState } = {}
local RedModels: { [Model]: LightState } = {}
local warningActive = false
local clearStartedAt = 0
local evaluationVersion = 0
local timeSinceCheck = CHECK_INTERVAL
local TimeSinceAmbienceUpdate = CHECK_INTERVAL
local AmbienceAnchor = Instance.new("Part")
AmbienceAnchor.Name = "ChaosHallwayAmbienceAnchor"
AmbienceAnchor.Anchored = true
AmbienceAnchor.CanCollide = false
AmbienceAnchor.CanTouch = false
AmbienceAnchor.CanQuery = false
AmbienceAnchor.Transparency = 1
AmbienceAnchor.Size = Vector3.one
AmbienceAnchor.Parent = workspace

local AmbienceSources = {}
for _, child in AMBIENCE_FOLDER:GetChildren() do
	if child:IsA("AudioEmitter") then
		table.insert(AmbienceSources, child)
	end
end
local AmbienceSounds: { AmbienceSound } = {}
local AmbienceVolume = 0

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

local function sameSpan(first: Hallways.StraightSpan, second: Hallways.StraightSpan): boolean
	local sameDirection = (first.Start - second.Start).Magnitude <= SPAN_EPSILON
		and (first.Finish - second.Finish).Magnitude <= SPAN_EPSILON
	local oppositeDirection = (first.Start - second.Finish).Magnitude <= SPAN_EPSILON
		and (first.Finish - second.Start).Magnitude <= SPAN_EPSILON
	return sameDirection or oppositeDirection
end

local function closestPointOnSpan(span: Hallways.StraightSpan, position: Vector3): Vector3
	local along = math.clamp((position - span.Start):Dot(span.Axis), 0, span.Length)
	return span.Start + span.Axis * along
end

local function nearestChaosHallway(position: Vector3): (Hallways.StraightSpan?, number)
	local nearestSpan: Hallways.StraightSpan? = nil
	local nearestDistance = math.huge

	for _, state in RedModels do
		if state.Model.Parent == nil then continue end

		for source in state.SourceParts do
			if source.Parent == nil then continue end

			local span = if Hallways.At(source.Position)
				then Hallways.StraightSpanAt(source.Position)
				else nil
			if not span then continue end

			local closest = closestPointOnSpan(span, position)
			local offset = closest - position
			local distance = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if distance < nearestDistance then
				nearestSpan = span
				nearestDistance = distance
			end
		end
	end

	return nearestSpan, nearestDistance
end

local function ensureAmbienceSounds()
	if #AmbienceSounds > 0 then return end

	for _, source in AmbienceSources do
		local player = AudioService:Play3DSound(source, AmbienceAnchor, true, AMBIENCE_BUS)
		table.insert(AmbienceSounds, {
			Player = player,
			BaseVolume = source.Player.Volume,
		})
		player.Volume = 0
	end
end

local function stopAmbienceSounds()
	for _, sound in AmbienceSounds do
		if sound.Player.Parent then
			AudioService:StopSound(sound.Player)
		end
	end
	table.clear(AmbienceSounds)
end

local function updateAmbience(deltaTime: number)
	local root = getRoot()
	local span: Hallways.StraightSpan? = nil
	local distance = math.huge
	if root then
		span, distance = nearestChaosHallway(root.Position)
	end
	local targetVolume = math.clamp(
		(AMBIENCE_SILENT_DISTANCE - distance)
			/ (AMBIENCE_SILENT_DISTANCE - AMBIENCE_FULL_DISTANCE),
		0,
		1
	)

	if span and root and targetVolume > 0 then
		local playerSpan = Hallways.StraightSpanAt(root.Position)
		local anchorPosition = closestPointOnSpan(span, root.Position)
		if playerSpan and sameSpan(playerSpan, span) then
			anchorPosition = root.Position
		else
			anchorPosition = Vector3.new(anchorPosition.X, root.Position.Y, anchorPosition.Z)
		end
		AmbienceAnchor.CFrame = CFrame.new(anchorPosition)
		ensureAmbienceSounds()
	end

	local fadeTime = math.max(AMBIENCE_FADE_TIME, 0.01)
	local alpha = math.clamp(deltaTime / fadeTime, 0, 1)
	AmbienceVolume += (targetVolume - AmbienceVolume) * alpha

	local busVolume = AudioService:GetBus(AMBIENCE_BUS).Volume
	for _, sound in AmbienceSounds do
		if sound.Player.Parent then
			sound.Player.Volume = sound.BaseVolume * busVolume * AmbienceVolume
		end
	end

	if targetVolume <= 0 and AmbienceVolume <= 0.01 then
		AmbienceVolume = 0
		stopAmbienceSounds()
	end
end

TagService:Listen(LIGHT_TAG, watchModel, unwatchModel, workspace)

localPlayer.CharacterAdded:Connect(resetWarning)
localPlayer.CharacterRemoving:Connect(resetWarning)

RunService.Heartbeat:Connect(function(deltaTime)
	timeSinceCheck += deltaTime
	TimeSinceAmbienceUpdate += deltaTime
	if timeSinceCheck >= CHECK_INTERVAL then
		timeSinceCheck = 0

		local root = getRoot()
		if not root then
			resetWarning()
		else
			local source = nearestSource(root, true)
			if source then
				clearStartedAt = 0
			elseif warningActive then
				if clearStartedAt == 0 then
					clearStartedAt = os.clock()
				elseif os.clock() - clearStartedAt >= REARM_TIME then
					resetWarning()
				end
			end
		end
	end

	if TimeSinceAmbienceUpdate >= CHECK_INTERVAL then
		local elapsed = TimeSinceAmbienceUpdate
		TimeSinceAmbienceUpdate = 0
		updateAmbience(elapsed)
	end
end)

return ChaosWarningSoundService
