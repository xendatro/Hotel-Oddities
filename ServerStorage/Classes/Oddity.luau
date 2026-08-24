local Oddity = {}
Oddity.__index = Oddity

Oddity.ClassName = "Oddity"
Oddity.Kind = "Oddity"
Oddity.Scope = "Map"
Oddity.Ambient = true

local nextToken = 0

function Oddity.extend(kind: string, parent: any?)
	local class = setmetatable({}, { __index = parent or Oddity })
	class.__index = class
	class.ClassName = kind
	class.Kind = kind
	return class
end

function Oddity.new(config: { [string]: any }?, class: any?)
	local self = setmetatable({}, class or Oddity)

	nextToken += 1
	self.Token = nextToken
	self.Config = config or {}
	self.Context = nil :: any
	self.Active = false
	self.StartedAt = 0
	self.Duration = 0
	self.Callbacks = {} :: { (any) -> () }

	return self
end

function Oddity:OnStopped(callback: (any) -> ())
	table.insert(self.Callbacks, callback)
end

function Oddity:Setting(name: string, fallback: number): number
	local value = self.Config[name]
	return if type(value) == "number" then value else fallback
end

function Oddity:RandomDuration(): number
	local minimum = math.max(self:Setting("MinDuration", 45), 0)
	local maximum = math.max(self:Setting("MaxDuration", 120), minimum)
	return minimum + math.random() * (maximum - minimum)
end

function Oddity:CanStart(_context: any): (boolean, string?)
	return true, nil
end

function Oddity:Start(context: any, duration: number?): boolean
	if self.Active then return false end

	self.Context = context
	self.Duration = duration or self:RandomDuration()
	self.StartedAt = os.clock()
	self.Active = true

	if self.OnStart then
		local ok, result = pcall(self.OnStart, self, context)
		if not ok then
			warn(`[oddity] {self.Kind} failed to start: {result}`)
			self.Active = false
			if self.OnStop then
				pcall(self.OnStop, self)
			end
			return false
		end
		if result == false then
			self.Active = false
			return false
		end
	end

	if self.Duration > 0 then
		task.delay(self.Duration, function()
			self:Stop()
		end)
	end
	return true
end

function Oddity:Stop(): boolean
	if not self.Active then return false end
	self.Active = false

	if self.OnStop then
		local ok, err = pcall(self.OnStop, self)
		if not ok then
			warn(`[oddity] {self.Kind} failed to stop: {err}`)
		end
	end
	for _, callback in self.Callbacks do
		callback(self)
	end
	table.clear(self.Callbacks)
	return true
end

function Oddity:Elapsed(): number
	return if self.Active then os.clock() - self.StartedAt else 0
end

function Oddity:Remaining(): number
	return if self.Active then math.max(self.Duration - self:Elapsed(), 0) else 0
end

return Oddity
