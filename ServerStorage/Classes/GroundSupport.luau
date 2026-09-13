local GroundSupport = {}

function GroundSupport.Check(origin, destination, radius, params, config)
	local delta = Vector3.new(destination.X - origin.X, 0, destination.Z - origin.Z)
	local side = if delta.Magnitude > 0.001 then delta.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
	side *= radius * config.SupportWidthFraction
	local steps = math.max(1, math.ceil(delta.Magnitude / config.SupportSpacing))
	local floorY = origin.Y
	for index = 0, steps do
		local point = origin + delta * (index / steps)
		local centerY = nil
		for _, lane in { 0, -1, 1 } do
			local sample = Vector3.new(point.X, floorY + config.MaxStepUp, point.Z) + side * lane
			local hit = workspace:Raycast(sample, -Vector3.yAxis * (config.MaxStepUp + config.MaxDrop), params)
			if not hit or hit.Normal.Y < config.MinimumNormalY then return false end
			if lane == 0 then centerY = hit.Position.Y end
		end
		floorY = centerY
	end
	return true
end

return GroundSupport
