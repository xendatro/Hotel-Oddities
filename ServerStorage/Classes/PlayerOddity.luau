local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local CharacterService = require(ReplicatedStorage.Services.CharacterService)
local Oddity = require(ServerStorage.Classes.Oddity)

local PlayerOddity = Oddity.extend("PlayerOddity")

PlayerOddity.Scope = "Player"
PlayerOddity.ConfigName = "PlayerOddityConfig"
PlayerOddity.Ambient = false

function PlayerOddity.new(config: { [string]: any }?, class: any?)
	local self = Oddity.new(config, class or PlayerOddity)

	self.Player = nil :: Player?
	self.Character = nil :: Model?
	self.Humanoid = nil :: Humanoid?
	self.Died = nil :: RBXScriptConnection?

	return self
end

function PlayerOddity.IsAvailable(_class: any): boolean
	return true
end

function PlayerOddity:CanStart(player: Player?): (boolean, string?)
	if not player then return false, "no player was given" end

	if not CharacterService.GetAliveHumanoid(player) then
		return false, "that player has no living character"
	end
	return true, nil
end

function PlayerOddity:Start(player: Player, duration: number?): boolean
	local character = player.Character
	local humanoid = CharacterService.GetHumanoid(character)
	if not character or not humanoid then return false end

	self.Player = player
	self.Character = character
	self.Humanoid = humanoid

	if not Oddity.Start(self, player, duration) then return false end

	self.Died = humanoid.Died:Connect(function()
		self:Stop()
	end)
	return true
end

function PlayerOddity:Stop(): boolean
	if self.Died then
		self.Died:Disconnect()
		self.Died = nil
	end
	return Oddity.Stop(self)
end

return PlayerOddity
