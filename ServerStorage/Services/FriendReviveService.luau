local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local MarketplaceService = require(ReplicatedStorage.Services.MarketplaceService)
local ReviveService = require(ServerStorage.Services.ReviveService)

local Communication = ReplicatedStorage.Communication.Revive
local Offer = Communication.Offer :: RemoteEvent
local Withdraw = Communication.Withdraw :: RemoteEvent
local Request = Communication.Request :: RemoteEvent

local CONFIG = PerkConfig.FriendRevive
local PRODUCT_ID = MarketplaceService.Products.ReviveFriend
local ENABLED = type(PRODUCT_ID) == "number" and PRODUCT_ID > 0

type Claim = {
	Target: Player,
	ExpiresAt: number,
}

local FriendReviveService = {}

local Offers: { [Player]: number } = {}
local Claims: { [Player]: Claim } = {}
local Friendships: { [string]: boolean } = {}

local function areFriends(player: Player, other: Player): boolean
	local key = `{player.UserId}:{other.UserId}`
	local cached = Friendships[key]
	if cached ~= nil then return cached end

	local success, result = pcall(player.IsFriendsWith, player, other.UserId)
	local friends = success and result == true
	Friendships[key] = friends
	Friendships[`{other.UserId}:{player.UserId}`] = friends
	return friends
end

local function close(target: Player)
	if Offers[target] == nil then return end
	Offers[target] = nil
	Withdraw:FireAllClients(target)
end

function FriendReviveService:Offer(target: Player)
	if not ENABLED then return end

	local expiresAt = os.clock() + CONFIG.Window
	Offers[target] = expiresAt

	task.delay(CONFIG.Window, function()
		if Offers[target] == expiresAt then
			Offers[target] = nil
		end
	end)

	for _, candidate in Players:GetPlayers() do
		if candidate == target then continue end

		task.spawn(function()
			if not areFriends(candidate, target) then return end
			if Offers[target] == nil then return end
			Offer:FireClient(candidate, target, CONFIG.Window)
		end)
	end
end

Request.OnServerEvent:Connect(function(player: Player, target: any)
	if not ENABLED then return end
	if typeof(target) ~= "Instance" or not target:IsA("Player") then return end
	if target == player or target.Parent ~= Players then return end

	local expiresAt = Offers[target]
	if not expiresAt or os.clock() > expiresAt then return end
	if not ReviveService:HasPendingDeath(target) then return end
	if not areFriends(player, target) then return end

	Claims[player] = {
		Target = target,
		ExpiresAt = os.clock() + CONFIG.PurchaseGrace,
	}

	MarketplaceService:PromptProductPurchase(player, PRODUCT_ID)
end)

if ENABLED then
	MarketplaceService:CreateReceipt(PRODUCT_ID, function(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not player then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		local claim = Claims[player]
		Claims[player] = nil

		if not claim or os.clock() > claim.ExpiresAt or claim.Target.Parent ~= Players then
			warn(`FriendReviveService: {player.Name} paid for a revive that can no longer be delivered`)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		close(claim.Target)
		ReviveService:Grant(claim.Target)

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)
end

Players.PlayerRemoving:Connect(function(player: Player)
	close(player)
	Claims[player] = nil

	for buyer, claim in Claims do
		if claim.Target == player then
			Claims[buyer] = nil
		end
	end
end)

return FriendReviveService
