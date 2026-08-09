local DevProductService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local DevProductConfigs = require(ServerStorage.Configs.DevProductConfigs)

-- Every product shares the receipt router in ReplicatedStorage.Services.MarketplaceService. Roblox
-- only allows one ProcessReceipt callback, so assigning the native callback here would silently
-- replace products registered by other services.
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
