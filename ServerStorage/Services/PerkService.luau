--- Everything the gamepasses actually do, and the one place anything asks who owns what.
---
--- Three of them are spawn-time facts about a player -- what they are carrying, how fast they walk --
--- and are applied below. The fourth, the unlimited Pathfinder, is a fact about a tool rather than a
--- spawn, so both halves of `Pathfinder` read their answer from here instead: the server through
--- `:Owns`, the client through the attribute this publishes.
---
--- Ownership is resolved once per player and cached, because every perk here is needed at the exact
--- moment a character arrives -- or, for the Pathfinder, inside a marker placement -- and asking
--- Roblox at either of those moments would spend a web round trip in the middle of something the
--- player is doing. A pass bought mid-round is picked up from the purchase signal, so nobody has to
--- rejoin to use what they just paid for.
---
--- The passes themselves live in `MarketplaceService.Gamepasses`, and what each is worth is tuned in
--- `ReplicatedStorage.Configs.PerkConfig`. A pass still sitting at id 0 is owned by nobody, so all of
--- this is inert until the passes exist on the site.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local InventoryService = require(ServerStorage.Services.InventoryService)
local LoadoutService = require(ServerStorage.Services.LoadoutService)
local SpeedBoostService = require(ServerStorage.Services.SpeedBoostService)

local PASSES = MarketplaceService.Gamepasses
local ATTRIBUTE_PREFIX = PerkConfig.AttributePrefix
local VISOR_TOOL = PerkConfig.Visor.ToolName
local SPEED_MULTIPLIER = PerkConfig.DoubleSpeed.Multiplier

--- Seconds a character will wait for its owner's passes to come back before spawning unperked. Only
--- ever reached if Roblox is refusing the ownership lookup outright.
local OWNERSHIP_TIMEOUT = 20

local PerkService = {}

-- [player] = { [pass name] = owns }. Absent while the lookup is still out.
local Owned: { [Player]: { [string]: boolean } } = {}
-- What a keep-items player was carrying when they died, waiting on a Backpack to put it back into.
local Kept: { [Player]: LoadoutService.Snapshot } = {}

--- Whether `player` owns a pass by its `Gamepasses` name. False while the lookup is still out, so
--- anything that must not spawn unperked should go through `WaitForPasses` first.
function PerkService:Owns(player: Player, passName: string): boolean
	local passes = Owned[player]
	return passes ~= nil and passes[passName] == true
end

--- Yields until `player`'s passes are known, and returns whether they arrived. False means the
--- lookup timed out and the caller should treat them as owning nothing.
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

	-- Published for the client halves that need the same answer -- the Pathfinder's counter has to
	-- know whether it is drawing a number or an infinity before it can draw anything. Written as
	-- nil rather than false where unowned, so the attribute list stays as short as what was bought.
	for passName, owns in passes do
		player:SetAttribute(ATTRIBUTE_PREFIX .. passName, owns or nil)
	end

	SpeedBoostService:SetMultiplier(player, if passes.DoubleSpeed then SPEED_MULTIPLIER else 1)
end

--- The perks ---------------------------------------------------------------------------------------

-- Written before any drink can be involved, so `SpeedBoostService` reads it as the player's ordinary
-- speed and scales its boosts from there rather than treating our write as somebody else's change.
local function applySpeed(player: Player, humanoid: Humanoid)
	if not PerkService:Owns(player, "DoubleSpeed") then return end
	if humanoid.Health <= 0 or humanoid.WalkSpeed <= 0 then return end

	humanoid.WalkSpeed *= SPEED_MULTIPLIER
end

-- Granted rather than equipped: the Eye only skips a player who has the visor OUT, so the pass buys
-- the item every round, not the protection.
local function applyVisor(player: Player)
	if not PerkService:Owns(player, "Visor") then return end
	if InventoryService:Get(player, VISOR_TOOL) then return end

	InventoryService:Add(player, VISOR_TOOL, 1)
end

local function applyKeptItems(player: Player)
	local snapshot = Kept[player]
	Kept[player] = nil
	if not snapshot or LoadoutService:IsEmpty(snapshot) then return end
	if not PerkService:Owns(player, "KeepItems") then return end

	LoadoutService:Restore(player, snapshot)
end

--- Wiring -----------------------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then return end

	humanoid.Died:Once(function()
		-- Captured for everybody, not just pass owners: a pass bought while dead should still give
		-- back the death that prompted it, and an unowned snapshot is dropped on the next spawn.
		Kept[player] = LoadoutService:Capture(player)
	end)

	if not PerkService:WaitForPasses(player) then return end
	if character.Parent == nil or player.Character ~= character then return end

	applySpeed(player, humanoid)
	-- Kept items first: the visor grant checks what the player is already holding, and a restored
	-- visor is one it should not duplicate.
	applyKeptItems(player)
	applyVisor(player)
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

-- A pass bought mid-round. Re-resolved rather than assumed, so a failed or cancelled purchase cannot
-- talk us into granting anything, and the perks land on the player's next spawn.
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, _, wasPurchased: boolean)
	if not wasPurchased or Owned[player] == nil then return end
	task.spawn(resolvePasses, player)
end)

return PerkService
