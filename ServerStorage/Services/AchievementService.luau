local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local BadgeConfig = require(ReplicatedStorage.Configs.BadgeConfig)
local BadgeService = require(ServerStorage.Services.BadgeService)
local ComputerService = require(ServerStorage.Services.ComputerService)
local DataSaveService = require(ServerStorage.Services.DataSaveService)
local DeathService = require(ServerStorage.Services.DeathService)
local EscapeService = require(ServerStorage.Services.EscapeService)
local POIDiscoveryService = require(ServerStorage.Services.POIDiscoveryService)

local AchievementService = {}

local function award(player: Player, id: any): boolean
	if type(id) ~= "number" or id <= 0 then return false end
	if not player:IsDescendantOf(Players) then return false end
	return BadgeService:AwardBadge(player, id)
end

function AchievementService:AwardJoined(player: Player): boolean
	return award(player, BadgeConfig.Joined)
end

function AchievementService:AwardRoom(player: Player, name: string): boolean
	return award(player, BadgeConfig.Rooms[name])
end

function AchievementService:AwardComputer(player: Player, color: string?): boolean
	if type(color) ~= "string" then return false end
	return award(player, BadgeConfig.Computers[color])
end

function AchievementService:AwardEscapes(player: Player, escapes: number): boolean
	local any = false
	if escapes >= 1 then
		any = award(player, BadgeConfig.Escaped) or any
	end
	if escapes >= BadgeConfig.Escapes.Count then
		any = award(player, BadgeConfig.Escapes.Badge) or any
	end
	return any
end

function AchievementService:AwardDeath(player: Player, cause: string?): boolean
	if type(cause) ~= "string" then return false end
	return award(player, BadgeConfig.Deaths[cause])
end

local function catchUp(player: Player)
	local profile = DataSaveService:Wait(player)
	if not profile or not player:IsDescendantOf(Players) then return end

	AchievementService:AwardEscapes(player, EscapeService:Get(player))

	local discovered = profile.Data.DiscoveredPOIs
	if type(discovered) ~= "table" then return end
	for name, value in discovered do
		if type(name) == "string" and value == true then
			AchievementService:AwardRoom(player, name)
		end
	end
end

local function watchPlayer(player: Player)
	task.spawn(AchievementService.AwardJoined, AchievementService, player)
	task.spawn(catchUp, player)
end

for _, player in Players:GetPlayers() do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)

POIDiscoveryService.Discovered:Connect(function(player: Player, name: string)
	AchievementService:AwardRoom(player, name)
end)

ComputerService.Hacked:Connect(function(player: Player, _model: Model, color: string?)
	AchievementService:AwardComputer(player, color)
end)

EscapeService.Awarded:Connect(function(player: Player, escapes: number)
	AchievementService:AwardEscapes(player, escapes)
end)

DeathService.Died:Connect(function(player: Player, cause: string?)
	AchievementService:AwardDeath(player, cause)
end)

return AchievementService
