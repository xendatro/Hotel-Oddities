local ControllerService = require(script.Parent.Parent.Services.ControllerService)

local Toggle = require(script.Parent.Toggle)
local Sequence = require(script.Parent.Sequence)

local Tab = {}
Tab.__index = Tab
setmetatable(Tab, Toggle)

local function setUpConnections(self)
	self.Connections = {}
	self.Connections.MouseButton1Click = self.Tab.MouseButton1Click:Connect(function()
		local controller = ControllerService:Get(self.PageGroup)
		
		if self.Tab:GetAttribute("Toggle") == true then
			if controller.Active == self.PageId then
				controller:Fire("", self.Tab)
				return
			end
		end
		
		controller:Fire(self.PageId, self.Tab)
	end)
end

function Tab.new(tab: GuiButton, source: Configuration?)
	local pageGroup
	local pageId
	if not source then
		source = tab
	end

	pageGroup = source:GetAttribute("PageGroup")
	pageId = source:GetAttribute("PageId")
	
	local self = setmetatable(Toggle.new(tab, source, "Tab"), Tab)
	
	if type(pageGroup) ~= "string" then
		error(`PageGroup of {tab:GetFullName()} is invalid`)
	end
	
	if type(pageId) ~= "string" then
		error(`PageId of {tab:GetFullName()} is invalid`)
	end
	
	self.Tab = tab
	self.PageGroup = pageGroup
	self.PageId = pageId
	
	setUpConnections(self)
	
	return self
end


function Tab:Disconnect()
	for _, connection in self.Connections do
		connection:Disconnect()
	end
end

return Tab