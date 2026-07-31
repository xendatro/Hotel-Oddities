local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)

--- @class Healer
--- Shared body of every consumable that restores health. Subclasses supply only the amount, via
--- their config's `HealAmount`. Not a tool itself -- it lives outside `Classes/Tools` so the
--- registry never tries to bind a tag to it.
local Healer = ServerTool.extend("Healer")

--- Creates a subclass of Healer.
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

	-- Spend first: if nobody owns this, no heal is applied.
	if not self:Consume(1) then return end

	self:PlaySound(self.Config.Sound, self.Character.PrimaryPart)
	humanoid.Health = math.min(humanoid.Health + self.Config.HealAmount, humanoid.MaxHealth)
end

return Healer
