local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local PlayerOddityService = require(ServerStorage.Services.PlayerOddityService)

local PlayerOddityTool = ServerTool.extend("PlayerOddityTool")

function PlayerOddityTool.extend(className: string)
	local class = setmetatable({}, { __index = PlayerOddityTool })
	class.__index = class
	class.ClassName = className
	return class
end

function PlayerOddityTool.new(tool: Tool, class: any?)
	return ServerTool.new(tool, class or PlayerOddityTool)
end

function PlayerOddityTool:_ChooseEffect(): (string?, { [string]: any }?)
	if type(self.Config.OddityKind) == "string" then
		return self.Config.OddityKind, self.Config.OddityOverrides
	end

	local choices = self.Config.OddityChoices
	if type(choices) ~= "table" or #choices == 0 then return nil, nil end

	local choice = choices[math.random(1, #choices)]
	if type(choice) ~= "table" or type(choice.Kind) ~= "string" then return nil, nil end
	return choice.Kind, choice.Settings
end

function PlayerOddityTool:OnActivated()
	local player = self:GetPlayer()
	if not player then return end

	local kind, overrides = self:_ChooseEffect()
	if not kind then return end

	local ok = PlayerOddityService:Trigger(player, kind, overrides)
	if ok then
		self:Consume()
	end
end

return PlayerOddityTool
