local Players = game:GetService("Players")
local ControllerService = require(script.Services.ControllerService)
local CollectionService = game:GetService("CollectionService")
local ElementService=  require(script.Services.ElementService)

local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")

local Tagger = require(script.Modules.Tagger)(PlayerGui)

local xenterface = {}

function xenterface:Controller(pageGroup: string)
	return ControllerService:Get(pageGroup)
end

function xenterface:Get(elementId: string)
	return ElementService:Get(elementId)
end

function xenterface:Wait(elementId: string)
	return ElementService:Wait(elementId)
end

return xenterface