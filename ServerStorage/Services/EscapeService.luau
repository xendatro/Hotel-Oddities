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
local LeaderboardStore = DataStoreService:GetOrderedDataStore(EscapeConfig.OrderedStore.Name)
local TimeConfig = EscapeConfig.TimeOrderedStore
local TimeStore = DataStoreService:GetOrderedDataStore((if RunService:IsStudio() then TimeConfig.StudioPrefix else "") .. TimeConfig.Name)
local TimeLeaderboardStore = DataStoreService:GetOrderedDataStore(TimeConfig.Name)
local Stats: { [Player]: IntValue } = {}
local Runs: { [Player]: { StartedAt: number, Elapsed: number, Data: any } } = {}
local awarded = Instance.new("BindableEvent")

EscapeService.Awarded = awarded.Event

local function publish(userId: number, escapes: number)
	local ok, err = pcall(Store.SetAsync, Store, tostring(userId), escapes)
	if not ok then
		warn(`EscapeService: failed to publish {escapes} escapes for {userId}: {err}`)
	end
end

local function validTime(seconds: any): boolean
	return type(seconds) == "number" and seconds > 0 and seconds < math.huge
end

local function publishTime(userId: number, seconds: number)
	local milliseconds = math.max(1, math.round(seconds * TimeConfig.UnitsPerSecond))
	local ok, err = pcall(TimeStore.UpdateAsync, TimeStore, tostring(userId), function(previous)
		return if validTime(previous) then math.min(previous, milliseconds) else milliseconds
	end)
	if not ok then
		warn(`EscapeService: failed to publish escape time for {userId}: {err}`)
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
	if profile.Data.EscapeRunActive then
		EscapeService:StartRun(player)
	end

	local escapes = profile.Data.Escapes
	if type(escapes) ~= "number" or escapes < 0 then
		escapes = 0
		profile.Data.Escapes = 0
	end
	ensureStat(player).Value = escapes
	if escapes > 0 then
		task.spawn(publish, player.UserId, escapes)
	end
	if validTime(profile.Data.BestEscapeTime) then
		task.spawn(publishTime, player.UserId, profile.Data.BestEscapeTime)
	end
end

function EscapeService:Get(player: Player): number
	local profile = DataSaveService:Get(player)
	local escapes = profile and profile.Data.Escapes
	return if type(escapes) == "number" then escapes else 0
end

function EscapeService:StartRun(player: Player)
	if Runs[player] then return end
	local profile = DataSaveService:Get(player)
	if not profile then return end
	local elapsed = profile.Data.EscapeRunTime
	Runs[player] = {
		StartedAt = os.clock(),
		Elapsed = if validTime(elapsed) then elapsed else 0,
		Data = profile.Data,
	}
	profile.Data.EscapeRunActive = true
end

function EscapeService:GetRunTime(player: Player): number?
	local run = Runs[player]
	return if run then run.Elapsed + os.clock() - run.StartedAt else nil
end

function EscapeService:ResetRun(player: Player)
	Runs[player] = nil
	local profile = DataSaveService:Get(player)
	if profile then
		profile.Data.EscapeRunTime = 0
		profile.Data.EscapeRunActive = false
	end
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
	local seconds = self:GetRunTime(player)
	if validTime(seconds) then
		local best = profile.Data.BestEscapeTime
		if not validTime(best) or seconds < best then
			profile.Data.BestEscapeTime = seconds
			task.spawn(publishTime, player.UserId, seconds)
		end
	end
	self:ResetRun(player)
	awarded:Fire(player, escapes)
	return escapes
end

function EscapeService:GetTopTimes(count: number): { { UserId: number, Time: number } }?
	local ok, pages = pcall(TimeLeaderboardStore.GetSortedAsync, TimeLeaderboardStore, true, count, 1)
	if not ok then
		warn(`EscapeService: failed to read the time leaderboard: {pages}`)
		return nil
	end

	local top = {}
	for _, entry in pages:GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId and validTime(entry.value) then
			table.insert(top, { UserId = userId, Time = entry.value / TimeConfig.UnitsPerSecond })
		end
	end
	return top
end

function EscapeService:GetTop(count: number): { { UserId: number, Escapes: number } }?
	local ok, pages = pcall(LeaderboardStore.GetSortedAsync, LeaderboardStore, false, count)
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
	Runs[player] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, run in Runs do
		run.Data.EscapeRunTime = run.Elapsed + now - run.StartedAt
	end
end)

return EscapeService
