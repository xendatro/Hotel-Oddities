local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CameraBobConfig = require(ReplicatedStorage.Configs.CameraBobConfig)
local ChaserCameraService = require(ReplicatedStorage.Services.ChaserCameraService)
local MathService = require(ReplicatedStorage.Services.MathService)

local FirstPersonCameraService = {}

local RENDER_JOB = "CameraBob"
local TAU = MathService.TAU
local localPlayer = Players.LocalPlayer

UserInputService.MouseIconEnabled = false
localPlayer.PlayerGui:WaitForChild("Cursor").Enabled = true

type CharacterState = {
	Humanoid: Humanoid,
	Root: BasePart,
}

local characterState = nil :: CharacterState?
local phase = 0
local weight = 0
local amplitude = 1

local function bindCharacter(character: Model)
	local state = {
		Humanoid = character:WaitForChild("Humanoid") :: Humanoid,
		Root = character:WaitForChild("HumanoidRootPart") :: BasePart,
	}
	if localPlayer.Character ~= character then return end

	characterState = state
	phase = 0
	weight = 0
	amplitude = 1
end

local function render(deltaTime: number)
	local state = characterState
	local camera = workspace.CurrentCamera
	if not state or not camera then return end

	local velocity = state.Root.AssemblyLinearVelocity
	local horizontalSpeed = MathService.HorizontalMagnitude(velocity)
	local humanoid = state.Humanoid
	local moving = humanoid.Health > 0
		and humanoid.MoveDirection.Magnitude > 0.05
		and horizontalSpeed > 0.1
		and humanoid.FloorMaterial ~= Enum.Material.Air
	local chaserActive = ChaserCameraService:IsActive()
	if chaserActive then
		weight = 0
	else
		local targetWeight = if moving then 1 else 0
		weight += (targetWeight - weight) * MathService.ExpAlpha(CameraBobConfig.FadeSpeed, deltaTime)
	end

	if moving then
		local speedRatio = horizontalSpeed / CameraBobConfig.ReferenceWalkSpeed
		phase += TAU * CameraBobConfig.StepsPerSecond * speedRatio * deltaTime

		local target = math.clamp(
			1 + (speedRatio - 1) * CameraBobConfig.AmplitudeSpeedInfluence,
			CameraBobConfig.MinAmplitudeScale,
			CameraBobConfig.MaxAmplitudeScale
		)
		amplitude += (target - amplitude) * MathService.ExpAlpha(CameraBobConfig.FadeSpeed, deltaTime)
	end

	if weight < 1e-3 then return end

	local scale = weight * amplitude
	local side = math.sin(phase / 2)
	local offset = Vector3.new(
		side * CameraBobConfig.HorizontalDistance,
		-math.cos(phase) * CameraBobConfig.VerticalDistance,
		0
	) * scale
	local roll = math.rad(-side * CameraBobConfig.RollAngle * scale)
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

return FirstPersonCameraService
