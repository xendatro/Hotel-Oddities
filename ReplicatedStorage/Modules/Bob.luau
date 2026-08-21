local TAU = math.pi * 2

local Bob = {}

function Bob.NewPhase(): number
	return math.random() * TAU
end

function Bob.Offset(clock: number, phase: number, height: number, period: number): Vector3
	return Vector3.yAxis * math.sin(clock * TAU / period + phase) * height
end

return Bob
