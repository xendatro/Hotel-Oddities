local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local GemService = require(ServerStorage.Services.GemService)
local KitService = require(ServerStorage.Services.KitService)

local Purchase = CommunicationService.Get("Kits", "Purchase") :: RemoteEvent

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
	if not GemService:Spend(player, price) then return "InsufficientGems" end

	if not KitService:Grant(player, kitId) then
		GemService:Award(player, price)
		return "GrantFailed"
	end

	return "Purchased"
end

Purchase.OnServerEvent:Connect(function(player: Player, kitId: any)
	if type(kitId) ~= "string" then return end

	local result = KitShopService:Buy(player, kitId)
	GemService:Sync(player, result)
	KitService:Sync(player, result, kitId)
end)

return KitShopService
