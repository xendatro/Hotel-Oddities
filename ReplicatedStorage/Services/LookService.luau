local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local LookConfig = require(ReplicatedStorage.Configs.LookConfig)

local LookService = {}

if not RunService:IsClient() then
	return LookService
end

local PITCH_ATTRIBUTE = "LookPitch"
local YAW_ATTRIBUTE = "LookYaw"

local player = Players.LocalPlayer

local Update = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Look")
	:WaitForChild("Update") :: RemoteEvent

local lastSentPitch, lastSentYaw = 0, 0
local nextSendAt = 0

local function report()
	local now = os.clock()
	if now < nextSendAt then return end
	nextSendAt = now + LookConfig.SendInterval

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not camera then return end

	local look = camera.CFrame.LookVector
	local pitch = math.asin(math.clamp(look.Y, -1, 1))

	local yaw = 0
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local flatBody = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatLook.Magnitude > 1e-3 and flatBody.Magnitude > 1e-3 then
		flatLook, flatBody = flatLook.Unit, flatBody.Unit
		yaw = math.atan2(flatBody:Cross(flatLook).Y, flatBody:Dot(flatLook))
	end

	pitch = math.clamp(pitch, -LookConfig.MaxPitch, LookConfig.MaxPitch)
	yaw = math.clamp(yaw, -LookConfig.MaxYaw, LookConfig.MaxYaw)

	if math.abs(pitch - lastSentPitch) < LookConfig.SendThreshold
		and math.abs(yaw - lastSentYaw) < LookConfig.SendThreshold
	then
		return
	end
	lastSentPitch, lastSentYaw = pitch, yaw
	Update:FireServer(pitch, yaw)
end

type Applied = {
	Neck: CFrame,
	Waist: CFrame,
	Pitch: number,
	Yaw: number,
}

local applied: { [Model]: Applied } = {}

local function getMotor(model: Model, partName: string, motorName: string): any?
	local part = model:FindFirstChild(partName)
	local motor = part and part:FindFirstChild(motorName)
	if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
		return motor
	end
	return nil
end

local function collectTargets(): { Model }
	local targets = {}

	for _, other in Players:GetPlayers() do
		local character = other.Character
		local isOther = other ~= player or LookConfig.Debug.IncludeLocalPlayer
		if isOther and character and character:GetAttribute(PITCH_ATTRIBUTE) ~= nil then
			table.insert(targets, character)
		end
	end

	for _, model in CollectionService:GetTagged("Enemy") do
		if model:IsDescendantOf(workspace) and model:GetAttribute(PITCH_ATTRIBUTE) ~= nil then
			table.insert(targets, model)
		end
	end

	return targets
end

RunService.PreAnimation:Connect(function()
	for model, state in applied do
		if model:IsDescendantOf(workspace) then
			local neck = getMotor(model, "Head", "Neck")
			local waist = getMotor(model, "UpperTorso", "Waist")
			if neck then neck.Transform = state.Neck:Inverse() * neck.Transform end
			if waist then waist.Transform = state.Waist:Inverse() * waist.Transform end
		else
			applied[model] = nil
		end
	end
end)

RunService.PreSimulation:Connect(function(deltaTime: number)
	report()

	local seen: { [Model]: boolean } = {}
	local alpha = 1 - math.exp(-deltaTime * LookConfig.Smoothing)

	for _, model in collectTargets() do
		local neck = getMotor(model, "Head", "Neck")
		local waist = getMotor(model, "UpperTorso", "Waist")
		if not neck and not waist then continue end

		local targetPitch = model:GetAttribute(PITCH_ATTRIBUTE)
		local targetYaw = model:GetAttribute(YAW_ATTRIBUTE)
		if type(targetPitch) ~= "number" then targetPitch = 0 end
		if type(targetYaw) ~= "number" then targetYaw = 0 end
		targetPitch = math.clamp(targetPitch, -LookConfig.MaxPitch, LookConfig.MaxPitch)
		targetYaw = math.clamp(targetYaw, -LookConfig.MaxYaw, LookConfig.MaxYaw)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health <= 0 then
			targetPitch, targetYaw = 0, 0
		end

		local state = applied[model]
		if not state then
			state = { Neck = CFrame.identity, Waist = CFrame.identity, Pitch = 0, Yaw = 0 }
			applied[model] = state
		end

		state.Pitch += (targetPitch - state.Pitch) * alpha
		state.Yaw += (targetYaw - state.Yaw) * alpha

		local neckConfig, waistConfig = LookConfig.Neck, LookConfig.Waist
		state.Neck = CFrame.Angles(state.Pitch * neckConfig.Pitch, state.Yaw * neckConfig.Yaw, 0)
		state.Waist = CFrame.Angles(state.Pitch * waistConfig.Pitch, state.Yaw * waistConfig.Yaw, 0)

		if neck then neck.Transform = state.Neck * neck.Transform end
		if waist then waist.Transform = state.Waist * waist.Transform end
		seen[model] = true
	end

	for model in applied do
		if not seen[model] then
			applied[model] = nil
		end
	end
end)

return LookService
