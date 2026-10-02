-- A still camera for location scouting: Director.Play("Scout", { Pos = {x, y, z},
-- Look = {x, y, z}, Fov = 70, Roll = 0, HoldAt = 0 }). Parks the hidden
-- character under the camera so the area streams in with in-game lighting.
local function vector(list: { number }?): Vector3
	local values = list or { 0, 0, 0 }
	return Vector3.new(values[1], values[2], values[3])
end

return {
	Duration = 1,
	Warmup = 1.5,
	Park = function(options)
		local position = vector(options.Pos)
		return CFrame.new(position.X, position.Y - 1.8, position.Z)
	end,
	Keys = function(_, _, options)
		return {
			{ Time = 0, Position = vector(options.Pos), Focus = vector(options.Look), Fov = options.Fov or 70, Roll = options.Roll or 0, Handheld = 0 },
		}
	end,
}
