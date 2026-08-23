local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LanternSwayService = {}

if not RunService:IsClient() then
	return LanternSwayService
end

local Config = require(ReplicatedStorage.Configs.LanternSwayConfig)

local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local oddities = communication and communication:WaitForChild("Oddities", 30)
local MapDoors = oddities and oddities:WaitForChild("MapDoors", 30)

local LIGHT_TAG = "Floor1Light"
local SwayNames: { [string]: true } = {}
for _, name in Config.SwayModelNames do
	SwayNames[name] = true
end
local TAU = math.pi * 2
local DEG = math.pi / 180
local MAX_SUBSTEP = 1 / 90
local MAX_FRAME_DT = 1 / 20

type SwayState = {
	Model: Model,
	RestPivot: CFrame,
	Hinge: Vector3,
	SpanDir: Vector3,
	AcrossDir: Vector3,
	AlongAngle: number,
	AlongVel: number,
	AcrossAngle: number,
	AcrossVel: number,
	WAlong: number,
	WAcross: number,
	Zeta: number,
	AlongAmp: number,
	AcrossAmp: number,
	TwistAmp: number,
	TwistW: number,
	TwistPhase: number,
	Seed1: number,
	Seed2: number,
	Seed3: number,
	StartAt: number,
	Envelope: number,
	Releasing: boolean,
	Activity: number,
	ActiveTarget: boolean,
	Moved: boolean,
	Tokens: { [number]: true },
	TokenCount: number,
}

local States: { [Model]: SwayState } = {}
local StateList: { SwayState } = {}
local TokenModels: { [number]: { Model } } = {}
local rng = Random.new()
local overlap = OverlapParams.new()
overlap.MaxParts = 0
local renderConnection: RBXScriptConnection? = nil
local sinceRecull = math.huge

local function removeState(state: SwayState)
	States[state.Model] = nil
	local count = #StateList
	for index = count, 1, -1 do
		if StateList[index] == state then
			StateList[index] = StateList[count]
			StateList[count] = nil
			break
		end
	end
end

local function stopLoopIfEmpty()
	if #StateList == 0 and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function acrossClearance(model: Model, origin: Vector3, acrossDir: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }

	local clearance = Config.ClearanceProbe
	local hit = workspace:Raycast(origin, acrossDir * Config.ClearanceProbe, params)
	if hit then
		clearance = math.min(clearance, hit.Distance)
	end
	hit = workspace:Raycast(origin, -acrossDir * Config.ClearanceProbe, params)
	if hit then
		clearance = math.min(clearance, hit.Distance)
	end
	return clearance
end

local function bindLantern(model: Model, token: number, boxCFrame: CFrame, boxSize: Vector3, spanDir: Vector3, acrossDir: Vector3)
	local state = States[model]
	if state then
		if not state.Tokens[token] then
			state.Tokens[token] = true
			state.TokenCount += 1
		end
		state.Releasing = false
		return
	end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local hinge = boundsCFrame.Position + boundsCFrame.UpVector * (boundsSize.Y / 2)
	local length = math.max(boundsSize.Y, 0.5)
	local halfWidth = math.max(boundsSize.X, boundsSize.Z) / 2

	local clearance = acrossClearance(model, boundsCFrame.Position, acrossDir)
	local maxDisplacement = clearance - Config.WallMargin - halfWidth
	local acrossLimit = math.asin(math.clamp(maxDisplacement / length, 0, 1))

	local ampScale = rng:NextNumber(0.75, 1.25)
	local wAlong = TAU * Config.BaseFrequency * (1 + Config.FrequencyJitter * rng:NextNumber(-1, 1))
	local wAcross = wAlong * Config.AcrossFrequencyRatio * (1 + 0.5 * Config.FrequencyJitter * rng:NextNumber(-1, 1))

	local alongProjection = (hinge - boxCFrame.Position):Dot(spanDir) + boxSize.Z / 2
	local delay = math.max(alongProjection, 0) * Config.SpanStagger
		+ rng:NextNumber(0, Config.StaggerJitter)

	state = {
		Model = model,
		RestPivot = model:GetPivot(),
		Hinge = hinge,
		SpanDir = spanDir,
		AcrossDir = acrossDir,
		AlongAngle = 0,
		AlongVel = 0,
		AcrossAngle = 0,
		AcrossVel = 0,
		WAlong = wAlong,
		WAcross = wAcross,
		Zeta = Config.DampingRatio * rng:NextNumber(0.75, 1.35),
		AlongAmp = Config.AlongAmplitude * DEG * ampScale,
		AcrossAmp = math.min(Config.AcrossAmplitude * DEG * ampScale, acrossLimit),
		TwistAmp = Config.TwistAmplitude * DEG * rng:NextNumber(0.6, 1.4),
		TwistW = TAU * Config.TwistFrequency * rng:NextNumber(0.8, 1.25),
		TwistPhase = rng:NextNumber(0, TAU),
		Seed1 = rng:NextNumber(0, 10000),
		Seed2 = rng:NextNumber(0, 10000),
		Seed3 = rng:NextNumber(0, 10000),
		StartAt = os.clock() + delay,
		Envelope = 0,
		Releasing = false,
		Activity = 1,
		ActiveTarget = true,
		Moved = false,
		Tokens = { [token] = true },
		TokenCount = 1,
	}
	States[model] = state
	table.insert(StateList, state)
