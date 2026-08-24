local Vanished = {}

Vanished.Tag = "Ignore"

function Vanished.Is(character: Instance?): boolean
	return character ~= nil
		and (character:HasTag(Vanished.Tag) or character:FindFirstChildWhichIsA("ForceField", true) ~= nil)
end

return Vanished
