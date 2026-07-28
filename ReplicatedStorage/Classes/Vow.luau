--- @class Vow
--- A cancelable, blocking wrapper around a yielding function. `Fire` runs the function on a
--- worker thread, blocks the caller, and returns whatever it resolves with -- by returning, by
--- calling its `cancel` closure, or via an external `Cancel`. Reusable (re-fire after it
--- resolves); `Destroy` is terminal.

--- The closure passed to the wrapped function as its first argument. Calling it resolves the Vow
--- with the given values and freezes the function at the call site. Must be called on the
--- function's own thread.
export type Cancel = (...any) -> ()

--- The function a Vow wraps: receives `(cancel, ...firedArgs)` and resolves by returning values
--- (or by calling `cancel` with them).
export type VowFunction = (cancel: Cancel, ...any) -> ...any

--- `Ready` = idle/awaiting fire, `Active` = a firing is in flight, `Dead` = destroyed (terminal).
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

--- Wraps `func` in a new Vow. Does not run it; call `:Fire(...)`.
--- @param func VowFunction
--- @return Vow
function Vow.new(func: VowFunction): Vow
	local self = setmetatable({}, Vow)
	self.Function = func
	self.MainThread = nil
	self.FunctionThread = nil
	self.State = "Ready"
	return self
end

--- Runs the wrapped function on a worker thread and BLOCKS the caller until it resolves, then
--- returns the resolved values. No-op (returns nothing) unless the Vow is `Ready`.
--- @param ... any -- arguments forwarded to the wrapped function (after `cancel`)
--- @return ...any -- whatever the function resolved with
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

--- Resolves an in-flight firing from outside the wrapped function. No-op unless `Active`.
--- Must be called off the function's own thread (use the `cancel` closure inside the function).
--- @param ... any -- values the blocked `Fire` will return
function Vow.Cancel(self: Vow, ...: any)
	if self.State ~= "Active" then return end
	assert(coroutine.running() ~= self.FunctionThread, "use the cancel closure inside the function, not Cancel()")
	self.State = "Ready"
	task.spawn(self.MainThread, ...)
end

--- Permanently kills the Vow: resolves any in-flight firing (caller gets nothing) and marks it
--- `Dead` so future `Fire`s are rejected. Must be called off the function's own thread.
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
