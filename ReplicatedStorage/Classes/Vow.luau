export type Cancel = (...any) -> ()

export type VowFunction = (cancel: Cancel, ...any) -> ...any

export type VowState = "Ready" | "Active" | "Dead"

local Vow = {}
Vow.__index = Vow

export type Vow = typeof(setmetatable(
	{} :: {
		Function: VowFunction,
		MainThread: thread?,
		FunctionThread: thread?,
		State: VowState,
	},
	Vow
	))

function Vow.new(func: VowFunction): Vow
	local self = setmetatable({}, Vow)
	self.Function = func
	self.MainThread = nil
	self.FunctionThread = nil
	self.State = "Ready"
	return self
end

function Vow.Fire(self: Vow, ...: any): ...any
	if self.State ~= "Ready" then return end
	self.State = "Active"
	self.MainThread = coroutine.running()
	local t = table.pack(...)
	local v = nil
	local ok, err = true, nil
	local cancel = function(...)
		assert(coroutine.running() == self.FunctionThread, "cancel must be called on the function's own thread")
		local v = table.pack(...)
		self.State = "Ready"
		task.defer(function()
			if coroutine.status(self.MainThread) == "dead" then
				warn("originally running coroutine is dead")
				return
			end
			task.spawn(self.MainThread, table.unpack(v, 1, v.n))
		end)
		coroutine.yield()
	end
	self.FunctionThread = task.defer(function()
		ok, err = pcall(function()
			v = table.pack(self.Function(cancel, table.unpack(t, 1, t.n)))
		end)
		self.State = "Ready"
		task.defer(function()
			if coroutine.status(self.MainThread) == "dead" then
				warn("originally running coroutine is dead")
				return
			end
			if ok then
				task.spawn(self.MainThread, table.unpack(v, 1, v.n))
			else
				task.spawn(self.MainThread)
			end
		end)
		coroutine.yield()
	end)
	local y = table.pack(coroutine.yield(self.MainThread))
	task.cancel(self.FunctionThread)
	if not ok then
		error(err, 0)
	end
	return table.unpack(y, 1, y.n)
end

function Vow.Cancel(self: Vow, ...: any)
	if self.State ~= "Active" then return end
	assert(coroutine.running() ~= self.FunctionThread, "use the cancel closure inside the function, not Cancel()")
	self.State = "Ready"
	task.spawn(self.MainThread, ...)
end

function Vow.Destroy(self: Vow)
	if self.State == "Active" then
		assert(coroutine.running() ~= self.FunctionThread, "use the cancel closure inside the function, not Destroy()")
		self.State = "Dead"
		task.spawn(self.MainThread)
	else
		self.State = "Dead"
	end
end

return Vow
