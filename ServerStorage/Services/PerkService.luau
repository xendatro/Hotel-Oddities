local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CaptureConfig = require(ReplicatedStorage.Configs.CaptureConfig)
local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local InventoryService = require(ServerStorage.Services.InventoryService)
local LoadoutService = require(ServerStorage.Services.LoadoutService)
local SpeedBoostService = require(ServerStorage.Services.SpeedBoostService)

local PASSES = MarketplaceService.Gamepasses
local ATTRIBUTE_PREFIX = PerkConfig.AttributePrefix
local VISOR_TOOL = PerkConfig.Visor.ToolName
local CAMCORDER_TOOL = PerkConfig.Camcorder.ToolName
local SPEED_MULTIPLIER = PerkConfig.DoubleSpeed.Multiplier

local OWNERSHIP_TIMEOUT = 20

local PerkService = {}

local Owned: { [Player]: { [string]: boolean } } = {}
local Kept: { [Player]: LoadoutService.Snapshot } = {}

function PerkService:Owns(player: Player, passName: string): boolean
	local passes = Owned[player]
	return passes ~= nil and passes[passName] == true
end

function PerkService:WaitForPasses(player: Player): boolean
	local deadline = os.clock() + OWNERSHIP_TIMEOUT
	while Owned[player] == nil do
		if os.clock() >= deadline or player.Parent ~= Players then return false end
		task.wait()
	end
	return true
end

local function resolvePasses(player: Player)
	local passes = {}
	for passName, passId in PASSES do
		passes[passName] = MarketplaceService:UserOwnsGamePass(player, passId) == true
	end

	if player.Parent ~= Players then return end
	Owned[player] = passes

	for passName, owns in passes do
		player:SetAttribute(ATTRIBUTE_PREFIX .. passName, owns or nil)
	end

	SpeedBoostService:SetMultiplier(player, if passes.DoubleSpeed then SPEED_MULTIPLIER else 1)
end

local function applySpeed(player: Player, humanoid: Humanoid)
	if not PerkService:Owns(player, "DoubleSpeed") then return end
	if humanoid.Health <= 0 or humanoid.WalkSpeed <= 0 then return end

	humanoid.WalkSpeed *= SPEED_MULTIPLIER
end

local function applyVisor(player: Player)
	if not PerkService:Owns(player, "Visor") then return end
	if InventoryService:Get(player, VISOR_TOOL) then return end

	InventoryService:Add(player, VISOR_TOOL, 1)
end

local function applyCamcorder(player: Player)
	if CaptureConfig.RequireGamepass and not PerkService:Owns(player, "Camcorder") then return end
	if InventoryService:Get(player, CAMCORDER_TOOL) then return end
	InventoryService:Add(player, CAMCORDER_TOOL, 1)
end

local function applyKeptItems(player: Player)
	local snapshot = Kept[player]
	Kept[player] = nil
	if not snapshot or LoadoutService:IsEmpty(snapshot) then return end
	if not PerkService:Owns(player, "KeepItems") then return end

	LoadoutService:Restore(player, snapshot)
end

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	humanoid.Died:Once(function()
		Kept[player] = LoadoutService:Capture(player)
	end)

	if not PerkService:WaitForPasses(player) then return end
	if character.Parent == nil or player.Character ~= character then return end

	applySpeed(player, humanoid)
	applyKeptItems(player)
	applyVisor(player)
	applyCamcorder(player)
	InventoryService:EnsureSingle(player, "Walkie Talkie")
end

local function watchPlayer(player: Player)
	task.spawn(resolvePasses, player)

	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character: Model)
		task.spawn(onCharacterAdded, player, character)
	end)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

Players.PlayerRemoving:Connect(function(player: Player)
	Owned[player] = nil
	Kept[player] = nil
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, _, wasPurchased: boolean)
	if not wasPurchased or Owned[player] == nil then return end
	task.spawn(resolvePasses, player)
end)

return PerkService
