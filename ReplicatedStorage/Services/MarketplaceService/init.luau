local _MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local extend = require(ReplicatedStorage.Modules.extend)

local CACHE = {}
local PRODUCTS = {}

local MarketplaceService = {}

MarketplaceService.Gamepasses = require(script.Gamepasses)
MarketplaceService.Products = require(script.Products)
local MarketplaceIds = {
	Passes = MarketplaceService.Gamepasses,
	Products = MarketplaceService.Products,
}
local VIP_GAMEPASS_ID = MarketplaceService.Gamepasses.VIP
local LEGACY_VIP_SUBSCRIPTION_ID = "EXP-3498472065697186291"

local function userOwnsLegacyVIPSubscription(player: Player): boolean
	local success, status = pcall(function()
		return _MarketplaceService:GetUserSubscriptionStatusAsync(player, LEGACY_VIP_SUBSCRIPTION_ID)
	end)
	return success and status and status.IsSubscribed == true
end

local function getPromptRemote(name: string): RemoteEvent
	if RunService:IsServer() then
		local existing = script:FindFirstChild(name)
		if existing then
			return existing :: RemoteEvent
		end

		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = script
		return remote
	end

	return script:WaitForChild(name) :: RemoteEvent
end

local PromptProductPurchase = getPromptRemote("PromptProductPurchase")
local PromptGamePassPurchase = getPromptRemote("PromptGamePassPurchase")

local GamePassSync
if RunService:IsServer() then
	GamePassSync = script:FindFirstChild("GamePassSync")
	if not GamePassSync then
		GamePassSync = Instance.new("RemoteEvent")
		GamePassSync.Name = "GamePassSync"
		GamePassSync.Parent = script
	end
else
	GamePassSync = script:WaitForChild("GamePassSync")
end

export type ReceiptInfo = {
	PurchaseId: number,
	PlayerId: number,
	ProductId: number,
	PlaceId: number,
	CurrencySpent: number,
	CurrencyType: number,
	ProductPurchaseChannel: Enum.ProductPurchaseChannel
}

export type ProductInfo = {
	AssetId: number,
	AssetTypeId: number,
	Created: string,
	Creator: {
		CreatorTargetId: number,
		CreatorType: Enum.CreatorType,
		HasVerifiedBadge: boolean?,
		Name: string,
	},
	DisplayIconImageAssetId: number,
	DisplayName: string,
	IconImageAssetId: number,
	IsForSale: boolean,
	IsLimited: boolean,
	IsLimitedUnique: boolean,
	IsNew: boolean,
	IsPublicDomain: boolean,
	MinimumMembershipLevel: number,
	Name: string,
	PriceInRobux: number,
	ProductId: number,
	ProductType: Enum.InfoType,
	TargetId: number,
	Updated: string,
}

local productPurchased: RBXScriptConnection = nil

local function forEachProductId(products, callback)
	for _, value in products do
		if typeof(value) == "number" then
			if value > 0 then
				callback(value)
			end
		elseif typeof(value) == "table" then
			forEachProductId(value, callback)
		end
	end
end

function MarketplaceService:PromptProductPurchase(player: Player, productId: number)
	if RunService:IsServer() then
		PromptProductPurchase:FireClient(player, productId)
	else
		if productPurchased then
			productPurchased:Disconnect()
		end
		_MarketplaceService:PromptProductPurchase(player, productId)
		productPurchased = _MarketplaceService.PromptProductPurchaseFinished:Once(function(_, _, isPurchased)
			if isPurchased then
			end
		end)
	end
end

function MarketplaceService:PromptGamePassPurchase(player: Player, gamePassId: number)
	if RunService:IsServer() then
		PromptGamePassPurchase:FireClient(player, gamePassId)
	else
		_MarketplaceService:PromptGamePassPurchase(player, gamePassId)
		_MarketplaceService.PromptGamePassPurchaseFinished:Once(function(_, _, wasPurchased)
			if wasPurchased then
			end
		end)
	end
end

function MarketplaceService:UserOwnsGamePass(player: Player|number, gamePassId: number): boolean
	if typeof(gamePassId) ~= "number" or gamePassId <= 0 then
		return false
	end

	if typeof(player) == "number" then
		if Players:GetPlayerByUserId(player) then
			player = Players:GetPlayerByUserId(player)
		else
			return _MarketplaceService:UserOwnsGamePassAsync(player, gamePassId)
		end
	end
	if CACHE[player] and CACHE[player][gamePassId] == true then
		return true
	end
	if RunService:IsServer() and gamePassId == VIP_GAMEPASS_ID and userOwnsLegacyVIPSubscription(player) then
		if not CACHE[player] then
			CACHE[player] = {}
		end
		CACHE[player][gamePassId] = true
		GamePassSync:FireAllClients("UpdatePass", player, gamePassId, true)
		return true
	end
	if CACHE[player] and CACHE[player][gamePassId] ~= nil then
		return CACHE[player][gamePassId]
	end

	if RunService:IsClient() then
		local bindable = Instance.new("BindableEvent")
		local connection
		connection = GamePassSync.OnClientEvent:Connect(function(action, targetPlayer, passId, owns)
			if action == "UpdatePass" and targetPlayer == player and passId == gamePassId then
				bindable:Fire(owns)
			end
		end)

		GamePassSync:FireServer("CheckGamePass", player, gamePassId)

		task.delay(10, function()
			if connection.Connected then
				bindable:Fire(false)
			end
		end)

		local owns = bindable.Event:Wait()
		connection:Disconnect()
		bindable:Destroy()

		return owns
	end

	local success, result
	local tries = 0
	repeat
		success, result = pcall(function()
			return _MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
		end)
		tries += 1
		if not success then task.wait() end
	until success or tries == 10

	local owns = false
	if success then
		owns = result
	end

	if not CACHE[player] then
		CACHE[player] = {}
	end
	CACHE[player][gamePassId] = owns

	GamePassSync:FireAllClients("UpdatePass", player, gamePassId, owns)

	return owns
