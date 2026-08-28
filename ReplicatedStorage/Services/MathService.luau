local MathService = {}

MathService.TAU = math.pi * 2

function MathService.Smoothstep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

function MathService.ExpAlpha(speed: number, deltaTime: number): number
	return 1 - math.exp(-speed * deltaTime)
end

function MathService.Horizontal(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

function MathService.HorizontalMagnitude(vector: Vector3): number
	return Vector2.new(vector.X, vector.Z).Magnitude
end

function MathService.DistanceToSegment(point: Vector3, origin: Vector3, destination: Vector3, minimumLengthSquared: number?): number
	local offset = destination - origin
	local lengthSquared = offset:Dot(offset)
	if lengthSquared < (minimumLengthSquared or 1e-3) then
		return (point - origin).Magnitude
	end
	local alpha = math.clamp((point - origin):Dot(offset) / lengthSquared, 0, 1)
	return (point - origin:Lerp(destination, alpha)).Magnitude
end

function MathService.AngleBetween(a: Vector3, b: Vector3): number
	if a.Magnitude < 1e-6 or b.Magnitude < 1e-6 then return 0 end
	return math.deg(math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)))
end

function MathService.IsWithinCone(origin: Vector3, direction: Vector3, point: Vector3, maximumAngle: number): boolean
	local toPoint = point - origin
	if toPoint.Magnitude < 1e-6 then return true end
	return MathService.AngleBetween(direction, toPoint) <= maximumAngle
end

function MathService.LookDegrees(look: Vector3): number
	return math.deg(math.atan2(look.X, -look.Z))
end

function MathService.RandomRange(minimum: number, maximum: number): number
	return minimum + math.random() * (maximum - minimum)
end

function MathService.Comma(value: number): string
	local rounded = math.floor(math.abs(value) + 0.5)
	local digits = tostring(rounded):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	local trimmed = digits:gsub("^,", "")
	local sign = if value < 0 and rounded > 0 then "-" else ""
	return sign .. trimmed
end

function MathService.SinePulse(time: number, period: number): number
	return (math.sin(time * MathService.TAU / math.max(period, 1e-6)) + 1) * 0.5
end

return MathService
