local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TagService = require(ReplicatedStorage.Services.TagService)

local ROOM_TAG = "Room"
local ROOM_LABEL = "Room"
local POLL_INTERVAL = 0.1
local BLOCKER_FOLDER = "RoomBlockers"
local ROOM_FOLDER_NAME = "Rooms"
local ROOM_BLOCKER_COLLISION_GROUP = "RoomBlocker"
local ENEMY_COLLISION_GROUP = "Enemies"
local PLAYER_COLLISION_GROUP = "Players"
local FURNITURE_COLLISION_GROUP = "Furniture"
local WALL_INSET = 1
local MAX_INSET_FRACTION = 0.25
local SAFE_PAD = 0.5

local RoomService = {}

type Room = {
	Model: Model,
	CFrame: CFrame,
	HalfSize: Vector3,
	Blocker: BasePart,
}

local PlayerRooms: { [Player]: Model } = {}
local Accumulator = 0

for _, groupName in {
	ROOM_BLOCKER_COLLISION_GROUP,
	ENEMY_COLLISION_GROUP,
	PLAYER_COLLISION_GROUP,
	FURNITURE_COLLISION_GROUP,
} do
	if not PhysicsService:IsCollisionGroupRegistered(groupName) then
		PhysicsService:RegisterCollisionGroup(groupName)
	end
