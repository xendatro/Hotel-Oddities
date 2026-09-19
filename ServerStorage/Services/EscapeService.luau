local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local EscapeConfig = require(ReplicatedStorage.Configs.EscapeConfig)
local DataSaveService = require(ServerStorage.Services.DataSaveService)

local EscapeService = {}

local STORE_NAME = (if RunService:IsStudio() then EscapeConfig.OrderedStore.StudioPrefix else "")
	.. EscapeConfig.OrderedStore.Name
local Store = DataStoreService:GetOrderedDataStore(STORE_NAME)
local Stats: { [Player]: IntValue } = {}
local awarded = Instance.new("BindableEvent")

EscapeService.Awarded = awarded.Event

local function publish(userId: number, escapes: number)
	local ok, err = pcall(Store.SetAsync, Store, tostring(userId), escapes)
	if not ok then
		warn(`EscapeService: failed to publish {escapes} escapes for {userId}: {err}`)
	end
end

local function ensureStat(player: Player): IntValue
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local stat = folder:FindFirstChild(EscapeConfig.StatName)
	if not stat or not stat:IsA("IntValue") then
		stat = Instance.new("IntValue")
		stat.Name = EscapeConfig.StatName
		stat.Parent = folder
	end
	Stats[player] = stat :: IntValue
	return stat :: IntValue
end

local function loadPlayer(player: Player)
	local profile = DataSaveService:Wait(player)
	if not profile or not player:IsDescendantOf(Players) then return end

	local escapes = profile.Data.Escapes
	if type(escapes) ~= "number" or escapes < 0 then
		escapes = 0
		profile.Data.Escapes = 0
	end
	ensureStat(player).Value = escapes
	if escapes > 0 then
		task.spawn(publish, player.UserId, escapes)
	end
end

function EscapeService:Get(player: Player): number
	local profile = DataSaveService:Get(player)
	local escapes = profile and profile.Data.Escapes
	return if type(escapes) == "number" then escapes else 0
end

function EscapeService:Award(player: Player): number?
	local profile = DataSaveService:Get(player)
	if not profile then
		warn(`EscapeService: {player.Name} has no loaded profile, escape not awarded`)
		return nil
	end

	local escapes = (if type(profile.Data.Escapes) == "number" then profile.Data.Escapes else 0) + 1
	profile.Data.Escapes = escapes
	local stat = Stats[player] or ensureStat(player)
	stat.Value = escapes
	task.spawn(publish, player.UserId, escapes)
	awarded:Fire(player, escapes)
	return escapes
end

function EscapeService:GetTop(count: number): { { UserId: number, Escapes: number } }?
	local ok, pages = pcall(Store.GetSortedAsync, Store, false, count)
	if not ok then
		warn(`EscapeService: failed to read the escape leaderboard: {pages}`)
		return nil
	end

	local top = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId and type(entry.value) == "number" then
			table.insert(top, { UserId = userId, Escapes = entry.value })
		end
	end
	return top
end

for _, player in Players:GetPlayers() do
	task.spawn(loadPlayer, player)
end
Players.PlayerAdded:Connect(function(player: Player)
	task.spawn(loadPlayer, player)
end)
Players.PlayerRemoving:Connect(function(player: Player)
	Stats[player] = nil
end)

return EscapeService
