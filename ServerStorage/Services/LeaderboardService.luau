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
local Entries: { [string]: { LeaderboardBoard.Entry } } = {}
local Boards: { [string]: { any } } = {}
local Refreshing = false

local function findParts(): { BasePart }
	local folder = workspace:FindFirstChild(Config.Folder)
	local parts = {}
	if folder then
		for _, part in folder:GetDescendants() do
			if not part:IsA("BasePart") or part.Name ~= Config.Part then continue end
			local boardType = part:GetAttribute(Config.TypeAttribute) or "Escapes"
			if Config.Types[boardType] then
				table.insert(parts, part)
			end
		end
	end
	return parts
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

local function refreshType(boardType: string, boards: { any })
	local top
	if boardType == "Time" then
		top = EscapeService:GetTopTimes(Config.TopCount)
	else
		top = EscapeService:GetTop(Config.TopCount)
	end
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
				Time = entry.Time,
			})
		end
		Entries[boardType] = entries
		for _, board in boards do
			board:SetEntries(entries)
		end
	end
end

local function refresh()
	if Refreshing then return end
	Refreshing = true
	for boardType, boards in Boards do
		refreshType(boardType, boards)
	end
	Refreshing = false
end

function LeaderboardService:GetEntries(boardType: string?): { LeaderboardBoard.Entry }
	return Entries[boardType or "Escapes"] or {}
end

function LeaderboardService:Refresh()
	refresh()
end

local parts = findParts()
local design = findDesign()
if #parts > 0 and design then
	for _, part in parts do
		local board = LeaderboardBoard.new(part, design)
		local boards = Boards[board.Type]
		if not boards then
			boards = {}
			Boards[board.Type] = boards
		end
		table.insert(boards, board)
	end
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
