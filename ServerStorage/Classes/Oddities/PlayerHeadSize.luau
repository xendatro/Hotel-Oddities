local ServerStorage = game:GetService("ServerStorage")

local PlayerOddity = require(ServerStorage.Classes.PlayerOddity)

local PlayerHeadSize = PlayerOddity.extend("HeadSize", PlayerOddity)

function PlayerHeadSize.new(config: { [string]: any }?)
	local self = PlayerOddity.new(config, PlayerHeadSize)
	self.HeadScale = nil :: NumberValue?
	self.OriginalHeadScale = 1
	self.CreatedHeadScale = false
	return self
end

function PlayerHeadSize:OnStart()
	local humanoid = self.Humanoid :: Humanoid
	local multiplier = self:Setting("HeadSizeMultiplier", 1.5)
	if multiplier <= 0 then return false end

	local headScale = humanoid:FindFirstChild("HeadScale")
	if not headScale or not headScale:IsA("NumberValue") then
		headScale = Instance.new("NumberValue")
		headScale.Name = "HeadScale"
		headScale.Value = 1
		headScale.Parent = humanoid
		self.CreatedHeadScale = true
	end

	self.HeadScale = headScale :: NumberValue
	self.OriginalHeadScale = self.HeadScale.Value
	self.HeadScale.Value = self.OriginalHeadScale * multiplier
	return true
end

function PlayerHeadSize:OnStop()
	local headScale = self.HeadScale
	if not headScale or not headScale.Parent then return end

	headScale.Value = self.OriginalHeadScale
	if self.CreatedHeadScale then
		headScale:Destroy()
	end
	self.HeadScale = nil
	self.CreatedHeadScale = false
end

return PlayerHeadSize
