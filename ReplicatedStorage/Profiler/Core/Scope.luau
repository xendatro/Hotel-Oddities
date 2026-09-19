local Statistics = require(script.Parent.Statistics)
local Settings = require(script.Parent.Parent.Config.Settings)
local Scope = {}
local current

-- Begin/End and Wrap measure elapsed wall time, including yields. They do NOT
-- claim CPU time. Do not monkeypatch live services: wrap at the definition/callsite.
function Scope.Start(prefixes)
	assert(not current, "A scope recording is already active")
	current = { scopes = {}, counters = {}, prefixes = prefixes or {}, started = os.clock(), dropped = 0 }
	return current
end

local function accepts(name)
	if not current or type(name) ~= "string" or #name > 120 then return false end
	if #current.prefixes == 0 then return true end
	for _, prefix in current.prefixes do
		if string.sub(name, 1, #prefix) == prefix then return true end
	end
	return false
end

function Scope.Begin(name)
	if not accepts(name) then return nil end
	local entry = current.scopes[name]
	if not entry then
		local count = 0
		for _ in current.scopes do count += 1 end
		if count >= Settings.MaxScopes then current.dropped += 1; return nil end
		entry = { durations = Statistics.New(Settings.MaxScopeSamples), errors = 0 }
		current.scopes[name] = entry
	end
	return { session = current, entry = entry, started = os.clock() }
end

function Scope.End(token, failed)
	if not token or token.ended then return end
	token.ended = true
	if token.session ~= current then return end
	Statistics.Add(token.entry.durations, (os.clock() - token.started) * 1000)
	if failed then token.entry.errors += 1 end
end

function Scope.Wrap(name, callback)
	return function(...)
		local token = Scope.Begin(name)
		if not token then return callback(...) end
		local result = table.pack(pcall(callback, ...))
		Scope.End(token, not result[1])
		if not result[1] then error(result[2], 0) end
		return table.unpack(result, 2, result.n)
	end
end

function Scope.Count(name, amount)
	if not accepts(name) or not Statistics.Finite(amount or 1) then return end
	if current.counters[name] == nil then
		local count = 0
		for _ in current.counters do count += 1 end
		if count >= Settings.MaxScopes then current.dropped += 1; return end
	end
	current.counters[name] = (current.counters[name] or 0) + (amount or 1)
end

function Scope.Stop(session)
	if current ~= session then return { scopes = {}, counters = {} } end
	current = nil
	local rows = {}
	for name, entry in session.scopes do
		local row = Statistics.Summary(entry.durations)
		row.name = name; row.errors = entry.errors; row.totalMs = entry.durations.sum
		table.insert(rows, row)
	end
	table.sort(rows, function(a,b) return a.totalMs > b.totalMs end)
	return { semantics = "elapsed wall milliseconds including yields; nested scopes overlap",
		scopes = rows, counters = session.counters, droppedNames = session.dropped }
end

return Scope
