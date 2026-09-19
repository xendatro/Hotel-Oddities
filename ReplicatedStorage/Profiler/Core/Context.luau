local Context = {}
Context.__index = Context

function Context.new(player, options)
	return setmetatable({ Player = player, Options = options, Checks = {}, Events = {},
		Cleanups = {}, Cancelled = false, Started = os.clock(), State = {} }, Context)
end

-- Register undo work BEFORE mutating anything. Cleanup runs in reverse order on
-- success, cancellation, timeout, or failure. Keep it bounded and safe to repeat.
function Context:Defer(callback)
	table.insert(self.Cleanups, callback)
end

function Context:Check(name, passed, detail)
	table.insert(self.Checks, { name = name, passed = passed == true, detail = tostring(detail or "") })
end

function Context:Mark(name, detail)
	if #self.Events < 128 then
		table.insert(self.Events, { t = os.clock() - self.Started, name = name, detail = tostring(detail or "") })
	end
end

function Context:WaitFor(predicate, timeout, label)
	local deadline = os.clock() + timeout
	repeat
		assert(not self.Cancelled, "Cancelled")
		local value = predicate()
		if value then return value end
		task.wait(0.05)
	until os.clock() >= deadline
	error("Timed out: " .. (label or "condition"), 0)
end

function Context:Sleep(seconds)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		assert(not self.Cancelled, "Cancelled")
		task.wait(math.min(0.05, deadline - os.clock()))
	end
end

function Context:Cleanup()
	local errors = {}
	for index = #self.Cleanups, 1, -1 do
		local ok, err = pcall(self.Cleanups[index])
		if not ok then table.insert(errors, tostring(err)) end
	end
	table.clear(self.Cleanups)
	return errors
end

return Context
