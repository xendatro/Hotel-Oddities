local MathService = {}

MathService.TAU = math.pi * 2

local HALF_PI = math.pi / 2
local ROTATION_EPSILON = 1e-6

function MathService.Smoothstep(alpha: number): number
	local clamped = math.clamp(alpha, 0, 1)
	return clamped * clamped * (3 - 2 * clamped)
end

local function inOutPower(alpha: number, power: number): number
	if alpha < 0.5 then
		return 2 ^ (power - 1) * alpha ^ power
	end
	return 1 - (-2 * alpha + 2) ^ power / 2
end

MathService.Eases = {
	Linear = function(alpha: number): number
		return alpha
	end,
	InSine = function(alpha: number): number
		return 1 - math.cos(alpha * HALF_PI)
	end,
	OutSine = function(alpha: number): number
		return math.sin(alpha * HALF_PI)
	end,
	InOutSine = function(alpha: number): number
		return (1 - math.cos(math.pi * alpha)) / 2
	end,
	InQuad = function(alpha: number): number
		return alpha * alpha
	end,
	OutQuad = function(alpha: number): number
		return 1 - (1 - alpha) ^ 2
	end,
	InOutQuad = function(alpha: number): number
		return inOutPower(alpha, 2)
	end,
	InCubic = function(alpha: number): number
		return alpha ^ 3
	end,
	OutCubic = function(alpha: number): number
		return 1 - (1 - alpha) ^ 3
	end,
	InOutCubic = function(alpha: number): number
		return inOutPower(alpha, 3)
	end,
	InOutQuart = function(alpha: number): number
		return inOutPower(alpha, 4)
	end,
	OutQuint = function(alpha: number): number
		return 1 - (1 - alpha) ^ 5
	end,
	InOutQuint = function(alpha: number): number
		return inOutPower(alpha, 5)
	end,
	OutExpo = function(alpha: number): number
		if alpha >= 1 then return 1 end
		return (1 - 2 ^ (-10 * alpha)) / (1 - 2 ^ -10)
	end,
	InOutExpo = function(alpha: number): number
		if alpha <= 0 then return 0 end
		if alpha >= 1 then return 1 end
		if alpha < 0.5 then
			return 2 ^ (20 * alpha - 10) / 2
		end
		return (2 - 2 ^ (-20 * alpha + 10)) / 2
	end,
} :: { [string]: (number) -> number }

function MathService.BackOut(overshoot: number): (number) -> number
	return function(alpha: number): number
		local shifted = alpha - 1
		return 1 + (overshoot + 1) * shifted * shifted * shifted + overshoot * shifted * shifted
	end
end

function MathService.RotationVector(rotation: CFrame): Vector3
	local axis, angle = rotation:ToAxisAngle()
	if angle < ROTATION_EPSILON or axis.Magnitude < ROTATION_EPSILON then return Vector3.zero end
	return axis.Unit * angle
end

function MathService.FromRotationVector(vector: Vector3): CFrame
	local angle = vector.Magnitude
	if angle < ROTATION_EPSILON then return CFrame.identity end
	return CFrame.fromAxisAngle(vector / angle, angle)
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
