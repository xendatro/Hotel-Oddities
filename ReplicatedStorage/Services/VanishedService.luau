local Vanished = {}

Vanished.Tag = "Ignore"
Vanished.EyeExemptTag = "IgnoreExceptEye"

function Vanished.Is(character: Instance?): boolean
	return character ~= nil
		and (
			character:HasTag(Vanished.Tag)
			or character:HasTag(Vanished.EyeExemptTag)
			or character:FindFirstChildWhichIsA("ForceField", true) ~= nil
		)
end

function Vanished.IsForEye(character: Instance?): boolean
	return character ~= nil
		and (character:HasTag(Vanished.Tag) or character:FindFirstChildWhichIsA("ForceField", true) ~= nil)
end

return Vanished
