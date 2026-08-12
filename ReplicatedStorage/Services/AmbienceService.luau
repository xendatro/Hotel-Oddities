local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Configs.AmbienceConfig)
local AudioService = require(ReplicatedStorage.Services.AudioService)
local HallwayGraph = require(ReplicatedStorage.Modules.HallwayGraph)

local AmbienceService = {}

if not RunService:IsClient() then
	return AmbienceService
end

local AMBIENCE_FOLDER = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Ambience")
local ENEMY_TAG = "Enemy"

-- The bed ducks as an enemy closes in. A fader of its own between the players and the speakers
-- means the ducking is one number, independent of whatever volume each clip was authored at and of
-- the Ambience bus underneath it.
local Duck = Instance.new("AudioFader")
Duck.Name = "AmbienceDuck"
Duck.Parent = workspace:WaitForChild("Sounds")
AudioService:Wire(Duck, AudioService:GetOutput())

local sources = {}
for _, child in AMBIENCE_FOLDER:GetChildren() do
	if child:IsA("AudioPlayer") then
		table.insert(sources, child)
	end
end

local playing: AudioPlayer?
local sourceIndex = 0
local volumeMultiplier = 1
local accumulator = math.huge

local function getNextSource(): AudioPlayer?
	if #sources == 0 then return nil end

	local nextIndex = sourceIndex + 1
	if nextIndex > #sources then
		nextIndex = 1
	end
	sourceIndex = nextIndex
	return sources[sourceIndex]
end

local function playNext()
	local source = getNextSource()
	if not source then return end

	local player = AudioService:Play2D(source, false, "Ambience", nil, Duck)
	playing = player

	player.Ended:Connect(function()
		if playing == player then
			playing = nil
			playNext()
		end
	end)
end

local function getAliveRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then return nil end
	return root :: BasePart
end

local function getNearestEnemyDistance(position: Vector3): number
	local nearest = math.huge
	for _, enemy in CollectionService:GetTagged(ENEMY_TAG) do
		if enemy:IsA("Model") and enemy:IsDescendantOf(workspace) then
			local distance = HallwayGraph:GetWalkingDistance(position, enemy:GetPivot().Position)
			nearest = math.min(nearest, distance)
		end
	end
	return nearest
end

local function updateVolume(deltaTime: number)
	local root = getAliveRoot()
	local nearestDistance = if root then getNearestEnemyDistance(root.Position) else math.huge
	local targetMultiplier = math.clamp(
		(nearestDistance - AmbienceConfig.SilentDistance)
			/ (AmbienceConfig.FullVolumeDistance - AmbienceConfig.SilentDistance),
		0,
		1
	)

	local fadeTime = math.max(AmbienceConfig.FadeTime, 0.01)
	local alpha = math.clamp(deltaTime / fadeTime, 0, 1)
	volumeMultiplier += (targetMultiplier - volumeMultiplier) * alpha
	Duck.Volume = volumeMultiplier
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	accumulator += deltaTime
	if accumulator < AmbienceConfig.UpdateInterval then return end

	local elapsed = accumulator
	accumulator = 0
	updateVolume(elapsed)
end)

playNext()

return AmbienceService
