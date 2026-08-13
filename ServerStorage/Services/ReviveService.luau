--- What a revive IS, and the self-serve product that sells one. A death is kept in memory until
--- something spends it: where it happened and what the player was carrying at that moment.
---
--- Two products can spend the same death -- the player's own `Revive` and a friend's `ReviveFriend`,
--- which lives in `FriendReviveService` and calls `:Grant` here. Granting is public for exactly that
--- reason; the receipt below only covers the player buying their own way back.
---
--- Note a revive is not resurrection. Respawning is automatic and fast, so by the time a prompt has
--- been answered the player is usually already alive somewhere else -- what is actually being sold
--- is the trip back to where they fell, with their inventory and a few seconds of immunity.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local LoadoutService = require(ServerStorage.Services.LoadoutService)

local REVIVE_PRODUCT_ID = MarketplaceService.Products.Revive
local FORCE_FIELD_DURATION = DeathConfig.Revive.ForceFieldDuration
local CHARACTER_LOAD_TIMEOUT = 10

type DeathSnapshot = {
	Token: number,
	Location: CFrame,
	Items: LoadoutService.Snapshot,
}

local ReviveService = {}
local PendingDeaths: { [Player]: DeathSnapshot } = {}
local NextOfferId: { [Player]: number } = {}

local function loadLivingCharacter(player: Player): Model
	local character = LoadoutService:GetLivingCharacter(player)
	if character then return character end

	player:LoadCharacter()
	local deadline = os.clock() + CHARACTER_LOAD_TIMEOUT
	repeat
		character = LoadoutService:GetLivingCharacter(player)
		if character then return character end
		task.wait()
	until os.clock() >= deadline or player.Parent ~= Players

	error(`ReviveService: failed to load a character for {player.Name}`)
end

--- Saves everything needed to fulfill a revive. The prompt opens when the client's death screen
--- reports that it has fully finished, so the purchase UI does not interrupt the death screen. Returns
--- a token that identifies this death to the client's completion signal.
function ReviveService:Offer(player: Player, character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart")
	local location = if root and root:IsA("BasePart") then root.CFrame else character:GetPivot()
	local token = (NextOfferId[player] or 0) + 1
	NextOfferId[player] = token

	PendingDeaths[player] = {
		Token = token,
		Location = location,
		Items = LoadoutService:Capture(player),
	}

	return token
end

--- Opens the player's own revive purchase prompt for the pending death, if it is still available.
function ReviveService:Prompt(player: Player, token: number)
	local snapshot = PendingDeaths[player]
	if not snapshot or snapshot.Token ~= token then return end
	MarketplaceService:PromptProductPurchase(player, REVIVE_PRODUCT_ID)
end

--- Whether `player` has a death nobody has spent yet. What a friend's card is really offering to
--- buy, and false once anything has already paid for it.
function ReviveService:HasPendingDeath(player: Player): boolean
	return PendingDeaths[player] ~= nil
end

--- Puts `player` back on their feet and spends their pending death: full health, a force field, and
--- back where they fell with what they were carrying. Safe to call on a player who is already alive
--- somewhere else, which after a three second respawn is the normal case.
function ReviveService:Grant(player: Player)
	local snapshot = PendingDeaths[player]
	PendingDeaths[player] = nil

	local character = loadLivingCharacter(player)

	local forceField = Instance.new("ForceField")
	forceField.Name = "ReviveForceField"
	forceField.Visible = true
	forceField.Parent = character

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.Health = humanoid.MaxHealth

	if snapshot then
		character:PivotTo(snapshot.Location)
		if not LoadoutService:IsEmpty(snapshot.Items) then
			LoadoutService:Restore(player, snapshot.Items)
		end
	end

	task.delay(FORCE_FIELD_DURATION, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
end

assert(
	type(REVIVE_PRODUCT_ID) == "number" and REVIVE_PRODUCT_ID > 0,
	"MarketplaceService.Products.Revive must be a valid developer product ID"
)

MarketplaceService:CreateReceipt(REVIVE_PRODUCT_ID, function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	ReviveService:Grant(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end)

Players.PlayerRemoving:Connect(function(player: Player)
	PendingDeaths[player] = nil
	NextOfferId[player] = nil
end)

return ReviveService
