local Wait = {}

-- Prefer this over a fixed sleep. Fixed sleeps either waste wall clock or land
-- after the window you wanted to observe has closed.
function Wait.For(predicate: () -> boolean, timeout: number?, interval: number?): (boolean, number)
	local started = os.clock()
	local deadline = started + (timeout or 30)
	while os.clock() < deadline do
		local ok, result = pcall(predicate)
		if ok and result then return true, os.clock() - started end
		task.wait(interval or 0.1)
	end
	return false, os.clock() - started
end

function Wait.Value(getter: () -> any, timeout: number?, interval: number?): (any, number)
	local value
	local found, elapsed = Wait.For(function()
		local ok, result = pcall(getter)
		if ok and result ~= nil then
			value = result
			return true
		end
		return false
	end, timeout, interval)
	return if found then value else nil, elapsed
end

function Wait.Child(parent: Instance, name: string, timeout: number?): Instance?
	local value = Wait.Value(function()
		return parent:FindFirstChild(name)
	end, timeout)
	return value
end

function Wait.Gone(instance: Instance, timeout: number?): (boolean, number)
	return Wait.For(function()
		return instance.Parent == nil
	end, timeout)
end

return Wait
