local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GravityWarpService = {}

if not RunService:IsClient() then
	return GravityWarpService
end

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local WallstickService = require(ReplicatedStorage.Services.WallstickService)

local Config = ToolConfigs["Gravity Warper"]

local Active = false
local CAMERA_BIND = "GravityWarpCamera"
local CameraRoot = nil :: BasePart?

local function renderCameraRoll()
	local camera = workspace.CurrentCamera
	local root = CameraRoot
	if not camera or not root or not root.Parent then return end

	local cameraCFrame = camera.CFrame
	local look = cameraCFrame.LookVector
	local rootUp = root.CFrame.UpVector
	WallstickService.SetCameraUpVector(rootUp)

	local projectedUp = rootUp - look * rootUp:Dot(look)
	if projectedUp.Magnitude < 1e-4 then return end

	local up = projectedUp.Unit
	local right = look:Cross(up).Unit
	camera.CFrame = CFrame.fromMatrix(cameraCFrame.Position, right, up, -look)
end

local function startCameraRoll(root: BasePart)
	CameraRoot = root
	WallstickService.SetCameraUpVector(root.CFrame.UpVector)
	RunService:BindToRenderStep(CAMERA_BIND, Enum.RenderPriority.Camera.Value + 1, renderCameraRoll)
end

local function stopCameraRoll()
	CameraRoot = nil
	RunService:UnbindFromRenderStep(CAMERA_BIND)
	WallstickService.SetCameraUpVector(Vector3.yAxis)
end

function GravityWarpService.IsActive(): boolean
	return Active
end

local function rayParamsFor(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	return params
end

local function tweenRoot(root: BasePart, goal: CFrame, time: number): boolean
	root.Anchored = true
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local tween = TweenService:Create(
		root,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ CFrame = goal }
	)
	tween:Play()
	local playbackState = tween.Completed:Wait()

	if root.Parent then
		root.Anchored = false
	end

	return playbackState == Enum.PlaybackState.Completed
end

local function warp(duration: number)
	if Active then return end

	local character = Players.LocalPlayer.Character
	local humanoid = CharacterService.GetHumanoid(character)
	local root = character and CharacterService.GetAliveRootFromCharacter(character)
	if not character or not humanoid or not root then return end

	local params = rayParamsFor(character)
	local ceiling = workspace:Raycast(root.Position, Vector3.new(0, Config.MaxCeilingDistance, 0), params)
	if not ceiling then return end

	Active = true
	startCameraRoll(root)

	local hipHeight = humanoid.HipHeight
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		hipHeight = 2
	end
	local clearance = hipHeight + root.Size.Y / 2 + 0.05

	local flipped = root.CFrame.Rotation * CFrame.Angles(0, 0, math.pi)
	local reachedCeiling = tweenRoot(
		root,
		CFrame.new(ceiling.Position - Vector3.new(0, clearance, 0)) * flipped,
		Config.AscendTime
	)

	if not reachedCeiling or not CharacterService.IsAlive(character) or root.Parent == nil then
		stopCameraRoll()
		Active = false
		return
	end

	local wallstick = WallstickService.Enable({
		tilt = true,
		spin = false,
		surfaceNormal = -Vector3.yAxis,
	})
	if not wallstick then
		stopCameraRoll()
		Active = false
		return
	end

	local ceilingPart = (ceiling.Instance :: BasePart).AssemblyRootPart
	local ceilingNormal = ceilingPart.CFrame:VectorToObjectSpace(-Vector3.yAxis)
	wallstick:setAndPivot(ceilingPart, ceilingNormal, ceiling.Position)
	wallstick:snapCameraUp()

	local elapsed = 0
	while elapsed < duration do
		elapsed += task.wait(0.1)
		if not CharacterService.IsAlive(character) or root.Parent == nil then
			WallstickService.Disable()
			stopCameraRoll()
			Active = false
			return
		end
	end

	WallstickService.Disable()

	if CharacterService.IsAlive(character) and root.Parent ~= nil then
		local uprightRotation = root.CFrame.Rotation * CFrame.Angles(0, 0, math.pi)
		local floor = workspace:Raycast(root.Position, Vector3.new(0, -Config.MaxCeilingDistance, 0), params)
		local goalPosition = floor and floor.Position + Vector3.new(0, clearance, 0)
			or root.Position - Vector3.new(0, 4, 0)
		tweenRoot(root, CFrame.new(goalPosition) * uprightRotation, Config.DescendTime)
	end

	stopCameraRoll()
	Active = false
end

CommunicationService.Get("GravityWarp", "Warp").OnClientEvent:Connect(function(duration: number)
	task.spawn(warp, duration)
end)

return GravityWarpService
