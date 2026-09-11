local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local StoreConfig = require(ReplicatedStorage.Configs.StoreConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local GemService = require(ServerStorage.Services.GemService)

local GemShopService = {}

local function grant(receiptInfo, amount: number): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local profile = DataSaveService:Get(player)
	if not profile then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local receiptId = tostring(receiptInfo.PurchaseId)
	if profile.Data.ProcessedGemReceipts[receiptId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	if not GemService:Award(player, amount, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	profile.Data.ProcessedGemReceipts[receiptId] = true
	GemService:Sync(player, StoreConfig.GemPurchaseResult)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

for amount, productId in MarketplaceService.Products.Gems do
	if type(amount) ~= "number" or type(productId) ~= "number" or productId <= 0 then continue end

	MarketplaceService:CreateReceipt(productId, function(receiptInfo)
		return grant(receiptInfo, amount)
	end)
end

return GemShopService
