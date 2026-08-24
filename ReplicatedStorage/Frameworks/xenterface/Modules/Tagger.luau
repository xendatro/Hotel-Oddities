local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TagService = require(ReplicatedStorage.Services.TagService)

local Tab = require(script.Parent.Parent.Classes.Tab)
local Page = require(script.Parent.Parent.Classes.Page)
local Hover = require(script.Parent.Parent.Classes.Hover)

return function(playerGui: Folder)
	TagService:Listen("Tab", function(obj)
		if obj:IsA("GuiButton") then
			return Tab.new(obj)
		elseif obj.Parent:IsA("GuiButton") then
			return Tab.new(obj.Parent, obj)
		end
		error(`Assigned Tab tag to {obj:GetFullName()}, which does not follow proper Tab hierarchy`)
	end, function(_, tabObject)
		tabObject:Disconnect()
	end, playerGui)
	
	TagService:Listen("Page", function(obj)
		if obj:IsA("GuiObject") then
			return Page.new(obj)
		elseif obj.Parent:IsA("GuiObject") then
			return Page.new(obj.Parent, obj)
		end
		error(`Assigned Page tag to {obj:GetFullName()}, which does not follow proper Page hierarchy`)
	end, function(_, pageObject)
		--
	end, playerGui)
	
	TagService:Listen("Hover", function(obj)
		if obj:IsA("GuiObject") then
			return Hover.new(obj)
		elseif obj.Parent:IsA("GuiObject") then
			return Hover.new(obj.Parent, obj)
		end
	end, function(_, hoverObject)
		hoverObject:Disconnect()
	end, game)
	
end