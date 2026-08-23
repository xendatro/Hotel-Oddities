local ServerStorage = game:GetService("ServerStorage")

local PlayerOddity = require(ServerStorage.Classes.PlayerOddity)

local PlayerTransparency = PlayerOddity.extend("Transparency", PlayerOddity)

function PlayerTransparency.new(config: { [string]: any }?)
	local self = PlayerOddity.new(config, PlayerTransparency)

	self.Original = {} :: { [BasePart]: number }
	self.Added = nil :: RBXScriptConnection?

	return self
end

function PlayerTransparency:OnStart()
	local character = self.Character :: Model
	local level = self:Setting("OddTransparency", 0.1)

	local function apply(instance: Instance)
		if not instance:IsA("BasePart") or instance.Transparency ~= 0 then return end
		self.Original[instance] = 0
		instance.Transparency = level
	end

	for _, descendant in character:GetDescendants() do
		apply(descendant)
	end
	self.Added = character.DescendantAdded:Connect(apply)
	return true
end

function PlayerTransparency:OnStop()
	if self.Added then
		self.Added:Disconnect()
		self.Added = nil
	end

	for part, transparency in self.Original do
		if part.Parent then
			part.Transparency = transparency
		end
	end
	table.clear(self.Original)
end

return PlayerTransparency
