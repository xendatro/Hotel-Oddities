local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)

local KitStateService = {}

if not RunService:IsClient() then
	return KitStateService
end

local player = Players.LocalPlayer

local KitSync = CommunicationService.Get("Kits", "Sync") :: RemoteEvent
local Equip = CommunicationService.Get("Kits", "Equip") :: RemoteEvent
local Purchase = CommunicationService.Get("Kits", "Purchase") :: RemoteEvent
local RobuxPurchase = CommunicationService.Get("Kits", "RobuxPurchase") :: RemoteEvent
local Roll = CommunicationService.Get("Kits", "Roll") :: RemoteFunction
local GemSync = CommunicationService.Get("Gems", "Sync") :: RemoteEvent

local kitsChanged = Instance.new("BindableEvent")
local gemsChanged = Instance.new("BindableEvent")

local owned: { [string]: boolean } = { [KitConfig.DefaultKit] = true }
local equipped = KitConfig.DefaultKit
local gems = 0
local robuxPrices: { [string]: number | boolean } = {}

KitStateService.KitsChanged = kitsChanged.Event
KitStateService.GemsChanged = gemsChanged.Event

function KitStateService:IsOwned(kitId: string): boolean
	return owned[kitId] == true
end

function KitStateService:GetEquipped(): string
	return equipped
end

function KitStateService:GetGems(): number
	return gems
end

function KitStateService:CanAfford(kitId: string): boolean
	local kit = KitConfig.EntriesById[kitId]
	if not kit then return false end
	return gems >= KitConfig.GetRarity(kit).GemPrice
end

function KitStateService:CanRoll(): boolean
	return player:GetAttribute("CanRoll") == true
end

function KitStateService:Equip(kitId: string)
	Equip:FireServer(kitId)
end

function KitStateService:Buy(kitId: string)
	Purchase:FireServer(kitId)
end

function KitStateService:GetRobuxProduct(kitId: string): number?
	local kit = KitConfig.EntriesById[kitId]
	local productId = kit and MarketplaceService.Products.Kits[kit.Rarity]
	return if type(productId) == "number" and productId > 0 then productId else nil
end

function KitStateService:GetRobuxPrice(kitId: string): number?
	local kit = KitConfig.EntriesById[kitId]
	local productId = KitStateService:GetRobuxProduct(kitId)
	if not kit or not productId then return nil end

	local cached = robuxPrices[kit.Rarity]
	if type(cached) == "number" then return cached end
	if cached == true then return nil end

	robuxPrices[kit.Rarity] = true
	task.spawn(function()
		local success, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, productId, Enum.InfoType.Product)
		if not success or not info or type(info.PriceInRobux) ~= "number" then
			robuxPrices[kit.Rarity] = nil
			return
		end
		robuxPrices[kit.Rarity] = info.PriceInRobux
		kitsChanged:Fire()
	end)
	return nil
end

function KitStateService:BuyWithRobux(kitId: string)
	if not KitStateService:GetRobuxProduct(kitId) or owned[kitId] then return end
	RobuxPurchase:FireServer(kitId)
end

function KitStateService:RequestRoll(): { [string]: any }
	local success, result = pcall(Roll.InvokeServer, Roll)
	if not success or type(result) ~= "table" then
		return { Ok = false, Reason = "Failed" }
	end
	return result
end

KitSync.OnClientEvent:Connect(function(list: any, current: any, result: any, kitId: any)
	if type(list) == "table" then
		owned = { [KitConfig.DefaultKit] = true }
		for _, id in list do
			if type(id) == "string" then owned[id] = true end
		end
	end

	if type(current) == "string" and KitConfig.EntriesById[current] then
		equipped = current
	end

	kitsChanged:Fire(result, kitId)
end)

GemSync.OnClientEvent:Connect(function(amount: any, result: any)
	if type(amount) == "number" then gems = math.max(0, math.floor(amount)) end
	gemsChanged:Fire(result)
end)

player:GetAttributeChangedSignal("Gems"):Connect(function()
	local amount = player:GetAttribute("Gems")
	if type(amount) ~= "number" then return end
	gems = math.max(0, math.floor(amount))
	gemsChanged:Fire()
end)

player:GetAttributeChangedSignal("CanRoll"):Connect(function()
	kitsChanged:Fire()
end)

task.spawn(function()
	KitSync:FireServer()
	GemSync:FireServer()
end)

return KitStateService
