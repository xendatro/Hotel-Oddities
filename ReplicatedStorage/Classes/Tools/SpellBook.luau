local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)

local SpellBook = ClientTool.extend("SpellBook")

local ANIMATION_START_TIMEOUT = 2

function SpellBook.new(tool: Tool)
	return ClientTool.new(tool, SpellBook)
end

function SpellBook:OnActivated()
	local track = self:WaitForToolAnimation("Book", ANIMATION_START_TIMEOUT)
	if not track then return end

	self:WaitForTrack(track, self.Config.MaxCastTime)
end

return SpellBook
