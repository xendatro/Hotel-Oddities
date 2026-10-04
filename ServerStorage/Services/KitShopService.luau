local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local GemService = require(ServerStorage.Services.GemService)
local KitService = require(ServerStorage.Services.KitService)

local Purchase = CommunicationService.Get("Kits", "Purchase") :: RemoteEvent
local RobuxPurchase = CommunicationService.Ensure("Kits", "RobuxPurchase", "RemoteEvent") :: RemoteEvent

local PRODUCTS = MarketplaceService.Products.Kits

local KitShopService = {}

function KitShopService:PriceOf(kitId: string): number?
	local kit = KitConfig.EntriesById[kitId]
	if not kit then return nil end
	return KitConfig.GetRarity(kit).GemPrice
end

function KitShopService:Buy(player: Player, kitId: string): string
	local kit = KitConfig.EntriesById[kitId]
	if not kit then return "UnknownKit" end
	if not DataSaveService:Get(player) then return "NotLoaded" end
	if KitService:Owns(player, kitId) then return "AlreadyOwned" end

	local price = KitConfig.GetRarity(kit).GemPrice
	if not GemService:Spend(player, price, kitId) then return "InsufficientGems" end

	if not KitService:Grant(player, kitId) then
		GemService:Refund(player, price)
		return "GrantFailed"
	end

	AnalyticsService:LogEvent(player, "KitPurchased", price, { Kit = kitId, Rarity = kit.Rarity, Currency = "Gems" })
	return "Purchased"
end

function KitShopService:ProductOf(kitId: string): number?
	local kit = KitConfig.EntriesById[kitId]
	local productId = kit and PRODUCTS[kit.Rarity]
	return if type(productId) == "number" and productId > 0 then productId else nil
end

local function pendingKits(profile): { [string]: string }
	local pending = profile.Data.PendingRobuxKits
	if type(pending) ~= "table" then
		pending = {}
		profile.Data.PendingRobuxKits = pending
	end
	return pending
end

local function processedReceipts(profile): { [string]: boolean }
	local processed = profile.Data.ProcessedKitReceipts
	if type(processed) ~= "table" then
		processed = {}
		profile.Data.ProcessedKitReceipts = processed
	end
	return processed
end

local function pickKit(player: Player, rarityId: string, requested: string?): string?
	local kit = requested and KitConfig.EntriesById[requested]
	if kit and kit.Rarity == rarityId and not KitService:Owns(player, kit.Id) then
		return kit.Id
	end

	local unowned = {}
	for _, entry in KitConfig.Entries do
		if entry.Rarity == rarityId and not KitService:Owns(player, entry.Id) then
			table.insert(unowned, entry.Id)
		end
	end
	return if #unowned > 0 then unowned[math.random(#unowned)] else nil
end

local function grantRobux(receiptInfo, rarityId: string): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local profile = DataSaveService:Get(player)
	if not profile then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local receiptId = tostring(receiptInfo.PurchaseId)
	local processed = processedReceipts(profile)
	if processed[receiptId] then return Enum.ProductPurchaseDecision.PurchaseGranted end

	local pending = pendingKits(profile)
	local kitId = pickKit(player, rarityId, pending[rarityId])

	if kitId then
		if not KitService:Grant(player, kitId) then return Enum.ProductPurchaseDecision.NotProcessedYet end
	else
		local rarity = KitConfig.RaritiesById[rarityId]
		if not rarity or not GemService:Award(player, rarity.GemPrice, false) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		GemService:Sync(player)
	end

	processed[receiptId] = true
	pending[rarityId] = nil

	if kitId then
		AnalyticsService:LogEvent(player, "KitPurchased", receiptInfo.CurrencySpent, {
			Kit = kitId,
			Rarity = rarityId,
			Currency = "Robux",
		})
	end
	KitService:Sync(player, "Purchased", kitId)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

Purchase.OnServerEvent:Connect(function(player: Player, kitId: any)
	if type(kitId) ~= "string" then return end

	local result = KitShopService:Buy(player, kitId)
	GemService:Sync(player, result)
	KitService:Sync(player, result, kitId)
end)

RobuxPurchase.OnServerEvent:Connect(function(player: Player, kitId: any)
	if type(kitId) ~= "string" then return end

	local kit = KitConfig.EntriesById[kitId]
	local productId = KitShopService:ProductOf(kitId)
	if not kit or not productId or KitService:Owns(player, kitId) then return end

	local profile = DataSaveService:Get(player)
	if not profile then return end

	pendingKits(profile)[kit.Rarity] = kitId
	MarketplaceService:PromptProductPurchase(player, productId)
end)

for rarityId, productId in PRODUCTS do
	if type(productId) ~= "number" or productId <= 0 then continue end

	MarketplaceService:CreateReceipt(productId, function(receiptInfo)
		return grantRobux(receiptInfo, rarityId)
	end)
end

return KitShopService
