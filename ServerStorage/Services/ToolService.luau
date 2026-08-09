local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local InventoryService = require(ServerStorage.Services.InventoryService)

local Signal = ReplicatedStorage.Communication.Tools.Signal
local ToolClasses = ServerStorage.Classes.Tools

--- Registers every tool that has a server half and routes messages from client halves to the right
--- instance. Walks `ToolConfigs` at boot, so a new tool needs no edit here and none in the Tagger.
local ToolService = {}

-- [Tool instance] = the class instance driving it.
local Instances: { [Tool]: any } = {}

--- The live server half driving `tool`, if it has one.
function ToolService:FromTool(tool: Instance?): any?
	return tool and Instances[tool] or nil
end

--- Every live instance of a named tool. Handy for effects that need to sweep all of one kind.
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

		-- Global scope: tools move between a player's Backpack and their Character, so there is no
		-- single ancestor to scope the listen to.
		TagService:Listen(config.Tag, function(tool: Tool)
			local instance = class.new(tool)
			Instances[tool] = instance

			-- A tagged Tool can be rebuilt after Roblox has already moved it into the Character and
			-- fired Equipped. Recover that missed event once normal event delivery has had a chance.
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

-- A client half talking to its server half. The tool is resolved through the player's own
-- inventory, which validates ownership as a side effect: a player who does not hold that tool has
-- nothing to resolve, so the message is dropped before it reaches any handler.
Signal.OnServerEvent:Connect(function(player: Player, toolName: any, eventName: any, ...)
	if type(toolName) ~= "string" or type(eventName) ~= "string" then return end

	local tool = InventoryService:Get(player, toolName)
	if not tool then return end

	local instance = Instances[tool]
	if not instance then return end

	instance:_Dispatch(eventName, player, ...)
end)

return ToolService
