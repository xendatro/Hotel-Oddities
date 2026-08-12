--- Adds a small, speed-matched step motion after Roblox positions the first-person camera.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraBobConfig = require(ReplicatedStorage.Configs.CameraBobConfig)

local FirstPersonCameraService = {}

local RENDER_JOB = "CameraBob"
local TAU = math.pi * 2
local localPlayer = Players.LocalPlayer

type CharacterState = {
	Humanoid: Humanoid,
	Root: BasePart,
}

local characterState = nil :: CharacterState?
local phase = 0
local weight = 0

local function bindCharacter(character: Model)
	local state = {
		Humanoid = character:WaitForChild("Humanoid") :: Humanoid,
		Root = character:WaitForChild("HumanoidRootPart") :: BasePart,
	}
	if localPlayer.Character ~= character then return end

	characterState = state
	phase = 0
	weight = 0
end

local function render(deltaTime: number)
	local state = characterState
	local camera = workspace.CurrentCamera
	if not state or not camera then return end

	local velocity = state.Root.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local humanoid = state.Humanoid
	local moving = humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.05
		and horizontalSpeed > 0.1
		and humanoid.FloorMaterial ~= Enum.Material.Air
	local targetWeight = if moving then 1 else 0
	weight += (targetWeight - weight) * (1 - math.exp(-CameraBobConfig.FadeSpeed * deltaTime))

	if moving then
		local stepRate = CameraBobConfig.StepsPerSecond
			* horizontalSpeed / CameraBobConfig.ReferenceWalkSpeed
		phase += TAU * stepRate * deltaTime
	end

	if weight < 1e-3 then return end

	local side = math.sin(phase / 2)
	local offset = Vector3.new(
		side * CameraBobConfig.HorizontalDistance,
		-math.cos(phase) * CameraBobConfig.VerticalDistance,
		0
	) * weight
	local roll = math.rad(-side * CameraBobConfig.RollAngle * weight)
	camera.CFrame *= CFrame.new(offset) * CFrame.Angles(0, 0, roll)
end

localPlayer.CharacterAdded:Connect(bindCharacter)
localPlayer.CharacterRemoving:Connect(function()
	characterState = nil
	weight = 0
end)

if localPlayer.Character then
	task.spawn(bindCharacter, localPlayer.Character)
end

RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 2, render)
UserInputService.MouseIconEnabled = false
localPlayer.PlayerGui:WaitForChild("Cursor").Enabled = true

return FirstPersonCameraService
