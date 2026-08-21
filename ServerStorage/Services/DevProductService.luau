local DevProductService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local DevProductConfigs = require(ServerStorage.Configs.DevProductConfigs)

for productId, handler in DevProductConfigs do
	MarketplaceService:CreateReceipt(productId, function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local success, result = pcall(handler, player)
		if not success then
			warn(`Error processing product {productId}: {result}`)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)
end

return DevProductService
