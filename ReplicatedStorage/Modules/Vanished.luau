--- Whether a character is protected from enemies. The spell book does this by making its reader
--- vanish, while Roblox forcefields protect the character directly.
---
--- One check, one rule, and both live here so that neither can drift. A protected player is not a
--- target for anything that picks targets, **and** cannot be hurt by any enemy at all. Those are
--- separate promises and the second is the one that has to hold everywhere.
--- Perception is the polite half -- a Chaser turning away because it can no longer find you -- but
--- the things with no perception to speak of still sweep a corridor and still kill whoever is
--- standing in it, and a vanish that a Chaos walks straight through is not a vanish.
---
--- Shared, because the client draws this too: an `Eye` stops following a protected player, which is
--- the only moment a player can watch the hotel lose them.

local Vanished = {}

--- Written on a character while it lasts. Named for what enemies do about it rather than for the
--- book, since the book is only one way in and there may be others.
Vanished.Tag = "Ignore"

--- Whether `character` is protected right now. Nil-safe, so a caller holding a player who has not
--- respawned yet can ask without checking first. A ForceField normally sits directly under the
--- character, but the descendant lookup also supports effects that place it inside an attachment.
function Vanished.Is(character: Instance?): boolean
	return character ~= nil
		and (character:HasTag(Vanished.Tag) or character:FindFirstChildWhichIsA("ForceField", true) ~= nil)
end

return Vanished
