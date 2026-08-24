local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local InventoryService = require(ServerStorage.Services.InventoryService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local Signal = CommunicationService.Get("Tools", "Signal")
local ToolClasses = ServerStorage.Classes.Tools

local ToolService = {}

local Instances: { [Tool]: any } = {}

function ToolService:FromTool(tool: Instance?): any?
	return tool and Instances[tool] or nil
end

function ToolService:GetAllOf(toolName: string): { any }
	local found = {}
	for tool, instance in Instances do
		if tool.Name == toolName then
			table.insert(found, instance)
		end
	end
	return found
end

for toolName, config in ToolConfigs do
	local module = ToolClasses:FindFirstChild(toolName)
	if module then
		local class = require(module)

		TagService:Listen(config.Tag, function(tool: Tool)
			local instance = class.new(tool)
			Instances[tool] = instance

			task.delay(0.05, function()
				if Instances[tool] ~= instance or instance.Character then return end
				local character = tool.Parent
				local humanoid = character and character:IsA("Model")
					and character:FindFirstChildOfClass("Humanoid")
				if not humanoid then return end

				instance.Character = character
				instance.Humanoid = humanoid
				instance:OnEquipped()
			end)
			return instance
		end, function(tool: Instance, instance: any)
			Instances[tool] = nil
			if instance then
				instance:Destroy()
			end
		end)
	end
end

Signal.OnServerEvent:Connect(function(player: Player, toolName: any, eventName: any, ...)
	if type(toolName) ~= "string" or type(eventName) ~= "string" then return end

	local tool = InventoryService:Get(player, toolName)
	if not tool then return end

	local instance = Instances[tool]
	if not instance then return end

	instance:_Dispatch(eventName, player, ...)
end)

return ToolService
