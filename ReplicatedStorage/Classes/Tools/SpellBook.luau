local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientTool = require(ReplicatedStorage.Classes.ClientTool)

--- @class SpellBook (client)
--- The spell book's local half. The cast itself is the server's business -- the vanish, the rooting,
--- the spend -- and this side exists to make the cast legible to the person performing it.
---
--- In first person the caster cannot see their own arms, so a two-second reading animation reads as
--- two seconds of being frozen for no visible reason. Holding the limb reveal open for exactly as
--- long as the animation runs gives that time back its meaning.
---
--- The animation is played server-side, so there is no track to wait on here -- only one to notice
--- arriving. `WaitForToolAnimation` watches for it; the reveal is bracketed by the chassis around
--- this whole method, so it lifts the moment this returns.
local SpellBook = ClientTool.extend("SpellBook")

local ANIMATION_START_TIMEOUT = 2

function SpellBook.new(tool: Tool)
	return ClientTool.new(tool, SpellBook)
end

function SpellBook:OnActivated()
	local track = self:WaitForToolAnimation("Book", ANIMATION_START_TIMEOUT)
	if not track then return end

	-- Bounded, like every other animation wait: a cast cut short by death never fires Ended, and an
	-- unbounded wait here would hold the limb reveal open for the rest of the round.
	self:WaitForTrack(track, self.Config.MaxCastTime)
end

return SpellBook
