local Vanished = {}

Vanished.Tag = "Ignore"
Vanished.EyeExemptTag = "IgnoreExceptEye"
Vanished.InfiniteTag = "InfiniteImmunity"
Vanished.SafeZoneTag = "SafeZoneImmunity"
Vanished.SpellBookTag = "SpellBookImmunity"
Vanished.HoleTag = "HoleImmunity"
Vanished.SpellBookEndsAtAttribute = "SpellBookImmunityEndsAt"
Vanished.HoleEndsAtAttribute = "HoleImmunityEndsAt"

local SOURCE_TAGS = {
	[Vanished.InfiniteTag] = true,
	[Vanished.SafeZoneTag] = true,
	[Vanished.SpellBookTag] = true,
	[Vanished.HoleTag] = true,
}

function Vanished.SetSource(character: Instance?, sourceTag: string, enabled: boolean)
	if not character or not SOURCE_TAGS[sourceTag] then return end

	if enabled then
		character:AddTag(sourceTag)
	else
		character:RemoveTag(sourceTag)
	end

	local hasSource = false
	for tag in SOURCE_TAGS do
		if character:HasTag(tag) then
			hasSource = true
			break
		end
	end

	if hasSource then
		character:AddTag(Vanished.Tag)
	else
		character:RemoveTag(Vanished.Tag)
	end
end

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
