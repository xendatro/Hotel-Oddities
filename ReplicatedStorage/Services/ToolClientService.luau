local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TagService = require(ReplicatedStorage.Services.TagService)
local ToolConfigs = require(ReplicatedStorage.Configs.ToolConfigs)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local ToolClientService = {}

if not RunService:IsClient() then
	return ToolClientService
end

local Signal = CommunicationService.Get("Tools", "Signal")
local ToolClasses = ReplicatedStorage.Classes.Tools
local player = Players.LocalPlayer

local Instances: { [Tool]: any } = {}

local function belongsToPlayer(tool: Tool): boolean
	if tool:IsDescendantOf(player) then return true end
	local character = tool:FindFirstAncestorOfClass("Model")
	return character ~= nil and Players:GetPlayerFromCharacter(character) == player
end

function ToolClientService:FromTool(tool: Instance?): any?
	return tool and Instances[tool] or nil
end

for toolName, config in ToolConfigs do
	local module = ToolClasses:FindFirstChild(toolName)
	if module then
		local class = require(module)

		TagService:Listen(config.Tag, function(tool: Tool)
			if not belongsToPlayer(tool) then return nil end

			local instance = class.new(tool)
			Instances[tool] = instance

			local function recoverEquipped()
				if Instances[tool] ~= instance or instance.Character then return end
				local character = tool.Parent
				local humanoid = character and character:IsA("Model")
					and character:FindFirstChildOfClass("Humanoid")
				if not humanoid then return end

				instance.Character = character
				instance.Humanoid = humanoid
				instance.Mouse = player:GetMouse()
				instance:OnEquipped()
			end

			recoverEquipped()
			task.delay(0.05, recoverEquipped)
			return instance
		end, function(tool: Instance, instance: any)
			Instances[tool] = nil
			if instance then
				instance:Destroy()
			end
		end)
	end
end

Signal.OnClientEvent:Connect(function(toolName: string, eventName: string, ...)
	for tool, instance in Instances do
		if tool.Name == toolName then
			instance:_Dispatch(eventName, ...)
			return
		end
	end
end)

return ToolClientService
