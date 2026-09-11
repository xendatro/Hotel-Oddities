local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Toggle = require(script.Parent.Toggle)

local Press = {}
Press.__index = Press
setmetatable(Press, Toggle)

local function setUpConnections(self)
	self.Connections = {}
	self.Connections.MouseEnter = self.Press.MouseEnter:Connect(function()
		self.Hovered = true
	end)
	self.Connections.MouseLeave = self.Press.MouseLeave:Connect(function()
		self.Hovered = false
	end)
	self.Connections.MouseButton1Down = self.Press.MouseButton1Down:Connect(function()
		self:Pressed()
	end)
	self.Connections.MouseButton1Up = self.Press.MouseButton1Up:Connect(function()
		self:Released()
	end)
end

function Press.new(press: GuiButton, source: Configuration?)
	if not source then
		source = press
	end
	local self = setmetatable(Toggle.new(press, source, "Press"), Press)

	self.Press = press
	self.Hovered = false

	setUpConnections(self)

	return self
end

function Press:Pressed()
	self:Activate()
end

function Press:Released()
	local hover = TagService:GetApplied("Hover", self.Press)
	if self.Hovered and hover then
		if self.Active then
			self.Active:Stop()
		end
		hover:Activate()
		return
	end
	self:Deactivate()
end

function Press:Disconnect()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Press