end

local function releaseToken(token: number)
	local models = TokenModels[token]
	if not models then return end
	TokenModels[token] = nil

	for _, model in models do
		local state = States[model]
		if state and state.Tokens[token] then
			state.Tokens[token] = nil
			state.TokenCount -= 1
			if state.TokenCount <= 0 then
				state.Releasing = true
			end
		end
	end
end

local function resolveLanterns(boxCFrame: CFrame, boxSize: Vector3): { Model }
	local parts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, overlap)
	local seen: { [Model]: true } = {}
	local models: { Model } = {}

	for _, part in parts do
		local instance: Instance? = part.Parent
		while instance and instance ~= workspace do
			if instance:IsA("Model") and SwayNames[instance.Name] then
				if not seen[instance] and instance:HasTag(LIGHT_TAG) then
					seen[instance] = true
					table.insert(models, instance)
				end
				break
			end
			instance = instance.Parent
		end
	end

	return models
end

local function recull()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local cameraPosition = camera.CFrame.Position
	local radius = Config.CameraCullRadius

	local within: { SwayState } = {}
	local distances: { [SwayState]: number } = {}
	for _, state in StateList do
		local distance = (state.Hinge - cameraPosition).Magnitude
		if distance <= radius then
			distances[state] = distance
			table.insert(within, state)
		else
			state.ActiveTarget = false
		end
	end

	if #within > Config.MaxSimulated then
		table.sort(within, function(first, second)
			return distances[first] < distances[second]
		end)
	end
	for index, state in within do
		state.ActiveTarget = index <= Config.MaxSimulated
	end
end

