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

Lens.Shake = {
	Yaw = 2.4,
	Pitch = 2,
	Roll = 3,
	Position = 0.15,
	Frequency = 16,
}

function Lens.Impulses(impulses: { { [string]: number } }, seed: number?): (number) -> (CFrame, number)
	local offset = (seed or 0) * 7.31
	return function(time: number): (CFrame, number)
		local trauma, fov, push = 0, 0, 0
		for _, impulse in impulses do
			local age = time - impulse.At
			if age < 0 then continue end
			local attack = impulse.Attack or 0.03
			local envelope = if age < attack then age / attack else math.exp(-(age - attack) / (impulse.Decay or 0.3))
			trauma += (impulse.Shake or 0) * envelope
			fov += (impulse.Fov or 0) * envelope
			push += (impulse.Push or 0) * envelope
		end
		local amount = math.min(trauma, 1) ^ 2
		local shake = Lens.Shake
		local t = time * shake.Frequency
		local function wobble(channel: number): number
			return math.noise(t, offset + channel * 3.7, 0.5)
		end
		local position = Vector3.new(wobble(1), wobble(2), wobble(3)) * shake.Position * amount
		local rotation = CFrame.fromEulerAnglesYXZ(
			math.rad(wobble(4) * shake.Pitch * amount),
			math.rad(wobble(5) * shake.Yaw * amount),
			math.rad(wobble(6) * shake.Roll * amount)
		)
		return CFrame.new(position + Vector3.new(0, 0, -push)) * rotation, fov
	end
end

return Lens
