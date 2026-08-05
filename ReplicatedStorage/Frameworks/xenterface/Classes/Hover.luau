local Toggle = require(script.Parent.Toggle)

local Hover = {}
Hover.__index = Hover
setmetatable(Hover, Toggle)

local function setUpConnections(self)
	self.Connections = {}
	self.Connections.MouseEnter = self.Hover.MouseEnter:Connect(function()
		self:Entered()
	end)
	self.Connections.MouseLeave = self.Hover.MouseLeave:Connect(function()
		self:Left()
	end)
end

function Hover.new(hover: GuiObject, source: Configuration?)
	if not source then
		source = hover
	end
	local self = setmetatable(Toggle.new(hover, source, "Hover"), Hover)
	
	self.Hover = hover
	
	setUpConnections(self)

	return self
end

function Hover:Entered()
	self:Activate()
end

function Hover:Left()
	self:Deactivate()
end

function Hover:Disconnect()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end


return Hover