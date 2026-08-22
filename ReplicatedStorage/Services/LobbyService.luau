local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

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

function LobbyService:IsPlayerOnLobbyFloor(player: Player?): boolean
	local target = player or Players.LocalPlayer
	local character = target.Character
	if not character then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end

	LobbyRaycastParams.FilterDescendantsInstances = CollectionService:GetTagged(LOBBY_FLOOR_TAG)
	local result = workspace:Raycast(
		root.Position + RAYCAST_ORIGIN_OFFSET,
		Vector3.new(0, -RAYCAST_DISTANCE, 0),
		LobbyRaycastParams
	)
	return result ~= nil
end

return LobbyService
