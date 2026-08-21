local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ToolBase = require(ReplicatedStorage.Classes.ToolBase)
local InventoryService = require(ServerStorage.Services.InventoryService)

local ServerTool = ToolBase.extend("ServerTool")

function ServerTool.extend(className: string)
	local class = setmetatable({}, { __index = ServerTool })
	class.__index = class
	class.ClassName = className
	return class
end

function ServerTool.new(tool: Tool, class: any?)
	return ToolBase.new(tool, class or ServerTool)
end

function ServerTool:Consume(n: number?): boolean
	local player = self:GetPlayer()
	if not player then return false end

	InventoryService:Remove(player, self.Name, n or 1)
	return true
end

return ServerTool
