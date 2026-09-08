local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MirrorRoomService = {}

if not RunService:IsClient() then
	return MirrorRoomService
end

local MirrorRoomConfig = require(ReplicatedStorage.Configs.MirrorRoomConfig)
local MirrorRoom = require(ReplicatedStorage.Classes.MirrorRoom)
local TagService = require(ReplicatedStorage.Services.TagService)

TagService:Listen(MirrorRoomConfig.Tag, function(instance: Instance)
	if not instance:IsA("Model") then return nil end
	return MirrorRoom.new(instance)
end, function(_, object: any)
	if object then object:Destroy() end
end, workspace)

return MirrorRoomService
