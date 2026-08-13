local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local InventoryService = require(ServerStorage.Services.InventoryService)

local Communication = ReplicatedStorage.Communication.Items
local Purchase = Communication.Purchase :: RemoteEvent
local Sync = Communication.Sync :: RemoteEvent

local ItemShopService = {}

local function getCoins(profile): number
	local coins = tonumber(profile.Data.Coins) or ItemShopConfig.StartingCoins
	return math.max(0, math.floor(coins))
end

function ItemShopService:Sync(player: Player, result: string?, itemId: string?)
	local profile = DataSaveService:Get(player)
	if not profile then return end

	local coins = getCoins(profile)
	profile.Data.Coins = coins
	player:SetAttribute("Coins", coins)
	Sync:FireClient(player, coins, result, itemId)
end

local function grant(player: Player, itemId: string): boolean
	if not ItemShopConfig.EntriesById[itemId] then return false end
	return InventoryService:Add(player, itemId, 1)
end

Purchase.OnServerEvent:Connect(function(player: Player, itemId: any)
	if type(itemId) ~= "string" then return end
	if not InventoryService:Wait(player, 10) then return end

	local entry = ItemShopConfig.EntriesById[itemId]
	if not entry then return end

	local profile = DataSaveService:Get(player)
	if not profile then return end

	local coins = getCoins(profile)
	if coins < entry.CoinPrice then
		ItemShopService:Sync(player, "InsufficientCoins", itemId)
		return
	end

	if not grant(player, itemId) then
		ItemShopService:Sync(player, "InventoryFull", itemId)
		return
	end

	profile.Data.Coins = coins - entry.CoinPrice
	ItemShopService:Sync(player, "Purchased", itemId)
end)

Sync.OnServerEvent:Connect(function(player: Player)
	ItemShopService:Sync(player)
end)

for _, entry in ItemShopConfig.Entries do
	local productId = MarketplaceService.Products.Items[entry.Product]
	if type(productId) ~= "number" or productId <= 0 then continue end

	MarketplaceService:CreateReceipt(productId, function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
		if not InventoryService:Wait(player, 10) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local profile = DataSaveService:Get(player)
		if not profile then return Enum.ProductPurchaseDecision.NotProcessedYet end

		local receiptId = tostring(receiptInfo.PurchaseId)
		if profile.Data.ProcessedItemReceipts[receiptId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		if not grant(player, entry.Id) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		profile.Data.ProcessedItemReceipts[receiptId] = true
		ItemShopService:Sync(player, "Purchased", entry.Id)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)
end

local function publish(player: Player)
	DataSaveService:Wait(player)
	if player.Parent == Players then ItemShopService:Sync(player) end
end

for _, player in Players:GetPlayers() do
	task.spawn(publish, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(publish, player)
end)

return ItemShopService
