local CollectionService = game:GetService("CollectionService")

local Controller = require(script.Parent.Parent.Classes.Controller)

local ControllerService = {}

local Controllers = {}

function ControllerService:Create(pageGroup: string)
	if Controllers[pageGroup] ~= nil then
		warn("Attempted to create duplicate controllers")
		return
	end
	local controller = Controller.new(pageGroup)
	Controllers[pageGroup] = controller
	return controller
end

function ControllerService:Get(pageGroup: string): typeof(Controller.new())
	return Controllers[pageGroup] or ControllerService:Create(pageGroup)
end

function ControllerService:Fire(pageGroup: string, pageId: string, tab: GuiButton?)
	local controller = ControllerService:Get(pageGroup)
	if not controller then return end
	controller:Fire(pageId, tab)
end

return ControllerService