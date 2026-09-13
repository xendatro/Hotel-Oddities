local Recorder = {}

local Runs: { [string]: any } = {}

local function statsOf(values: { number })
	if #values == 0 then return nil end

	local sum, low, high = 0, math.huge, -math.huge
	for _, value in values do
		sum += value
		low = math.min(low, value)
		high = math.max(high, value)
	end
	local mean = sum / #values

	local spread = 0
	for _, value in values do
		spread += (value - mean) ^ 2
	end

	local function round(n: number)
		return math.round(n * 10000) / 10000
	end
	return {
		n = #values,
		mean = round(mean),
		min = round(low),
		max = round(high),
		sd = round(math.sqrt(spread / #values)),
	}
end

local function collect(run, field: string, filter: ((any) -> boolean)?): { number }
	local values = {}
	for _, row in run.samples do
		if filter and not filter(row) then continue end
		local value = row[field]
		if type(value) == "number" then
			table.insert(values, value)
		end
	end
	return values
end

function Recorder.start(name: string, sampler: () -> any, interval: number?)
	Recorder.stop(name)

	local run = { samples = {}, running = true, errors = 0, lastError = nil, started = os.clock() }
	Runs[name] = run

	task.spawn(function()
		while run.running do
			local ok, row = pcall(sampler)
			if ok and type(row) == "table" then
				if row.t == nil then
					row.t = workspace:GetServerTimeNow()
				end
				table.insert(run.samples, row)
			else
				run.errors += 1
				run.lastError = if ok then "sampler returned " .. typeof(row) else tostring(row)
			end
			task.wait(interval or 0.25)
		end
	end)

	return run
end

function Recorder.stop(name: string)
	local run = Runs[name]
	if run then
		run.running = false
	end
	return run
end

function Recorder.stopAll()
	for _, run in Runs do
		run.running = false
	end
end

function Recorder.discard(name: string)
	Recorder.stop(name)
	Runs[name] = nil
end

function Recorder.list()
	local out = {}
	for name, run in Runs do
		table.insert(out, string.format("%s: %d samples, running=%s, errors=%d%s",
			name, #run.samples, tostring(run.running), run.errors,
			if run.lastError then " last=" .. run.lastError else ""))
	end
	return out
end

function Recorder.dump(name: string, filter: ((any) -> boolean)?)
	local run = Runs[name]
	if not run then return "no run named " .. name end

	local fields = {}
	for _, row in run.samples do
		for key, value in row do
			if type(value) == "number" then
				fields[key] = true
			end
		end
	end

	local out = { samples = #run.samples, errors = run.errors, lastError = run.lastError, fields = {} }
	for field in fields do
		out.fields[field] = statsOf(collect(run, field, filter))
	end
	return out
end

-- The assertion that matters: the same measurement with the effect present and absent.
function Recorder.compare(name: string, field: string, predicate: (any) -> boolean)
	local run = Runs[name]
	if not run then return "no run named " .. name end

	local matched, other = {}, {}
	for _, row in run.samples do
		local value = row[field]
		if type(value) ~= "number" then continue end
		table.insert(if predicate(row) then matched else other, value)
	end
	return { matched = statsOf(matched), other = statsOf(other) }
end

function Recorder.rows(name: string, format: (any) -> string, filter: ((any) -> boolean)?, limit: number?)
	local run = Runs[name]
	if not run then return { "no run named " .. name } end

	local out = {}
	local cap = limit or 40
	local kept = {}
	for _, row in run.samples do
		if filter and not filter(row) then continue end
		table.insert(kept, row)
	end

	local stride = math.max(math.floor(#kept / cap), 1)
	for index = 1, #kept, stride do
		local ok, line = pcall(format, kept[index])
		table.insert(out, if ok then line else "format error: " .. tostring(line))
	end
	return out
end

function Recorder.samples(name: string)
	local run = Runs[name]
	return if run then run.samples else nil
end

return Recorder
