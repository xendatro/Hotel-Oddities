local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryService = require(script.Parent.InventoryService)

local PlayerLocatorConfig = require(ReplicatedStorage.Configs.PlayerLocatorConfig)

--- Owns the locator's teleport and the cooldown on it.
---
--- The client picks the target and nothing else. Both characters are re-checked here -- alive, in the
--- world, not the same one -- and the cooldown is measured on the server, so a client that never
--- draws a countdown still cannot teleport more than once a minute.
local PlayerLocatorService = {}

local Teleport = ReplicatedStorage.Communication.PlayerLocator.Teleport

local NextTeleport: { [Player]: number } = {}

local function isEquipped(player: Player): boolean
	local tool = InventoryService:Get(player, "Player Locator")
	return tool ~= nil and tool.Parent == player.Character
end

local function livingRoot(target: Player): BasePart?
	local character = target.Character
	if not character then return nil end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then return nil end

	return root
end

--- Seconds before `player` may teleport again, or 0 when they may now.
function PlayerLocatorService:GetCooldown(player: Player): number
	return math.max((NextTeleport[player] or 0) - os.clock(), 0)
end

--- Moves `player` to `target`, if everything is still true. Returns whether it happened.
function PlayerLocatorService:Teleport(player: Player, target: Player): boolean
	if target == player then return false end
	if self:GetCooldown(player) > 0 then return false end

	local root = livingRoot(player)
	local targetRoot = livingRoot(target)
	if not root or not targetRoot then return false end

	-- Behind them, facing the way they face: they are the first thing the arriving player sees.
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

	-- Answered either way. A refused request is still worth a reply: it is how a client whose
	-- countdown has drifted, or was never drawn, gets the real number back.
	Teleport:FireClient(player, PlayerLocatorService:GetCooldown(player))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	NextTeleport[player] = nil
end)

return PlayerLocatorService
