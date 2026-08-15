local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Configs.PlayerOddityConfig)

local PlayerOddityRenderService = {}

if not RunService:IsClient() or not Config.Enabled then
	return PlayerOddityRenderService
end

local communication = ReplicatedStorage:WaitForChild("Communication", 30)
local oddities = communication and communication:WaitForChild("Oddities", 30)
local HeadStare = oddities and oddities:WaitForChild("HeadStare", 30)
if not HeadStare or not HeadStare:IsA("RemoteEvent") then
	return PlayerOddityRenderService
end

type HeadTurn = {
	Neck: Motor6D,
	Applied: CFrame,
}

local localPlayer = Players.LocalPlayer
local activeUntil = 0
local turns: { [Model]: HeadTurn } = {}

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getNeck(model: Model): Motor6D?
	local neck = model:FindFirstChild("Neck", true)
	return if neck and neck:IsA("Motor6D") then neck else nil
end

local function headRotation(model: Model, target: Vector3): CFrame
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then return CFrame.identity end

	local relative = root.CFrame:VectorToObjectSpace(target - root.Position)
	local horizontal = flatten(relative)
	if horizontal.Magnitude < 1e-3 then return CFrame.identity end

	local yaw = math.clamp(math.atan2(-relative.X, -relative.Z), -math.rad(80), math.rad(80))
	local pitch = math.clamp(
		math.atan2(relative.Y, horizontal.Magnitude),
		-math.rad(35),
		math.rad(35)
	)
	return CFrame.Angles(-pitch, yaw, 0)
end

local function targetPosition(): Vector3?
	local character = localPlayer.Character
	if not character then return nil end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return nil end

	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head.Position end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then return root.Position + Vector3.yAxis * 2.5 end
	return nil
end

HeadStare.OnClientEvent:Connect(function(duration: any)
	if type(duration) ~= "number" then return end
	if duration > 0 then
		activeUntil = math.max(activeUntil, os.clock() + math.clamp(duration, 0, Config.MaxDuration))
	else
		activeUntil = 0
	end
end)

-- Remove last frame's contribution before the animation system writes the next one. This keeps the
-- oddity additive and lets normal head motion resume as soon as the eased turn reaches identity.
RunService.PreAnimation:Connect(function()
	for model, state in turns do
		if state.Neck.Parent and model:IsDescendantOf(workspace) then
			state.Neck.Transform = state.Applied:Inverse() * state.Neck.Transform
		else
			turns[model] = nil
		end
	end
end)

RunService.PreSimulation:Connect(function(deltaTime: number)
	local now = os.clock()
	local target = targetPosition()
	local watching = target ~= nil and now < activeUntil
	local seen: { [Model]: boolean } = {}

	if not watching and next(turns) == nil then return end

	for _, player in Players:GetPlayers() do
		if player == localPlayer then continue end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local neck = character and getNeck(character)
		if not character or not humanoid or humanoid.Health <= 0 or not neck then continue end

		local state = turns[character]
		if not state or state.Neck ~= neck then
			state = { Neck = neck, Applied = CFrame.identity }
			turns[character] = state
		end

		local desired = if watching then headRotation(character, target :: Vector3) else CFrame.identity
		local rate = if watching then Config.HeadTurnRate else Config.HeadReturnRate
		local alpha = 1 - math.exp(-rate * deltaTime)
		state.Applied = state.Applied:Lerp(desired, alpha)
		neck.Transform = state.Applied * neck.Transform
		seen[character] = true
	end

	for model, state in turns do
		if seen[model] then continue end
		turns[model] = nil
	end

	if not watching then
		local settled = true
		for _, state in turns do
			local x, y, z = state.Applied:ToOrientation()
			if math.abs(x) + math.abs(y) + math.abs(z) > 0.01 then
				settled = false
				break
			end
		end
		if settled then
			for _, state in turns do
				if state.Neck.Parent then
					state.Neck.Transform = state.Applied:Inverse() * state.Neck.Transform
				end
			end
			table.clear(turns)
		end
	end
end)

return PlayerOddityRenderService