end

function MarketplaceService:GetProductInfo(id: number, infoType: Enum.InfoType?): ProductInfo
	if infoType then
		return _MarketplaceService:GetProductInfoAsync(id, infoType)
	else
		return PRODUCTS[id]
	end
end

_MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId, wasPurchased)
	if not wasPurchased then return end
	if not CACHE[player] then
		CACHE[player] = {}
	end
	CACHE[player][gamePassId] = true

	if RunService:IsServer() then
		GamePassSync:FireAllClients("UpdatePass", player, gamePassId, true)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	if CACHE[player] then
		CACHE[player] = nil
	end
end)

if RunService:IsClient() then
	PromptGamePassPurchase.OnClientEvent:Connect(function(gamePassId)
		MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, gamePassId)
	end)
	PromptProductPurchase.OnClientEvent:Connect(function(productId)
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
	end)

	GamePassSync.OnClientEvent:Connect(function(action, arg1, arg2, arg3)
		if action == "FullSync" then
			local serverCache = arg1
			for plr, passes in pairs(serverCache) do
				if not CACHE[plr] then CACHE[plr] = {} end
				for passId, owns in pairs(passes) do
					CACHE[plr][passId] = owns
				end
			end
		elseif action == "UpdatePass" then
			local plr = arg1
			local passId = arg2
			local owns = arg3

			if not CACHE[plr] then CACHE[plr] = {} end
			CACHE[plr][passId] = owns
		end
	end)

	GamePassSync:FireServer("RequestSync")

	forEachProductId(MarketplaceIds.Products, function(id)
		task.defer(function()
			local success, result
			repeat
				success, result = pcall(function()
					return _MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.Product)
				end)
				task.wait(1)
			until success

			if success then
				PRODUCTS[id] = result
			end
		end)
	end)

	extend(MarketplaceService, _MarketplaceService)
	return MarketplaceService:: typeof(MarketplaceService) & typeof(_MarketplaceService)
end

local Functions = {}

function MarketplaceService:CreateReceipt(productId: number, f: (receiptInfo: ReceiptInfo) -> Enum.ProductPurchaseDecision)
	assert(productId ~= nil, "Argument 1 is nil")
	assert(f ~= nil, "Argument 2 is nil")
	Functions[productId] = f
end

function MarketplaceService:DeleteReceipt(productId: number)
	if Functions[productId] then
		Functions[productId] = nil
	end
end

_MarketplaceService.ProcessReceipt = function(receiptInfo: ReceiptInfo)
	print(Functions, receiptInfo)
	if Functions["ALL"] then
		task.defer(function()
			Functions["ALL"](receiptInfo)
		end)
	end
	if Functions[receiptInfo.ProductId] then
		return Functions[receiptInfo.ProductId](receiptInfo)
	end
	warn(`Product function not found: {receiptInfo.ProductId}`)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

GamePassSync.OnServerEvent:Connect(function(client, action, targetPlayer, passId)
	if action == "RequestSync" then
		GamePassSync:FireClient(client, "FullSync", CACHE)
	elseif action == "CheckGamePass" then
		if CACHE[targetPlayer] and CACHE[targetPlayer][passId] ~= nil then
			GamePassSync:FireClient(client, "UpdatePass", targetPlayer, passId, CACHE[targetPlayer][passId])
		else
			MarketplaceService:UserOwnsGamePass(targetPlayer, passId)
		end
	end
end)

local function initPlayerCache(player)
	if not CACHE[player] then CACHE[player] = {} end
	if MarketplaceIds.Passes then
		for _, passId in pairs(MarketplaceIds.Passes) do
			if typeof(passId) ~= "number" or passId <= 0 then continue end
			task.spawn(function()
				MarketplaceService:UserOwnsGamePass(player, passId)
			end)
		end
	end
end

Players.PlayerAdded:Connect(initPlayerCache)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(initPlayerCache, player)
end

extend(MarketplaceService, _MarketplaceService)
local metatable = getmetatable(MarketplaceService)
local newindexFunction = metatable.__newindex
metatable.__newindex = function(t, i, v)
	if i == "ProcessReceipt" then
		error("Cannot assign to native ProcessReceipt")
	end
	newindexFunction(t, i, v)
end

local module: typeof(MarketplaceService) & typeof(_MarketplaceService) = MarketplaceService
return module
