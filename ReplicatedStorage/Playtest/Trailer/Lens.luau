-- Helpers for authoring smooth camera moves. Shots describe where the camera
-- is and what it looks at, but the Director interpolates yaw, pitch and roll
-- as splines, so a turn sweeps at an even angular speed instead of speeding up
-- wherever a look-at point passes close to the lens. Leave Ease off a key to
-- keep the move continuous through it; the first and last keys ease in and out
-- on their own.
local Lens = {}

Lens.Steady = {
	Yaw = 0.35,
	Pitch = 0.28,
	Roll = 0.2,
	Position = Vector3.new(0.02, 0.018, 0.012),
	Frequencies = { 0.11, 0.29, 0.7 },
	Weights = { 1, 0.35, 0.06 },
	BreathPeriod = 4.2,
	BreathAmount = 0.01,
}

function Lens.Angles(from: Vector3, to: Vector3): (number, number)
	local direction = (to - from).Unit
	local yaw = math.deg(math.atan2(-direction.X, -direction.Z))
	local pitch = math.deg(math.asin(math.clamp(direction.Y, -1, 1)))
	return yaw, pitch
end

function Lens.Key(time: number, position: Vector3?, look: Vector3?, extra: { [string]: any }?): { [string]: any }
	local key: { [string]: any } = { Time = time, Position = position }
	if position and look then
		key.Yaw, key.Pitch = Lens.Angles(position, look)
	end
	for name, value in extra or {} do
		key[name] = value
	end
	return key
end

function Lens.Unwrap(keys: { { [string]: any } }): { { [string]: any } }
	local previous: number? = nil
	for _, key in keys do
		local yaw = key.Yaw
		if type(yaw) == "number" then
			if previous then
				while yaw - previous > 180 do
					yaw -= 360
				end
				while yaw - previous < -180 do
					yaw += 360
				end
				key.Yaw = yaw
			end
			previous = yaw
		end
	end
	return keys
end

function Lens.Handheld(seed: number, scale: number?): { [string]: any }
	local amount = scale or 1
	local steady = Lens.Steady
	return {
		Yaw = steady.Yaw * amount,
		Pitch = steady.Pitch * amount,
		Roll = steady.Roll * amount,
		Position = steady.Position * amount,
		Frequencies = steady.Frequencies,
		Weights = steady.Weights,
		BreathPeriod = steady.BreathPeriod,
		BreathAmount = steady.BreathAmount * amount,
		Seed = seed,
	}
end

return Lens
