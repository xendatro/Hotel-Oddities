local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ToolBase = require(ReplicatedStorage.Classes.ToolBase)
local InventoryService = require(ServerStorage.Services.InventoryService)

--- @class ServerTool
--- A tool's server half. Everything shared lives in `ToolBase`; this adds the one thing only the
--- server can do -- actually spend from the stack -- plus the subclass helper.
local ServerTool = ToolBase.extend("ServerTool")

--- Creates a subclass of ServerTool.
function ServerTool.extend(className: string)
	local class = setmetatable({}, { __index = ServerTool })
	class.__index = class
	class.ClassName = className
	return class
end

function ServerTool.new(tool: Tool, class: any?)
	return ToolBase.new(tool, class or ServerTool)
end

--- Spends `n` from the stack. Returns false if nobody is holding the tool, so a caller can bail
--- rather than apply an effect nobody paid for.
function ServerTool:Consume(n: number?): boolean
	local player = self:GetPlayer()
	if not player then return false end

	InventoryService:Remove(player, self.Name, n or 1)
	return true
end

return ServerTool
