local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TagService = require(ReplicatedStorage.Services.TagService)

local ROOM_TAG = "Room"
local ROOM_LABEL = "Room" -- pathfinding label; enemy agents price this at math.huge
local POLL_INTERVAL = 0.1
local BLOCKER_FOLDER = "RoomBlockers"
-- Studs trimmed off every face of a room's bounds before anybody counts as inside it. The box reaches
-- the outer face of the walls, and the far side of a wall is not the room.
local WALL_INSET = 1
-- ...but never more than this much of an axis, so a cupboard does not inset itself out of existence.
local MAX_INSET_FRACTION = 0.25
-- Studs added back onto every face of the inset box so the safe volume slightly overhangs the walls.
local SAFE_PAD = 0.5

--- Owns the `Room` tag: the safe zones players duck into to break an enemy's interest. Rooms are the
--- room models themselves, and occupancy is the model's own bounding box rather than a separate
--- volume placed alongside it -- one less thing to keep in sync, and a room nobody remembered to put
--- a marker in is a room enemies walk straight into.
---
--- Occupancy is polled rather than driven by touch events so it stays correct for teleports and for
--- volumes nothing can touch.
local RoomService = {}

type Room = {
	Model: Model,
	CFrame: CFrame, -- of the bounding box, which is oriented, so containment is done in its space
	HalfSize: Vector3, -- already inset, so the test is three comparisons
	Blocker: BasePart,
}

local PlayerRooms: { [Player]: Model } = {}
local Accumulator = 0

local Blockers = Instance.new("Folder")
Blockers.Name = BLOCKER_FOLDER
Blockers.Parent = workspace

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

-- True if any body part of `character` is inside `room`. Falls back to nil if the character has no
-- parts yet, so a partially loaded avatar never reports a stale room.
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

--- Every room doubles as a pathfinding blocker so enemies never route a path through a safe zone.
---
--- A `PathfindingModifier` only labels the single part it hangs on, and a room is a model, so the
--- volume it needs is built here instead of being placed by hand: one invisible box matching the
--- model's bounds. That is exactly the safe-zone part this used to ask a mapper to keep in sync with
--- the room it belonged to, minus the asking. It lives outside the model so that re-reading the
--- model's bounds never measures the blocker as part of the room.
---
--- Bounds are measured once, when the tag is applied. A room is built and then stands still; a model
--- that is still being assembled when it is tagged measures whatever exists at that moment.
TagService:Listen(ROOM_TAG, function(model: Model): Room
	local boundsCFrame, boundsSize = model:GetBoundingBox()

	local blocker = Instance.new("Part")
	blocker.Name = `{model.Name}Blocker`
	blocker.Anchored = true
	blocker.CanCollide = false
	blocker.CanQuery = false -- sight is measured through rooms; this is for pathfinding and nothing else
	blocker.CanTouch = false
	blocker.CastShadow = false
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

--- Every model currently tagged as a room.
function RoomService:GetRooms(): { Model }
	local rooms = {}
	for model in TagService:GetAllApplied(ROOM_TAG) do
		table.insert(rooms, model :: Model)
	end
	return rooms
end

--- The room a player is standing in, or nil if they are out in the open.
function RoomService:GetRoom(player: Player): Model?
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
		PlayerRooms[player] = if character then isCharacterInside(character, rooms) else nil
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	PlayerRooms[player] = nil
end)

return RoomService
