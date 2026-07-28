local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TagService = require(ReplicatedStorage.Services.TagService)

local ROOM_TAG = "Room"
local ROOM_LABEL = "Room" -- pathfinding label; enemy agents price this at math.huge
local POLL_INTERVAL = 0.1

--- Owns the `Room` tag: the safe zones players duck into to break an enemy's interest. Rooms are
--- plain block parts in workspace; occupancy is polled rather than driven by touch events so it
--- stays correct for non-collidable volumes and teleports alike.
local RoomService = {}

local PlayerRooms: { [Player]: BasePart } = {}
local Accumulator = 0

local function isInside(point: Vector3, part: BasePart): boolean
	local offset = part.CFrame:PointToObjectSpace(point)
	local half = part.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- Every room doubles as a pathfinding blocker so enemies never route a path through a safe zone.
TagService:Listen(ROOM_TAG, function(part: BasePart)
	local modifier = Instance.new("PathfindingModifier")
	modifier.Name = "RoomBlocker"
	modifier.Label = ROOM_LABEL
	modifier.PassThrough = false
	modifier.Parent = part
	return modifier
end, function(_part: Instance, modifier: PathfindingModifier)
	modifier:Destroy()
end, workspace)

--- Every part currently tagged as a room.
function RoomService:GetRooms(): { BasePart }
	local rooms = {}
	for part in TagService:GetAllApplied(ROOM_TAG) do
		table.insert(rooms, part)
	end
	return rooms
end

--- The room a player is standing in, or nil if they are out in the open.
function RoomService:GetRoom(player: Player): BasePart?
	return PlayerRooms[player]
end

--- Whether a player is currently safe from enemies that respect rooms.
function RoomService:IsInRoom(player: Player): boolean
	return PlayerRooms[player] ~= nil
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	Accumulator += deltaTime
	if Accumulator < POLL_INTERVAL then return end
	Accumulator = 0

	local rooms = TagService:GetAllApplied(ROOM_TAG)
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local occupied = nil
		if root then
			for part in rooms do
				if isInside(root.Position, part) then
					occupied = part
					break
				end
			end
		end
		PlayerRooms[player] = occupied
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	PlayerRooms[player] = nil
end)

return RoomService
