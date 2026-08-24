local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local EnemyService = require(ServerStorage.Services.EnemyService)
local Replication = require(ReplicatedStorage.Classes.Wallstick.Replication)

local ORIGIN_CFRAME = CFrame.new(0, 4096, 0)

local WallstickService = {}

local function setupCollisions()
	EnemyService:EnsureCollisionGroup()

	if not PhysicsService:IsCollisionGroupRegistered("WallstickCollision") then
		PhysicsService:RegisterCollisionGroup("WallstickCollision")
	end
	if not PhysicsService:IsCollisionGroupRegistered("WallstickNoCollision") then
		PhysicsService:RegisterCollisionGroup("WallstickNoCollision")
	end

	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		PhysicsService:CollisionGroupSetCollidable(group.name, "WallstickCollision", false)
		PhysicsService:CollisionGroupSetCollidable(group.name, "WallstickNoCollision", false)
	end

	PhysicsService:CollisionGroupSetCollidable("WallstickCollision", "WallstickCollision", true)
end

local function createReplicationFocus(player: Player, originCF: CFrame, parent: Instance)
	if parent:FindFirstChild(`StreamingFocus_{player.UserId}`) then return end

	local part = Instance.new("Part")
	part.Name = `StreamingFocus_{player.UserId}`
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = originCF
	part.Parent = parent

	local attach = Instance.new("Attachment")
	attach.Parent = part

	local alignPosition = Instance.new("AlignPosition")
	alignPosition.Enabled = true
	alignPosition.MaxVelocity = 10_000_000
	alignPosition.Responsiveness = 200
	alignPosition.Position = originCF.Position
	alignPosition.Mode = Enum.PositionAlignmentMode.OneAttachment
	alignPosition.Attachment0 = attach
	alignPosition.Parent = part

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Enabled = true
	alignOrientation.MaxTorque = 10_000_000
	alignOrientation.Responsiveness = 200
	alignOrientation.CFrame = originCF
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.Attachment0 = attach
	alignOrientation.Parent = part

	if workspace.StreamingEnabled then
		player:AddReplicationFocus(part)
	end

	part:SetNetworkOwner(player)

	local connection
	connection = Players.PlayerRemoving:Connect(function(leavingPlayer)
		if leavingPlayer == player then
			connection:Disconnect()
			part:Destroy()
		end
	end)
end

local function setupWallstickModel(): Model
	local existing = workspace:FindFirstChild("Wallstick")
	if existing and existing:IsA("Model") then
		return existing
	end

	local wallstickModel = Instance.new("Model")
	wallstickModel.Name = "Wallstick"
	wallstickModel.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local origin = Instance.new("Part")
	origin.Name = "Origin"
	origin.CFrame = ORIGIN_CFRAME
	origin.Size = Vector3.new(1, 1, 1)
	origin.Transparency = 1
	origin.Anchored = true
	origin.CanCollide = false
	origin.CanTouch = false
	origin.CanQuery = false
	origin.Parent = wallstickModel

	local streamingFoci = Instance.new("Folder")
	streamingFoci.Name = "StreamingFoci"
	streamingFoci.Parent = wallstickModel

	wallstickModel.Parent = workspace
	return wallstickModel
end

setupCollisions()
local wallstickModel = setupWallstickModel()
local streamingFoci = wallstickModel:FindFirstChild("StreamingFoci") :: Folder

CharacterService.ForEachPlayer(function(player)
	createReplicationFocus(player, ORIGIN_CFRAME, streamingFoci)
end)

Replication.listenServer()

return WallstickService
