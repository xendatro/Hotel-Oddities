local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local UserService = game:GetService("UserService")

local EscapeConfig = require(ReplicatedStorage.Configs.EscapeConfig)
local LeaderboardBoard = require(ServerStorage.Classes.LeaderboardBoard)
local EscapeService = require(ServerStorage.Services.EscapeService)

local LeaderboardService = {}

local Config = EscapeConfig.Leaderboard
local Names: { [number]: { DisplayName: string, Username: string } } = {}
local Entries: { LeaderboardBoard.Entry } = {}
local Board = nil
local Refreshing = false

local function findPart(): BasePart?
	local folder = workspace:FindFirstChild(Config.Folder)
	local part = folder and folder:FindFirstChild(Config.Part)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

local function findDesign(): Instance?
	local gui = StarterGui:FindFirstChild(Config.Gui)
	return gui and gui:FindFirstChild(Config.Root)
end

local function lookup(ids: { number })
	local missing = {}
	for _, id in ids do
		if Names[id] then continue end
		local player = Players:GetPlayerByUserId(id)
		if player then
			Names[id] = { DisplayName = player.DisplayName, Username = player.Name }
		else
			table.insert(missing, id)
		end
	end
	if #missing == 0 then return end

	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, missing)
	if ok and type(infos) == "table" then
		for _, info in infos do
			Names[info.Id] = { DisplayName = info.DisplayName, Username = info.Username }
		end
	end

	for _, id in missing do
		if Names[id] then continue end
		local okName, name = pcall(Players.GetNameFromUserIdAsync, Players, id)
		if okName and type(name) == "string" then
			Names[id] = { DisplayName = name, Username = name }
		end
	end
end

local function refresh()
	if Refreshing then return end
	Refreshing = true

	local top = EscapeService:GetTop(Config.TopCount)
	if top then
		local ids = {}
		for _, entry in top do
			table.insert(ids, entry.UserId)
		end
		lookup(ids)

		local entries = {}
		for _, entry in top do
			local names = Names[entry.UserId]
			table.insert(entries, {
				UserId = entry.UserId,
				DisplayName = if names then names.DisplayName else Config.UnknownName,
				Username = if names then names.Username else tostring(entry.UserId),
				Escapes = entry.Escapes,
			})
		end
		Entries = entries
		if Board then
			Board:SetEntries(entries)
		end
	end

	Refreshing = false
end

function LeaderboardService:GetEntries(): { LeaderboardBoard.Entry }
	return Entries
end

function LeaderboardService:Refresh()
	refresh()
end

local part = findPart()
local design = findDesign()
if part and design then
	Board = LeaderboardBoard.new(part, design)
else
	warn(`LeaderboardService: missing {Config.Folder}.{Config.Part} or StarterGui.{Config.Gui}.{Config.Root}, no board built`)
end

EscapeService.Awarded:Connect(function()
	task.delay(Config.AwardRefreshDelay, refresh)
end)

task.spawn(function()
	while true do
		refresh()
		task.wait(Config.RefreshInterval)
	end
end)

return LeaderboardService
