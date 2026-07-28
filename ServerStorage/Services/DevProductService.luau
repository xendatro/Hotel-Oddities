local DevProductService = {}

local MarketplaceService = game:GetService("MarketplaceService")
local ServerStorage = game:GetService("ServerStorage")

local DevProductConfigs = require(ServerStorage.Configs.DevProductConfigs)

-- Process receipt callback
local function processReceipt(receiptInfo)
	local player = game:GetService("Players"):GetPlayerByUserId(receiptInfo.PlayerId)
	
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	
	local productId = receiptInfo.ProductId
	local handler = DevProductConfigs[productId]
	
	if handler then
		local success, result = pcall(handler, player)
		
		if success then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		else
			warn("Error processing product " .. productId .. ": " .. tostring(result))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	else
		warn("No handler found for product ID: " .. productId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

-- Connect to ProcessReceipt
MarketplaceService.ProcessReceipt = processReceipt

return DevProductService
