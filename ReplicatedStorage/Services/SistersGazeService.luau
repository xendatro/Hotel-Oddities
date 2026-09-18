local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SistersGazeService = {}

if not RunService:IsClient() then
	return SistersGazeService
end

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local FLAGS = require(ReplicatedStorage.Configs.FLAGS)
local GravityWarpService = require(ReplicatedStorage.Services.GravityWarpService)
local MathService = require(ReplicatedStorage.Services.MathService)
local SistersConfig = require(ReplicatedStorage.Configs.SistersConfig)
local SistersVertigoService = require(ReplicatedStorage.Services.SistersVertigoService)
local TagService = require(ReplicatedStorage.Services.TagService)
local Vanished = require(ReplicatedStorage.Services.VanishedService)
local WallstickService = require(ReplicatedStorage.Services.WallstickService)

if not FLAGS.Enemies then
	return SistersGazeService
end

local Config = SistersConfig.Gaze
local MINIMUM_DISTANCE = 1e-3

local localPlayer = Players.LocalPlayer
local GazeRemote = CommunicationService.Get(SistersConfig.Remotes.Folder, SistersConfig.Remotes.Gaze) :: RemoteEvent
local GazedRemote = CommunicationService.Get(SistersConfig.Remotes.Folder, SistersConfig.Remotes.Gazed) :: RemoteEvent

local Sisters: { [Model]: boolean } = {}
local Dwell = 0
local Pending = false
local RequestToken = 0
local SuppressedUntil = 0

local RayParams = RaycastParams.new()
RayParams.FilterType = Enum.RaycastFilterType.Exclude

TagService:Listen(SistersConfig.Tag, function(model: Instance): boolean
	Sisters[model :: Model] = true
	return true
end, function(model: Instance)
	Sisters[model :: Model] = nil
end, workspace)

local function hitsSister(instance: Instance): boolean
	for sister in Sisters do
		if instance:IsDescendantOf(sister) then return true end
	end
	return false
end

local function headVisible(camera: Camera, character: Model, head: BasePart): boolean
	RayParams.FilterDescendantsInstances = { character }
	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, head.Position - origin, RayParams)
	return result == nil or hitsSister(result.Instance)
end

function SistersGazeService.FindGazed(camera: Camera, character: Model): Model?
	local origin = camera.CFrame.Position
	local look = camera.CFrame.LookVector
	local best = nil :: Model?
	local bestAngle = Config.Angle
	for sister in Sisters do
		local head = sister:FindFirstChild("Head") :: BasePart?
		if not head then continue end

		local offset = head.Position - origin
		local distance = offset.Magnitude
		if distance < MINIMUM_DISTANCE or distance > Config.Range then continue end

		local angle = MathService.AngleBetween(offset, look)
		if angle > bestAngle then continue end
		if not headVisible(camera, character, head) then continue end

		best = sister
		bestAngle = angle
	end
	return best
end

local function suppress(seconds: number)
	SuppressedUntil = math.max(SuppressedUntil, os.clock() + seconds)
end

local function report(sister: Model)
	Pending = true
	RequestToken += 1
	local requestToken = RequestToken
	GazeRemote:FireServer(sister)
	task.delay(Config.ReplyTimeout, function()
		if requestToken == RequestToken then
			Pending = false
		end
	end)
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	if GravityWarpService.IsActive() or WallstickService.IsEnabled() then
		suppress(Config.Cooldown)
		Dwell = 0
		return
	end

	local camera = workspace.CurrentCamera
	local character = localPlayer.Character
	if not camera
		or not character
		or Pending
		or os.clock() < SuppressedUntil
		or not CharacterService.IsAlive(character)
		or Vanished.Is(character)
	then
		Dwell = 0
		return
	end

	local sister = SistersGazeService.FindGazed(camera, character)
	if not sister then
		Dwell = 0
		return
	end

	Dwell += deltaTime
	if Dwell < Config.DwellTime then return end

	Dwell = 0
	report(sister)
end)

GazedRemote.OnClientEvent:Connect(function(caught: boolean, leadTime: number?)
	Pending = false
	if caught then
		SistersVertigoService:Play(leadTime)
		suppress((leadTime or 0) + Config.Cooldown)
	else
		suppress(Config.RetryDelay)
	end
end)

localPlayer.CharacterAdded:Connect(function()
	Dwell = 0
	Pending = false
	SistersVertigoService:Stop()
end)

return SistersGazeService
