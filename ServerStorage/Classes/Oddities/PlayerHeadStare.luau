local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)
local PlayerOddity = require(ServerStorage.Classes.PlayerOddity)

local HeadStare = CommunicationService.Ensure("Oddities", "HeadStare")

local PlayerHeadStare = PlayerOddity.extend("HeadStare", PlayerOddity)

function PlayerHeadStare.new(config: { [string]: any }?)
	return PlayerOddity.new(config, PlayerHeadStare)
end

local function livingPlayerCount(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if CharacterService.GetAliveHumanoid(player) then
			count += 1
		end
	end
	return count
end

function PlayerHeadStare.IsAvailable(class: any): boolean
	local minimum = class.Settings and class.Settings.MinimumPlayersForHeadStare
	return livingPlayerCount() >= (if type(minimum) == "number" then minimum else 3)
end

function PlayerHeadStare:CanStart(player: Player?): (boolean, string?)
	local ok, reason = PlayerOddity.CanStart(self, player)
	if not ok then return ok, reason end

	if not PlayerHeadStare.IsAvailable(PlayerHeadStare) then
		return false, "stare needs at least 2 other living players"
	end
	return true, nil
end

function PlayerHeadStare:OnStart()
	HeadStare:FireClient(self.Player :: Player, self.Duration)
	return true
end

function PlayerHeadStare:OnStop()
	local player = self.Player :: Player
	if player and player.Parent == Players then
		HeadStare:FireClient(player, 0)
	end
end

return PlayerHeadStare
