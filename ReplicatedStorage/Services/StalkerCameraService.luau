--- Client half of the Stalker's reveal. Once its patience runs out, the server names the Stalker and
--- this service takes the camera after Roblox's own camera step: first easing the view around, then
--- holding it on the charge until the server releases it or the target dies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FLAGS = require(ReplicatedStorage.Configs.FLAGS)

local StalkerCameraService = {}

if not FLAGS.Enemies then
	return StalkerCameraService
end

local FaceStalker = ReplicatedStorage
	:WaitForChild("Communication")
	:WaitForChild("Enemies")
	:WaitForChild("FaceStalker") :: RemoteEvent

local RENDER_JOB = "StalkerCameraLock"
local localPlayer = Players.LocalPlayer

type Job = {
	Model: Model,
	Target: BasePart,
	StartedAt: number,
	TurnTime: number,
	StartRotation: CFrame,
}

local job = nil :: Job?

local function release()
	if not job then return end
	job = nil
	RunService:UnbindFromRenderStep(RENDER_JOB)
end

local function render()
	local active = job
	if not active then return end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid or humanoid.Health <= 0 or not active.Model:IsDescendantOf(workspace) then
		release()
		return
	end

	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local offset = active.Target.Position - origin
	if offset.Magnitude < 1e-3 then return end

	local goalRotation = CFrame.lookAt(Vector3.zero, offset).Rotation
	local progress = math.clamp((os.clock() - active.StartedAt) / active.TurnTime, 0, 1)
	local eased = progress * progress * (3 - 2 * progress)
	local rotation = active.StartRotation:Lerp(goalRotation, eased)
	camera.CFrame = CFrame.new(origin) * rotation
end

FaceStalker.OnClientEvent:Connect(function(model: Model?, turnTime: number?)
	release()
	if not model then return end

	local camera = workspace.CurrentCamera
	job = {
		Model = model,
		Target = model.UpperTorso :: BasePart,
		StartedAt = os.clock(),
		TurnTime = turnTime :: number,
		StartRotation = camera.CFrame.Rotation,
	}
	RunService:BindToRenderStep(RENDER_JOB, Enum.RenderPriority.Camera.Value + 1, render)
end)

return StalkerCameraService
