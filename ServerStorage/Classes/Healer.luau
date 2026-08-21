local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)

local Healer = ServerTool.extend("Healer")

function Healer.extend(className: string)
	local class = setmetatable({}, { __index = Healer })
	class.__index = class
	class.ClassName = className
	return class
end

function Healer.new(tool: Tool, class: any?)
	return ServerTool.new(tool, class or Healer)
end

function Healer:OnActivated()
	local humanoid = self.Humanoid
	if not humanoid or humanoid.Health <= 0 then return end

	if not self:Consume(1) then return end

	self:PlaySound(self.Config.Sound, self.Character.PrimaryPart)
	humanoid.Health = math.min(humanoid.Health + self.Config.HealAmount, humanoid.MaxHealth)
end

return Healer
