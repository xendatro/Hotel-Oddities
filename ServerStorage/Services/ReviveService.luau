--- Offers and grants the revive developer product. A death is kept in memory until its matching
--- purchase arrives: where it happened and the item stacks the player held at that moment.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DeathConfig = require(ReplicatedStorage.Configs.DeathConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local REVIVE_PRODUCT_ID = MarketplaceService.Products.Revive
local FORCE_FIELD_DURATION = DeathConfig.Revive.ForceFieldDuration
local CHARACTER_LOAD_TIMEOUT = 10

type ItemSnapshot = { [string]: number }
type DeathSnapshot = {
	Location: CFrame,
	Items: ItemSnapshot,
}

local ReviveService = {}
local PendingDeaths: { [Player]: DeathSnapshot } = {}

local function captureItems(player: Player): ItemSnapshot
	local items = {}
	for name, tool in InventoryService:GetAll(player) do
		items[name] = tool:GetAttribute("quantity") or 1
	end
	return items
end

local function getLivingCharacter(player: Player): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return character
	end
	return nil
end

local function loadLivingCharacter(player: Player): Model
	local character = getLivingCharacter(player)
	if character then return character end

	player:LoadCharacter()
	local deadline = os.clock() + CHARACTER_LOAD_TIMEOUT
	repeat
		character = getLivingCharacter(player)
		if character then return character end
		task.wait()
	until os.clock() >= deadline or player.Parent ~= Players

	error(`ReviveService: failed to load a character for {player.Name}`)
end

-- Restore at least the quantity held at death. This does not delete items earned after an automatic
-- respawn while the purchase prompt was still open.
local function restoreItems(player: Player, snapshot: ItemSnapshot)
	local backpack = player:FindFirstChildOfClass("Backpack")
		or player:WaitForChild("Backpack", CHARACTER_LOAD_TIMEOUT)
	if not backpack or not backpack:IsA("Backpack") then
		error(`ReviveService: failed to load a backpack for {player.Name}`)
	end

	for name, quantityAtDeath in snapshot do
		local current = InventoryService:Get(player, name)
		local currentQuantity = if current then current:GetAttribute("quantity") or 1 else 0
		local missing = quantityAtDeath - currentQuantity
		if missing > 0 then
			InventoryService:Add(player, name, missing)
		end
	end
end

local function grantRevive(player: Player, snapshot: DeathSnapshot?)
	local character = loadLivingCharacter(player)

	local forceField = Instance.new("ForceField")
	forceField.Name = "ReviveForceField"
	forceField.Visible = true
	forceField.Parent = character

	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.Health = humanoid.MaxHealth

	if snapshot then
		character:PivotTo(snapshot.Location)
		restoreItems(player, snapshot.Items)
	end

	task.delay(FORCE_FIELD_DURATION, function()
		if forceField.Parent then
			forceField:Destroy()
		end
	end)
end

--- Saves everything needed to fulfill a revive, then opens the product prompt on that player.
function ReviveService:Offer(player: Player, character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	local location = if root and root:IsA("BasePart") then root.CFrame else character:GetPivot()

	PendingDeaths[player] = {
		Location = location,
		Items = captureItems(player),
	}

	MarketplaceService:PromptProductPurchase(player, REVIVE_PRODUCT_ID)
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

	local snapshot = PendingDeaths[player]
	grantRevive(player, snapshot)
	PendingDeaths[player] = nil

	return Enum.ProductPurchaseDecision.PurchaseGranted
end)

Players.PlayerRemoving:Connect(function(player: Player)
	PendingDeaths[player] = nil
end)

return ReviveService
