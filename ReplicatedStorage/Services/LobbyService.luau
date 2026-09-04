local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)

local LobbyService = {}

if not RunService:IsClient() then
	return LobbyService
end

local LOBBY_FLOOR_TAG = "LobbyFloor"
local RAYCAST_DISTANCE = 8
local RAYCAST_ORIGIN_OFFSET = Vector3.new(0, 1, 0)

local LobbyRaycastParams = RaycastParams.new()
LobbyRaycastParams.FilterType = Enum.RaycastFilterType.Include
LobbyRaycastParams.IgnoreWater = true

local filterDirty = true

local function markFilterDirty()
	filterDirty = true
end

CollectionService:GetInstanceAddedSignal(LOBBY_FLOOR_TAG):Connect(markFilterDirty)
CollectionService:GetInstanceRemovedSignal(LOBBY_FLOOR_TAG):Connect(markFilterDirty)

function LobbyService:IsPlayerOnLobbyFloor(player: Player?): boolean
	local target = player or Players.LocalPlayer
	local root = CharacterService.GetAliveRoot(target)
	local humanoid = CharacterService.GetHumanoid(target.Character)
	if not humanoid or not root or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	if filterDirty then
		filterDirty = false
		LobbyRaycastParams.FilterDescendantsInstances = CollectionService:GetTagged(LOBBY_FLOOR_TAG)
	end
	local result = workspace:Raycast(
		root.Position + RAYCAST_ORIGIN_OFFSET,
		Vector3.new(0, -RAYCAST_DISTANCE, 0),
		LobbyRaycastParams
	)
	return result ~= nil
end

return LobbyService
