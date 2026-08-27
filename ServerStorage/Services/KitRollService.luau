local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local KitConfig = require(ReplicatedStorage.Configs.KitConfig)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local GemService = require(ServerStorage.Services.GemService)
local KitService = require(ServerStorage.Services.KitService)

local Roll = CommunicationService.Get("Kits", "Roll") :: RemoteFunction

local ATTRIBUTE = "CanRoll"
local ROLL = KitConfig.Roll

local KitRollService = {}

local allowed: { [Player]: boolean } = {}
local rolling: { [Player]: boolean } = {}
local random = Random.new()

local byRarity: { [string]: { KitConfig.Kit } } = {}
local totalWeight = 0

for _, kit in KitConfig.Entries do
	local list = byRarity[kit.Rarity]
	if not list then
		list = {}
		byRarity[kit.Rarity] = list
	end
	table.insert(list, kit)
end

for _, rarity in KitConfig.Rarities do
	if byRarity[rarity.Id] then totalWeight += rarity.Weight end
end

function KitRollService:CanRoll(player: Player): boolean
	return allowed[player] == true
end

local function pickRarity(): KitConfig.Rarity?
	local roll = random:NextNumber() * totalWeight
	for _, rarity in KitConfig.Rarities do
		if not byRarity[rarity.Id] then continue end
		roll -= rarity.Weight
		if roll <= 0 then return rarity end
	end

	for index = #KitConfig.Rarities, 1, -1 do
		local rarity = KitConfig.Rarities[index]
		if byRarity[rarity.Id] then return rarity end
	end
	return nil
end

function KitRollService:Roll(player: Player): { [string]: any }
	if not DataSaveService:Get(player) then return { Ok = false, Reason = "NotLoaded" } end
	if not allowed[player] then return { Ok = false, Reason = "Restricted" } end
	if rolling[player] then return { Ok = false, Reason = "Busy" } end

	rolling[player] = true

	local result
	if not GemService:Spend(player, ROLL.GemCost) then
		result = { Ok = false, Reason = "InsufficientGems" }
	else
		local rarity = pickRarity()
		local pool = rarity and byRarity[rarity.Id]
		if not pool or #pool == 0 then
			GemService:Award(player, ROLL.GemCost)
			result = { Ok = false, Reason = "EmptyPool" }
		else
			local kit = pool[random:NextInteger(1, #pool)]
			local duplicate = not KitService:Grant(player, kit.Id)
			local refund = 0

			if duplicate then
				refund = math.floor(KitConfig.GetRarity(kit).GemPrice * ROLL.DuplicateRefundFraction)
				GemService:Award(player, refund)
			end

			result = {
				Ok = true,
				KitId = kit.Id,
				Rarity = kit.Rarity,
				Duplicate = duplicate,
				Refund = refund,
			}
		end
	end

	rolling[player] = nil
	result.Gems = GemService:Get(player)

	GemService:Sync(player)
	KitService:Sync(player, if result.Ok then "Rolled" else result.Reason, result.KitId)
	return result
end

Roll.OnServerInvoke = function(player: Player)
	return KitRollService:Roll(player)
end

local function resolvePolicy(player: Player): boolean
	local success, info = pcall(
		PolicyService.GetPolicyInfoForPlayerAsync,
		PolicyService,
		player
	)
	if not success or type(info) ~= "table" then return false end
	return info.ArePaidRandomItemsRestricted ~= true
end

local function watch(player: Player)
	local canRoll = resolvePolicy(player)
	if player.Parent ~= Players then return end

	allowed[player] = canRoll
	player:SetAttribute(ATTRIBUTE, canRoll)
end

for _, player in Players:GetPlayers() do
	task.spawn(watch, player)
end
Players.PlayerAdded:Connect(function(player)
	task.spawn(watch, player)
end)
Players.PlayerRemoving:Connect(function(player)
	allowed[player] = nil
	rolling[player] = nil
end)

return KitRollService
