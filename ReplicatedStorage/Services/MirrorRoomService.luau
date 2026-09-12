local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MirrorRoomConfig = require(ReplicatedStorage.Configs.MirrorRoomConfig)
local MirrorRoom = require(ReplicatedStorage.Classes.MirrorRoom)

local MirrorRoomService = {}

export type Bounds = MirrorRoom.Bounds

MirrorRoomService.GetBounds = MirrorRoom.GetBounds
MirrorRoomService.IsInside = MirrorRoom.IsInside
MirrorRoomService.MirrorPoint = MirrorRoom.MirrorPoint

function MirrorRoomService.GetRooms(): { Model }
	local rooms = {}
	for _, instance in CollectionService:GetTagged(MirrorRoomConfig.Tag) do
		if instance:IsA("Model") and instance:IsDescendantOf(workspace) then
			table.insert(rooms, instance)
		end
	end
	return rooms
end

function MirrorRoomService.GetRoomAt(position: Vector3): (Model?, Bounds?)
	for _, room in MirrorRoomService.GetRooms() do
		local bounds = MirrorRoom.GetBounds(room)
		if bounds and MirrorRoom.IsInside(bounds, position) then
			return room, bounds
		end
	end
	return nil, nil
end

if not RunService:IsClient() then
	return MirrorRoomService
end

local TagService = require(ReplicatedStorage.Services.TagService)

TagService:Listen(MirrorRoomConfig.Tag, function(instance: Instance)
	if not instance:IsA("Model") then return nil end
	return MirrorRoom.new(instance)
end, function(_, object: any)
	if object then object:Destroy() end
end, workspace)

return MirrorRoomService
