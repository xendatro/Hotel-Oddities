local ServerStorage = game:GetService("ServerStorage")

local PlayerOddity = require(ServerStorage.Classes.PlayerOddity)

local PlayerSize = PlayerOddity.extend("Size", PlayerOddity)

function PlayerSize.new(config: { [string]: any }?)
	local self = PlayerOddity.new(config, PlayerSize)
	self.OriginalScale = 1
	return self
end

function PlayerSize:OnStart()
	local character = self.Character :: Model
	local options = self.Config.SizeOptions
	if type(options) ~= "table" or #options == 0 then return false end

	self.OriginalScale = character:GetScale()
	character:ScaleTo(self.OriginalScale * options[math.random(1, #options)])
	return true
end

function PlayerSize:OnStop()
	local character = self.Character :: Model
	if character and character.Parent then
		character:ScaleTo(self.OriginalScale)
	end
end

return PlayerSize
