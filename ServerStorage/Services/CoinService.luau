local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local AnalyticsConfig = require(ServerStorage.Configs.AnalyticsConfig)
local AnalyticsService = require(ServerStorage.Services.AnalyticsService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local CoinService = {}

local ATTRIBUTE = "Coins"
local CURRENCY = AnalyticsConfig.Economy.Currencies.Coins
local TRANSACTIONS = AnalyticsConfig.Economy.Transactions
local DOUBLE_ATTRIBUTE = PerkConfig.AttributePrefix .. "DoubleCoins"

local function read(profile): number
	local coins = tonumber(profile.Data.Coins) or ItemShopConfig.StartingCoins
	return math.max(0, math.floor(coins))
end

local function multiplier(player: Player): number
	return if player:GetAttribute(DOUBLE_ATTRIBUTE) == true then 2 else 1
end

function CoinService:Get(player: Player): number
	local profile = DataSaveService:Get(player)
	return if profile then read(profile) else 0
end

function CoinService:Sync(player: Player)
	local profile = DataSaveService:Get(player)
	if not profile then return end

	local coins = read(profile)
	profile.Data.Coins = coins
	player:SetAttribute(ATTRIBUTE, coins)
end

function CoinService:Award(player: Player, amount: number, multiplied: boolean?): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false end

	local factor = if multiplied == false then 1 else multiplier(player)
	local balance = read(profile) + amount * factor
	profile.Data.Coins = balance
	CoinService:Sync(player)
	AnalyticsService:LogEconomy(player, "Source", CURRENCY, amount * factor, balance, TRANSACTIONS.Award)
	return true
end

function CoinService:Refund(player: Player, amount: number): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false end

	local balance = read(profile) + amount
	profile.Data.Coins = balance
	CoinService:Sync(player)
	AnalyticsService:LogEconomy(player, "Source", CURRENCY, amount, balance, TRANSACTIONS.Refund)
	return true
end

function CoinService:Spend(player: Player, amount: number, sku: string?): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount < 0 then return false end

	local coins = read(profile)
	if coins < amount then return false end

	profile.Data.Coins = coins - amount
	CoinService:Sync(player)
	AnalyticsService:LogEconomy(player, "Sink", CURRENCY, amount, coins - amount, TRANSACTIONS.Purchase, sku)
	return true
end

local function publish(player: Player)
	DataSaveService:Wait(player)
	if player.Parent == Players then CoinService:Sync(player) end
end

for _, player in Players:GetPlayers() do
	task.spawn(publish, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(publish, player)
end)

return CoinService
