local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ItemShopConfig = require(ReplicatedStorage.Configs.ItemShopConfig)
local PerkConfig = require(ReplicatedStorage.Configs.PerkConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local CoinService = {}

local ATTRIBUTE = "Coins"
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
	profile.Data.Coins = read(profile) + amount * factor
	CoinService:Sync(player)
	return true
end

function CoinService:Refund(player: Player, amount: number): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then return false end

	profile.Data.Coins = read(profile) + amount
	CoinService:Sync(player)
	return true
end

function CoinService:Spend(player: Player, amount: number): boolean
	local profile = DataSaveService:Get(player)
	if not profile then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount < 0 then return false end

	local coins = read(profile)
	if coins < amount then return false end

	profile.Data.Coins = coins - amount
	CoinService:Sync(player)
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
