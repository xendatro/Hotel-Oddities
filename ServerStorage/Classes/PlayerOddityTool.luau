local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local ServerTool = require(ServerStorage.Classes.ServerTool)
local PlayerOddityService = require(ServerStorage.Services.PlayerOddityService)
local CommunicationService = require(ReplicatedStorage.Services.CommunicationService)

local PlayerOddityTool = ServerTool.extend("PlayerOddityTool")
local ShowNotification = CommunicationService.Ensure("Notifications", "Show")

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

function PlayerOddityTool:_Notify(message: string?)
	local player = self:GetPlayer()
	if not player or type(message) ~= "string" or message == "" then return end
	ShowNotification:FireClient(player, message)
end

function PlayerOddityTool:OnActivated()
	local player = self:GetPlayer()
	if not player then return end

	local kind, overrides = self:_ChooseEffect()
	if not kind then return end

	local ok, _, reason = PlayerOddityService:Trigger(player, kind, overrides)
	if not ok then
		local message = if PlayerOddityService:IsActive(player)
			then "Only one player oddity can be active at a time."
			else reason
		self:_Notify(message)
		return
	end

	self:Consume()
end

return PlayerOddityTool
