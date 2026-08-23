local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LanternSwayService = {}

if not RunService:IsClient() then
	return LanternSwayService
end

local Config = require(ReplicatedStorage.Configs.LanternSwayConfig)

local LIGHT_TAG = "Floor1Light"
local RED_ATTRIBUTE = "ChaosRed"
local SwayNames: { [string]: true } = {}
for _, name in Config.SwayModelNames do
	SwayNames[name] = true
end

type SwayState = {
	Model: Model,
	RestPivot: CFrame,
	Hinge: Vector3,
	SpanDir: Vector3,
	AcrossDir: Vector3,
	Length: number,
	LimitDeg: number,
	Seed: number,
	Releasing: boolean,
	ActiveTarget: boolean,
	Proxy: BasePart?,
	AnchorPart: BasePart?,
	HingeConstraint: HingeConstraint?,
	WindTorque: Torque?,
	KickAccel: number,
	KickUntil: number,
	JoltAccel: number,
	JoltUntil: number,
}

local States: { [Model]: SwayState } = {}
local StateList: { SwayState } = {}
local Watched: { [Model]: RBXScriptConnection } = {}
local rng = Random.new()
local heartbeatConnection: RBXScriptConnection? = nil
local sinceRecull = math.huge

local function horizontal(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else nil
end

local function clearanceAlong(model: Model, origin: Vector3, direction: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { model }

	local clearance = Config.ClearanceProbe
	local hit = workspace:Raycast(origin, direction * Config.ClearanceProbe, params)
	if hit then
		clearance = math.min(clearance, hit.Distance)
	end
	hit = workspace:Raycast(origin, -direction * Config.ClearanceProbe, params)
	if hit then
		clearance = math.min(clearance, hit.Distance)
	end
	return clearance
end

local function inertia(state: SwayState): number
	local proxy = state.Proxy
	if not proxy then return 1 end
	return proxy.AssemblyMass * state.Length * state.Length / 3
end

local function teardown(state: SwayState)
	if state.AnchorPart then
		state.AnchorPart:Destroy()
	end
	if state.Proxy then
		state.Proxy:Destroy()
	end
	state.Proxy = nil
	state.AnchorPart = nil
	state.HingeConstraint = nil
	state.WindTorque = nil
end

local function makeStill(state: SwayState)
	if not state.Proxy then return end
	teardown(state)
	if state.Model.Parent then
		state.Model:PivotTo(state.RestPivot)
	end
end

local function makePhysical(state: SwayState)
	if state.Proxy then return end

	local anchor = Instance.new("Part")
	anchor.Name = "LanternSwayAnchor"
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CFrame = CFrame.new(state.Hinge)

	local proxy = Instance.new("Part")
	proxy.Name = "LanternSwayProxy"
	proxy.Size = Vector3.new(0.6, state.Length, 0.6)
	proxy.Transparency = 1
	proxy.Anchored = false
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.CFrame = CFrame.fromMatrix(
		state.Hinge - Vector3.yAxis * (state.Length / 2),
		state.AcrossDir,
		Vector3.yAxis
	)

	local frame = CFrame.fromMatrix(state.Hinge, state.AcrossDir, Vector3.yAxis)
	local anchorAttachment = Instance.new("Attachment")
	anchorAttachment.Parent = anchor
	local proxyAttachment = Instance.new("Attachment")
	proxyAttachment.Parent = proxy

	local hinge = Instance.new("HingeConstraint")
	hinge.Attachment0 = anchorAttachment
	hinge.Attachment1 = proxyAttachment
	hinge.LimitsEnabled = true
	hinge.UpperAngle = state.LimitDeg
	hinge.LowerAngle = -state.LimitDeg
	hinge.Restitution = Config.LimitBounce
	hinge.Parent = anchor

	local torque = Instance.new("Torque")
	torque.Attachment0 = proxyAttachment
	torque.RelativeTo = Enum.ActuatorRelativeTo.World
	torque.Torque = Vector3.zero
	torque.Parent = proxy

	anchor.Parent = workspace
	proxy.Parent = workspace
	anchorAttachment.WorldCFrame = frame
	proxyAttachment.WorldCFrame = frame

	local lift = Instance.new("VectorForce")
	lift.Attachment0 = proxyAttachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.yAxis * proxy.AssemblyMass * workspace.Gravity * (1 - Config.GravityScale)
	lift.Parent = proxy

	state.Proxy = proxy
	state.AnchorPart = anchor
	state.HingeConstraint = hinge
	state.WindTorque = torque

	local kick = Config.ImpulseStrength * rng:NextNumber(0.5, 1) / 0.25
	if rng:NextNumber() < 0.5 then kick = -kick end
	state.KickAccel = kick
	state.KickUntil = os.clock() + 0.25
end

local function removeState(index: number)
	local state = StateList[index]
	makeStill(state)
	States[state.Model] = nil
	local count = #StateList
	StateList[index] = StateList[count]
	StateList[count] = nil
end

local function bindLantern(model: Model)
	local state = States[model]
	if state then
		state.Releasing = false
		return
	end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	local hinge = boundsCFrame.Position + boundsCFrame.UpVector * (boundsSize.Y / 2)
	local length = math.max(boundsSize.Y, 0.5)
	local halfWidth = math.max(boundsSize.X, boundsSize.Z) / 2

	local axisA = horizontal(boundsCFrame.RightVector) or Vector3.xAxis
	local axisB = horizontal(boundsCFrame.LookVector) or axisA:Cross(Vector3.yAxis).Unit
	local clearA = clearanceAlong(model, boundsCFrame.Position, axisA)
	local clearB = clearanceAlong(model, boundsCFrame.Position, axisB)

	local spanDir, acrossDir, spanClear
	if clearA >= clearB then
		spanDir, acrossDir, spanClear = axisA, axisB, clearA
	else
		spanDir, acrossDir, spanClear = axisB, axisA, clearB
	end

	local maxDisplacement = spanClear - Config.WallMargin - halfWidth
	local fitLimit = math.deg(math.asin(math.clamp(maxDisplacement / length, 0, 1)))

	state = {
		Model = model,
		RestPivot = model:GetPivot(),
		Hinge = hinge,
		SpanDir = spanDir,
		AcrossDir = acrossDir,
		Length = length,
		LimitDeg = math.min(Config.SwingLimit, fitLimit),
		Seed = rng:NextNumber(0, 10000),
		Releasing = false,
		ActiveTarget = true,
		Proxy = nil,
		AnchorPart = nil,
		HingeConstraint = nil,
		WindTorque = nil,
		KickAccel = 0,
		KickUntil = 0,
		JoltAccel = 0,
		JoltUntil = 0,
	}
	States[model] = state
	table.insert(StateList, state)
end

local function releaseLantern(model: Model)
	local state = States[model]
	if state then
		state.Releasing = true
	end
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

local function stepPhysical(state: SwayState, now: number, deltaTime: number)
	local proxy = state.Proxy :: BasePart
	local torque = state.WindTorque
	local hinge = state.HingeConstraint
	if not torque or not hinge then return end

	local spin = proxy.AssemblyAngularVelocity:Dot(state.AcrossDir)

	if state.Releasing then
		torque.Torque = state.AcrossDir * (inertia(state) * -Config.SettleDamping * spin)
	else
		local accel = Config.WindStrength * math.noise(state.Seed, now * Config.WindSpeed) * 2

		if rng:NextNumber() < Config.ImpulseChance * deltaTime then
			local kick = Config.ImpulseStrength * rng:NextNumber(0.3, 1) / 0.15
			if rng:NextNumber() < 0.5 then kick = -kick end
			state.JoltAccel = kick
			state.JoltUntil = now + 0.15
		end
		if now < state.JoltUntil then
			accel += state.JoltAccel
		end
		if now < state.KickUntil then
			accel += state.KickAccel
		end

		accel -= Config.Damping * spin
		torque.Torque = state.AcrossDir * (inertia(state) * accel)
	end

	local angle = math.rad(hinge.CurrentAngle)
	state.Model:PivotTo(
		CFrame.new(state.Hinge)
			* CFrame.fromAxisAngle(state.AcrossDir, angle)
			* CFrame.new(-state.Hinge)
			* state.RestPivot
	)
end

local function settled(state: SwayState): boolean
	local hinge = state.HingeConstraint
	local proxy = state.Proxy
	if not hinge or not proxy then return true end
	return math.abs(hinge.CurrentAngle) <= Config.SettleAngle
		and math.abs(proxy.AssemblyAngularVelocity:Dot(state.AcrossDir)) <= 0.15
end

local function onHeartbeat(deltaTime: number)
	sinceRecull += deltaTime
	if sinceRecull >= Config.RecullInterval then
		sinceRecull = 0
		recull()
	end

	local now = os.clock()

	for index = #StateList, 1, -1 do
		local state = StateList[index]
		local model = state.Model

		if model.Parent == nil then
			teardown(state)
			States[model] = nil
			local count = #StateList
			StateList[index] = StateList[count]
			StateList[count] = nil
		elseif not state.ActiveTarget then
			makeStill(state)
			if state.Releasing then
				removeState(index)
			end
		elseif state.Proxy then
			stepPhysical(state, now, deltaTime)
			if state.Releasing and settled(state) then
				removeState(index)
			end
		elseif state.Releasing then
			removeState(index)
		else
			makePhysical(state)
		end
	end

	if #StateList == 0 and heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function startLoop()
	if heartbeatConnection then return end
	sinceRecull = math.huge
	heartbeatConnection = RunService.Heartbeat:Connect(onHeartbeat)
end

local function evaluate(model: Model)
	if model:GetAttribute(RED_ATTRIBUTE) then
		bindLantern(model)
		startLoop()
	else
		releaseLantern(model)
	end
end

local function watch(instance: Instance)
	if not instance:IsA("Model") or not SwayNames[instance.Name] then return end
	if Watched[instance] then return end
	Watched[instance] = instance:GetAttributeChangedSignal(RED_ATTRIBUTE):Connect(function()
		evaluate(instance)
	end)
	evaluate(instance)
end

local function unwatch(instance: Instance)
	local connection = Watched[instance :: Model]
	if not connection then return end
	connection:Disconnect()
	Watched[instance :: Model] = nil
	releaseLantern(instance :: Model)
end

CollectionService:GetInstanceAddedSignal(LIGHT_TAG):Connect(watch)
CollectionService:GetInstanceRemovedSignal(LIGHT_TAG):Connect(unwatch)
for _, instance in CollectionService:GetTagged(LIGHT_TAG) do
	watch(instance)
end

return LanternSwayService
