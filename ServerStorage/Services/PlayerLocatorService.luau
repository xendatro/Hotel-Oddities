local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local InventoryService = require(ServerStorage.Services.InventoryService)
local HallwayStreamingService = require(ServerStorage.Services.HallwayStreamingService)

local PlayerLocatorConfig = require(ReplicatedStorage.Configs.PlayerLocatorConfig)
local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local PlayerLocatorService = {}

local Teleport = CommunicationService.Get("PlayerLocator", "Teleport")

local NextTeleport: { [Player]: number } = {}

local function isEquipped(player: Player): boolean
	local tool = InventoryService:Get(player, "Player Locator")
	return tool ~= nil and tool.Parent == player.Character
end

local livingRoot = CharacterService.GetAliveRoot

function PlayerLocatorService:GetCooldown(player: Player): number
	return math.max((NextTeleport[player] or 0) - os.clock(), 0)
end

function PlayerLocatorService:Teleport(player: Player, target: Player): boolean
	if target == player then return false end
	if self:GetCooldown(player) > 0 then return false end

	local root = livingRoot(player)
	local targetRoot = livingRoot(target)
	if not root or not targetRoot then return false end

	local destination = targetRoot.CFrame * CFrame.new(0, 0, PlayerLocatorConfig.ArriveDistance)
	if not HallwayStreamingService:PrepareTeleport(player, destination.Position) then
		return false
	end

	root = livingRoot(player)
	targetRoot = livingRoot(target)
	if not root or not targetRoot then return false end
	root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, PlayerLocatorConfig.ArriveDistance)
	NextTeleport[player] = os.clock() + PlayerLocatorConfig.Cooldown
	return true
end

Teleport.OnServerEvent:Connect(function(player: Player, target: any)
	if not isEquipped(player) then
		Teleport:FireClient(player, PlayerLocatorService:GetCooldown(player))
		return
	end

	if typeof(target) == "Instance" and target:IsA("Player") and target:IsDescendantOf(Players) then
		PlayerLocatorService:Teleport(player, target)
	end

	Teleport:FireClient(player, PlayerLocatorService:GetCooldown(player))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	NextTeleport[player] = nil
end)

return PlayerLocatorService
