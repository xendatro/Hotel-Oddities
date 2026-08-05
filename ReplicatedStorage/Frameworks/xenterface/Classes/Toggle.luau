local PresetConfig = require(script.Parent.Parent.Config.PresetConfig)

local Sequence = require(script.Parent.Sequence)

local Toggle = {}
Toggle.__index = Toggle

function Toggle.new(guiObject: GuiObject, source: Configuration | GuiObject, systemType: string)
	local self = setmetatable({}, Toggle)
	
	local preset = source:GetAttribute("Preset")
	
	local activeSequence
	local inactiveSequence
	if preset then
		local presetConfig = PresetConfig[preset]
		if presetConfig then
			activeSequence = presetConfig.Active
			inactiveSequence = presetConfig.Inactive
		end
	end
	activeSequence = source:GetAttribute("Active") or activeSequence
	inactiveSequence = source:GetAttribute("Inactive") or inactiveSequence
	
	--[[
	Hover > Page > Tab
	]]
	if systemType == "Tab" and (source:HasTag("Page") or source:HasTag("Hover")) then
		activeSequence = nil
		inactiveSequence = nil
	elseif systemType == "Page" and source:HasTag("Hover") then
		activeSequence = nil
		inactiveSequence = nil
	end
	
	if activeSequence then
		self.Active = Sequence.new(guiObject, activeSequence, {inactiveSequence}, "Active")
	end
	if inactiveSequence then
		self.Inactive = Sequence.new(guiObject, inactiveSequence, {activeSequence}, "Inactive")
	end
	
	return self
end

function Toggle:Activate()
	if self.Active == nil then
		return
	end
	if self.Inactive then
		self.Inactive:Stop()
	end
	self.Active:Play()
end

function Toggle:Deactivate()
	if self.Inactive == nil then
		return
	end
	if self.Active then
		self.Active:Stop()
	end
	self.Inactive:Play()
end


return Toggle