local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Configs.AmbienceConfig)
local HallwayGraph = require(ReplicatedStorage.Modules.HallwayGraph)

local AmbienceService = {}

if not RunService:IsClient() then
	return AmbienceService
end

local AMBIENCE_FOLDER = ReplicatedStorage:WaitForChild("Sounds"):WaitForChild("Ambience")
local OUTPUT_FOLDER = workspace:WaitForChild("Sounds")
local ENEMY_TAG = "Enemy"

type PlayingSound = {
	Sound: Sound,
	BaseVolume: number,
}

local sources = {}
for _, child in AMBIENCE_FOLDER:GetChildren() do
	if child:IsA("Sound") then
		table.insert(sources, child)
	end
end

local playing: PlayingSound?
local sourceIndex = 0
local volumeMultiplier = 1
local accumulator = math.huge

local function getNextSource(): Sound?
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

	local sound = source:Clone()
	sound.Looped = false
	sound.Volume = source.Volume * volumeMultiplier
	sound.Parent = OUTPUT_FOLDER
	playing = {
		Sound = sound,
		BaseVolume = source.Volume,
	}

	sound.Ended:Connect(function()
		if playing and playing.Sound == sound then
			playing = nil
			playNext()
		end
	end)
	sound:Play()
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

	if playing then
		playing.Sound.Volume = playing.BaseVolume * volumeMultiplier
	end
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
