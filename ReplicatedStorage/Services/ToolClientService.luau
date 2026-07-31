local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)

--- Registers every tool that has a client half and routes messages from server halves to the right
--- instance. The mirror of `ToolService`; between them, a tool never touches a remote directly.
local ToolClientService = {}

if not RunService:IsClient() then
	return ToolClientService
end

local Signal = ReplicatedStorage.Communication.Tools.Signal
local ToolClasses = ReplicatedStorage.Classes.Tools
local player = Players.LocalPlayer

-- [Tool instance] = the class instance driving it.
local Instances: { [Tool]: any } = {}

--- The live client half driving `tool`, if it has one.
function ToolClientService:FromTool(tool: Instance?): any?
	return tool and Instances[tool] or nil
end

for toolName, config in ToolConfigs do
	local module = ToolClasses:FindFirstChild(toolName)
	if module then
		local class = require(module)

		TagService:Listen(config.Tag, function(tool: Tool)
			-- Other players' tools replicate into their characters too; only drive our own.
			if not tool:IsDescendantOf(player) then return nil end

			local instance = class.new(tool)
			Instances[tool] = instance
			return instance
		end, function(tool: Instance, instance: any)
			Instances[tool] = nil
			if instance then
				instance:Destroy()
			end
		end)
	end
end

-- A server half talking to its client half.
Signal.OnClientEvent:Connect(function(toolName: string, eventName: string, ...)
	for tool, instance in Instances do
		if tool.Name == toolName then
			instance:_Dispatch(eventName, ...)
			return
		end
	end
end)

return ToolClientService