local function stepState(state: SwayState, now: number, deltaTime: number): boolean
	local model = state.Model
	if model.Parent == nil then
		return false
	end

	local envelopeTarget = if state.Releasing or now < state.StartAt then 0 else 1
	if envelopeTarget > state.Envelope then
		state.Envelope = math.min(envelopeTarget, state.Envelope + deltaTime / math.max(Config.AttackTime, 0.05))
	elseif envelopeTarget < state.Envelope then
		state.Envelope = math.max(envelopeTarget, state.Envelope - deltaTime / math.max(Config.ReleaseTime, 0.05))
	end

	local activityTarget = if state.ActiveTarget then 1 else 0
	if activityTarget > state.Activity then
		state.Activity = math.min(activityTarget, state.Activity + deltaTime / math.max(Config.AttackTime, 0.05))
	elseif activityTarget < state.Activity then
		state.Activity = math.max(activityTarget, state.Activity - deltaTime / math.max(Config.ReleaseTime, 0.05))
	end

	if state.Releasing and state.Envelope <= 0.001 then
		if state.Moved then
			model:PivotTo(state.RestPivot)
		end
		return false
	end

	local weight = state.Envelope * state.Activity
	if weight <= 0.001 then
		if state.Moved then
			model:PivotTo(state.RestPivot)
			state.Moved = false
		end
		return true
	end

	if state.ActiveTarget or state.Activity > 0.001 then
		local noiseTime = now * Config.NoiseScale
		local forceAlong = Config.NoiseStrength * state.AlongAmp * state.WAlong * state.WAlong
			* math.noise(state.Seed1, noiseTime) * 2 * state.Envelope
		local forceAcross = Config.NoiseStrength * state.AcrossAmp * state.WAcross * state.WAcross
			* math.noise(state.Seed2, noiseTime * 1.31) * 2 * state.Envelope

		if rng:NextNumber() < Config.ImpulseChance * deltaTime then
			local kick = Config.ImpulseStrength * rng:NextNumber(0.3, 1)
			if rng:NextNumber() < 0.5 then kick = -kick end
			state.AlongVel += kick * state.AlongAmp * state.WAlong * state.Envelope
			state.AcrossVel += kick * 0.5 * state.AcrossAmp * state.WAcross * state.Envelope
		end

		local remaining = deltaTime
		while remaining > 0 do
			local h = math.min(remaining, MAX_SUBSTEP)
			remaining -= h

			state.AlongVel += (forceAlong - 2 * state.Zeta * state.WAlong * state.AlongVel
				- state.WAlong * state.WAlong * state.AlongAngle) * h
			state.AlongAngle += state.AlongVel * h

			state.AcrossVel += (forceAcross - 2 * state.Zeta * state.WAcross * state.AcrossVel
				- state.WAcross * state.WAcross * state.AcrossAngle) * h
			state.AcrossAngle += state.AcrossVel * h
		end

		local alongLimit = state.AlongAmp * 1.5
		if math.abs(state.AlongAngle) > alongLimit then
			state.AlongAngle = if state.AlongAngle > 0 then alongLimit else -alongLimit
			if state.AlongAngle * state.AlongVel > 0 then
				state.AlongVel = -state.AlongVel * 0.4
			end
		end
		if math.abs(state.AcrossAngle) > state.AcrossAmp then
			state.AcrossAngle = if state.AcrossAngle > 0 then state.AcrossAmp else -state.AcrossAmp
			if state.AcrossAngle * state.AcrossVel > 0 then
				state.AcrossVel = -state.AcrossVel * 0.4
			end
		end
	end

	local twistNoise = 0.6 + 0.8 * math.noise(state.Seed3, now * Config.NoiseScale * 0.7)
	local twist = state.TwistAmp * weight * math.sin(now * state.TwistW + state.TwistPhase) * twistNoise

	local rotation = CFrame.fromAxisAngle(state.AcrossDir, state.AlongAngle * weight)
		* CFrame.fromAxisAngle(state.SpanDir, state.AcrossAngle * weight)
		* CFrame.fromAxisAngle(Vector3.yAxis, twist)

	model:PivotTo(CFrame.new(state.Hinge) * rotation * CFrame.new(-state.Hinge) * state.RestPivot)
	state.Moved = true

	return true
end

local function onRenderStep(deltaTime: number)
	local count = #StateList
	if count == 0 then
		stopLoopIfEmpty()
		return
	end

	sinceRecull += deltaTime
	if sinceRecull >= Config.RecullInterval then
		sinceRecull = 0
		recull()
	end

	local now = os.clock()
	local dt = math.min(deltaTime, MAX_FRAME_DT)

	for index = count, 1, -1 do
		local state = StateList[index]
		if not stepState(state, now, dt) then
			for token in state.Tokens do
				local models = TokenModels[token]
				if models then
					local total = #models
					for modelIndex = total, 1, -1 do
						if models[modelIndex] == state.Model then
							models[modelIndex] = models[total]
							models[total] = nil
							break
						end
					end
				end
			end
			removeState(state)
		end
	end

	stopLoopIfEmpty()
end

local function startLoop()
	if renderConnection or #StateList == 0 then return end
	sinceRecull = math.huge
	renderConnection = RunService.RenderStepped:Connect(onRenderStep)
end

if MapDoors and MapDoors:IsA("RemoteEvent") then
	(MapDoors :: RemoteEvent).OnClientEvent:Connect(function(
		action: any,
		token: any,
		boxCFrame: any,
		boxSize: any,
		_speed: any,
		mode: any,
		_closeSpeed: any,
		_intervalMin: any,
		_intervalMax: any,
		warnKind: any
	)
		if type(token) ~= "number" then return end

		if action == "Start" then
			if mode ~= "Chaos" or warnKind ~= "ChaosWarning" then return end
			if typeof(boxCFrame) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then return end

			if TokenModels[token] then
				releaseToken(token)
			end

			local look = boxCFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude < 1e-3 then
				flat = Vector3.zAxis
			end
			local spanDir = flat.Unit
			local acrossDir = spanDir:Cross(Vector3.yAxis).Unit

			local models = resolveLanterns(boxCFrame, boxSize)
			if #models == 0 then return end

			TokenModels[token] = models
			for _, model in models do
				bindLantern(model, token, boxCFrame, boxSize, spanDir, acrossDir)
			end
			startLoop()
		elseif action == "Stop" then
			releaseToken(token)
		end
	end)
end

return LanternSwayService
