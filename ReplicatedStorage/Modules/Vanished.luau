--- Whether a character is currently gone as far as the hotel is concerned -- the state the spell book
--- puts its reader in for the length of a cast.
---
--- One tag, one rule, and both live here so that neither can drift. The rule is the strong one: a
--- vanished player is not a target for anything that picks targets, **and** cannot be hurt by any
--- enemy at all. Those are separate promises and the second is the one that has to hold everywhere.
--- Perception is the polite half -- a Chaser turning away because it can no longer find you -- but
--- the things with no perception to speak of still sweep a corridor and still kill whoever is
--- standing in it, and a vanish that a Chaos walks straight through is not a vanish.
---
--- Shared, because the client draws this too: an `Eye` stops following a reader mid-cast, which is
--- the only moment a player can watch the hotel lose them.

local Vanished = {}

--- Written on a character while it lasts. Named for what enemies do about it rather than for the
--- book, since the book is only one way in and there may be others.
Vanished.Tag = "Ignore"

--- Whether `character` is vanished right now. Nil-safe, so a caller holding a player who has not
--- respawned yet can ask without checking first.
function Vanished.Is(character: Instance?): boolean
	return character ~= nil and character:HasTag(Vanished.Tag)
end

return Vanished
