local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local CameraFovService = require(ReplicatedStorage.Services.CameraFovService)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MathService = require(ReplicatedStorage.Services.MathService)

local StalkerCameraService = {}

if not FLAGS.Enemies then
	return StalkerCameraService
end

local FaceStalker = CommunicationService.Get("Enemies", "FaceStalker") :: RemoteEvent

local RENDER_JOB = "StalkerCameraLock"
local FOV_OFFSET_NAME = "StalkerKill"
local KILL_FOV_OFFSET = 30
local FOV_RESTORE_TIME = 0.2
local localPlayer = Players.LocalPlayer

type Job = {
	Model: Model,
	Target: BasePart,
	StartedAt: number,
	TurnTime: number,
	StartRotation: CFrame,
	Kill: boolean,
	AnchoredRoot: BasePart?,
}

local job = nil :: Job?

local function release()
	local active = job
	if not active then return end
	job = nil
	RunService:UnbindFromRenderStep(RENDER_JOB)

	if active.Kill then
		CameraFovService:TweenOffset(
			FOV_OFFSET_NAME,
			0,
			TweenInfo.new(FOV_RESTORE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		)
	end
	local root = active.AnchoredRoot
	if root and root.Parent then
		root.Anchored = false
	end
end

local function render()
	local active = job
	if not active then return end

	local humanoid = CharacterService.GetAliveHumanoid(localPlayer)
	if not humanoid or not active.Model:IsDescendantOf(workspace) then
		release()
		return
	end

	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local offset = active.Target.Position - origin
	if offset.Magnitude < 1e-3 then return end

	local goalRotation = CFrame.lookAt(Vector3.zero, offset).Rotation
	local progress = math.clamp((os.clock() - active.StartedAt) / active.TurnTime, 0, 1)
	local eased = MathService.Smoothstep(progress)
	local rotation = active.StartRotation:Lerp(goalRotation, eased)
	camera.CFrame = CFrame.new(origin) * rotation
end

FaceStalker.OnClientEvent:Connect(function(model: Model?, turnTime: number?, kill: boolean?)
	release()
	if not model then return end

	local anchoredRoot = nil :: BasePart?
	if kill then
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = true
			anchoredRoot = root
		end
		CameraFovService:TweenOffset(
			FOV_OFFSET_NAME,
			KILL_FOV_OFFSET,
			TweenInfo.new(turnTime :: number, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		)
	end

	local camera = workspace.CurrentCamera
	job = {
		Model = model,
		Target = model.UpperTorso :: BasePart,
		StartedAt = os.clock(),
		TurnTime = turnTime :: number,
		StartRotation = camera.CFrame.Rotation,
		Kill = kill == true,
		AnchoredRoot = anchoredRoot,
	}
	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 1, render)
end)

return StalkerCameraService