end
PhysicsService:CollisionGroupSetCollidable(ROOM_BLOCKER_COLLISION_GROUP, ENEMY_COLLISION_GROUP, true)
PhysicsService:CollisionGroupSetCollidable(ROOM_BLOCKER_COLLISION_GROUP, "Default", false)
PhysicsService:CollisionGroupSetCollidable(ROOM_BLOCKER_COLLISION_GROUP, PLAYER_COLLISION_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(ROOM_BLOCKER_COLLISION_GROUP, FURNITURE_COLLISION_GROUP, false)
PhysicsService:CollisionGroupSetCollidable(ROOM_BLOCKER_COLLISION_GROUP, ROOM_BLOCKER_COLLISION_GROUP, false)

local Blockers = Instance.new("Folder")
Blockers.Name = BLOCKER_FOLDER
Blockers.Parent = workspace

local function isRoomModel(instance: Instance): boolean
	if not instance:IsA("Model") or not instance.Name:match("^Room_") then return false end
	local parent = instance.Parent
	return parent ~= nil and parent:IsA("Folder") and parent.Name == ROOM_FOLDER_NAME
end

local function tagRoomModel(instance: Instance)
	if isRoomModel(instance) and not instance:HasTag(ROOM_TAG) then
		instance:AddTag(ROOM_TAG)
	end
end

for _, descendant in workspace:GetDescendants() do
	tagRoomModel(descendant)
end
workspace.DescendantAdded:Connect(tagRoomModel)

local function insetHalfSize(size: Vector3): Vector3
	local half = size / 2
	return Vector3.new(
		half.X - math.min(WALL_INSET, half.X * MAX_INSET_FRACTION) + SAFE_PAD,
		half.Y - math.min(WALL_INSET, half.Y * MAX_INSET_FRACTION) + SAFE_PAD,
		half.Z - math.min(WALL_INSET, half.Z * MAX_INSET_FRACTION) + SAFE_PAD
	)
end

local function isInside(point: Vector3, room: Room): boolean
	local offset = room.CFrame:PointToObjectSpace(point)
	local half = room.HalfSize
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

local function isCharacterInside(character: Model, rooms): Model?
	for _, room in rooms do
		for _, part in character:GetChildren() do
			if part:IsA("BasePart") and isInside(part.Position, room) then
				return room.Model
			end
		end
	end
	return nil
end

TagService:Listen(ROOM_TAG, function(model: Model): Room
	local boundsCFrame, boundsSize = model:GetBoundingBox()

	local blocker = Instance.new("Part")
	blocker.Name = `{model.Name}Blocker`
	blocker.Anchored = true
	blocker.CanCollide = true
	blocker.CanQuery = true
	blocker.CanTouch = false
	blocker.AudioCanCollide = false
	blocker.CastShadow = false
	blocker.CollisionGroup = ROOM_BLOCKER_COLLISION_GROUP
	blocker.Transparency = 1
	blocker.Size = boundsSize
	blocker.CFrame = boundsCFrame

	local modifier = Instance.new("PathfindingModifier")
	modifier.Name = "RoomBlocker"
	modifier.Label = ROOM_LABEL
	modifier.PassThrough = false
	modifier.Parent = blocker
	blocker.Parent = Blockers

	return {
		Model = model,
		CFrame = boundsCFrame,
		HalfSize = insetHalfSize(boundsSize),
		Blocker = blocker,
	}
end, function(_model: Instance, room: Room)
	room.Blocker:Destroy()
end, workspace)

function RoomService:GetRooms(): { Model }
	local rooms = {}
	for model in TagService:GetAllApplied(ROOM_TAG) do
		table.insert(rooms, model :: Model)
	end
	return rooms
end

function RoomService:GetRoom(player: Player): Model?
	return PlayerRooms[player]
end

function RoomService:IsInRoom(player: Player): boolean
	return PlayerRooms[player] ~= nil
end

function RoomService:IsNearOccupiedRoom(position: Vector3, distance: number): boolean
	local distanceSquared = distance * distance
	for _, room in PlayerRooms do
		if not room or not room:IsDescendantOf(workspace) then continue end

		local boundsCFrame, boundsSize = room:GetBoundingBox()
		local localPosition = boundsCFrame:PointToObjectSpace(position)
		local dx = math.max(math.abs(localPosition.X) - boundsSize.X / 2, 0)
		local dz = math.max(math.abs(localPosition.Z) - boundsSize.Z / 2, 0)
		if dx * dx + dz * dz <= distanceSquared then return true end
	end
	return false
end

function RoomService:GetDoorway(room: Model): Model?
	local suffix = room.Name:match("^Room_(.+)$")
	local nearest: Model? = nil
	local nearestDistance = math.huge
	local roomPosition = room:GetPivot().Position

	for _, instance in CollectionService:GetTagged("Doorway") do
		if not instance:IsA("Model") or not instance:HasTag("RoomDoor") then continue end
		local doorway = instance :: Model
		if suffix and doorway.Name == `Doorway_{suffix}` then
			return doorway
		end

		local position = doorway:GetPivot().Position
		if math.abs(position.Y - roomPosition.Y) <= 8 then
			local distance = (position - roomPosition).Magnitude
			if distance < nearestDistance then
				nearest, nearestDistance = doorway, distance
			end
		end
	end

	return nearest
end

function RoomService:GetDoorApproach(room: Model, agentRadius: number): (Vector3?, Vector3?)
	local doorway = self:GetDoorway(room)
	if not doorway then return nil, nil end

	local threshold = doorway:FindFirstChild("Threshold", true)
	local thresholdPart: BasePart? = if threshold and threshold:IsA("BasePart") then threshold else nil
	local doorPosition = if thresholdPart then thresholdPart.Position else doorway:GetPivot().Position
	local roomCFrame = room:GetBoundingBox()
	local outward = Vector3.new(doorPosition.X - roomCFrame.Position.X, 0, doorPosition.Z - roomCFrame.Position.Z)
	if outward.Magnitude < 1e-3 then
		outward = Vector3.new(doorway:GetPivot().Position.X - roomCFrame.Position.X, 0, doorway:GetPivot().Position.Z - roomCFrame.Position.Z)
	end
	if outward.Magnitude < 1e-3 then return nil, nil end

	local distance = math.max(agentRadius + 0.75, 3.25)
	local approach = doorPosition + outward.Unit * distance
	return Vector3.new(approach.X, doorPosition.Y, approach.Z), doorPosition
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < POLL_INTERVAL then return end
	Accumulator = 0

	local rooms = TagService:GetAllApplied(ROOM_TAG)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		PlayerRooms[player] = if character then isCharacterInside(character, rooms) else nil
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	PlayerRooms[player] = nil
end)

return RoomService
