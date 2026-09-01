local EnemySizeService = {}

function EnemySizeService.Apply(model: Model)
	local sizedParts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and typeof(descendant:GetAttribute("Size")) == "Vector3" then
			table.insert(sizedParts, descendant)
		end
	end
	if #sizedParts == 0 then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutomaticScalingEnabled = false
	end
	for _, part in sizedParts do
		part.Size = part:GetAttribute("Size") :: Vector3
	end
end

return EnemySizeService
