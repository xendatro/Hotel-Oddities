local Spring = {}
Spring.__index = Spring

function Spring.new(stiffness: number, dampingRatio: number, maxStep: number)
	local self = setmetatable({}, Spring)

	self.Stiffness = stiffness
	self.Damping = dampingRatio * 2 * math.sqrt(stiffness)
	self.MaxStep = maxStep
	self.Position = 0
	self.Velocity = 0
	self.Target = 0

	return self
end

function Spring:Snap(position: number)
	self.Position = position
	self.Velocity = 0
end

function Spring:Step(deltaTime: number, clamp: ((position: number, velocity: number) -> (number, number))?)
	local remaining = math.min(deltaTime, 0.1)
	while remaining > 0 do
		local step = math.min(remaining, self.MaxStep)
		remaining -= step

		self.Velocity += ((self.Target - self.Position) * self.Stiffness - self.Velocity * self.Damping) * step
		self.Position += self.Velocity * step

		if clamp then
			self.Position, self.Velocity = clamp(self.Position, self.Velocity)
		end
	end
end

return Spring
